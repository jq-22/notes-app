//
//  NoteSection.swift
//  Notes
//
//  Responsibility: Value type representing a Section inside a Notebook, holding an ordered array of Pages.
//  Named `NoteSection` to avoid shadowing SwiftUI's `Section` view type.
//  Dependencies: Foundation, Page.
//  Errors: Out-of-bounds or unknown UUID mutations are no-ops or return nil safely.
//  Tested in: NotesTests/Domain/NotebookHierarchyTests.swift
//

import Foundation

public struct NoteSection: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var pages: [Page]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "Untitled Section",
        pages: [Page] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = Self.sanitizedTitle(title)
        self.pages = pages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func rename(to newTitle: String, now: Date = Date()) {
        self.title = Self.sanitizedTitle(newTitle)
        self.updatedAt = now
    }

    /// Inserts a new page immediately below `afterPageID`.
    /// If `afterPageID` is `nil` or not found in `pages`, appends the page to the end.
    /// The new page starts with `paperTypeOverride = nil` so it inherits the notebook default.
    @discardableResult
    public mutating func addPage(
        title: String? = nil,
        afterPageID: UUID? = nil,
        now: Date = Date()
    ) -> Page {
        let nextNumber = pages.count + 1
        let resolvedTitle = title ?? "Page \(nextNumber)"
        let page = Page(
            title: resolvedTitle,
            paperTypeOverride: nil,
            createdAt: now,
            updatedAt: now
        )

        if let afterPageID, let index = pages.firstIndex(where: { $0.id == afterPageID }) {
            pages.insert(page, at: index + 1)
        } else {
            pages.append(page)
        }
        updatedAt = now
        return page
    }

    @discardableResult
    public mutating func deletePage(id pageID: UUID, now: Date = Date()) -> Page? {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else {
            return nil
        }
        let removed = pages.remove(at: index)
        updatedAt = now
        return removed
    }

    public mutating func movePages(fromOffsets source: IndexSet, toOffset destination: Int, now: Date = Date()) {
        pages.moveElements(fromOffsets: source, toOffset: destination)
        updatedAt = now
    }

    public static func sanitizedTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Section" : trimmed
    }
}

extension RangeReplaceableCollection {
    /// Pure Foundation equivalent of SwiftUI's `Array.move(fromOffsets:toOffset:)` so `Domain` never needs to import SwiftUI.
    public mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty else { return }
        var elements = Array(self)
        let moving = source.map { elements[$0] }
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) {
            elements.remove(at: index)
        }
        let clampedDestination = Swift.max(0, Swift.min(adjustedDestination, elements.count))
        elements.insert(contentsOf: moving, at: clampedDestination)
        self = Self(elements)
    }
}
