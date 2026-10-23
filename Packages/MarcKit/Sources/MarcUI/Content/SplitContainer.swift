import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// Lays out the panes of a split as separate content cards with draggable gaps between them.
struct SplitContainer: View {
    @Bindable var window: BrowserWindowModel
    let splitID: SidebarItem.ID
    let layout: SplitLayout

    var body: some View {
        SplitNodeView(window: window, splitID: splitID, node: layout.root, path: [])
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Split view")
    }
}

private struct SplitNodeView: View {
    @Bindable var window: BrowserWindowModel
    let splitID: SidebarItem.ID
    let node: SplitLayout.Node
    let path: [Int]

    var body: some View {
        switch node {
        case let .pane(paneID):
            ContentCard(isFocused: window.selectedItemID == paneID) {
                PaneContent(window: window, itemID: paneID)
            }
            .overlay(alignment: .top) {
                PaneHeader(window: window, paneID: paneID)
            }
        case let .group(group):
            GeometryReader { proxy in
                let isHorizontal = group.axis == .horizontal
                let total = (isHorizontal ? proxy.size.width : proxy.size.height) - Metrics.Content
                    .splitSpacing * CGFloat(group.children.count - 1)
                let layout = isHorizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    ForEach(Array(group.children.enumerated()), id: \.offset) { index, child in
                        let length = max(total * group.fractions[index], 80)
                        SplitNodeView(window: window, splitID: splitID, node: child, path: path + [index])
                            .frame(width: isHorizontal ? length : nil, height: isHorizontal ? nil : length)
                        if index < group.children.count - 1 {
                            SplitDivider(axis: group.axis) { translation in
                                resize(group: group, index: index, translation: translation, total: total)
                            }
                        }
                    }
                }
            }
        }
    }

    private func resize(group: SplitLayout.Group, index: Int, translation: CGFloat, total: CGFloat) {
        let pair = group.fractions[index] + group.fractions[index + 1]
        let leading = (group.fractions[index] * total + translation) / (pair * total)
        try? window.store.update { workspace in
            try workspace.updateSplitLayout(splitID) { $0.resizeDivider(groupPath: path, index: index, fraction: leading) }
        }
    }
}

/// The gap between panes; dragging it resizes the neighbors.
private struct SplitDivider: View {
    let axis: SplitLayout.Axis
    let onDrag: (CGFloat) -> Void
    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(
                width: axis == .horizontal ? Metrics.Content.splitSpacing : nil,
                height: axis == .vertical ? Metrics.Content.splitSpacing : nil,
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let translation = axis == .horizontal ? value.translation.width : value.translation.height
                        onDrag(translation - lastTranslation)
                        lastTranslation = translation
                    }
                    .onEnded { _ in lastTranslation = 0 },
            )
            .accessibilityLabel("Resize split")
    }
}

/// A hover strip at the top of a pane with pane-level actions.
private struct PaneHeader: View {
    @Bindable var window: BrowserWindowModel
    let paneID: SidebarItem.ID
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 2) {
            Spacer()
            if isHovered {
                Button { separate() } label: { Image(systemName: "rectangle.portrait.and.arrow.right") }
                    .help("Separate from Split View")
                Button { close() } label: { Image(systemName: "xmark") }
                    .help("Close Split Pane")
            }
        }
        .buttonStyle(.pressable)
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background {
            if isHovered {
                Rectangle().fill(.regularMaterial)
            }
        }
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: Metrics.Content.cornerRadius,
            topTrailingRadius: Metrics.Content.cornerRadius,
            style: Metrics.Content.cornerStyle,
        ))
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(Motion.hover) { isHovered = hovering } }
    }

    private func separate() {
        try? window.store.update { try $0.separateFromSplit(paneID) }
    }

    private func close() {
        window.select(paneID)
        window.closeSelected()
    }
}
