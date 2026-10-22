//
//  ScribbleClassifierTests.swift
//  NotesTests
//
//  Responsibility: Synthetic stroke unit tests for `ScribbleClassifier`:
//    1. Dense back-and-forth scribble over existing strokes -> triggers & returns covered stroke IDs
//    2. Normal straight/curved line (e.g. underline) -> does NOT trigger
//    3. Closed circle / loop -> does NOT trigger
//    4. Zigzag letter ('M' / 'W') -> does NOT trigger
//    5. Scribble over empty space (no overlapping strokes) -> does NOT trigger
//    6. Scribble when feature is disabled in settings (`isEnabled = false`) -> does NOT trigger
//

import CoreGraphics
import Foundation
import Testing
@testable import Notes

@Suite("Domain — ScribbleClassifier Synthetic Stroke Tests")
struct ScribbleClassifierTests {

    // MARK: - Synthetic Stroke Generators

    /// Generates a dense back-and-forth horizontal scribble oscillating 6 times across `rect`.
    static func makeSyntheticScribble(in rect: CGRect, passes: Int = 6, samplesPerPass: Int = 8) -> StrokeSample {
        var points: [CGPoint] = []
        for pass in 0..<passes {
            let goingRight = (pass % 2 == 0)
            let startX = goingRight ? rect.minX : rect.maxX
            let endX = goingRight ? rect.maxX : rect.minX
            let yStart = rect.minY + (rect.height * CGFloat(pass) / CGFloat(max(passes, 1)))
            let yEnd = rect.minY + (rect.height * CGFloat(pass + 1) / CGFloat(max(passes, 1)))

            for step in 0...samplesPerPass {
                let t = CGFloat(step) / CGFloat(samplesPerPass)
                let x = startX + (endX - startX) * t
                let y = yStart + (yEnd - yStart) * t
                points.append(CGPoint(x: x, y: y))
            }
        }
        return StrokeSample(points: points)
    }

