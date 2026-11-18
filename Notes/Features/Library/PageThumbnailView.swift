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
    public let pageObjects: [PageObject]
    public let assetDataProvider: (UUID) -> Data?
    public let pageNumber: Int
    public let isBookmarked: Bool
    public let isSelected: Bool

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    public init(
        paperType: PaperType,
        drawingData: Data? = nil,
        pageObjects: [PageObject] = [],
        assetDataProvider: @escaping (UUID) -> Data? = { _ in nil },
        pageNumber: Int,
        isBookmarked: Bool = false,
        isSelected: Bool
    ) {
        self.paperType = paperType
        self.drawingData = drawingData
        self.pageObjects = pageObjects
        self.assetDataProvider = assetDataProvider
        self.pageNumber = pageNumber
        self.isBookmarked = isBookmarked
        self.isSelected = isSelected
    }

    private var renderedInkImage: UIImage? {
        guard let drawingData,
              !drawingData.isEmpty,
              let drawing = try? PKDrawing(data: drawingData),
              !drawing.strokes.isEmpty else {
            return nil
        }
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        var image: UIImage?
        lightTraits.performAsCurrent {
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

            if !pageObjects.isEmpty {
                PageObjectsOverlayView(
                    objects: pageObjects,
                    selectedObjectID: nil,
                    isInteractive: false,
                    assetDataProvider: assetDataProvider
                )
                .scaleEffect(
                    x: Theme.Thumbnail.width / PageGeometry.a4Width,
                    y: Theme.Thumbnail.height / PageGeometry.a4Height,
                    anchor: .topLeading
                )
                .frame(width: Theme.Thumbnail.width, height: Theme.Thumbnail.height, alignment: .topLeading)
                .allowsHitTesting(false)
            }

            if let inkImage = renderedInkImage {
                Image(uiImage: inkImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }

            if isBookmarked {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(2.5)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(3)
                    }
                    Spacer()
                }
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
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.pageThumbnail))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.pageThumbnail)
                .stroke(
                    isSelected ? Theme.Colors.selectedThumbnailBorder : Theme.Colors.pageBorder,
                    lineWidth: isSelected ? 2.0 : 1.0
                )
        )
        .themeShadow(Theme.Shadows.subtleCard)
    }
}
