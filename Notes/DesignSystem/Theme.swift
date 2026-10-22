//
//  Theme.swift
//  Notes
//
//  Responsibility: Single source of truth for colours, spacing, fonts, and corner radii across the app.
//  Follows system light/dark mode so both appearances stay readable.
//  Dependencies: SwiftUI.
//

import SwiftUI

public enum Theme {
    public enum Spacing {
        public static let xSmall: CGFloat = 4
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 12
        public static let large: CGFloat = 20
        public static let xLarge: CGFloat = 32
    }

    public enum CornerRadius {
        public static let small: CGFloat = 6
        public static let medium: CGFloat = 10
        public static let page: CGFloat = 4
    }

    public enum Thumbnail {
        public static let width: CGFloat = 44
        public static let height: CGFloat = 62
        public static let lineSpacing: CGFloat = 8
    }

    public enum Colors {
        public static let canvasWorkspaceBackground = Color(uiColor: .secondarySystemBackground)
        public static let pageBackground = Color(uiColor: .systemBackground)
        public static let pageBorder = Color(uiColor: .separator)
        public static let paperRuleLine = Color.primary.opacity(0.16)
        public static let paperMarginLine = Color.red.opacity(0.28)
        public static let selectedThumbnailBorder = Color.accentColor
    }

    public enum Fonts {
        public static let pageHeader = Font.headline
        public static let rowTitle = Font.body
        public static let rowSubtitle = Font.caption
        public static let badge = Font.caption2.weight(.medium)
    }
}
