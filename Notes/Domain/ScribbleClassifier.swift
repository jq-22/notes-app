//
//  ScribbleClassifier.swift
//  Notes
//
//  Responsibility: Pure geometric heuristic that inspects a newly completed stroke and determines whether it is a "scribble-to-erase" gesture over existing strokes.
//  Design notes:
//    - False triggers (wiping out valid handwriting, circles, or zigzag letters like 'M'/'W') are much worse than missed scribbles, so all thresholds err on the cautious side.
//    - All thresholds live as named constants on `ScribbleClassifier.Configuration` so they can be tuned on the iPad.
//    - Imports no UI or PencilKit types (`CGPoint` and `CGRect` come from `CoreGraphics`). `PageEditor` converts `PKStroke` points/bounds into `StrokeSample` and `ExistingStrokeTarget`.
//  Dependencies: Foundation, CoreGraphics.
//  Errors: None (pure function returning `ScribbleClassification`).
//  Tested in: NotesTests/Domain/ScribbleClassifierTests.swift
//

import CoreGraphics
import Foundation

/// Lightweight geometric representation of a newly drawn stroke.
public struct StrokeSample: Equatable, Sendable {
    public let points: [CGPoint]

    public init(points: [CGPoint]) {
        self.points = points
    }
}

/// Lightweight geometric representation of an existing stroke on the page that could be erased.
public struct ExistingStrokeTarget: Equatable, Sendable {
    public let id: Int
    public let bounds: CGRect
    public let samplePoints: [CGPoint]

    public init(id: Int, bounds: CGRect, samplePoints: [CGPoint] = []) {
        self.id = id
        self.bounds = bounds
        self.samplePoints = samplePoints
    }
}

/// Result of classifying a completed stroke.
public struct ScribbleClassification: Equatable, Sendable {
    public let isScribbleErase: Bool
    /// Indices/IDs of the existing strokes covered by the scribble that should be removed together with the scribble stroke in one undo step.
    public let erasedStrokeIDs: [Int]
    public let metrics: Metrics

    public struct Metrics: Equatable, Sendable {
        public let pathLength: CGFloat
        public let boundingBox: CGRect
        public let diagonalLength: CGFloat
        public let pathToDiagonalRatio: CGFloat
        public let sharpReversalCount: Int
        public let horizontalAxisReversalCount: Int
        public let netDisplacementRatio: CGFloat
    }
}

public enum ScribbleClassifier {

    /// Named constants controlling scribble-to-erase sensitivity.
    public struct Configuration: Equatable, Sendable {
        /// Minimum number of sampled points required before a stroke is even considered.
        public var minimumPointCount: Int = 12

        /// Minimum distance between consecutive resampled vertices so tiny jitter doesn't count as a reversal.
        public var minimumSegmentLength: CGFloat = 4.0

        /// Minimum total path length (in points) for a scribble gesture.
        public var minimumPathLength: CGFloat = 140.0

        /// Minimum bounding-box width or height (avoids triggering on tiny dots or ticks).
        public var minimumBoundingDimension: CGFloat = 8.0

        /// Maximum bounding-box width or height (avoids triggering on huge page-wide borders or diagrams).
        public var maximumBoundingDimension: CGFloat = 380.0

        /// Minimum ratio of total path length to bounding-box diagonal (`pathLength / diagonal`).
        /// A straight line has ratio ~1.0; a circle ~2.2; a 4-segment letter 'M' or 'W' ~2.8–3.4; a dense back-and-forth scribble is typically >= 3.8.
        public var minimumPathToDiagonalRatio: CGFloat = 3.8

        /// Minimum number of sharp direction reversals (turning angle > `sharpReversalAngleDegrees`).
        /// A letter 'M' or 'W' has 2–3 sharp corners; a back-and-forth scribble has at least 4+.
        public var minimumSharpReversals: Int = 4

        /// Minimum turning angle (in degrees, where 0° is straight ahead and 180° is a U-turn) to count as a sharp reversal.
        public var sharpReversalAngleDegrees: CGFloat = 125.0

        /// Minimum number of primary-axis velocity sign flips (oscillations back and forth).
        public var minimumAxisReversals: Int = 4

