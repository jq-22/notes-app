//
//  FilePageStore.swift
//  Notes
//
//  Responsibility: File-based implementation of `PageStore` using atomic writes in Application Support (or a custom directory for tests).
//  Layout on disk:
//    <baseDirectory>/notebooks.json             (metadata for all notebooks, sections, pages)
//    <baseDirectory>/Drawings/<page-uuid>.pkdrawing   (raw PKDrawing bytes per page)
//  Dependencies: Foundation, Domain, PageStore.
//  Errors: Surfaces all I/O or decoding failures as `PageStoreError`.
//  Tested in: NotesTests/Persistence/FilePageStoreTests.swift
//

import Foundation

public final class FilePageStore: PageStore, @unchecked Sendable {
    private let baseDirectoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    public init(baseDirectoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let baseDirectoryURL {
            self.baseDirectoryURL = baseDirectoryURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.baseDirectoryURL = appSupport.appendingPathComponent("NotesAppStorage", isDirectory: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        self.decoder = decoder
    }

    private var notebooksFileURL: URL {
        baseDirectoryURL.appendingPathComponent("notebooks.json", isDirectory: false)
    }

    private var drawingsDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("Drawings", isDirectory: true)
    }

    private var assetsDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("Assets", isDirectory: true)
    }

    private var shapeLibraryDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("ShapeLibrary", isDirectory: true)
    }

    private var shapePreviewsDirectoryURL: URL {
        shapeLibraryDirectoryURL.appendingPathComponent("Previews", isDirectory: true)
    }

    private func drawingFileURL(for pageID: UUID) -> URL {
        drawingsDirectoryURL.appendingPathComponent("\(pageID.uuidString).pkdrawing", isDirectory: false)
    }

    private func assetFileURL(for assetID: UUID) -> URL {
        assetsDirectoryURL.appendingPathComponent("\(assetID.uuidString).dat", isDirectory: false)
    }

    private func shapeLibraryFileURL(for notebookID: UUID) -> URL {
        shapeLibraryDirectoryURL.appendingPathComponent("\(notebookID.uuidString).json", isDirectory: false)
    }

    private func shapePreviewFileURL(for itemID: UUID) -> URL {
        shapePreviewsDirectoryURL.appendingPathComponent("\(itemID.uuidString).png", isDirectory: false)
    }

    private func ensureDirectoriesExist() throws {
        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: drawingsDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: assetsDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: shapeLibraryDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: shapePreviewsDirectoryURL, withIntermediateDirectories: true)
    }

    public func loadNotebooks() throws -> [Notebook] {
        lock.lock()
        defer { lock.unlock() }

        let url = notebooksFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([Notebook].self, from: data)
        } catch {
            throw PageStoreError.failedToLoadNotebooks(reason: error.localizedDescription)
        }
    }

    public func saveNotebooks(_ notebooks: [Notebook]) throws {
        lock.lock()
        defer { lock.unlock() }

        do {
            try ensureDirectoriesExist()
            let data = try encoder.encode(notebooks)
            try data.write(to: notebooksFileURL, options: [.atomic])
        } catch {
            throw PageStoreError.failedToSaveNotebooks(reason: error.localizedDescription)
        }
    }

    public func loadDrawingData(for pageID: UUID) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }

        let url = drawingFileURL(for: pageID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            return try Data(contentsOf: url)
        } catch {
            throw PageStoreError.failedToLoadDrawing(pageID: pageID, reason: error.localizedDescription)
        }
    }

    public func saveDrawingData(_ data: Data, for pageID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        do {
            try ensureDirectoriesExist()
            let url = drawingFileURL(for: pageID)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw PageStoreError.failedToSaveDrawing(pageID: pageID, reason: error.localizedDescription)
        }
    }

    public func deleteDrawingData(for pageIDs: [UUID]) throws {
        lock.lock()
        defer { lock.unlock() }

        for pageID in pageIDs {
            let url = drawingFileURL(for: pageID)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw PageStoreError.failedToDeleteDrawing(pageID: pageID, reason: error.localizedDescription)
            }
        }
    }

    public func loadAssetData(for assetID: UUID) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }

        let url = assetFileURL(for: assetID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            return try Data(contentsOf: url)
        } catch {
            throw PageStoreError.failedToLoadAsset(assetID: assetID, reason: error.localizedDescription)
        }
    }

    public func saveAssetData(_ data: Data, for assetID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        do {
            try ensureDirectoriesExist()
            let url = assetFileURL(for: assetID)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw PageStoreError.failedToSaveAsset(assetID: assetID, reason: error.localizedDescription)
        }
    }

    public func deleteAssetData(for assetIDs: [UUID]) throws {
        lock.lock()
        defer { lock.unlock() }

        for assetID in assetIDs {
            let url = assetFileURL(for: assetID)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw PageStoreError.failedToDeleteAsset(assetID: assetID, reason: error.localizedDescription)
            }
        }
    }

    public func loadShapeLibraryItems(for notebookID: UUID) throws -> [ShapeLibraryItem] {
        lock.lock()
        defer { lock.unlock() }

        let url = shapeLibraryFileURL(for: notebookID)
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([ShapeLibraryItem].self, from: data)
        } catch {
            throw PageStoreError.failedToLoadShapeLibrary(notebookID: notebookID, reason: error.localizedDescription)
        }
    }

    public func saveShapeLibraryItem(_ item: ShapeLibraryItem, previewPNGData: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        do {
            try ensureDirectoriesExist()

            // 1. Save transparent PNG preview
            let previewURL = shapePreviewFileURL(for: item.id)
            try previewPNGData.write(to: previewURL, options: [.atomic])

            // 2. Update notebook's shape library JSON list
            let libraryURL = shapeLibraryFileURL(for: item.notebookID)
            var items: [ShapeLibraryItem] = []
            if fileManager.fileExists(atPath: libraryURL.path) {
                let existingData = try Data(contentsOf: libraryURL)
                items = (try? decoder.decode([ShapeLibraryItem].self, from: existingData)) ?? []
            }
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = item
            } else {
                items.insert(item, at: 0)
            }
            let data = try encoder.encode(items)
            try data.write(to: libraryURL, options: [.atomic])
        } catch {
            throw PageStoreError.failedToSaveShapeLibraryItem(itemID: item.id, reason: error.localizedDescription)
        }
    }

    public func deleteShapeLibraryItem(id itemID: UUID, notebookID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        do {
            // 1. Remove preview file
            let previewURL = shapePreviewFileURL(for: itemID)
            if fileManager.fileExists(atPath: previewURL.path) {
                try? fileManager.removeItem(at: previewURL)
            }

            // 2. Remove from notebook's shape library JSON list
            let libraryURL = shapeLibraryFileURL(for: notebookID)
            if fileManager.fileExists(atPath: libraryURL.path) {
                let existingData = try Data(contentsOf: libraryURL)
                var items = (try? decoder.decode([ShapeLibraryItem].self, from: existingData)) ?? []
                items.removeAll { $0.id == itemID }
                let data = try encoder.encode(items)
                try data.write(to: libraryURL, options: [.atomic])
            }
        } catch {
            throw PageStoreError.failedToDeleteShapeLibraryItem(itemID: itemID, reason: error.localizedDescription)
        }
    }

    public func loadShapeLibraryPreview(for itemID: UUID) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }

        let url = shapePreviewFileURL(for: itemID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }
}
