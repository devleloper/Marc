import SwiftUI

/// Layout metrics. Values for the sidebar and content card were measured on Arc 1.169 and
/// are documented in docs/FEATURE_INVENTORY.md.
public enum Metrics {
    public enum Window {
        public static let minimumSize = CGSize(width: 680, height: 420)
        public static let defaultSize = CGSize(width: 1280, height: 820)
        /// Traffic lights sit 12 pt from the left edge, vertically centered on the toolbar row.
        public static let trafficLightLeading: CGFloat = 12
        public static let trafficLightCenterY: CGFloat = 23
        /// The Little window's single bar, which also holds its traffic lights.
        public static let littleToolbarHeight: CGFloat = 38
    }

    public enum Sidebar {
        public static let defaultWidth: CGFloat = 250
        public static let minimumWidth: CGFloat = 200
        public static let maximumWidth: CGFloat = 400
        public static let inset: CGFloat = 8
        public static let toolbarHeight: CGFloat = 46
        public static let toolbarButtonSize: CGFloat = 32
        public static let rowHeight: CGFloat = 36
        public static let rowSpacing: CGFloat = 5
        public static let rowCornerRadius: CGFloat = 10
        public static let iconSize: CGFloat = 16
        public static let iconLeading: CGFloat = 10
        public static let titleLeading: CGFloat = 10
        public static let addressFieldHeight: CGFloat = 36
        public static let favoriteTileHeight: CGFloat = 47
        public static let favoriteSpacing: CGFloat = 8
        public static let favoriteCornerRadius: CGFloat = 10
        public static let maximumFavoriteColumns = 4
        public static let footerHeight: CGFloat = 50
        public static let nestingIndent: CGFloat = 16
        /// Hot zone on the window's leading edge that reveals a hidden sidebar.
        public static let revealZoneWidth: CGFloat = 10
    }

    public enum Content {
        public static let inset: CGFloat = 10
        /// Arc's page card uses circular (not continuous) 6 pt corners.
        public static let cornerRadius: CGFloat = 6
        public static let cornerStyle: RoundedCornerStyle = .circular
        public static let splitSpacing: CGFloat = 8
    }

    public enum CommandBar {
        public static let width: CGFloat = 765
        public static let fieldHeight: CGFloat = 63
        /// Result rows are 46 pt tall on a 50 pt pitch.
        public static let rowHeight: CGFloat = 46
        public static let rowSpacing: CGFloat = 4
        public static let resultsInsets = EdgeInsets(top: 6, leading: 9, bottom: 10, trailing: 9)
        public static let fieldLeading: CGFloat = 22
        /// Circular corners, like the page card.
        public static let cornerRadius: CGFloat = 12
        public static let rowCornerRadius: CGFloat = 8
        /// The panel's top edge sits at about a third of the window height.
        public static let verticalPosition: CGFloat = 0.34
        public static let maximumVisibleRows = 8
    }

    public enum Popover {
        public static let cornerRadius: CGFloat = 12
        public static let padding: CGFloat = 12
    }
}

/// Fixed Command Bar colors measured on Arc (dark appearance).
public enum CommandBarColors {
    public static let darkBackground = Color(red: 0x30 / 255, green: 0x30 / 255, blue: 0x2F / 255)
    public static let lightBackground = Color.white
    public static let selection = Color(red: 0x47 / 255, green: 0x4D / 255, blue: 0xD4 / 255)
}

public enum Typography {
    public static let tabTitle = Font.system(size: 14)
    public static let rowLabel = Font.system(size: 14)
    public static let sectionHeader = Font.system(size: 13, weight: .semibold)
    public static let addressHost = Font.system(size: 14)
    public static let addressDetail = Font.system(size: 12)
    public static let caption = Font.system(size: 11, weight: .semibold)
    public static let commandField = Font.system(size: 18)
    public static let commandRow = Font.system(size: 14, weight: .medium)
    public static let commandDetail = Font.system(size: 13)
    public static let body = Font.system(size: 13)
    public static let title = Font.system(size: 22, weight: .bold)
}

/// Animation primitives. Curves were fitted to frame-by-frame recordings of Arc.
public enum Motion {
    /// Sidebar show/hide: ease-out quart, 100 ms.
    public static let sidebarToggle = Animation.timingCurve(0.25, 1, 0.5, 1, duration: 0.1)
    /// Space paging: ease-out expo, 300 ms.
    public static let spacePage = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.3)
    public static let hover = Animation.easeOut(duration: 0.08)
    /// Rows inserting, moving or disappearing in the sidebar.
    public static let listChange = Animation.spring(response: 0.28, dampingFraction: 0.88)
    /// Peek cards, popovers and other floating surfaces.
    public static let surface = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// Favicons fade in once a page has landed.
    public static let fadeIn = Animation.easeOut(duration: 0.2)
    public static let toast = Animation.spring(response: 0.35, dampingFraction: 0.82)

    /// Honors Reduce Motion by replacing movement with a short fade.
    public static func accessible(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : animation
    }
}
