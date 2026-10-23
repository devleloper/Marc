import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Native pages shown for `marc://` tabs.
struct InternalPageView: View {
    @Bindable var window: BrowserWindowModel
    let page: InternalPage

    var body: some View {
        Group {
            switch page {
            case .history: HistoryPageView(window: window)
            case .archive: ArchivePageView(window: window)
            case .downloads: DownloadsPageView(window: window)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct PageHeader<Trailing: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(.tint)
            Text(title).font(Typography.title)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }
}

/// History grouped by day with full-text search and deletion.
struct HistoryPageView: View {
    @Bindable var window: BrowserWindowModel
    @State private var query = ""
    @State private var visits: [HistoryVisit] = []
    @State private var selection = Set<Int64>()
    @State private var isLoading = false
    @State private var canLoadMore = true

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "History", symbol: "clock.arrow.circlepath") {
                TextField("Search History", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Menu("Clear History") {
                    Button("Last Hour") { clear(since: Date.now.addingTimeInterval(-3600)) }
                    Button("Today") { clear(since: Calendar.current.startOfDay(for: .now)) }
                    Button("Today and Yesterday") { clear(since: Calendar.current.date(
                        byAdding: .day,
                        value: -1,
                        to: Calendar.current.startOfDay(for: .now),
                    )!) }
                    Divider()
                    Button("All History", role: .destructive) { clearAll() }
                }
                .fixedSize()
            }
            if window.kind == .incognito {
                ContentUnavailableView(
                    "History Is Off",
                    systemImage: "eyeglasses",
                    description: Text("Incognito windows don't save history."),
                )
            } else {
                List(selection: $selection) {
                    ForEach(groupedVisits, id: \.day) { group in
                        Section(group.day.formatted(date: .complete, time: .omitted)) {
                            ForEach(group.visits) { visit in
                                HistoryRow(window: window, visit: visit)
                                    .tag(visit.id)
                                    .onAppear { if visit.id == visits.last?.id { loadMore() } }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .onDeleteCommand(perform: deleteSelection)
                .contextMenu(forSelectionType: Int64.self) { ids in
                    Button("Open in New Tab") { open(ids) }
                    Button("Delete", role: .destructive) { delete(ids) }
                } primaryAction: { ids in
                    open(ids)
                }
                .overlay {
                    if visits.isEmpty, !isLoading {
                        ContentUnavailableView(query.isEmpty ? "No History" : "No Results", systemImage: "clock")
                    }
                }
            }
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(150))
            await reload()
        }
    }

    private var services: ProfileServices? {
        guard let session = window.session, let profile = window.profile, window.kind != .incognito else { return nil }
        return session.profileServices(for: profile)
    }

    private var groupedVisits: [(day: Date, visits: [HistoryVisit])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: visits) { calendar.startOfDay(for: $0.visitedAt) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    private func reload() async {
        guard let services else { return }
        isLoading = true
        visits = await (try? services.history.visits(matching: query.isEmpty ? nil : query, before: nil, limit: 200)) ?? []
        canLoadMore = visits.count == 200
        isLoading = false
    }

    private func loadMore() {
        guard canLoadMore, !isLoading, let services, let last = visits.last else { return }
        isLoading = true
        Task {
            let more = await (try? services.history.visits(matching: query.isEmpty ? nil : query, before: last.visitedAt, limit: 200)) ?? []
            visits += more
            canLoadMore = more.count == 200
            isLoading = false
        }
    }

    private func open(_ ids: Set<Int64>) {
        for visit in visits where ids.contains(visit.id) {
            window.open(visit.url, placement: .newTab)
        }
    }

    private func delete(_ ids: Set<Int64>) {
        guard let services else { return }
        visits.removeAll { ids.contains($0.id) }
        Task { try? await services.history.deleteVisits(Array(ids)) }
    }

    private func deleteSelection() {
        delete(selection)
        selection.removeAll()
    }

    private func clear(since date: Date) {
        guard let services else { return }
        Task {
            try? await services.history.deleteVisits(in: DateInterval(start: date, end: .now.addingTimeInterval(60)))
            await reload()
        }
    }

    private func clearAll() {
        guard let services else { return }
        Task {
            try? await services.history.deleteAll()
            await reload()
        }
    }
}

private struct HistoryRow: View {
    let window: BrowserWindowModel
    let visit: HistoryVisit

    var body: some View {
        HStack(spacing: 10) {
            Text(visit.visitedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(visit.title.isEmpty ? visit.url.displayString : visit.title)
                .lineLimit(1)
            Text(visit.url.displayHost ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .font(.system(size: 13))
        .padding(.vertical, 2)
    }
}

/// Archived tabs with search and restore.
struct ArchivePageView: View {
    @Bindable var window: BrowserWindowModel
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Archive", symbol: "archivebox") {
                TextField("Search Archive", text: $query).textFieldStyle(.roundedBorder).frame(width: 260)
                Button("Clear Archive", role: .destructive) { window.session?.archive.clear() }
            }
            let tabs = (window.session?.archive.tabs ?? []).filter {
                query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.absoluteString
                    .localizedCaseInsensitiveContains(query)
            }
            List(tabs) { tab in
                HStack(spacing: 10) {
                    Text(tab.title).lineLimit(1)
                    Text(tab.url.displayHost ?? "").foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(tab.archivedAt.formatted(.relative(presentation: .named))).foregroundStyle(.secondary).font(.system(size: 11))
                    Button("Restore") {
                        window.open(tab.url, placement: .newTab)
                        window.session?.archive.remove([tab.id])
                    }
                }
                .font(.system(size: 13))
            }
            .listStyle(.inset)
            .overlay {
                if tabs.isEmpty {
                    ContentUnavailableView(
                        "Nothing Archived",
                        systemImage: "archivebox",
                        description: Text("Tabs you close and Today tabs that expire are kept here."),
                    )
                }
            }
        }
    }
}

/// All downloads with progress and actions.
struct DownloadsPageView: View {
    @Bindable var window: BrowserWindowModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Downloads", symbol: "arrow.down.circle") {
                Button("Clear Finished") { window.session?.downloads.clearFinished() }
            }
            let downloads = window.session?.downloads.downloads ?? []
            List(downloads) { download in
                HStack(spacing: 12) {
                    Image(nsImage: download.fileURL.map { NSWorkspace.shared.icon(forFile: $0.path(percentEncoded: false)) } ?? NSWorkspace
                        .shared.icon(for: .data))
                        .resizable()
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(download.fileName).lineLimit(1)
                        if let fraction = download.state.fractionCompleted {
                            ProgressView(value: fraction).frame(maxWidth: 240)
                        } else {
                            Text(download.sourceURL?.displayHost ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if download.state.isActive {
                        Button("Cancel") { window.session?.downloads.cancel(download.id) }
                    } else if download.state == .finished {
                        Button("Open") { window.session?.downloads.open(download.id) }
                        Button { window.session?.downloads.reveal(download.id) } label: { Image(systemName: "magnifyingglass") }
                    } else {
                        Text(download.state == .cancelled ? "Cancelled" : "Failed").foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 13))
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
            .overlay {
                if downloads.isEmpty {
                    ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle")
                }
            }
        }
    }
}
