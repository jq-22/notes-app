//
//  ShapeLibraryPopoverView.swift
//  Notes
//
//  Responsibility: Popover view displaying reusable diagram shapes saved in notebooks.
//  Shows items saved in the current notebook by default.
//  Tapping the notebook title at the top opens a scrollable list of notebooks to browse and pull items from.
//  Tapping any item places it onto the page as an interactive, resizable, rotatable PageObject.
//  Dependencies: SwiftUI, Domain (ShapeLibraryItem, Notebook), LibraryViewModel.
//

import SwiftUI
import UIKit

public struct ShapeLibraryPopoverView: View {
    @Bindable var viewModel: LibraryViewModel
    let currentNotebook: Notebook
    let onPlaceShape: (ShapeLibraryItem) -> Void
    let onDismiss: () -> Void

    @State private var browsingNotebookID: UUID
    @State private var isNotebookPickerPresented: Bool = false

    public init(
        viewModel: LibraryViewModel,
        currentNotebook: Notebook,
        onPlaceShape: @escaping (ShapeLibraryItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.currentNotebook = currentNotebook
        self.onPlaceShape = onPlaceShape
        self.onDismiss = onDismiss
        self._browsingNotebookID = State(initialValue: currentNotebook.id)
    }

    private var browsingNotebook: Notebook? {
        viewModel.notebooks.first(where: { $0.id == browsingNotebookID }) ?? currentNotebook
    }

    private var items: [ShapeLibraryItem] {
        viewModel.loadShapeLibraryItems(for: browsingNotebookID)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Notebook Switcher Bar
                HStack {
                    Menu {
                        ForEach(viewModel.notebooks) { nb in
                            Button {
                                browsingNotebookID = nb.id
                            } label: {
                                HStack {
                                    Text(nb.title)
                                    if nb.id == browsingNotebookID {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "book.closed")
                                .font(.subheadline)
                            Text(browsingNotebook?.title ?? "Notebook")
                                .font(.headline)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider()

                // Content: Grid of saved shapes
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Saved Shapes",
                        systemImage: "square.dashed",
                        description: Text("Lasso any drawing with the Lasso tool and tap the Save button to reuse it here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 14)], spacing: 14) {
                            ForEach(items) { item in
                                shapeCard(for: item)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 420, minHeight: 380, idealHeight: 460)
            .navigationBarHidden(true)
        }
    }

    @ViewBuilder
    private func shapeCard(for item: ShapeLibraryItem) -> some View {
        Button {
            onPlaceShape(item)
            onDismiss()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )

                    if let previewData = viewModel.loadShapeLibraryPreview(for: item.id),
                       let uiImage = UIImage(data: previewData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                    } else {
                        Image(systemName: "scribble.variable")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 100)

                Text(item.label)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(6)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteShapeLibraryItem(id: item.id, notebookID: item.notebookID)
            } label: {
                Label("Delete Shape", systemImage: "trash")
            }
        }
    }
}
