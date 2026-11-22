//
//  DrawingToolStateTests.swift
//  NotesTests
//
//  Responsibility: Unit tests for `DrawingToolState`:
//    1. Tool selection and Apple Pencil double-tap toggle between active inking tool (Pen / Highlighter) and Rubber (Eraser)
//    2. Size and opacity clamping for Pen, Highlighter, and Rubber
//    3. Ruler overlay independent toggle
//    4. Input policy touch counts (1-finger swipe in Pencil mode vs 2-finger swipe in Finger-drawing mode)
//

import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Notes

@Suite("Domain — DrawingToolState & Apple Pencil Double-Tap")
struct DrawingToolStateTests {

    @Test("Apple Pencil double-tap toggles between Pen/Highlighter and Rubber (Eraser)")
    func pencilDoubleTapTogglesEraserAndRestoresPreviousInkingTool() {
        var state = DrawingToolState()
        #expect(state.activeTool == .pen)

        // Double-tap while on Pen -> switches to Rubber
        state.handlePencilDoubleTapToggleEraser()
        #expect(state.activeTool == .eraser)
        #expect(state.previousInkingTool == .pen)

        // Double-tap again while on Rubber -> returns to Pen
        state.handlePencilDoubleTapToggleEraser()
        #expect(state.activeTool == .pen)

        // Select Highlighter, then double-tap -> switches to Rubber, then back to Highlighter
        state.selectTool(.highlighter)
        #expect(state.activeTool == .highlighter)

        state.handlePencilDoubleTapToggleEraser()
        #expect(state.activeTool == .eraser)
        #expect(state.previousInkingTool == .highlighter)

        state.handlePencilDoubleTapToggleEraser()
        #expect(state.activeTool == .highlighter)
    }

    @Test("Widths and opacities clamp to valid ranges")
    func widthAndOpacityClamping() {
        var state = DrawingToolState()

        state.setPenWidth(500)
        #expect(state.penWidth == DrawingToolState.widthRange.upperBound)
        state.setPenWidth(0.1)
        #expect(state.penWidth == DrawingToolState.widthRange.lowerBound)

        state.setPenOpacity(2.0)
        #expect(state.penOpacity == DrawingToolState.opacityRange.upperBound)
        state.setPenOpacity(0.01)
        #expect(state.penOpacity == DrawingToolState.opacityRange.lowerBound)

        state.setHighlighterWidth(100)
        #expect(state.highlighterWidth == DrawingToolState.highlighterWidthRange.upperBound)
        state.setHighlighterOpacity(0.0)
        #expect(state.highlighterOpacity == DrawingToolState.opacityRange.lowerBound)

        state.setEraserWidth(200)
        #expect(state.eraserWidth == DrawingToolState.eraserWidthRange.upperBound)
    }

    @Test("Ruler toggles independently without losing active drawing tool")
    func rulerIndependentToggle() {
        var state = DrawingToolState()
        state.selectTool(.highlighter)
        #expect(state.isRulerActive == false)

        state.toggleRuler()
        #expect(state.isRulerActive == true)
        #expect(state.activeTool == .highlighter)

        state.toggleRuler()
        #expect(state.isRulerActive == false)
        #expect(state.activeTool == .highlighter)
    }

    @Test("InkColorPreset dynamically adapts monochrome swatch display and name between Light and Dark mode")
    func inkColorPresetAdaptsMonochromeSwatchesToLightAndDarkMode() {
        // Light Mode: Black swatch is dark, White swatch is white
        #expect(InkColorPreset.black.inkDisplayColor(for: .light) == Color(red: 0.08, green: 0.08, blue: 0.08))
        #expect(InkColorPreset.black.inkDisplayName(for: .light) == "Black")
        #expect(InkColorPreset.white.inkDisplayColor(for: .light) == Color.white)
        #expect(InkColorPreset.white.inkDisplayName(for: .light) == "White")

        // Dark Mode: Black preset draws white ink, so swatch displays as White (Adaptive).
        // White preset draws black ink, so swatch displays as Black.
        #expect(InkColorPreset.black.inkDisplayColor(for: .dark) == Color.white)
        #expect(InkColorPreset.black.inkDisplayName(for: .dark) == "White (Adaptive)")
        #expect(InkColorPreset.white.inkDisplayColor(for: .dark) == Color(red: 0.08, green: 0.08, blue: 0.08))
        #expect(InkColorPreset.white.inkDisplayName(for: .dark) == "Black")

        // Chromatic colors stay identical across light and dark mode
        for preset in [InkColorPreset.blue, .red, .green, .orange, .purple, .yellow] {
            #expect(preset.inkDisplayColor(for: .light) == preset.inkDisplayColor(for: .dark))
            #expect(preset.inkDisplayName(for: .light) == preset.displayName)
            #expect(preset.inkDisplayName(for: .dark) == preset.displayName)
        }
    }

    @Test("InkColorPreset decodes legacy 'primary' identifier to .black")
    func legacyPrimaryDecoding() throws {
        let json = "\"primary\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(InkColorPreset.self, from: json)
        #expect(decoded == .black)
    }
}
