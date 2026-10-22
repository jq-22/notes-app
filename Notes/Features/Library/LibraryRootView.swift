//
//  LibraryRootView.swift
//  Notes
//
//  Responsibility: Three-column NavigationSplitView for iPad:
//    1. Sidebar: Notebooks (create, rename, change default paper type, reorder, delete with confirmation)
//    2. Content: Sections & Pages inside the selected notebook (create, rename, reorder, delete with confirmation, page thumbnails)
//    3. Detail: Selected A4 page view with paper background & page controls.
//  Also observes scenePhase to flush any pending state when the app backgrounds, and presents save/load errors via alert.
//  Dependencies: SwiftUI, Domain, DesignSystem, LibraryViewModel, PageThumbnailView, PageCanvasPlaceholderView.
//

import SwiftUI

public struct LibraryRootView: View {
    @Bindable var viewModel: LibraryViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // Rename dialog state
    @State private var renameTarget: RenameTarget?
    @State private var renameDraftTitle: String = ""

    // Delete confirmation state
    @State private var deleteTarget: DeleteTarget?

    public init(viewModel: LibraryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            notebookSidebar
        } content: {
            sectionAndPageColumn
        } detail: {
            detailColumn
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                viewModel.saveNow()
            }
        }
        .alert(
            "Rename \(renameTarget?.kindLabel ?? "Item")",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            ),
            presenting: renameTarget
        ) { target in
            TextField("Title", text: $renameDraftTitle)
            Button("Save") {
                commitRename(target: target, newTitle: renameDraftTitle)
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) {
                renameTarget = nil
            }
        }
        .confirmationDialog(
            deleteTarget?.confirmationTitle ?? "Delete?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { target in
            Button("Delete \"\(target.title)\"", role: .destructive) {
                commitDelete(target: target)
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: { target in
            Text(target.confirmationMessage)
        }
        .alert(
            "Storage Error",
            isPresented: Binding(
                get: { viewModel.activeErrorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.activeErrorMessage ?? "")
        }
    }

    // MARK: - Column 1: Notebooks Sidebar

    private var notebookSidebar: some View {
        List(selection: $viewModel.selectedNotebookID) {
            ForEach(viewModel.notebooks) { notebook in
                HStack(spacing: Theme.Spacing.small) {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notebook.title)
                            .font(Theme.Fonts.rowTitle)
                        Text("\(notebook.sections.count) section\(notebook.sections.count == 1 ? "" : "s") • \(notebook.defaultPaperType.displayName)")
                            .font(Theme.Fonts.rowSubtitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(notebook.id)
                .contextMenu {
                    Button {
                        beginRename(.notebook(id: notebook.id, currentTitle: notebook.title))
                    } label: {
                        Label("Rename Notebook", systemImage: "pencil")
                    }

                    Menu {
                        ForEach(PaperType.allCases) { paper in
                            Button {
                                viewModel.setNotebookDefaultPaperType(id: notebook.id, to: paper)
                            } label: {
                                if notebook.defaultPaperType == paper {
                                    Label(paper.displayName, systemImage: "checkmark")
                                } else {
                                    Label(paper.displayName, systemImage: paper.systemImageName)
                                }
                            }
                        }
                    } label: {
                        Label("Default Paper (\(notebook.defaultPaperType.displayName))", systemImage: notebook.defaultPaperType.systemImageName)
                    }

                    Divider()

                    Button(role: .destructive) {
                        deleteTarget = .notebook(id: notebook.id, title: notebook.title)
                    } label: {
                        Label("Delete Notebook", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget = .notebook(id: notebook.id, title: notebook.title)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        beginRename(.notebook(id: notebook.id, currentTitle: notebook.title))
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
            .onMove { source, destination in
                viewModel.moveNotebooks(fromOffsets: source, toOffset: destination)
            }
        }
        .navigationTitle("Notebooks")
        .overlay {
            if viewModel.notebooks.isEmpty {
                ContentUnavailableView {
                    Label("No Notebooks", systemImage: "books.vertical")
                } description: {
                    Text("Create your first notebook for a module or project.")
                } actions: {
                    Button("New Notebook") {
                        viewModel.createNotebook()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    ForEach(PaperType.allCases) { paper in
                        Button {
                            viewModel.createNotebook(defaultPaperType: paper)
                        } label: {
                            Label("New \(paper.displayName) Notebook", systemImage: paper.systemImageName)
                        }
                    }
                } label: {
                    Label("New Notebook", systemImage: "plus")
                } primaryAction: {
                    viewModel.createNotebook()
                }
                .help("Create a new notebook")
            }
        }
    }

    // MARK: - Column 2: Sections and Pages

    @ViewBuilder
    private var sectionAndPageColumn: some View {
        if let notebook = viewModel.selectedNotebook {
            VStack(spacing: 0) {
                sectionsList(for: notebook)
                Divider()
                pagesList(for: notebook)
            }
            .navigationTitle(notebook.title)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker(
                            "Default Paper",
                            selection: Binding<PaperType>(
                                get: { notebook.defaultPaperType },
                                set: { viewModel.setNotebookDefaultPaperType(id: notebook.id, to: $0) }
                            )
                        ) {
                            ForEach(PaperType.allCases) { paper in
                                Label(paper.displayName, systemImage: paper.systemImageName)
                                    .tag(paper)
                            }
                        }
                    } label: {
                        Label("Default Paper", systemImage: notebook.defaultPaperType.systemImageName)
                    }
                    .help("Default paper type for new pages in this notebook")

                    Button {
                        viewModel.createSection(in: notebook.id)
                    } label: {
                        Label("New Section", systemImage: "folder.badge.plus")
                    }
                    .help("Add a section to \(notebook.title)")

                    Button {
                        viewModel.createPage(
                            in: viewModel.selectedSectionID,
                            notebookID: notebook.id,
                            afterPageID: viewModel.selectedPageID
                        )
                    } label: {
                        Label("New Page", systemImage: "doc.badge.plus")
                    }
                    .disabled(viewModel.selectedSection == nil)
                    .help("Add a page below the current page")
                }
            }
        } else {
            ContentUnavailableView(
                "Select a Notebook",
                systemImage: "book.closed",
                description: Text("Choose a notebook in the sidebar or create a new one.")
            )
        }
    }

    private func sectionsList(for notebook: Notebook) -> some View {
        List(selection: $viewModel.selectedSectionID) {
            Section {
                ForEach(notebook.sections) { section in
                    HStack {
                        Label(section.title, systemImage: "folder")
                            .font(Theme.Fonts.rowTitle)
                        Spacer()
                        Text("\(section.pages.count)")
                            .font(Theme.Fonts.rowSubtitle)
                            .foregroundStyle(.secondary)
                    }
                    .tag(section.id)
                    .contextMenu {
                        Button {
                            beginRename(.section(notebookID: notebook.id, sectionID: section.id, currentTitle: section.title))
                        } label: {
                            Label("Rename Section", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) {
                            deleteTarget = .section(notebookID: notebook.id, sectionID: section.id, title: section.title)
                        } label: {
                            Label("Delete Section", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteTarget = .section(notebookID: notebook.id, sectionID: section.id, title: section.title)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            beginRename(.section(notebookID: notebook.id, sectionID: section.id, currentTitle: section.title))
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                .onMove { source, destination in
                    viewModel.moveSections(in: notebook.id, fromOffsets: source, toOffset: destination)
                }
            } header: {
                HStack {
                    Text("Sections")
                    Spacer()
                    Button {
                        viewModel.createSection(in: notebook.id)
                    } label: {
                        Label("Add Section", systemImage: "plus.circle")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .frame(minHeight: 160, maxHeight: 260)
    }

    @ViewBuilder
    private func pagesList(for notebook: Notebook) -> some View {
        if let section = viewModel.selectedSection {
            List(selection: $viewModel.selectedPageID) {
                Section {
                    ForEach(Array(section.pages.enumerated()), id: \.element.id) { index, page in
                        let effectivePaper = page.effectivePaperType(notebookDefault: notebook.defaultPaperType)
                        HStack(spacing: Theme.Spacing.medium) {
                            PageThumbnailView(
                                paperType: effectivePaper,
                                pageNumber: index + 1,
                                isSelected: viewModel.selectedPageID == page.id
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(page.title)
                                    .font(Theme.Fonts.rowTitle)
                                HStack(spacing: 4) {
                                    Image(systemName: effectivePaper.systemImageName)
                                    Text(effectivePaper.displayName)
                                    if page.paperTypeOverride != nil {
                                        Text("(Custom)")
                                    }
                                }
                                .font(Theme.Fonts.rowSubtitle)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(page.id)
                        .contextMenu {
                            Button {
                                viewModel.createPage(
                                    in: section.id,
                                    notebookID: notebook.id,
                                    afterPageID: page.id
                                )
                            } label: {
                                Label("Add Page Below", systemImage: "doc.badge.plus")
                            }

                            Button {
                                beginRename(.page(notebookID: notebook.id, sectionID: section.id, pageID: page.id, currentTitle: page.title))
                            } label: {
                                Label("Rename Page", systemImage: "pencil")
                            }

                            Menu {
                                Button {
                                    viewModel.setPagePaperTypeOverride(
                                        id: page.id,
                                        in: section.id,
                                        notebookID: notebook.id,
                                        to: nil
                                    )
                                } label: {
                                    if page.paperTypeOverride == nil {
                                        Label("Notebook Default (\(notebook.defaultPaperType.displayName))", systemImage: "checkmark")
                                    } else {
                                        Text("Notebook Default (\(notebook.defaultPaperType.displayName))")
                                    }
                                }
                                Divider()
                                ForEach(PaperType.allCases) { paper in
                                    Button {
                                        viewModel.setPagePaperTypeOverride(
                                            id: page.id,
                                            in: section.id,
                                            notebookID: notebook.id,
                                            to: paper
                                        )
                                    } label: {
                                        if page.paperTypeOverride == paper {
                                            Label(paper.displayName, systemImage: "checkmark")
                                        } else {
                                            Label(paper.displayName, systemImage: paper.systemImageName)
                                        }
                                    }
                                }
                            } label: {
                                Label("Paper Style", systemImage: effectivePaper.systemImageName)
                            }

                            Divider()

                            Button(role: .destructive) {
                                deleteTarget = .page(
                                    notebookID: notebook.id,
                                    sectionID: section.id,
                                    pageID: page.id,
                                    title: page.title
                                )
                            } label: {
                                Label("Delete Page", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteTarget = .page(
                                    notebookID: notebook.id,
                                    sectionID: section.id,
                                    pageID: page.id,
                                    title: page.title
                                )
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                beginRename(.page(notebookID: notebook.id, sectionID: section.id, pageID: page.id, currentTitle: page.title))
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .onMove { source, destination in
                        viewModel.movePages(
                            in: section.id,
                            notebookID: notebook.id,
                            fromOffsets: source,
                            toOffset: destination
                        )
                    }
                } header: {
                    HStack {
                        Text("Pages in \(section.title)")
                        Spacer()
                        Button {
                            viewModel.createPage(
                                in: section.id,
                                notebookID: notebook.id,
                                afterPageID: viewModel.selectedPageID
                            )
                        } label: {
                            Label("Add Page", systemImage: "plus.circle")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }
            .overlay {
                if section.pages.isEmpty {
                    ContentUnavailableView {
                        Label("No Pages", systemImage: "doc")
                    } description: {
                        Text("Add a page to \(section.title).")
                    } actions: {
                        Button("New Page") {
                            viewModel.createPage(in: section.id, notebookID: notebook.id)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label("No Section Selected", systemImage: "folder")
            } description: {
                Text("Select or create a section above to view its pages.")
            } actions: {
                Button("New Section") {
                    viewModel.createSection(in: notebook.id)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Column 3: Detail Page View

    @ViewBuilder
    private var detailColumn: some View {
        if let notebook = viewModel.selectedNotebook,
           let section = viewModel.selectedSection,
           let page = viewModel.selectedPage {
            PageCanvasPlaceholderView(
                viewModel: viewModel,
                notebook: notebook,
                section: section,
                page: page
            )
        } else {
            ContentUnavailableView(
                "No Page Selected",
                systemImage: "doc.richtext",
                description: Text("Select or create a page in the sidebar to begin.")
            )
        }
    }

    // MARK: - Rename & Delete Actions

    private func beginRename(_ target: RenameTarget) {
        renameDraftTitle = target.currentTitle
        renameTarget = target
    }

    private func commitRename(target: RenameTarget, newTitle: String) {
        switch target {
        case .notebook(let id, _):
            viewModel.renameNotebook(id: id, to: newTitle)
        case .section(let notebookID, let sectionID, _):
            viewModel.renameSection(id: sectionID, in: notebookID, to: newTitle)
        case .page(let notebookID, let sectionID, let pageID, _):
            viewModel.renamePage(id: pageID, in: sectionID, notebookID: notebookID, to: newTitle)
        }
    }

    private func commitDelete(target: DeleteTarget) {
        switch target {
        case .notebook(let id, _):
            viewModel.deleteNotebook(id: id)
        case .section(let notebookID, let sectionID, _):
            viewModel.deleteSection(id: sectionID, in: notebookID)
        case .page(let notebookID, let sectionID, let pageID, _):
            viewModel.deletePage(id: pageID, in: sectionID, notebookID: notebookID)
        }
    }
}

// MARK: - Supporting Dialog Types

private enum RenameTarget: Identifiable {
    case notebook(id: UUID, currentTitle: String)
    case section(notebookID: UUID, sectionID: UUID, currentTitle: String)
    case page(notebookID: UUID, sectionID: UUID, pageID: UUID, currentTitle: String)

    var id: String {
        switch self {
        case .notebook(let id, _): return "notebook-\(id.uuidString)"
        case .section(_, let sectionID, _): return "section-\(sectionID.uuidString)"
        case .page(_, _, let pageID, _): return "page-\(pageID.uuidString)"
        }
    }

    var currentTitle: String {
        switch self {
        case .notebook(_, let title),
             .section(_, _, let title),
             .page(_, _, _, let title):
            return title
        }
    }

    var kindLabel: String {
        switch self {
        case .notebook: return "Notebook"
        case .section: return "Section"
        case .page: return "Page"
        }
    }
}

private enum DeleteTarget: Identifiable {
    case notebook(id: UUID, title: String)
    case section(notebookID: UUID, sectionID: UUID, title: String)
    case page(notebookID: UUID, sectionID: UUID, pageID: UUID, title: String)

    var id: String {
        switch self {
        case .notebook(let id, _): return "notebook-\(id.uuidString)"
        case .section(_, let sectionID, _): return "section-\(sectionID.uuidString)"
        case .page(_, _, let pageID, _): return "page-\(pageID.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .notebook(_, let title),
             .section(_, _, let title),
             .page(_, _, _, let title):
            return title
        }
    }

    var confirmationTitle: String {
        switch self {
        case .notebook: return "Delete Notebook?"
        case .section: return "Delete Section?"
        case .page: return "Delete Page?"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .notebook(_, let title):
            return "Deleting \"\(title)\" will permanently remove all of its sections and pages."
        case .section(_, _, let title):
            return "Deleting \"\(title)\" will permanently remove all pages inside this section."
        case .page(_, _, _, let title):
            return "Deleting \"\(title)\" cannot be undone."
        }
    }
}
