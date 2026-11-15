//
//  ThemeTests.swift
//  NotesTests
//
//  Responsibility: Unit tests verifying Design System tokens, 8pt spatial grid adherence, corner radii, and shadow geometry.
//

import CoreGraphics
import Foundation
import Testing
@testable import Notes

@Suite("Design System — Theme Tokens")
struct ThemeTests {
    @Test("Spacing tokens strictly conform to 8pt spatial grid multiples")
    func spacingTokensConformTo8ptGrid() {
        #expect(Theme.Spacing.small == 8.0)
        #expect(Theme.Spacing.medium == 16.0)
        #expect(Theme.Spacing.large == 24.0)
        #expect(Theme.Spacing.xLarge == 32.0)

        let gridMultiples: [CGFloat] = [
            Theme.Spacing.small,
            Theme.Spacing.medium,
            Theme.Spacing.large,
            Theme.Spacing.xLarge
        ]

        for token in gridMultiples {
            #expect(token.truncatingRemainder(dividingBy: 8.0) == 0.0)
        }

        #expect(Theme.Spacing.grid8 == 8.0)
        #expect(Theme.Spacing.grid16 == 16.0)
        #expect(Theme.Spacing.grid24 == 24.0)
        #expect(Theme.Spacing.grid32 == 32.0)
        #expect(Theme.Spacing.xSmall == 4.0)
    }

    @Test("Standardized corner radii tokens match modern iPadOS requirements")
    func cornerRadiiTokensMatchRequirements() {
        #expect(Theme.CornerRadius.pageThumbnail == 16.0)
        #expect(Theme.CornerRadius.thumbnail == 16.0)
        #expect(Theme.CornerRadius.linkCard == 12.0)
        #expect(Theme.CornerRadius.tableHandle == 8.0)
        #expect(Theme.CornerRadius.floatingPill == 8.0)
        #expect(Theme.CornerRadius.page == 4.0)
    }

    @Test("Shadow tokens define correct radii and elevations")
    func shadowTokensParameters() {
        #expect(Theme.Shadows.subtleCard.radius == 3.0)
        #expect(Theme.Shadows.subtleCard.y == 1.0)
        #expect(Theme.Shadows.floating.radius == 8.0)
        #expect(Theme.Shadows.floating.y == 3.0)
        #expect(Theme.Shadows.handle.radius == 2.0)
        #expect(Theme.Shadows.handle.y == 1.0)
    }
}
