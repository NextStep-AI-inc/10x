import AppKit
import SwiftUI

struct AccessibilityAnnouncer {
    private let application: @MainActor () -> Any?
    private let post: @MainActor (Any, String) -> Void

    init(
        application: @escaping @MainActor () -> Any?,
        post: @escaping @MainActor (Any, String) -> Void
    ) {
        self.application = application
        self.post = post
    }

    @MainActor
    func announce(_ message: String) {
        guard let application = application() else { return }
        post(application, message)
    }

    static let live = AccessibilityAnnouncer(
        application: { NSApp },
        post: { application, message in
            NSAccessibility.post(
                element: application,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: message,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ])
        })
}

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

private struct AccessibilityAnnouncerKey: EnvironmentKey {
    static let defaultValue = AccessibilityAnnouncer.live
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

    var accessibilityAnnouncer: AccessibilityAnnouncer {
        get { self[AccessibilityAnnouncerKey.self] }
        set { self[AccessibilityAnnouncerKey.self] = newValue }
    }
}
