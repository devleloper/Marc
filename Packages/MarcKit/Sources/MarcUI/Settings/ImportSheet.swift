import AppKit
import MarcCore
import MarcWebKit
import SwiftUI
import UniformTypeIdentifiers

/// Imports Spaces, bookmarks and history from another browser. Files are chosen in an open
/// panel (preselected at the browser's usual location) so the sandbox grants access to exactly
/// those files.
struct ImportSheet: View {
    @Bindable var window: BrowserWindowModel
    @Environment(\.dismiss) private var dismiss
    @State private var source = BrowserImport.Source.arc
    @State private var includeHistory = true
    @State private var status: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Browser Data").font(.system(size: 18, weight: .bold))
            Picker("Import from", selection: $source) {
                ForEach(BrowserImport.Source.allCases, id: \.self) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .pickerStyle(.radioGroup)
            Text(description).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if source == .chrome || source == .safari {
                Toggle("Also import history", isOn: $includeHistory)
            }
            if let status {
                Text(status).font(.system(size: 12)).foregroundStyle(status.hasPrefix("Imported") ? Color.secondary : .orange)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                Button("Choose File…") { chooseFile() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private var description: String {
        switch source {
        case .arc: """
            Choose Arc's StorableSidebar.json (in ~/Library/Application Support/Arc). Spaces, pinned tabs, \
            folders, split views and favorites are imported.
            """
        case .chrome: """
            Choose Chrome's Bookmarks file (in ~/Library/Application Support/Google/Chrome/Default). You'll then \
            be asked for the History file.
            """
        case .safari: """
            Choose Safari's Bookmarks.plist (in ~/Library/Safari). You'll then be asked for History.db. \
            Passwords are never imported.
            """
        case .bookmarksFile: "Choose an HTML bookmarks file exported from any browser."
        }
    }

    private func chooseFile() {
        guard let nsWindow = window.nsWindow, let session = window.session, let spaceID = window.state.spaceID else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if let location = session.services.importers.suggestedLocation(source) {
            panel.directoryURL = location.deletingLastPathComponent()
        }
        panel.message = "Choose the \(source.displayName) file to import"
        panel.beginSheetModal(for: nsWindow) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await importFile(url, session: session, spaceID: spaceID) }
        }
    }

    private func importFile(_ url: URL, session: BrowserSession, spaceID: Space.ID) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let data = try Data(contentsOf: url)
            var imported: BrowserImport = switch source {
            case .arc: try ArcSidebarParser().parse(data)
            case .chrome: try BrowserImport(source: .chrome, bookmarks: ChromeBookmarksParser().parse(data))
            case .safari: try BrowserImport(source: .safari, bookmarks: SafariBookmarksParser().parse(data))
            case .bookmarksFile: try BrowserImport(source: .bookmarksFile, bookmarks: NetscapeBookmarksParser().parse(data))
            }
            if includeHistory, source == .chrome || source == .safari, let historyURL = await chooseHistoryFile() {
                imported.history = (try? session.services.importers.readHistory(source, historyURL)) ?? []
            }
            let summary = try window.store.update { try $0.apply(imported, targetSpace: spaceID) }
            Task { await session.fillMissingFavicons() }
            if !imported.history.isEmpty, let profile = window.profile {
                try? await session.profileServices(for: profile).history.importPages(imported.history)
            }
            let counts = [
                "\(summary.tabs) tabs", "\(summary.folders) folders", "\(summary.spaces) Spaces",
                "\(summary.favorites) favorites", "\(summary.historyEntries) history entries",
            ]
            status = "Imported " + counts.formatted(.list(type: .and))
        } catch BrowserImportError.nothingToImport {
            status = "That file doesn't contain anything to import."
        } catch {
            status = "That file couldn't be read as \(source.displayName) data."
        }
    }

    private func chooseHistoryFile() async -> URL? {
        guard let nsWindow = window.nsWindow, let session = window.session else { return nil }
        let panel = NSOpenPanel()
        panel.message = "Choose the \(source.displayName) History file"
        panel.showsHiddenFiles = true
        let location = session.services.importers.suggestedLocation(source == .chrome ? .chrome : .safari)
        panel.directoryURL = location?.deletingLastPathComponent()
        return await panel.beginSheetModal(for: nsWindow) == .OK ? panel.url : nil
    }
}
