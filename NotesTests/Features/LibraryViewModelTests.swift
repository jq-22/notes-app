//
//  LibraryViewModelTests.swift
//  NotesTests
//
//  Responsibility: Unit tests for `LibraryViewModel` using an in-memory `PageStore` fake to verify CRUD, selection fallback, paper overrides, and error surfacing.
//

import Foundation
import Testing
@testable import Notes

final class InMemoryPageStore: PageStore, @unchecked Sendable {
    var storedNotebooks: [Notebook] = []
    var storedDrawings: [UUID: Data] = [:]
    var shouldFailSaves = false
    var shouldFailLoads = false

    func loadNotebooks() throws -> [Notebook] {
        if shouldFailLoads {
            throw PageStoreError.failedToLoadNotebooks(reason: "Simulated load failure")
        }
        return storedNotebooks
    }

    func saveNotebooks(_ notebooks: [Notebook]) throws {
        if shouldFailSaves {
            throw PageStoreError.failedToSaveNotebooks(reason: "Simulated disk full")
        }
        storedNotebooks = notebooks
    }

    func loadDrawingData(for pageID: UUID) throws -> Data? {
        storedDrawings[pageID]
    }

    func saveDrawingData(_ data: Data, for pageID: UUID) throws {
        if shouldFailSaves {
            throw PageStoreError.failedToSaveDrawing(pageID: pageID, reason: "Simulated disk full")
        }
        storedDrawings[pageID] = data
    }

    func deleteDrawingData(for pageIDs: [UUID]) throws {
        for id in pageIDs {
            storedDrawings.removeValue(forKey: id)
        }
    }
}

@Suite("Features — LibraryViewModel")
@MainActor
struct LibraryViewModelTests {

    @Test("Creating a notebook 'Test' with two sections and mixed paper types persists and restores cleanly")
    func createStructureAndRestore() throws {
        let store = InMemoryPageStore()
        let vm = LibraryViewModel(store: store)

        let notebook = vm.createNotebook(title: "Test", defaultPaperType: .lined)
        #expect(vm.selectedNotebookID == notebook.id)
        #expect(vm.selectedSection != nil)
        #expect(vm.selectedPage != nil)

        guard let section1ID = vm.selectedSectionID,
              let page1ID = vm.selectedPageID else {
            Issue.record("Expected initial section and page to be created")
            return
        }

        // Add a second page below page 1 and override its paper type to squared
        let page2 = vm.createPage(in: section1ID, notebookID: notebook.id, afterPageID: page1ID, title: "Diagram Page")
        #expect(page2 != nil)
        if let page2 {
            vm.setPagePaperTypeOverride(id: page2.id, in: section1ID, notebookID: notebook.id, to: .squared)
        }

        // Add a second section with a blank page override
        let section2 = vm.createSection(in: notebook.id, title: "Section 2")
        #expect(section2 != nil)
        if let section2, let sec2Page1 = section2.pages.first {
            vm.setPagePaperTypeOverride(id: sec2Page1.id, in: section2.id, notebookID: notebook.id, to: .blank)
        }

        // Simulate app relaunch with a fresh ViewModel reading from the same store
        let reopenedVM = LibraryViewModel(store: store)
        #expect(reopenedVM.notebooks.count == 1)
        #expect(reopenedVM.notebooks[0].title == "Test")
        #expect(reopenedVM.notebooks[0].sections.count == 2)
        #expect(reopenedVM.notebooks[0].sections[0].pages.count == 2)
        #expect(reopenedVM.notebooks[0].sections[0].pages[0].effectivePaperType(notebookDefault: .lined) == .lined)
        #expect(reopenedVM.notebooks[0].sections[0].pages[1].effectivePaperType(notebookDefault: .lined) == .squared)
        #expect(reopenedVM.notebooks[0].sections[1].pages[0].effectivePaperType(notebookDefault: .lined) == .blank)
    }

    @Test("Deleting a section or notebook cleans up associated drawing data and updates selection")
    func deleteCleansUpDrawingsAndSelection() throws {
        let store = InMemoryPageStore()
        let vm = LibraryViewModel(store: store)

        let notebook = vm.createNotebook(title: "Electronics")
        let pageID = try #require(vm.selectedPageID)
        try store.saveDrawingData(Data([0xAA, 0xBB]), for: pageID)
        #expect(store.storedDrawings[pageID] != nil)

        vm.deleteNotebook(id: notebook.id)
        #expect(vm.notebooks.isEmpty)
        #expect(vm.selectedNotebookID == nil)
        #expect(store.storedDrawings[pageID] == nil)
    }

    @Test("Save failures surface in activeErrorMessage instead of failing silently")
    func saveFailureSurfacesError() {
        let store = InMemoryPageStore()
        let vm = LibraryViewModel(store: store)
        store.shouldFailSaves = true

        _ = vm.createNotebook(title: "Should Alert")
        #expect(vm.activeErrorMessage != nil)
        #expect(vm.activeErrorMessage?.contains("Simulated disk full") == true)

        vm.clearError()
        #expect(vm.activeErrorMessage == nil)
    }
}
