import Foundation
import Testing
@testable import TenXApp

@MainActor
@Test func accessibilityAnnouncementSkipsAWindowlessApplication() {
    var postedMessages: [String] = []
    let announcer = AccessibilityAnnouncer(
        application: { nil },
        post: { _, message in postedMessages.append(message) })

    announcer.announce("Couldn’t open File.swift")

    #expect(postedMessages.isEmpty)
}

@MainActor
@Test func accessibilityAnnouncementUsesTheResolvedApplicationElement() {
    let application = NSObject()
    var postedElement: AnyObject?
    var postedMessage: String?
    let announcer = AccessibilityAnnouncer(
        application: { application },
        post: { element, message in
            postedElement = element as AnyObject
            postedMessage = message
        })

    announcer.announce("Couldn’t open File.swift")

    #expect(postedElement === application)
    #expect(postedMessage == "Couldn’t open File.swift")
}
