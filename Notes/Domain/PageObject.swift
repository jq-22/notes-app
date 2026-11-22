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

/// Horizontal text alignment inside a `.textBox` `PageObject`.
public enum TextBoxAlignment: String, Codable, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case leading
    case center
    case trailing

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .leading: return "Left"
        case .center: return "Center"
        case .trailing: return "Right"
        }
    }

    public var systemImageName: String {
        switch self {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = TextBoxAlignment(rawValue: raw) ?? .leading
    }
}

/// Font family / design for a `.textBox` or `.table` text styling.
public enum TextBoxFontDesign: String, Codable, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case standard
    case serif
    case monospaced
    case rounded

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard: return "Default"
        case .serif: return "Serif"
        case .monospaced: return "Mono"
        case .rounded: return "Rounded"
        }
    }

    public var systemImageName: String {
        switch self {
        case .standard: return "textformat"
        case .serif: return "character.book.closed"
        case .monospaced: return "chevron.left.forwardslash.chevron.right"
        case .rounded: return "character.circle"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = TextBoxFontDesign(rawValue: raw) ?? .standard
    }
}

/// Whole-card typography and card-appearance styling for a `.textBox` `PageObject`.
public struct TextBoxStyle: Codable, Equatable, Hashable, Sendable {
    public static let fontSizeRange: ClosedRange<CGFloat> = 10.0...72.0
    public static let defaultFontSize: CGFloat = 16.0

    public var fontSize: CGFloat
    public var fontDesign: TextBoxFontDesign
    public var isBold: Bool
    public var isItalic: Bool
    public var alignment: TextBoxAlignment
    public var textColor: InkColorPreset
    public var backgroundColor: InkColorPreset?
    public var borderColor: InkColorPreset?

    private enum CodingKeys: String, CodingKey {
        case fontSize
        case fontDesign
        case isBold
        case isItalic
        case alignment
        case textColor
        case backgroundColor
        case borderColor
    }

    public init(
        fontSize: CGFloat = TextBoxStyle.defaultFontSize,
        fontDesign: TextBoxFontDesign = .standard,
        isBold: Bool = false,
        isItalic: Bool = false,
        alignment: TextBoxAlignment = .leading,
        textColor: InkColorPreset = .black,
        backgroundColor: InkColorPreset? = nil,
        borderColor: InkColorPreset? = nil
    ) {
        self.fontSize = Self.clampedFontSize(fontSize)
        self.fontDesign = fontDesign
        self.isBold = isBold
        self.isItalic = isItalic
        self.alignment = alignment
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? Self.defaultFontSize
        self.fontSize = Self.clampedFontSize(decodedFontSize)
        self.fontDesign = try container.decodeIfPresent(TextBoxFontDesign.self, forKey: .fontDesign) ?? .standard
        self.isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        self.isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        self.alignment = try container.decodeIfPresent(TextBoxAlignment.self, forKey: .alignment) ?? .leading
        self.textColor = try container.decodeIfPresent(InkColorPreset.self, forKey: .textColor) ?? .black
        self.backgroundColor = try container.decodeIfPresent(InkColorPreset.self, forKey: .backgroundColor)
        self.borderColor = try container.decodeIfPresent(InkColorPreset.self, forKey: .borderColor)
    }

    public static func clampedFontSize(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return defaultFontSize }
        return Swift.min(Swift.max(value, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }
}

/// Structured grid table configuration, styling, and cell text storage.
public struct TableProperties: Codable, Equatable, Hashable, Sendable {
    public var rowCount: Int
    public var columnCount: Int
    public var columnWidthFractions: [CGFloat]?
    public var rowHeightFractions: [CGFloat]?
    public var strokeColor: InkColorPreset
    public var hasHeaderRow: Bool
    public var isStriped: Bool
    public var isTextMode: Bool
    public var cellTexts: [String: String]
    public var textStyle: TextBoxStyle

