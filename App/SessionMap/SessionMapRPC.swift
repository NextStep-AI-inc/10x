import Foundation
import OmpKit

enum SessionMapRPCError: Error, Equatable {
    case deadlineExceeded
    case streamEnded
    case provider(String)
    case missingFinalOutput
}

struct SessionMapRPC: Sendable {
    private actor DeadlineState {
        private(set) var hasExpired = false
        func expire() { hasExpired = true }
    }

    typealias ClientFactory = @Sendable (RpcClientConfiguration) -> RpcClient

    private let executableURL: URL
    private let projectURL: URL
    private let environment: [String: String]
    private let deadline: Duration
    private let clientFactory: ClientFactory

    init(
        executableURL: URL,
        projectURL: URL,
        environment: [String: String] = OmpProcessEnvironment.resolved(),
        deadline: Duration = .seconds(90),
        clientFactory: @escaping ClientFactory = { RpcClient(configuration: $0) }
    ) {
        self.executableURL = executableURL
        self.projectURL = projectURL
        self.environment = environment
        self.deadline = deadline
        self.clientFactory = clientFactory
    }

    func complete(
        prompt: String,
        images: [PromptImage],
        model: SessionMapResolvedModel
    ) async throws -> String {
        var configuration = RpcClientConfiguration()
        configuration.executable = executableURL.path
        configuration.cwd = projectURL
        configuration.noSession = true
        configuration.provider = model.provider
        configuration.model = model.modelID
        configuration.thinking = model.effort
        configuration.extraArguments = [
            "--no-tools", "--no-extensions", "--no-skills", "--no-rules",
        ]
        configuration.environment = environment
        configuration.startupTimeout = .seconds(30)
        configuration.requestTimeout = .seconds(90)

        let client = clientFactory(configuration)
        return try await withTaskCancellationHandler {
            do {
                let result = try await raceLifecycle(
                    client: client, prompt: prompt, images: images)
                await client.shutdown()
                return result
            } catch {
                await client.shutdown()
                throw error
            }
        } onCancel: {
            Task { await client.shutdown() }
        }
    }

    private func raceLifecycle(
        client: RpcClient,
        prompt: String,
        images: [PromptImage]
    ) async throws -> String {
        let deadlineState = DeadlineState()
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let output = Task { try await Self.terminalOutput(from: client.events) }
                do {
                    try await client.start()
                    _ = try await client.send(.prompt(
                        message: prompt, images: images, streamingBehavior: nil))
                    return try await output.value
                } catch {
                    output.cancel()
                    if await deadlineState.hasExpired {
                        throw SessionMapRPCError.deadlineExceeded
                    }
                    throw error
                }
            }
            group.addTask {
                try await Task.sleep(for: deadline)
                await deadlineState.expire()
                await client.shutdown()
                throw SessionMapRPCError.deadlineExceeded
            }
            guard let result = try await group.next() else {
                throw SessionMapRPCError.streamEnded
            }
            group.cancelAll()
            return result
        }
    }

    private static func terminalOutput(from events: AsyncStream<RpcFrame>) async throws -> String {
        var finalOutput: String?
        for await frame in events {
            try Task.checkCancellation()
            guard case .event(let type, let payload) = frame else { continue }
            if type == "message_end",
               payload["message"]?["role"]?.stringValue == "assistant",
               let text = assistantText(payload["message"])
            {
                finalOutput = text
            }
            if ["agent_error", "provider_error", "error"].contains(type) {
                let detail = payload["message"]?.stringValue
                    ?? payload["error"]?.stringValue
                    ?? "The map writer failed."
                throw SessionMapRPCError.provider(String(detail.prefix(400)))
            }
            let isTerminal = type == "turn_end"
                || type == "prompt_result"
                || (type == "agent_end" && payload["isTerminal"]?.boolValue == true)
            if isTerminal {
                guard let finalOutput, !finalOutput.isEmpty else {
                    throw SessionMapRPCError.missingFinalOutput
                }
                return finalOutput
            }
        }
        throw SessionMapRPCError.streamEnded
    }

    private static func assistantText(_ message: JSONValue?) -> String? {
        message?["content"]?.arrayValue?
            .compactMap { part in
                guard part["type"]?.stringValue == "text" else { return nil }
                return part["text"]?.stringValue
            }
            .joined()
    }
}
