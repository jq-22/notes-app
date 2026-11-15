//
//  Theme.swift
//  Notes
//
//  Responsibility: Single source of truth for colours, spacing, fonts, corner radii, and shadows across the app.
//  Follows system light/dark mode and 8pt spatial grid tokens.
//  Dependencies: SwiftUI.
//

import SwiftUI

public enum Theme {
    // MARK: - 8pt Spatial Grid Spacing
    public enum Spacing {
        /// 4pt: Sub-grid half-step for micro-spacings (hairlines, badges, compact dividers)
        public static let xSmall: CGFloat = 4
        /// 8pt: Base 1x grid token
        public static let small: CGFloat = 8
        /// 16pt: Standard 2x grid token (standardized from 12pt)
        public static let medium: CGFloat = 16
        /// 24pt: Standard 3x grid token (standardized from 20pt)
        public static let large: CGFloat = 24
        /// 32pt: Standard 4x grid token
        public static let xLarge: CGFloat = 32

        // Explicit grid multiples
        public static let grid8: CGFloat = 8
        public static let grid16: CGFloat = 16
        public static let grid24: CGFloat = 24
        public static let grid32: CGFloat = 32
    }

    // MARK: - Standardized Corner Radii
    public enum CornerRadius {
        /// 16pt: Page thumbnails in sidebar
        public static let pageThumbnail: CGFloat = 16
        /// 16pt: Alias for pageThumbnail
        public static let thumbnail: CGFloat = 16
        /// 12pt: Notion-style page link cards
        public static let linkCard: CGFloat = 12
        /// 8pt: Table column/row divider handles
        public static let tableHandle: CGFloat = 8
        /// 8pt: Floating action pills and toolbars
        public static let floatingPill: CGFloat = 8

        // Semantic & Legacy aliases
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 12
        public static let page: CGFloat = 4
    }

    // MARK: - Sidebar Thumbnail Metrics
    public enum Thumbnail {
        public static let width: CGFloat = 44
        public static let height: CGFloat = 62
        public static let lineSpacing: CGFloat = 8
    }

    // MARK: - Light / Dark Dynamic Colors
    public enum Colors {
        public static let canvasWorkspaceBackground = Color(uiColor: .secondarySystemBackground)
        public static let pageBackground = Color(uiColor: .systemBackground)
        public static let pageBorder = Color(uiColor: .separator)
        public static let paperRuleLine = Color.primary.opacity(0.16)
        public static let paperMarginLine = Color.red.opacity(0.28)
        public static let selectedThumbnailBorder = Color.accentColor

        // R2 & R3 Dynamic Tokens
        public static let cardBorder = Color.primary.opacity(0.12)
        public static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
        public static let floatingChromeBackground = Color(uiColor: .systemBackground)
        public static let floatingChromeBorder = Color(uiColor: .separator)
        public static let handleFill = Color(uiColor: .systemBackground)
        public static let handleBorder = Color.accentColor
        public static let handleIcon = Color.accentColor
    }

    // MARK: - Elevation & Shadow Tokens
    public enum Shadows {
        public struct ShadowToken: Equatable, Sendable {
            public let color: Color
            public let radius: CGFloat
            public let x: CGFloat
            public let y: CGFloat

            public init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
                self.color = color
                self.radius = radius
                self.x = x
                self.y = y
            }
        }

        /// Subtle card / badge shadow (link cards, page thumbnails)
        public static let subtleCard = ShadowToken(
            color: Color.black.opacity(0.08),
            radius: 3,
            x: 0,
            y: 1
        )

        /// Floating toolbar / pill shadow
        public static let floating = ShadowToken(
            color: Color.black.opacity(0.16),
            radius: 8,
            x: 0,
            y: 3
        )

        /// Precision handle shadow (table drag handles, resize handles)
        public static let handle = ShadowToken(
            color: Color.black.opacity(0.20),
            radius: 2,
            x: 0,
            y: 1
        )
    }

    // MARK: - Typography Tokens
    public enum Fonts {
        public static let pageHeader = Font.headline
        public static let rowTitle = Font.body
        public static let rowSubtitle = Font.caption
        public static let badge = Font.caption2.weight(.medium)
        public static let cardTitle = Font.subheadline.weight(.semibold)
        public static let cardBreadcrumb = Font.caption2
    }
}

// MARK: - View Extension for Theme Shadows
public extension View {
    func themeShadow(_ token: Theme.Shadows.ShadowToken) -> some View {
        self.shadow(color: token.color, radius: token.radius, x: token.x, y: token.y)
    }
}
