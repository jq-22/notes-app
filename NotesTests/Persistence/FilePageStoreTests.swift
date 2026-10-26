//
//  FilePageStoreTests.swift
//  NotesTests
//
//  Responsibility: Unit tests for `FilePageStore` persistence, separate drawing data storage, and error handling.
//

import Foundation
import Testing
@testable import Notes

@Suite("Persistence — FilePageStore")
struct FilePageStoreTests {

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NotesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Loading from a fresh directory returns an empty array without throwing")
    func emptyStoreReturnsEmptyArray() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = FilePageStore(baseDirectoryURL: dir)
        let loaded = try store.loadNotebooks()
        #expect(loaded.isEmpty)
    }

    @Test("Round-trip saving and loading notebooks preserves UUIDs, hierarchy, and paper overrides")
    func roundTripNotebooks() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = FilePageStore(baseDirectoryURL: dir)

        let page1 = Page(title: "Intro", paperTypeOverride: nil)
        let page2 = Page(title: "Grid Diagram", paperTypeOverride: .squared)
        let section = NoteSection(title: "Week 1", pages: [page1, page2])
        let notebook = Notebook(title: "Test", defaultPaperType: .lined, sections: [section])

        try store.saveNotebooks([notebook])
        let restored = try store.loadNotebooks()

        #expect(restored == [notebook])
        #expect(restored.first?.sections.first?.pages.last?.paperTypeOverride == .squared)
    }

    @Test("Drawing data is saved and deleted separately from notebook metadata")
    func separateDrawingDataLifecycle() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = FilePageStore(baseDirectoryURL: dir)
        let pageID = UUID()
        let samplePayload = Data([0x01, 0x02, 0x03, 0xFF])

        #expect(try store.loadDrawingData(for: pageID) == nil)
        try store.saveDrawingData(samplePayload, for: pageID)
        #expect(try store.loadDrawingData(for: pageID) == samplePayload)

        try store.deleteDrawingData(for: [pageID])
        #expect(try store.loadDrawingData(for: pageID) == nil)
    }

    @Test("Corrupted JSON file surfaces a descriptive PageStoreError")
    func corruptedMetadataThrowsError() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let badFile = dir.appendingPathComponent("notebooks.json")
        try Data("not valid json".utf8).write(to: badFile)

        let store = FilePageStore(baseDirectoryURL: dir)
        #expect(throws: PageStoreError.self) {
            _ = try store.loadNotebooks()
        }
    }

    @Test("Image asset data is saved, loaded, and deleted independently")
    func separateImageAssetDataLifecycle() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = FilePageStore(baseDirectoryURL: dir)
        let assetID = UUID()
        let sampleImageBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        #expect(try store.loadAssetData(for: assetID) == nil)
        try store.saveAssetData(sampleImageBytes, for: assetID)
        #expect(try store.loadAssetData(for: assetID) == sampleImageBytes)

        try store.deleteAssetData(for: [assetID])
        #expect(try store.loadAssetData(for: assetID) == nil)
    }

    @Test("Shape Library items and preview images are saved, loaded, updated, and deleted independently")
    func shapeLibraryPersistenceLifecycle() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = FilePageStore(baseDirectoryURL: dir)
        let notebookID = UUID()

        #expect(try store.loadShapeLibraryItems(for: notebookID).isEmpty)

        let item1 = ShapeLibraryItem(
            notebookID: notebookID,
            label: "Decision Diamond",
            strokeDrawingData: Data([0x01, 0x02, 0x03]),
            sourceBoundsWidth: 150,
            sourceBoundsHeight: 120
        )
        let preview1 = Data([0x89, 0x50, 0x4E, 0x47, 0x01])
        try store.saveShapeLibraryItem(item1, previewPNGData: preview1)

        let loaded = try store.loadShapeLibraryItems(for: notebookID)
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == item1.id)
        #expect(loaded.first?.label == "Decision Diamond")
        #expect(try store.loadShapeLibraryPreview(for: item1.id) == preview1)

        // Add a second item
        let item2 = ShapeLibraryItem(
            notebookID: notebookID,
            label: "Process Box",
            strokeDrawingData: Data([0x04, 0x05]),
            sourceBoundsWidth: 200,
            sourceBoundsHeight: 100
        )
        let preview2 = Data([0x89, 0x50, 0x4E, 0x47, 0x02])
        try store.saveShapeLibraryItem(item2, previewPNGData: preview2)

        let loaded2 = try store.loadShapeLibraryItems(for: notebookID)
        #expect(loaded2.count == 2)

        // Delete first item
        try store.deleteShapeLibraryItem(id: item1.id, notebookID: notebookID)
        let loaded3 = try store.loadShapeLibraryItems(for: notebookID)
        #expect(loaded3.count == 1)
        #expect(loaded3.first?.id == item2.id)
        #expect(try store.loadShapeLibraryPreview(for: item1.id) == nil)
        #expect(try store.loadShapeLibraryPreview(for: item2.id) == preview2)
    }
}
