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
    public let objects: [PageObject]
    public let selectedObjectID: UUID?
    public let isInteractive: Bool
    public let assetDataProvider: (UUID) -> Data?
    public let onSelectObject: (UUID?) -> Void
    public let onUpdateObjectLive: (PageObject) -> Void
    public let onCommitObjectsChange: ([PageObject], [PageObject]) -> Void
    public let onCopyObject: (UUID) -> Void
    public let onDuplicateObject: (UUID) -> Void
    public let onDeleteObject: (UUID) -> Void

    @State private var dragStartObject: PageObject?
    @State private var dragStartAllObjects: [PageObject]?
    @State private var isActivelyDraggingHandle: Bool = false

    private static let coordinateSpaceName = "A4PageCoordinateSpace"
    private static let rotateHandleLength: CGFloat = 28.0
    private static let cornerDotDiameter: CGFloat = 13.0
    private static let cornerHitTargetSize: CGFloat = 34.0

    public init(
        objects: [PageObject],
        selectedObjectID: UUID? = nil,
        isInteractive: Bool = false,
        assetDataProvider: @escaping (UUID) -> Data?,
        onSelectObject: @escaping (UUID?) -> Void = { _ in },
        onUpdateObjectLive: @escaping (PageObject) -> Void = { _ in },
        onCommitObjectsChange: @escaping ([PageObject], [PageObject]) -> Void = { _, _ in },
        onCopyObject: @escaping (UUID) -> Void = { _ in },
        onDuplicateObject: @escaping (UUID) -> Void = { _ in },
        onDeleteObject: @escaping (UUID) -> Void = { _ in }
    ) {
        self.objects = objects
        self.selectedObjectID = selectedObjectID
        self.isInteractive = isInteractive
        self.assetDataProvider = assetDataProvider
        self.onSelectObject = onSelectObject
        self.onUpdateObjectLive = onUpdateObjectLive
        self.onCommitObjectsChange = onCommitObjectsChange
        self.onCopyObject = onCopyObject
        self.onDuplicateObject = onDuplicateObject
        self.onDeleteObject = onDeleteObject
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
            // Transparent background tap catcher when in interactive object mode so tapping empty space deselects
            if isInteractive {
                Color.clear
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
    }

    @ViewBuilder
    private func objectItemView(for object: PageObject, isSelected: Bool) -> some View {
        ZStack {
            // 1. Visual content of the object inside its local width x height
            PageObjectContentView(object: object, assetDataProvider: assetDataProvider)
                .frame(width: object.width, height: object.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isInteractive else { return }
                    onSelectObject(object.id)
                }
                .gesture(
                    isInteractive ? moveGesture(for: object) : nil
                )

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
                // Rectangle border to move
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.8)
                    .frame(width: object.width, height: object.height)
                    .allowsHitTesting(false)

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

                // Four corner dots to resize
                cornerHandleDot(for: object, corner: .topLeft)
                    .offset(x: -object.width * 0.5, y: -object.height * 0.5)

                cornerHandleDot(for: object, corner: .topRight)
                    .offset(x: object.width * 0.5, y: -object.height * 0.5)

                cornerHandleDot(for: object, corner: .bottomLeft)
                    .offset(x: -object.width * 0.5, y: object.height * 0.5)

                cornerHandleDot(for: object, corner: .bottomRight)
                    .offset(x: object.width * 0.5, y: object.height * 0.5)
            }
        }
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

    @ViewBuilder
    private func floatingContextToolbar(for object: PageObject) -> some View {
        let clampedX = Swift.min(Swift.max(object.center.x, 150), PageGeometry.a4Width - 150)
        let preferredBottomY = object.frame.maxY + 26
        let toolbarY = (preferredBottomY < PageGeometry.a4Height - 36)
            ? preferredBottomY
            : Swift.max(36, object.frame.minY - 46)

        HStack(spacing: 8) {
            if canRecolor(object) {
                ForEach(InkColorPreset.allCases) { preset in
                    Button {
                        let before = objects
                        let updated = object.recolored(to: preset)
                        onUpdateObjectLive(updated)
                        let after = objects.map { $0.id == updated.id ? updated : $0 }
                        onCommitObjectsChange(before, after)
                    } label: {
                        Circle()
                            .fill(preset.swiftUIColor)
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
                }

                Divider()
                    .frame(height: 18)
            }

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

    private func canRecolor(_ object: PageObject) -> Bool {
        switch object.kind {
        case .basicShape, .strokeGroup:
            return true
        case .image:
            return false
        }
    }

    private func isCurrentColor(_ preset: InkColorPreset, on object: PageObject) -> Bool {
        switch object.kind {
        case .basicShape(_, let color, _):
            return color == preset
        case .strokeGroup(_, _, _, let tint):
            return tint == preset
        case .image:
            return false
        }
    }

    // MARK: - Gestures (Move, 4-Corner Resize, Rotate)

    private func moveGesture(for object: PageObject) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if dragStartObject == nil {
                    dragStartObject = object
                    dragStartAllObjects = objects
                    isActivelyDraggingHandle = true
                    if selectedObjectID != object.id {
                        onSelectObject(object.id)
                    }
                }
                guard let initial = dragStartObject else { return }
                let updated = initial.moved(by: value.translation)
                onUpdateObjectLive(updated)
            }
            .onEnded { value in
                defer {
                    dragStartObject = nil
                    dragStartAllObjects = nil
                    isActivelyDraggingHandle = false
                }
                guard let initial = dragStartObject, let before = dragStartAllObjects else { return }
                let finalObj = initial.moved(by: value.translation)
                onUpdateObjectLive(finalObj)
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
                    dragStartObject = object
                    dragStartAllObjects = objects
                    isActivelyDraggingHandle = true
                }
                guard let initial = dragStartObject else { return }
                let updated = initial.resized(corner: corner, pageDelta: value.translation)
                onUpdateObjectLive(updated)
            }
            .onEnded { value in
                defer {
                    dragStartObject = nil
                    dragStartAllObjects = nil
                    isActivelyDraggingHandle = false
                }
                guard let initial = dragStartObject, let before = dragStartAllObjects else { return }
                let finalObj = initial.resized(corner: corner, pageDelta: value.translation)
                onUpdateObjectLive(finalObj)
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
                onUpdateObjectLive(updated)
            }
            .onEnded { value in
                defer {
                    dragStartObject = nil
                    dragStartAllObjects = nil
                    isActivelyDraggingHandle = false
                }
                guard let initial = dragStartObject, let before = dragStartAllObjects else { return }
                let finalObj = initial.resizedEndpoint(endpoint, pageDelta: value.translation)
                onUpdateObjectLive(finalObj)
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
                    dragStartObject = object
                    dragStartAllObjects = objects
                    isActivelyDraggingHandle = true
                }
                guard let initial = dragStartObject else { return }
                let updated = initial.rotated(toward: value.location)
                onUpdateObjectLive(updated)
            }
            .onEnded { value in
                defer {
                    dragStartObject = nil
                    dragStartAllObjects = nil
                    isActivelyDraggingHandle = false
                }
                guard let initial = dragStartObject, let before = dragStartAllObjects else { return }
                let finalObj = initial.rotated(toward: value.location)
                onUpdateObjectLive(finalObj)
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
                let shading = GraphicsContext.Shading.color(strokeColor.swiftUIColor)

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
