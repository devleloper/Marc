import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// The Library replaces the Space pager in the sidebar: downloads, archive, notes and boosts.
struct LibraryPanel: View {
    @Bindable var window: BrowserWindowModel
    @State private var section = Section.downloads
    @Environment(\.themePalette) private var palette

    enum Section: String, CaseIterable, Identifiable {
        case downloads = "Downloads"
        case archive = "Archive"
        case notes = "Notes"
        case boosts = "Boosts"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .downloads: "arrow.down.circle"
            case .archive: "archivebox"
            case .notes: "note.text"
            case .boosts: "paintbrush.pointed"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Library").font(Typography.sectionHeader).foregroundStyle(palette.secondaryText)
                Spacer()
                IconButton("xmark", label: "Close Library", size: 24, symbolSize: 11) { window.isShowingLibrary = false }
            }
            .padding(.leading, 8)

            HStack(spacing: 4) {
                ForEach(Section.allCases) { candidate in
                    Button { section = candidate } label: {
                        Image(systemName: candidate.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .foregroundStyle(section == candidate ? palette.primaryText : palette.secondaryText)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(section == candidate ? palette.selectedFill : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(candidate.rawValue)
                    .accessibilityLabel(candidate.rawValue)
                }
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    switch section {
                    case .downloads: DownloadsList(window: window)
                    case .archive: ArchiveList(window: window)
                    case .notes: NotesList(window: window)
                    case .boosts: BoostsList(window: window)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, Metrics.Sidebar.inset)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct LibraryRow<Accessory: View>: View {
    let icon: NSImage?
    let symbol: String?
    let title: String
    let subtitle: String
    let action: () -> Void
    @ViewBuilder let accessory: () -> Accessory
    @State private var isHovered = false
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else if let symbol {
                    Image(systemName: symbol).foregroundStyle(palette.icon)
                }
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.primaryText).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(palette.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 0)
            if isHovered { accessory() }
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
        .rowBackground(isSelected: false, isHovered: isHovered)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { isHovered = $0 }
    }
}

private struct EmptyLibraryText: View {
    let text: String
    @Environment(\.themePalette) private var palette

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(palette.tertiaryText)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }
}

private struct DownloadsList: View {
    @Bindable var window: BrowserWindowModel

    var body: some View {
        if let downloads = window.session?.downloads {
            if downloads.downloads.isEmpty {
                EmptyLibraryText(text: "No downloads yet")
            }
            ForEach(downloads.downloads) { download in
                LibraryRow(
                    icon: download.fileURL.map { NSWorkspace.shared.icon(forFile: $0.path(percentEncoded: false)) },
                    symbol: "doc",
                    title: download.fileName,
                    subtitle: subtitle(for: download),
                    action: { downloads.open(download.id) },
                ) {
                    if download.state.isActive {
                        IconButton("xmark.circle", label: "Cancel", size: 22, symbolSize: 12) { downloads.cancel(download.id) }
                    } else {
                        IconButton("magnifyingglass", label: "Show in Finder", size: 22, symbolSize: 12) { downloads.reveal(download.id) }
                        IconButton("trash", label: "Remove from List", size: 22, symbolSize: 12) { downloads.remove(download.id) }
                    }
                }
            }
            if downloads.downloads.contains(where: { !$0.state.isActive }) {
                Button("Clear Finished") { downloads.clearFinished() }
                    .buttonStyle(.plain)
                    .font(Typography.caption)
                    .foregroundStyle(window.palette.secondaryText)
                    .padding(.top, 6)
            }
        }
    }

    private func subtitle(for download: Download) -> String {
        switch download.state {
        case let .inProgress(received, expected):
            let formatter = ByteCountFormatter()
            if let expected { return "\(formatter.string(fromByteCount: received)) of \(formatter.string(fromByteCount: expected))" }
            return formatter.string(fromByteCount: received)
        case .finished: return download.finishedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Finished"
        case let .failed(message): return "Failed — \(message)"
        case .cancelled: return "Cancelled"
        }
    }
}

private struct ArchiveList: View {
    @Bindable var window: BrowserWindowModel
    @State private var query = ""

    var body: some View {
        if let archive = window.session?.archive {
            TextField("Search Archive", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.bottom, 4)
            let tabs = archive.tabs
                .filter {
                    query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.absoluteString
                        .localizedCaseInsensitiveContains(query)
                }
            if tabs.isEmpty {
                EmptyLibraryText(text: "Archived tabs appear here")
            }
            ForEach(tabs.prefix(300)) { tab in
                LibraryRow(
                    icon: tab.faviconURL.flatMap { window.session?.engine.favicons.cachedImage(for: $0) },
                    symbol: "globe",
                    title: tab.title,
                    subtitle: "\(tab.url.displayHost ?? "") · \(tab.archivedAt.formatted(.relative(presentation: .named)))",
                    action: {
                        window.open(tab.url, placement: .newTab)
                        archive.remove([tab.id])
                    },
                ) {
                    IconButton("trash", label: "Remove", size: 22, symbolSize: 12) { archive.remove([tab.id]) }
                }
            }
            if !archive.tabs.isEmpty {
                Button("Clear Archive") { archive.clear() }
                    .buttonStyle(.plain)
                    .font(Typography.caption)
                    .foregroundStyle(window.palette.secondaryText)
                    .padding(.top, 6)
            }
        }
    }
}

private struct NotesList: View {
    @Bindable var window: BrowserWindowModel

    var body: some View {
        if let notes = window.session?.notes {
            let sorted = notes.notes.values.sorted { $0.updatedAt > $1.updatedAt }
            Button { window.perform(.newNote) } label: { Label("New Note", systemImage: "plus") }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.vertical, 6)
            if sorted.isEmpty {
                EmptyLibraryText(text: "No notes yet")
            }
            ForEach(sorted) { note in
                LibraryRow(
                    icon: nil,
                    symbol: "note.text",
                    title: note.displayTitle,
                    subtitle: note.updatedAt.formatted(.relative(presentation: .named)),
                    action: { open(note) },
                ) {
                    IconButton("trash", label: "Delete Note", size: 22, symbolSize: 12) { delete(note) }
                }
            }
        }
    }

    private func open(_ note: Note) {
        if let item = window.workspace.items.values.first(where: { $0.content == .note(note.id) }) {
            window.select(item.id)
        } else if let spaceID = window.state.spaceID, let itemID = try? window.store.update({ try $0.addNote(
            note.id,
            placement: .todayTop(spaceID),
        ) }) {
            window.select(itemID)
        }
        window.isShowingLibrary = false
    }

    private func delete(_ note: Note) {
        let items = window.workspace.items.values.filter { $0.content == .note(note.id) }.map(\.id)
        window.store.update { workspace in items.forEach { workspace.remove($0) } }
        window.session?.notes.delete(note.id)
    }
}

private struct BoostsList: View {
    @Bindable var window: BrowserWindowModel

    var body: some View {
        if let boosts = window.session?.boosts {
            if boosts.boosts.isEmpty {
                EmptyLibraryText(text: "Customize a site with ⌘K › Boost This Site")
            }
            ForEach(boosts.boosts) { boost in
                LibraryRow(icon: nil, symbol: "paintbrush.pointed", title: boost.name, subtitle: boost.hostPattern, action: {
                    window.open(URL(string: "https://\(boost.hostPattern.replacingOccurrences(of: "*.", with: ""))")!, placement: .newTab)
                }) {
                    Toggle("Enabled", isOn: Binding(
                        get: { boost.isEnabled },
                        set: { enabled in
                            var updated = boost
                            updated.isEnabled = enabled
                            boosts.save(updated)
                        },
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    IconButton("trash", label: "Delete Boost", size: 22, symbolSize: 12) { boosts.delete(boost.id) }
                }
            }
        }
    }
}
