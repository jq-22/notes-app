//
//  TextBoxEditorView.swift
//  Notes
//
//  Responsibility: Shared typography/layout helpers, pure SwiftUI `TextBoxContentView` (for unfocused canvas & thumbnails),
//  and `TextBoxEditorView` (`UIViewRepresentable` wrapping `UITextView` + explicit `UIScribbleInteraction`) for inline editing
//  with iPadOS Apple Pencil Scribble when a `.textBox` `PageObject` is selected.
//  Dependencies: SwiftUI, UIKit, Domain (PageObject, TextBoxStyle, TextBoxAlignment, InkColorPreset), DesignSystem (Theme).
//

import SwiftUI
import UIKit

// MARK: - Shared Layout & Typography Helpers (Canvas, Editor, Thumbnail, PDF)

public enum TextBoxLayout {
    public static let textPadding: CGFloat = 10.0
    public static let editorOuterInset: CGFloat = 8.0
    public static let editorInnerInset: CGFloat = 2.0
    public static let cornerRadius: CGFloat = Theme.CornerRadius.floatingPill
    public static let borderWidth: CGFloat = 1.5

    /// Expands a `.textBox` along its rotated local vertical axis (`height`) so the rotated top-left corner remains anchored
    /// and `width` is preserved at any `rotation` angle.
    public static func autoExpandedTextBox(_ object: PageObject, fittingBoxHeight: CGFloat) -> PageObject {
        guard fittingBoxHeight > object.height + 1.0 else { return object }
        let deltaH = fittingBoxHeight - object.height
        let pageDelta = CGSize(
            width: -deltaH * sin(object.rotation),
            height: deltaH * cos(object.rotation)
        )
        return object.resized(corner: .bottomRight, pageDelta: pageDelta)
    }
}

/// Coordinates flushing or discarding uncommitted inline `TextBoxEditorView` edits across Delete, Style, Handle Drag, Undo/Redo, and Page Switch transitions.
@MainActor
public final class TextBoxUndoBridge {
    public private(set) var activePageID: UUID?
    public private(set) var activeObjectID: UUID?
    public private(set) var hasUncommittedEdit: Bool = false
    private var flushHandler: (() -> Void)?
    private var discardHandler: (() -> Void)?
    public var onUncommittedEditStateChanged: (() -> Void)?

    public init() {}

    func register(
        pageID: UUID,
        objectID: UUID,
        flush: @escaping () -> Void,
        discard: @escaping () -> Void
    ) {
        activePageID = pageID
        activeObjectID = objectID
        flushHandler = flush
        discardHandler = discard
    }

    func unregister(objectID: UUID) {
        guard activeObjectID == objectID else { return }
        activePageID = nil
        activeObjectID = nil
        flushHandler = nil
        discardHandler = nil
        setHasUncommittedEdit(false)
    }

    func setHasUncommittedEdit(_ newValue: Bool) {
        guard hasUncommittedEdit != newValue else { return }
        hasUncommittedEdit = newValue
        onUncommittedEditStateChanged?()
    }

    public func flushPendingEditIfNeeded() {
        flushHandler?()
    }

    public func discardPendingEditIfNeeded() {
        discardHandler?()
    }
}

public extension TextBoxAlignment {
    var swiftUITextAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var swiftUIFrameAlignment: Alignment {
        switch self {
        case .leading: return .topLeading
        case .center: return .top
        case .trailing: return .topTrailing
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }
}

public extension TextBoxStyle {
    /// Resolves the UIKit font matching `fontSize`, `isBold`, and `isItalic` (shared with `PagePDFExporter` for WYSIWYG fidelity).
    func resolvedUIFont() -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: fontSize, weight: isBold ? .bold : .regular)
        if isItalic {
            var traits = baseFont.fontDescriptor.symbolicTraits
            traits.insert(.traitItalic)
            if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) {
                return UIFont(descriptor: descriptor, size: fontSize)
            }
            if !isBold {
                return UIFont.italicSystemFont(ofSize: fontSize)
            }
        }
        return baseFont
    }

    /// Resolves adaptive SwiftUI text colour for the live canvas: when transparent (`backgroundColor == nil`) and using default `.black`,
    /// adapts via `Color.primary` so text remains readable in both Light and Dark Mode; explicit card fills preserve fixed preset contrast.
    func resolvedCanvasTextColor() -> Color {
        if backgroundColor == nil && textColor == .black {
            return Color.primary
        }
        return textColor.swiftUIColor
    }

    /// Resolves adaptive UIKit text colour for `UITextView` matching `resolvedCanvasTextColor()`.
    func resolvedCanvasUITextColor() -> UIColor {
        if backgroundColor == nil && textColor == .black {
            return UIColor.label
        }
        return textColor.uiColor(opacity: 1.0)
    }
}

