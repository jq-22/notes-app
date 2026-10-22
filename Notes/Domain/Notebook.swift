//
//  Notebook.swift
//  Notes
//
//  Responsibility: Root aggregate value type representing a Notebook containing ordered Sections and a default PaperType.
//  Every Notebook, NoteSection, and Page has a permanent UUID.
//  Dependencies: Foundation, NoteSection, Page, PaperType.
//  Errors: Mutations with unknown UUIDs are safe no-ops.
//  Tested in: NotesTests/Domain/NotebookHierarchyTests.swift
//

import Foundation

public struct Notebook: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var defaultPaperType: PaperType
    public var sections: [NoteSection]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "Untitled Notebook",
        defaultPaperType: PaperType = .lined,
        sections: [NoteSection] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = Self.sanitizedTitle(title)
        self.defaultPaperType = defaultPaperType
        self.sections = sections
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func rename(to newTitle: String, now: Date = Date()) {
        self.title = Self.sanitizedTitle(newTitle)
        self.updatedAt = now
    }

    public mutating func setDefaultPaperType(_ paperType: PaperType, now: Date = Date()) {
        self.defaultPaperType = paperType
        self.updatedAt = now
    }

    @discardableResult
    public mutating func addSection(title: String? = nil, now: Date = Date()) -> NoteSection {
        let nextNumber = sections.count + 1
        let resolvedTitle = title ?? "Section \(nextNumber)"
        let initialPage = Page(title: "Page 1", paperTypeOverride: nil, createdAt: now, updatedAt: now)
        let section = NoteSection(
            title: resolvedTitle,
            pages: [initialPage],
            createdAt: now,
            updatedAt: now
        )
        sections.append(section)
        updatedAt = now
        return section
    }

    @discardableResult
    public mutating func deleteSection(id sectionID: UUID, now: Date = Date()) -> NoteSection? {
        guard let index = sections.firstIndex(where: { $0.id == sectionID }) else {
            return nil
        }
        let removed = sections.remove(at: index)
        updatedAt = now
        return removed
    }

    public mutating func moveSections(fromOffsets source: IndexSet, toOffset destination: Int, now: Date = Date()) {
        sections.moveElements(fromOffsets: source, toOffset: destination)
        updatedAt = now
    }

    public static func sanitizedTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Notebook" : trimmed
    }
}
