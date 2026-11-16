import Foundation
import XCTest
@testable import Curio

/// Scan rules shared with the desktop Media library, using Curio's iOS Documents root.
final class MediaLibraryTests: XCTestCase {
    func testKindComesFromCaseInsensitiveExtension() {
        for ext in ["png", "JPG", "jpeg", "gif", "webp", "heic", "heif", "svg", "bmp", "tiff"] {
            XCTAssertEqual(MediaItem.Kind(fileURL: URL(fileURLWithPath: "photo.\(ext)")), .image)
        }
        for ext in ["mp4", "MOV", "m4v", "webm", "mkv", "avi"] {
            XCTAssertEqual(MediaItem.Kind(fileURL: URL(fileURLWithPath: "clip.\(ext)")), .video)
        }
        XCTAssertNil(MediaItem.Kind(fileURL: URL(fileURLWithPath: "notes.txt")))
        XCTAssertNil(MediaItem.Kind(fileURL: URL(fileURLWithPath: "README")))
    }

    func testFindsFilesNewestFirstAndLabelsDownloads() throws {
        let root = try directory()
        try write("screenshot.png", in: root, age: 10)
        try write("Trips/2026/beach.jpg", in: root, age: 20)
        try write("Downloads/clip.mp4", in: root, age: 30)
        try write("Downloads/Trip/loose.gif", in: root, age: 40)
        try write("DownloadsArchive/old.jpg", in: root, age: 50)
        try write("notes.txt", in: root, age: 5)

        let items = MediaLibrary.scanFiles(in: root)
        XCTAssertEqual(items.map(\.name), ["screenshot.png", "beach.jpg", "clip.mp4", "loose.gif", "old.jpg"])
        XCTAssertEqual(items.map(\.folder), ["Documents", "Documents", "Downloads", "Downloads", "Documents"])
        XCTAssertEqual(items.first { $0.name == "clip.mp4" }?.kind, .video)
    }

    func testSkipsHiddenFilesPackagesBuildOutputSymlinksAndEmptyFiles() throws {
        let root = try directory()
        let keep = try write("keep.png", in: root)
        try write(".hidden.png", in: root)
        try write(".cache/inside.png", in: root)
        try write("Tool.APP/Contents/icon.png", in: root)
        try write("Pictures/Photos Library.photoslibrary/originals/a.heic", in: root)
        try write("site/node_modules/pkg/logo.png", in: root)
        try write("game/target/debug/sprite.png", in: root)
        try write("empty.png", in: root, contents: Data())
        let outside = try directory()
        try write("external.jpg", in: outside)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "link.png"), withDestinationURL: keep)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "linked-folder"), withDestinationURL: outside)

        XCTAssertEqual(MediaLibrary.scanFiles(in: root).map(\.name), ["keep.png"])
    }

    func testRespectsDepthEntryAndFileLimits() throws {
        let root = try directory()
        try write("a.png", in: root, age: 1)
        try write("one/b.png", in: root, age: 2)
        try write("one/two/c.png", in: root, age: 3)

        let shallow = MediaLibrary.ScanLimits(depth: 1)
        XCTAssertEqual(MediaLibrary.scanFiles(in: root, limits: shallow).map(\.name), ["a.png", "b.png"])
        let few = MediaLibrary.ScanLimits(files: 2)
        XCTAssertEqual(MediaLibrary.scanFiles(in: root, limits: few).map(\.name), ["a.png", "b.png"])
        let bounded = MediaLibrary.ScanLimits(entries: 1)
        XCTAssertLessThan(MediaLibrary.scanFiles(in: root, limits: bounded).count, 2)
    }

    func testAddsExtraDownloadsOnceAndSkipsInvalidPaths() throws {
        let root = try directory()
        let elsewhere = try directory()
        let photo = try write("Downloads/photo.jpg", in: root, age: 1)
        let video = try write("video.webm", in: elsewhere, age: 2)
        let missing = elsewhere.appending(path: "missing.png")
        let link = elsewhere.appending(path: "link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: photo)

        let items = MediaLibrary.scanFiles(in: root, extraDownloads: [photo, video, video, missing, link])
        XCTAssertEqual(items.map(\.name), ["photo.jpg", "video.webm"])
        XCTAssertEqual(items.map(\.folder), ["Downloads", "Downloads"])
    }

    func testSkipsUnreadableRootButStillChecksDownloads() throws {
        let root = try directory()
        let missing = root.appending(path: "missing")
        XCTAssertTrue(MediaLibrary.scanFiles(in: missing).isEmpty)
        let photo = try write("photo.jpg", in: root)
        XCTAssertEqual(MediaLibrary.scanFiles(in: missing, extraDownloads: [photo]).map(\.name), ["photo.jpg"])
    }

    func testSearchMatchesEveryWordAcrossNameAndFolder() throws {
        let root = try directory()
        try write("Downloads/Résumé.PNG", in: root)
        let item = try XCTUnwrap(MediaLibrary.scanFiles(in: root).first)
        XCTAssertTrue(item.matches(["downloads", "resume", "png"]))
        XCTAssertFalse(item.matches(["documents", "png"]))
        XCTAssertFalse(item.matches(["downloads", "video"]))
    }

    private func directory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    @discardableResult
    private func write(_ path: String, in directory: URL, age: TimeInterval = 0, contents: Data = Data([0])) throws -> URL {
        let url = directory.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 - age)],
                                              ofItemAtPath: url.path(percentEncoded: false))
        return url
    }
}
