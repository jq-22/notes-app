//
//  PageObjectTests.swift
//  NotesTests
//
//  Responsibility: Unit tests for Milestone v1b `PageObject` geometry (move, 4-corner resize with opposite-corner anchoring, rotation, recolouring, rotated hit testing) and backwards-compatible `Page` JSON decoding from v1a.
//

import CoreGraphics
import Foundation
import Testing
@testable import Notes

@Suite("Domain — PageObject & v1b Geometry")
struct PageObjectTests {

    @Test("Moving and 4-corner resizing keep the opposite corner anchored and clamp to minimum size")
    func moveAndFourCornerResizeAnchorOppositeCorner() {
        let initial = PageObject(
            frame: CGRect(x: 100, y: 200, width: 160, height: 100),
            rotation: 0,
            kind: .basicShape(kind: .rectangle, strokeColor: .black, strokeWidth: 3.0)
        )

        // 1. Move by (+30, -20)
        let moved = initial.moved(by: CGSize(width: 30, height: -20))
        #expect(moved.frame == CGRect(x: 130, y: 180, width: 160, height: 100))

        // 2. Drag bottomRight corner by (+40, +50): topLeft (100, 200) must remain anchored
        let resizedBR = initial.resized(corner: .bottomRight, pageDelta: CGSize(width: 40, height: 50))
        #expect(abs(resizedBR.frame.minX - 100) < 0.001)
        #expect(abs(resizedBR.frame.minY - 200) < 0.001)
        #expect(abs(resizedBR.frame.width - 200) < 0.001)
        #expect(abs(resizedBR.frame.height - 150) < 0.001)

        // 3. Drag topLeft corner by (-20, -30): bottomRight (260, 300) must remain anchored
        let resizedTL = initial.resized(corner: .topLeft, pageDelta: CGSize(width: -20, height: -30))
        #expect(abs(resizedTL.frame.maxX - 260) < 0.001)
        #expect(abs(resizedTL.frame.maxY - 300) < 0.001)
        #expect(abs(resizedTL.frame.width - 180) < 0.001)
        #expect(abs(resizedTL.frame.height - 130) < 0.001)

        // 4. Shrinking past minimumDimension clamps cleanly
        let clamped = initial.resized(corner: .bottomRight, pageDelta: CGSize(width: -500, height: -500))
        #expect(abs(clamped.width - PageObject.minimumDimension) < 0.001)
        #expect(abs(clamped.height - PageObject.minimumDimension) < 0.001)

        // 5. Line & Arrow endpoint lengthening/shortening keeps the opposite end anchored
        let lineObj = PageObject.defaultBasicShape(.arrow, color: .black, strokeWidth: 3.0)
        #expect(lineObj.usesLinearEndpointHandles == true)
        let originalLeftX = lineObj.frame.minX
        let originalRightX = lineObj.frame.maxX

        let lengthenedRight = lineObj.resizedEndpoint(.end, pageDelta: CGSize(width: 50, height: 0))
        #expect(abs(lengthenedRight.frame.minX - originalLeftX) < 0.001)
        #expect(abs(lengthenedRight.frame.maxX - (originalRightX + 50)) < 0.001)

        let lengthenedLeft = lineObj.resizedEndpoint(.start, pageDelta: CGSize(width: -40, height: 0))
        #expect(abs(lengthenedLeft.frame.maxX - originalRightX) < 0.001)
        #expect(abs(lengthenedLeft.frame.minX - (originalLeftX - 40)) < 0.001)
    }

    @Test("Rotate handle angle calculation and rotated hit testing")
    func rotateAndRotatedHitTest() {
        let obj = PageObject(
            frame: CGRect(x: 200, y: 300, width: 100, height: 100), // center = (250, 350)
            rotation: 0,
            kind: .basicShape(kind: .arrow, strokeColor: .blue, strokeWidth: 3.0)
        )

        // Dragging the top rotate handle directly to the right of center (350, 350) rotates by +90° (π/2)
        let rotatedRight = obj.rotated(toward: CGPoint(x: 350, y: 350))
        #expect(abs(rotatedRight.rotation - (.pi * 0.5)) < 0.001)

        // Dragging directly above center (250, 250) returns to 0 radians
        let rotatedUp = rotatedRight.rotated(toward: CGPoint(x: 250, y: 250))
        #expect(abs(rotatedUp.rotation - 0.0) < 0.001)

        // Hit-test inside and outside
        #expect(obj.contains(pagePoint: CGPoint(x: 250, y: 350)))
        #expect(!obj.contains(pagePoint: CGPoint(x: 50, y: 50)))
    }

