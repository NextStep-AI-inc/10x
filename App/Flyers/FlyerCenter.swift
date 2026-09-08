import Foundation
import Observation

@MainActor
@Observable
final class FlyerCenter {
    private var flyers: [Flyer] = []

    func post(_ flyer: Flyer) {
        if let index = flyers.firstIndex(where: { $0.key == flyer.key }) {
            flyers[index] = flyer
        } else {
            flyers.append(flyer)
        }
    }

    func remove(_ key: Flyer.Key) {
        flyers.removeAll { $0.key == key }
    }

    func removeSession(_ key: String) {
        flyers.removeAll { $0.scope == .session(key) }
    }

    func visible(sessionKey: String?, at date: Date) -> [Flyer] {
        let matching = flyers.filter { flyer in
            let isUnexpired = flyer.expiresAt.map { $0 > date } ?? true
            guard isUnexpired else { return false }

            switch flyer.scope {
            case .global:
                return true
            case let .session(key):
                return key == sessionKey
            }
        }
        return Array(matching.suffix(3))
    }

    func expire(at date: Date) {
        flyers.removeAll { flyer in
            flyer.expiresAt.map { $0 <= date } ?? false
        }
    }
}
