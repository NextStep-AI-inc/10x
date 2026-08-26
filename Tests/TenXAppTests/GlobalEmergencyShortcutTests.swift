import Testing
@testable import TenXApp

@MainActor
@Test func emergencyShortcutRegistersOnlyWhileComputerUseIsEnabled() async throws {
    let registrar = FakeHotKeyRegistrar()
    let shortcut = GlobalEmergencyShortcut(registrar: registrar)
    var stopCount = 0

    shortcut.update(phase: .off) { stopCount += 1 }
    #expect(registrar.registrations().isEmpty)

    shortcut.update(phase: .ready) { stopCount += 1 }
    #expect(registrar.registrations() == [
        HotKeyRegistration(
            keyCode: GlobalEmergencyShortcut.escapeKeyCode,
            modifiers: GlobalEmergencyShortcut.requiredModifiers),
    ])

    registrar.fire()
    await Task.yield()
    #expect(stopCount == 1)

    shortcut.update(phase: .off) { stopCount += 1 }
    #expect(registrar.unregisteredTokens() == [GlobalHotKeyToken(id: 1)])
}

private struct HotKeyRegistration: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
}

@MainActor
private final class FakeHotKeyRegistrar: GlobalHotKeyRegistering {
    private var nextID: UInt32 = 1
    private var registrationValues: [HotKeyRegistration] = []
    private var unregisterValues: [GlobalHotKeyToken] = []
    private var handler: (@Sendable () -> Void)?

    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        handler: @escaping @Sendable () -> Void
    ) throws -> GlobalHotKeyToken {
        registrationValues.append(HotKeyRegistration(keyCode: keyCode, modifiers: modifiers))
        self.handler = handler
        defer { nextID += 1 }
        return GlobalHotKeyToken(id: nextID)
    }

    func unregister(_ token: GlobalHotKeyToken) {
        unregisterValues.append(token)
        handler = nil
    }

    func registrations() -> [HotKeyRegistration] {
        registrationValues
    }

    func unregisteredTokens() -> [GlobalHotKeyToken] {
        unregisterValues
    }

    func fire() {
        handler?()
    }
}
