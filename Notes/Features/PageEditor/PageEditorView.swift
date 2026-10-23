//
//  PageEditorView.swift
//  Notes
//
//  Responsibility: Hosts `PencilCanvasScrollView` for the selected A4 portrait page and provides toolbar controls for:
//    - Overriding the page's paper type (lined / squared / blank, or inheriting notebook default)
//    - Toggling Scribble-to-Erase on or off
//    - Adding a new page immediately below the current page
//  Dependencies: SwiftUI, Domain, DesignSystem, LibraryViewModel, PencilCanvasScrollView.
//

import SwiftUI

public struct PageEditorView: View {
    @Bindable var viewModel: LibraryViewModel
    let notebook: Notebook
    let section: NoteSection
    let page: Page
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void

    public init(
        viewModel: LibraryViewModel,
        notebook: Notebook,
        section: NoteSection,
        page: Page,
        isFullScreen: Bool = false,
        onToggleFullScreen: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.notebook = notebook
        self.section = section
        self.page = page
        self.isFullScreen = isFullScreen
        self.onToggleFullScreen = onToggleFullScreen
    }

    private var effectivePaper: PaperType {
        page.effectivePaperType(notebookDefault: notebook.defaultPaperType)
    }

    private var pagePositionLabel: String {
        if let idx = section.pages.firstIndex(where: { $0.id == page.id }) {
            return "\(page.title) (\(idx + 1)/\(section.pages.count))"
        }
        return page.title
    }

    public var body: some View {
        PencilCanvasScrollView(
            pageID: page.id,
            paperType: effectivePaper,
            initialDrawingData: viewModel.loadDrawingData(for: page.id),
            isScribbleToEraseEnabled: viewModel.isScribbleToEraseEnabled,
            onDrawingChanged: { updatedData in
                viewModel.scheduleDrawingAutosave(updatedData, for: page.id)
            },
            onSwipeToNextPage: {
                viewModel.goToNextOrCreatePage()
            },
            onSwipeToPreviousPage: {
                viewModel.goToPreviousPage()
            }
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(pagePositionLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button(action: onToggleFullScreen) {
                    Label(
                        isFullScreen ? "Show Sidebar" : "Full Screen",
                        systemImage: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                    )
                }
                .help(isFullScreen ? "Show sidebar menus" : "Hide sidebars for full-screen writing")

                Button {
                    viewModel.goToPreviousPage()
                } label: {
                    Label("Previous Page", systemImage: "chevron.left")
                }
                .disabled(!viewModel.canGoToPreviousPage)
                .help("Go to previous page (or swipe right)")

                Button {
                    viewModel.goToNextOrCreatePage()
                } label: {
                    Label("Next / New Page", systemImage: "chevron.right")
                }
                .help("Go to next page or create a new page (or swipe left)")
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Toggle(isOn: $viewModel.isScribbleToEraseEnabled) {
                    Label(
                        "Scribble to Erase",
                        systemImage: viewModel.isScribbleToEraseEnabled ? "scribble.variable" : "scribble"
                    )
                }
                .toggleStyle(.button)
                .help("Toggle Scribble-to-Erase gesture")

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
