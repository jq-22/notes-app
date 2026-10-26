//
//  LassoSelectionOverlayView.swift
//  Notes
//
//  Responsibility: Freehand Lasso drawing and selection overlay on the A4 page.
//  Allows the user to:
//    1. Draw a closed freehand loop around any combination of ink strokes and `PageObject`s.
//    2. Drag inside the resulting selection box to move all lassoed strokes and objects together.
//    3. Use the floating action bar to Copy, Cut, Recolour, Convert to Resizable Object, or Delete the selection.
//  Dependencies: SwiftUI, CoreGraphics, Domain (LassoPolygon, ActiveLassoSelection, InkColorPreset, PageGeometry).
//

import CoreGraphics
import SwiftUI

public struct LassoSelectionOverlayView: View {
    public let isLassoToolActive: Bool
    public let activeSelection: ActiveLassoSelection?
    public let onCompleteLassoLoop: (LassoPolygon) -> Void
    public let onTranslateSelection: (CGSize) -> Void
    public let onCopySelection: () -> Void
    public let onCutSelection: () -> Void
    public let onRecolorSelection: (InkColorPreset) -> Void
    public let onConvertStrokesToObject: () -> Void
    public let onSaveStrokesToLibrary: () -> Void
    public let onDeleteSelection: () -> Void
    public let onClearSelection: () -> Void

    @State private var currentLassoPoints: [CGPoint] = []
    @State private var liveTranslation: CGSize = .zero
    @State private var isDraggingSelectionBox: Bool = false

    private static let coordinateSpaceName = "A4LassoCoordinateSpace"

    public init(
        isLassoToolActive: Bool,
        activeSelection: ActiveLassoSelection?,
        onCompleteLassoLoop: @escaping (LassoPolygon) -> Void,
        onTranslateSelection: @escaping (CGSize) -> Void,
        onCopySelection: @escaping () -> Void,
        onCutSelection: @escaping () -> Void,
        onRecolorSelection: @escaping (InkColorPreset) -> Void,
        onConvertStrokesToObject: @escaping () -> Void,
        onSaveStrokesToLibrary: @escaping () -> Void = {},
        onDeleteSelection: @escaping () -> Void,
        onClearSelection: @escaping () -> Void
    ) {
        self.isLassoToolActive = isLassoToolActive
        self.activeSelection = activeSelection
        self.onCompleteLassoLoop = onCompleteLassoLoop
        self.onTranslateSelection = onTranslateSelection
        self.onCopySelection = onCopySelection
        self.onCutSelection = onCutSelection
        self.onRecolorSelection = onRecolorSelection
        self.onConvertStrokesToObject = onConvertStrokesToObject
        self.onSaveStrokesToLibrary = onSaveStrokesToLibrary
        self.onDeleteSelection = onDeleteSelection
        self.onClearSelection = onClearSelection
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if isLassoToolActive {
                // Background canvas surface for drawing a new lasso loop (or tapping to clear an existing selection)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if activeSelection != nil {
                            onClearSelection()
                        }
                    }
                    .gesture(drawLassoGesture)
            }

            // Live freehand lasso path while dragging
            if currentLassoPoints.count >= 2 {
                Canvas { context, _ in
                    var path = Path()
                    path.move(to: currentLassoPoints[0])
                    for pt in currentLassoPoints.dropFirst() {
                        path.addLine(to: pt)
                    }
                    path.closeSubpath()

                    context.fill(path, with: .color(Color.accentColor.opacity(0.09)))
                    context.stroke(
                        path,
                        with: .color(Color.accentColor),
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round, dash: [6, 5])
                    )
                }
                .allowsHitTesting(false)
            }

            // Active selection bounding box + floating action bar
            if let selection = activeSelection, !selection.isEmpty {
                let displayedRect = selection.selectionBounds
                    .insetBy(dx: -8, dy: -8)
                    .offsetBy(dx: liveTranslation.width, dy: liveTranslation.height)

                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.06))
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [6, 4])
                        )
                }
                .frame(width: Swift.max(24, displayedRect.width), height: Swift.max(24, displayedRect.height))
                .contentShape(Rectangle())
                .position(x: displayedRect.midX, y: displayedRect.midY)
                .gesture(moveSelectionBoxGesture)

                if !isDraggingSelectionBox {
                    floatingLassoToolbar(around: displayedRect, hasStrokes: !selection.strokeIndices.isEmpty)
                }
            }
        }
        .frame(width: PageGeometry.a4Width, height: PageGeometry.a4Height, alignment: .topLeading)
        .coordinateSpace(name: Self.coordinateSpaceName)
    }

    @ViewBuilder
    private func floatingLassoToolbar(around rect: CGRect, hasStrokes: Bool) -> some View {
        let clampedX = Swift.min(Swift.max(rect.midX, 175), PageGeometry.a4Width - 175)
        let preferredBottomY = rect.maxY + 26
        let toolbarY = (preferredBottomY < PageGeometry.a4Height - 36)
            ? preferredBottomY
            : Swift.max(36, rect.minY - 36)

        HStack(spacing: 8) {
            // Quick recolour swatches
            ForEach(InkColorPreset.allCases) { preset in
                Button {
                    onRecolorSelection(preset)
                } label: {
                    Circle()
                        .fill(preset.swiftUIColor)
                        .frame(width: 17, height: 17)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.28), lineWidth: 1.0)
                        )
                }
                .buttonStyle(.plain)
                .help("Recolour Selection (\(preset.displayName))")
            }

            Divider()
                .frame(height: 18)

            Button {
                onCopySelection()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Copy Selection")

            Button {
                onCutSelection()
            } label: {
                Image(systemName: "scissors")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Cut Selection")

            if hasStrokes {
                Button {
                    onConvertStrokesToObject()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Resize / Rotate as Object")

                Button {
                    onSaveStrokesToLibrary()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Save to Shape Library")
            }

            Button(role: .destructive) {
                onDeleteSelection()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Delete Selection")

            Button {
                onClearSelection()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Done")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.16), radius: 6, x: 0, y: 2)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color(uiColor: .separator), lineWidth: 0.8)
        )
        .position(x: clampedX, y: toolbarY)
    }

    private var drawLassoGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if currentLassoPoints.isEmpty {
                    if activeSelection != nil {
                        onClearSelection()
                    }
                    currentLassoPoints = [value.startLocation, value.location]
                } else if let last = currentLassoPoints.last,
                          hypot(value.location.x - last.x, value.location.y - last.y) >= 3.0 {
                    currentLassoPoints.append(value.location)
                }
            }
            .onEnded { _ in
                let completedPoints = currentLassoPoints
                currentLassoPoints = []
                let polygon = LassoPolygon(points: completedPoints)
                if polygon.isValidLoop {
                    onCompleteLassoLoop(polygon)
                }
            }
    }

    private var moveSelectionBoxGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                isDraggingSelectionBox = true
                liveTranslation = value.translation
            }
            .onEnded { value in
                isDraggingSelectionBox = false
                let delta = value.translation
                liveTranslation = .zero
                if abs(delta.width) > 0.5 || abs(delta.height) > 0.5 {
                    onTranslateSelection(delta)
                }
            }
    }
}
