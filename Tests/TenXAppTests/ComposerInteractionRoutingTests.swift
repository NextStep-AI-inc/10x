import OmpKit
import SwiftUI
import Testing
@testable import TenXApp

@Test func composerReturnRoutingRecognizesOnlyConfiguredShortcuts() {
    #expect(ComposerReturnRouting.shortcut(for: []) == .enter)
    #expect(ComposerReturnRouting.shortcut(for: [.command]) == .commandEnter)
    #expect(ComposerReturnRouting.shortcut(for: [.shift]) == .shiftEnter)
    #expect(ComposerReturnRouting.shortcut(for: [.option]) == nil)
    #expect(ComposerReturnRouting.shortcut(for: [.control]) == nil)
}

@Test func primaryAndAlternateResolveAgainstTheCurrentStreamingBehavior() {
    #expect(ComposerReturnRouting.behavior(for: .primary, primary: .steer) == .steer)
    #expect(ComposerReturnRouting.behavior(for: .alternate, primary: .steer) == .followUp)
    #expect(ComposerReturnRouting.behavior(for: .primary, primary: .followUp) == .followUp)
    #expect(ComposerReturnRouting.behavior(for: .alternate, primary: .followUp) == .steer)
    #expect(ComposerReturnRouting.behavior(for: .newline, primary: .steer) == nil)
}
