//
//  LassoSelection.swift
//  Notes
//
//  Responsibility: Pure geometric lasso selection logic (point-in-polygon ray casting, stroke sample hit-testing, PageObject hit-testing) and clipboard payload model for copying and pasting strokes and objects across pages and notebooks.
//  Dependencies: Foundation, CoreGraphics, PageObject.
//  Tested in: NotesTests/Domain/LassoSelectionTests.swift
//

import CoreGraphics
import Foundation

/// Pure geometric representation of a user-drawn closed lasso loop in A4 page coordinates.
public struct LassoPolygon: Equatable, Sendable {
    public let points: [CGPoint]
    public let boundingBox: CGRect

    /// Minimum number of points required to form a valid lasso loop.
    public static let minimumPointCount: Int = 4
    /// Minimum bounding-box dimension (width or height in points) so accidental tiny taps don't trigger a lasso.
    public static let minimumBoundingDimension: CGFloat = 10.0
    /// Fraction of a stroke's sample points that must fall inside the lasso polygon to select that stroke.
    public static let strokeInclusionThreshold: Double = 0.50

    public init(points: [CGPoint]) {
        self.points = points
        if let first = points.first {
            var minX = first.x
            var maxX = first.x
            var minY = first.y
            var maxY = first.y
            for p in points.dropFirst() {
                minX = Swift.min(minX, p.x)
                maxX = Swift.max(maxX, p.x)
                minY = Swift.min(minY, p.y)
                maxY = Swift.max(maxY, p.y)
            }
            self.boundingBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        } else {
            self.boundingBox = .null
        }
    }

    public var isValidLoop: Bool {
        guard points.count >= Self.minimumPointCount, !boundingBox.isNull else {
            return false
        }
        return boundingBox.width >= Self.minimumBoundingDimension || boundingBox.height >= Self.minimumBoundingDimension
    }

    /// Standard even-odd ray-casting point-in-polygon test.
    public func contains(_ testPoint: CGPoint) -> Bool {
        guard isValidLoop, boundingBox.insetBy(dx: -2, dy: -2).contains(testPoint) else {
            return false
        }
        var inside = false
        var j = points.count - 1
        for i in 0..<points.count {
            let pi = points[i]
            let pj = points[j]
            let intersectsY = ((pi.y > testPoint.y) != (pj.y > testPoint.y))
            if intersectsY {
                let slopeX = (pj.x - pi.x) * (testPoint.y - pi.y) / (pj.y - pi.y) + pi.x
                if testPoint.x < slopeX {
                    inside.toggle()
                }
            }
            j = i
        }
        return inside
    }

    /// Returns the indices of strokes whose sampled points have at least `strokeInclusionThreshold` (50%) inside the lasso polygon.
    public func selectedStrokeIndices(from strokeSampleArrays: [[CGPoint]]) -> Set<Int> {
        guard isValidLoop else { return [] }
        var selected = Set<Int>()
        for (index, samples) in strokeSampleArrays.enumerated() where !samples.isEmpty {
            var insideCount = 0
            for pt in samples {
                if contains(pt) {
                    insideCount += 1
                }
            }
            let ratio = Double(insideCount) / Double(samples.count)
            if ratio >= Self.strokeInclusionThreshold {
                selected.insert(index)
            }
        }
        return selected
    }

    /// Returns the UUIDs of `PageObject`s whose center or majority of corners fall inside the lasso polygon.
    public func selectedObjectIDs(from objects: [PageObject]) -> Set<UUID> {
        guard isValidLoop else { return [] }
        var selected = Set<UUID>()
        for object in objects {
            if contains(object.center) {
                selected.insert(object.id)
                continue
            }
            let rect = object.frame
            let corners = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY)
            ]
            let insideCorners = corners.filter { contains($0) }.count
            if insideCorners >= 2 {
                selected.insert(object.id)
            }
        }
        return selected
    }
}

/// Active lasso selection state on the current page.
public struct ActiveLassoSelection: Equatable, Sendable {
    public var strokeIndices: Set<Int>
    public var objectIDs: Set<UUID>
    /// Combined bounding box in A4 page coordinates of all selected strokes and objects.
    public var selectionBounds: CGRect

    public var isEmpty: Bool {
        strokeIndices.isEmpty && objectIDs.isEmpty
    }

    public init(strokeIndices: Set<Int>, objectIDs: Set<UUID>, selectionBounds: CGRect) {
        self.strokeIndices = strokeIndices
        self.objectIDs = objectIDs
        self.selectionBounds = selectionBounds
    }
}

/// App-wide clipboard payload allowing selected strokes and `PageObject`s to be copied and pasted between any pages and notebooks.
public struct CanvasClipboardPayload: Equatable, Sendable {
    /// Serialized `PKDrawing` containing the copied ink strokes (if any).
    public let strokeDrawingData: Data?
    /// Bounding box of the copied ink strokes in A4 page coordinates at copy time.
    public let strokeBounds: CGRect?
    /// Copied `PageObject` items (if any).
    public let objects: [PageObject]
    /// Binary image data keyed by `assetID` for any `.image` objects included in `objects`.
    public let imageAssetsByID: [UUID: Data]

    public var isEmpty: Bool {
        strokeDrawingData == nil && objects.isEmpty
    }

    public init(
        strokeDrawingData: Data? = nil,
        strokeBounds: CGRect? = nil,
        objects: [PageObject] = [],
        imageAssetsByID: [UUID: Data] = [:]
    ) {
        self.strokeDrawingData = strokeDrawingData
        self.strokeBounds = strokeBounds
        self.objects = objects
        self.imageAssetsByID = imageAssetsByID
    }
}
