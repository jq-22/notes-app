//
//  PagePDFExporterTests.swift
//  NotesTests
//
//  Responsibility: Unit tests for `PagePDFExporter` vector PDF output using `PDFKit`, verifying A4 media bounds,
//  `.textBox` text extraction, rotated/styled fill/border pixel rendering, and mixed ink + objects export.
//

import Foundation
import PDFKit
import PencilKit
import Testing
import UIKit
@testable import Notes

@Suite("Features — PagePDFExporter")
@MainActor
struct PagePDFExporterTests {

    @Test("Exported PDF contains selectable TextBox text on an A4 page")
    func exportsTextBoxTextIntoPDF() throws {
        let style = TextBoxStyle(
            fontSize: 18,
            isBold: true,
            isItalic: false,
            alignment: .leading,
            textColor: .black,
            backgroundColor: nil,
            borderColor: nil
        )
        let textBox = PageObject(
            frame: CGRect(x: 100, y: 140, width: 280, height: 110),
            rotation: 0,
            kind: .textBox(text: "Architecture Notes", style: style)
        )
        let page = Page(title: "Design", objects: [textBox])

        let pdfURL = try PagePDFExporter.exportPDF(
            pages: [ExportablePageInput(page: page, effectivePaperType: .blank, drawingData: nil)],
            fileNameTitle: "TextBox-PDF-Test-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let document = try #require(PDFDocument(url: pdfURL))
        #expect(document.pageCount == 1)

        let pdfPage = try #require(document.page(at: 0))
        let mediaBox = pdfPage.bounds(for: .mediaBox)
        #expect(mediaBox.size == PageGeometry.a4Size)
        #expect(pdfPage.string?.contains("Architecture Notes") == true)
    }

    @Test("Rotated and styled TextBox renders non-white fill/border/text pixels in PDF")
    func rotatedAndStyledTextBoxRendersPixels() throws {
        let style = TextBoxStyle(
            fontSize: 20,
            isBold: true,
            isItalic: true,
            alignment: .center,
            textColor: .blue,
            backgroundColor: .yellow,
            borderColor: .red
        )
        // Verify bold + italic font descriptor traits
        let resolvedFont = style.resolvedUIFont()
        #expect(resolvedFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(resolvedFont.fontDescriptor.symbolicTraits.contains(.traitItalic))

        let rotatedBox = PageObject(
            frame: CGRect(x: 160, y: 260, width: 260, height: 120),
            rotation: .pi / 6.0,
            kind: .textBox(text: "Rotated Card", style: style)
        )
        let page = Page(title: "Styled", objects: [rotatedBox])

        let pdfURL = try PagePDFExporter.exportPDF(
            pages: [ExportablePageInput(page: page, effectivePaperType: .blank, drawingData: nil)],
            fileNameTitle: "Styled-TextBox-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let document = try #require(PDFDocument(url: pdfURL))
        let pdfPage = try #require(document.page(at: 0))
        #expect(pdfPage.string?.contains("Rotated Card") == true)

        // Rasterize the PDF page and verify the card center region is non-white
        let renderer = UIGraphicsImageRenderer(size: PageGeometry.a4Size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: PageGeometry.a4Size))
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 0, y: PageGeometry.a4Height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            pdfPage.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }

        #expect(hasNonWhitePixel(in: image, around: rotatedBox.center, radius: 30))
    }

    @Test("Empty TextBox with fill/border and mixed ink + shapes export cleanly")
    func emptyTextBoxAndMixedPageExport() throws {
        let emptyStyledBox = PageObject(
            frame: CGRect(x: 120, y: 160, width: 220, height: 90),
            kind: .textBox(
                text: "",
                style: TextBoxStyle(backgroundColor: .yellow, borderColor: .black)
            )
        )
        let shape = PageObject.defaultBasicShape(.rectangle, color: .blue, strokeWidth: 3.0)

        let strokePoints = [
            PKStrokePoint(location: CGPoint(x: 80, y: 400), timeOffset: 0, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: 240, y: 460), timeOffset: 0.1, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        ]
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: strokePoints, creationDate: Date())
        )
        let drawingData = PKDrawing(strokes: [stroke]).dataRepresentation()

        let page = Page(title: "Mixed", objects: [emptyStyledBox, shape])
        let pdfURL = try PagePDFExporter.exportPDF(
            pages: [ExportablePageInput(page: page, effectivePaperType: .lined, drawingData: drawingData)],
            fileNameTitle: "Mixed-TextBox-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let document = try #require(PDFDocument(url: pdfURL))
        #expect(document.pageCount == 1)
    }

    private func hasNonWhitePixel(in image: UIImage, around center: CGPoint, radius: Int) -> Bool {
        guard let cgImage = image.cgImage,
              let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data,
              let bytes = CFDataGetBytePtr(pixelData) else {
            return false
        }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        let scaleX = CGFloat(width) / PageGeometry.a4Width
        let scaleY = CGFloat(height) / PageGeometry.a4Height

        let cx = Int(center.x * scaleX)
        let cy = Int(center.y * scaleY)

        for dy in stride(from: -radius, through: radius, by: 4) {
            for dx in stride(from: -radius, through: radius, by: 4) {
                let x = cx + dx
                let y = cy + dy
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                let offset = y * bytesPerRow + x * bytesPerPixel
                if offset + 2 < CFDataGetLength(pixelData) {
                    let c0 = bytes[offset]
                    let c1 = bytes[offset + 1]
                    let c2 = bytes[offset + 2]
                    if c0 < 245 || c1 < 245 || c2 < 245 {
                        return true
                    }
                }
            }
        }
        return false
    }
}
