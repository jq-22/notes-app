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
    var storedShapeItems: [UUID: [ShapeLibraryItem]] = [:]
    var storedShapePreviews: [UUID: Data] = [:]
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

    func loadShapeLibraryItems(for notebookID: UUID) throws -> [ShapeLibraryItem] {
        if shouldFailLoads {
            throw PageStoreError.failedToLoadShapeLibrary(notebookID: notebookID, reason: "Simulated failure")
        }
        return storedShapeItems[notebookID] ?? []
    }

    func saveShapeLibraryItem(_ item: ShapeLibraryItem, previewPNGData: Data) throws {
        if shouldFailSaves {
            throw PageStoreError.failedToSaveShapeLibraryItem(itemID: item.id, reason: "Simulated failure")
        }
        var items = storedShapeItems[item.notebookID] ?? []
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items.insert(item, at: 0)
        }
        storedShapeItems[item.notebookID] = items
        storedShapePreviews[item.id] = previewPNGData
    }

    func deleteShapeLibraryItem(id itemID: UUID, notebookID: UUID) throws {
        storedShapeItems[notebookID]?.removeAll { $0.id == itemID }
        storedShapePreviews.removeValue(forKey: itemID)
    }

    func loadShapeLibraryPreview(for itemID: UUID) throws -> Data? {
        storedShapePreviews[itemID]
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

    @Test("Shape Library saving, loading, placing as PageObject, and deleting")
    func shapeLibraryOperations() throws {
        let store = InMemoryPageStore()
        let vm = LibraryViewModel(store: store)

        let nb = vm.createNotebook(title: "Architecture")
        let secID = try #require(nb.sections.first?.id)
        let pageID = try #require(nb.sections.first?.pages.first?.id)

        let sampleDrawingData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let samplePNGData = Data([0x89, 0x50, 0x4E, 0x47])
        let bounds = CGRect(x: 100, y: 150, width: 220, height: 180)

        // 1. Save to Shape Library
        let savedItem = try #require(vm.saveToShapeLibrary(
            label: "Microservice Node",
            strokeDrawingData: sampleDrawingData,
            sourceBounds: bounds,
            previewPNGData: samplePNGData,
            notebookID: nb.id
        ))

        #expect(savedItem.label == "Microservice Node")
        #expect(savedItem.sourceBoundsWidth == 220)
        #expect(savedItem.sourceBoundsHeight == 180)

        // 2. Load shape library items & preview
        let items = vm.loadShapeLibraryItems(for: nb.id)
        #expect(items.count == 1)
        #expect(items.first?.id == savedItem.id)
        #expect(vm.loadShapeLibraryPreview(for: savedItem.id) == samplePNGData)

        // 3. Place shape onto page as an interactive strokeGroup PageObject
        let placedObj = try #require(vm.placeShapeLibraryItem(savedItem, on: pageID, in: secID, notebookID: nb.id))
        #expect(vm.selectedPage?.objects.count == 1)
        #expect(placedObj.frame.width == 220)
        #expect(placedObj.frame.height == 180)
        if case .strokeGroup(let data, let w, let h, let tint) = placedObj.kind {
            #expect(data == sampleDrawingData)
            #expect(w == 220)
            #expect(h == 180)
            #expect(tint == nil)
        } else {
            Issue.record("Expected strokeGroup kind for placed shape library item")
        }

        // 4. Delete shape library item
        vm.deleteShapeLibraryItem(id: savedItem.id, notebookID: nb.id)
        #expect(vm.loadShapeLibraryItems(for: nb.id).isEmpty)
    }

    @Test("Inserting tables and page links, and navigating across pages")
    func tableAndPageLinkOperations() throws {
        let store = InMemoryPageStore()
        let vm = LibraryViewModel(store: store)

        let nb1 = vm.createNotebook(title: "Maths")
        let sec1ID = try #require(nb1.sections.first?.id)
        let page1ID = try #require(nb1.sections.first?.pages.first?.id)

        // 1. Insert a 3x4 Table
        let tableObj = try #require(vm.insertTable(rows: 4, columns: 3, color: .blue, hasHeaderRow: true, on: page1ID, in: sec1ID, notebookID: nb1.id))
        #expect(vm.selectedPage?.objects.count == 1)
        #expect(vm.selectedObjectID == tableObj.id)
        if case .table(let tableProps) = tableObj.kind {
            #expect(tableProps.rowCount == 4)
            #expect(tableProps.columnCount == 3)
            #expect(tableProps.strokeColor == .blue)
            #expect(tableProps.hasHeaderRow == true)
            #expect(tableProps.isTextMode == false) // Auto-selected to Draw Mode
        } else {
            Issue.record("Expected table kind")
        }

        // 2. Create another page in a second notebook to link to
        let nb2 = vm.createNotebook(title: "Physics")
        let sec2ID = try #require(nb2.sections.first?.id)
        let page2ID = try #require(nb2.sections.first?.pages.first?.id)

        // Switch back to Page 1 and insert a Page Link pointing to Page 2
        vm.navigateToPage(pageID: page1ID, sectionID: sec1ID, notebookID: nb1.id)
        #expect(vm.selectedPageID == page1ID)

        let linkObj = try #require(vm.insertPageLink(
            targetPageID: page2ID,
            targetSectionID: sec2ID,
            targetNotebookID: nb2.id,
            title: "Physics Page 1",
            on: page1ID,
            in: sec1ID,
            notebookID: nb1.id
        ))
        #expect(vm.selectedPage?.objects.count == 2)
        #expect(vm.selectedObjectID == linkObj.id)

        // 3. Navigate to Page 2 via link target
        vm.navigateToPage(pageID: page2ID, sectionID: sec2ID, notebookID: nb2.id)
        #expect(vm.selectedNotebookID == nb2.id)
        #expect(vm.selectedSectionID == sec2ID)
        #expect(vm.selectedPageID == page2ID)
        #expect(vm.selectedObjectID == nil)
    }

    @Test("LibraryViewModel toggles bookmarks, persists changes, and handles filtering")
    func bookmarkOperationsAndFiltering() throws {
        let fake = InMemoryPageStore()
        let vm = LibraryViewModel(store: fake)

        let notebook = vm.createNotebook(title: "Architecture")
        let sectionID = try #require(notebook.sections.first?.id)
        let page1ID = try #require(notebook.sections.first?.pages.first?.id)
        let page2 = try #require(vm.createPage(in: sectionID, notebookID: notebook.id, title: "Drafting"))

        vm.selectedPageID = page1ID
        #expect(vm.isBookmarkFilterActive == false)
        #expect(vm.selectedPage?.isBookmarked == false)

        // Toggle bookmark on page 1
        vm.toggleBookmark(id: page1ID, in: sectionID, notebookID: notebook.id)
        #expect(vm.selectedPage?.isBookmarked == true)
        #expect(fake.storedNotebooks.first?.sections.first?.pages.first?.isBookmarked == true)

        // Page 2 is not bookmarked
        let p2InStore = fake.storedNotebooks.first?.sections.first?.pages.first(where: { $0.id == page2.id })
        #expect(p2InStore?.isBookmarked == false)

        // Set explicit bookmark on page 2
        vm.setPageBookmarked(id: page2.id, in: sectionID, notebookID: notebook.id, to: true)
        let p2Bookmarked = fake.storedNotebooks.first?.sections.first?.pages.first(where: { $0.id == page2.id })
        #expect(p2Bookmarked?.isBookmarked == true)

        // Toggle page 1 back to false
        vm.toggleBookmark(id: page1ID, in: sectionID, notebookID: notebook.id)
        #expect(vm.selectedPage?.isBookmarked == false)

        // Test filter state toggle
        vm.isBookmarkFilterActive = true
        #expect(vm.isBookmarkFilterActive == true)
    }

    @Test("TextBox insert, debounced live edit, flush/save, duplicate, and cross-notebook copy/cut/paste")
    func textBoxLifecycleDebouncedSaveAndClipboard() throws {
        let store = InMemoryPageStore()
        let vm = LibraryViewModel(store: store, autosaveDebounceNanoseconds: 500_000_000)

        let nb1 = vm.createNotebook(title: "Text Notebook")
        let sec1ID = try #require(nb1.sections.first?.id)
        let page1ID = try #require(nb1.sections.first?.pages.first?.id)
        let page2 = try #require(vm.createPage(in: sec1ID, notebookID: nb1.id, afterPageID: page1ID, title: "Page 2"))
        vm.selectedPageID = page1ID

        // 1. Insert TextBox selects it and clears Lasso mode
        vm.isLassoModeActive = true
        let inserted = try #require(vm.insertTextBox(text: "Initial", on: page1ID, in: sec1ID, notebookID: nb1.id))
        #expect(vm.selectedObjectID == inserted.id)
        #expect(vm.isLassoModeActive == false)
        #expect(store.storedNotebooks.first?.sections.first?.pages.first?.objects.count == 1)

        // 2. Live update with persistImmediately: false updates in-memory without immediate disk write, then flushes on page change
        let editedStyle = TextBoxStyle(
            fontSize: 22,
            isBold: true,
            isItalic: true,
            alignment: .center,
            textColor: .blue,
            backgroundColor: .yellow,
            borderColor: .orange
        )
        let liveUpdated = inserted.withText("Live Typed Text").withTextBoxStyle(editedStyle)
        vm.updatePageObject(liveUpdated, on: page1ID, in: sec1ID, notebookID: nb1.id, persistImmediately: false)

        // In-memory state is updated immediately
        if case .textBox(let text, let style) = vm.selectedPage?.objects.first?.kind {
            #expect(text == "Live Typed Text")
            #expect(style == editedStyle)
        } else {
            Issue.record("Expected updated textBox in memory")
        }
        // Store still has "Initial" until flushed
        if case .textBox(let persistedText, _) = store.storedNotebooks.first?.sections.first?.pages.first?.objects.first?.kind {
            #expect(persistedText == "Initial")
        }

        // Switching pages flushes pending metadata edits
        vm.selectedPageID = page2.id
        if case .textBox(let flushedText, let flushedStyle) = store.storedNotebooks.first?.sections.first?.pages.first?.objects.first?.kind {
            #expect(flushedText == "Live Typed Text")
            #expect(flushedStyle == editedStyle)
        } else {
            Issue.record("Expected flushed textBox in store")
        }

        // 3. Duplicate TextBox
        vm.selectedPageID = page1ID
        let dup = try #require(vm.duplicatePageObject(id: inserted.id, on: page1ID, in: sec1ID, notebookID: nb1.id))
        #expect(dup.id != inserted.id)
        #expect(abs(dup.x - (liveUpdated.x + 18)) < 0.001)
        #expect(abs(dup.y - (liveUpdated.y + 18)) < 0.001)
        #expect(dup.kind == liveUpdated.kind)

        // 4. Copy single TextBox and paste onto Page 2 in another notebook
        vm.copySingleObjectToClipboard(id: inserted.id, on: page1ID, in: sec1ID, notebookID: nb1.id)
        #expect(vm.canPasteFromClipboard == true)

        let nb2 = vm.createNotebook(title: "Destination Notebook")
        let sec2ID = try #require(nb2.sections.first?.id)
        let page2Nb2ID = try #require(nb2.sections.first?.pages.first?.id)

        let pasted = vm.pasteFromClipboard(on: page2Nb2ID, in: sec2ID, notebookID: nb2.id)
        #expect(pasted.count == 1)
        #expect(pasted[0].id != inserted.id)
        #expect(pasted[0].kind == liveUpdated.kind)

        // 5. Cut mixed (TextBox + strokes) from Page 1 and paste onto Page 2
        let strokeData = Data([0xAA, 0xBB, 0xCC])
        vm.copyObjectsAndStrokesToClipboard(
            strokeDrawingData: strokeData,
            strokeBounds: CGRect(x: 40, y: 60, width: 120, height: 80),
            objectIDs: [dup.id],
            on: page1ID,
            in: sec1ID,
            notebookID: nb1.id
        )
        // Simulate Cut removal
        let remaining = (vm.notebooks[0].sections[0].pages[0].objects).filter { $0.id != dup.id }
        vm.setPageObjects(remaining, on: page1ID, in: sec1ID, notebookID: nb1.id)
        #expect(vm.notebooks[0].sections[0].pages[0].objects.count == 1)

        let cutPasted = vm.pasteFromClipboard(on: page2.id, in: sec1ID, notebookID: nb1.id)
        #expect(cutPasted.count == 2) // 1 strokeGroup + 1 textBox
        #expect(cutPasted.contains(where: { if case .textBox(let t, _) = $0.kind { return t == "Live Typed Text" }; return false }))

        // 6. Wide TextBox paste clamps safely to >= 16pt instead of going negative
        let wideBox = PageObject(
            frame: CGRect(x: 10, y: 100, width: PageGeometry.a4Width, height: 100),
            kind: .textBox(text: "Wide", style: TextBoxStyle())
        )
        vm.addPageObject(wideBox, on: page1ID, in: sec1ID, notebookID: nb1.id)
        vm.copySingleObjectToClipboard(id: wideBox.id, on: page1ID, in: sec1ID, notebookID: nb1.id)
        let pastedWide = vm.pasteFromClipboard(on: page2.id, in: sec1ID, notebookID: nb1.id)
        #expect(pastedWide.count == 1)
        #expect(pastedWide[0].x >= 16)

        // 7. Pasting onto a page with a high-zIndex object assigns strictly higher zIndex
        let highZObj = PageObject(
            frame: CGRect(x: 50, y: 50, width: 100, height: 100),
            zIndex: 50,
            kind: .basicShape(kind: .rectangle, strokeColor: .black, strokeWidth: 2)
        )
        vm.addPageObject(highZObj, on: page2.id, in: sec1ID, notebookID: nb1.id)
        let pastedHighZ = vm.pasteFromClipboard(on: page2.id, in: sec1ID, notebookID: nb1.id)
        #expect(pastedHighZ.count == 1)
        #expect(pastedHighZ[0].zIndex > 50)
    }
}
