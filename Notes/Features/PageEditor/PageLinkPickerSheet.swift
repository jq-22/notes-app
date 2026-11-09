//
//  PageLinkPickerSheet.swift
//  Notes
//
//  Responsibility: Searchable picker sheet allowing the user to select any existing page
//  across all notebooks and sections to insert a permanent UUID-based Page-to-Page link badge.
//  Dependencies: SwiftUI, Domain (Notebook, NoteSection, Page), LibraryViewModel.
//

import SwiftUI

public struct PageLinkPickerSheet: View {
    public let notebooks: [Notebook]
    public let currentPageID: UUID
    public let onSelectPage: (Page, NoteSection, Notebook) -> Void
    public let onDismiss: () -> Void

    @State private var searchText: String = ""

    public init(
        notebooks: [Notebook],
        currentPageID: UUID,
        onSelectPage: @escaping (Page, NoteSection, Notebook) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.notebooks = notebooks
        self.currentPageID = currentPageID
        self.onSelectPage = onSelectPage
        self.onDismiss = onDismiss
    }

    private struct PageEntry: Identifiable {
        let page: Page
        let section: NoteSection
        let notebook: Notebook

        var id: UUID { page.id }
    }

    private var allEntries: [PageEntry] {
        var result: [PageEntry] = []
        for nb in notebooks {
            for sec in nb.sections {
                for pg in sec.pages where pg.id != currentPageID {
                    result.append(PageEntry(page: pg, section: sec, notebook: nb))
                }
            }
        }
        return result
    }

    private var filteredEntries: [PageEntry] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allEntries }
        return allEntries.filter { entry in
            entry.page.title.localizedCaseInsensitiveContains(trimmed) ||
            entry.section.title.localizedCaseInsensitiveContains(trimmed) ||
            entry.notebook.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Other Pages" : "No Matching Pages",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(searchText.isEmpty ? "Create another page first to link between pages." : "No pages match '\(searchText)'.")
                    )
                } else {
                    List {
                        ForEach(filteredEntries) { entry in
                            Button {
                                onSelectPage(entry.page, entry.section, entry.notebook)
                                onDismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text")
                                        .font(.title3)
                                        .foregroundStyle(Color.accentColor)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.page.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)

                                        HStack(spacing: 4) {
                                            Text(entry.notebook.title)
                                            Text("›")
                                            Text(entry.section.title)
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "link.badge.plus")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search pages across notebooks…")
            .navigationTitle("Link to Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
        }
        .frame(minWidth: 360, idealWidth: 460, minHeight: 400, idealHeight: 520)
    }
}
