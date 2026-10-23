//
//  PagePDFExporter.swift
//  Notes
//
//  Responsibility: Renders one or more `Page`s (including their A4 paper pattern — lined, squared, or blank — and `PKDrawing` ink strokes) into a multi-page vector PDF file for sharing via `UIActivityViewController` / `ShareLink`.
//  Dependencies: Foundation, UIKit, PencilKit, Domain.
//  Errors: Throws standard `Error` if the temporary PDF file cannot be written.
//

import CoreGraphics
import Foundation
import PencilKit
import UIKit

public struct ExportablePageInput: Sendable {
    public let page: Page
    public let effectivePaperType: PaperType
    public let drawingData: Data?

    public init(page: Page, effectivePaperType: PaperType, drawingData: Data?) {
        self.page = page
        self.effectivePaperType = effectivePaperType
        self.drawingData = drawingData
    }
}

public enum PagePDFExporter {

    /// Generates a PDF file in the temporary directory containing each page in `inputs` at A4 portrait size (595 x 842 pt).
    @MainActor
    public static func exportPDF(
        pages inputs: [ExportablePageInput],
        fileNameTitle: String
    ) throws -> URL {
        let pageBounds = CGRect(origin: .zero, size: PageGeometry.a4Size)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        let pdfData = renderer.pdfData { context in
            let lightTraits = UITraitCollection(userInterfaceStyle: .light)
            for input in inputs {
                context.beginPage()
                let cgContext = context.cgContext

                // 1. White A4 background
                cgContext.setFillColor(UIColor.white.cgColor)
                cgContext.fill(pageBounds)

                // 2. Paper lines/grid
                drawPaperPattern(input.effectivePaperType, in: pageBounds, cgContext: cgContext)

                // 3. Ink strokes from PKDrawing
                if let data = input.drawingData,
                   !data.isEmpty,
                   let drawing = try? PKDrawing(data: data),
                   !drawing.strokes.isEmpty {
                    var inkImage: UIImage?
                    lightTraits.performAsCurrent {
                        inkImage = drawing.image(from: pageBounds, scale: 2.0)
                    }
                    inkImage?.draw(in: pageBounds)
                }
            }
        }

        let safeName = sanitizedFileName(from: fileNameTitle)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).pdf", isDirectory: false)
        try pdfData.write(to: outputURL, options: [.atomic])
        return outputURL
    }

    private static func drawPaperPattern(_ paperType: PaperType, in rect: CGRect, cgContext: CGContext) {
        let spacing = PageGeometry.lineSpacing
        guard spacing > 2 else { return }

        let ruleColor = UIColor.black.withAlphaComponent(0.14).cgColor
        let marginColor = UIColor.systemRed.withAlphaComponent(0.28).cgColor

        cgContext.saveGState()
        defer { cgContext.restoreGState() }

        switch paperType {
        case .blank:
            break

        case .lined:
            cgContext.setStrokeColor(ruleColor)
            cgContext.setLineWidth(0.75)
            var y = PageGeometry.topMargin
            while y < rect.height {
                cgContext.move(to: CGPoint(x: 0, y: y))
                cgContext.addLine(to: CGPoint(x: rect.width, y: y))
                y += spacing
            }
            cgContext.strokePath()

            cgContext.setStrokeColor(marginColor)
            cgContext.setLineWidth(1.0)
            cgContext.move(to: CGPoint(x: PageGeometry.leftMarginOffset, y: 0))
            cgContext.addLine(to: CGPoint(x: PageGeometry.leftMarginOffset, y: rect.height))
            cgContext.strokePath()

        case .squared:
            cgContext.setStrokeColor(ruleColor)
            cgContext.setLineWidth(0.65)
            var x = spacing
            while x < rect.width {
                cgContext.move(to: CGPoint(x: x, y: 0))
                cgContext.addLine(to: CGPoint(x: x, y: rect.height))
                x += spacing
            }
            var y = spacing
            while y < rect.height {
                cgContext.move(to: CGPoint(x: 0, y: y))
                cgContext.addLine(to: CGPoint(x: rect.width, y: y))
                y += spacing
            }
            cgContext.strokePath()
        }
    }

    private static func sanitizedFileName(from raw: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = raw
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Notes-Export" : cleaned
    }
}
