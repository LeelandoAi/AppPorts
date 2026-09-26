import SwiftUI

/// 目录行直接提供操作，选中详情用于查看完整路径。
struct AppDataDirectoryBrowser<Actions: View>: View {
    let groups: [DataDirGroup]
    let matchingItemIDs: Set<String>
    let isFiltering: Bool
    let actions: (DataDirItem) -> Actions

    @State private var selectedItemID: String?
    @State private var collapsedDirectoryIDs: Set<String> = []
    @State private var collapsedGroups: Set<DataDirType> = []
    @FocusState private var isOutlineFocused: Bool

    private var allRows: [DataDirTree.Row] {
        groups.flatMap { DataDirTree.rows(in: $0.items) }
    }

    private var visibleRows: [DataDirTree.Row] {
        groups.filter { !collapsedGroups.contains($0.type) }
            .flatMap { DataDirTree.rows(in: $0.items, collapsedIDs: collapsedDirectoryIDs) }
    }

    private var selectedItem: DataDirItem? {
        allRows.first { $0.id == selectedItemID }?.item
    }

    var body: some View {
        VStack(spacing: 0) {
            columnHeader
            Divider()

            ScrollViewReader { proxy in
                List(selection: $selectedItemID) {
                    ForEach(groups, id: \.type) { group in
                        Section {
                            if !collapsedGroups.contains(group.type) {
                                ForEach(DataDirTree.rows(in: group.items, collapsedIDs: collapsedDirectoryIDs)) { row in
                                    AppDataDirectoryRow(
                                        row: row,
                                        isExpanded: !collapsedDirectoryIDs.contains(row.id),
                                        isContext: !matchingItemIDs.contains(row.id),
                                        isSelected: selectedItemID == row.id,
                                        isOutlineFocused: isOutlineFocused,
                                        onToggle: { toggleDirectory(row.item) },
                                        actions: actions(row.item)
                                    )
                                    .tag(row.id)
                                    .id(row.id)
                                    .contextMenu {
                                        Button("在 Finder 中显示".localized) { reveal(row.item) }
                                        Button("复制路径".localized) { copyPath(row.item) }
                                    }
                                    .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                                }
                            }
                        } header: {
                            groupHeader(group)
                        }
                    }
                }
                .listStyle(.inset)
                .focused($isOutlineFocused)
                .modifier(DirectoryOutlineKeyboardNavigation { direction in
                    moveSelection(direction)
                    // Only keyboard navigation reveals off-screen rows, using the minimum scroll.
                    if let selectedItemID {
                        proxy.scrollTo(selectedItemID)
                    }
                })
                .onCopyCommand {
                    selectedItem.map { [NSItemProvider(object: $0.path.path as NSString)] } ?? []
                }
                .onChange(of: selectedItemID) { id in
                    if id != nil { isOutlineFocused = true }
                }
            }

            Divider()
            Group {
                if let selectedItem {
                    details(for: selectedItem)
                } else {
                    Label("选择目录以查看完整路径".localized, systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }
            }
            // Selection and differing path lengths must not resize the list above.
            .frame(height: 104)
            .background(.regularMaterial)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: matchingItemIDs) { _ in
            if isFiltering { expandAll() }
            if selectedItem == nil { selectedItemID = nil }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text("名称".localized)
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                Button(action: expandAll) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .help("展开全部".localized)
                .accessibilityLabel("展开全部".localized)
                Button(action: collapseAll) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .help("折叠全部".localized)
                .accessibilityLabel("折叠全部".localized)
            }
            .font(.system(size: 13, weight: .medium))
            .buttonStyle(.plain)
            Text("大小".localized + " · " + "状态".localized)
                .frame(width: DirectoryRowColumns.metadataWidth, alignment: .trailing)
            Text("操作".localized)
                .frame(width: DirectoryRowColumns.actionsWidth, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.secondary)
        .padding(.leading, 20)
        .padding(.trailing, 36)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    private func groupHeader(_ group: DataDirGroup) -> some View {
        Button {
            if collapsedGroups.contains(group.type) {
                collapsedGroups.remove(group.type)
            } else {
                collapsedGroups.insert(group.type)
                if DataDirTree.rows(in: group.items).contains(where: { $0.id == selectedItemID }) {
                    selectedItemID = nil
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: collapsedGroups.contains(group.type) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18)
                Image(systemName: group.type.icon)
                    .font(.system(size: 17))
                    .foregroundColor(.accentColor)
                Text(group.type.localizedTitle)
                    .fontWeight(.semibold)
                Text("\(DataDirTree.rows(in: group.items).filter { matchingItemIDs.contains($0.id) }.count)")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsedGroups.contains(group.type) ? "展开目录".localized : "折叠目录".localized)
    }

    private func details(for item: DataDirItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DataDirFolderIcon(type: item.type, pointSize: 20)
                    .foregroundColor(.accentColor)
                Text(verbatim: item.path.lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                PriorityBadge(priority: item.priority)
                Spacer(minLength: 4)
                Button { reveal(item) } label: {
                    Label("在 Finder 中显示".localized, systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("在 Finder 中显示".localized)
                Button { copyPath(item) } label: {
                    Label("复制路径".localized, systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("复制路径".localized)
                Button { selectedItemID = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("关闭".localized)
                .accessibilityLabel("关闭".localized)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    pathLine(item.path, label: "本地路径".localized)
                    if let destination = item.linkedDestination, destination != item.path {
                        pathLine(destination, label: "外部路径".localized)
                    }
                    Text(item.description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    if !item.isMigratable, !DataDirStatus.mountStatuses.contains(item.status) {
                        Label((item.nonMigratableReason ?? "此目录不支持迁移").localized, systemImage: "lock")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func pathLine(_ url: URL, label: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize()
            Text(verbatim: url.path)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggleDirectory(_ item: DataDirItem) {
        if collapsedDirectoryIDs.contains(item.id) {
            collapsedDirectoryIDs.remove(item.id)
        } else {
            collapsedDirectoryIDs.insert(item.id)
            if let selectedItemID, selectedItemID.hasPrefix(item.id + "/") {
                self.selectedItemID = item.id
            }
        }
    }

    private func expandAll() {
        collapsedGroups.removeAll()
        collapsedDirectoryIDs.removeAll()
    }

    private func collapseAll() {
        collapsedGroups = Set(groups.map(\.type))
        collapsedDirectoryIDs = Set(allRows.filter { !$0.item.children.isEmpty }.map(\.id))
        selectedItemID = nil
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let rows = visibleRows
        guard !rows.isEmpty else { return }
        guard let index = rows.firstIndex(where: { $0.id == selectedItemID }) else {
            selectedItemID = rows[0].id
            return
        }
        let row = rows[index]
        switch direction {
        case .up: selectedItemID = rows[max(0, index - 1)].id
        case .down: selectedItemID = rows[min(rows.count - 1, index + 1)].id
        case .left:
            if !row.item.children.isEmpty && !collapsedDirectoryIDs.contains(row.id) {
                toggleDirectory(row.item)
            } else if let parentID = row.parentID {
                selectedItemID = parentID
            }
        case .right:
            if collapsedDirectoryIDs.contains(row.id) {
                collapsedDirectoryIDs.remove(row.id)
            } else if let child = row.item.children.first {
                selectedItemID = child.id
            }
        @unknown default: break
        }
    }

    private func reveal(_ item: DataDirItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.linkedDestination ?? item.path])
    }

    private func copyPath(_ item: DataDirItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.path.path, forType: .string)
    }
}

private enum DirectoryRowColumns {
    static let metadataWidth: CGFloat = 90
    static let actionsWidth: CGFloat = 128
}

private struct DataDirFolderIcon: View {
    let type: DataDirType
    let pointSize: CGFloat

    var body: some View {
        DataDirFolderSilhouette()
            .frame(width: pointSize * 1.2, height: pointSize)
            .overlay {
                Image(systemName: type.icon)
                    .resizable()
                    .scaledToFit()
                    .font(.system(size: pointSize * 0.5, weight: .semibold))
                    .frame(width: pointSize * 0.5, height: pointSize * 0.5)
                    .foregroundColor(.black)
                    // Keep the entire emblem inside the face, clear of the tab.
                    .offset(y: pointSize * 0.12)
                    .blendMode(.destinationOut)
            }
            .symbolRenderingMode(.monochrome)
            // The cutout stays legible on both blue and selected white folders.
            .compositingGroup()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(type.localizedTitle)
    }
}

/// A solid folder face gives each type emblem room without the system symbol's horizontal cutout.
private struct DataDirFolderSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0, 0.15))
        path.addQuadCurve(to: point(0.13, 0), control: point(0, 0))
        path.addLine(to: point(0.35, 0))
        path.addQuadCurve(to: point(0.42, 0.04), control: point(0.39, 0))
        path.addLine(to: point(0.50, 0.16))
        path.addLine(to: point(0.87, 0.16))
        path.addQuadCurve(to: point(1, 0.31), control: point(1, 0.16))
        path.addLine(to: point(1, 0.85))
        path.addQuadCurve(to: point(0.87, 1), control: point(1, 1))
        path.addLine(to: point(0.13, 1))
        path.addQuadCurve(to: point(0, 0.85), control: point(0, 1))
        path.closeSubpath()
        return path
    }
}

private struct AppDataDirectoryRow<Actions: View>: View {
    let row: DataDirTree.Row
    let isExpanded: Bool
    let isContext: Bool
    let isSelected: Bool
    let isOutlineFocused: Bool
    let onToggle: () -> Void
    let actions: Actions
    @Environment(\.controlActiveState) private var controlActiveState

    private var isEmphasized: Bool { isSelected && isOutlineFocused && controlActiveState == .key }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                if row.item.children.isEmpty {
                    Color.clear.frame(width: 20, height: 32)
                } else {
                    Button(action: onToggle) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isEmphasized ? .white.opacity(0.85) : .secondary)
                            .frame(width: 20, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "折叠目录".localized : "展开目录".localized)
                    .accessibilityLabel(isExpanded ? "折叠目录".localized : "展开目录".localized)
                }

                DataDirFolderIcon(type: row.item.type, pointSize: 23)
                    .frame(width: 36, height: 36)
                    .foregroundColor(isEmphasized ? .white : .accentColor.opacity(isContext ? 0.5 : 0.85))
                    .background(isEmphasized ? Color.white.opacity(0.16) : Color.accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(verbatim: row.item.path.lastPathComponent)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isEmphasized ? .white : (isContext ? .secondary : .primary))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !row.item.isMigratable && !DataDirStatus.mountStatuses.contains(row.item.status) {
                            Image(systemName: "lock")
                                .font(.system(size: 11))
                                .foregroundColor(isEmphasized ? .white.opacity(0.85) : .secondary)
                                .help((row.item.nonMigratableReason ?? "此目录不支持迁移").localized)
                        }
                    }
                    if let contextPath = row.contextPath {
                        Text(verbatim: contextPath)
                            .font(.system(size: 11))
                            .foregroundColor(isEmphasized ? .white.opacity(0.85) : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(row.level) * 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(row.item.path.path)

            VStack(alignment: .trailing, spacing: 4) {
                Text(row.item.size ?? "计算中...".localized)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(isEmphasized ? .white : (row.item.size == nil ? .secondary : .primary))
                DataDirStatusBadge(status: row.item.status, compact: false, isEmphasized: isEmphasized)
            }
            .frame(width: DirectoryRowColumns.metadataWidth, alignment: .trailing)

            HStack(spacing: 6) { actions }
                .frame(width: DirectoryRowColumns.actionsWidth, alignment: .trailing)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }
}

private struct DirectoryOutlineKeyboardNavigation: ViewModifier {
    let move: (MoveCommandDirection) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.leftArrow) {
                    move(.left)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    move(.right)
                    return .handled
                }
        } else {
            content.onMoveCommand(perform: move)
        }
    }
}
