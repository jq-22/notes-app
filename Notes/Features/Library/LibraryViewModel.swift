//
//  LibraryViewModel.swift
//  Notes
//
//  Responsibility: Coordinates the Notebook → Section → Page navigation state, CRUD operations, reordering, paper-type settings, and automatic persistence via `PageStore`.
//  Inputs/Outputs: Observable state consumed by `LibraryRootView` and child views; persists every structural change through `PageStore` and on scene backgrounding.
//  Dependencies: Foundation, Observation, Domain, Persistence.
//  Errors: Any `PageStore` failure sets `activeErrorMessage` so the UI displays an alert rather than swallowing the error.
//  Tested in: NotesTests/Features/LibraryViewModelTests.swift
//

import Foundation
import Observation

@MainActor
@Observable
public final class LibraryViewModel {
    private let store: PageStore

    public private(set) var notebooks: [Notebook] = []
    public var selectedNotebookID: UUID? {
        didSet {
            if oldValue != selectedNotebookID {
                ensureValidSectionAndPageSelection()
            }
        }
    }
    public var selectedSectionID: UUID? {
        didSet {
            if oldValue != selectedSectionID {
                ensureValidPageSelection()
            }
        }
    }
    public var selectedPageID: UUID? {
        willSet {
            if selectedPageID != newValue {
                flushPendingDrawings()
            }
        }
    }

    /// Non-nil when a save or load operation fails; bound to a user-visible alert.
    public var activeErrorMessage: String?

