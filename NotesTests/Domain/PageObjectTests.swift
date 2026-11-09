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
        if case .table(let rows, let cols, _, _, let color, let header) = table.kind {
            #expect(rows == 4)
            #expect(cols == 3)
            #expect(color == .black)
            #expect(header == true)
        } else {
            Issue.record("Expected table kind")
        }

        // Add row
        let withRow = table.withAddedTableRow()
        if case .table(let rows, _, _, _, _, _) = withRow.kind {
            #expect(rows == 5)
            #expect(withRow.height > table.height)
        }

        // Remove row
        let withoutRow = withRow.withRemovedTableRow()
        if case .table(let rows, _, _, _, _, _) = withoutRow.kind {
            #expect(rows == 4)
        }

        // Add column
        let withCol = table.withAddedTableColumn()
        if case .table(_, let cols, _, _, _, _) = withCol.kind {
            #expect(cols == 4)
            #expect(withCol.width > table.width)
        }

        // Remove column
        let withoutCol = withCol.withRemovedTableColumn()
        if case .table(_, let cols, _, _, _, _) = withoutCol.kind {
            #expect(cols == 3)
        }

        // Toggle header
        let toggledHeader = table.withToggledTableHeader()
        if case .table(_, _, _, _, _, let header) = toggledHeader.kind {
            #expect(header == false)
        }

        // Recolour
        let blueTable = table.recolored(to: .blue)
        if case .table(_, _, _, _, let color, _) = blueTable.kind {
            #expect(color == .blue)
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
}
