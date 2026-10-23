import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// The centered Command Bar. It appears without animation, as Arc's does, and leaves the page
/// undimmed.
struct CommandBarView: View {
    @Bindable var model: CommandBarModel
    let window: BrowserWindowModel
    @FocusState private var isFocused: Bool
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let site = model.siteSearch {
                    Text(site.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(red: 0.27, green: 0.28, blue: 0.82)))
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                TextField(placeholder, text: $model.query)
                    .textFieldStyle(.plain)
                    .font(Typography.commandField)
                    .focused($isFocused)
                    .onSubmit { model.activateSelection() }
                    .onKeyPress(.upArrow) {
                        model.moveSelection(by: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        model.moveSelection(by: 1)
                        return .handled
                    }
                    .onKeyPress(.tab) { model.handleTab() ? .handled : .ignored }
                    .onKeyPress(.delete) { model.handleDeleteBackward() ? .handled : .ignored }
                    .onExitCommand { window.dismissCommandBar() }
                    .accessibilityIdentifier("commandBarField")
            }
            .padding(.horizontal, 18)
            .frame(height: Metrics.CommandBar.fieldHeight)

            if !model.results.isEmpty {
                Divider().opacity(0.4)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                                CommandBarRow(result: result, isSelected: index == model.selectedIndex, window: window)
                                    .id(result.id)
                                    .onTapGesture { model.activate(result) }
                                    .onHover { if $0 { model.selectedIndex = index } }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: Metrics.CommandBar.rowHeight * CGFloat(Metrics.CommandBar.maximumVisibleRows) + 16)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: model.selectedIndex) { _, index in
                        if model.results.indices.contains(index) { proxy.scrollTo(model.results[index].id) }
                    }
                }
            }
        }
        .frame(width: Metrics.CommandBar.width)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.CommandBar.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.CommandBar.cornerRadius, style: .continuous).strokeBorder(
            .primary.opacity(0.1),
            lineWidth: 0.5,
        ))
        .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
        .onAppear { isFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command Bar")
        .accessibilityIdentifier("commandBar")
    }

    private var placeholder: String {
        if let site = model.siteSearch { return "Search \(site.name)…" }
        switch model.placement {
        case .newTab: return "Search or Enter URL…"
        case .currentTab: return "Search or Enter URL…"
        case .split: return "Open in Split View…"
        }
    }
}

private struct CommandBarRow: View {
    let result: CommandBarResult
    let isSelected: Bool
    let window: BrowserWindowModel

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 20, height: 20)
            HStack(spacing: 6) {
                Text(title)
                    .font(Typography.commandRow)
                    .lineLimit(1)
                if let subtitle {
                    Text("— \(subtitle)")
                        .font(Typography.commandDetail)
                        .foregroundStyle(isSelected ? .white.opacity(0.75) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 12)
        .frame(height: Metrics.CommandBar.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Metrics.CommandBar.rowCornerRadius, style: .continuous)
                .fill(isSelected ? Color(red: 0.27, green: 0.28, blue: 0.82) : .clear),
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var title: String {
        switch result {
        case let .navigate(url): url.displayString
        case let .search(query, _): query
        case let .suggestion(text, _): text
        case let .tab(tab): tab.title.isEmpty ? (tab.url?.displayString ?? "Tab") : tab.title
        case let .history(page): page.title.isEmpty ? page.url.displayString : page.title
        case let .command(command): command.title
        case let .searchSite(engine): "Search \(engine.name)"
        }
    }

    private var subtitle: String? {
        switch result {
        case .navigate: nil
        case let .search(_, engine): "Search \(engine.name)"
        case .suggestion: nil
        case let .tab(tab): tab.url?.displayString
        case let .history(page): page.url.displayString
        case .command: nil
        case .searchSite: "Press Tab"
        }
    }

    @ViewBuilder private var icon: some View {
        switch result {
        case .navigate:
            Image(systemName: "globe").font(.system(size: 14))
        case .search, .suggestion, .searchSite:
            Image(systemName: "magnifyingglass").font(.system(size: 14))
        case let .tab(tab):
            FaviconView(
                image: tab.faviconURL.flatMap { window.session?.engine.favicons.cachedImage(for: $0) },
                fallbackTitle: tab.title,
                size: 16,
            )
        case let .history(page):
            FaviconView(image: nil, fallbackTitle: page.url.displayHost ?? page.title, size: 16)
        case let .command(command):
            Image(systemName: command.symbol).font(.system(size: 14))
        }
    }

    @ViewBuilder private var trailing: some View {
        switch result {
        case .tab:
            HStack(spacing: 6) {
                Text("Switch to Tab").font(.system(size: 12, weight: .medium))
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(isSelected ? 0.25 : 0.08)))
            }
            .opacity(isSelected ? 1 : 0.55)
        case let .command(command):
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .opacity(0.6)
            }
        case .searchSite:
            Text("⇥").font(.system(size: 13, weight: .semibold)).opacity(0.6)
        default:
            EmptyView()
        }
    }
}