    public init(
        rowCount: Int = 4,
        columnCount: Int = 3,
        columnWidthFractions: [CGFloat]? = nil,
        rowHeightFractions: [CGFloat]? = nil,
        strokeColor: InkColorPreset = .black,
        hasHeaderRow: Bool = true,
        isStriped: Bool = false,
        isTextMode: Bool = false,
        cellTexts: [String: String] = [:],
        textStyle: TextBoxStyle = TextBoxStyle(fontSize: 14)
    ) {
        self.rowCount = Swift.max(1, rowCount)
        self.columnCount = Swift.max(1, columnCount)
        self.columnWidthFractions = columnWidthFractions
        self.rowHeightFractions = rowHeightFractions
        self.strokeColor = strokeColor
        self.hasHeaderRow = hasHeaderRow
        self.isStriped = isStriped
        self.isTextMode = isTextMode
        self.cellTexts = cellTexts
        self.textStyle = textStyle
    }

    public func text(forRow row: Int, column col: Int) -> String {
        cellTexts["\(row),\(col)"] ?? ""
    }

    public mutating func setText(_ text: String, forRow row: Int, column col: Int) {
        let key = "\(row),\(col)"
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cellTexts.removeValue(forKey: key)
        } else {
            cellTexts[key] = text
        }
    }
}

/// Payload type for a `PageObject`.
public enum PageObjectKind: Equatable, Hashable, Sendable {
    /// A vector geometric shape drawn with a chosen colour and stroke width.
    case basicShape(kind: BasicShapeKind, strokeColor: InkColorPreset, strokeWidth: CGFloat)
    /// An imported image whose binary data is stored on disk via `PageStore` under `assetID`.
    case image(assetID: UUID)
    /// A group of PencilKit strokes (from Lasso Copy/Paste or the Notebook Shape Library) that can be moved, resized, rotated, and recoloured.
    case strokeGroup(drawingData: Data, sourceBoundsWidth: CGFloat, sourceBoundsHeight: CGFloat, tintColorOverride: InkColorPreset?)
    /// A structured grid table for handwritten or typed notes where each cell has a fixed size and text is clipped without spilling.
    case table(TableProperties)
    /// A link to another page in the notebook hierarchy (by permanent UUID).
    case pageLink(
        targetPageID: UUID,
        targetSectionID: UUID,
        targetNotebookID: UUID,
        fallbackTitle: String
    )
    /// An inline-editable typed text card with whole-card typography and card appearance styling.
    case textBox(
        text: String,
        style: TextBoxStyle
    )
}

