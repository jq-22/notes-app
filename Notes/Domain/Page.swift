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
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "Untitled Page",
        paperTypeOverride: PaperType? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = Self.sanitizedTitle(title)
        self.paperTypeOverride = paperTypeOverride
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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

    public static func sanitizedTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Page" : trimmed
    }
}
