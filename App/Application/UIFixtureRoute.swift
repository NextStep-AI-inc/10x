import Foundation

enum UIFixtureRoute: String, CaseIterable, Sendable {
    case mapPlanning = "map-planning"
    case mapImplementing = "map-implementing"
    case mapDense = "map-dense"
    case mapEmpty = "map-empty"
    case mapInvalid = "map-invalid"
    case settingsMap = "settings-map"
    case mapWriterLive = "map-writer-live"
    case flyerFitting = "flyer-fitting"
    case flyerOverflow = "flyer-overflow"
    case flyerStack = "flyer-stack"
    case flyerRecovery = "flyer-recovery"

    static let environmentKey = "TENX_UI_FIXTURE"

    var isFlyer: Bool {
        switch self {
        case .flyerFitting, .flyerOverflow, .flyerStack, .flyerRecovery:
            true
        default:
            false
        }
    }

    var usesLiveMapWriter: Bool { self == .mapWriterLive }

    static func resolve(environment: [String: String]) throws -> UIFixtureRoute? {
        guard let value = environment[environmentKey], !value.isEmpty else { return nil }
        guard let route = UIFixtureRoute(rawValue: value) else {
            throw UIFixtureRouteError.unsupported(value)
        }
        return route
    }
}

enum UIFixtureRouteError: LocalizedError {
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let value):
            "Unsupported TENX_UI_FIXTURE value: \(value)"
        }
    }
}