// MARK: - Unfocused / Thumbnail Pure SwiftUI Card Renderer

public struct TextBoxContentView: View {
    public let text: String
    public let style: TextBoxStyle
    public let isSelected: Bool

    public init(text: String, style: TextBoxStyle, isSelected: Bool = false) {
        self.text = text
        self.style = style
        self.isSelected = isSelected
    }

    private var showsDiscoverableEmptyOutline: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && style.backgroundColor == nil
            && style.borderColor == nil
            && !isSelected
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TextBoxLayout.cornerRadius, style: .continuous)
                .fill(style.backgroundColor?.swiftUIColor ?? Color.clear)

            if let borderColor = style.borderColor {
                RoundedRectangle(cornerRadius: TextBoxLayout.cornerRadius, style: .continuous)
                    .strokeBorder(borderColor.swiftUIColor, lineWidth: TextBoxLayout.borderWidth)
            } else if showsDiscoverableEmptyOutline {
                RoundedRectangle(cornerRadius: TextBoxLayout.cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(0.22),
                        style: StrokeStyle(lineWidth: 1.0, dash: [4, 3])
                    )
            }

            if text.isEmpty && isSelected {
                Text("Write or type…")
                    .font(Font(style.resolvedUIFont()))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .multilineTextAlignment(style.alignment.swiftUITextAlignment)
                    .padding(TextBoxLayout.textPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.alignment.swiftUIFrameAlignment)
            } else {
                Text(text)
                    .font(Font(style.resolvedUIFont()))
                    .foregroundStyle(style.resolvedCanvasTextColor())
                    .multilineTextAlignment(style.alignment.swiftUITextAlignment)
                    .padding(TextBoxLayout.textPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.alignment.swiftUIFrameAlignment)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: TextBoxLayout.cornerRadius, style: .continuous))
    }
}

// MARK: - Inline UITextView + Apple Pencil Scribble Editor (Mounted Only When Focused)

public struct TextBoxEditorView: UIViewRepresentable {
    public let pageID: UUID
    public let object: PageObject
    public let allObjects: [PageObject]
    public let text: String
    public let style: TextBoxStyle
    public let undoBridge: TextBoxUndoBridge?
    public let onLiveObjectUpdate: (PageObject) -> Void
    public let onCommitObjectsChange: ([PageObject], [PageObject]) -> Void
    public let onCommitTextBoxEdit: ((UUID, UUID, [PageObject], [PageObject]) -> Void)?

