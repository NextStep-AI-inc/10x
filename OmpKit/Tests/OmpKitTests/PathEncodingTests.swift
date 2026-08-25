import Testing
import Foundation
@testable import OmpKit

@Test func encodesHomeRelative() {
    #expect(SessionPathEncoding.bucketName(
        forCwd: "/Users/me/CS Projects/foo", home: "/Users/me", tmp: "/tmp/t")
        == "-CS Projects-foo")
}

@Test func encodesHomeItself() {
    #expect(SessionPathEncoding.bucketName(
        forCwd: "/Users/me", home: "/Users/me", tmp: "/tmp/t") == "-")
}

@Test func encodesTmp() {
    #expect(SessionPathEncoding.bucketName(
        forCwd: "/tmp/t/x", home: "/Users/me", tmp: "/tmp/t") == "-tmp-x")
}

@Test func encodesTmpRootItself() {
    #expect(SessionPathEncoding.bucketName(
        forCwd: "/tmp/t", home: "/Users/me", tmp: "/tmp/t") == "-tmp")
}

@Test func encodesAbsolute() {
    #expect(SessionPathEncoding.bucketName(
        forCwd: "/Volumes/X/repo", home: "/Users/me", tmp: "/tmp/t")
        == "--Volumes-X-repo--")
}

@Test func siblingOfHomeIsNotHomeRelative() {
    // "/Users/meow" must not be treated as living under "/Users/me".
    #expect(SessionPathEncoding.bucketName(
        forCwd: "/Users/meow/x", home: "/Users/me", tmp: "/tmp/t")
        == "--Users-meow-x--")
}

@Test func nestedHomePathKeepsEveryComponent() {
    #expect(SessionPathEncoding.bucketName(
        forCwd: "/Users/me/a/b/c", home: "/Users/me", tmp: "/tmp/t") == "-a-b-c")
}