    @Test("Recolouring basic shapes and aspect-preserving image placement")
    func recolorAndDefaultImageAspectRatio() {
        let shape = PageObject.defaultBasicShape(.circle, color: .black, strokeWidth: 3.0)
        let recolored = shape.recolored(to: .red)
        if case .basicShape(let kind, let color, _) = recolored.kind {
            #expect(kind == .circle)
            #expect(color == .red)
        } else {
            Issue.record("Expected basicShape kind")
        }

        let assetID = UUID()
        let imgObj = PageObject.defaultImageObject(assetID: assetID, intrinsicSize: CGSize(width: 1000, height: 500))
        #expect(abs((imgObj.width / imgObj.height) - 2.0) < 0.01)
        #expect(imgObj.width <= 280.0)
    }

    @Test("Backward-compatible decoding of v1a Page JSON without objects key")
    func backwardCompatibleV1aPageJSONDecoding() throws {
        let v1aJSON = """
        {
          "createdAt" : 782950000,
          "id" : "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          "paperTypeOverride" : "squared",
          "title" : "Lecture 1",
          "updatedAt" : 782950100
        }
        """.data(using: .utf8)!

        let decodedPage = try JSONDecoder().decode(Page.self, from: v1aJSON)
        #expect(decodedPage.title == "Lecture 1")
        #expect(decodedPage.paperTypeOverride == .squared)
        #expect(decodedPage.objects.isEmpty)
    }

    @Test("Table PageObject creation, row/column addition, removal, header toggle, and recolouring")
    func tableObjectOperationsAndGridMath() {
        let table = PageObject.defaultTable(rows: 4, columns: 3, color: .black, hasHeaderRow: true)
        #expect(table.width == 460)
        if case .table(let props) = table.kind {
            #expect(props.rowCount == 4)
            #expect(props.columnCount == 3)
            #expect(props.strokeColor == .black)
            #expect(props.hasHeaderRow == true)
            #expect(props.isTextMode == false) // Auto-selected to Draw Mode
        } else {
            Issue.record("Expected table kind")
        }

        // Add row
        let withRow = table.withAddedTableRow()
        if case .table(let props) = withRow.kind {
            #expect(props.rowCount == 5)
            #expect(withRow.height > table.height)
        }

        // Remove row
        let withoutRow = withRow.withRemovedTableRow()
        if case .table(let props) = withoutRow.kind {
            #expect(props.rowCount == 4)
        }

        // Add column
        let withCol = table.withAddedTableColumn()
        if case .table(let props) = withCol.kind {
            #expect(props.columnCount == 4)
            #expect(withCol.width > table.width)
        }

        // Remove column
        let withoutCol = withCol.withRemovedTableColumn()
        if case .table(let props) = withoutCol.kind {
            #expect(props.columnCount == 3)
        }

        // Toggle header
        let toggledHeader = table.withToggledTableHeader()
        if case .table(let props) = toggledHeader.kind {
            #expect(props.hasHeaderRow == false)
        }

        // Recolour
        let blueTable = table.recolored(to: .blue)
        if case .table(let props) = blueTable.kind {
            #expect(props.strokeColor == .blue)
        }

        // Adjust column divider: expand column 0 by 30pt, shrinking column 1 by 30pt
        let initialColWidths = table.tableColumnWidths()
        let adjustedCols = table.adjustingColumnDivider(at: 0, pageDelta: CGSize(width: 30, height: 0))
        let newColWidths = adjustedCols.tableColumnWidths()
        #expect(abs(newColWidths[0] - (initialColWidths[0] + 30)) < 0.01)
        #expect(abs(newColWidths[1] - (initialColWidths[1] - 30)) < 0.01)
        #expect(abs(newColWidths.reduce(0, +) - table.width) < 0.01)

        // Adjust row height uniformly: expand all rows by delta
        let initialHeights = table.tableRowHeights()
        let adjustedRows = table.adjustingTableRowHeight(pageDelta: CGSize(width: 0, height: 40))
        let newHeights = adjustedRows.tableRowHeights()
        #expect(adjustedRows.height > table.height)
        #expect(newHeights.allSatisfy { abs($0 - newHeights[0]) < 0.01 })
    }

