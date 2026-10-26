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
    @State private var isShapeLibraryPresented: Bool = false
    @State private var isSaveShapePromptPresented: Bool = false
    @State private var shapeLabelDraft: String = "Shape"
    @State private var pendingSaveStrokes: (data: Data, bounds: CGRect, png: Data)?

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

    private var lassoModeBinding: Binding<Bool> {
        Binding<Bool>(
            get: { viewModel.isLassoModeActive },
            set: { newValue in
                viewModel.isLassoModeActive = newValue
                if newValue {
                    viewModel.selectedObjectID = nil
                }
            }
        )
    }

    public var body: some View {
        PencilCanvasScrollView(
            pageID: page.id,
            paperType: effectivePaper,
            initialDrawingData: viewModel.loadDrawingData(for: page.id),
            pageObjects: page.objects,
            selectedObjectID: viewModel.selectedObjectID,
            isLassoModeActive: viewModel.isLassoModeActive,
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
                if objectID != nil {
                    viewModel.isLassoModeActive = false
                }
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
            onCopyObject: { objectID in
                viewModel.copySingleObjectToClipboard(
                    id: objectID,
                    on: page.id,
                    in: section.id,
                    notebookID: notebook.id
                )
            },
            onCopyLassoPayload: { strokeData, strokeBounds, objectIDs in
                viewModel.copyObjectsAndStrokesToClipboard(
                    strokeDrawingData: strokeData,
                    strokeBounds: strokeBounds,
                    objectIDs: objectIDs,
                    on: page.id,
                    in: section.id,
                    notebookID: notebook.id
                )
            },
            onConvertLassoStrokesToObject: { strokeData, strokeBounds in
                viewModel.isLassoModeActive = false
                let safeW = Swift.max(PageObject.minimumDimension, strokeBounds.width)
                let safeH = Swift.max(PageObject.minimumDimension, strokeBounds.height)
                let newObj = PageObject(
                    frame: CGRect(x: strokeBounds.minX, y: strokeBounds.minY, width: safeW, height: safeH),
                    rotation: 0,
                    kind: .strokeGroup(
                        drawingData: strokeData,
                        sourceBoundsWidth: safeW,
                        sourceBoundsHeight: safeH,
                        tintColorOverride: nil
                    )
                )
                viewModel.addPageObject(
                    newObj,
                    on: page.id,
                    in: section.id,
                    notebookID: notebook.id
                )
            },
            onSaveLassoStrokesToLibrary: { strokeData, strokeBounds, previewPNG in
                pendingSaveStrokes = (strokeData, strokeBounds, previewPNG)
                shapeLabelDraft = "Shape"
                isSaveShapePromptPresented = true
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
                viewModel.isLassoModeActive = false
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
        .alert("Save to Shape Library", isPresented: $isSaveShapePromptPresented) {
            TextField("Shape Name", text: $shapeLabelDraft)
            Button("Cancel", role: .cancel) {
                pendingSaveStrokes = nil
            }
            Button("Save") {
                if let payload = pendingSaveStrokes {
                    let trimmed = shapeLabelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalLabel = trimmed.isEmpty ? "Shape" : trimmed
                    viewModel.saveToShapeLibrary(
                        label: finalLabel,
                        strokeDrawingData: payload.data,
                        sourceBounds: payload.bounds,
                        previewPNGData: payload.png,
                        notebookID: notebook.id
                    )
                }
                pendingSaveStrokes = nil
            }
        } message: {
            Text("Enter a name for this shape to reuse it across your notes.")
        }
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
            viewModel.isLassoModeActive = false
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

                // Freehand Lasso Selection Tool
                Toggle(isOn: lassoModeBinding) {
                    Label("Lasso", systemImage: "lasso")
                }
                .toggleStyle(.button)
                .help("Lasso ink strokes and objects to move, recolour, copy, or cut")

                // Paste Button (enabled whenever strokes or objects are on the clipboard)
                if viewModel.canPasteFromClipboard {
                    Button {
                        viewModel.pasteFromClipboard(
                            on: page.id,
                            in: section.id,
                            notebookID: notebook.id
                        )
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .help("Paste copied strokes or objects onto this page")
                }

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

                // Notebook Shape Library Popover Button
                Button {
                    isShapeLibraryPresented = true
                } label: {
                    Label("Shape Library", systemImage: "square.stack.3d.up")
                }
                .help("Browse and insert saved diagram shapes from your notebook library")
                .popover(isPresented: $isShapeLibraryPresented) {
                    ShapeLibraryPopoverView(
                        viewModel: viewModel,
                        currentNotebook: notebook,
                        onPlaceShape: { item in
                            viewModel.isLassoModeActive = false
                            viewModel.placeShapeLibraryItem(
                                item,
                                on: page.id,
                                in: section.id,
                                notebookID: notebook.id
                            )
                        },
                        onDismiss: {
                            isShapeLibraryPresented = false
                        }
                    )
                }

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
