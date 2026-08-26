import Foundation

struct ResolvedFileReference: Equatable {
    let originalPath: String
    let line: Int?
    let url: URL?
    let exists: Bool

    var originalReference: String {
        originalPath + (line.map { ":\($0)" } ?? "")
    }

    var compactLabel: String {
        URL(filePath: originalPath).lastPathComponent + (line.map { ":\($0)" } ?? "")
    }

    var fullPathLabel: String {
        (url?.path ?? originalPath) + (line.map { ":\($0)" } ?? "")
    }
}

struct FileReferenceResolver {
    private let fileExists: (String) -> Bool

    init(fileExists: @escaping (String) -> Bool = FileManager.default.fileExists(atPath:)) {
        self.fileExists = fileExists
    }

    func resolve(path: String, line: Int?, relativeTo baseURL: URL?) -> ResolvedFileReference {
        let url: URL?
        if path.hasPrefix("/") {
            url = URL(filePath: path).standardizedFileURL
        } else if path == "~" || path.hasPrefix("~/") {
            url = URL(filePath: NSString(string: path).expandingTildeInPath).standardizedFileURL
        } else if let baseURL {
            url = baseURL.appending(path: path).standardizedFileURL
        } else {
            url = nil
        }
        return ResolvedFileReference(
            originalPath: path,
            line: line,
            url: url,
            exists: url.map { fileExists($0.path) } ?? false)
    }
}