    @Test("PageLink PageObject creation and properties")
    func pageLinkBadgeCreationAndProperties() {
        let targetPageID = UUID()
        let targetSecID = UUID()
        let targetNbID = UUID()

        let link = PageObject.defaultPageLink(
            targetPageID: targetPageID,
            targetSectionID: targetSecID,
            targetNotebookID: targetNbID,
            title: "Linear Algebra Summary"
        )

        #expect(link.width == 220)
        #expect(link.height == 46)
        if case .pageLink(let pgID, let secID, let nbID, let title) = link.kind {
            #expect(pgID == targetPageID)
            #expect(secID == targetSecID)
            #expect(nbID == targetNbID)
            #expect(title == "Linear Algebra Summary")
        } else {
            Issue.record("Expected pageLink kind")
        }
    }

    @Test("TextBox PageObject creation, styling defaults, clamping, mutators, and recolouring")
    func textBoxCreationStylingAndMutators() throws {
        let defaultBox = PageObject.defaultTextBox(text: "System Overview")
        #expect(defaultBox.usesLinearEndpointHandles == false)
        #expect(defaultBox.width == 260)
        #expect(defaultBox.height == 110)

        guard case .textBox(let initialText, let initialStyle) = defaultBox.kind else {
            Issue.record("Expected textBox kind")
            return
        }
        #expect(initialText == "System Overview")
        #expect(initialStyle.fontSize == 16.0)
        #expect(initialStyle.isBold == false)
        #expect(initialStyle.isItalic == false)
        #expect(initialStyle.alignment == .leading)
        #expect(initialStyle.textColor == .black)
        #expect(initialStyle.backgroundColor == nil)
        #expect(initialStyle.borderColor == nil)

        // Font size clamping in init and withTextBoxStyle
        let clampedLow = TextBoxStyle(fontSize: 2.0)
        let clampedHigh = TextBoxStyle(fontSize: 200.0)
        #expect(clampedLow.fontSize == 10.0)
        #expect(clampedHigh.fontSize == 72.0)

        let t1 = Date(timeIntervalSince1970: 5000)
        let updatedText = defaultBox.withText("Updated Body", now: t1)
        #expect(updatedText.updatedAt == t1)
        if case .textBox(let text, _) = updatedText.kind {
            #expect(text == "Updated Body")
        }

        let customStyle = TextBoxStyle(
            fontSize: 24,
            isBold: true,
            isItalic: true,
            alignment: .center,
            textColor: .blue,
            backgroundColor: .yellow,
            borderColor: .orange
        )
        let styledBox = updatedText.withTextBoxStyle(customStyle, now: t1)
        if case .textBox(let text, let style) = styledBox.kind {
            #expect(text == "Updated Body")
            #expect(style == customStyle)
        } else {
            Issue.record("Expected textBox kind")
        }

        let recoloredBox = styledBox.recolored(to: .purple, now: t1)
        if case .textBox(_, let style) = recoloredBox.kind {
            #expect(style.textColor == .purple)
            #expect(style.backgroundColor == .yellow)
            #expect(style.borderColor == .orange)
        }

        // Resilient Codable decoding from partial TextBoxStyle JSON
        let partialStyleJSON = Data("{}".utf8)
        let decodedDefaultStyle = try JSONDecoder().decode(TextBoxStyle.self, from: partialStyleJSON)
        #expect(decodedDefaultStyle == TextBoxStyle())
    }