extension PageObjectKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case basicShape
        case image
        case strokeGroup
        case table
        case pageLink
        case textBox
    }

    private enum LegacyTableKeys: String, CodingKey {
        case _0 // rowCount
        case _1 // columnCount
        case _2 // columnWidthFractions
        case _3 // rowHeightFractions
        case _4 // strokeColor
        case _5 // hasHeaderRow
        case _6 // isStriped
        case _7 // isTextMode
        case _8 // cellTexts
        case _9 // textStyle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.basicShape) {
            struct BasicShapePayload: Codable {
                let _0: BasicShapeKind
                let _1: InkColorPreset
                let _2: CGFloat
            }
            let payload = try container.decode(BasicShapePayload.self, forKey: .basicShape)
            self = .basicShape(kind: payload._0, strokeColor: payload._1, strokeWidth: payload._2)
        } else if container.contains(.image) {
            struct ImagePayload: Codable {
                let assetID: UUID
            }
            let payload = try container.decode(ImagePayload.self, forKey: .image)
            self = .image(assetID: payload.assetID)
        } else if container.contains(.strokeGroup) {
            struct StrokeGroupPayload: Codable {
                let _0: Data
                let _1: CGFloat
                let _2: CGFloat
                let _3: InkColorPreset?
            }
            let payload = try container.decode(StrokeGroupPayload.self, forKey: .strokeGroup)
            self = .strokeGroup(drawingData: payload._0, sourceBoundsWidth: payload._1, sourceBoundsHeight: payload._2, tintColorOverride: payload._3)
        } else if container.contains(.pageLink) {
            struct PageLinkPayload: Codable {
                let _0: UUID
                let _1: UUID
                let _2: UUID
                let _3: String
            }
            let payload = try container.decode(PageLinkPayload.self, forKey: .pageLink)
            self = .pageLink(targetPageID: payload._0, targetSectionID: payload._1, targetNotebookID: payload._2, fallbackTitle: payload._3)
        } else if container.contains(.textBox) {
            struct PositionalTextBoxPayload: Codable {
                let _0: String
                let _1: TextBoxStyle
            }
            struct NamedTextBoxPayload: Codable {
                let text: String
                let style: TextBoxStyle?
            }
            if let pos = try? container.decode(PositionalTextBoxPayload.self, forKey: .textBox) {
                self = .textBox(text: pos._0, style: pos._1)
            } else if let named = try? container.decode(NamedTextBoxPayload.self, forKey: .textBox) {
                self = .textBox(text: named.text, style: named.style ?? TextBoxStyle())
            } else {
                let payload = try container.decode(PositionalTextBoxPayload.self, forKey: .textBox)
                self = .textBox(text: payload._0, style: payload._1)
            }
        } else if container.contains(.table) {
            if let directProps = try? container.decode(TableProperties.self, forKey: .table) {
                self = .table(directProps)
            } else {
                let tableContainer = try container.nestedContainer(keyedBy: LegacyTableKeys.self, forKey: .table)
                let rows = try tableContainer.decode(Int.self, forKey: ._0)
                let cols = try tableContainer.decode(Int.self, forKey: ._1)
                let colFracs = try tableContainer.decodeIfPresent([CGFloat].self, forKey: ._2)
                let rowFracs = try tableContainer.decodeIfPresent([CGFloat].self, forKey: ._3)
                let strokeColor = try tableContainer.decode(InkColorPreset.self, forKey: ._4)
                let hasHeader = try tableContainer.decode(Bool.self, forKey: ._5)
                let isStriped = try tableContainer.decodeIfPresent(Bool.self, forKey: ._6) ?? false
                let isTextMode = try tableContainer.decodeIfPresent(Bool.self, forKey: ._7) ?? false
                let cellTexts = try tableContainer.decodeIfPresent([String: String].self, forKey: ._8) ?? [:]
                let textStyle = try tableContainer.decodeIfPresent(TextBoxStyle.self, forKey: ._9) ?? TextBoxStyle(fontSize: 14)
                self = .table(TableProperties(
                    rowCount: rows,
                    columnCount: cols,
                    columnWidthFractions: colFracs,
                    rowHeightFractions: rowFracs,
                    strokeColor: strokeColor,
                    hasHeaderRow: hasHeader,
                    isStriped: isStriped,
                    isTextMode: isTextMode,
                    cellTexts: cellTexts,
                    textStyle: textStyle
                ))
            }
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown PageObjectKind")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .basicShape(let kind, let color, let width):
            struct BasicShapePayload: Codable {
                let _0: BasicShapeKind
                let _1: InkColorPreset
                let _2: CGFloat
            }
            try container.encode(BasicShapePayload(_0: kind, _1: color, _2: width), forKey: .basicShape)
        case .image(let assetID):
            struct ImagePayload: Codable {
                let assetID: UUID
            }
            try container.encode(ImagePayload(assetID: assetID), forKey: .image)
        case .strokeGroup(let data, let w, let h, let tint):
            struct StrokeGroupPayload: Codable {
                let _0: Data
                let _1: CGFloat
                let _2: CGFloat
                let _3: InkColorPreset?
            }
            try container.encode(StrokeGroupPayload(_0: data, _1: w, _2: h, _3: tint), forKey: .strokeGroup)
        case .table(let props):
            try container.encode(props, forKey: .table)
        case .pageLink(let pageID, let secID, let nbID, let title):
            struct PageLinkPayload: Codable {
                let _0: UUID
                let _1: UUID
                let _2: UUID
                let _3: String
            }
            try container.encode(PageLinkPayload(_0: pageID, _1: secID, _2: nbID, _3: title), forKey: .pageLink)
        case .textBox(let text, let style):
            struct TextBoxPayload: Codable {
                let _0: String
                let _1: TextBoxStyle
            }
            try container.encode(TextBoxPayload(_0: text, _1: style), forKey: .textBox)
        }
    }
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

    private enum CodingKeys: String, CodingKey {
        case id
        case x
        case y
        case width
        case height
        case rotation
        case zIndex
        case kind
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        let rawX = try container.decode(CGFloat.self, forKey: .x)
        let rawY = try container.decode(CGFloat.self, forKey: .y)
        let rawWidth = try container.decode(CGFloat.self, forKey: .width)
        let rawHeight = try container.decode(CGFloat.self, forKey: .height)
        let rawRotation = try container.decode(CGFloat.self, forKey: .rotation)
        self.x = rawX.isFinite ? rawX : 0
        self.y = rawY.isFinite ? rawY : 0
        self.width = rawWidth.isFinite ? Swift.max(Self.minimumDimension, rawWidth) : Self.minimumDimension
        self.height = rawHeight.isFinite ? Swift.max(Self.minimumDimension, rawHeight) : Self.minimumDimension
        self.rotation = rawRotation.isFinite ? rawRotation : 0
        self.zIndex = try container.decode(Int.self, forKey: .zIndex)
        self.kind = try container.decode(PageObjectKind.self, forKey: .kind)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

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
        isStriped: Bool = false,
        isTextMode: Bool = false,
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
        let props = TableProperties(
            rowCount: safeRows,
            columnCount: safeCols,
            columnWidthFractions: nil,
            rowHeightFractions: nil,
            strokeColor: color,
            hasHeaderRow: hasHeaderRow,
            isStriped: isStriped,
            isTextMode: isTextMode,
            cellTexts: [:],
            textStyle: TextBoxStyle(fontSize: 14)
        )
        return PageObject(
            frame: CGRect(origin: origin, size: CGSize(width: tableWidth, height: tableHeight)),
            rotation: 0,
            zIndex: zIndex,
            kind: .table(props)
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

    /// Creates a default-sized inline-editable text box card centered on an A4 page.
    public static func defaultTextBox(
        text: String = "",
        style: TextBoxStyle = TextBoxStyle(),
        zIndex: Int = 0,
        pageSize: CGSize = PageGeometry.a4Size
    ) -> PageObject {
        let boxWidth: CGFloat = 260
        let boxHeight: CGFloat = 110
        let origin = CGPoint(
            x: (pageSize.width - boxWidth) * 0.5,
            y: (pageSize.height - boxHeight) * 0.38
        )
        return PageObject(
            frame: CGRect(origin: origin, size: CGSize(width: boxWidth, height: boxHeight)),
            rotation: 0,
            zIndex: zIndex,
            kind: .textBox(text: text, style: style)
        )
    }

    // MARK: - Pure Geometric Transforms & Hit Testing

    /// Returns the four corner points of this object in A4 page coordinates, accounting for `rotation` around `center`.
    public func rotatedCorners() -> [CGPoint] {
        let halfW = width * 0.5
        let halfH = height * 0.5
        let cosA = cos(rotation)
        let sinA = sin(rotation)
        let localCorners = [
            CGPoint(x: -halfW, y: -halfH),
            CGPoint(x: halfW, y: -halfH),
            CGPoint(x: halfW, y: halfH),
            CGPoint(x: -halfW, y: halfH)
        ]
        return localCorners.map { local in
            CGPoint(
                x: center.x + local.x * cosA - local.y * sinA,
                y: center.y + local.x * sinA + local.y * cosA
            )
        }
    }

    /// Returns the axis-aligned bounding box enclosing all four `rotatedCorners()` in A4 page coordinates.
    public func rotatedBoundingBox() -> CGRect {
        let corners = rotatedCorners()
        guard let first = corners.first else { return frame }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for pt in corners.dropFirst() {
            minX = Swift.min(minX, pt.x)
            maxX = Swift.max(maxX, pt.x)
            minY = Swift.min(minY, pt.y)
            maxY = Swift.max(maxY, pt.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

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

    /// Accessor for table properties when `kind` is `.table`.
    public var tableProperties: TableProperties? {
        get {
            if case .table(let props) = kind { return props }
            return nil
        }
        set {
            if let newValue {
                kind = .table(newValue)
            }
        }
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
        case .table(var table):
            table.strokeColor = newColor
            copy.kind = .table(table)
            copy.updatedAt = now
        case .textBox(let text, var style):
            style.textColor = newColor
            copy.kind = .textBox(text: text, style: style)
            copy.updatedAt = now
        case .image, .pageLink:
            break
        }
        return copy
    }

    /// Updates the text content of a `.textBox` object.
    public func withText(_ newText: String, now: Date = Date()) -> PageObject {
        guard case .textBox(_, let style) = kind else {
            return self
        }
        var copy = self
        copy.kind = .textBox(text: newText, style: style)
        copy.updatedAt = now
        return copy
    }

    /// Updates the whole-card `TextBoxStyle` of a `.textBox` object (clamping `fontSize` to `TextBoxStyle.fontSizeRange`).
    public func withTextBoxStyle(_ newStyle: TextBoxStyle, now: Date = Date()) -> PageObject {
        guard case .textBox(let text, _) = kind else {
            return self
        }
        var sanitized = newStyle
        sanitized.fontSize = TextBoxStyle.clampedFontSize(newStyle.fontSize)
        var copy = self
        copy.kind = .textBox(text: text, style: sanitized)
        copy.updatedAt = now
        return copy
    }

    /// Appends a new row to the table and expands its height accordingly.
    public func withAddedTableRow(now: Date = Date()) -> PageObject {
        guard var table = tableProperties else { return self }
        let newRows = table.rowCount + 1
        let rowHeight = height / CGFloat(table.rowCount)
        table.rowCount = newRows
        table.rowHeightFractions = nil
        var copy = self
        copy.height += rowHeight
        copy.kind = .table(table)
        copy.updatedAt = now
        return copy
    }

    /// Removes the bottom row from the table (minimum 1 row).
    public func withRemovedTableRow(now: Date = Date()) -> PageObject {
        guard var table = tableProperties, table.rowCount > 1 else { return self }
        let rowHeight = height / CGFloat(table.rowCount)
        let removedRow = table.rowCount - 1
        for c in 0..<table.columnCount {
            table.cellTexts.removeValue(forKey: "\(removedRow),\(c)")
        }
        table.rowCount -= 1
        table.rowHeightFractions = nil
        var copy = self
        copy.height = Swift.max(Self.minimumDimension, height - rowHeight)
        copy.kind = .table(table)
        copy.updatedAt = now
        return copy
    }

    /// Appends a new column to the table and expands its width accordingly.
    public func withAddedTableColumn(now: Date = Date()) -> PageObject {
        guard var table = tableProperties else { return self }
        let newCols = table.columnCount + 1
        let colWidth = width / CGFloat(table.columnCount)
        table.columnCount = newCols
        table.columnWidthFractions = nil
        var copy = self
        copy.width += colWidth
        copy.kind = .table(table)
        copy.updatedAt = now
        return copy
    }

    /// Removes the rightmost column from the table (minimum 1 column).
    public func withRemovedTableColumn(now: Date = Date()) -> PageObject {
        guard var table = tableProperties, table.columnCount > 1 else { return self }
        let colWidth = width / CGFloat(table.columnCount)
        let removedCol = table.columnCount - 1
        for r in 0..<table.rowCount {
            table.cellTexts.removeValue(forKey: "\(r),\(removedCol)")
        }
        table.columnCount -= 1
        table.columnWidthFractions = nil
        var copy = self
        copy.width = Swift.max(Self.minimumDimension, width - colWidth)
        copy.kind = .table(table)
        copy.updatedAt = now
        return copy
    }

    /// Toggles the header row styling for table objects.
    public func withToggledTableHeader(now: Date = Date()) -> PageObject {
        guard var table = tableProperties else { return self }
        table.hasHeaderRow.toggle()
        var copy = self
        copy.kind = .table(table)
        copy.updatedAt = now
        return copy
    }

    /// Toggles alternating row shading ("zebra stripes") for table objects.
    public func withToggledTableStriping(now: Date = Date()) -> PageObject {
        guard var table = tableProperties else { return self }
        table.isStriped.toggle()
        var copy = self
        copy.kind = .table(table)
        copy.updatedAt = now
        return copy
    }

    /// Toggles between Draw Mode (pencil inking) and Text Mode (typed cell text).
    public func withToggledTableTextMode(now: Date = Date()) -> PageObject {
        guard var table = tableProperties else { return self }
        table.isTextMode.toggle()
        var copy = self
        copy.kind = .table(table)
        copy.updatedAt = now
        return copy
    }

    /// Sets the text content for a single cell in a table.
    public func withTableCellText(row: Int, column col: Int, text: String, now: Date = Date()) -> PageObject {
        guard var table = tableProperties else { return self }
        table.setText(text, forRow: row, column: col)
        var copy = self
        copy.kind = .table(table)
        copy.updatedAt = now
        return copy
    }

    /// Updates the text styling for all cells in a table.
    public func withTableTextStyle(_ newStyle: TextBoxStyle, now: Date = Date()) -> PageObject {
        guard var table = tableProperties else { return self }
        table.textStyle = newStyle
        var copy = self
        copy.kind = .table(table)
        copy.updatedAt = now
        return copy
    }

    /// Updates the outline/grid stroke color for a table.
    public func withTableStrokeColor(_ newColor: InkColorPreset, now: Date = Date()) -> PageObject {
        guard var table = tableProperties else { return self }
        table.strokeColor = newColor
        var copy = self
        copy.kind = .table(table)
        copy.updatedAt = now
        return copy
    }

    /// Returns the pixel widths of all columns for a table object, summing exactly to `width`.
    public func tableColumnWidths() -> [CGFloat] {
        guard let table = tableProperties, table.columnCount > 0 else {
            return [width]
        }
        if let fractions = table.columnWidthFractions, fractions.count == table.columnCount {
            let sum = fractions.reduce(0, +)
            if sum > 0.0001 {
                return fractions.map { ($0 / sum) * width }
            }
        }
        let equalW = width / CGFloat(table.columnCount)
        return Array(repeating: equalW, count: table.columnCount)
    }

    /// Returns the pixel heights of all rows for a table object, summing exactly to `height`.
    public func tableRowHeights() -> [CGFloat] {
        guard let table = tableProperties, table.rowCount > 0 else {
            return [height]
        }
        if let fractions = table.rowHeightFractions, fractions.count == table.rowCount {
            let sum = fractions.reduce(0, +)
            if sum > 0.0001 {
                return fractions.map { ($0 / sum) * height }
            }
        }
        let equalH = height / CGFloat(table.rowCount)
        return Array(repeating: equalH, count: table.rowCount)
    }

    /// Adjusts the column divider between column `dividerIndex` and `dividerIndex + 1` by `pageDelta` (in page points).
    /// Projects page movement into local table space, resizing adjacent columns while preserving total width.
    public func adjustingColumnDivider(at dividerIndex: Int, pageDelta: CGSize, now: Date = Date()) -> PageObject {
        guard var table = tableProperties, dividerIndex >= 0, dividerIndex < table.columnCount - 1 else {
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
        table.columnWidthFractions = colWidths.map { $0 / total }

        var copy = self
        copy.kind = .table(table)
        copy.updatedAt = now
        return copy
    }

    /// Adjusts table row heights uniformly by `pageDelta` (in page points).
    /// Smoothly expands or shrinks all rows equally, updating the total table height.
    public func adjustingTableRowHeight(pageDelta: CGSize, now: Date = Date()) -> PageObject {
        guard var table = tableProperties, table.rowCount > 0 else {
            return self
        }
        let cosA = cos(rotation)
        let sinA = sin(rotation)
        let localDeltaY = -pageDelta.width * sinA + pageDelta.height * cosA

        let minRowHeight: CGFloat = 24.0
        let currentHeights = tableRowHeights()
        let currentAvgHeight = currentHeights.reduce(0, +) / CGFloat(table.rowCount)
        let newRowHeight = Swift.max(minRowHeight, currentAvgHeight + (localDeltaY / CGFloat(table.rowCount)))

        table.rowHeightFractions = nil
        var copy = self
        copy.height = newRowHeight * CGFloat(table.rowCount)
        copy.kind = .table(table)
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
