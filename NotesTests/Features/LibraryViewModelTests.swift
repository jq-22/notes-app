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
    var storedAssets: [UUID: Data] = [:]
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

    func loadAssetData(for assetID: UUID) throws -> Data? {
        storedAssets[assetID]
    }

    func saveAssetData(_ data: Data, for assetID: UUID) throws {
        if shouldFailSaves {
            throw PageStoreError.failedToSaveAsset(assetID: assetID, reason: "Simulated disk full")
        }
        storedAssets[assetID] = data
    }

    func deleteAssetData(for assetIDs: [UUID]) throws {
        for id in assetIDs {
            storedAssets.removeValue(forKey: id)
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

    @Test("Debounced drawing autosave flushes on page change and retains pending data if disk write fails")
    func drawingAutosaveAndFlush() throws {
        let store = InMemoryPageStore()
        let vm = LibraryViewModel(store: store, autosaveDebounceNanoseconds: 500_000_000)

        let notebook = vm.createNotebook(title: "Physics")
        let sectionID = try #require(vm.selectedSectionID)
        let page1ID = try #require(vm.selectedPageID)
        let page2 = try #require(vm.createPage(in: sectionID, notebookID: notebook.id, afterPageID: page1ID, title: "Page 2"))

        vm.selectedPageID = page1ID
        let sampleDrawing = Data([0x10, 0x20, 0x30, 0x40])
        vm.scheduleDrawingAutosave(sampleDrawing, for: page1ID)

        // Immediately readable from memory even before debounce timer fires
        #expect(vm.loadDrawingData(for: page1ID) == sampleDrawing)

        // Switching pages flushes pending drawing to store immediately
        vm.selectedPageID = page2.id
        #expect(store.storedDrawings[page1ID] == sampleDrawing)
        #expect(vm.drawingRevisionByPageID[page1ID] == 1)
    }

    @Test("Swipe navigation moves to next page or creates a new page at the end, and moves back to previous page")
    func swipeNavigationNextOrCreateAndPrevious() throws {
        let store = InMemoryPageStore()
        let vm = LibraryViewModel(store: store)

        let notebook = vm.createNotebook(title: "Swipe Test")
        let page1ID = try #require(vm.selectedPageID)
        #expect(vm.canGoToPreviousPage == false)
        #expect(vm.goToPreviousPage() == false)

        // Swiping next on the last page creates Page 2 and selects it
        let createdPage2 = try #require(vm.goToNextOrCreatePage())
        #expect(createdPage2.id != page1ID)
        #expect(vm.selectedPageID == createdPage2.id)
        #expect(vm.notebooks[0].sections[0].pages.count == 2)
        #expect(vm.canGoToPreviousPage == true)

        // Swiping back returns to Page 1
        #expect(vm.goToPreviousPage() == true)
        #expect(vm.selectedPageID == page1ID)

        // Swiping next again from Page 1 goes to existing Page 2 without creating a 3rd page
        let movedToExistingPage2 = try #require(vm.goToNextOrCreatePage())
        #expect(movedToExistingPage2.id == createdPage2.id)
        #expect(vm.notebooks[0].sections[0].pages.count == 2)
        #expect(notebook.id == vm.selectedNotebookID)
    }

    @Test("Multi-page selection supports moving pages between sections, batch deleting, and PDF export")
    func multiPageBatchMoveDeleteAndPDFExport() throws {
        let store = InMemoryPageStore()
        let vm = LibraryViewModel(store: store)

        let notebook = vm.createNotebook(title: "Engineering")
        let sec1ID = try #require(vm.selectedSectionID)
        let p1ID = try #require(vm.selectedPageID)
        let p2 = try #require(vm.createPage(in: sec1ID, notebookID: notebook.id, afterPageID: p1ID, title: "Page 2"))
        let p3 = try #require(vm.createPage(in: sec1ID, notebookID: notebook.id, afterPageID: p2.id, title: "Page 3"))

        let sec2 = try #require(vm.createSection(in: notebook.id, title: "Section 2"))

        // Move Page 1 and Page 3 from Section 1 to Section 2
        vm.movePages(ids: [p1ID, p3.id], fromSectionID: sec1ID, toSectionID: sec2.id, in: notebook.id)
        #expect(vm.notebooks[0].sections[0].pages.map(\.id) == [p2.id])
        #expect(vm.notebooks[0].sections[1].pages.contains(where: { $0.id == p1ID }))
        #expect(vm.notebooks[0].sections[1].pages.contains(where: { $0.id == p3.id }))

        // Export those two moved pages to a PDF file
        let pdfURL = try PagePDFExporter.exportPDF(
            pages: [
                ExportablePageInput(page: p2, effectivePaperType: .lined, drawingData: nil),
                ExportablePageInput(page: p3, effectivePaperType: .squared, drawingData: nil)
            ],
            fileNameTitle: "Engineering Export"
        )
        let pdfData = try Data(contentsOf: pdfURL)
        #expect(pdfData.count > 100)
        try? FileManager.default.removeItem(at: pdfURL)

        // Batch delete the two moved pages from Section 2
        vm.deletePages(ids: [p1ID, p3.id], in: sec2.id, notebookID: notebook.id)
        #expect(vm.notebooks[0].sections[1].pages.count == 1)
    }

    @Test("Inserting, updating, duplicating, and deleting Basic Shapes and Images persists and selects objects")
    func pageObjectLifecycleInViewModel() throws {
        let store = InMemoryPageStore()
        let vm = LibraryViewModel(store: store)
        let nb = vm.createNotebook(title: "Diagrams")
        let secID = try #require(nb.sections.first?.id)
        let pageID = try #require(nb.sections.first?.pages.first?.id)

        // 1. Insert Basic Shape (Rectangle)
        let rectObj = try #require(vm.insertBasicShape(.rectangle, color: .blue, strokeWidth: 4.0, on: pageID, in: secID, notebookID: nb.id))
        #expect(vm.selectedObjectID == rectObj.id)
        #expect(vm.selectedPage?.objects.count == 1)

        // 2. Move & Resize update
        let moved = rectObj.moved(by: CGSize(width: 25, height: 40))
        vm.updatePageObject(moved, on: pageID, in: secID, notebookID: nb.id)
        #expect(vm.selectedPage?.objects.first?.frame == moved.frame)

        // 3. Duplicate
        let dup = try #require(vm.duplicatePageObject(id: rectObj.id, on: pageID, in: secID, notebookID: nb.id))
        #expect(vm.selectedPage?.objects.count == 2)
        #expect(vm.selectedObjectID == dup.id)

        // 4. Insert Image Object
        let imgBytes = Data([0x01, 0x02, 0x03, 0x04])
        let imgObj = try #require(vm.insertImageObject(imageData: imgBytes, intrinsicSize: CGSize(width: 400, height: 200), on: pageID, in: secID, notebookID: nb.id))
        #expect(vm.selectedPage?.objects.count == 3)
        if case .image(let assetID) = imgObj.kind {
            #expect(vm.loadAssetData(for: assetID) == imgBytes)
        } else {
            Issue.record("Expected image object kind")
        }

        // 5. Delete object
        vm.deletePageObject(id: dup.id, on: pageID, in: secID, notebookID: nb.id)
        #expect(vm.selectedPage?.objects.count == 2)
    }

    @Test("Copying strokes and objects and pasting into another page and notebook creates independent resizable PageObjects")
    func crossNotebookCopyAndPaste() throws {
        let store = InMemoryPageStore()
        let vm = LibraryViewModel(store: store)

        let nb1 = vm.createNotebook(title: "Module 1")
        let sec1ID = try #require(nb1.sections.first?.id)
        let page1ID = try #require(nb1.sections.first?.pages.first?.id)

        let shapeObj = try #require(vm.insertBasicShape(.arrow, color: .red, strokeWidth: 3.0, on: page1ID, in: sec1ID, notebookID: nb1.id))
        let imgBytes = Data([0xAA, 0xBB, 0xCC])
        let imgObj = try #require(vm.insertImageObject(imageData: imgBytes, intrinsicSize: CGSize(width: 200, height: 100), on: page1ID, in: sec1ID, notebookID: nb1.id))

        let sampleStrokeBytes = Data([0x10, 0x20, 0x30])
        vm.copyObjectsAndStrokesToClipboard(
            strokeDrawingData: sampleStrokeBytes,
            strokeBounds: CGRect(x: 80, y: 120, width: 140, height: 90),
            objectIDs: [shapeObj.id, imgObj.id],
            on: page1ID,
            in: sec1ID,
            notebookID: nb1.id
        )
        #expect(vm.canPasteFromClipboard == true)

        // Create a second notebook and paste onto its first page
        let nb2 = vm.createNotebook(title: "Module 2")
        let sec2ID = try #require(nb2.sections.first?.id)
        let page2ID = try #require(nb2.sections.first?.pages.first?.id)

        let pasted = vm.pasteFromClipboard(on: page2ID, in: sec2ID, notebookID: nb2.id)
        #expect(pasted.count == 3) // 1 strokeGroup object + 1 arrow shape + 1 cloned image object
        #expect(vm.selectedPage?.objects.count == 3)
        #expect(pasted.allSatisfy { $0.id != shapeObj.id && $0.id != imgObj.id })
    }
}
