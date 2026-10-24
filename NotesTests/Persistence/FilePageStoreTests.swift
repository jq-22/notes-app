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
}
