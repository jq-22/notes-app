//
//  DrawingToolMenuButton.swift
//  Notes
//
//  Responsibility: Compact toolbar button showing the current tool icon and colour badge.
//  Tapping opens the 4-row popover menu from the owner's sketch:
//    1. Pen >          (selects Pen; '>' opens size, opacity, and colour submenu)
//    2. Highlighter >  (selects Highlighter; '>' opens size, opacity, and colour submenu)
//    3. Rubber >       (selects Rubber/Eraser; '>' opens Object/Stroke vs Pixel + size submenu)
//    4. Ruler          (toggles PencilKit's native ruler overlay on/off)
//  Dependencies: SwiftUI, UIKit, Domain (DrawingToolState, InkColorPreset), DesignSystem (Theme).
//

import SwiftUI
import UIKit

extension InkColorPreset {
    public var swiftUIColor: Color {
        switch self {
        case .primary: return Color(uiColor: .label)
        case .blue: return Color(uiColor: .systemBlue)
        case .red: return Color(uiColor: .systemRed)
        case .green: return Color(uiColor: .systemGreen)
        case .orange: return Color(uiColor: .systemOrange)
        case .purple: return Color(uiColor: .systemPurple)
        case .yellow: return Color(uiColor: .systemYellow)
        }
    }

    public func uiColor(opacity: CGFloat) -> UIColor {
        let base: UIColor
        switch self {
        case .primary: base = .label
        case .blue: base = .systemBlue
        case .red: base = .systemRed
        case .green: base = .systemGreen
        case .orange: base = .systemOrange
        case .purple: base = .systemPurple
        case .yellow: base = .systemYellow
        }
        return base.withAlphaComponent(opacity)
    }
}

public struct DrawingToolMenuButton: View {
    @Binding var toolState: DrawingToolState

    @State private var isPopoverPresented = false
    @State private var subpage: Subpage = .root

    private enum Subpage: Equatable {
        case root
        case penOptions
        case highlighterOptions
        case eraserOptions
    }

    public init(toolState: Binding<DrawingToolState>) {
        self._toolState = toolState
    }

    private var activeIndicatorColor: Color {
        switch toolState.activeTool {
        case .pen:
            return toolState.penColor.swiftUIColor.opacity(Double(toolState.penOpacity))
        case .highlighter:
            return toolState.highlighterColor.swiftUIColor.opacity(Double(max(toolState.highlighterOpacity, 0.5)))
        case .eraser:
            return .secondary
        }
    }

