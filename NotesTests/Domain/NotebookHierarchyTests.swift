//
//  NotebookHierarchyTests.swift
//  NotesTests
//
//  Responsibility: Unit tests for Domain models (`Notebook`, `NoteSection`, `Page`, `PaperType`).
//

import Foundation
import Testing
@testable import Notes

@Suite("Domain — Notebook, Section, and Page Hierarchy")
struct NotebookHierarchyTests {

    @Test("Page resolves effective paper type from override or notebook default")
    func pageEffectivePaperType() {
        var page = Page(title: "Lecture 1", paperTypeOverride: nil)
        #expect(page.effectivePaperType(notebookDefault: .lined) == .lined)
        #expect(page.effectivePaperType(notebookDefault: .squared) == .squared)

        page.setPaperTypeOverride(.blank)
        #expect(page.effectivePaperType(notebookDefault: .lined) == .blank)

        page.setPaperTypeOverride(nil)
        #expect(page.effectivePaperType(notebookDefault: .squared) == .squared)
    }

    @Test("Empty or whitespace titles are sanitized to non-empty defaults")
    func titleSanitization() {
        let notebook = Notebook(title: "   \n ")
        let section = NoteSection(title: "")
        let page = Page(title: "   ")

        #expect(notebook.title == "Untitled Notebook")
        #expect(section.title == "Untitled Section")
        #expect(page.title == "Untitled Page")
    }

    @Test("Adding a page below a specific page inserts immediately after it and preserves UUIDs")
    func insertPageBelowTarget() {
        var section = NoteSection(title: "Circuit Analysis")
        let first = section.addPage(title: "Page A")
        let second = section.addPage(title: "Page B", afterPageID: first.id)
        let middle = section.addPage(title: "Page A.5", afterPageID: first.id)

        #expect(section.pages.map(\.id) == [first.id, middle.id, second.id])
        #expect(section.pages.map(\.title) == ["Page A", "Page A.5", "Page B"])
        #expect(middle.paperTypeOverride == nil)
    }

    @Test("Reordering sections and pages preserves permanent UUIDs")
    func reorderingPreservesUUIDs() {
        var notebook = Notebook(title: "Engineering Maths", defaultPaperType: .squared)
        let sec1 = notebook.addSection(title: "Linear Algebra")
        let sec2 = notebook.addSection(title: "Differential Equations")
        let sec3 = notebook.addSection(title: "Fourier Transform")

        // Move first section to the end
        notebook.moveSections(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(notebook.sections.map(\.id) == [sec2.id, sec3.id, sec1.id])
    }

    @Test("Deleting unknown section or page ID is a safe no-op")
    func deletingUnknownIDsIsSafe() {
        var notebook = Notebook(title: "Verification Plan")
        let section = notebook.addSection(title: "PCIe")
        #expect(notebook.deleteSection(id: UUID()) == nil)
        #expect(notebook.sections.count == 1)

        var mutableSection = section
        #expect(mutableSection.deletePage(id: UUID()) == nil)
        #expect(mutableSection.pages.count == 1)
    }
}
