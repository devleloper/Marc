import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

extension BrowserWindowModel {
    /// Splits `anchor` with a dropped sidebar tab or link, on the side it was dropped. A dropped
    /// favorite is duplicated into Today first, and so is a favorite anchor.
    func split(with payload: SidebarDragPayload.Content, anchor anchorID: SidebarItem.ID, placeBefore: Bool) {
        guard kind != .little else { return }
        if case let .item(id) = payload, id == anchorID { return }
        guard let anchor = splittableAnchor(anchorID) else { return }
        let otherID: SidebarItem.ID
        switch payload {
        case let .item(id):
            guard id != anchor, workspace.items[id]?.kind == .tab else { return }
            if workspace.items[id]?.container.section == .favorites {
                guard let duplicate = try? store.update({ try $0.duplicateTab(id) }) else { return }
                otherID = duplicate
            } else {
                otherID = id
            }
        case let .url(url):
            guard let spaceID = state.spaceID,
                  let id = try? store.update({ try $0.openTab(TabContent(url: url), placement: .todayTop(spaceID)) })
            else { return }
            runtimeTab(for: id)?.load(url, initiator: .user, transition: .link)
            otherID = id
        }
        withAnimation(Motion.surface) {
            try? store.update { try $0.split(anchor, with: otherID, axis: .horizontal, placeAfter: !placeBefore) }
        }
        select(otherID)
    }

    /// Shows or hides the split highlight while a tab is dragged over the page.
    func updateSplitDrop(placesBefore: Bool?) {
        guard splitDropPlacesBefore != placesBefore else { return }
        withAnimation(Motion.hover) { splitDropPlacesBefore = placesBefore }
    }
}

/// Drops on the content area outside web pages (the gaps, notes, empty pages) and links from other
/// apps. Over a web page, `WebContainerView` handles sidebar drags itself, because the page would
/// otherwise get them first.
struct ContentDropDelegate: DropDelegate {
    let window: BrowserWindowModel

    func validateDrop(info: DropInfo) -> Bool {
        window.selectedItem?.kind == .tab && window.kind != .little && info.hasItemsConforming(to: SidebarDragPayload.types)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let width = window.nsWindow?.contentView?.bounds.width ?? 1000
        let contentWidth = width - (window.isSidebarVisible ? window.state.sidebarWidth : 0)
        let leadingEdge = window.isSidebarVisible ? window.state.sidebarWidth : 0
        window.updateSplitDrop(placesBefore: info.location.x - leadingEdge < contentWidth / 2)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        window.updateSplitDrop(placesBefore: nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let placeBefore = window.splitDropPlacesBefore ?? false
        window.updateSplitDrop(placesBefore: nil)
        guard let anchor = window.selectedItemID else { return false }
        let window = window
        Task { @MainActor in
            guard let payload = await SidebarDragPayload.load(from: info) else { return }
            window.split(with: payload, anchor: anchor, placeBefore: placeBefore)
        }
        return true
    }
}

/// The half of the content area a dropped tab would take.
struct SplitDropHighlight: View {
    let placesBefore: Bool

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: Metrics.Content.cornerRadius, style: Metrics.Content.cornerStyle)
                .fill(Color.accentColor.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: Metrics.Content.cornerRadius, style: Metrics.Content.cornerStyle).strokeBorder(
                    Color.accentColor,
                    lineWidth: 2,
                ))
                .frame(width: proxy.size.width / 2)
                .frame(maxWidth: .infinity, alignment: placesBefore ? .leading : .trailing)
        }
        .allowsHitTesting(false)
    }
}
