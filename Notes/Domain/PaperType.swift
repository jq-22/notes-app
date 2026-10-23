//
//  PaperType.swift
//  Notes
//
//  Responsibility: Defines the available background paper patterns for a page and standard A4 geometry constants.
//  Inputs/Outputs: Pure value type (enum), Codable for JSON persistence.
//  Dependencies: Foundation, CoreGraphics.
//  Errors: None (exhaustive enum).
//  Tested in: NotesTests/Domain/NotebookHierarchyTests.swift
//

import CoreGraphics
import Foundation

/// Background paper style rendered behind the ink layer.
/// Changing a page's paper type never alters its ink strokes.
public enum PaperType: String, Codable, CaseIterable, Identifiable, Sendable {
    case lined
    case squared
    case blank

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .lined: return "Lined"
        case .squared: return "Squared"
        case .blank: return "Blank"
        }
    }

    public var systemImageName: String {
        switch self {
        case .lined: return "lines.measurement.horizontal"
        case .squared: return "squareshape.split.3x3"
        case .blank: return "doc"
        }
    }
}

/// Standard page geometry constants (A4 portrait at 72 DPI: 595 x 842 pt).
public enum PageGeometry {
    public static let a4Width: CGFloat = 595
    public static let a4Height: CGFloat = 842
    public static let a4Size = CGSize(width: a4Width, height: a4Height)
    public static let aspectRatio: CGFloat = a4Width / a4Height

    /// Spacing between horizontal lines on lined paper, or grid lines on squared paper.
    public static let lineSpacing: CGFloat = 28
    /// Top margin before the first horizontal line on lined paper.
    public static let topMargin: CGFloat = 56
    /// Left margin line x-offset on lined paper.
    public static let leftMarginOffset: CGFloat = 64

    /// Small breathing margin around the page when fitting or snapping to screen width.
    public static let viewportPadding: CGFloat = 24
    /// Relative tolerance within which pinch-zoom automatically snaps to the fit-width scale.
    public static let fitWidthSnapRelativeTolerance: CGFloat = 0.08

    /// Computes the zoom scale that makes the A4 page fill the available horizontal viewport width (minus `padding` on each side).
    public static func fitWidthZoomScale(forViewportWidth viewportWidth: CGFloat, padding: CGFloat = viewportPadding) -> CGFloat {
        let usableWidth = max(viewportWidth - (padding * 2), a4Width * 0.5)
        return max(0.5, usableWidth / a4Width)
    }

    /// Computes the zoom scale that fits the entire A4 page (both width and height) inside `viewportSize`.
    public static func fitWholePageZoomScale(forViewportSize viewportSize: CGSize, padding: CGFloat = viewportPadding) -> CGFloat {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return 1.0 }
        let usableWidth = max(viewportSize.width - (padding * 2), a4Width * 0.5)
        let usableHeight = max(viewportSize.height - (padding * 2), a4Height * 0.5)
        return max(0.5, min(usableWidth / a4Width, usableHeight / a4Height))
    }

    /// Computes the default initial zoom scale for a given viewport size:
    /// - In portrait (`height >= width`), fits the page width so the page fills the iPad screen cleanly.
    /// - In landscape (`width > height`), fits the whole page if needed or uses a comfortable width scale (`>= 1.15x`) so the page isn't a tiny box in the middle.
    public static func defaultInitialZoomScale(forViewportSize viewportSize: CGSize, padding: CGFloat = viewportPadding) -> CGFloat {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return 1.0 }
        let fitWidth = fitWidthZoomScale(forViewportWidth: viewportSize.width, padding: padding)
        if viewportSize.height >= viewportSize.width {
            // Portrait: snap straight to fit-width
            return fitWidth
        } else {
            // Landscape: fill the vertical height comfortably (or at least 1.15x) without exceeding fitWidth
            let fitHeight = max(viewportSize.height - (padding * 2), a4Height * 0.5) / a4Height
            return min(fitWidth, max(fitHeight, 1.15))
        }
    }

    /// If `zoomScale` is within `fitWidthSnapRelativeTolerance` (±8%) of `fitWidthScale`, returns `fitWidthScale`; otherwise returns `zoomScale`.
    public static func snappedZoomScale(_ zoomScale: CGFloat, fitWidthScale: CGFloat) -> CGFloat {
        guard fitWidthScale > 0 else { return zoomScale }
        let relativeDiff = abs(zoomScale - fitWidthScale) / fitWidthScale
        if relativeDiff <= fitWidthSnapRelativeTolerance {
            return fitWidthScale
        }
        return zoomScale
    }
}
