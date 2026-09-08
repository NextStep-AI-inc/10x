import Foundation

struct EnumPresentation: Equatable {
    let options: [SettingOption]
    let currentValue: String
    /// Non-nil when the current value is not one of the curated options.
    let customValue: String?

    init(options: [SettingOption], currentValue: String) {
        self.options = options
        self.currentValue = currentValue
        self.customValue = currentValue.isEmpty || options.contains { $0.value == currentValue }
            ? nil : currentValue
    }

    func displayText(for value: String) -> String {
        options.first { $0.value == value }?.label ?? value
    }
}
