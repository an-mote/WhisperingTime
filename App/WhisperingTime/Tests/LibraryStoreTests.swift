import XCTest
import AppKit
import AVFoundation
@testable import WhisperingTime

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() async throws {
        for url in temporaryURLs { try? FileManager.default.removeItem(at: url) }
        temporaryURLs = []
        try await super.tearDown()
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WhisperingTimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLs.append(url)
        return url
    }

    private func makeImage(in directory: URL) throws -> URL {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<8 { for y in 0..<8 { bitmap.setColor(.systemBlue, atX: x, y: y) } }
        let url = directory.appendingPathComponent("中文照片.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    private func makeAudio(in directory: URL) throws -> URL {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
        buffer.frameLength = 1_600
        for index in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][index] = sin(Float(index) * 0.1) * 0.05 }
        let url = directory.appendingPathComponent("原声.wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    func testChineseRoundTripWithAllContentAndAttachments() async throws {
        let directory = try temporaryDirectory()
        let source = try temporaryDirectory()
        let store = LibraryStore(rootURL: directory)
        let parent = try store.createCategory(name: "人生", parentID: nil)
        let leaf = try store.createCategory(name: "散步与家常", parentID: parent)
        let image = try await store.importAttachment(from: makeImage(in: source), kind: .image)
        var audio = try await store.importAttachment(from: makeAudio(in: source), kind: .audio)
        audio.transcript = "这是中文原声的转写，可以继续修改。"
        audio.transcriptionNote = "本机转写"
        let scales = [ImprintScale(name: "步行", kind: .number, value: "2.5", unit: "公里"), ImprintScale(name: "心情", kind: .choice, value: "轻松", options: ["轻松", "平静"]), ImprintScale(name: "天气", kind: .text, value: "有风")]
        var record = Imprint(categoryID: leaf, occurredAt: Date(timeIntervalSince1970: 1_792_000_000), body: "今天在河边走了一会儿。\n第二行中文与 🌿。", attachments: [image, audio], scales: scales)
        try store.save(record)
        XCTAssertNil(store.imprints.first?.title)
        record.title = "  后来补上的标题  "
        record.body += "\n第三行。"
        record.scales[0].value = "3.5"
        try store.save(record)
        let committed = store.snapshot
        try FileManager.default.removeItem(at: source)
        let reopened = LibraryStore(rootURL: directory)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.categories, committed.categories)
        XCTAssertEqual(reopened.imprints.map(\.body), committed.imprints.map(\.body))
        XCTAssertEqual(reopened.imprints.first?.title, "后来补上的标题")
        XCTAssertEqual(try XCTUnwrap(reopened.imprints.first?.occurredAt).timeIntervalSince1970, record.occurredAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(reopened.imprints.first?.scales, record.scales)
        XCTAssertEqual(reopened.imprints.first?.attachments, [image, audio])
        for attachment in reopened.imprints[0].attachments {
            XCTAssertTrue(FileManager.default.fileExists(atPath: reopened.mediaURL(for: attachment).path))
            XCTAssertTrue(reopened.mediaURL(for: attachment).path.hasPrefix(directory.path + "/media/"))
        }
        XCTAssertEqual(reopened.categoryPath(leaf), "人生 / 散步与家常")
    }

    func testTreeDescendantsCycleAndDeleteReparentPreserveRecords() throws {
        let store = LibraryStore(rootURL: try temporaryDirectory())
        let life = try store.createCategory(name: "人生", parentID: nil)
        let home = try store.createCategory(name: "家庭生活", parentID: life)
        let personal = try store.createCategory(name: "个人生活", parentID: home)
        let food = try store.createCategory(name: "饮食", parentID: personal)
        let work = try store.createCategory(name: "职场", parentID: life)
        let oldest = Imprint(categoryID: food, occurredAt: Date(timeIntervalSince1970: 10), body: "晚餐")
        let newest = Imprint(categoryID: work, occurredAt: Date(timeIntervalSince1970: 30), body: "工作片段")
        let middle = Imprint(categoryID: personal, occurredAt: Date(timeIntervalSince1970: 20), body: "个人生活")
        let loose = Imprint(body: "先留下来，不分类")
        for record in [oldest, newest, middle, loose] { try store.save(record) }
        XCTAssertEqual(store.records(in: .category(home)).map(\.id), [middle.id, oldest.id])
        XCTAssertEqual(store.records(in: .category(life)).map(\.id), [newest.id, middle.id, oldest.id])
        XCTAssertEqual(store.records(in: .unclassified).map(\.id), [loose.id])
        let beforeCycle = store.snapshot
        XCTAssertThrowsError(try store.moveCategory(life, parentID: food))
        XCTAssertThrowsError(try store.moveCategory(home, parentID: home))
        XCTAssertEqual(store.snapshot, beforeCycle)
        try store.renameCategory(food, name: "  饮食日常  ")
        XCTAssertTrue(store.categoryPath(food).hasSuffix("饮食日常"))
        try store.deleteCategory(personal)
        XCTAssertEqual(store.categories.first(where: { $0.id == food })?.parentID, home)
        XCTAssertEqual(store.imprints.first(where: { $0.id == middle.id })?.categoryID, home)
        XCTAssertEqual(store.imprints.count, 4)
        try store.deleteCategory(life)
        XCTAssertNil(store.categories.first(where: { $0.id == home })?.parentID)
        XCTAssertNil(store.categories.first(where: { $0.id == work })?.parentID)
        XCTAssertEqual(LibraryStore(rootURL: store.rootURL).imprints.count, 4)
    }

    func testFailedAtomicWriteLeavesCommittedStateAndDraftUntouched() throws {
        let parent = try temporaryDirectory()
        let directory = parent.appendingPathComponent("Library", isDirectory: true)
        let store = LibraryStore(rootURL: directory)
        var draft = Imprint(body: "已经保存的中文")
        try store.save(draft)
        let committed = store.snapshot
        let preserved = parent.appendingPathComponent("Preserved", isDirectory: true)
        try FileManager.default.moveItem(at: directory, to: preserved)
        try Data("block directory creation".utf8).write(to: directory)
        draft.body = "保存失败也不能丢失的输入"
        XCTAssertThrowsError(try store.save(draft))
        XCTAssertEqual(store.snapshot, committed)
        XCTAssertEqual(draft.body, "保存失败也不能丢失的输入")
        XCTAssertEqual(LibraryStore(rootURL: preserved).imprints.first?.body, "已经保存的中文")
    }

    func testCorruptAndUnknownVersionCannotOverwriteOriginal() throws {
        for bytes in [Data("{broken JSON".utf8), Data("{\"version\":99,\"categories\":[],\"imprints\":[]}".utf8)] {
            let directory = try temporaryDirectory()
            let manifest = directory.appendingPathComponent("library.json")
            try bytes.write(to: manifest)
            let store = LibraryStore(rootURL: directory)
            XCTAssertNotNil(store.loadError)
            XCTAssertThrowsError(try store.save(Imprint(body: "不能覆盖")))
            XCTAssertThrowsError(try store.createCategory(name: "不能覆盖", parentID: nil))
            XCTAssertEqual(try Data(contentsOf: manifest), bytes)
            store.setDemo(true)
            XCTAssertFalse(store.imprints.isEmpty)
            store.setDemo(false)
            XCTAssertNotNil(store.loadError)
        }
    }

    func testMissingUnsafeAndSymbolicMediaReferencesAreRejected() async throws {
        let directory = try temporaryDirectory()
        let outside = try temporaryDirectory()
        let store = LibraryStore(rootURL: directory)
        let image = try await store.importAttachment(from: makeImage(in: outside), kind: .image)
        var record = Imprint(body: "图片", attachments: [image])
        let committed = store.snapshot
        var traversal = image
        traversal.relativePath = "../中文照片.png"
        record.attachments = [traversal]
        XCTAssertThrowsError(try store.save(record))
        XCTAssertEqual(store.snapshot, committed)
        let imageURL = store.mediaURL(for: image)
        try FileManager.default.removeItem(at: imageURL)
        record.attachments = [image]
        XCTAssertThrowsError(try store.save(record))
        try FileManager.default.createSymbolicLink(at: imageURL, withDestinationURL: outside.appendingPathComponent("中文照片.png"))
        XCTAssertThrowsError(try store.save(record))
        XCTAssertEqual(store.snapshot, committed)
    }

    func testMissingReferencedAttachmentBlocksReopenWithoutLosingManifest() async throws {
        let directory = try temporaryDirectory()
        let source = try temporaryDirectory()
        let store = LibraryStore(rootURL: directory)
        let image = try await store.importAttachment(from: makeImage(in: source), kind: .image)
        try store.save(Imprint(body: "正文仍在", attachments: [image]))
        let manifest = directory.appendingPathComponent("library.json")
        let bytes = try Data(contentsOf: manifest)
        try FileManager.default.removeItem(at: store.mediaURL(for: image))
        let reopened = LibraryStore(rootURL: directory)
        XCTAssertNotNil(reopened.loadError)
        XCTAssertThrowsError(try reopened.deleteRecord(store.imprints[0].id))
        XCTAssertEqual(try Data(contentsOf: manifest), bytes)
    }

    func testInvalidTypeAndBrokenImageAreNotImported() async throws {
        let directory = try temporaryDirectory()
        let source = try temporaryDirectory()
        let store = LibraryStore(rootURL: directory)
        let unsupported = source.appendingPathComponent("pretend.exe")
        try Data("file".utf8).write(to: unsupported)
        do { _ = try await store.importAttachment(from: unsupported, kind: .audio); XCTFail("Unsupported file was imported") } catch {}
        let broken = source.appendingPathComponent("broken.png")
        try Data("not image bytes".utf8).write(to: broken)
        do { _ = try await store.importAttachment(from: broken, kind: .image); XCTFail("Broken image was imported") } catch {}
        let oversized = source.appendingPathComponent("too-large.png")
        try Data([0]).write(to: oversized)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: 101 * 1_024 * 1_024)
        try handle.close()
        do { _ = try await store.importAttachment(from: oversized, kind: .image); XCTFail("Oversized attachment was imported") } catch {}
        XCTAssertTrue(store.imprints.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("library.json").path))
    }

    func testManifestAndMediaDirectorySymlinksCannotWriteOutsideLibrary() async throws {
        let directory = try temporaryDirectory()
        let outside = try temporaryDirectory()
        let protected = outside.appendingPathComponent("protected.json")
        let original = Data("{\"version\":1,\"categories\":[],\"imprints\":[]}".utf8)
        try original.write(to: protected)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("library.json"), withDestinationURL: protected)
        let store = LibraryStore(rootURL: directory)
        XCTAssertThrowsError(try store.save(Imprint(body: "不能写到外部")))
        XCTAssertEqual(try Data(contentsOf: protected), original)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("media"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("media"), withDestinationURL: outside)
        do {
            _ = try await store.importAttachment(from: makeImage(in: outside), kind: .image)
            XCTFail("Symbolic media directory was accepted")
        } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path).sorted(), ["protected.json", "中文照片.png"].sorted())
    }

    func testDemoIsReadOnlyIndependentAndDoesNotPersistExamples() throws {
        let directory = try temporaryDirectory()
        let store = LibraryStore(rootURL: directory)
        try store.save(Imprint(body: "自己的记录"))
        let mine = store.snapshot
        store.setDemo(true)
        XCTAssertGreaterThan(store.imprints.count, 3)
        XCTAssertTrue(store.imprints.contains { !$0.scales.isEmpty })
        XCTAssertTrue(store.imprints.contains { $0.attachments.contains { $0.kind == .audio } })
        XCTAssertThrowsError(try store.save(Imprint(body: "修改示例")))
        XCTAssertThrowsError(try store.deleteCategory(store.categories[0].id))
        store.setDemo(false)
        XCTAssertEqual(store.snapshot, mine)
        XCTAssertEqual(LibraryStore(rootURL: directory).imprints.map(\.body), ["自己的记录"])
    }
}
