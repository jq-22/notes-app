//
//  PageCanvasPlaceholderView.swift
//  Notes
//
//  Responsibility: Displays the selected A4 portrait page (595 x 842 pt aspect ratio), its paper background layer, and toolbar controls to override the page's paper type or add a page below.
//  Note: PencilKit ink canvas integration is the next step in Milestone v1a.
//  Dependencies: SwiftUI, Domain, DesignSystem, LibraryViewModel, PaperBackgroundView.
//

import SwiftUI

public struct PageCanvasPlaceholderView: View {
    @Bindable var viewModel: LibraryViewModel
    let notebook: Notebook
    let section: NoteSection
    let page: Page

    public init(
        viewModel: LibraryViewModel,
        notebook: Notebook,
        section: NoteSection,
        page: Page
    ) {
        self.viewModel = viewModel
        self.notebook = notebook
        self.section = section
        self.page = page
    }

    private var effectivePaper: PaperType {
        page.effectivePaperType(notebookDefault: notebook.defaultPaperType)
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView([.vertical, .horizontal]) {
                VStack(spacing: Theme.Spacing.medium) {
                    PaperBackgroundView(paperType: effectivePaper)
                        .frame(
                            width: PageGeometry.a4Width,
                            height: PageGeometry.a4Height
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.page))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.page)
                                .stroke(Theme.Colors.pageBorder, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                        .padding(Theme.Spacing.xLarge)
                }
                .frame(
                    minWidth: geometry.size.width,
                    minHeight: geometry.size.height
                )
            }
            .background(Theme.Colors.canvasWorkspaceBackground)
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker(
                        "Page Paper",
                        selection: Binding<PaperType?>(
                            get: { page.paperTypeOverride },
                            set: { newOverride in
                                viewModel.setPagePaperTypeOverride(
                                    id: page.id,
                                    in: section.id,
                                    notebookID: notebook.id,
                                    to: newOverride
                                )
                            }
                        )
                    ) {
                        Text("Notebook Default (\(notebook.defaultPaperType.displayName))")
                            .tag(PaperType?.none)
                        Divider()
                        ForEach(PaperType.allCases) { paper in
                            Label(paper.displayName, systemImage: paper.systemImageName)
                                .tag(PaperType?.some(paper))
                        }
                    }
                } label: {
                    Label(effectivePaper.displayName, systemImage: effectivePaper.systemImageName)
                }
                .help("Change paper style for this page")

                Button {
                    viewModel.createPage(
                        in: section.id,
                        notebookID: notebook.id,
                        afterPageID: page.id
                    )
                } label: {
                    Label("Add Page Below", systemImage: "doc.badge.plus")
                }
                .help("Add a new page below the current page")
            }
        }
    }
}
