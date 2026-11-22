//
//  LassoSelectionTests.swift
//  NotesTests
//
//  Responsibility: Unit tests for Milestone v1b Increment 2 `LassoPolygon` point-in-polygon ray casting, stroke sample hit-testing, and `PageObject` selection.
//

import CoreGraphics
import Foundation
import Testing
@testable import Notes

@Suite("Domain — LassoSelection")
struct LassoSelectionTests {

    @Test("LassoPolygon ray-casting selects enclosed strokes and objects while ignoring outside items")
    func lassoSelectsEnclosedStrokesAndObjects() {
        // Square lasso loop from (100, 100) to (300, 300)
        let lasso = LassoPolygon(points: [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 300, y: 100),
            CGPoint(x: 300, y: 300),
            CGPoint(x: 100, y: 300)
        ])

        #expect(lasso.isValidLoop == true)
        #expect(lasso.contains(CGPoint(x: 200, y: 200)) == true)
        #expect(lasso.contains(CGPoint(x: 50, y: 50)) == false)

        let strokeInside = [
            CGPoint(x: 140, y: 150),
            CGPoint(x: 180, y: 180),
            CGPoint(x: 220, y: 210)
        ]
        let strokeOutside = [
            CGPoint(x: 20, y: 20),
            CGPoint(x: 40, y: 40),
            CGPoint(x: 60, y: 60)
        ]
        let strokeMostlyInside = [
            CGPoint(x: 150, y: 150),
            CGPoint(x: 200, y: 200),
            CGPoint(x: 250, y: 250),
            CGPoint(x: 340, y: 340) // 3 of 4 points (75%) inside
        ]

        let selectedStrokes = lasso.selectedStrokeIndices(from: [strokeInside, strokeOutside, strokeMostlyInside])
        #expect(selectedStrokes == [0, 2])

        let insideObj = PageObject(
            frame: CGRect(x: 150, y: 150, width: 80, height: 60),
            kind: .basicShape(kind: .rectangle, strokeColor: .black, strokeWidth: 3)
        )
        let outsideObj = PageObject(
            frame: CGRect(x: 400, y: 500, width: 80, height: 60),
            kind: .basicShape(kind: .circle, strokeColor: .blue, strokeWidth: 3)
        )

        let selectedObjs = lasso.selectedObjectIDs(from: [insideObj, outsideObj])
        #expect(selectedObjs == [insideObj.id])
    }

    @Test("Tiny accidental tap does not form a valid lasso loop")
    func tinyTapIsRejected() {
        let tinyLasso = LassoPolygon(points: [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 102, y: 101),
            CGPoint(x: 101, y: 102),
            CGPoint(x: 100, y: 100)
        ])
        #expect(tinyLasso.isValidLoop == false)
    }

    @Test("LassoPolygon selects unrotated, rotated, and mixed TextBox objects accurately")
    func lassoSelectsTextBoxesIncludingRotated() {
        let insideBox = PageObject(
            frame: CGRect(x: 120, y: 140, width: 120, height: 80),
            rotation: 0,
            kind: .textBox(text: "Inside", style: TextBoxStyle())
        )
        let outsideBox = PageObject(
            frame: CGRect(x: 420, y: 500, width: 120, height: 80),
            rotation: 0,
            kind: .textBox(text: "Outside", style: TextBoxStyle())
        )

        // Long thin textBox centered at (340, 200) rotated by 90 degrees so its corners extend vertically to y=80 and y=320.
        // The lasso covers (100, 100) to (310, 300): center (340, 200) is outside, unrotated frame corners at x=220 and x=460,
        // wait - let's test a rotated box whose rotated corners fall inside the lasso while unrotated frame corners fall outside!
        // Unrotated frame: center (200, 100), width 240, height 40 -> unrotated corners are at x=80..320, y=80..120 (all y <= 120).
        // Lasso covers x=150..250, y=130..250 (below y=120, so center (200,100) AND all 4 unrotated corners are OUTSIDE).
        // Rotating by 90 degrees puts two rotated corners at (180, 220) and (220, 220) — strictly INSIDE the lasso!
        let rotatedBox = PageObject(
            frame: CGRect(x: 80, y: 80, width: 240, height: 40),
            rotation: .pi * 0.5,
            kind: .textBox(text: "Rotated", style: TextBoxStyle())
        )

        let rotatedLasso = LassoPolygon(points: [
            CGPoint(x: 150, y: 130),
            CGPoint(x: 250, y: 130),
            CGPoint(x: 250, y: 250),
            CGPoint(x: 150, y: 250)
        ])
        #expect(rotatedLasso.selectedObjectIDs(from: [rotatedBox]) == [rotatedBox.id])

        // Mixed selection: stroke + textBox + basicShape
        let mixedLasso = LassoPolygon(points: [
            CGPoint(x: 90, y: 90),
            CGPoint(x: 320, y: 90),
            CGPoint(x: 320, y: 320),
            CGPoint(x: 90, y: 320)
        ])
        let shape = PageObject(
            frame: CGRect(x: 160, y: 240, width: 60, height: 60),
            kind: .basicShape(kind: .circle, strokeColor: .blue, strokeWidth: 2)
        )
        let stroke = [CGPoint(x: 110, y: 110), CGPoint(x: 140, y: 140), CGPoint(x: 170, y: 170)]

        #expect(mixedLasso.selectedStrokeIndices(from: [stroke]) == [0])
        #expect(mixedLasso.selectedObjectIDs(from: [insideBox, outsideBox, shape]) == [insideBox.id, shape.id])
    }
}
