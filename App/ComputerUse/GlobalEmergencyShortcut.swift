import Carbon
import Foundation

struct GlobalHotKeyToken: Sendable, Equatable {
    let id: UInt32
}

@MainActor
protocol GlobalHotKeyRegistering: AnyObject {
    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        handler: @escaping @Sendable () -> Void
    ) throws -> GlobalHotKeyToken
    func unregister(_ token: GlobalHotKeyToken)
}

@MainActor
final class GlobalEmergencyShortcut {
    static let escapeKeyCode: UInt32 = 53
    static let requiredModifiers = UInt32(controlKey | optionKey | cmdKey)

    private let registrar: any GlobalHotKeyRegistering
    private var token: GlobalHotKeyToken?

    init(registrar: any GlobalHotKeyRegistering = CarbonGlobalHotKeyRegistrar()) {
        self.registrar = registrar
    }

    func update(isActive: Bool, onStop: @escaping @MainActor @Sendable () -> Void) {
        guard isActive else {
            if let token { registrar.unregister(token) }
            token = nil
            return
        }
        guard token == nil else { return }
        token = try? registrar.register(
            keyCode: Self.escapeKeyCode,
            modifiers: Self.requiredModifiers)
        {
            Task { @MainActor in onStop() }
        }
    }
}

@MainActor
private final class CarbonGlobalHotKeyRegistrar: GlobalHotKeyRegistering {
    private static let signature: OSType = 0x31305845 // 10XE
    private var nextID: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var activeToken: GlobalHotKeyToken?
    private var handler: (@Sendable () -> Void)?

    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        handler: @escaping @Sendable () -> Void
    ) throws -> GlobalHotKeyToken {
        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                    guard let event, let userData else { return noErr }
                    let registrar = Unmanaged<CarbonGlobalHotKeyRegistrar>
                        .fromOpaque(userData)
                        .takeUnretainedValue()
                    var hotKeyID = EventHotKeyID()
                    let readStatus = GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID)
                    guard readStatus == noErr else { return readStatus }
                    Task { @MainActor in registrar.fire(id: hotKeyID.id) }
                    return noErr
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef)
            guard status == noErr else { throw GlobalHotKeyError.registrationFailed(status) }
        }

        let token = GlobalHotKeyToken(id: nextID)
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: token.id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef)
        guard status == noErr else { throw GlobalHotKeyError.registrationFailed(status) }
        activeToken = token
        self.handler = handler
        return token
    }

    func unregister(_ token: GlobalHotKeyToken) {
        guard activeToken == token else { return }
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        activeToken = nil
        handler = nil
    }

    private func fire(id: UInt32) {
        guard activeToken?.id == id else { return }
        handler?()
    }
}

private enum GlobalHotKeyError: Error {
    case registrationFailed(OSStatus)
}
