import Foundation

/// Parsed form of a modelRoles entry: "provider/model-id" with optional
/// ":effort" suffix. Model ids may contain "/" (e.g. openrouter/google/gemini-x);
/// the provider is the first path component. A ":" suffix only counts as effort
/// when it is a known effort name — otherwise it belongs to the model id.
struct ModelRoleValue: Equatable {
    var provider: String
    var modelID: String
    var effort: String?

    static let efforts = ["minimal", "low", "medium", "high", "xhigh", "max"]

    init(provider: String, modelID: String, effort: String? = nil) {
        self.provider = provider
        self.modelID = modelID
        self.effort = effort
    }

    init?(raw: String) {
        guard let slash = raw.firstIndex(of: "/") else { return nil }
        let provider = String(raw[raw.startIndex..<slash])
        var rest = String(raw[raw.index(after: slash)...])
        var effort: String? = nil
        if let colon = rest.lastIndex(of: ":") {
            let suffix = String(rest[rest.index(after: colon)...])
            if Self.efforts.contains(suffix) {
                effort = suffix
                rest = String(rest[rest.startIndex..<colon])
            }
        }
        guard !provider.isEmpty, !rest.isEmpty else { return nil }
        self.provider = provider
        self.modelID = rest
        self.effort = effort
    }

    var raw: String {
        "\(provider)/\(modelID)" + (effort.map { ":\($0)" } ?? "")
    }
}