        /// Maximum ratio of start-to-end distance vs total path length (`distance(start, end) / pathLength`).
        /// Normal cursive words progress across the page, whereas a scribble folds back over itself repeatedly.
        public var maximumNetDisplacementRatio: CGFloat = 0.45

        /// Minimum fraction of an existing stroke's bounding box area (or sample points) that must fall within the scribble's expanded bounds to be erased.
        public var minimumTargetOverlapFraction: CGFloat = 0.25

        /// Slight padding (in points) applied to the scribble's bounding box when testing intersection against thin horizontal/vertical strokes.
        public var hitTestPadding: CGFloat = 6.0

        public init() {}
    }

    /// Evaluates whether `stroke` is a scribble-to-erase gesture over `existingStrokes`.
    /// - Parameters:
    ///   - stroke: The newly completed stroke.
    ///   - existingStrokes: Existing strokes on the canvas (excluding the newly drawn stroke itself).
    ///   - isEnabled: User setting toggle; when `false`, immediately returns non-scribble.
    ///   - configuration: Threshold configuration.
    public static func classify(
        stroke: StrokeSample,
        existingStrokes: [ExistingStrokeTarget],
        isEnabled: Bool = true,
        configuration: Configuration = Configuration()
    ) -> ScribbleClassification {
        let filteredPoints = decimatePoints(
            stroke.points,
            minimumSegmentLength: configuration.minimumSegmentLength
        )

        let bbox = boundingBox(for: filteredPoints)
        let pathLen = totalPathLength(for: filteredPoints)
        let diagonal = hypot(bbox.width, bbox.height)
        let pathToDiag = diagonal > 0.001 ? (pathLen / diagonal) : 0
        let netDisp: CGFloat = {
            guard let first = filteredPoints.first, let last = filteredPoints.last, pathLen > 0.001 else {
                return 1.0
            }
            return hypot(last.x - first.x, last.y - first.y) / pathLen
        }()

        let sharpReversals = countSharpReversals(
            in: filteredPoints,
            thresholdDegrees: configuration.sharpReversalAngleDegrees
        )
        let axisReversals = countPrimaryAxisReversals(
            in: filteredPoints,
            minimumStep: configuration.minimumSegmentLength
        )

        let metrics = ScribbleClassification.Metrics(
            pathLength: pathLen,
            boundingBox: bbox,
            diagonalLength: diagonal,
            pathToDiagonalRatio: pathToDiag,
            sharpReversalCount: sharpReversals,
            horizontalAxisReversalCount: axisReversals,
            netDisplacementRatio: netDisp
        )

        guard isEnabled,
              !existingStrokes.isEmpty,
              filteredPoints.count >= configuration.minimumPointCount,
              pathLen >= configuration.minimumPathLength,
              max(bbox.width, bbox.height) >= configuration.minimumBoundingDimension,
              max(bbox.width, bbox.height) <= configuration.maximumBoundingDimension,
              bbox.width >= configuration.minimumBoundingDimension * 0.5,
              bbox.height >= configuration.minimumBoundingDimension * 0.5,
              pathToDiag >= configuration.minimumPathToDiagonalRatio,
              sharpReversals >= configuration.minimumSharpReversals,
              axisReversals >= configuration.minimumAxisReversals,
              netDisp <= configuration.maximumNetDisplacementRatio
        else {
            return ScribbleClassification(
                isScribbleErase: false,
                erasedStrokeIDs: [],
                metrics: metrics
            )
        }

        let scribbleHitBox = bbox.insetBy(
            dx: -configuration.hitTestPadding,
            dy: -configuration.hitTestPadding
        )

        let coveredIDs = existingStrokes.compactMap { target -> Int? in
            if isTargetCovered(
                target,
                byScribbleBox: scribbleHitBox,
                minimumOverlapFraction: configuration.minimumTargetOverlapFraction
            ) {
                return target.id
            }
            return nil
        }

        guard !coveredIDs.isEmpty else {
            return ScribbleClassification(
                isScribbleErase: false,
                erasedStrokeIDs: [],
                metrics: metrics
            )
        }

        return ScribbleClassification(
            isScribbleErase: true,
            erasedStrokeIDs: coveredIDs,
            metrics: metrics
        )
    }

