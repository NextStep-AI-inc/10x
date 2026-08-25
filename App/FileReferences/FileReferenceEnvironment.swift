import SwiftUI

struct OpenIDEPreferencesAction: Sendable {
    private let action: @MainActor @Sendable () -> Void

    init(_ action: @escaping @MainActor @Sendable () -> Void = {}) {
        self.action = action
    }

    @MainActor
    func callAsFunction() {
        action()
    }
}

private struct FileOpenServiceKey: EnvironmentKey {
    static let defaultValue = FileOpenService.live
}

private struct FileReferenceBaseURLKey: EnvironmentKey {
    static let defaultValue: URL? = nil
}

private struct OpenIDEPreferencesKey: EnvironmentKey {
    static let defaultValue = OpenIDEPreferencesAction()
}

extension EnvironmentValues {
    var fileOpenService: FileOpenService {
        get { self[FileOpenServiceKey.self] }
        set { self[FileOpenServiceKey.self] = newValue }
    }

    var fileReferenceBaseURL: URL? {
        get { self[FileReferenceBaseURLKey.self] }
        set { self[FileReferenceBaseURLKey.self] = newValue }
    }

    var openIDEPreferences: OpenIDEPreferencesAction {
        get { self[OpenIDEPreferencesKey.self] }
        set { self[OpenIDEPreferencesKey.self] = newValue }
    }
}
