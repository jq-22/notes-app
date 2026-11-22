//
//  PageObjectsOverlayView.swift
//  Notes
//
//  Responsibility: Renders all `PageObject` items on an A4 page (Basic Shapes, Images, and Stroke/Library objects)
//  and, when interactive, provides the unified selection chrome specified in SPEC.md:
//    - Rectangle border (and interior drag) to move
//    - Four corner dots to resize
//    - Rotate handle sticking out above the top edge
//    - Compact floating bar for recolouring, duplicating, and deleting the selected object
//  Dependencies: SwiftUI, UIKit, PencilKit, Domain, DesignSystem.
//

import PencilKit
import SwiftUI
import UIKit

public struct PageObjectsOverlayView: View {
    public let pageID: UUID
    public let objects: [PageObject]
    public let selectedObjectID: UUID?
    public let isInteractive: Bool
    public let textBoxUndoBridge: TextBoxUndoBridge?
    public let assetDataProvider: (UUID) -> Data?
    public let onSelectObject: (UUID?) -> Void
    public let onUpdateObjectLive: (PageObject, Bool) -> Void
    public let onCommitObjectsChange: ([PageObject], [PageObject]) -> Void
    public let onCommitTextBoxEdit: ((UUID, UUID, [PageObject], [PageObject]) -> Void)?
    public let onCopyObject: (UUID) -> Void
    public let onDuplicateObject: (UUID) -> Void
    public let onDeleteObject: (UUID) -> Void
    public let onNavigateToPage: ((UUID, UUID, UUID) -> Void)?

    @State private var dragStartObject: PageObject?
    @State private var dragStartAllObjects: [PageObject]?
    @State private var isActivelyDraggingHandle: Bool = false
    @State private var lastDetentStep: Int = 0
    @State private var isTextColorPickerPresented: Bool = false
    @State private var isCardFillPickerPresented: Bool = false
    @State private var isCardBorderPickerPresented: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private static let coordinateSpaceName = "A4PageCoordinateSpace"
    private static let rotateHandleLength: CGFloat = 28.0
    private static let cornerDotDiameter: CGFloat = 13.0
    private static let cornerHitTargetSize: CGFloat = 34.0
    private static let tableHandleTouchTargetSize: CGFloat = 44.0
    private static let tableHandleCornerRadius: CGFloat = Theme.CornerRadius.tableHandle

    public init(
        pageID: UUID = UUID(),
        objects: [PageObject],
        selectedObjectID: UUID? = nil,
        isInteractive: Bool = false,
        textBoxUndoBridge: TextBoxUndoBridge? = nil,
        assetDataProvider: @escaping (UUID) -> Data?,
        onSelectObject: @escaping (UUID?) -> Void = { _ in },
        onUpdateObjectLive: @escaping (PageObject, Bool) -> Void = { _, _ in },
        onCommitObjectsChange: @escaping ([PageObject], [PageObject]) -> Void = { _, _ in },
        onCommitTextBoxEdit: ((UUID, UUID, [PageObject], [PageObject]) -> Void)? = nil,
        onCopyObject: @escaping (UUID) -> Void = { _ in },
        onDuplicateObject: @escaping (UUID) -> Void = { _ in },
        onDeleteObject: @escaping (UUID) -> Void = { _ in },
        onNavigateToPage: ((UUID, UUID, UUID) -> Void)? = nil
    ) {
        self.pageID = pageID
        self.objects = objects
        self.selectedObjectID = selectedObjectID
        self.isInteractive = isInteractive
        self.textBoxUndoBridge = textBoxUndoBridge
        self.assetDataProvider = assetDataProvider
        self.onSelectObject = onSelectObject
        self.onUpdateObjectLive = onUpdateObjectLive
        self.onCommitObjectsChange = onCommitObjectsChange
        self.onCommitTextBoxEdit = onCommitTextBoxEdit
        self.onCopyObject = onCopyObject
        self.onDuplicateObject = onDuplicateObject
        self.onDeleteObject = onDeleteObject
        self.onNavigateToPage = onNavigateToPage
    }

    private var sortedObjects: [PageObject] {
        objects.sorted { lhs, rhs in
            if lhs.zIndex == rhs.zIndex {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.zIndex < rhs.zIndex
        }
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if isInteractive {
                Color.clear
                    .frame(width: PageGeometry.a4Width, height: PageGeometry.a4Height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectObject(nil)
                    }
            }

            ForEach(sortedObjects) { object in
                let isSelected = isInteractive && (object.id == selectedObjectID)
                objectItemView(for: object, isSelected: isSelected)
            }
        }
        .frame(width: PageGeometry.a4Width, height: PageGeometry.a4Height, alignment: .topLeading)
        .coordinateSpace(name: Self.coordinateSpaceName)
        .onChange(of: selectedObjectID) { _, _ in
            isTextColorPickerPresented = false
            isCardFillPickerPresented = false
            isCardBorderPickerPresented = false
        }
    }

