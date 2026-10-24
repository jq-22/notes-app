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
}
