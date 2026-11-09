//
//  PageObject.swift
//  Notes
//
//  Responsibility: Pure value types representing movable, resizable, rotatable objects placed on a Page
//  (Basic Shapes: rectangle, circle, arrow, line; Images referenced by asset UUID; and Stroke/Library objects).
//  Includes pure geometric transform helpers for moving, 4-corner resizing (preserving the opposite corner anchor even when rotated), and rotating.
//  Dependencies: Foundation, CoreGraphics, DrawingToolState (InkColorPreset), PaperType (PageGeometry).
//  Tested in: NotesTests/Domain/PageObjectTests.swift
//

import CoreGraphics
import Foundation

/// The four basic geometric shapes supported in Milestone v1b.
public enum BasicShapeKind: String, Codable, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case rectangle
    case circle
    case arrow
    case line

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .arrow: return "Arrow"
        case .line: return "Line"
        }
    }

    public var systemImageName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        }
    }
}

/// The four corner handles shared by rectangular/circular/image `PageObject`s.
public enum ObjectResizeCorner: String, CaseIterable, Equatable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

/// The two end-cap handles used by `.line` and `.arrow` shapes to lengthen/shorten from either end.
public enum LineEndpointHandle: String, CaseIterable, Equatable, Sendable {
    case start
    case end
}

/// Payload type for a `PageObject`.
public enum PageObjectKind: Codable, Equatable, Hashable, Sendable {
    /// A vector geometric shape drawn with a chosen colour and stroke width.
    case basicShape(kind: BasicShapeKind, strokeColor: InkColorPreset, strokeWidth: CGFloat)
    /// An imported image whose binary data is stored on disk via `PageStore` under `assetID`.
    case image(assetID: UUID)
    /// A group of PencilKit strokes (from Lasso Copy/Paste or the Notebook Shape Library) that can be moved, resized, rotated, and recoloured.
    case strokeGroup(drawingData: Data, sourceBoundsWidth: CGFloat, sourceBoundsHeight: CGFloat, tintColorOverride: InkColorPreset?)
    /// A structured grid table for handwritten notes (e.g. Name / Meaning / Example) where ink flows naturally across cells.
    case table(
        rowCount: Int,
        columnCount: Int,
        columnWidthFractions: [CGFloat]?,
        rowHeightFractions: [CGFloat]?,
        strokeColor: InkColorPreset,
        hasHeaderRow: Bool
    )
    /// A link to another page in the notebook hierarchy (by permanent UUID).
    case pageLink(
        targetPageID: UUID,
        targetSectionID: UUID,
        targetNotebookID: UUID,
        fallbackTitle: String
    )
}