    @Test("TextBox move, 4-corner resize, rotate, rotatedCorners/BoundingBox, and Page Codable round-trip")
    func textBoxGeometryAndCodableRoundTrip() throws {
        let style = TextBoxStyle(
            fontSize: 20,
            isBold: true,
            isItalic: false,
            alignment: .trailing,
            textColor: .red,
            backgroundColor: .white,
            borderColor: .black
        )
        let box = PageObject(
            frame: CGRect(x: 100, y: 120, width: 200, height: 100),
            rotation: 0,
            kind: .textBox(text: "Key Idea", style: style)
        )

        // Move
        let moved = box.moved(by: CGSize(width: 20, height: -10))
        #expect(moved.frame == CGRect(x: 120, y: 110, width: 200, height: 100))

        // Resize bottomRight keeps topLeft anchored
        let resized = box.resized(corner: .bottomRight, pageDelta: CGSize(width: 50, height: 40))
        #expect(abs(resized.frame.minX - 100) < 0.001)
        #expect(abs(resized.frame.minY - 120) < 0.001)
        #expect(abs(resized.width - 250) < 0.001)
        #expect(abs(resized.height - 140) < 0.001)

        // Rotate 90 degrees clockwise around center (200, 170)
        let rotated = box.rotated(toward: CGPoint(x: 300, y: 170))
        #expect(abs(rotated.rotation - (.pi * 0.5)) < 0.001)
        // Rotated hit-testing: point along rotated vertical span (200, 260) is inside 200-wide rotated box
        #expect(rotated.contains(pagePoint: CGPoint(x: 200, y: 260), tolerance: 0))
        #expect(!rotated.contains(pagePoint: CGPoint(x: 290, y: 170), tolerance: 0))

        let corners = rotated.rotatedCorners()
        #expect(corners.count == 4)
        let bbox = rotated.rotatedBoundingBox()
        #expect(abs(bbox.width - 100) < 0.01)
        #expect(abs(bbox.height - 200) < 0.01)

        // Codable round-trip inside a Page alongside other kinds
        let shape = PageObject.defaultBasicShape(.rectangle)
        let page = Page(title: "Mixed", objects: [shape, rotated])
        let encoded = try JSONEncoder().encode(page)
        let decoded = try JSONDecoder().decode(Page.self, from: encoded)
        #expect(decoded == page)
    }