    /// User preference for Scribble-to-Erase (persisted in UserDefaults, defaults to true).
    public var isScribbleToEraseEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isScribbleToEraseEnabled, forKey: Self.scribbleEnabledDefaultsKey)
        }
    }

    /// Monotonically incremented each time a page's drawing data is saved so sidebar thumbnails refresh.
    public private(set) var drawingRevisionByPageID: [UUID: Int] = [:]

    private var pendingDrawingByPageID: [UUID: Data] = [:]
    private var debounceSaveTasks: [UUID: Task<Void, Never>] = [:]
    private let autosaveDebounceNanoseconds: UInt64

    public static let scribbleEnabledDefaultsKey = "Notes.isScribbleToEraseEnabled"

    public init(
        store: PageStore,
        loadImmediately: Bool = true,
        autosaveDebounceNanoseconds: UInt64 = 400_000_000 // 400ms
    ) {
        self.store = store
        self.autosaveDebounceNanoseconds = autosaveDebounceNanoseconds
        if UserDefaults.standard.object(forKey: Self.scribbleEnabledDefaultsKey) == nil {
            self.isScribbleToEraseEnabled = true
        } else {
            self.isScribbleToEraseEnabled = UserDefaults.standard.bool(forKey: Self.scribbleEnabledDefaultsKey)
        }
        if loadImmediately {
            loadFromStore()
        }
    }

    // MARK: - Computed Active Items

    public var selectedNotebook: Notebook? {
        guard let selectedNotebookID else { return nil }
        return notebooks.first(where: { $0.id == selectedNotebookID })
    }

    public var selectedSection: NoteSection? {
        guard let notebook = selectedNotebook, let selectedSectionID else { return nil }
        return notebook.sections.first(where: { $0.id == selectedSectionID })
    }

    public var selectedPage: Page? {
        guard let section = selectedSection, let selectedPageID else { return nil }
        return section.pages.first(where: { $0.id == selectedPageID })
    }

    /// Returns the effective `PaperType` for any page in the currently selected notebook.
    public func effectivePaperType(for page: Page) -> PaperType {
        let defaultPaper = selectedNotebook?.defaultPaperType ?? .lined
        return page.effectivePaperType(notebookDefault: defaultPaper)
    }

    // MARK: - Persistence

    public func loadFromStore() {
        do {
            notebooks = try store.loadNotebooks()
            if selectedNotebookID == nil || !notebooks.contains(where: { $0.id == selectedNotebookID }) {
                selectedNotebookID = notebooks.first?.id
            }
            ensureValidSectionAndPageSelection()
        } catch {
            activeErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func saveNow() {
        flushPendingDrawings()
        do {
            try store.saveNotebooks(notebooks)
        } catch {
            activeErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Drawing Persistence & Debounced Autosave

    /// Loads the current drawing data for `pageID` (returning any unsaved in-memory buffer first, or loading from `store`).
    public func loadDrawingData(for pageID: UUID) -> Data? {
        if let pending = pendingDrawingByPageID[pageID] {
            return pending
        }
        do {
            return try store.loadDrawingData(for: pageID)
        } catch {
            activeErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// Schedules a debounced autosave after a stroke completes.
    public func scheduleDrawingAutosave(_ data: Data, for pageID: UUID) {
        pendingDrawingByPageID[pageID] = data
        debounceSaveTasks[pageID]?.cancel()

        let delay = autosaveDebounceNanoseconds
        debounceSaveTasks[pageID] = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            self?.commitPendingDrawing(for: pageID)
        }
    }

    /// Immediately writes any pending debounced drawing data to `PageStore` (called on page switch or app backgrounding).
    public func flushPendingDrawings() {
        for (_, task) in debounceSaveTasks {
            task.cancel()
        }
        debounceSaveTasks.removeAll()

        let pendingIDs = Array(pendingDrawingByPageID.keys)
        for pageID in pendingIDs {
            commitPendingDrawing(for: pageID)
        }
    }

    private func commitPendingDrawing(for pageID: UUID) {
        guard let data = pendingDrawingByPageID.removeValue(forKey: pageID) else { return }
        debounceSaveTasks.removeValue(forKey: pageID)
        do {
            try store.saveDrawingData(data, for: pageID)
            drawingRevisionByPageID[pageID, default: 0] += 1
        } catch {
            // Retain in pending dictionary so a page's strokes are never lost in memory if disk write fails
            pendingDrawingByPageID[pageID] = data
            activeErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func clearError() {
        activeErrorMessage = nil
    }

    // MARK: - Notebook Operations

    @discardableResult
    public func createNotebook(title: String? = nil, defaultPaperType: PaperType = .lined) -> Notebook {
        let nextNumber = notebooks.count + 1
        let resolvedTitle = title ?? "Notebook \(nextNumber)"
        let now = Date()
        let firstPage = Page(title: "Page 1", paperTypeOverride: nil, createdAt: now, updatedAt: now)
        let firstSection = NoteSection(
            title: "Section 1",
            pages: [firstPage],
            createdAt: now,
            updatedAt: now
        )
        let notebook = Notebook(
            title: resolvedTitle,
            defaultPaperType: defaultPaperType,
            sections: [firstSection],
            createdAt: now,
            updatedAt: now
        )
        notebooks.append(notebook)
        selectedNotebookID = notebook.id
        selectedSectionID = firstSection.id
        selectedPageID = firstPage.id
        saveNow()
        return notebook
    }

    public func renameNotebook(id notebookID: UUID, to newTitle: String) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookID }) else { return }
        notebooks[index].rename(to: newTitle)
        saveNow()
    }

    public func setNotebookDefaultPaperType(id notebookID: UUID, to paperType: PaperType) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookID }) else { return }
        notebooks[index].setDefaultPaperType(paperType)
        saveNow()
    }

    public func moveNotebooks(fromOffsets source: IndexSet, toOffset destination: Int) {
        notebooks.moveElements(fromOffsets: source, toOffset: destination)
        saveNow()
    }

    public func deleteNotebook(id notebookID: UUID) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookID }) else { return }
        let removed = notebooks.remove(at: index)
        let pageIDs = removed.sections.flatMap { $0.pages.map(\.id) }

        if selectedNotebookID == notebookID {
            selectedNotebookID = notebooks.first?.id
            ensureValidSectionAndPageSelection()
        }

        for pid in pageIDs {
            debounceSaveTasks[pid]?.cancel()
            debounceSaveTasks.removeValue(forKey: pid)
            pendingDrawingByPageID.removeValue(forKey: pid)
        }
        saveNow()
        do {
            try store.deleteDrawingData(for: pageIDs)
        } catch {
            activeErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Section Operations

    @discardableResult
    public func createSection(in notebookID: UUID? = nil, title: String? = nil) -> NoteSection? {
        guard let targetNotebookID = notebookID ?? selectedNotebookID,
              let notebookIndex = notebooks.firstIndex(where: { $0.id == targetNotebookID }) else {
            return nil
        }
        let newSection = notebooks[notebookIndex].addSection(title: title)
        selectedNotebookID = targetNotebookID
        selectedSectionID = newSection.id
        selectedPageID = newSection.pages.first?.id
        saveNow()
        return newSection
    }

    public func renameSection(id sectionID: UUID, in notebookID: UUID? = nil, to newTitle: String) {
        guard let targetNotebookID = notebookID ?? selectedNotebookID,
              let notebookIndex = notebooks.firstIndex(where: { $0.id == targetNotebookID }),
              let sectionIndex = notebooks[notebookIndex].sections.firstIndex(where: { $0.id == sectionID }) else {
            return
        }
        notebooks[notebookIndex].sections[sectionIndex].rename(to: newTitle)
        notebooks[notebookIndex].updatedAt = Date()
        saveNow()
    }

    public func moveSections(in notebookID: UUID? = nil, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let targetNotebookID = notebookID ?? selectedNotebookID,
              let notebookIndex = notebooks.firstIndex(where: { $0.id == targetNotebookID }) else {
            return
        }
        notebooks[notebookIndex].moveSections(fromOffsets: source, toOffset: destination)
        saveNow()
    }

    public func deleteSection(id sectionID: UUID, in notebookID: UUID? = nil) {
        guard let targetNotebookID = notebookID ?? selectedNotebookID,
              let notebookIndex = notebooks.firstIndex(where: { $0.id == targetNotebookID }),
              let removed = notebooks[notebookIndex].deleteSection(id: sectionID) else {
            return
        }
        let pageIDs = removed.pages.map(\.id)

        if selectedSectionID == sectionID {
            ensureValidSectionAndPageSelection()
        }

        for pid in pageIDs {
            debounceSaveTasks[pid]?.cancel()
            debounceSaveTasks.removeValue(forKey: pid)
            pendingDrawingByPageID.removeValue(forKey: pid)
        }
        saveNow()
        do {
            try store.deleteDrawingData(for: pageIDs)
        } catch {
            activeErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Page Operations

    /// Adds a new page immediately below the specified `afterPageID` (or below the currently selected page if omitted).
    /// Inherits the notebook's default paper type (`paperTypeOverride == nil`).
    @discardableResult
    public func createPage(
        in sectionID: UUID? = nil,
        notebookID: UUID? = nil,
        afterPageID: UUID? = nil,
        title: String? = nil
    ) -> Page? {
        guard let targetNotebookID = notebookID ?? selectedNotebookID,
              let notebookIndex = notebooks.firstIndex(where: { $0.id == targetNotebookID }),
              let targetSectionID = sectionID ?? selectedSectionID,
              let sectionIndex = notebooks[notebookIndex].sections.firstIndex(where: { $0.id == targetSectionID }) else {
            return nil
        }

        let insertionAnchor = afterPageID ?? selectedPageID
        let newPage = notebooks[notebookIndex].sections[sectionIndex].addPage(
            title: title,
            afterPageID: insertionAnchor
        )
        notebooks[notebookIndex].updatedAt = Date()
        selectedNotebookID = targetNotebookID
        selectedSectionID = targetSectionID
        selectedPageID = newPage.id
        saveNow()
        return newPage
    }

    public func renamePage(
        id pageID: UUID,
        in sectionID: UUID? = nil,
        notebookID: UUID? = nil,
        to newTitle: String
    ) {
        guard let indices = pageIndices(pageID: pageID, sectionID: sectionID, notebookID: notebookID) else {
            return
        }
        let now = Date()
        notebooks[indices.notebook].sections[indices.section].pages[indices.page].rename(to: newTitle, now: now)
        notebooks[indices.notebook].sections[indices.section].updatedAt = now
        notebooks[indices.notebook].updatedAt = now
        saveNow()
    }

    /// Sets or clears a page's paper type override without touching any drawing data.
    public func setPagePaperTypeOverride(
        id pageID: UUID,
        in sectionID: UUID? = nil,
        notebookID: UUID? = nil,
        to overrideType: PaperType?
    ) {
        guard let indices = pageIndices(pageID: pageID, sectionID: sectionID, notebookID: notebookID) else {
            return
        }
        let now = Date()
        notebooks[indices.notebook].sections[indices.section].pages[indices.page].setPaperTypeOverride(overrideType, now: now)
        notebooks[indices.notebook].sections[indices.section].updatedAt = now
        notebooks[indices.notebook].updatedAt = now
        saveNow()
    }

    public func movePages(
        in sectionID: UUID? = nil,
        notebookID: UUID? = nil,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        guard let targetNotebookID = notebookID ?? selectedNotebookID,
              let notebookIndex = notebooks.firstIndex(where: { $0.id == targetNotebookID }),
              let targetSectionID = sectionID ?? selectedSectionID,
              let sectionIndex = notebooks[notebookIndex].sections.firstIndex(where: { $0.id == targetSectionID }) else {
            return
        }
        notebooks[notebookIndex].sections[sectionIndex].movePages(fromOffsets: source, toOffset: destination)
        notebooks[notebookIndex].updatedAt = Date()
        saveNow()
    }

    public func deletePage(id pageID: UUID, in sectionID: UUID? = nil, notebookID: UUID? = nil) {
        guard let targetNotebookID = notebookID ?? selectedNotebookID,
              let notebookIndex = notebooks.firstIndex(where: { $0.id == targetNotebookID }),
              let targetSectionID = sectionID ?? selectedSectionID,
              let sectionIndex = notebooks[notebookIndex].sections.firstIndex(where: { $0.id == targetSectionID }),
              notebooks[notebookIndex].sections[sectionIndex].deletePage(id: pageID) != nil else {
            return
        }
        notebooks[notebookIndex].updatedAt = Date()

        if selectedPageID == pageID {
            ensureValidPageSelection()
        }

        debounceSaveTasks[pageID]?.cancel()
        debounceSaveTasks.removeValue(forKey: pageID)
        pendingDrawingByPageID.removeValue(forKey: pageID)
        saveNow()
        do {
            try store.deleteDrawingData(for: [pageID])
        } catch {
            activeErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Selection Helpers

    private func ensureValidSectionAndPageSelection() {
        guard let notebook = selectedNotebook else {
            selectedSectionID = nil
            selectedPageID = nil
            return
        }
        if let currentSectionID = selectedSectionID,
           notebook.sections.contains(where: { $0.id == currentSectionID }) {
            ensureValidPageSelection()
        } else {
            selectedSectionID = notebook.sections.first?.id
            ensureValidPageSelection()
        }
    }

    private func ensureValidPageSelection() {
        guard let section = selectedSection else {
            selectedPageID = nil
            return
        }
        if let currentPageID = selectedPageID,
           section.pages.contains(where: { $0.id == currentPageID }) {
            return
        }
        selectedPageID = section.pages.first?.id
    }

    private func pageIndices(
        pageID: UUID,
        sectionID: UUID?,
        notebookID: UUID?
    ) -> (notebook: Int, section: Int, page: Int)? {
        guard let targetNotebookID = notebookID ?? selectedNotebookID,
              let notebookIndex = notebooks.firstIndex(where: { $0.id == targetNotebookID }),
              let targetSectionID = sectionID ?? selectedSectionID,
              let sectionIndex = notebooks[notebookIndex].sections.firstIndex(where: { $0.id == targetSectionID }),
              let pageIndex = notebooks[notebookIndex].sections[sectionIndex].pages.firstIndex(where: { $0.id == pageID }) else {
            return nil
        }
        return (notebookIndex, sectionIndex, pageIndex)
    }
}
