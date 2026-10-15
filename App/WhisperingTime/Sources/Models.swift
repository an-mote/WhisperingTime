import Foundation

enum ReviewMode: String, CaseIterable, Identifiable, Codable {
    case cards, calendar, timeline, slideshow
    var id: Self { self }
    var title: String { switch self { case .cards: "卡片"; case .calendar: "日历"; case .timeline: "时间轴"; case .slideshow: "播放" } }
    var symbol: String { switch self { case .cards: "rectangle.grid.2x2"; case .calendar: "calendar"; case .timeline: "point.3.connected.trianglepath.dotted"; case .slideshow: "play.rectangle" } }
}

enum TimeDisplay: String, CaseIterable, Identifiable, Codable {
    case hidden, absolute, relative
    var id: Self { self }
    var title: String { switch self { case .hidden: "隐藏时间"; case .absolute: "绝对时间"; case .relative: "相对时间" } }
    func label(for date: Date) -> String? {
        switch self {
        case .hidden: return nil
        case .absolute: return date.formatted(.dateTime.year().month().day())
        case .relative:
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            return formatter.localizedString(for: date, relativeTo: Date())
        }
    }
}

enum ReviewScope: Hashable {
    case all, unclassified, category(UUID)
}

struct CategoryNode: Identifiable, Codable, Hashable {
    var id = UUID()
    var parentID: UUID?
    var name: String
}

enum MediaKind: String, Codable { case image, audio }

struct MediaAttachment: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: MediaKind
    var relativePath: String
    var originalName: String
    var transcript: String = ""
    var transcriptionNote: String?
}

enum ScaleKind: String, Codable, CaseIterable, Identifiable {
    case text, number, choice
    var id: Self { self }
    var title: String { switch self { case .text: "文字"; case .number: "数值"; case .choice: "选项" } }
}

struct ImprintScale: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var kind: ScaleKind = .text
    var value = ""
    var unit = ""
    var options: [String] = []
}

struct Imprint: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String? = nil
    var categoryID: UUID? = nil
    var occurredAt = Date()
    var updatedAt = Date()
    var body = ""
    var attachments: [MediaAttachment] = []
    var scales: [ImprintScale] = []
    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        if let first = body.split(whereSeparator: \.isNewline).first { return String(first.prefix(64)) }
        if !attachments.isEmpty { return attachments.contains(where: { $0.kind == .audio }) ? "一段声音" : "一些画面" }
        return "一条印迹"
    }
    var hasContent: Bool {
        !(title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty || scales.contains { !$0.value.isEmpty }
    }
}

struct LibrarySnapshot: Codable, Equatable {
    var version = 1
    var categories: [CategoryNode] = []
    var imprints: [Imprint] = []
}

enum PrototypeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { message } else { nil } }
}
