//
//  PageThumbnailView.swift
//  Notes
//
//  Responsibility: Compact A4 portrait thumbnail previewing a page's effective paper style, live ink strokes (`PKDrawing`), and page number in the sidebar list.
//  Dependencies: SwiftUI, PencilKit, Domain (PaperType, PageGeometry), DesignSystem (Theme), PaperBackgroundView.
//

import PencilKit
import SwiftUI

public struct PageThumbnailView: View {
    public let paperType: PaperType
    public let drawingData: Data?
    public let pageNumber: Int
    public let isSelected: Bool

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    public init(
        paperType: PaperType,
        drawingData: Data? = nil,
        pageNumber: Int,
        isSelected: Bool
    ) {
        self.paperType = paperType
        self.drawingData = drawingData
        self.pageNumber = pageNumber
        self.isSelected = isSelected
    }

    private var renderedInkImage: UIImage? {
        guard let drawingData,
              !drawingData.isEmpty,
              let drawing = try? PKDrawing(data: drawingData),
              !drawing.strokes.isEmpty else {
            return nil
        }
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        var image: UIImage?
        traits.performAsCurrent {
            image = drawing.image(
                from: CGRect(origin: .zero, size: PageGeometry.a4Size),
                scale: max(displayScale, 1.0) * (Theme.Thumbnail.width / PageGeometry.a4Width)
            )
        }
        return image
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PaperBackgroundView(
                paperType: paperType,
                lineSpacing: Theme.Thumbnail.lineSpacing,
                showMarginLine: false
            )

            if let inkImage = renderedInkImage {
                Image(uiImage: inkImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }

            Text("\(pageNumber)")
                .font(Theme.Fonts.badge)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 3))
                .padding(3)
        }
        .frame(width: Theme.Thumbnail.width, height: Theme.Thumbnail.height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.page))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.page)
                .stroke(
                    isSelected ? Theme.Colors.selectedThumbnailBorder : Theme.Colors.pageBorder,
                    lineWidth: isSelected ? 2.0 : 1.0
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
    }
}