    public var body: some View {
        Button {
            subpage = .root
            isPopoverPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: toolState.activeTool.systemImageName)
                Circle()
                    .fill(activeIndicatorColor)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.75))
                if toolState.isRulerActive {
                    Image(systemName: "ruler")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
        }
        .help("Drawing Tools (\(toolState.activeTool.displayName))")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                switch subpage {
                case .root:
                    rootMenuView
                case .penOptions:
                    penOptionsView
                case .highlighterOptions:
                    highlighterOptionsView
                case .eraserOptions:
                    eraserOptionsView
                }
            }
            .frame(width: 265)
            .padding(.vertical, Theme.Spacing.small)
            .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Root 4-Row Menu (Pen >, Highlighter >, Rubber >, Ruler)

    private var rootMenuView: some View {
        VStack(alignment: .leading, spacing: 2) {
            toolRow(
                title: "Pen",
                icon: DrawingToolKind.pen.systemImageName,
                isSelected: toolState.activeTool == .pen,
                colorBadge: toolState.penColor.swiftUIColor.opacity(Double(toolState.penOpacity)),
                selectAction: {
                    toolState.selectTool(.pen)
                },
                detailAction: {
                    toolState.selectTool(.pen)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        subpage = .penOptions
                    }
                }
            )

            Divider().padding(.horizontal, Theme.Spacing.medium)

            toolRow(
                title: "Highlighter",
                icon: DrawingToolKind.highlighter.systemImageName,
                isSelected: toolState.activeTool == .highlighter,
                colorBadge: toolState.highlighterColor.swiftUIColor.opacity(Double(max(toolState.highlighterOpacity, 0.5))),
                selectAction: {
                    toolState.selectTool(.highlighter)
                },
                detailAction: {
                    toolState.selectTool(.highlighter)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        subpage = .highlighterOptions
                    }
                }
            )

            Divider().padding(.horizontal, Theme.Spacing.medium)

            toolRow(
                title: "Rubber",
                icon: DrawingToolKind.eraser.systemImageName,
                isSelected: toolState.activeTool == .eraser,
                colorBadge: nil,
                selectAction: {
                    toolState.selectTool(.eraser)
                },
                detailAction: {
                    toolState.selectTool(.eraser)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        subpage = .eraserOptions
                    }
                }
            )

            Divider().padding(.horizontal, Theme.Spacing.medium)

            // Row 4: Ruler toggle
            Button {
                toolState.toggleRuler()
            } label: {
                HStack(spacing: Theme.Spacing.small) {
                    Image(systemName: "ruler")
                        .frame(width: 22)
                        .foregroundStyle(toolState.isRulerActive ? Color.accentColor : Color.primary)
                    Text("Ruler")
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(.primary)
                    Spacer()
                    if toolState.isRulerActive {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func toolRow(
        title: String,
        icon: String,
        isSelected: Bool,
        colorBadge: Color?,
        selectAction: @escaping () -> Void,
        detailAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            Button(action: selectAction) {
                HStack(spacing: Theme.Spacing.small) {
                    Image(systemName: icon)
                        .frame(width: 22)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    Text(title)
                        .font(isSelected ? Theme.Fonts.rowTitle.weight(.semibold) : Theme.Fonts.rowTitle)
                        .foregroundStyle(.primary)
                    if let colorBadge {
                        Circle()
                            .fill(colorBadge)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.leading, Theme.Spacing.medium)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: detailAction) {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Configure \(title) options")
        }
    }

    // MARK: - Subpage: Pen Options (Colour, Size, Opacity)

    private var penOptionsView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            subpageHeader(title: "Pen")

            colorSwatchesGrid(selected: $toolState.penColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Size")
                        .font(Theme.Fonts.rowSubtitle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(toolState.penWidth.rounded())) pt")
                        .font(Theme.Fonts.rowSubtitle)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { toolState.penWidth },
                        set: { toolState.setPenWidth($0) }
                    ),
                    in: DrawingToolState.widthRange,
                    step: 0.5
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Opacity")
                        .font(Theme.Fonts.rowSubtitle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((toolState.penOpacity * 100).rounded()))%")
                        .font(Theme.Fonts.rowSubtitle)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { toolState.penOpacity },
                        set: { toolState.setPenOpacity($0) }
                    ),
                    in: DrawingToolState.opacityRange,
                    step: 0.05
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.bottom, Theme.Spacing.small)
    }

    // MARK: - Subpage: Highlighter Options (Colour, Size, Opacity)

    private var highlighterOptionsView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            subpageHeader(title: "Highlighter")

            colorSwatchesGrid(selected: $toolState.highlighterColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Size")
                        .font(Theme.Fonts.rowSubtitle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(toolState.highlighterWidth.rounded())) pt")
                        .font(Theme.Fonts.rowSubtitle)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { toolState.highlighterWidth },
                        set: { toolState.setHighlighterWidth($0) }
                    ),
                    in: DrawingToolState.highlighterWidthRange,
                    step: 1.0
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Opacity")
                        .font(Theme.Fonts.rowSubtitle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((toolState.highlighterOpacity * 100).rounded()))%")
                        .font(Theme.Fonts.rowSubtitle)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { toolState.highlighterOpacity },
                        set: { toolState.setHighlighterOpacity($0) }
                    ),
                    in: DrawingToolState.opacityRange,
                    step: 0.05
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.bottom, Theme.Spacing.small)
    }

    // MARK: - Subpage: Rubber / Eraser Options (Object/Stroke vs Pixel + Size)

    private var eraserOptionsView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            subpageHeader(title: "Rubber")

            Picker("Eraser Mode", selection: $toolState.eraserMode) {
                Text("Object / Stroke").tag(EraserMode.object)
                Text("Pixel").tag(EraserMode.pixel)
            }
            .pickerStyle(.segmented)

            if toolState.eraserMode == .pixel {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Eraser Size")
                            .font(Theme.Fonts.rowSubtitle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(toolState.eraserWidth.rounded())) pt")
                            .font(Theme.Fonts.rowSubtitle)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { toolState.eraserWidth },
                            set: { toolState.setEraserWidth($0) }
                        ),
                        in: DrawingToolState.eraserWidthRange,
                        step: 1.0
                    )
                }
            } else {
                Text("Touches any part of a stroke to erase the whole stroke at once.")
                    .font(Theme.Fonts.rowSubtitle)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.bottom, Theme.Spacing.small)
    }

    // MARK: - Shared Subpage Helpers

    private func subpageHeader(title: String) -> some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    subpage = .root
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Tools")
                }
                .font(Theme.Fonts.rowSubtitle.weight(.semibold))
            }
            Spacer()
            Text(title)
                .font(Theme.Fonts.rowTitle.weight(.semibold))
            Spacer()
            // Balance header layout
            Color.clear.frame(width: 44, height: 1)
        }
        .padding(.top, 4)
    }

    private func colorSwatchesGrid(selected: Binding<InkColorPreset>) -> some View {
        HStack(spacing: 10) {
            ForEach(InkColorPreset.allCases) { preset in
                Button {
                    selected.wrappedValue = preset
                } label: {
                    ZStack {
                        Circle()
                            .fill(preset.swiftUIColor)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.25), lineWidth: 1)
                            )
                        if selected.wrappedValue == preset {
                            Circle()
                                .stroke(Color.accentColor, lineWidth: 2.5)
                                .frame(width: 32, height: 32)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(preset.displayName)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 2)
    }
}
