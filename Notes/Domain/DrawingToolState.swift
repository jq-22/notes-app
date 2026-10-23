//
//  DrawingToolState.swift
//  Notes
//
//  Responsibility: Pure value model representing the user's selected drawing tool (Pen, Highlighter, Rubber/Eraser, Ruler toggle), tool parameters (colour, width, opacity, eraser mode), Apple Pencil double-tap switching, and input policy (Pencil-only vs Draw with Finger).
//  Dependencies: Foundation, CoreGraphics (imports no UIKit/SwiftUI/PencilKit).
//  Errors: Clamps stroke widths and opacities to valid ranges.
//  Tested in: NotesTests/Domain/DrawingToolStateTests.swift
//

import CoreGraphics
import Foundation

/// Active primary tool in the editor.
public enum DrawingToolKind: String, Codable, CaseIterable, Equatable, Sendable {
    case pen
    case highlighter
    case eraser

    public var displayName: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .eraser: return "Rubber"
        }
    }

    public var systemImageName: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser.fill"
        }
    }
}

/// Eraser mode: whole-stroke ("Object") vs pixel ("Bitmap") with adjustable width.
public enum EraserMode: String, Codable, CaseIterable, Equatable, Sendable {
    case object
    case pixel

    public var displayName: String {
        switch self {
        case .object: return "Object (Whole Stroke)"
        case .pixel: return "Pixel"
        }
    }
}

/// Explicit ink colour presets (with separate Black and White options instead of automatic dark/light inversion).
public enum InkColorPreset: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case black
    case white
    case blue
    case red
    case green
    case orange
    case purple
    case yellow

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .black: return "Black"
        case .white: return "White"
        case .blue: return "Blue"
        case .red: return "Red"
        case .green: return "Green"
        case .orange: return "Orange"
        case .purple: return "Purple"
        case .yellow: return "Yellow"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == "primary" {
            self = .black
        } else if let value = InkColorPreset(rawValue: raw) {
            self = value
        } else {
            self = .black
        }
    }
}

/// Complete, testable state for the custom 4-tool menu (Pen, Highlighter, Rubber, Ruler) and input policy.
public struct DrawingToolState: Codable, Equatable, Sendable {
    public var activeTool: DrawingToolKind
    /// Remembers the last inking tool (`.pen` or `.highlighter`) so Apple Pencil double-tap can toggle to `.eraser` and back.
    public private(set) var previousInkingTool: DrawingToolKind

    // Pen settings
    public var penColor: InkColorPreset
    public var penWidth: CGFloat
    public var penOpacity: CGFloat

    // Highlighter settings
    public var highlighterColor: InkColorPreset
    public var highlighterWidth: CGFloat
    public var highlighterOpacity: CGFloat

    // Rubber (Eraser) settings
    public var eraserMode: EraserMode
    public var eraserWidth: CGFloat

    // Ruler overlay toggle (independent of active tool)
    public var isRulerActive: Bool

    public static let widthRange: ClosedRange<CGFloat> = 1.0...24.0
    public static let highlighterWidthRange: ClosedRange<CGFloat> = 6.0...40.0
    public static let eraserWidthRange: ClosedRange<CGFloat> = 4.0...48.0
    public static let opacityRange: ClosedRange<CGFloat> = 0.15...1.0

    public init(
        activeTool: DrawingToolKind = .pen,
        previousInkingTool: DrawingToolKind = .pen,
        penColor: InkColorPreset = .black,
        penWidth: CGFloat = 3.0,
        penOpacity: CGFloat = 1.0,
        highlighterColor: InkColorPreset = .yellow,
        highlighterWidth: CGFloat = 18.0,
        highlighterOpacity: CGFloat = 0.45,
        eraserMode: EraserMode = .object,
        eraserWidth: CGFloat = 16.0,
        isRulerActive: Bool = false
    ) {
        self.activeTool = activeTool
        self.previousInkingTool = (previousInkingTool == .eraser) ? .pen : previousInkingTool
        self.penColor = penColor
        self.penWidth = Self.clamp(penWidth, to: Self.widthRange)
        self.penOpacity = Self.clamp(penOpacity, to: Self.opacityRange)
        self.highlighterColor = highlighterColor
        self.highlighterWidth = Self.clamp(highlighterWidth, to: Self.highlighterWidthRange)
        self.highlighterOpacity = Self.clamp(highlighterOpacity, to: Self.opacityRange)
        self.eraserMode = eraserMode
        self.eraserWidth = Self.clamp(eraserWidth, to: Self.eraserWidthRange)
        self.isRulerActive = isRulerActive
    }

    /// Selects a tool and records `previousInkingTool` whenever `.pen` or `.highlighter` is chosen.
    public mutating func selectTool(_ tool: DrawingToolKind) {
        if activeTool != .eraser {
            previousInkingTool = activeTool
        }
        activeTool = tool
        if tool != .eraser {
            previousInkingTool = tool
        }
    }

    /// Handles the Apple Pencil double-tap action:
    /// - If currently using Pen or Highlighter, switches to Rubber (Eraser).
    /// - If already using Rubber, switches back to the previous inking tool (Pen or Highlighter).
    public mutating func handlePencilDoubleTapToggleEraser() {
        if activeTool == .eraser {
            activeTool = previousInkingTool
        } else {
            previousInkingTool = activeTool
            activeTool = .eraser
        }
    }

    public mutating func toggleRuler() {
        isRulerActive.toggle()
    }

    public mutating func setPenWidth(_ width: CGFloat) {
        penWidth = Self.clamp(width, to: Self.widthRange)
    }

    public mutating func setPenOpacity(_ opacity: CGFloat) {
        penOpacity = Self.clamp(opacity, to: Self.opacityRange)
    }

    public mutating func setHighlighterWidth(_ width: CGFloat) {
        highlighterWidth = Self.clamp(width, to: Self.highlighterWidthRange)
    }

    public mutating func setHighlighterOpacity(_ opacity: CGFloat) {
        highlighterOpacity = Self.clamp(opacity, to: Self.opacityRange)
    }

    public mutating func setEraserWidth(_ width: CGFloat) {
        eraserWidth = Self.clamp(width, to: Self.eraserWidthRange)
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
    }
}
