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

    @Test("Finger drawing mode requires 2 fingers for navigation swipes while Pencil-only mode requires 1 finger")
    func navigationTouchCountFollowsInputPolicy() {
        var state = DrawingToolState()
        #expect(state.allowsFingerDrawing == false)
        #expect(state.minimumTouchCountForNavigationSwipes == 1)

        state.allowsFingerDrawing = true
        #expect(state.minimumTouchCountForNavigationSwipes == 2)
    }
}
