import Foundation
import OmpKit

actor SessionTimelineLoader {
    func load(path: String) throws -> TranscriptHistory? {
        let url = URL(filePath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let file = try SessionFileParser.parse(data: Data(contentsOf: url))
        return TranscriptHistoryMapper.map(
            header: file.header,
            path: SessionTree.activePath(of: file))
    }
}
