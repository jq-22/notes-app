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
}
