//
//  PageStore.swift
//  Notes
//
//  Responsibility: Protocol boundary between Domain/Features and storage.
//  Separates metadata (`[Notebook]`) from heavy drawing payloads (`Data` per Page UUID) so saving ink or reordering pages never rewrites everything unnecessarily, and future sync can diff metadata independently.
//  Dependencies: Foundation, Domain.
//  Errors: Throws `PageStoreError` with user-presentable `LocalizedError` descriptions so failures are never silently swallowed.
//  Tested in: NotesTests/Persistence/FilePageStoreTests.swift
//

import Foundation

public enum PageStoreError: LocalizedError, Equatable, Sendable {
    case failedToLoadNotebooks(reason: String)
    case failedToSaveNotebooks(reason: String)
    case failedToLoadDrawing(pageID: UUID, reason: String)
    case failedToSaveDrawing(pageID: UUID, reason: String)
    case failedToDeleteDrawing(pageID: UUID, reason: String)
    case failedToLoadAsset(assetID: UUID, reason: String)
    case failedToSaveAsset(assetID: UUID, reason: String)
    case failedToDeleteAsset(assetID: UUID, reason: String)
    case failedToLoadShapeLibrary(notebookID: UUID, reason: String)
    case failedToSaveShapeLibraryItem(itemID: UUID, reason: String)
    case failedToDeleteShapeLibraryItem(itemID: UUID, reason: String)

    public var errorDescription: String? {
        switch self {
        case .failedToLoadNotebooks(let reason):
            return "Could not load notebooks: \(reason)"
        case .failedToSaveNotebooks(let reason):
            return "Could not save notebooks: \(reason)"
        case .failedToLoadDrawing(_, let reason):
            return "Could not load page drawing: \(reason)"
        case .failedToSaveDrawing(_, let reason):
            return "Could not save page drawing: \(reason)"
        case .failedToDeleteDrawing(_, let reason):
            return "Could not clean up deleted page data: \(reason)"
        case .failedToLoadAsset(_, let reason):
            return "Could not load image asset: \(reason)"
        case .failedToSaveAsset(_, let reason):
            return "Could not save image asset: \(reason)"
        case .failedToDeleteAsset(_, let reason):
            return "Could not delete image asset: \(reason)"
        case .failedToLoadShapeLibrary(_, let reason):
            return "Could not load shape library: \(reason)"
        case .failedToSaveShapeLibraryItem(_, let reason):
            return "Could not save shape to library: \(reason)"
        case .failedToDeleteShapeLibraryItem(_, let reason):
            return "Could not delete shape from library: \(reason)"
        }
    }
}

public protocol PageStore: Sendable {
    /// Loads the ordered list of notebooks and their section/page hierarchy metadata.
    /// Returns an empty array on first launch when no file exists yet.
    func loadNotebooks() throws -> [Notebook]

    /// Atomically persists the full ordered list of notebook metadata.
    func saveNotebooks(_ notebooks: [Notebook]) throws

    /// Loads raw `PKDrawing` data for a given page UUID, or returns `nil` if no drawing has been saved for that page yet.
    func loadDrawingData(for pageID: UUID) throws -> Data?

    /// Atomically saves raw `PKDrawing` data for a given page UUID.
    func saveDrawingData(_ data: Data, for pageID: UUID) throws

    /// Removes stored drawing data for the given page UUIDs (if present).
    func deleteDrawingData(for pageIDs: [UUID]) throws

    /// Loads binary asset data (e.g. PNG/JPEG image) for a given asset UUID, or returns `nil` if not found.
    func loadAssetData(for assetID: UUID) throws -> Data?

    /// Atomically saves binary asset data for a given asset UUID.
    func saveAssetData(_ data: Data, for assetID: UUID) throws

    /// Removes stored binary asset data for the given asset UUIDs (if present).
    func deleteAssetData(for assetIDs: [UUID]) throws

    /// Loads all saved ShapeLibraryItem metadata for a given notebook UUID.
    func loadShapeLibraryItems(for notebookID: UUID) throws -> [ShapeLibraryItem]

    /// Atomically saves a ShapeLibraryItem and its transparent preview PNG image.
    func saveShapeLibraryItem(_ item: ShapeLibraryItem, previewPNGData: Data) throws

    /// Deletes a ShapeLibraryItem and its preview image from a notebook's library.
    func deleteShapeLibraryItem(id itemID: UUID, notebookID: UUID) throws

    /// Loads the transparent PNG preview image data for a ShapeLibraryItem.
    func loadShapeLibraryPreview(for itemID: UUID) throws -> Data?
}

public extension PageStore {
    func loadAssetData(for assetID: UUID) throws -> Data? { nil }
    func saveAssetData(_ data: Data, for assetID: UUID) throws {}
    func deleteAssetData(for assetIDs: [UUID]) throws {}
    func loadShapeLibraryItems(for notebookID: UUID) throws -> [ShapeLibraryItem] { [] }
    func saveShapeLibraryItem(_ item: ShapeLibraryItem, previewPNGData: Data) throws {}
    func deleteShapeLibraryItem(id itemID: UUID, notebookID: UUID) throws {}
    func loadShapeLibraryPreview(for itemID: UUID) throws -> Data? { nil }
}
