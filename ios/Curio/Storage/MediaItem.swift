import Foundation
import Photos

nonisolated struct MediaItem: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case file(URL)
        case photo(PHAsset)
    }

    enum Kind: Hashable, Sendable {
        case image, video

        init?(fileURL: URL) {
            switch fileURL.pathExtension.lowercased() {
            case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "svg", "bmp", "tiff":
                self = .image
            case "mp4", "mov", "m4v", "webm", "mkv", "avi":
                self = .video
            default:
                return nil
            }
        }
    }

    let source: Source
    let name: String
    let folder: String
    let kind: Kind
    let date: Date
    let modificationDate: Date?
    let fileSize: Int?

    func matches(_ words: [Substring], photoName: String? = nil) -> Bool {
        let dateText = isFromPhotos && date != .distantPast ? date.formatted(date: .abbreviated, time: .omitted) : nil
        return words.allSatisfy { word in
            name.localizedStandardContains(word) || folder.localizedStandardContains(word)
                || photoName?.localizedStandardContains(word) == true || dateText?.localizedStandardContains(word) == true
        }
    }

    var isFromPhotos: Bool {
        if case .photo = source { return true }
        return false
    }

    static func newestFirst(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.name < rhs.name
    }
}
