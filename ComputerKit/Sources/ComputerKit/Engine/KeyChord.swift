import CoreGraphics
import Foundation

/// Parses "cmd+s", "ctrl+shift+tab", "return" into flags + virtual key code.
enum KeyChord {
    static func parse(_ chord: String) throws -> (flags: CGEventFlags, keyCode: CGKeyCode) {
        var flags: CGEventFlags = []
        var parts = chord.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.popLast() else { throw ComputerError("invalid_chord: \(chord)") }
        for modifier in parts {
            switch modifier {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: throw ComputerError("invalid_modifier: \(modifier)")
            }
        }
        guard let keyCode = keyCodes[key] else { throw ComputerError("invalid_key: \(key)") }
        return (flags, keyCode)
    }

    // ponytail: letters, digits, and the common named keys only — enough for
    // agent workflows. Ceiling: no F-keys/arrows beyond the listed ones.
    // Upgrade path: full UCKeyTranslate table.
    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "tab": 48, "space": 49, "delete": 51, "escape": 53, "return": 36,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}
