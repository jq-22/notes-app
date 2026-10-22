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
        PencilCanvasScrollView(
            pageID: page.id,
            paperType: effectivePaper,
            initialDrawingData: viewModel.loadDrawingData(for: page.id),
            isScribbleToEraseEnabled: viewModel.isScribbleToEraseEnabled,
            onDrawingChanged: { updatedData in
                viewModel.scheduleDrawingAutosave(updatedData, for: page.id)
            }
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
