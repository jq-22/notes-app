//
//  PaperBackgroundView.swift
//  Notes
//
//  Responsibility: Renders the A4 background paper layer (lined, squared, or blank) behind the canvas.
//  Paper is a separate visual layer and is never baked into the ink drawing.
//  Dependencies: SwiftUI, Domain (PaperType, PageGeometry), DesignSystem (Theme).
//

import SwiftUI

public struct PaperBackgroundView: View {
    @Environment(\.displayScale) private var envDisplayScale: CGFloat

    public let paperType: PaperType
    public var lineSpacing: CGFloat
    public var showMarginLine: Bool
    public var displayScale: CGFloat?

    public init(
        paperType: PaperType,
        lineSpacing: CGFloat = PageGeometry.lineSpacing,
        showMarginLine: Bool = true,
        displayScale: CGFloat? = nil
    ) {
        self.paperType = paperType
        self.lineSpacing = lineSpacing
        self.showMarginLine = showMarginLine
        self.displayScale = displayScale
    }

    private var effectiveScale: CGFloat {
        let scale = displayScale ?? envDisplayScale
        return scale > 0 ? scale : 2.0
    }

    public var body: some View {
        Canvas { context, size in
            guard lineSpacing > 2 else { return }

            let hairline = 1.0 / effectiveScale
            let marginLineWidth = Swift.max(hairline * 1.5, 0.75)

            switch paperType {
            case .blank:
                break

            case .lined:
                var rulesPath = Path()
                let startY = showMarginLine ? PageGeometry.topMargin : lineSpacing
                var y = startY
                while y < size.height {
                    rulesPath.move(to: CGPoint(x: 0, y: y))
                    rulesPath.addLine(to: CGPoint(x: size.width, y: y))
                    y += lineSpacing
                }
                context.stroke(rulesPath, with: .color(Theme.Colors.paperRuleLine), lineWidth: hairline)

                if showMarginLine && size.width > PageGeometry.leftMarginOffset * 1.5 {
                    var marginPath = Path()
                    marginPath.move(to: CGPoint(x: PageGeometry.leftMarginOffset, y: 0))
                    marginPath.addLine(to: CGPoint(x: PageGeometry.leftMarginOffset, y: size.height))
                    context.stroke(marginPath, with: .color(Theme.Colors.paperMarginLine), lineWidth: marginLineWidth)
                }

            case .squared:
                var gridPath = Path()
                var x = lineSpacing
                while x < size.width {
                    gridPath.move(to: CGPoint(x: x, y: 0))
                    gridPath.addLine(to: CGPoint(x: x, y: size.height))
                    x += lineSpacing
                }
                var y = lineSpacing
                while y < size.height {
                    gridPath.move(to: CGPoint(x: 0, y: y))
                    gridPath.addLine(to: CGPoint(x: size.width, y: y))
                    y += lineSpacing
                }
                context.stroke(gridPath, with: .color(Theme.Colors.paperRuleLine), lineWidth: hairline)
            }
        }
        .background(Theme.Colors.pageBackground)
    }
}
