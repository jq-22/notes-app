//
//  PageThumbnailView.swift
//  Notes
//
//  Responsibility: Compact A4 portrait thumbnail previewing a page's effective paper style and page number in the sidebar list.
//  Dependencies: SwiftUI, Domain (PaperType), DesignSystem (Theme), PaperBackgroundView.
//

import SwiftUI

public struct PageThumbnailView: View {
    public let paperType: PaperType
    public let pageNumber: Int
    public let isSelected: Bool

    public init(paperType: PaperType, pageNumber: Int, isSelected: Bool) {
        self.paperType = paperType
        self.pageNumber = pageNumber
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PaperBackgroundView(
                paperType: paperType,
                lineSpacing: Theme.Thumbnail.lineSpacing,
                showMarginLine: false
            )

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