    @ViewBuilder
    private func objectItemView(for object: PageObject, isSelected: Bool) -> some View {
        ZStack {
            // 1. Visual content (or inline UITextView + Scribble editor for a selected .textBox)
            if case .textBox(let text, let style) = object.kind, isSelected {
                ZStack {
                    RoundedRectangle(cornerRadius: TextBoxLayout.cornerRadius, style: .continuous)
                        .fill(style.backgroundColor?.swiftUIColor ?? Color.clear)
                        .allowsHitTesting(false)

                    if let borderColor = style.borderColor {
                        RoundedRectangle(cornerRadius: TextBoxLayout.cornerRadius, style: .continuous)
                            .strokeBorder(borderColor.swiftUIColor, lineWidth: TextBoxLayout.borderWidth)
                            .allowsHitTesting(false)
                    }

                    if text.isEmpty {
                        Text("Write or type…")
                            .font(Font(style.resolvedUIFont()))
                            .foregroundStyle(Color.secondary.opacity(0.55))
                            .multilineTextAlignment(style.alignment.swiftUITextAlignment)
                            .padding(TextBoxLayout.textPadding)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.alignment.swiftUIFrameAlignment)
                            .allowsHitTesting(false)
                    }

                    TextBoxEditorView(
                        pageID: pageID,
                        object: object,
                        allObjects: objects,
                        text: text,
                        style: style,
                        undoBridge: textBoxUndoBridge,
                        onLiveObjectUpdate: { updated in
                            onUpdateObjectLive(updated, false)
                        },
                        onCommitObjectsChange: onCommitObjectsChange,
                        onCommitTextBoxEdit: onCommitTextBoxEdit
                    )
                    .padding(TextBoxLayout.editorOuterInset)
                    .id("\(pageID.uuidString)-\(object.id.uuidString)")
                }
                .clipShape(RoundedRectangle(cornerRadius: TextBoxLayout.cornerRadius, style: .continuous))
                .frame(width: object.width, height: object.height)
            } else if case .table(let table) = object.kind, isSelected && table.isTextMode {
                TableView(
                    table: table,
                    columnWidths: object.tableColumnWidths(),
                    rowHeights: object.tableRowHeights(),
                    isSelected: true,
                    onCellTextChange: { r, c, newText in
                        let updated = object.withTableCellText(row: r, column: c, text: newText)
                        onUpdateObjectLive(updated, false)
                    },
                    onCommitCellText: {
                        let before = objects
                        let updated = objects.first(where: { $0.id == object.id }) ?? object
                        let after = before.map { $0.id == updated.id ? updated : $0 }
                        if before != after {
                            onCommitObjectsChange(before, after)
                        }
                    }
                )
                .frame(width: object.width, height: object.height)
            } else {
                PageObjectContentView(object: object, assetDataProvider: assetDataProvider)
                    .frame(width: object.width, height: object.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if case .pageLink(let targetPageID, let targetSecID, let targetNbID, _) = object.kind, !isSelected {
                            onNavigateToPage?(targetPageID, targetSecID, targetNbID)
                            return
                        }
                        onSelectObject(object.id)
                    }
                    .gesture(
                        isInteractive ? moveGesture(for: object) : nil
                    )
            }

            // 2. Unified Selection Chrome: Rectangle border, 4 corner resize dots, and rotate handle sticking out
            if isSelected {
                selectionChrome(for: object)
            }
        }
        .frame(width: object.width, height: object.height)
        .rotationEffect(.radians(Double(object.rotation)))
        .position(x: object.center.x, y: object.center.y)
        .overlay(alignment: .topLeading) {
            if isSelected && !isActivelyDraggingHandle {
                floatingContextToolbar(for: object)
            }
        }
    }

    // MARK: - Selection Chrome (Border + 4 Corner Dots OR Line End-Bars + Rotate Handle)

    @ViewBuilder
    private func selectionChrome(for object: PageObject) -> some View {
        if object.usesLinearEndpointHandles {
            // Line & Arrow Chrome: Rotate handle in the middle + two end-bar lines at each end to lengthen/shorten
            ZStack {
                // Subtle center guide line
                Rectangle()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: object.width, height: 1.2)
                    .allowsHitTesting(false)

                // Rotate handle sticking out from the middle of the line/arrow
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 1.8)
                            .frame(width: 22, height: 22)
                        Image(systemName: "arrow.trianglehead.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: Self.cornerHitTargetSize, height: Self.cornerHitTargetSize)
                    .contentShape(Rectangle())
                    .gesture(rotateGesture(for: object))

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 1.8, height: Self.rotateHandleLength - 8)
                        .allowsHitTesting(false)
                }
                .offset(y: -(Self.rotateHandleLength * 0.5 + 8))

                // Left end-bar handle (.start)
                lineEndpointBarHandle(for: object, endpoint: .start)
                    .offset(x: -object.width * 0.5)

                // Right end-bar handle (.end)
                lineEndpointBarHandle(for: object, endpoint: .end)
                    .offset(x: object.width * 0.5)
            }
        } else {
            ZStack {
                // Rectangle border visual indicator
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.8)
                    .frame(width: object.width, height: object.height)
                    .allowsHitTesting(false)

                // For .textBox or .table in text mode, expose a 20pt perimeter border ring to move the card without blocking interior Scribble/selection
                if case .textBox = object.kind {
                    textBoxPerimeterMoveRing(for: object)
                } else if case .table(let table) = object.kind, table.isTextMode {
                    textBoxPerimeterMoveRing(for: object)
                }

                // Rotate handle sticking out above the top-center edge
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 1.8)
                            .frame(width: 22, height: 22)
                        Image(systemName: "arrow.trianglehead.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: Self.cornerHitTargetSize, height: Self.cornerHitTargetSize)
                    .contentShape(Rectangle())
                    .gesture(rotateGesture(for: object))

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 1.8, height: Self.rotateHandleLength - 11)
                        .allowsHitTesting(false)
                }
                .offset(y: -(object.height * 0.5 + Self.rotateHandleLength * 0.5 + 5))

                // Table mode & outline settings pop up menu button placed next to the rotate handle
                if case .table(let table) = object.kind {
                    tableModeAndSettingsMenu(for: object, table: table)
                        .offset(x: 34, y: -(object.height * 0.5 + Self.rotateHandleLength * 0.5 + 5))
                }

                // Four corner dots to resize
                cornerHandleDot(for: object, corner: .topLeft)
                    .offset(x: -object.width * 0.5, y: -object.height * 0.5)

                cornerHandleDot(for: object, corner: .topRight)
                    .offset(x: object.width * 0.5, y: -object.height * 0.5)

                cornerHandleDot(for: object, corner: .bottomLeft)
                    .offset(x: -object.width * 0.5, y: object.height * 0.5)

                cornerHandleDot(for: object, corner: .bottomRight)
                    .offset(x: object.width * 0.5, y: object.height * 0.5)

                // If table: add circular column-width adjustment handles at the top of each divider,
                // and row-height adjustment handles along the left edge
                if case .table = object.kind {
                    let colWidths = object.tableColumnWidths()
                    let rowHeights = object.tableRowHeights()

                    // Top circular handles for each column boundary
                    ForEach(0..<(colWidths.count - 1), id: \.self) { divIdx in
                        let cumulativeX = colWidths[0...divIdx].reduce(0, +)
                        let localX = -object.width * 0.5 + cumulativeX
                        columnDividerHandle(for: object, dividerIndex: divIdx)
                            .offset(x: localX, y: -object.height * 0.5)
                    }

                    // Left circular handles for row height adjustment
                    ForEach(0..<(rowHeights.count - 1), id: \.self) { rowIdx in
                        let cumulativeY = rowHeights[0...rowIdx].reduce(0, +)
                        let localY = -object.height * 0.5 + cumulativeY
                        rowDividerHandle(for: object, rowIndex: rowIdx)
                            .offset(x: -object.width * 0.5, y: localY)
                    }
                }
            }
        }
    }

    private func textBoxPerimeterMoveRing(for object: PageObject) -> some View {
        let stripThickness: CGFloat = 20.0
        return ZStack {
            // Top edge strip
            Color.clear
                .frame(width: object.width, height: stripThickness)
                .contentShape(Rectangle())
                .gesture(moveGesture(for: object))
                .offset(y: -object.height * 0.5)

            // Bottom edge strip
            Color.clear
                .frame(width: object.width, height: stripThickness)
                .contentShape(Rectangle())
                .gesture(moveGesture(for: object))
                .offset(y: object.height * 0.5)

            // Left edge strip
            Color.clear
                .frame(width: stripThickness, height: object.height)
                .contentShape(Rectangle())
                .gesture(moveGesture(for: object))
                .offset(x: -object.width * 0.5)

            // Right edge strip
            Color.clear
                .frame(width: stripThickness, height: object.height)
                .contentShape(Rectangle())
                .gesture(moveGesture(for: object))
                .offset(x: object.width * 0.5)
        }
    }

    private func columnDividerHandle(for object: PageObject, dividerIndex: Int) -> some View {
        ZStack {
            // Sleek high-contrast tactile pill badge
            ZStack {
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.20), radius: 2.5, x: 0, y: 1)
                Capsule()
                    .strokeBorder(Color.accentColor, lineWidth: 1.8)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 28, height: 14)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .gesture(columnDividerGesture(for: object, dividerIndex: dividerIndex))
    }

    private func rowDividerHandle(for object: PageObject, rowIndex: Int) -> some View {
        ZStack {
            // Sleek high-contrast tactile pill badge
            ZStack {
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.20), radius: 2.5, x: 0, y: 1)
                Capsule()
                    .strokeBorder(Color.accentColor, lineWidth: 1.8)
                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 14, height: 28)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .gesture(rowHeightGesture(for: object))
    }

    private func lineEndpointBarHandle(for object: PageObject, endpoint: LineEndpointHandle) -> some View {
        ZStack {
            Capsule()
                .fill(Color.white)
                .frame(width: 6, height: 24)
                .shadow(color: .black.opacity(0.22), radius: 2, x: 0, y: 1)
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 3.5, height: 22)
        }
        .frame(width: Self.cornerHitTargetSize, height: Self.cornerHitTargetSize)
        .contentShape(Rectangle())
        .gesture(lineEndpointResizeGesture(for: object, endpoint: endpoint))
    }

    private func cornerHandleDot(for object: PageObject, corner: ObjectResizeCorner) -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: Self.cornerDotDiameter, height: Self.cornerDotDiameter)
                .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
            Circle()
                .strokeBorder(Color.accentColor, lineWidth: 2.2)
                .frame(width: Self.cornerDotDiameter, height: Self.cornerDotDiameter)
        }
        .frame(width: Self.cornerHitTargetSize, height: Self.cornerHitTargetSize)
        .contentShape(Rectangle())
        .gesture(resizeGesture(for: object, corner: corner))
    }

    // MARK: - Floating Action Bar for Selected Object

    public static func floatingToolbarGeometry(for object: PageObject) -> (center: CGPoint, size: CGSize) {
        let isTwoRow: Bool = {
            if case .textBox = object.kind { return true }
            if case .table(let table) = object.kind, table.isTextMode { return true }
            return false
        }()
        let bounds = object.rotatedBoundingBox()
        let horizontalMargin: CGFloat = isTwoRow ? 225 : 190
        let clampedX = Swift.min(Swift.max(object.center.x, horizontalMargin), PageGeometry.a4Width - horizontalMargin)
        let preferredBottomY = bounds.maxY + (isTwoRow ? 44 : 26)
        let toolbarY = (preferredBottomY < PageGeometry.a4Height - (isTwoRow ? 52 : 36))
            ? preferredBottomY
            : Swift.max(isTwoRow ? 52 : 36, bounds.minY - (isTwoRow ? 64 : 46))
        let width: CGFloat = {
            if case .textBox = object.kind { return 450 }
            if case .table(let table) = object.kind { return table.isTextMode ? 460 : 390 }
            return 330
        }()
        let size = CGSize(width: width, height: isTwoRow ? 94 : 56)
        return (CGPoint(x: clampedX, y: toolbarY), size)
    }

    public static func estimatedToolbarRect(for object: PageObject) -> CGRect {
        let geometry = floatingToolbarGeometry(for: object)
        return CGRect(
            x: geometry.center.x - geometry.size.width * 0.5,
            y: geometry.center.y - geometry.size.height * 0.5,
            width: geometry.size.width,
            height: geometry.size.height
        )
    }

    @ViewBuilder
    private func floatingContextToolbar(for object: PageObject) -> some View {
        let toolbarCenter = Self.floatingToolbarGeometry(for: object).center
        let clampedX = toolbarCenter.x
        let toolbarY = toolbarCenter.y

        Group {
            if case .textBox(_, let style) = object.kind {
                VStack(spacing: 6) {
                    textBoxStyleControlsRow(for: object, style: style)

                    Divider()

                    HStack(spacing: 12) {
                        commonObjectActionButtons(for: object)
                    }
                }
            } else if case .table(let table) = object.kind {
                if table.isTextMode {
                    VStack(spacing: 6) {
                        tableTextStyleControlsRow(for: object, table: table)

                        Divider()

                        HStack(spacing: 8) {
                            tableModeToggleChip(for: object, table: table)

                            Divider().frame(height: 18)

                            tableStructureControls(for: object, table: table)

                            Divider().frame(height: 18)

                            tableOutlineColorMenu(for: object, table: table)

                            Divider().frame(height: 18)

                            commonObjectActionButtons(for: object)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        tableModeToggleChip(for: object, table: table)

                        Divider().frame(height: 18)

                        tableStructureControls(for: object, table: table)

                        Divider().frame(height: 18)

                        tableOutlineColorMenu(for: object, table: table)

                        Divider().frame(height: 18)

                        commonObjectActionButtons(for: object)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    // Page link jump button
                    if case .pageLink(let targetPageID, let targetSecID, let targetNbID, _) = object.kind {
                        Button {
                            onNavigateToPage?(targetPageID, targetSecID, targetNbID)
                        } label: {
                            Label("Go to Page", systemImage: "arrow.right.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .frame(height: 18)
                    }

                    if canRecolor(object) {
                        ForEach(InkColorPreset.allCases) { preset in
                            Button {
                                let before = objects
                                let updated = object.recolored(to: preset)
                                onUpdateObjectLive(updated, true)
                                let after = before.map { $0.id == updated.id ? updated : $0 }
                                onCommitObjectsChange(before, after)
                            } label: {
                                Circle()
                                    .fill(preset.inkDisplayColor(for: colorScheme))
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                isCurrentColor(preset, on: object) ? Color.accentColor : Color.primary.opacity(0.28),
                                                lineWidth: isCurrentColor(preset, on: object) ? 2.2 : 1.0
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(preset.inkDisplayName(for: colorScheme))
                        }

                        Divider()
                            .frame(height: 18)
                    }

                    commonObjectActionButtons(for: object)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1.0)
        )
        .position(x: clampedX, y: toolbarY)
    }

    @ViewBuilder
    private func textBoxStyleControlsRow(for object: PageObject, style: TextBoxStyle) -> some View {
        HStack(spacing: 8) {
            // Font size stepper (- / size / +)
            HStack(spacing: 2) {
                Button {
                    var next = style
                    next.fontSize = TextBoxStyle.clampedFontSize(style.fontSize - 2)
                    commitTextBoxStyleChange(next, for: object)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(style.fontSize <= TextBoxStyle.fontSizeRange.lowerBound)
                .help("Decrease Font Size")

                Text("\(Int(style.fontSize.rounded()))")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .frame(minWidth: 22)

                Button {
                    var next = style
                    next.fontSize = TextBoxStyle.clampedFontSize(style.fontSize + 2)
                    commitTextBoxStyleChange(next, for: object)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(style.fontSize >= TextBoxStyle.fontSizeRange.upperBound)
                .help("Increase Font Size")
            }
            .padding(.horizontal, 3)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            // Font Family / Design Menu
            Menu {
                ForEach(TextBoxFontDesign.allCases) { design in
                    Button {
                        var next = style
                        next.fontDesign = design
                        commitTextBoxStyleChange(next, for: object)
                    } label: {
                        HStack {
                            Label(design.displayName, systemImage: design.systemImageName)
                            if style.fontDesign == design {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "textformat")
                        .font(.system(size: 11, weight: .semibold))
                    Text(style.fontDesign.displayName)
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Font Family")

            // Bold & Italic toggles
            HStack(spacing: 2) {
                Button {
                    var next = style
                    next.isBold.toggle()
                    commitTextBoxStyleChange(next, for: object)
                } label: {
                    Image(systemName: "bold")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(style.isBold ? Color.accentColor : Color.primary)
                        .frame(width: 26, height: 26)
                        .background(style.isBold ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Bold")

                Button {
                    var next = style
                    next.isItalic.toggle()
                    commitTextBoxStyleChange(next, for: object)
                } label: {
                    Image(systemName: "italic")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(style.isItalic ? Color.accentColor : Color.primary)
                        .frame(width: 26, height: 26)
                        .background(style.isItalic ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Italic")
            }

            Divider().frame(height: 18)

            // Alignment controls
            HStack(spacing: 2) {
                ForEach(TextBoxAlignment.allCases) { alignment in
                    Button {
                        var next = style
                        next.alignment = alignment
                        commitTextBoxStyleChange(next, for: object)
                    } label: {
                        Image(systemName: alignment.systemImageName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(style.alignment == alignment ? Color.accentColor : Color.primary)
                            .frame(width: 25, height: 25)
                            .background(style.alignment == alignment ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Align \(alignment.displayName)")
                }
            }

            // Bullet list toggle
            Button {
                if case .textBox(let currentText, _) = object.kind {
                    let newText = TextBoxBulletHelper.toggleBullets(in: currentText)
                    let before = objects
                    let updated = object.withText(newText)
                    onUpdateObjectLive(updated, false)
                    let after = before.map { $0.id == updated.id ? updated : $0 }
                    onCommitObjectsChange(before, after)
                }
            } label: {
                let isBulleted: Bool = {
                    if case .textBox(let currentText, _) = object.kind {
                        return TextBoxBulletHelper.isBulleted(currentText)
                    }
                    return false
                }()
                Image(systemName: "list.bullet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isBulleted ? Color.accentColor : Color.primary)
                    .frame(width: 25, height: 25)
                    .background(isBulleted ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Bullet List")

            Divider().frame(height: 18)

            // Text Color picker popover
            Button {
                isCardFillPickerPresented = false
                isCardBorderPickerPresented = false
                isTextColorPickerPresented.toggle()
            } label: {
                VStack(spacing: 1) {
                    Text("A")
                        .font(.system(size: 12, weight: .bold))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(style.textColor.swiftUIColor)
                        .frame(width: 14, height: 3)
                        .overlay(RoundedRectangle(cornerRadius: 1).stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Text Colour")
            .popover(isPresented: $isTextColorPickerPresented, arrowEdge: .bottom) {
                textBoxColorPopover(title: "Text Colour", selected: style.textColor, allowNone: false) { chosen in
                    var next = style
                    if let chosen {
                        next.textColor = chosen
                    }
                    commitTextBoxStyleChange(next, for: object)
                    isTextColorPickerPresented = false
                }
            }

            // Card Fill picker popover
            Button {
                isTextColorPickerPresented = false
                isCardBorderPickerPresented = false
                isCardFillPickerPresented.toggle()
            } label: {
                ZStack {
                    if let bg = style.backgroundColor {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(bg.swiftUIColor)
                            .frame(width: 16, height: 16)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.35), lineWidth: 1))
                    } else {
                        Image(systemName: "paintbrush")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Card Background Fill")
            .popover(isPresented: $isCardFillPickerPresented, arrowEdge: .bottom) {
                textBoxColorPopover(title: "Card Fill", selected: style.backgroundColor, allowNone: true) { chosen in
                    var next = style
                    next.backgroundColor = chosen
                    commitTextBoxStyleChange(next, for: object)
                    isCardFillPickerPresented = false
                }
            }

            // Card Border picker popover
            Button {
                isTextColorPickerPresented = false
                isCardFillPickerPresented = false
                isCardBorderPickerPresented.toggle()
            } label: {
                ZStack {
                    if let border = style.borderColor {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(border.swiftUIColor, lineWidth: 2.0)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "square.dashed")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Card Border")
            .popover(isPresented: $isCardBorderPickerPresented, arrowEdge: .bottom) {
                textBoxColorPopover(title: "Card Border", selected: style.borderColor, allowNone: true) { chosen in
                    var next = style
                    next.borderColor = chosen
                    commitTextBoxStyleChange(next, for: object)
                    isCardBorderPickerPresented = false
                }
            }
        }
    }

    @ViewBuilder
    private func textBoxColorPopover(
        title: String,
        selected: InkColorPreset?,
        allowNone: Bool,
        onSelect: @escaping (InkColorPreset?) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if allowNone {
                    Button {
                        onSelect(nil)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.secondary.opacity(0.12))
                                .frame(width: 22, height: 22)
                            Image(systemName: "nosign")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            if selected == nil {
                                Circle()
                                    .strokeBorder(Color.accentColor, lineWidth: 2.2)
                                    .frame(width: 26, height: 26)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("None")
                }

                ForEach(InkColorPreset.allCases) { preset in
                    Button {
                        onSelect(preset)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(preset.swiftUIColor)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.28), lineWidth: 1.0)
                                )
                            if selected == preset {
                                Circle()
                                    .strokeBorder(Color.accentColor, lineWidth: 2.2)
                                    .frame(width: 26, height: 26)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(preset.displayName)
                }
            }
        }
        .padding(12)
        .presentationCompactAdaptation(.popover)
    }

    @ViewBuilder
    private func commonObjectActionButtons(for object: PageObject) -> some View {
        Button {
            onCopyObject(object.id)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help("Copy Object")

        Button {
            onDuplicateObject(object.id)
        } label: {
            Image(systemName: "plus.square.on.square")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help("Duplicate Object")

        Button(role: .destructive) {
            textBoxUndoBridge?.flushPendingEditIfNeeded()
            let before = objects
            let after = objects.filter { $0.id != object.id }
            onDeleteObject(object.id)
            onCommitObjectsChange(before, after)
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help("Delete Object")

        Button {
            onSelectObject(nil)
        } label: {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help("Done Editing Object")
    }

    private func commitTextBoxStyleChange(_ newStyle: TextBoxStyle, for object: PageObject) {
        textBoxUndoBridge?.flushPendingEditIfNeeded()
        let before = objects
        let updated = object.withTextBoxStyle(newStyle)
        onUpdateObjectLive(updated, true)
        let after = before.map { $0.id == updated.id ? updated : $0 }
        onCommitObjectsChange(before, after)
    }

    private func commitTableTextStyleChange(_ newStyle: TextBoxStyle, for object: PageObject) {
        let before = objects
        let updated = object.withTableTextStyle(newStyle)
        onUpdateObjectLive(updated, true)
        let after = before.map { $0.id == updated.id ? updated : $0 }
        onCommitObjectsChange(before, after)
    }

    @ViewBuilder
    private func tableTextStyleControlsRow(for object: PageObject, table: TableProperties) -> some View {
        let style = table.textStyle
        HStack(spacing: 8) {
            // Font size stepper (- / size / +)
            HStack(spacing: 2) {
                Button {
                    var next = style
                    next.fontSize = TextBoxStyle.clampedFontSize(style.fontSize - 2)
                    commitTableTextStyleChange(next, for: object)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(style.fontSize <= TextBoxStyle.fontSizeRange.lowerBound)
                .help("Decrease Font Size")

                Text("\(Int(style.fontSize.rounded()))")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .frame(minWidth: 22)

                Button {
                    var next = style
                    next.fontSize = TextBoxStyle.clampedFontSize(style.fontSize + 2)
                    commitTableTextStyleChange(next, for: object)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(style.fontSize >= TextBoxStyle.fontSizeRange.upperBound)
                .help("Increase Font Size")
            }
            .padding(.horizontal, 3)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            // Font Family / Design Menu
            Menu {
                ForEach(TextBoxFontDesign.allCases) { design in
                    Button {
                        var next = style
                        next.fontDesign = design
                        commitTableTextStyleChange(next, for: object)
                    } label: {
                        HStack {
                            Label(design.displayName, systemImage: design.systemImageName)
                            if style.fontDesign == design {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "textformat")
                        .font(.system(size: 11, weight: .semibold))
                    Text(style.fontDesign.displayName)
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Font Family")

            // Bold & Italic toggles
            HStack(spacing: 2) {
                Button {
                    var next = style
                    next.isBold.toggle()
                    commitTableTextStyleChange(next, for: object)
                } label: {
                    Image(systemName: "bold")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(style.isBold ? Color.accentColor : Color.primary)
                        .frame(width: 26, height: 26)
                        .background(style.isBold ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Bold")

                Button {
                    var next = style
                    next.isItalic.toggle()
                    commitTableTextStyleChange(next, for: object)
                } label: {
                    Image(systemName: "italic")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(style.isItalic ? Color.accentColor : Color.primary)
                        .frame(width: 26, height: 26)
                        .background(style.isItalic ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Italic")
            }

            Divider().frame(height: 18)

            // Alignment controls
            HStack(spacing: 2) {
                ForEach(TextBoxAlignment.allCases) { alignment in
                    Button {
                        var next = style
                        next.alignment = alignment
                        commitTableTextStyleChange(next, for: object)
                    } label: {
                        Image(systemName: alignment.systemImageName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(style.alignment == alignment ? Color.accentColor : Color.primary)
                            .frame(width: 25, height: 25)
                            .background(style.alignment == alignment ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Align \(alignment.displayName)")
                }
            }

            // Bullet list toggle for table cells
            Button {
                var newCells = table.cellTexts
                let nonBlank = newCells.values.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                let allBulleted = !nonBlank.isEmpty && nonBlank.allSatisfy { TextBoxBulletHelper.isBulleted($0) }
                for (key, val) in newCells {
                    newCells[key] = TextBoxBulletHelper.toggleBullets(in: val)
                }
                let before = objects
                var updatedTable = table
                updatedTable.cellTexts = newCells
                var updated = object
                updated.kind = .table(updatedTable)
                onUpdateObjectLive(updated, true)
                let after = before.map { $0.id == updated.id ? updated : $0 }
                onCommitObjectsChange(before, after)
            } label: {
                let isBulleted: Bool = {
                    let nonBlank = table.cellTexts.values.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    return !nonBlank.isEmpty && nonBlank.allSatisfy { TextBoxBulletHelper.isBulleted($0) }
                }()
                Image(systemName: "list.bullet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isBulleted ? Color.accentColor : Color.primary)
                    .frame(width: 25, height: 25)
                    .background(isBulleted ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Bullet List")

            Divider().frame(height: 18)

            // Text Color picker popover
            Button {
                isCardFillPickerPresented = false
                isCardBorderPickerPresented = false
                isTextColorPickerPresented.toggle()
            } label: {
                VStack(spacing: 1) {
                    Text("A")
                        .font(.system(size: 12, weight: .bold))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(style.textColor.swiftUIColor)
                        .frame(width: 14, height: 3)
                        .overlay(RoundedRectangle(cornerRadius: 1).stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Cell Text Colour")
            .popover(isPresented: $isTextColorPickerPresented, arrowEdge: .bottom) {
                textBoxColorPopover(title: "Text Colour", selected: style.textColor, allowNone: false) { chosen in
                    if let chosen {
                        var next = style
                        next.textColor = chosen
                        commitTableTextStyleChange(next, for: object)
                    }
                    isTextColorPickerPresented = false
                }
            }
        }
    }

    private func tableModeToggleChip(for object: PageObject, table: TableProperties) -> some View {
        Button {
            let before = objects
            let updated = object.withToggledTableTextMode()
            onUpdateObjectLive(updated, true)
            let after = before.map { $0.id == updated.id ? updated : $0 }
            onCommitObjectsChange(before, after)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: table.isTextMode ? "character.cursor.ibeam" : "pencil.tip.crop.inline")
                    .font(.system(size: 12, weight: .bold))
                Text(table.isTextMode ? "Text Mode" : "Draw Mode")
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                table.isTextMode ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .foregroundStyle(table.isTextMode ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .help(table.isTextMode ? "Switch to Draw Mode" : "Switch to Text Mode")
    }

    @ViewBuilder
    private func tableStructureControls(for object: PageObject, table: TableProperties) -> some View {
        Button {
            let before = objects
            let updated = object.withToggledTableHeader()
            onUpdateObjectLive(updated, true)
            let after = before.map { $0.id == updated.id ? updated : $0 }
            onCommitObjectsChange(before, after)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: table.hasHeaderRow ? "tablecells.badge.ellipsis" : "tablecells")
                    .font(.system(size: 13, weight: .semibold))
                Text(table.hasHeaderRow ? "Header: On" : "Header: Off")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(table.hasHeaderRow ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Toggle Header Row")

        HStack(spacing: 2) {
            Button {
                let before = objects
                let updated = object.withAddedTableRow()
                onUpdateObjectLive(updated, true)
                let after = before.map { $0.id == updated.id ? updated : $0 }
                onCommitObjectsChange(before, after)
            } label: {
                Text("+ Row")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .help("Add Row")

            if table.rowCount > 1 {
                Button {
                    let before = objects
                    let updated = object.withRemovedTableRow()
                    onUpdateObjectLive(updated, true)
                    let after = before.map { $0.id == updated.id ? updated : $0 }
                    onCommitObjectsChange(before, after)
                } label: {
                    Text("- Row")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .help("Remove Row")
            }
        }
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

        HStack(spacing: 2) {
            Button {
                let before = objects
                let updated = object.withAddedTableColumn()
                onUpdateObjectLive(updated, true)
                let after = before.map { $0.id == updated.id ? updated : $0 }
                onCommitObjectsChange(before, after)
            } label: {
                Text("+ Col")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .help("Add Column")

            if table.columnCount > 1 {
                Button {
                    let before = objects
                    let updated = object.withRemovedTableColumn()
                    onUpdateObjectLive(updated, true)
                    let after = before.map { $0.id == updated.id ? updated : $0 }
                    onCommitObjectsChange(before, after)
                } label: {
                    Text("- Col")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .help("Remove Column")
            }
        }
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private func tableOutlineColorMenu(for object: PageObject, table: TableProperties) -> some View {
        Menu {
            ForEach(InkColorPreset.allCases) { preset in
                Button {
                    let before = objects
                    let updated = object.withTableStrokeColor(preset)
                    onUpdateObjectLive(updated, true)
                    let after = before.map { $0.id == updated.id ? updated : $0 }
                    onCommitObjectsChange(before, after)
                } label: {
                    HStack {
                        Circle()
                            .fill(preset.inkDisplayColor(for: colorScheme))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                        Text(preset.inkDisplayName(for: colorScheme))
                        if table.strokeColor == preset {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(table.strokeColor.inkDisplayColor(for: colorScheme))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1.0))
                Image(systemName: "square.dashed")
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Table Outline Colour")
    }

    private func tableModeAndSettingsMenu(for object: PageObject, table: TableProperties) -> some View {
        Menu {
            Section("Table Mode") {
                Button {
                    let before = objects
                    let updated = object.withToggledTableTextMode()
                    onUpdateObjectLive(updated, true)
                    let after = before.map { $0.id == updated.id ? updated : $0 }
                    onCommitObjectsChange(before, after)
                } label: {
                    Label(
                        table.isTextMode ? "Switch to Draw Mode" : "Switch to Text Mode",
                        systemImage: table.isTextMode ? "pencil.tip.crop.inline" : "character.cursor.ibeam"
                    )
                }
            }

            Section("Table Outline Colour") {
                ForEach(InkColorPreset.allCases) { preset in
                    Button {
                        let before = objects
                        let updated = object.withTableStrokeColor(preset)
                        onUpdateObjectLive(updated, true)
                        let after = before.map { $0.id == updated.id ? updated : $0 }
                        onCommitObjectsChange(before, after)
                    } label: {
                        HStack {
                            Circle()
                                .fill(preset.inkDisplayColor(for: colorScheme))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                            Text(preset.inkDisplayName(for: colorScheme))
                            if table.strokeColor == preset {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section("Table Grid") {
                Button {
                    let before = objects
                    let updated = object.withToggledTableHeader()
                    onUpdateObjectLive(updated, true)
                    let after = before.map { $0.id == updated.id ? updated : $0 }
                    onCommitObjectsChange(before, after)
                } label: {
                    Label(table.hasHeaderRow ? "Header Row: On" : "Header Row: Off", systemImage: "tablecells.badge.ellipsis")
                }

                Button {
                    let before = objects
                    let updated = object.withToggledTableStriping()
                    onUpdateObjectLive(updated, true)
                    let after = before.map { $0.id == updated.id ? updated : $0 }
                    onCommitObjectsChange(before, after)
                } label: {
                    Label(table.isStriped ? "Striped Rows: On" : "Striped Rows: Off", systemImage: "checklist.unchecked")
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.8)
                    .frame(width: 22, height: 22)
                Image(systemName: table.isTextMode ? "character.cursor.ibeam" : "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: Self.cornerHitTargetSize, height: Self.cornerHitTargetSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Table Mode & Settings")
    }

    private func canRecolor(_ object: PageObject) -> Bool {
        switch object.kind {
        case .basicShape, .strokeGroup, .table:
            return true
        case .image, .pageLink, .textBox:
            return false
        }
    }

    private func isCurrentColor(_ preset: InkColorPreset, on object: PageObject) -> Bool {
        switch object.kind {
        case .basicShape(_, let color, _):
            return color == preset
        case .strokeGroup(_, _, _, let tint):
            return tint == preset
        case .table(let table):
            return table.strokeColor == preset
        case .textBox(_, let style):
            return style.textColor == preset
        case .image, .pageLink:
            return false
        }
    }

    // MARK: - Gestures (Move, 4-Corner Resize, Rotate)

    private func moveGesture(for object: PageObject) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if dragStartObject == nil {
                    textBoxUndoBridge?.flushPendingEditIfNeeded()
                    dragStartObject = object
                    dragStartAllObjects = objects
                    isActivelyDraggingHandle = true
                    if selectedObjectID != object.id {
                        onSelectObject(object.id)
                    }
                }
                guard let initial = dragStartObject else { return }
                let updated = initial.moved(by: value.translation)
                onUpdateObjectLive(updated, false)
            }
            .onEnded { value in
                defer {
                    dragStartObject = nil
                    dragStartAllObjects = nil
                    isActivelyDraggingHandle = false
                }
                guard let initial = dragStartObject, let before = dragStartAllObjects else { return }
                let finalObj = initial.moved(by: value.translation)
                onUpdateObjectLive(finalObj, true)
                let after = before.map { $0.id == finalObj.id ? finalObj : $0 }
                if before != after {
                    onCommitObjectsChange(before, after)
                }
            }
    }

    private func resizeGesture(for object: PageObject, corner: ObjectResizeCorner) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if dragStartObject == nil {
                    textBoxUndoBridge?.flushPendingEditIfNeeded()
                    dragStartObject = object
                    dragStartAllObjects = objects
                    isActivelyDraggingHandle = true
                }
                guard let initial = dragStartObject else { return }
                let updated = initial.resized(corner: corner, pageDelta: value.translation)
                onUpdateObjectLive(updated, false)
            }
            .onEnded { value in
                defer {
                    dragStartObject = nil
                    dragStartAllObjects = nil
                    isActivelyDraggingHandle = false
                }
                guard let initial = dragStartObject, let before = dragStartAllObjects else { return }
                let finalObj = initial.resized(corner: corner, pageDelta: value.translation)
                onUpdateObjectLive(finalObj, true)
                let after = before.map { $0.id == finalObj.id ? finalObj : $0 }
                if before != after {
                    onCommitObjectsChange(before, after)
                }
            }
    }

    private func lineEndpointResizeGesture(for object: PageObject, endpoint: LineEndpointHandle) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if dragStartObject == nil {
                    dragStartObject = object
                    dragStartAllObjects = objects
                    isActivelyDraggingHandle = true
                }
                guard let initial = dragStartObject else { return }
                let updated = initial.resizedEndpoint(endpoint, pageDelta: value.translation)
                onUpdateObjectLive(updated, false)
            }
            .onEnded { value in
                defer {
                    dragStartObject = nil
                    dragStartAllObjects = nil
                    isActivelyDraggingHandle = false
                }
                guard let initial = dragStartObject, let before = dragStartAllObjects else { return }
                let finalObj = initial.resizedEndpoint(endpoint, pageDelta: value.translation)
                onUpdateObjectLive(finalObj, true)
                let after = before.map { $0.id == finalObj.id ? finalObj : $0 }
                if before != after {
                    onCommitObjectsChange(before, after)
                }
            }
    }

    private func rotateGesture(for object: PageObject) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if dragStartObject == nil {
                    textBoxUndoBridge?.flushPendingEditIfNeeded()
                    dragStartObject = object
                    dragStartAllObjects = objects
                    isActivelyDraggingHandle = true
                }
                guard let initial = dragStartObject else { return }
                let updated = initial.rotated(toward: value.location)
                onUpdateObjectLive(updated, false)
            }
            .onEnded { value in
                defer {
                    dragStartObject = nil
                    dragStartAllObjects = nil
                    isActivelyDraggingHandle = false
                }
                guard let initial = dragStartObject, let before = dragStartAllObjects else { return }
                let finalObj = initial.rotated(toward: value.location)
                onUpdateObjectLive(finalObj, true)
                let after = before.map { $0.id == finalObj.id ? finalObj : $0 }
                if before != after {
                    onCommitObjectsChange(before, after)
                }
            }
    }

    private func columnDividerGesture(for object: PageObject, dividerIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if dragStartObject == nil {
                    dragStartObject = object
                    dragStartAllObjects = objects
                    isActivelyDraggingHandle = true
                    lastDetentStep = 0
                }
                guard let initial = dragStartObject else { return }

                // Tactile detent feedback every 8pt of drag distance
                let step = Int(round(value.translation.width / Theme.Spacing.grid8))
                if step != lastDetentStep {
                    lastDetentStep = step
                    UISelectionFeedbackGenerator().selectionChanged()
                }

                let updated = initial.adjustingColumnDivider(at: dividerIndex, pageDelta: value.translation)
                onUpdateObjectLive(updated, false)
            }
            .onEnded { value in
                defer {
                    dragStartObject = nil
                    dragStartAllObjects = nil
                    isActivelyDraggingHandle = false
                    lastDetentStep = 0
                }
                guard let initial = dragStartObject, let before = dragStartAllObjects else { return }
                let finalObj = initial.adjustingColumnDivider(at: dividerIndex, pageDelta: value.translation)
                onUpdateObjectLive(finalObj, true)
                let after = before.map { $0.id == finalObj.id ? finalObj : $0 }
                if before != after {
                    onCommitObjectsChange(before, after)
                }
            }
    }

    private func rowHeightGesture(for object: PageObject) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if dragStartObject == nil {
                    dragStartObject = object
                    dragStartAllObjects = objects
                    isActivelyDraggingHandle = true
                    lastDetentStep = 0
                }
                guard let initial = dragStartObject else { return }

                // Tactile detent feedback every 8pt of drag distance
                let step = Int(round(value.translation.height / Theme.Spacing.grid8))
                if step != lastDetentStep {
                    lastDetentStep = step
                    UISelectionFeedbackGenerator().selectionChanged()
                }

                let updated = initial.adjustingTableRowHeight(pageDelta: value.translation)
                onUpdateObjectLive(updated, false)
            }
            .onEnded { value in
                defer {
                    dragStartObject = nil
                    dragStartAllObjects = nil
                    isActivelyDraggingHandle = false
                    lastDetentStep = 0
                }
                guard let initial = dragStartObject, let before = dragStartAllObjects else { return }
                let finalObj = initial.adjustingTableRowHeight(pageDelta: value.translation)
                onUpdateObjectLive(finalObj, true)
                let after = before.map { $0.id == finalObj.id ? finalObj : $0 }
                if before != after {
                    onCommitObjectsChange(before, after)
                }
            }
    }
}

// MARK: - Single PageObject Visual Content Renderer (Shared by Canvas, Thumbnail & PDF)

public struct PageObjectContentView: View {
    public let object: PageObject
    public let assetDataProvider: (UUID) -> Data?
    @Environment(\.colorScheme) private var colorScheme

    public init(object: PageObject, assetDataProvider: @escaping (UUID) -> Data?) {
        self.object = object
        self.assetDataProvider = assetDataProvider
    }

    public var body: some View {
        switch object.kind {
        case .basicShape(let shapeKind, let strokeColor, let strokeWidth):
            Canvas { context, size in
                let inset = Swift.max(strokeWidth * 0.5 + 1.0, 2.0)
                let drawRect = CGRect(x: inset, y: inset, width: Swift.max(1, size.width - inset * 2), height: Swift.max(1, size.height - inset * 2))
                let style = StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                let shading = GraphicsContext.Shading.color(strokeColor.inkDisplayColor(for: colorScheme))

                switch shapeKind {
                case .rectangle:
                    let path = Path(roundedRect: drawRect, cornerRadius: 2)
                    context.stroke(path, with: shading, style: style)

                case .circle:
                    let path = Path(ellipseIn: drawRect)
                    context.stroke(path, with: shading, style: style)

                case .line:
                    let midY = size.height * 0.5
                    var path = Path()
                    path.move(to: CGPoint(x: drawRect.minX, y: midY))
                    path.addLine(to: CGPoint(x: drawRect.maxX, y: midY))
                    context.stroke(path, with: shading, style: style)

                case .arrow:
                    let midY = size.height * 0.5
                    let start = CGPoint(x: drawRect.minX, y: midY)
                    let end = CGPoint(x: drawRect.maxX, y: midY)
                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)

                    let headLength = Swift.min(Swift.max(strokeWidth * 4.2, 14.0), drawRect.width * 0.42)
                    let headAngle: CGFloat = .pi / 6.0

                    let wing1 = CGPoint(
                        x: end.x - headLength * cos(-headAngle),
                        y: end.y - headLength * sin(-headAngle)
                    )
                    let wing2 = CGPoint(
                        x: end.x - headLength * cos(headAngle),
                        y: end.y - headLength * sin(headAngle)
                    )
                    path.move(to: end)
                    path.addLine(to: wing1)
                    path.move(to: end)
                    path.addLine(to: wing2)
                    context.stroke(path, with: shading, style: style)
                }
            }

        case .image(let assetID):
            if let data = assetDataProvider(assetID), let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: object.width, height: object.height)
                    .clipped()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }

        case .strokeGroup(let drawingData, let sourceW, let sourceH, let tintOverride):
            if let image = Self.renderStrokeGroupImage(
                drawingData: drawingData,
                sourceSize: CGSize(width: sourceW, height: sourceH),
                targetSize: CGSize(width: object.width, height: object.height),
                tintOverride: tintOverride
            ) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: object.width, height: object.height)
            } else {
                EmptyView()
            }

        case .table(let table):
            TableView(
                table: table,
                columnWidths: object.tableColumnWidths(),
                rowHeights: object.tableRowHeights(),
                isSelected: false,
                onCellTextChange: nil,
                onCommitCellText: nil
            )
            .frame(width: object.width, height: object.height)

        case .pageLink(let targetPageID, let targetSecID, let targetNbID, let fallbackTitle):
            PageLinkBadgeView(
                targetPageID: targetPageID,
                targetSectionID: targetSecID,
                targetNotebookID: targetNbID,
                fallbackTitle: fallbackTitle
            )

        case .textBox(let text, let style):
            TextBoxContentView(text: text, style: style)
        }
    }

    public static func renderStrokeGroupImage(
        drawingData: Data,
        sourceSize: CGSize,
        targetSize: CGSize,
        tintOverride: InkColorPreset?
    ) -> UIImage? {
        guard var drawing = try? PKDrawing(data: drawingData), !drawing.strokes.isEmpty else {
            return nil
        }
        if let tintOverride {
            let newColor = tintOverride.uiColor(opacity: 1.0)
            let tintedStrokes = drawing.strokes.map { stroke -> PKStroke in
                var copy = stroke
                copy.ink = PKInk(stroke.ink.inkType, color: newColor.withAlphaComponent(stroke.ink.color.cgColor.alpha))
                return copy
            }
            drawing = PKDrawing(strokes: tintedStrokes)
        }
        let bounds = drawing.bounds.isNull || drawing.bounds.isEmpty
            ? CGRect(origin: .zero, size: sourceSize)
            : drawing.bounds.insetBy(dx: -4, dy: -4)
        let traitCollection = UITraitCollection(userInterfaceStyle: .light)
        var rendered: UIImage?
        traitCollection.performAsCurrent {
            rendered = drawing.image(from: bounds, scale: 2.0)
        }
        return rendered
    }
}

// MARK: - Table Cell Inline Editor (UIKit UITextView + Scribble Interaction)

public struct TableCellInlineEditor: UIViewRepresentable {
    public let text: String
    public let style: TextBoxStyle
    public let onTextChange: (String) -> Void
    public let onEndEditing: () -> Void

    public init(
        text: String,
        style: TextBoxStyle,
        onTextChange: @escaping (String) -> Void,
        onEndEditing: @escaping () -> Void
    ) {
        self.text = text
        self.style = style
        self.onTextChange = onTextChange
        self.onEndEditing = onEndEditing
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
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
        textView.textContainerInset = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.delegate = context.coordinator

        let scribble = UIScribbleInteraction(delegate: context.coordinator)
        textView.addInteraction(scribble)

        textView.text = text
        textView.font = style.resolvedUIFont()
        textView.textColor = style.resolvedCanvasUITextColor()
        textView.textAlignment = style.alignment.nsTextAlignment
        return textView
    }

    public func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if textView.markedTextRange == nil && textView.text != text {
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
        let targetAlign = style.alignment.nsTextAlignment
        if textView.textAlignment != targetAlign {
            textView.textAlignment = targetAlign
        }
    }

    public final class Coordinator: NSObject, UITextViewDelegate, UIScribbleInteractionDelegate {
        var parent: TableCellInlineEditor

        init(_ parent: TableCellInlineEditor) {
            self.parent = parent
        }

        public func textViewDidChange(_ textView: UITextView) {
            parent.onTextChange(textView.text ?? "")
        }

        public func textViewDidEndEditing(_ textView: UITextView) {
            parent.onEndEditing()
        }

        public func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
            true
        }

        public func scribbleInteractionShouldDelayFocus(_ interaction: UIScribbleInteraction) -> Bool {
            false
        }
    }
}

// MARK: - Table View Component (Grid Sits Under Ink Layer; Supports Draw & Text Modes)

public struct TableView: View {
    @Environment(\.colorScheme) private var colorScheme
    public let table: TableProperties
    public let columnWidths: [CGFloat]
    public let rowHeights: [CGFloat]
    public let isSelected: Bool
    public let onCellTextChange: ((Int, Int, String) -> Void)?
    public let onCommitCellText: (() -> Void)?

    public init(
        table: TableProperties,
        columnWidths: [CGFloat],
        rowHeights: [CGFloat],
        isSelected: Bool = false,
        onCellTextChange: ((Int, Int, String) -> Void)? = nil,
        onCommitCellText: (() -> Void)? = nil
    ) {
        self.table = table
        self.columnWidths = columnWidths
        self.rowHeights = rowHeights
        self.isSelected = isSelected
        self.onCellTextChange = onCellTextChange
        self.onCommitCellText = onCommitCellText
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let colWidths = columnWidths.isEmpty ? [w] : columnWidths
            let rowHeights = rowHeights.isEmpty ? [h] : rowHeights
            let gridColor = table.strokeColor.inkDisplayColor(for: colorScheme)
            let isEditing = table.isTextMode && isSelected

            ZStack(alignment: .topLeading) {
                // Table content & cells arranged in crisp rows and columns
                VStack(spacing: 0) {
                    ForEach(0..<rowHeights.count, id: \.self) { r in
                        let rH = rowHeights[r]
                        let isHeader = (r == 0 && table.hasHeaderRow)
                        let isStripe = (table.isStriped && r % 2 == 1)
                        let rowBg: Color = {
                            if isHeader { return gridColor.opacity(0.12) }
                            if isStripe { return gridColor.opacity(0.06) }
                            return Color.clear
                        }()

                        HStack(spacing: 0) {
                            ForEach(0..<colWidths.count, id: \.self) { c in
                                let cW = colWidths[c]
                                let key = "\(r),\(c)"
                                let cellText = table.cellTexts[key] ?? ""

                                ZStack {
                                    if isEditing {
                                        TableCellInlineEditor(
                                            text: cellText,
                                            style: table.textStyle,
                                            onTextChange: { newText in
                                                onCellTextChange?(r, c, newText)
                                            },
                                            onEndEditing: {
                                                onCommitCellText?()
                                            }
                                        )
                                        .frame(width: Swift.max(1, cW - 8), height: Swift.max(1, rH - 6))
                                        .clipped()
                                    } else if !cellText.isEmpty {
                                        Text(cellText)
                                            .font(table.textStyle.resolvedSwiftUIFont())
                                            .foregroundStyle(table.textStyle.resolvedCanvasTextColor())
                                            .multilineTextAlignment(table.textStyle.alignment.swiftUITextAlignment)
                                            .frame(
                                                width: Swift.max(1, cW - 8),
                                                height: Swift.max(1, rH - 6),
                                                alignment: table.textStyle.alignment.swiftUIFrameAlignment
                                            )
                                            .clipped()
                                            .allowsHitTesting(false)
                                    }
                                }
                                .frame(width: cW, height: rH)
                                .clipped()
                            }
                        }
                        .frame(width: w, height: rH)
                        .background(rowBg)
                    }
                }

                // Grid lines overlay drawn in Canvas
                Canvas { context, size in
                    let color = gridColor
                    let outerStyle = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                    let innerStyle = StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)

                    // Outer border
                    context.stroke(
                        Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: size.height), cornerRadius: 4),
                        with: .color(color),
                        style: outerStyle
                    )

                    // Vertical column lines
                    var currentX: CGFloat = 0
                    for colIdx in 0..<(colWidths.count - 1) {
                        currentX += colWidths[colIdx]
                        var vLine = Path()
                        vLine.move(to: CGPoint(x: currentX, y: 0))
                        vLine.addLine(to: CGPoint(x: currentX, y: size.height))
                        context.stroke(vLine, with: .color(color.opacity(0.80)), style: innerStyle)
                    }

                    // Horizontal row lines
                    var currentY: CGFloat = 0
                    for rowIdx in 0..<(rowHeights.count - 1) {
                        currentY += rowHeights[rowIdx]
                        var hLine = Path()
                        hLine.move(to: CGPoint(x: 0, y: currentY))
                        hLine.addLine(to: CGPoint(x: size.width, y: currentY))
                        let isHeaderDivider = (rowIdx == 0 && table.hasHeaderRow)
                        let rowStyle = isHeaderDivider ? outerStyle : innerStyle
                        context.stroke(hLine, with: .color(isHeaderDivider ? color : color.opacity(0.80)), style: rowStyle)
                    }
                }
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}

// MARK: - Page Link Badge Component

public struct PageLinkBadgeView: View {
    public let targetPageID: UUID
    public let targetSectionID: UUID
    public let targetNotebookID: UUID
    public let fallbackTitle: String

    public init(
        targetPageID: UUID,
        targetSectionID: UUID,
        targetNotebookID: UUID,
        fallbackTitle: String
    ) {
        self.targetPageID = targetPageID
        self.targetSectionID = targetSectionID
        self.targetNotebookID = targetNotebookID
        self.fallbackTitle = fallbackTitle
    }

    public var body: some View {
        HStack(spacing: 10) {
            // 32x32pt squircle icon container with accent tint
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)

                Image(systemName: "doc.text.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 32, height: 32)

            // Headline title & caption breadcrumb
            VStack(alignment: .leading, spacing: 1) {
                Text(fallbackTitle)
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("Linked Page")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Right-up chevron arrow
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.linkCard, style: .continuous)
                .fill(.ultraThinMaterial)
                .themeShadow(Theme.Shadows.subtleCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.linkCard, style: .continuous)
                .strokeBorder(Theme.Colors.cardBorder, lineWidth: 1.0)
        )
    }
}
