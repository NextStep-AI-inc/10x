enum WorkspaceSignalStatus: Equatable {
    case opening
    case ready
    case working
    case needsInput
    case retrying
    case compacting
    case refreshingContext
    case nearLimit
    case failed
    case responseStopped
    case backgroundWorking(Int)
    case workspaceReady
}

enum SessionCompactionSignalPhase: Equatable {
    case none
    case sweeping
    case refreshing
    case revealing(generation: UInt64, percent: Int)
}

struct WorkspaceSignalPresentation: Equatable {
    let status: WorkspaceSignalStatus
    let contextPercent: Int?
    private let isSession: Bool

    /// Clamp only the painted length; the displayed percentage remains the measured value.
    var contextFraction: Double? {
        contextPercent.map { min(max(Double($0) / 100, 0), 1) }
    }

    var contextLabel: String? {
        guard isSession else { return nil }
        guard let contextPercent else { return "Context —" }
        return "Context \(contextPercent)%"
    }

    var label: String {
        switch status {
        case .opening: "Opening"
        case .ready: "Ready"
        case .working: "Working"
        case .needsInput: "Needs input"
        case .retrying: "Retrying"
        case .compacting: "Compacting"
        case .refreshingContext: "Refreshing context"
        case .nearLimit: "Near limit"
        case .failed: "Failed"
        case .responseStopped: "Response stopped"
        case .backgroundWorking(let count): "\(count) working"
        case .workspaceReady: "Workspace ready"
        }
    }

    var accessibilityLabel: String {
        guard isSession else { return label }
        guard let contextPercent else { return "\(label), context unavailable" }
        return "\(label), context \(contextPercent) percent"
    }

    static func session(
        runtimeState: SessionRuntimeState,
        contextPercent: Int?,
        hasPendingUserInput: Bool,
        isRetrying: Bool,
        hasTerminalRetryFailure: Bool,
        compactionPhase: SessionCompactionSignalPhase,
        isRecoveryPresented: Bool,
        isIntentionallyStopped: Bool
    ) -> Self {
        if isIntentionallyStopped {
            return Self(status: .responseStopped, contextPercent: contextPercent, isSession: true)
        }
        if runtimeState == .loading {
            return Self(status: .opening, contextPercent: nil, isSession: true)
        }
        if hasTerminalRetryFailure || isRecoveryPresented {
            return Self(status: .failed, contextPercent: contextPercent, isSession: true)
        }
        switch runtimeState {
        case .failed, .stopped:
            return Self(status: .failed, contextPercent: contextPercent, isSession: true)
        case .loading, .idle, .streaming:
            break
        }
        if hasPendingUserInput {
            return Self(status: .needsInput, contextPercent: contextPercent, isSession: true)
        }
        if isRetrying {
            return Self(status: .retrying, contextPercent: contextPercent, isSession: true)
        }
        switch compactionPhase {
        case .sweeping:
            return Self(status: .compacting, contextPercent: contextPercent, isSession: true)
        case .refreshing:
            return Self(status: .refreshingContext, contextPercent: contextPercent, isSession: true)
        case .revealing:
            break
        case .none:
            if let contextPercent, contextPercent >= 95 {
                return Self(status: .nearLimit, contextPercent: contextPercent, isSession: true)
            }
        }
        return Self(
            status: runtimeState == .streaming ? .working : .ready,
            contextPercent: contextPercent,
            isSession: true)
    }

    static func workspace(generatingCount: Int) -> Self {
        Self(
            status: generatingCount > 0 ? .backgroundWorking(generatingCount) : .workspaceReady,
            contextPercent: nil,
            isSession: false)
    }
}
