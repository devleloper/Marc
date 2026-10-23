import AppKit
import MarcCore
import MarcWebKit
import SwiftUI

/// The Settings window.
public struct SettingsView: View {
    @Bindable var session: BrowserSession
    @Binding var pane: SettingsPane

    public init(session: BrowserSession, pane: Binding<SettingsPane>) {
        self.session = session
        _pane = pane
    }

    public var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(get: { pane }, set: { if let value = $0 { pane = value } })) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch pane {
                case .general: GeneralSettings(session: session)
                case .profiles: ProfilesSettings(session: session)
                case .search: SearchSettings(session: session)
                case .privacy: PrivacySettings(session: session)
                case .passwords: PasswordsSettings(session: session)
                case .extensions: ExtensionsSettings(session: session)
                case .ai: AISettings(session: session)
                case .shortcuts: ShortcutsSettings()
                case .advanced: AdvancedSettings(session: session)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(pane.title)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

private struct GeneralSettings: View {
    @Bindable var session: BrowserSession

    private var settings: Binding<BrowserSettings> {
        Bindable(session.settings).settings
    }

    @State private var isDefault = DefaultBrowser.isDefault

    var body: some View {
        Form {
            Section {
                LabeledContent("Default browser") {
                    if isDefault {
                        Label("Marc is your default browser", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Make Marc the Default Browser") {
                            DefaultBrowser.request()
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                isDefault = DefaultBrowser.isDefault
                            }
                        }
                    }
                }
                Toggle("Open links from other apps in a Little window", isOn: settings.opensExternalLinksInLittleWindow)
            }
            Section("Tabs") {
                Picker("Archive unpinned tabs", selection: settings.archiveInterval) {
                    ForEach(ArchiveInterval.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Unload inactive tabs", selection: settings.memorySaverInterval) {
                    ForEach(MemorySaverInterval.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Show link address when hovering", isOn: settings.showsHoveredLinkStatus)
            }
            Section("Websites") {
                Picker("Website appearance", selection: settings.websiteAppearance) {
                    ForEach(WebsiteAppearance.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section {
                AppIconPicker(selection: settings.appIcon)
            } header: {
                Text("App Icon")
            } footer: {
                Text("Marc shows this icon in the Dock while it's open. When Marc is closed, the Dock and Finder show the standard icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Import from Another Browser…") {
                    session.keyWindow?.isShowingImport = true
                    session.keyWindow?.nsWindow?.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
}

private struct ProfilesSettings: View {
    @Bindable var session: BrowserSession
    @State private var deleting: Profile?
    @State private var replacement: Profile.ID?

    var body: some View {
        Form {
            Section {
                ForEach(session.store.workspace.orderedProfiles) { profile in
                    HStack {
                        Image(systemName: profile.symbol)
                        TextField("Name", text: Binding(
                            get: { session.store.workspace.profiles[profile.id]?.name ?? profile.name },
                            set: { name in try? session.store.update { try $0.updateProfile(profile.id) { $0.name = name } } },
                        ))
                        .textFieldStyle(.plain)
                        Spacer()
                        Text("\(session.store.workspace.spaces(in: profile.id).count) Spaces").foregroundStyle(.secondary)
                        Button(role: .destructive) { deleting = profile } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .disabled(session.store.workspace.profiles.count < 2)
                    }
                }
                Button("Add Profile") {
                    session.store.update { _ = $0.addProfile(name: "Profile \($0.profiles.count + 1)") }
                }
            } footer: {
                Text(
                    """
                    Each profile keeps its own cookies, history, passwords and extensions. Assign a profile to a Space \
                    from the Space's menu.
                    """,
                )
            }
        }
        .sheet(item: $deleting) { profile in
            VStack(alignment: .leading, spacing: 14) {
                Text("Delete “\(profile.name)”?").font(.headline)
                Text("Its cookies, history, saved passwords and downloads list are deleted. Its Spaces move to:")
                Picker("Move Spaces to", selection: $replacement) {
                    ForEach(session.store.workspace.orderedProfiles.filter { $0.id != profile.id }) { other in
                        Text(other.name).tag(Profile.ID?.some(other.id))
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { deleting = nil }
                    Button("Delete Profile", role: .destructive) {
                        if let replacement { Task { await session.deleteProfile(profile.id, reassigningTo: replacement) } }
                        deleting = nil
                    }
                    .disabled(replacement == nil)
                }
            }
            .padding(20)
            .frame(width: 400)
            .onAppear { replacement = session.store.workspace.orderedProfiles.first { $0.id != profile.id }?.id }
        }
    }
}

private struct SearchSettings: View {
    @Bindable var session: BrowserSession

    private var settings: Binding<BrowserSettings> {
        Bindable(session.settings).settings
    }

    var body: some View {
        Form {
            Picker("Search engine", selection: settings.searchEngineID) {
                ForEach(SearchEngine.builtIn) { Text($0.name).tag($0.id) }
            }
            Toggle("Show search suggestions", isOn: settings.showsSearchSuggestions)
            Section("Site search") {
                ForEach(SearchEngine.siteSearches) { engine in
                    LabeledContent(engine.name, value: engine.keyword ?? "")
                }
            }
            .help("Type the site's name in the Command Bar and press Tab to search it.")
        }
    }
}

private struct PrivacySettings: View {
    @Bindable var session: BrowserSession

    private var settings: Binding<BrowserSettings> {
        Bindable(session.settings).settings
    }

    @State private var siteSettings: [SiteSettings] = []
    @State private var permissions: [SitePermission] = []
    @State private var clearRange = 0
    @State private var message: String?

    var body: some View {
        Form {
            Section("Content blocking") {
                Toggle("Block ads and trackers", isOn: settings.isContentBlockingEnabled)
                LabeledContent("Status") { Text(blockerStatus).foregroundStyle(.secondary) }
                Button("Update Filter Lists Now") {
                    Task { await session.engine.contentBlocker.refresh(sources: session.enabledFilterLists) }
                }
                .disabled(!session.settings.settings.isContentBlockingEnabled)
                Text("Filter lists from easylist.to are downloaded and converted on this Mac.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Browsing data") {
                Picker("Clear", selection: $clearRange) {
                    Text("Last hour").tag(0)
                    Text("Today").tag(1)
                    Text("All time").tag(2)
                }
                Button("Clear History and Website Data…", role: .destructive) { clear() }
                if let message { Text(message).foregroundStyle(.secondary) }
            }
            Section("Site settings") {
                if siteSettings.isEmpty, permissions.isEmpty {
                    Text("No site has custom settings.").foregroundStyle(.secondary)
                }
                ForEach(permissions, id: \.self) { permission in
                    LabeledContent(
                        permission.host,
                        value: "\(permission.kind.displayName): \(permission.decision == .allow ? "Allow" : "Deny")",
                    )
                }
                ForEach(siteSettings, id: \.host) { settings in
                    LabeledContent(settings.host, value: description(of: settings))
                }
            }
        }
        .task { await loadSiteData() }
    }

    private var blockerStatus: String {
        switch session.engine.contentBlocker.status {
        case .idle: return "Idle"
        case .updating: return "Updating…"
        case let .ready(count, updatedAt):
            let lists = count == 1 ? "1 rule list" : "\(count) rule lists"
            let updated = updatedAt.map { ", updated \($0.formatted(.relative(presentation: .named)))" } ?? ""
            return "\(lists) active\(updated)"
        case let .failed(message): return "Failed: \(message)"
        }
    }

    private func description(of settings: SiteSettings) -> String {
        var parts: [String] = []
        if let zoom = settings.zoom { parts.append("Zoom \(Int(zoom * 100))%") }
        if settings.isContentBlockingEnabled == false { parts.append("Blocking off") }
        return parts.joined(separator: ", ")
    }

    private func loadSiteData() async {
        guard let profile = session.keyWindow?.profile else { return }
        let services = session.profileServices(for: profile)
        siteSettings = await (try? services.siteData.allSettings()) ?? []
        permissions = await (try? services.siteData.allPermissions()) ?? []
    }

    private func clear() {
        let since: Date = switch clearRange {
        case 0: .now.addingTimeInterval(-3600)
        case 1: Calendar.current.startOfDay(for: .now)
        default: .distantPast
        }
        Task {
            for profile in session.store.workspace.orderedProfiles {
                let services = session.profileServices(for: profile)
                try? await services.history.deleteVisits(in: DateInterval(start: since, end: .now.addingTimeInterval(60)))
                await session.engine.context(for: profile).removeAllData(modifiedSince: since)
            }
            message = "Cleared."
        }
    }
}

private struct ExtensionsSettings: View {
    @Bindable var session: BrowserSession

    var body: some View {
        ExtensionsManagerView(session: session)
    }
}

private struct ShortcutsSettings: View {
    private let commands: [BrowserCommand] = [
        .newTab, .openLocation, .newWindow, .newIncognitoWindow, .newLittleWindow, .archiveTab, .restoreClosedTab,
        .toggleSidebar, .pinTab, .clearToday, .nextTab, .previousTab, .nextSpace, .previousSpace, .addSplit,
        .closeSplitPane, .copyURL, .copyURLAsMarkdown, .find, .reload, .goBack, .goForward, .showHistory,
        .showLibrary, .showDownloads, .newNote, .zoomIn, .zoomOut, .actualSize, .viewSource, .settings,
    ]

    var body: some View {
        Form {
            ForEach(commands, id: \.self) { command in
                LabeledContent(command.title, value: command.keyboardShortcut?.displayString ?? "")
            }
            LabeledContent("Switch to Space 1–9", value: "⌃1 … ⌃9")
            LabeledContent("Select tab 1–9", value: "⌘1 … ⌘9")
        }
    }
}

private struct AdvancedSettings: View {
    @Bindable var session: BrowserSession

    var body: some View {
        Form {
            Section("Updates") {
                Button("Check for Updates…") { session.checkForUpdates?() }
            }
            Section("Developers") {
                Text(
                    """
                    Every page can be inspected with Safari's Web Inspector: enable Safari › Settings › Advanced › Show \
                    features for web developers, then use Safari's Develop menu.
                    """,
                )
                .foregroundStyle(.secondary)
            }
            Section("Onboarding") {
                Button("Show Welcome Again") { session.settings.settings.hasCompletedOnboarding = false }
            }
        }
    }
}
