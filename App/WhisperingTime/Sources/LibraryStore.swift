import Foundation
import Observation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// A local, plaintext prototype library. The demonstration library never shares its records or media with this store.
@MainActor @Observable
final class LibraryStore {
    let rootURL: URL
    private(set) var isDemo = false
    private(set) var loadError: String?
    private var savedSnapshot = LibrarySnapshot()
    @ObservationIgnored private let fileManager = FileManager.default
    @ObservationIgnored private let demoSnapshot: LibrarySnapshot
    nonisolated private static let maximumAttachmentBytes = 100 * 1_024 * 1_024
    nonisolated private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "webp", "bmp"]
    nonisolated private static let audioExtensions: Set<String> = ["m4a", "m4b", "mp3", "wav", "aif", "aiff", "aifc", "caf", "flac"]

    var snapshot: LibrarySnapshot { isDemo ? demoSnapshot : savedSnapshot }
    var categories: [CategoryNode] { snapshot.categories }
    var imprints: [Imprint] { snapshot.imprints }
    private var manifestURL: URL { rootURL.appendingPathComponent("library.json") }

    init(rootURL: URL? = nil, demonstration: LibrarySnapshot? = nil) {
        self.rootURL = (rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.acered.whisperingtime.prototype", isDirectory: true)).standardizedFileURL
        self.demoSnapshot = demonstration ?? Self.makeDemoSnapshot()
        if fileManager.fileExists(atPath: manifestURL.path) {
            do {
                let data = try Data(contentsOf: manifestURL)
                let decoded = try Self.decoder().decode(LibrarySnapshot.self, from: data)
                try validate(decoded)
                savedSnapshot = decoded
            } catch {
                loadError = "无法读取本地资料，原文件已保留。为避免覆盖，暂时停止写入。\n\(error.localizedDescription)"
            }
        }
    }

    func records(in scope: ReviewScope) -> [Imprint] {
        let records: [Imprint]
        switch scope {
        case .all: records = imprints
        case .unclassified: records = imprints.filter { $0.categoryID == nil }
        case .category(let id):
            let included = descendants(of: id, in: categories).union([id])
            records = imprints.filter { $0.categoryID.map(included.contains) ?? false }
        }
        return records.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func categoryPath(_ id: UUID?) -> String {
        guard var current = id else { return "未分类" }
        var names: [String] = []
        var visited: Set<UUID> = []
        let lookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        while visited.insert(current).inserted, let node = lookup[current] {
            names.insert(node.name, at: 0)
            guard let parent = node.parentID else { break }
            current = parent
        }
        return names.isEmpty ? "分类不可用" : names.joined(separator: " / ")
    }

    func save(_ record: Imprint) throws {
        try requireWritable()
        guard record.hasContent else { throw PrototypeError.message("请先写一点文字，或添加图片、声音与刻度。") }
        var next = savedSnapshot
        var updated = record
        updated.title = record.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.title?.isEmpty == true { updated.title = nil }
        updated.updatedAt = Date()
        if let index = next.imprints.firstIndex(where: { $0.id == record.id }) { next.imprints[index] = updated }
        else { next.imprints.append(updated) }
        try commit(next)
    }

    func deleteRecord(_ id: UUID) throws {
        try requireWritable()
        var next = savedSnapshot
        next.imprints.removeAll { $0.id == id }
        try commit(next)
        // Keep unreferenced media for now: a failed/cancelled edit must never remove another draft's original.
    }

    @discardableResult func createCategory(name: String, parentID: UUID?) throws -> UUID {
        try requireWritable()
        let name = try checkedName(name)
        var next = savedSnapshot
        let node = CategoryNode(parentID: parentID, name: name)
        next.categories.append(node)
        try commit(next)
        return node.id
    }

    func renameCategory(_ id: UUID, name: String) throws {
        try requireWritable()
        guard let index = savedSnapshot.categories.firstIndex(where: { $0.id == id }) else { throw PrototypeError.message("这个分类已不存在。") }
        var next = savedSnapshot
        next.categories[index].name = try checkedName(name)
        try commit(next)
    }

    func moveCategory(_ id: UUID, parentID: UUID?) throws {
        try requireWritable()
        guard let index = savedSnapshot.categories.firstIndex(where: { $0.id == id }) else { throw PrototypeError.message("这个分类已不存在。") }
        if let parentID, parentID == id || descendants(of: id, in: savedSnapshot.categories).contains(parentID) {
            throw PrototypeError.message("不能将分类移动到自己或自己的子分类中。")
        }
        var next = savedSnapshot
        next.categories[index].parentID = parentID
        try commit(next)
    }

    func deleteCategory(_ id: UUID) throws {
        try requireWritable()
        guard let node = savedSnapshot.categories.first(where: { $0.id == id }) else { return }
        var next = savedSnapshot
        next.categories.removeAll { $0.id == id }
        for index in next.categories.indices where next.categories[index].parentID == id { next.categories[index].parentID = node.parentID }
        for index in next.imprints.indices where next.imprints[index].categoryID == id { next.imprints[index].categoryID = node.parentID }
        try commit(next)
    }

    func importAttachment(from source: URL, kind: MediaKind) async throws -> MediaAttachment {
        try requireWritable()
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.lowercased()
        let isImage = kind == .image
        try await Task.detached(priority: .userInitiated) {
            try Self.validateMediaFile(source, isImage: isImage, extension: ext)
        }.value
        try Task.checkCancellation()
        try requireWritable()
        try prepareDirectories()
        let id = UUID()
        let relativePath = "media/\(id.uuidString.lowercased()).\(ext)"
        let attachment = MediaAttachment(id: id, kind: kind, relativePath: relativePath, originalName: source.lastPathComponent)
        let destination = try checkedMediaURL(attachment)
        do {
            try Task.checkCancellation()
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.copyItem(at: source, to: destination)
                try Self.validateMediaFile(destination, isImage: isImage, extension: ext)
            }.value
            try Task.checkCancellation()
            return attachment
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func mediaURL(for attachment: MediaAttachment) -> URL {
        if isDemo, attachment.relativePath.hasPrefix("demo/"),
           let resource = Self.demoResourceURL(named: String(attachment.relativePath.dropFirst(5))) { return resource }
        // Return an inaccessible location for an invalid reference rather than traversing outside the library.
        return (try? checkedMediaURL(attachment)) ?? rootURL.appendingPathComponent("invalid-media-reference")
    }

    func setDemo(_ enabled: Bool) { isDemo = enabled }

    private func requireWritable() throws {
        if isDemo { throw PrototypeError.message("这是独立的只读示例。切换到“我的印迹”后即可补记。") }
        if let loadError { throw PrototypeError.message(loadError) }
    }

    private func checkedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PrototypeError.message("请输入分类名称。") }
        return trimmed
    }

    private func commit(_ next: LibrarySnapshot) throws {
        try validate(next)
        try prepareDirectories()
        let data = try Self.encoder().encode(next)
        // Foundation writes a sibling temporary file and replaces the destination atomically.
        try data.write(to: manifestURL, options: .atomic)
        savedSnapshot = next
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let media = rootURL.appendingPathComponent("media", isDirectory: true)
        let expected = rootURL.resolvingSymlinksInPath().appendingPathComponent("media", isDirectory: true).standardizedFileURL
        guard media.resolvingSymlinksInPath().standardizedFileURL.path == expected.path else { throw PrototypeError.message("媒体目录位置异常，已停止写入。") }
        try fileManager.createDirectory(at: media, withIntermediateDirectories: true)
        guard !isSymbolicLink(manifestURL) else { throw PrototypeError.message("资料文件位置异常，已停止写入。") }
    }

    private func validate(_ candidate: LibrarySnapshot) throws {
        guard candidate.version == 1 else { throw PrototypeError.message("资料版本 \(candidate.version) 暂不支持，请保留原文件并使用对应版本打开。") }
        guard Set(candidate.categories.map(\.id)).count == candidate.categories.count,
              Set(candidate.imprints.map(\.id)).count == candidate.imprints.count else { throw PrototypeError.message("资料包含重复标识。") }
        let categoryIDs = Set(candidate.categories.map(\.id))
        for node in candidate.categories {
            _ = try checkedName(node.name)
            if let parent = node.parentID, !categoryIDs.contains(parent) { throw PrototypeError.message("分类的上级不存在。") }
            var visited: Set<UUID> = [node.id]
            var parent = node.parentID
            while let id = parent {
                guard visited.insert(id).inserted else { throw PrototypeError.message("分类不能形成循环。") }
                parent = candidate.categories.first(where: { $0.id == id })?.parentID
            }
        }
        var mediaByID: [UUID: MediaAttachment] = [:]
        for record in candidate.imprints {
            guard record.occurredAt.timeIntervalSinceReferenceDate.isFinite, record.updatedAt.timeIntervalSinceReferenceDate.isFinite else { throw PrototypeError.message("印迹的时间无效。") }
            if let categoryID = record.categoryID, !categoryIDs.contains(categoryID) { throw PrototypeError.message("印迹所属的分类不存在。") }
            guard Set(record.scales.map(\.id)).count == record.scales.count,
                  Set(record.attachments.map(\.id)).count == record.attachments.count else { throw PrototypeError.message("印迹包含重复附件或刻度。") }
            for attachment in record.attachments {
                if let previous = mediaByID[attachment.id], previous.relativePath != attachment.relativePath || previous.kind != attachment.kind {
                    throw PrototypeError.message("附件标识与文件不一致。")
                }
                mediaByID[attachment.id] = attachment
                let url = try checkedMediaURL(attachment)
                try Self.validateMediaFile(url, isImage: attachment.kind == .image, extension: url.pathExtension.lowercased())
            }
        }
    }

    private func checkedMediaURL(_ attachment: MediaAttachment) throws -> URL {
        let parts = attachment.relativePath.split(separator: "/", omittingEmptySubsequences: false)
        let ext = URL(fileURLWithPath: attachment.relativePath).pathExtension.lowercased()
        let allowed = attachment.kind == .image ? Self.imageExtensions : Self.audioExtensions
        guard parts.count == 2, parts[0] == "media", allowed.contains(ext),
              String(parts[1]) == "\(attachment.id.uuidString.lowercased()).\(ext)" else { throw PrototypeError.message("附件路径无效。") }
        let url = rootURL.appendingPathComponent(attachment.relativePath)
        let base = rootURL.resolvingSymlinksInPath().standardizedFileURL.path + "/media/"
        guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(base), !isSymbolicLink(url) else { throw PrototypeError.message("附件位置异常。") }
        return url
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    nonisolated private static func validateMediaFile(_ url: URL, isImage: Bool, extension ext: String) throws {
        let allowed = isImage ? Self.imageExtensions : Self.audioExtensions
        guard allowed.contains(ext) else { throw PrototypeError.message(isImage ? "请选择常见图片文件，如 PNG、JPEG 或 HEIC。" : "请选择常见音频文件，如 M4A、WAV、MP3 或 AIFF。") }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true, let bytes = info.fileSize, bytes > 0, bytes <= Self.maximumAttachmentBytes else { throw PrototypeError.message("附件必须是非空文件，且不能超过 100 MB。") }
        if isImage {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, Double(width) * Double(height) <= 100_000_000,
                  CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil else { throw PrototypeError.message("这张图片无法读取，请选择其他文件。") }
        } else {
            let file = try AVAudioFile(forReading: url)
            guard file.length > 0, file.processingFormat.channelCount > 0 else { throw PrototypeError.message("这段音频没有可读取的声音。") }
        }
    }

    private func descendants(of id: UUID, in nodes: [CategoryNode]) -> Set<UUID> {
        var result: Set<UUID> = []
        var queue = [id]
        while let parent = queue.popLast() {
            for node in nodes where node.parentID == parent && node.id != id {
                if result.insert(node.id).inserted { queue.append(node.id) }
            }
        }
        return result
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Millisecond dates retain subsecond ordering across restarts.
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static func demoResourceURL(named name: String) -> URL? {
        let file = URL(fileURLWithPath: name)
        return Bundle.main.url(forResource: file.deletingPathExtension().lastPathComponent, withExtension: file.pathExtension)
    }

    private static func makeDemoSnapshot() -> LibrarySnapshot {
        let life = CategoryNode(name: "人生")
        let home = CategoryNode(parentID: life.id, name: "家庭生活")
        let personal = CategoryNode(parentID: home.id, name: "个人生活")
        let food = CategoryNode(parentID: personal.id, name: "饮食")
        let work = CategoryNode(parentID: life.id, name: "职场")
        let walking = CategoryNode(parentID: personal.id, name: "散步")
        let today = Date()
        func daysAgo(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: -days, to: today) ?? today }
        let image = MediaAttachment(kind: .image, relativePath: "demo/示例画面.png", originalName: "河边的晚风.png")
        let sound = MediaAttachment(kind: .audio, relativePath: "demo/示例录音.aiff", originalName: "散步时的一段声音.aiff", transcript: "今天沿着河边走了一会儿，风很轻。想把这一刻留下来。", transcriptionNote: "示例转写，可播放原声")
        let dinner = Imprint(categoryID: food.id, occurredAt: daysAgo(2), body: "和家人一起做了一顿晚饭。番茄慢慢煮软，厨房里都是香气。\n吃饭时没有着急收拾，就这样多坐了一会儿。", scales: [ImprintScale(name: "心情", kind: .choice, value: "舒展", options: ["平静", "舒展", "忙碌"]), ImprintScale(name: "饮水", kind: .number, value: "1500", unit: "毫升")])
        let river = Imprint(title: "风经过河边", categoryID: walking.id, occurredAt: daysAgo(6), body: "没有特地走到哪里，只是想听一听水声。", attachments: [image, sound])
        let project = Imprint(categoryID: work.id, occurredAt: daysAgo(18), body: "把反复讨论的问题画在一张纸上，事情忽然清楚了一点。\n今天值得记住的，是大家终于开始问同一个问题。", scales: [ImprintScale(name: "一个念头", kind: .text, value: "先把问题说清楚")])
        let longBody = Array(repeating: "窗外的树叶动了一下，我才发现时间已经慢慢走到午后。桌上的书还停在那一页，不急着读完，也不急着整理成什么。有些记忆只需要留在这里，下次再遇见时，能想起当时的光线和心情。", count: 12).joined(separator: "\n\n")
        let reading = Imprint(title: "留在这一页", categoryID: personal.id, occurredAt: daysAgo(47), body: longBody)
        let note = Imprint(occurredAt: daysAgo(90), body: "回家的路上，记起一个很久没有联系的朋友。想找一天和他聊聊。")
        return LibrarySnapshot(categories: [life, home, personal, food, work, walking], imprints: [dinner, river, project, reading, note])
    }
}