/// A placed object on an A4 page with unified move, 4-corner resize, and top-handle rotate geometry.
public struct PageObject: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat
    /// Clockwise rotation in radians around the object's center (`frame.midX`, `frame.midY`).
    public var rotation: CGFloat
    public var zIndex: Int
    public var kind: PageObjectKind
    public let createdAt: Date
    public var updatedAt: Date

    public static let minimumDimension: CGFloat = 24.0

    public var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.origin.x
            y = newValue.origin.y
            width = Swift.max(Self.minimumDimension, newValue.size.width)
            height = Swift.max(Self.minimumDimension, newValue.size.height)
        }
    }

    public var center: CGPoint {
        CGPoint(x: x + width * 0.5, y: y + height * 0.5)
    }

    /// Returns `true` when this object is a 1D linear shape (`.line` or `.arrow`) that uses two end-bar handles + rotate handle instead of a 4-corner box.
    public var usesLinearEndpointHandles: Bool {
        if case .basicShape(let shapeKind, _, _) = kind {
            return shapeKind == .line || shapeKind == .arrow
        }
        return false
    }

    public init(
        id: UUID = UUID(),
        frame: CGRect,
        rotation: CGFloat = 0,
        zIndex: Int = 0,
        kind: PageObjectKind,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.x = frame.origin.x
        self.y = frame.origin.y
        self.width = Swift.max(Self.minimumDimension, frame.size.width)
        self.height = Swift.max(Self.minimumDimension, frame.size.height)
        self.rotation = rotation
        self.zIndex = zIndex
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Creates a default-sized basic shape centered near the middle of an A4 page.
    public static func defaultBasicShape(
        _ shapeKind: BasicShapeKind,
        color: InkColorPreset = .black,
        strokeWidth: CGFloat = 3.0,
        zIndex: Int = 0,
        pageSize: CGSize = PageGeometry.a4Size
    ) -> PageObject {
        let size: CGSize
        switch shapeKind {
        case .rectangle:
            size = CGSize(width: 180, height: 120)
        case .circle:
            size = CGSize(width: 140, height: 140)
        case .arrow, .line:
            size = CGSize(width: 190, height: 36)
        }
        let origin = CGPoint(
            x: (pageSize.width - size.width) * 0.5,
            y: (pageSize.height - size.height) * 0.38
        )
        return PageObject(
            frame: CGRect(origin: origin, size: size),
            rotation: 0,
            zIndex: zIndex,
            kind: .basicShape(kind: shapeKind, strokeColor: color, strokeWidth: strokeWidth)
        )
    }

    /// Creates an image `PageObject` scaled to fit comfortably inside the A4 page while preserving aspect ratio.
    public static func defaultImageObject(
        assetID: UUID,
        intrinsicSize: CGSize,
        zIndex: Int = 0,
        pageSize: CGSize = PageGeometry.a4Size
    ) -> PageObject {
        let maxW: CGFloat = 280
        let maxH: CGFloat = 280
        let safeW = Swift.max(1, intrinsicSize.width)
        let safeH = Swift.max(1, intrinsicSize.height)
        let scale = Swift.min(maxW / safeW, maxH / safeH, 1.0)
        let finalW = Swift.max(Self.minimumDimension, safeW * scale)
        let finalH = Swift.max(Self.minimumDimension, safeH * scale)
        let origin = CGPoint(
            x: (pageSize.width - finalW) * 0.5,
            y: (pageSize.height - finalH) * 0.38
        )
        return PageObject(
            frame: CGRect(x: origin.x, y: origin.y, width: finalW, height: finalH),
            rotation: 0,
            zIndex: zIndex,
            kind: .image(assetID: assetID)
        )
    }

    /// Creates a default-sized structured grid table centered on an A4 page.
    public static func defaultTable(
        rows: Int = 4,
        columns: Int = 3,
        color: InkColorPreset = .black,
        hasHeaderRow: Bool = true,
        zIndex: Int = 0,
        pageSize: CGSize = PageGeometry.a4Size
    ) -> PageObject {
        let safeRows = Swift.max(1, rows)
        let safeCols = Swift.max(1, columns)
        let tableWidth: CGFloat = 460
        let rowHeight: CGFloat = 40.0
        let tableHeight: CGFloat = CGFloat(safeRows) * rowHeight + (hasHeaderRow ? 8.0 : 0.0)
        let origin = CGPoint(
            x: (pageSize.width - tableWidth) * 0.5,
            y: (pageSize.height - tableHeight) * 0.38
        )
        return PageObject(
            frame: CGRect(origin: origin, size: CGSize(width: tableWidth, height: tableHeight)),
            rotation: 0,
            zIndex: zIndex,
            kind: .table(
                rowCount: safeRows,
                columnCount: safeCols,
                columnWidthFractions: nil,
                rowHeightFractions: nil,
                strokeColor: color,
                hasHeaderRow: hasHeaderRow
            )
        )
    }

    /// Creates a default-sized page-link badge pill.
    public static func defaultPageLink(
        targetPageID: UUID,
        targetSectionID: UUID,
        targetNotebookID: UUID,
        title: String,
        zIndex: Int = 0,
        pageSize: CGSize = PageGeometry.a4Size
    ) -> PageObject {
        let badgeWidth: CGFloat = 220
        let badgeHeight: CGFloat = 46
        let origin = CGPoint(
            x: (pageSize.width - badgeWidth) * 0.5,
            y: (pageSize.height - badgeHeight) * 0.38
        )
        return PageObject(
            frame: CGRect(origin: origin, size: CGSize(width: badgeWidth, height: badgeHeight)),
            rotation: 0,
            zIndex: zIndex,
            kind: .pageLink(
                targetPageID: targetPageID,
                targetSectionID: targetSectionID,
                targetNotebookID: targetNotebookID,
                fallbackTitle: title
            )
        )
    }

    // MARK: - Pure Geometric Transforms & Hit Testing

    /// Returns `true` if `pagePoint` (in A4 page coordinates) falls inside this object's (potentially rotated) bounding box, expanded by `tolerance`.
    public func contains(pagePoint: CGPoint, tolerance: CGFloat = 6.0) -> Bool {
        let dx = pagePoint.x - center.x
        let dy = pagePoint.y - center.y
        let cosA = cos(rotation)
        let sinA = sin(rotation)
        let localX = dx * cosA + dy * sinA
        let localY = -dx * sinA + dy * cosA
        let halfW = width * 0.5 + tolerance
        let halfH = height * 0.5 + tolerance
        return abs(localX) <= halfW && abs(localY) <= halfH
    }

    /// Returns a copy translated by `pageDelta` in A4 page points.
    public func moved(by pageDelta: CGSize, now: Date = Date()) -> PageObject {
        var copy = self
        copy.x += pageDelta.width
        copy.y += pageDelta.height
        copy.updatedAt = now
        return copy
    }

    /// Returns a copy resized by dragging `corner` by `pageDelta` (in page coordinates), keeping the opposite corner anchored in page space even when rotated.
    public func resized(
        corner: ObjectResizeCorner,
        pageDelta: CGSize,
        minimumSize: CGFloat = PageObject.minimumDimension,
        now: Date = Date()
    ) -> PageObject {
        let cosA = cos(rotation)
        let sinA = sin(rotation)

        // Convert page-space delta into the object's unrotated local frame
        let localDX = pageDelta.width * cosA + pageDelta.height * sinA
        let localDY = -pageDelta.width * sinA + pageDelta.height * cosA

        var minX = -width * 0.5
        var maxX = width * 0.5
        var minY = -height * 0.5
        var maxY = height * 0.5

        switch corner {
        case .topLeft:
            minX = Swift.min(maxX - minimumSize, minX + localDX)
            minY = Swift.min(maxY - minimumSize, minY + localDY)
        case .topRight:
            maxX = Swift.max(minX + minimumSize, maxX + localDX)
            minY = Swift.min(maxY - minimumSize, minY + localDY)
        case .bottomLeft:
            minX = Swift.min(maxX - minimumSize, minX + localDX)
            maxY = Swift.max(minY + minimumSize, maxY + localDY)
        case .bottomRight:
            maxX = Swift.max(minX + minimumSize, maxX + localDX)
            maxY = Swift.max(minY + minimumSize, maxY + localDY)
        }

        let newW = maxX - minX
        let newH = maxY - minY
        let localCenterOffsetX = (minX + maxX) * 0.5
        let localCenterOffsetY = (minY + maxY) * 0.5

        // Rotate the local center shift back into page space
        let pageCenterShiftX = localCenterOffsetX * cosA - localCenterOffsetY * sinA
        let pageCenterShiftY = localCenterOffsetX * sinA + localCenterOffsetY * cosA

        let newCenter = CGPoint(
            x: center.x + pageCenterShiftX,
            y: center.y + pageCenterShiftY
        )

        var copy = self
        copy.width = newW
        copy.height = newH
        copy.x = newCenter.x - newW * 0.5
        copy.y = newCenter.y - newH * 0.5
        copy.updatedAt = now
        return copy
    }

    /// Lengthens or shortens a `.line` or `.arrow` from either `.start` (left end) or `.end` (right end) along its rotated axis, keeping the opposite end anchored in page space.
    public func resizedEndpoint(
        _ endpoint: LineEndpointHandle,
        pageDelta: CGSize,
        minimumLength: CGFloat = 28.0,
        now: Date = Date()
    ) -> PageObject {
        let cosA = cos(rotation)
        let sinA = sin(rotation)

        // Project page-space drag onto the line's local axis
        let localDX = pageDelta.width * cosA + pageDelta.height * sinA

        var minX = -width * 0.5
        var maxX = width * 0.5

        switch endpoint {
        case .start:
            minX = Swift.min(maxX - minimumLength, minX + localDX)
        case .end:
            maxX = Swift.max(minX + minimumLength, maxX + localDX)
        }

        let newW = maxX - minX
        let localCenterOffsetX = (minX + maxX) * 0.5

        // Shift center along the rotated line axis so the opposite end stays fixed
        let newCenter = CGPoint(
            x: center.x + localCenterOffsetX * cosA,
            y: center.y + localCenterOffsetX * sinA
        )

        var copy = self
        copy.width = newW
        copy.x = newCenter.x - newW * 0.5
        copy.y = newCenter.y - height * 0.5
        copy.updatedAt = now
        return copy
    }

    /// Returns a copy rotated so its top rotate handle points toward `touchPointInPage`.
    /// Because the rotate handle sticks out above the top edge (`local (0, -height/2 - handleOffset)`),
    /// an upright object (`rotation == 0`) has its handle at angle `-π/2` from center.
    public func rotated(toward touchPointInPage: CGPoint, now: Date = Date()) -> PageObject {
        let dx = touchPointInPage.x - center.x
        let dy = touchPointInPage.y - center.y
        guard hypot(dx, dy) > 1.0 else { return self }
        var angle = atan2(dy, dx) + (.pi * 0.5)
        // Normalize to (-π, π]
        while angle <= -.pi { angle += 2 * .pi }
        while angle > .pi { angle -= 2 * .pi }
        var copy = self
        copy.rotation = angle
        copy.updatedAt = now
        return copy
    }

    /// Updates the stroke/tint colour for basic shapes, tables, or stroke-group objects.
    public func recolored(to newColor: InkColorPreset, now: Date = Date()) -> PageObject {
        var copy = self
        switch kind {
        case .basicShape(let shapeKind, _, let strokeWidth):
            copy.kind = .basicShape(kind: shapeKind, strokeColor: newColor, strokeWidth: strokeWidth)
            copy.updatedAt = now
        case .strokeGroup(let data, let w, let h, _):
            copy.kind = .strokeGroup(drawingData: data, sourceBoundsWidth: w, sourceBoundsHeight: h, tintColorOverride: newColor)
            copy.updatedAt = now
        case .table(let rows, let cols, let colFracs, let rowFracs, _, let header):
            copy.kind = .table(
                rowCount: rows,
                columnCount: cols,
                columnWidthFractions: colFracs,
                rowHeightFractions: rowFracs,
                strokeColor: newColor,
                hasHeaderRow: header
            )
            copy.updatedAt = now
        case .image, .pageLink:
            break
        }
        return copy
    }

    /// Appends a new row to the table and expands its height accordingly.
    public func withAddedTableRow(now: Date = Date()) -> PageObject {
        guard case .table(let rows, let cols, let colFracs, _, let strokeColor, let header) = kind else {
            return self
        }
        let newRows = rows + 1
        let rowHeight = height / CGFloat(rows)
        var copy = self
        copy.height += rowHeight
        copy.kind = .table(
            rowCount: newRows,
            columnCount: cols,
            columnWidthFractions: colFracs,
            rowHeightFractions: nil,
            strokeColor: strokeColor,
            hasHeaderRow: header
        )
        copy.updatedAt = now
        return copy
    }

    /// Removes the bottom row from the table (minimum 1 row).
    public func withRemovedTableRow(now: Date = Date()) -> PageObject {
        guard case .table(let rows, let cols, let colFracs, _, let strokeColor, let header) = kind, rows > 1 else {
            return self
        }
        let newRows = rows - 1
        let rowHeight = height / CGFloat(rows)
        var copy = self
        copy.height = Swift.max(Self.minimumDimension, height - rowHeight)
        copy.kind = .table(
            rowCount: newRows,
            columnCount: cols,
            columnWidthFractions: colFracs,
            rowHeightFractions: nil,
            strokeColor: strokeColor,
            hasHeaderRow: header
        )
        copy.updatedAt = now
        return copy
    }

    /// Appends a new column to the table and expands its width accordingly.
    public func withAddedTableColumn(now: Date = Date()) -> PageObject {
        guard case .table(let rows, let cols, _, let rowFracs, let strokeColor, let header) = kind else {
            return self
        }
        let newCols = cols + 1
        let colWidth = width / CGFloat(cols)
        var copy = self
        copy.width += colWidth
        copy.kind = .table(
            rowCount: rows,
            columnCount: newCols,
            columnWidthFractions: nil,
            rowHeightFractions: rowFracs,
            strokeColor: strokeColor,
            hasHeaderRow: header
        )
        copy.updatedAt = now
        return copy
    }

    /// Removes the rightmost column from the table (minimum 1 column).
    public func withRemovedTableColumn(now: Date = Date()) -> PageObject {
        guard case .table(let rows, let cols, _, let rowFracs, let strokeColor, let header) = kind, cols > 1 else {
            return self
        }
        let newCols = cols - 1
        let colWidth = width / CGFloat(cols)
        var copy = self
        copy.width = Swift.max(Self.minimumDimension, width - colWidth)
        copy.kind = .table(
            rowCount: rows,
            columnCount: newCols,
            columnWidthFractions: nil,
            rowHeightFractions: rowFracs,
            strokeColor: strokeColor,
            hasHeaderRow: header
        )
        copy.updatedAt = now
        return copy
    }

    /// Toggles the header row styling for table objects.
    public func withToggledTableHeader(now: Date = Date()) -> PageObject {
        guard case .table(let rows, let cols, let colFracs, let rowFracs, let strokeColor, let header) = kind else {
            return self
        }
        var copy = self
        copy.kind = .table(
            rowCount: rows,
            columnCount: cols,
            columnWidthFractions: colFracs,
            rowHeightFractions: rowFracs,
            strokeColor: strokeColor,
            hasHeaderRow: !header
        )
        copy.updatedAt = now
        return copy
    }

    /// Returns the pixel widths of all columns for a table object, summing exactly to `width`.
    public func tableColumnWidths() -> [CGFloat] {
        guard case .table(_, let colCount, let colFracs, _, _, _) = kind, colCount > 0 else {
            return [width]
        }
        if let fractions = colFracs, fractions.count == colCount {
            let sum = fractions.reduce(0, +)
            if sum > 0.0001 {
                return fractions.map { ($0 / sum) * width }
            }
        }
        let equalW = width / CGFloat(colCount)
        return Array(repeating: equalW, count: colCount)
    }

    /// Returns the pixel heights of all rows for a table object, summing exactly to `height`.
    public func tableRowHeights() -> [CGFloat] {
        guard case .table(let rowCount, _, _, let rowFracs, _, _) = kind, rowCount > 0 else {
            return [height]
        }
        if let fractions = rowFracs, fractions.count == rowCount {
            let sum = fractions.reduce(0, +)
            if sum > 0.0001 {
                return fractions.map { ($0 / sum) * height }
            }
        }
        let equalH = height / CGFloat(rowCount)
        return Array(repeating: equalH, count: rowCount)
    }

    /// Adjusts the column divider between column `dividerIndex` and `dividerIndex + 1` by `pageDelta` (in page points).
    /// Projects page movement into local table space, resizing adjacent columns while preserving total width.
    public func adjustingColumnDivider(at dividerIndex: Int, pageDelta: CGSize, now: Date = Date()) -> PageObject {
        guard case .table(let rowCount, let colCount, _, let rowFracs, let strokeColor, let hasHeaderRow) = kind,
              dividerIndex >= 0, dividerIndex < colCount - 1 else {
            return self
        }
        let cosA = cos(rotation)
        let sinA = sin(rotation)
        let localDeltaX = pageDelta.width * cosA + pageDelta.height * sinA

        var colWidths = tableColumnWidths()
        let minColWidth: CGFloat = 36.0

        let leftW = colWidths[dividerIndex]
        let rightW = colWidths[dividerIndex + 1]

        var actualDelta = localDeltaX
        if leftW + actualDelta < minColWidth {
            actualDelta = minColWidth - leftW
        } else if rightW - actualDelta < minColWidth {
            actualDelta = rightW - minColWidth
        }

        colWidths[dividerIndex] = leftW + actualDelta
        colWidths[dividerIndex + 1] = rightW - actualDelta

        let total = colWidths.reduce(0, +)
        let newFractions = colWidths.map { $0 / total }

        var copy = self
        copy.kind = .table(
            rowCount: rowCount,
            columnCount: colCount,
            columnWidthFractions: newFractions,
            rowHeightFractions: rowFracs,
            strokeColor: strokeColor,
            hasHeaderRow: hasHeaderRow
        )
        copy.updatedAt = now
        return copy
    }

    /// Adjusts table row heights uniformly by `pageDelta` (in page points).
    /// Smoothly expands or shrinks all rows equally, updating the total table height.
    public func adjustingTableRowHeight(pageDelta: CGSize, now: Date = Date()) -> PageObject {
        guard case .table(let rowCount, let colCount, let colFracs, _, let strokeColor, let hasHeaderRow) = kind,
              rowCount > 0 else {
            return self
        }
        let cosA = cos(rotation)
        let sinA = sin(rotation)
        let localDeltaY = -pageDelta.width * sinA + pageDelta.height * cosA

        let minRowHeight: CGFloat = 24.0
        let currentHeights = tableRowHeights()
        let currentAvgHeight = currentHeights.reduce(0, +) / CGFloat(rowCount)
        let newRowHeight = Swift.max(minRowHeight, currentAvgHeight + (localDeltaY / CGFloat(rowCount)))

        var copy = self
        copy.height = newRowHeight * CGFloat(rowCount)
        copy.kind = .table(
            rowCount: rowCount,
            columnCount: colCount,
            columnWidthFractions: colFracs,
            rowHeightFractions: nil,
            strokeColor: strokeColor,
            hasHeaderRow: hasHeaderRow
        )
        copy.updatedAt = now
        return copy
    }

    /// Updates the stroke width for basic shapes.
    public func withStrokeWidth(_ newWidth: CGFloat, now: Date = Date()) -> PageObject {
        var copy = self
        if case .basicShape(let shapeKind, let color, _) = kind {
            let clamped = Swift.min(Swift.max(newWidth, DrawingToolState.widthRange.lowerBound), DrawingToolState.widthRange.upperBound)
            copy.kind = .basicShape(kind: shapeKind, strokeColor: color, strokeWidth: clamped)
            copy.updatedAt = now
        }
        return copy
    }
}
