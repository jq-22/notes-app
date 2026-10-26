//
//  ShapeLibraryItem.swift
//  Notes
//
//  Responsibility: Pure value type representing a saved shape in the Notebook Shape Library.
//  Stored as ink strokes (PKDrawing data representation) so it can be placed, resized, rotated, and recoloured,
//  plus metadata for label, dimensions, and parent notebook.
//  Dependencies: Foundation, CoreGraphics.
//  Tested in: NotesTests/Domain/PageObjectTests.swift
//

import CoreGraphics
import Foundation

public struct ShapeLibraryItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let notebookID: UUID
    public var label: String
    public let strokeDrawingData: Data
    public let sourceBoundsWidth: CGFloat
    public let sourceBoundsHeight: CGFloat
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        notebookID: UUID,
        label: String,
        strokeDrawingData: Data,
        sourceBoundsWidth: CGFloat,
        sourceBoundsHeight: CGFloat,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.notebookID = notebookID
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = trimmed.isEmpty ? "Saved Shape" : trimmed
        self.strokeDrawingData = strokeDrawingData
        self.sourceBoundsWidth = Swift.max(PageObject.minimumDimension, sourceBoundsWidth)
        self.sourceBoundsHeight = Swift.max(PageObject.minimumDimension, sourceBoundsHeight)
        self.createdAt = createdAt
    }
}