    /// Generates a straight horizontal underline stroke.
    static func makeSyntheticStraightLine(from start: CGPoint, to end: CGPoint, steps: Int = 25) -> StrokeSample {
        let points = (0...steps).map { step -> CGPoint in
            let t = CGFloat(step) / CGFloat(steps)
            return CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            )
        }
        return StrokeSample(points: points)
    }

    /// Generates a closed circle stroke.
    static func makeSyntheticCircle(center: CGPoint, radius: CGFloat, steps: Int = 36) -> StrokeSample {
        let points = (0...steps).map { step -> CGPoint in
            let angle = (2.0 * .pi * CGFloat(step)) / CGFloat(steps)
            return CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
        return StrokeSample(points: points)
    }

    /// Generates a 4-segment capital letter 'W' or 'M' zigzag stroke (3 corners).
    static func makeSyntheticZigzagLetterW(origin: CGPoint, width: CGFloat = 48, height: CGFloat = 32, stepsPerLeg: Int = 6) -> StrokeSample {
        let vertices = [
            CGPoint(x: origin.x, y: origin.y),
            CGPoint(x: origin.x + width * 0.25, y: origin.y + height),
            CGPoint(x: origin.x + width * 0.50, y: origin.y + height * 0.2),
            CGPoint(x: origin.x + width * 0.75, y: origin.y + height),
            CGPoint(x: origin.x + width, y: origin.y)
        ]
        var points: [CGPoint] = []
        for leg in 0..<(vertices.count - 1) {
            let start = vertices[leg]
            let end = vertices[leg + 1]
            let startIdx = (leg == 0) ? 0 : 1
            for step in startIdx...stepsPerLeg {
                let t = CGFloat(step) / CGFloat(stepsPerLeg)
                points.append(CGPoint(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t
                ))
            }
        }
        return StrokeSample(points: points)
    }

    // MARK: - Tests

    @Test("Dense back-and-forth scribble over existing strokes triggers erase and identifies covered strokes")
    func scribbleOverExistingStrokesTriggers() {
        let coveredWord1 = ExistingStrokeTarget(
            id: 0,
            bounds: CGRect(x: 105, y: 205, width: 45, height: 18),
            samplePoints: [CGPoint(x: 115, y: 212), CGPoint(x: 135, y: 214)]
        )
        let coveredWord2 = ExistingStrokeTarget(
            id: 1,
            bounds: CGRect(x: 155, y: 204, width: 40, height: 20),
            samplePoints: [CGPoint(x: 165, y: 214), CGPoint(x: 185, y: 214)]
        )
        let distantStroke = ExistingStrokeTarget(
            id: 2,
            bounds: CGRect(x: 400, y: 500, width: 60, height: 20),
            samplePoints: [CGPoint(x: 420, y: 510)]
        )

        let scribble = Self.makeSyntheticScribble(
            in: CGRect(x: 100, y: 200, width: 100, height: 26),
            passes: 6
        )

        let result = ScribbleClassifier.classify(
            stroke: scribble,
            existingStrokes: [coveredWord1, coveredWord2, distantStroke],
            isEnabled: true
        )

        #expect(result.isScribbleErase == true)
        #expect(result.erasedStrokeIDs == [0, 1])
    }

    @Test("Normal straight line or underline never triggers scribble-to-erase")
    func normalLineDoesNotTrigger() {
        let target = ExistingStrokeTarget(
            id: 0,
            bounds: CGRect(x: 100, y: 200, width: 120, height: 20)
        )
        let underline = Self.makeSyntheticStraightLine(
            from: CGPoint(x: 100, y: 210),
            to: CGPoint(x: 220, y: 212)
        )

        let result = ScribbleClassifier.classify(
            stroke: underline,
            existingStrokes: [target],
            isEnabled: true
        )

        #expect(result.isScribbleErase == false)
        #expect(result.erasedStrokeIDs.isEmpty)
    }

    @Test("Closed circle or loop around existing ink never triggers scribble-to-erase")
    func circleDoesNotTrigger() {
        let target = ExistingStrokeTarget(
            id: 0,
            bounds: CGRect(x: 180, y: 180, width: 40, height: 40)
        )
        let circle = Self.makeSyntheticCircle(center: CGPoint(x: 200, y: 200), radius: 35)

        let result = ScribbleClassifier.classify(
            stroke: circle,
            existingStrokes: [target],
            isEnabled: true
        )

        #expect(result.isScribbleErase == false)
        #expect(result.erasedStrokeIDs.isEmpty)
    }

    @Test("Zigzag letter ('W' or 'M') never triggers scribble-to-erase")
    func zigzagLetterDoesNotTrigger() {
        let target = ExistingStrokeTarget(
            id: 0,
            bounds: CGRect(x: 100, y: 200, width: 50, height: 32)
        )
        let letterW = Self.makeSyntheticZigzagLetterW(origin: CGPoint(x: 100, y: 200))

        let result = ScribbleClassifier.classify(
            stroke: letterW,
            existingStrokes: [target],
            isEnabled: true
        )

        #expect(result.isScribbleErase == false)
        #expect(result.erasedStrokeIDs.isEmpty)
    }

    @Test("Scribble over blank space without overlapping existing strokes does not trigger")
    func scribbleInEmptySpaceDoesNotTrigger() {
        let distantTarget = ExistingStrokeTarget(
            id: 0,
            bounds: CGRect(x: 400, y: 600, width: 80, height: 20)
        )
        let scribble = Self.makeSyntheticScribble(
            in: CGRect(x: 80, y: 120, width: 90, height: 25),
            passes: 6
        )

        let result = ScribbleClassifier.classify(
            stroke: scribble,
            existingStrokes: [distantTarget],
            isEnabled: true
        )

        #expect(result.isScribbleErase == false)
        #expect(result.erasedStrokeIDs.isEmpty)
    }

    @Test("Scribble does not trigger when scribble-to-erase is disabled in settings")
    func disabledSettingPreventsTrigger() {
        let coveredTarget = ExistingStrokeTarget(
            id: 0,
            bounds: CGRect(x: 105, y: 205, width: 80, height: 20)
        )
        let scribble = Self.makeSyntheticScribble(
            in: CGRect(x: 100, y: 200, width: 100, height: 26),
            passes: 6
        )

        let result = ScribbleClassifier.classify(
            stroke: scribble,
            existingStrokes: [coveredTarget],
            isEnabled: false
        )

        #expect(result.isScribbleErase == false)
        #expect(result.erasedStrokeIDs.isEmpty)
    }
}