    // MARK: - Geometry Helpers

    private static func decimatePoints(_ points: [CGPoint], minimumSegmentLength: CGFloat) -> [CGPoint] {
        guard let first = points.first else { return [] }
        var result: [CGPoint] = [first]
        for point in points.dropFirst() {
            let previous = result[result.count - 1]
            if hypot(point.x - previous.x, point.y - previous.y) >= minimumSegmentLength {
                result.append(point)
            }
        }
        return result
    }

    private static func boundingBox(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func totalPathLength(for points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var length: CGFloat = 0
        for index in 1..<points.count {
            let p0 = points[index - 1]
            let p1 = points[index]
            length += hypot(p1.x - p0.x, p1.y - p0.y)
        }
        return length
    }

    private static func countSharpReversals(in points: [CGPoint], thresholdDegrees: CGFloat) -> Int {
        guard points.count >= 3 else { return 0 }
        let cosineThreshold = cos(thresholdDegrees * .pi / 180.0) // Negative for > 90°
        var reversals = 0
        var lastReversalIndex = -2

        for index in 1..<(points.count - 1) {
            let v1 = CGPoint(
                x: points[index].x - points[index - 1].x,
                y: points[index].y - points[index - 1].y
            )
            let v2 = CGPoint(
                x: points[index + 1].x - points[index].x,
                y: points[index + 1].y - points[index].y
            )
            let len1 = hypot(v1.x, v1.y)
            let len2 = hypot(v2.x, v2.y)
            guard len1 > 0.001, len2 > 0.001 else { continue }

            let cosTheta = (v1.x * v2.x + v1.y * v2.y) / (len1 * len2)
            if cosTheta <= cosineThreshold {
                // If a U-turn spans two adjacent segments, count it as a single reversal
                if index - lastReversalIndex > 1 {
                    reversals += 1
                    lastReversalIndex = index
                }
            }
        }
        return reversals
    }

    private static func countPrimaryAxisReversals(in points: [CGPoint], minimumStep: CGFloat) -> Int {
        guard points.count >= 3 else { return 0 }

        let xReversals = countSignFlips(deltas: (1..<points.count).map { points[$0].x - points[$0 - 1].x }, deadzone: minimumStep * 0.35)
        let yReversals = countSignFlips(deltas: (1..<points.count).map { points[$0].y - points[$0 - 1].y }, deadzone: minimumStep * 0.35)
        return max(xReversals, yReversals)
    }

    private static func countSignFlips(deltas: [CGFloat], deadzone: CGFloat) -> Int {
        var currentSign = 0
        var flips = 0
        for delta in deltas {
            guard abs(delta) >= deadzone else { continue }
            let sign = delta > 0 ? 1 : -1
            if currentSign != 0 && sign != currentSign {
                flips += 1
            }
            currentSign = sign
        }
        return flips
    }

    private static func isTargetCovered(
        _ target: ExistingStrokeTarget,
        byScribbleBox scribbleBox: CGRect,
        minimumOverlapFraction: CGFloat
    ) -> Bool {
        guard scribbleBox.intersects(target.bounds) else { return false }

        // If sample points are provided for the existing stroke, check the fraction of points inside the scribble box.
        if !target.samplePoints.isEmpty {
            let insideCount = target.samplePoints.filter { scribbleBox.contains($0) }.count
            let fraction = CGFloat(insideCount) / CGFloat(target.samplePoints.count)
            if fraction >= minimumOverlapFraction {
                return true
            }
        }

        // Also check bounding box intersection ratio (padded for thin horizontal/vertical lines).
        let paddedTarget = target.bounds.insetBy(
            dx: min(0, -(4.0 - target.bounds.width) / 2),
            dy: min(0, -(4.0 - target.bounds.height) / 2)
        )
        let intersection = scribbleBox.intersection(paddedTarget)
        guard !intersection.isNull else { return false }

        let targetArea = max(paddedTarget.width * paddedTarget.height, 1.0)
        let intersectionArea = intersection.width * intersection.height
        return (intersectionArea / targetArea) >= minimumOverlapFraction
    }
}
