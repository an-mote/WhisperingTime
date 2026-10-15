import SwiftUI
import AppKit

enum CategoryAction: Identifiable {
    case create(UUID?), rename(CategoryNode), move(CategoryNode), delete(CategoryNode)
    var id: String {
        switch self {
        case .create(let parent): "create-\(parent?.uuidString ?? "root")"
        case .rename(let node): "rename-\(node.id)"
        case .move(let node): "move-\(node.id)"
        case .delete(let node): "delete-\(node.id)"
        }
    }
    var title: String {
        switch self { case .create: "新建分类"; case .rename: "重命名分类"; case .move: "移动分类"; case .delete: "删除分类" }
    }
}

struct CategorySidebar: View {
    @Bindable var store: LibraryStore
    @Binding var scope: ReviewScope
    @Binding var action: CategoryAction?
    @Binding var showSync: Bool
    @Binding var showAbout: Bool

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("回顾") {
                    scopeButton("全部印迹", symbol: "square.stack", value: .all)
                    scopeButton("未分类", symbol: "tray", value: .unclassified)
                }
                Section {
                    ForEach(store.categories.filter { $0.parentID == nil }) { node in
                        CategoryBranchRow(node: node, categories: store.categories, readOnly: store.isDemo || store.loadError != nil, scope: $scope, action: $action)
                    }
                    Button { action = .create(nil) } label: { Label("新建分类", systemImage: "folder.badge.plus") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityIdentifier("newCategory")
                        .disabled(store.isDemo || store.loadError != nil)
                } header: { Text("分类") }
                if !store.isDemo {
                    Section {
                        Button { store.setDemo(true) } label: { Label("查看示例", systemImage: "sparkles.rectangle.stack") }
                            .buttonStyle(.plain).accessibilityIdentifier("showExamples")
                    }
                }
            }
            .listStyle(.sidebar)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Button { showSync = true } label: { Label("中转同步演示", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(.plain).accessibilityIdentifier("relayDemo")
                Button { showAbout = true } label: { Label("原型与本机资料", systemImage: "info.circle") }
                    .buttonStyle(.plain).accessibilityIdentifier("prototypeInfo")
            }
            .imprintFont(.callout).padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("印迹")
    }

    private func scopeButton(_ title: String, symbol: String, value: ReviewScope) -> some View {
        Button { scope = value } label: {
            HStack { Label(title, systemImage: symbol); Spacer(); if scope == value { Image(systemName: "checkmark").accessibilityLabel("已选中") } }
                .padding(.vertical, 3).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(scope == value ? Color.accentColor.opacity(0.13) : Color.clear)
        .accessibilityAddTraits(scope == value ? .isSelected : [])
    }
}

struct CategoryBranchRow: View {
    let node: CategoryNode
    let categories: [CategoryNode]
    let readOnly: Bool
    @Binding var scope: ReviewScope
    @Binding var action: CategoryAction?
    @State private var expanded = true
    private var children: [CategoryNode] { categories.filter { $0.parentID == node.id } }

    var body: some View {
        Group {
            if children.isEmpty { row }
            else {
                DisclosureGroup(isExpanded: $expanded) {
                    ForEach(children) { child in CategoryBranchRow(node: child, categories: categories, readOnly: readOnly, scope: $scope, action: $action) }
                } label: { row }
            }
        }
        .contextMenu { if !readOnly { categoryMenu } else { Text("只读示例分类") } }
    }