    public init(
        pageID: UUID = UUID(),
        object: PageObject,
        allObjects: [PageObject],
        text: String,
        style: TextBoxStyle,
        undoBridge: TextBoxUndoBridge? = nil,
        onLiveObjectUpdate: @escaping (PageObject) -> Void,
        onCommitObjectsChange: @escaping ([PageObject], [PageObject]) -> Void,
        onCommitTextBoxEdit: ((UUID, UUID, [PageObject], [PageObject]) -> Void)? = nil
    ) {
        self.pageID = pageID
        self.object = object
        self.allObjects = allObjects
        self.text = text
        self.style = style
        self.undoBridge = undoBridge
        self.onLiveObjectUpdate = onLiveObjectUpdate
        self.onCommitObjectsChange = onCommitObjectsChange
        self.onCommitTextBoxEdit = onCommitTextBoxEdit
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.clipsToBounds = true
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = UIEdgeInsets(
            top: TextBoxLayout.editorInnerInset,
            left: TextBoxLayout.editorInnerInset,
            bottom: TextBoxLayout.editorInnerInset,
            right: TextBoxLayout.editorInnerInset
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        textView.delegate = context.coordinator

        let scribbleInteraction = UIScribbleInteraction(delegate: context.coordinator)
        textView.addInteraction(scribbleInteraction)

        applyAppearance(to: textView, text: text, style: style)
        context.coordinator.registerWithUndoBridge()

        DispatchQueue.main.async {
            guard !context.coordinator.didRequestInitialFocus else { return }
            context.coordinator.didRequestInitialFocus = true
            if textView.window != nil && !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        }

        return textView
    }

    public func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.latestObject = object
        context.coordinator.latestAllObjects = allObjects
        context.coordinator.registerWithUndoBridge()

        if textView.markedTextRange == nil && textView.text != text {
            let selectedRange = textView.selectedRange
            textView.text = text
            let maxOffset = (text as NSString).length
            let clampedLocation = Swift.min(selectedRange.location, maxOffset)
            let clampedLength = Swift.min(selectedRange.length, maxOffset - clampedLocation)
            textView.selectedRange = NSRange(location: clampedLocation, length: clampedLength)
            textView.undoManager?.removeAllActions()
            // External text replacement (e.g. Undo/Redo) resets uncommitted snapshot
            context.coordinator.discardPendingTextEdit()
        }

        applyAppearance(to: textView, text: nil, style: style)

        if !context.coordinator.didRequestInitialFocus && textView.window != nil && !textView.isFirstResponder {
            context.coordinator.didRequestInitialFocus = true
            DispatchQueue.main.async {
                if textView.window != nil && !textView.isFirstResponder {
                    textView.becomeFirstResponder()
                }
            }
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    public static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        coordinator.commitPendingTextEditIfNeeded()
        coordinator.parent.undoBridge?.unregister(objectID: coordinator.latestObject.id)
        if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    private func applyAppearance(to textView: UITextView, text: String?, style: TextBoxStyle) {
        if let text {
            textView.text = text
        }
        let targetFont = style.resolvedUIFont()
        if textView.font != targetFont {
            textView.font = targetFont
        }
        let targetColor = style.resolvedCanvasUITextColor()
        if textView.textColor != targetColor {
            textView.textColor = targetColor
        }
        let targetAlignment = style.alignment.nsTextAlignment
        if textView.textAlignment != targetAlignment {
            textView.textAlignment = targetAlignment
        }
    }

    @MainActor
    public final class Coordinator: NSObject, UITextViewDelegate, UIScribbleInteractionDelegate {
        var parent: TextBoxEditorView
        let editingPageID: UUID
        var latestObject: PageObject
        var latestAllObjects: [PageObject]
        var uncommittedBeforeObjects: [PageObject]?
        var didRequestInitialFocus = false
        var isScribbleActive = false

        init(parent: TextBoxEditorView) {
            self.parent = parent
            self.editingPageID = parent.pageID
            self.latestObject = parent.object
            self.latestAllObjects = parent.allObjects
        }

        func registerWithUndoBridge() {
            parent.undoBridge?.register(
                pageID: editingPageID,
                objectID: latestObject.id,
                flush: { [weak self] in
                    self?.commitPendingTextEditIfNeeded()
                },
                discard: { [weak self] in
                    self?.discardPendingTextEdit()
                }
            )
        }

        public func textViewDidChange(_ textView: UITextView) {
            if uncommittedBeforeObjects == nil {
                uncommittedBeforeObjects = latestAllObjects
                parent.undoBridge?.setHasUncommittedEdit(true)
            }
            let newText = textView.text ?? ""
            var updated = latestObject.withText(newText)

            let innerWidth = Swift.max(1.0, updated.width - (TextBoxLayout.editorOuterInset * 2.0))
            let fittingTextViewHeight = ceil(
                textView.sizeThatFits(CGSize(width: innerWidth, height: .greatestFiniteMagnitude)).height
            )
            let fittingBoxHeight = fittingTextViewHeight + (TextBoxLayout.editorOuterInset * 2.0)
            updated = TextBoxLayout.autoExpandedTextBox(updated, fittingBoxHeight: fittingBoxHeight)

            latestObject = updated
            latestAllObjects = latestAllObjects.map { $0.id == updated.id ? updated : $0 }
            parent.onLiveObjectUpdate(updated)
        }

        public func textViewDidEndEditing(_ textView: UITextView) {
            commitPendingTextEditIfNeeded()
        }

        public func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
            true
        }

        public func scribbleInteractionShouldDelayFocus(_ interaction: UIScribbleInteraction) -> Bool {
            false
        }

        public func scribbleInteractionWillBeginWriting(_ interaction: UIScribbleInteraction) {
            isScribbleActive = true
        }

        public func scribbleInteractionDidFinishWriting(_ interaction: UIScribbleInteraction) {
            isScribbleActive = false
            commitPendingTextEditIfNeeded()
        }

        func commitPendingTextEditIfNeeded() {
            guard let before = uncommittedBeforeObjects else { return }
            uncommittedBeforeObjects = nil
            parent.undoBridge?.setHasUncommittedEdit(false)
            let after = latestAllObjects
            if before != after {
                if let onCommitTextBoxEdit = parent.onCommitTextBoxEdit {
                    onCommitTextBoxEdit(editingPageID, latestObject.id, before, after)
                } else {
                    parent.onCommitObjectsChange(before, after)
                }
            }
        }

        func discardPendingTextEdit() {
            uncommittedBeforeObjects = nil
            parent.undoBridge?.setHasUncommittedEdit(false)
        }
    }
}
