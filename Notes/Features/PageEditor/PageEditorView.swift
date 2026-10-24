//
//  PageEditorView.swift
//  Notes
//
//  Responsibility: Hosts `PencilCanvasScrollView` for the selected A4 portrait page and provides toolbar controls for:
//    - Top-left: Full-Screen sidebar toggle + Undo and Redo buttons
//    - Top-right: Compact 4-Tool Menu Button (Pen, Highlighter, Rubber, Ruler), Object Select toggle, Insert Menu (Photo & Basic Shapes: Rectangle, Circle, Arrow, Line), Scribble-to-Erase toggle, Page Paper style picker, and Add Page Below.
//  Dependencies: SwiftUI, PhotosUI, UIKit, Domain, DesignSystem, LibraryViewModel, PencilCanvasScrollView, DrawingToolMenuButton.
//

import PhotosUI
import SwiftUI
import UIKit

public struct PageEditorView: View {
    @Bindable var viewModel: LibraryViewModel
    let notebook: Notebook
    let section: NoteSection
    let page: Page
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void

    @State private var canUndo: Bool = false
    @State private var canRedo: Bool = false
    @State private var undoTriggerCount: Int = 0
    @State private var redoTriggerCount: Int = 0
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented: Bool = false

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
            pageObjects: page.objects,
            selectedObjectID: viewModel.selectedObjectID,
            toolState: viewModel.toolState,
            isScribbleToEraseEnabled: viewModel.isScribbleToEraseEnabled,
            undoTriggerCount: undoTriggerCount,
            redoTriggerCount: redoTriggerCount,
            canGoToPreviousPage: viewModel.canGoToPreviousPage,
            assetDataProvider: { assetID in
                viewModel.loadAssetData(for: assetID)
            },
            onDrawingChanged: { updatedData in
                viewModel.scheduleDrawingAutosave(updatedData, for: page.id)
            },
            onSelectObject: { objectID in
                viewModel.selectedObjectID = objectID
            },
            onUpdateObjectLive: { updatedObject in
                viewModel.updatePageObject(
                    updatedObject,
                    on: page.id,
                    in: section.id,
                    notebookID: notebook.id
                )
            },
            onReplaceAllObjects: { replacedObjects in
                viewModel.setPageObjects(
                    replacedObjects,
                    on: page.id,
                    in: section.id,
                    notebookID: notebook.id
                )
            },
            onDuplicateObject: { objectID in
                viewModel.duplicatePageObject(
                    id: objectID,
                    on: page.id,
                    in: section.id,
                    notebookID: notebook.id
                )
            },
            onDeleteObject: { objectID in
                viewModel.deletePageObject(
                    id: objectID,
                    on: page.id,
                    in: section.id,
                    notebookID: notebook.id
                )
            },
            onUndoStateChanged: { updatedCanUndo, updatedCanRedo in
                canUndo = updatedCanUndo
                canRedo = updatedCanRedo
            },
            onPencilDoubleTap: {
                viewModel.selectedObjectID = nil
                viewModel.toolState.handlePencilDoubleTapToggleEraser()
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
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { @MainActor in
                defer { selectedPhotoItem = nil }
                if let rawData = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: rawData) {
                    let normalizedData = uiImage.pngData() ?? rawData
                    viewModel.insertImageObject(
                        imageData: normalizedData,
                        intrinsicSize: uiImage.size,
                        on: page.id,
                        in: section.id,
                        notebookID: notebook.id
                    )
                }
            }
        }
        .onChange(of: viewModel.toolState) { _, _ in
            // Picking or adjusting an ink tool returns focus to drawing
            viewModel.selectedObjectID = nil
        }
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
                    undoTriggerCount += 1
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!canUndo)
                .help("Undo last stroke or object change")

                Button {
                    redoTriggerCount += 1
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!canRedo)
                .help("Redo stroke or object change")
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                // Compact 4-Tool Popover Button (Pen >, Highlighter >, Rubber >, Ruler)
                DrawingToolMenuButton(toolState: $viewModel.toolState)

                // Insert Menu (Photos & Basic Shapes: Rectangle, Circle, Arrow, Line)
                Menu {
                    Button {
                        isPhotoPickerPresented = true
                    } label: {
                        Label("Insert Photo…", systemImage: "photo.on.rectangle.angled")
                    }

                    Divider()

                    Section("Basic Shapes") {
                        ForEach(BasicShapeKind.allCases) { shapeKind in
                            Button {
                                viewModel.insertBasicShape(
                                    shapeKind,
                                    on: page.id,
                                    in: section.id,
                                    notebookID: notebook.id
                                )
                            } label: {
                                Label(shapeKind.displayName, systemImage: shapeKind.systemImageName)
                            }
                        }
                    }
                } label: {
                    Label("Insert", systemImage: "plus.square.on.square")
                }
                .help("Insert an image or basic shape (Rectangle, Circle, Arrow, Line)")

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