    private var row: some View {
        HStack(spacing: 4) {
            Button { scope = .category(node.id) } label: {
                HStack(spacing: 7) {
                    Label(node.name, systemImage: "folder")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if scope == .category(node.id) { Image(systemName: "checkmark").accessibilityLabel("已选中") }
                }
                .padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(scope == .category(node.id) ? Color.accentColor : Color.primary)
            .accessibilityLabel("分类，\(node.name)")
            .accessibilityAddTraits(scope == .category(node.id) ? .isSelected : [])
            if !readOnly {
                Menu { categoryMenu } label: { Image(systemName: "ellipsis").accessibilityLabel("\(node.name)分类操作") }
                    .menuStyle(.borderlessButton).fixedSize().help("分类操作")
            }
        }
        .accessibilityAction(named: "新建子分类") { if !readOnly { action = .create(node.id) } }
        .accessibilityAction(named: "重命名") { if !readOnly { action = .rename(node) } }
        .accessibilityAction(named: "移动") { if !readOnly { action = .move(node) } }
    }
    @ViewBuilder private var categoryMenu: some View {
        Button("新建子分类") { action = .create(node.id) }
        Button("重命名") { action = .rename(node) }
        Button("移动到…") { action = .move(node) }
        Divider()
        Button("删除分类…", role: .destructive) { action = .delete(node) }
    }
}

struct CategoryOption: Identifiable {
    let id: UUID
    let path: String
}

func categoryOptions(_ categories: [CategoryNode]) -> [CategoryOption] {
    var result: [CategoryOption] = []
    func append(parent: UUID?, prefix: String, visited: Set<UUID>) {
        for node in categories.filter({ $0.parentID == parent }) where !visited.contains(node.id) {
            let path = prefix.isEmpty ? node.name : "\(prefix) / \(node.name)"
            result.append(CategoryOption(id: node.id, path: path))
            append(parent: node.id, prefix: path, visited: visited.union([node.id]))
        }
    }
    append(parent: nil, prefix: "", visited: [])
    return result
}

struct CategoryEditSheet: View {
    @Bindable var store: LibraryStore
    let action: CategoryAction
    var completion: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var parentID: UUID?
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(action.title).imprintFont(.title2, bold: true)
            if case .delete(let node) = action {
                Label("删除“\(node.name)”后，印迹和子分类会保留并归入它的上级；没有上级时，印迹归为未分类。", systemImage: "folder.badge.minus")
                    .imprintFont(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if case .move = action {} else {
                    TextField("分类名称", text: $name).textFieldStyle(.roundedBorder).focused($nameFocused).accessibilityIdentifier("categoryName")
                }
                if case .rename = action {} else {
                    Picker("上级分类", selection: $parentID) {
                        Text("无上级分类").tag(Optional<UUID>.none)
                        ForEach(categoryOptions(store.categories)) { option in
                            Text(option.path).tag(Optional(option.id))
                        }
                    }
                    .accessibilityIdentifier("parentCategory")
                }
            }
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isDelete ? "删除分类" : "保存", role: isDelete ? .destructive : nil) { submit() }
                    .keyboardShortcut(.defaultAction).accessibilityIdentifier("saveCategory")
            }
        }
        .padding(24).frame(minWidth: 370, idealWidth: 460)
        .onAppear {
            switch action {
            case .create(let parent): parentID = parent
            case .rename(let node), .move(let node), .delete(let node): name = node.name; parentID = node.parentID
            }
            nameFocused = true
        }
    }
    private var isDelete: Bool { if case .delete = action { true } else { false } }
    private func submit() {
        do {
            switch action {
            case .create: _ = try store.createCategory(name: name, parentID: parentID)
            case .rename(let node): try store.renameCategory(node.id, name: name)
            case .move(let node): try store.moveCategory(node.id, parentID: parentID)
            case .delete(let node): try store.deleteCategory(node.id)
            }
            completion(isDelete); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct PrototypeInfoSheet: View {
    let store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("本机的印迹原型").imprintFont(.title2, bold: true)
            Text("你输入的测试内容保存在这台 Mac。示例集与测试资料分开，切换不会混入资料。").imprintFont(.body)
            Text("当前资料未加密，尚未接入真实同步、正式备份或旧数据导入。请使用可用于测试的内容。")
                .imprintFont(.body)
                .foregroundStyle(.secondary)
            Text(store.rootURL.path).imprintFont(.caption1, monospaced: true).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([store.rootURL]) }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(minWidth: 420, idealWidth: 500)
    }
}

struct RelayDemoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var state = 0
    private let names = ["等待接收", "已接收并清除", "到期需补齐", "首次补齐"]
    private let symbols = ["clock.arrow.circlepath", "checkmark.icloud", "exclamationmark.arrow.triangle.2.circlepath", "laptopcomputer.and.arrow.down"]
    private let details = [
        "资料在设备上完整保存。中转等待目标设备可靠保存内容和附件后确认；完整接收起最多保留 365 天。",
        "所有目标设备已经确认。未来中转服务将提前清除对应内容与附件；设备上的完整资料仍然保留。",
        "超过 365 天的中转资料不再保留。离线设备需要从已有完整资料的设备或用户备份补齐，并保留本机尚未同步的修改。",
        "新设备从已有完整资料的设备或用户备份补齐。服务器不是长期资料库，已经清除的内容无法单独从服务器恢复。"
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("中转同步演示").imprintFont(.title2, bold: true); Spacer(); Text("模拟").imprintFont(.caption1, bold: true).padding(.horizontal, 9).padding(.vertical, 4).background(.quaternary, in: Capsule()) }
            Text("这是产品规则演示，没有连接服务器或传输资料。").imprintFont(.body).foregroundStyle(.secondary)
            Picker("演示状态", selection: $state) { ForEach(0..<names.count, id: \.self) { index in Text(names[index]).tag(index) } }
                .accessibilityIdentifier("relayState")
            Label(names[state], systemImage: symbols[state]).imprintFont(.title3, bold: true)
            Text(details[state]).imprintFont(.body).fixedSize(horizontal: false, vertical: true).lineSpacing(5)
            Divider()
            Text("中转不能替代备份。重试不延长保留期限；未来清理验收还须覆盖临时文件、日志和备份策略。现有 Go 服务尚未实现这些规则。")
                .imprintFont(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(minWidth: 420, idealWidth: 540)
    }
}
