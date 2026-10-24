//
//  Page.swift
//  Notes
//
//  Responsibility: Value type representing a single page's metadata inside a Section.
//  Drawing data (PKDrawing bytes) is stored separately by UUID via PageStore so metadata stays lightweight and sync-ready.
//  Dependencies: Foundation, PaperType.
//  Errors: Validation normalizes empty titles to "Untitled Page".
//  Tested in: NotesTests/Domain/NotebookHierarchyTests.swift
//

import Foundation

public struct Page: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    /// Optional per-page override. When `nil`, the page inherits its parent `Notebook.defaultPaperType`.
    public var paperTypeOverride: PaperType?
    /// Placed objects on this page (Basic Shapes, Images, Library/Stroke objects). Defaults to `[]` when decoding v1a files.
    public var objects: [PageObject]
    public let createdAt: Date
    public var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case paperTypeOverride
        case objects
        case createdAt
        case updatedAt
    }

    public init(
        id: UUID = UUID(),
        title: String = "Untitled Page",
        paperTypeOverride: PaperType? = nil,
        objects: [PageObject] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = Self.sanitizedTitle(title)
        self.paperTypeOverride = paperTypeOverride
        self.objects = objects
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        let rawTitle = try container.decode(String.self, forKey: .title)
        self.title = Self.sanitizedTitle(rawTitle)
        self.paperTypeOverride = try container.decodeIfPresent(PaperType.self, forKey: .paperTypeOverride)
        self.objects = try container.decodeIfPresent([PageObject].self, forKey: .objects) ?? []
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// Resolves the effective paper type for rendering, falling back to the notebook's default when not overridden.
    public func effectivePaperType(notebookDefault: PaperType) -> PaperType {
        paperTypeOverride ?? notebookDefault
    }

    public mutating func rename(to newTitle: String, now: Date = Date()) {
        self.title = Self.sanitizedTitle(newTitle)
        self.updatedAt = now
    }

    public mutating func setPaperTypeOverride(_ overrideType: PaperType?, now: Date = Date()) {
        self.paperTypeOverride = overrideType
        self.updatedAt = now
    }

    public mutating func addObject(_ object: PageObject, now: Date = Date()) {
        var placed = object
        if placed.zIndex == 0, let maxZ = objects.map(\.zIndex).max() {
            placed.zIndex = maxZ + 1
        }
        objects.append(placed)
        updatedAt = now
    }

    public mutating func updateObject(_ updated: PageObject, now: Date = Date()) {
        guard let index = objects.firstIndex(where: { $0.id == updated.id }) else { return }
        objects[index] = updated
        updatedAt = now
    }

    @discardableResult
    public mutating func deleteObject(id: UUID, now: Date = Date()) -> PageObject? {
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = objects.remove(at: index)
        updatedAt = now
        return removed
    }

    public mutating func setObjects(_ newObjects: [PageObject], now: Date = Date()) {
        objects = newObjects
        updatedAt = now
    }

    /// Returns all image `assetID`s referenced by objects on this page.
    public var referencedImageAssetIDs: [UUID] {
        objects.compactMap { obj in
            if case .image(let assetID) = obj.kind {
                return assetID
            }
            return nil
        }
    }

    public static func sanitizedTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Page" : trimmed
    }
}