    @Test("Codable resilience: unknown TextBoxAlignment falls back to .leading, NaN fontSize defaults to 16, and degenerate PageObject sizes clamp to minimumDimension")
    func codableResilienceAndDegenerateGuards() throws {
        // 1. Unknown TextBoxAlignment raw value falls back to .leading
        let unknownAlignmentJSON = Data(#"{"fontSize": 18, "alignment": "justified"}"#.utf8)
        let decodedStyle = try JSONDecoder().decode(TextBoxStyle.self, from: unknownAlignmentJSON)
        #expect(decodedStyle.alignment == .leading)
        #expect(decodedStyle.fontSize == 18)

        // 2. Non-finite fontSize (NaN / infinity) safely falls back to defaultFontSize
        let nanStyle = TextBoxStyle(fontSize: .nan)
        #expect(nanStyle.fontSize == TextBoxStyle.defaultFontSize)
        #expect(TextBoxStyle.clampedFontSize(.infinity) == TextBoxStyle.defaultFontSize)
        #expect(TextBoxStyle.clampedFontSize(-.infinity) == TextBoxStyle.defaultFontSize)

        // 3. Degenerate negative/zero PageObject dimensions in JSON clamp to >= minimumDimension
        let objectID = UUID()
        let degenerateJSON = """
        {
            "id": "\(objectID.uuidString)",
            "x": 40,
            "y": 50,
            "width": -20,
            "height": 0,
            "rotation": 0,
            "zIndex": 1,
            "kind": {
                "textBox": {
                    "text": "Clamped",
                    "style": {}
                }
            },
            "createdAt": 1000,
            "updatedAt": 1000
        }
        """.data(using: .utf8)!
        let decodedObj = try JSONDecoder().decode(PageObject.self, from: degenerateJSON)
        #expect(decodedObj.id == objectID)
        #expect(decodedObj.width >= PageObject.minimumDimension)
        #expect(decodedObj.height >= PageObject.minimumDimension)
    }

    @Test("Table text mode toggle, cell text storage, and striping toggle")
    func tableTextModeAndCellTexts() {
        var table = PageObject.defaultTable(rows: 3, columns: 3, color: .black, hasHeaderRow: true)
        guard var props = table.tableProperties else {
            Issue.record("Expected table properties")
            return
        }
        #expect(props.isTextMode == false) // Default auto-selected to Draw mode

        // Toggle to text mode
        let textModeTable = table.withToggledTableTextMode()
        #expect(textModeTable.tableProperties?.isTextMode == true)

        // Set cell text at (0, 0) and (1, 2)
        let withText = textModeTable
            .withTableCellText(row: 0, column: 0, text: "Header Cell")
            .withTableCellText(row: 1, column: 2, text: "Value 42")

        #expect(withText.tableProperties?.cellTexts["0,0"] == "Header Cell")
        #expect(withText.tableProperties?.cellTexts["1,2"] == "Value 42")

        // Striping toggle
        let striped = withText.withToggledTableStriping()
        #expect(striped.tableProperties?.isStriped == true)

        // Table text styling
        let styled = striped.withTableTextStyle(TextBoxStyle(fontSize: 18, fontDesign: .serif, isBold: true))
        #expect(styled.tableProperties?.textStyle.fontSize == 18)
        #expect(styled.tableProperties?.textStyle.fontDesign == .serif)
        #expect(styled.tableProperties?.textStyle.isBold == true)
    }

    @Test("TextBoxFontDesign and TextBoxBulletHelper functions")
    func textBoxFontDesignAndBulletHelpers() {
        #expect(TextBoxFontDesign.allCases.count == 4)
        #expect(TextBoxFontDesign.standard.displayName == "Default")
        #expect(TextBoxFontDesign.serif.displayName == "Serif")
        #expect(TextBoxFontDesign.monospaced.displayName == "Mono")
        #expect(TextBoxFontDesign.rounded.displayName == "Rounded")

        // Bullet list helper
        let plain = "First line\nSecond line"
        #expect(!TextBoxBulletHelper.isBulleted(plain))

        let bulleted = TextBoxBulletHelper.toggleBullets(in: plain)
        #expect(TextBoxBulletHelper.isBulleted(bulleted))
        #expect(bulleted.contains("• First line"))
        #expect(bulleted.contains("• Second line"))

        let toggledBack = TextBoxBulletHelper.toggleBullets(in: bulleted)
        #expect(!TextBoxBulletHelper.isBulleted(toggledBack))
        #expect(!toggledBack.contains("• "))
    }

    @Test("Backward-compatible decoding of legacy table JSON with _0..._5 positional keys")
    func legacyTableJsonDecodingBackwardCompatibility() throws {
        let objectID = UUID()
        let legacyTableJSON = """
        {
            "id": "\(objectID.uuidString)",
            "x": 67.5,
            "y": 200.0,
            "width": 460.0,
            "height": 180.0,
            "rotation": 0.0,
            "zIndex": 1,
            "kind": {
                "table": {
                    "_0": 4,
                    "_1": 3,
                    "_2": [0.333, 0.333, 0.334],
                    "_3": null,
                    "_4": "blue",
                    "_5": true
                }
            },
            "createdAt": 1000.0,
            "updatedAt": 1000.0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PageObject.self, from: legacyTableJSON)
        #expect(decoded.id == objectID)
        guard let table = decoded.tableProperties else {
            Issue.record("Expected tableProperties to decode from legacy JSON")
            return
        }
        #expect(table.rowCount == 4)
        #expect(table.columnCount == 3)
        #expect(table.strokeColor == .blue)
        #expect(table.hasHeaderRow == true)
        #expect(table.isTextMode == false) // Legacy tables default safely to draw mode
    }
}
