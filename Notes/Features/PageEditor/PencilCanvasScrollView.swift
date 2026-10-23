//
//  PencilCanvasScrollView.swift
//  Notes
//
//  Responsibility: UIKit wrapper (`UIViewRepresentable`) hosting an A4 portrait `PKCanvasView` (595 x 842 pt) inside a zoomable/pannable `UIScrollView` (1x to 5x zoom, double-tap to reset).
//  Design notes:
//    - Paper background (`PaperBackgroundView` via `UIHostingController`) sits behind the transparent `PKCanvasView` inside the same zoom container view so paper and ink zoom together, while paper is never drawn into `PKDrawing`.
//    - Uses `.pencilOnly` drawing policy exactly as in the working baseline, with `PKCanvasView.tool` and `PKCanvasView.isRulerActive` driven by `DrawingToolState`.
//    - Ruler overlay: When `UIScrollView` zooms `pageContainerView`, we re-assert `canvasView.isRulerActive` and slightly scale down any internal PencilKit ruler view by ~25% so it doesn't disappear on zoom or look oversized.
//    - Sharp Zoom Rendering: On zoom completion, updates `contentScaleFactor` on the paper background view only (never mutating `PKCanvasView`'s internal subviews/layers, which breaks Apple Pencil stroke delivery).
//  Dependencies: SwiftUI, UIKit, PencilKit, Domain, DesignSystem.
//

import PencilKit
import SwiftUI
import UIKit

public struct PencilCanvasScrollView: UIViewRepresentable {
    public let pageID: UUID
    public let paperType: PaperType
    public let initialDrawingData: Data?
    public let toolState: DrawingToolState
    public let isScribbleToEraseEnabled: Bool
    public let undoTriggerCount: Int
    public let redoTriggerCount: Int
    public let onDrawingChanged: (Data) -> Void
    public let onUndoStateChanged: (Bool, Bool) -> Void
    public let onPencilDoubleTap: () -> Void
    public var onSwipeToNextPage: (() -> Void)?
    public var onSwipeToPreviousPage: (() -> Void)?

    public static let minimumZoomScale: CGFloat = 1.0
    public static let maximumZoomScale: CGFloat = 5.0
    public static let rulerScaleFactor: CGFloat = 0.75

    public init(
        pageID: UUID,
        paperType: PaperType,
        initialDrawingData: Data?,
        toolState: DrawingToolState,
        isScribbleToEraseEnabled: Bool,
        undoTriggerCount: Int = 0,
        redoTriggerCount: Int = 0,
        onDrawingChanged: @escaping (Data) -> Void,
        onUndoStateChanged: @escaping (Bool, Bool) -> Void = { _, _ in },
        onPencilDoubleTap: @escaping () -> Void = {},
        onSwipeToNextPage: (() -> Void)? = nil,
        onSwipeToPreviousPage: (() -> Void)? = nil
    ) {
        self.pageID = pageID
        self.paperType = paperType
        self.initialDrawingData = initialDrawingData
        self.toolState = toolState
        self.isScribbleToEraseEnabled = isScribbleToEraseEnabled
        self.undoTriggerCount = undoTriggerCount
        self.redoTriggerCount = redoTriggerCount
        self.onDrawingChanged = onDrawingChanged
        self.onUndoStateChanged = onUndoStateChanged
        self.onPencilDoubleTap = onPencilDoubleTap
        self.onSwipeToNextPage = onSwipeToNextPage
        self.onSwipeToPreviousPage = onSwipeToPreviousPage
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> UIScrollView {
        let scrollView = CenteringScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = Self.minimumZoomScale
        scrollView.maximumZoomScale = Self.maximumZoomScale
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.backgroundColor = UIColor.secondarySystemBackground

        // Page container at A4 portrait points (595 x 842)
        let pageContainer = UIView(frame: CGRect(origin: .zero, size: PageGeometry.a4Size))
        pageContainer.backgroundColor = UIColor.systemBackground
        pageContainer.layer.cornerRadius = Theme.CornerRadius.page
        pageContainer.layer.borderWidth = 1.0
        pageContainer.layer.borderColor = UIColor.separator.cgColor
        pageContainer.layer.shadowColor = UIColor.black.cgColor
        pageContainer.layer.shadowOpacity = 0.12
        pageContainer.layer.shadowRadius = 8
        pageContainer.layer.shadowOffset = CGSize(width: 0, height: 4)

        // 1. Background paper layer (SwiftUI PaperBackgroundView)
        let paperHost = UIHostingController(rootView: PaperBackgroundView(paperType: paperType))
        paperHost.view.frame = pageContainer.bounds
        paperHost.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        paperHost.view.layer.cornerRadius = Theme.CornerRadius.page
        paperHost.view.clipsToBounds = true
        paperHost.view.isUserInteractionEnabled = false
        pageContainer.addSubview(paperHost.view)

        // 2. Transparent PKCanvasView layer on top of paper (exact working setup)
        let canvasView = PKCanvasView(frame: pageContainer.bounds)
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .pencilOnly
        canvasView.isScrollEnabled = false // Outer UIScrollView handles scrolling and zooming
        canvasView.delegate = context.coordinator
        pageContainer.addSubview(canvasView)

        // 3. Apple Pencil double-tap interaction -> switch to Rubber (Eraser) and back
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvasView.addInteraction(pencilInteraction)

        scrollView.addSubview(pageContainer)
        scrollView.pageContainerView = pageContainer
        scrollView.contentSize = PageGeometry.a4Size

        // Double-tap with finger to reset zoom to 1x
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.addGestureRecognizer(doubleTap)

        // Finger swipe left -> next / new page; finger swipe right -> previous page
        let swipeRight = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleHorizontalSwipe(_:))
        )
        swipeRight.direction = .right
        swipeRight.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        swipeRight.delegate = context.coordinator
        scrollView.addGestureRecognizer(swipeRight)

        let swipeLeft = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleHorizontalSwipe(_:))
        )
        swipeLeft.direction = .left
        swipeLeft.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        swipeLeft.delegate = context.coordinator
        scrollView.addGestureRecognizer(swipeLeft)

        context.coordinator.scrollView = scrollView
        context.coordinator.pageContainerView = pageContainer
        context.coordinator.paperHostingController = paperHost
        context.coordinator.canvasView = canvasView

        context.coordinator.loadPageIfNeeded(pageID: pageID, data: initialDrawingData)
        context.coordinator.applyToolState(toolState, to: canvasView)

        return scrollView
    }

    public func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.paperHostingController?.rootView = PaperBackgroundView(paperType: paperType)
        context.coordinator.loadPageIfNeeded(pageID: pageID, data: initialDrawingData)
        if let canvasView = context.coordinator.canvasView {
            context.coordinator.applyToolState(toolState, to: canvasView)
            context.coordinator.handleUndoRedoTriggersIfNeeded(
                undoTriggerCount: undoTriggerCount,
                redoTriggerCount: redoTriggerCount,
                on: canvasView
            )
        }
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
        var parent: PencilCanvasScrollView
        weak var scrollView: CenteringScrollView?
        weak var pageContainerView: UIView?
        var paperHostingController: UIHostingController<PaperBackgroundView>?
        weak var canvasView: PKCanvasView?

        private var currentLoadedPageID: UUID?
        private var isProgrammaticDrawingUpdate = false
        private var previousDrawingSnapshot = PKDrawing()
        private var lastAppliedToolState: DrawingToolState?
        private var lastHandledUndoTriggerCount: Int = 0
        private var lastHandledRedoTriggerCount: Int = 0

        init(parent: PencilCanvasScrollView) {
            self.parent = parent
            self.lastHandledUndoTriggerCount = parent.undoTriggerCount
            self.lastHandledRedoTriggerCount = parent.redoTriggerCount
        }

        // MARK: - Tool State

        func applyToolState(_ state: DrawingToolState, to canvasView: PKCanvasView) {
            if canvasView.drawingPolicy != .pencilOnly {
                canvasView.drawingPolicy = .pencilOnly
            }

            if lastAppliedToolState != state {
                lastAppliedToolState = state

                let pkTool: PKTool
                switch state.activeTool {
                case .pen:
                    let color = state.penColor.uiColor(opacity: state.penOpacity)
                    pkTool = PKInkingTool(.pen, color: color, width: state.penWidth)
                case .highlighter:
                    let color = state.highlighterColor.uiColor(opacity: state.highlighterOpacity)
                    pkTool = PKInkingTool(.marker, color: color, width: state.highlighterWidth)
                case .eraser:
                    switch state.eraserMode {
                    case .object:
                        pkTool = PKEraserTool(.vector)
                    case .pixel:
                        pkTool = PKEraserTool(.bitmap, width: state.eraserWidth)
                    }
                }
                canvasView.tool = pkTool
            }

            if canvasView.isRulerActive != state.isRulerActive {
                canvasView.isRulerActive = state.isRulerActive
            }
            if state.isRulerActive {
                DispatchQueue.main.async { [weak self] in
                    self?.adjustRulerScaleIfNeeded()
                }
            }
        }

        /// Keeps PencilKit's ruler visible and ~25% smaller (`0.75x`) when active.
        private func adjustRulerScaleIfNeeded() {
            guard let canvasView, parent.toolState.isRulerActive else { return }
            if !canvasView.isRulerActive {
                canvasView.isRulerActive = true
            }
            let zoomScale = max(scrollView?.zoomScale ?? 1.0, 1.0)
            // Keep the ruler 25% smaller than default and counter-scale when zoomed in so it stays a comfortable size on screen
            let targetScale = PencilCanvasScrollView.rulerScaleFactor / sqrt(zoomScale)
            Self.scaleRulerSubviews(in: canvasView, scale: targetScale)
        }

        private static func scaleRulerSubviews(in root: UIView, scale: CGFloat) {
            for subview in root.subviews {
                let typeName = String(describing: type(of: subview))
                if typeName.localizedCaseInsensitiveContains("Ruler") {
                    for child in subview.subviews {
                        child.layer.setValue(scale, forKeyPath: "transform.scale")
                    }
                } else {
                    scaleRulerSubviews(in: subview, scale: scale)
                }
            }
        }

        func handleUndoRedoTriggersIfNeeded(
            undoTriggerCount: Int,
            redoTriggerCount: Int,
            on canvasView: PKCanvasView
        ) {
            if undoTriggerCount != lastHandledUndoTriggerCount {
                lastHandledUndoTriggerCount = undoTriggerCount
                if canvasView.undoManager?.canUndo == true {
                    canvasView.undoManager?.undo()
                    previousDrawingSnapshot = canvasView.drawing
                    parent.onDrawingChanged(canvasView.drawing.dataRepresentation())
                    notifyUndoState(for: canvasView)
                }
            }
            if redoTriggerCount != lastHandledRedoTriggerCount {
                lastHandledRedoTriggerCount = redoTriggerCount
                if canvasView.undoManager?.canRedo == true {
                    canvasView.undoManager?.redo()
                    previousDrawingSnapshot = canvasView.drawing
                    parent.onDrawingChanged(canvasView.drawing.dataRepresentation())
                    notifyUndoState(for: canvasView)
                }
            }
        }

        private func notifyUndoState(for canvasView: PKCanvasView) {
            let canUndo = canvasView.undoManager?.canUndo ?? false
            let canRedo = canvasView.undoManager?.canRedo ?? false
            DispatchQueue.main.async { [weak self] in
                self?.parent.onUndoStateChanged(canUndo, canRedo)
            }
        }

        // MARK: - Apple Pencil Double-Tap Delegate

        @available(iOS 17.5, *)
        public func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveTap tap: UIPencilInteraction.Tap
        ) {
            parent.onPencilDoubleTap()
        }

        public func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            if #unavailable(iOS 17.5) {
                parent.onPencilDoubleTap()
            }
        }

        // MARK: - Page Loading

        func loadPageIfNeeded(pageID: UUID, data: Data?) {
            guard currentLoadedPageID != pageID, let canvasView else { return }
            currentLoadedPageID = pageID
            isProgrammaticDrawingUpdate = true
            defer { isProgrammaticDrawingUpdate = false }

            if let data, let decoded = try? PKDrawing(data: data) {
                canvasView.drawing = decoded
                previousDrawingSnapshot = decoded
            } else {
                let empty = PKDrawing()
                canvasView.drawing = empty
                previousDrawingSnapshot = empty
            }
            canvasView.undoManager?.removeAllActions()
            scrollView?.setZoomScale(1.0, animated: false)
            DispatchQueue.main.async { [weak self] in
                guard let self, let canvas = self.canvasView else { return }
                canvas.becomeFirstResponder()
                self.notifyUndoState(for: canvas)
            }
        }

        // MARK: - UIScrollViewDelegate

        public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            pageContainerView
        }

        public func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? CenteringScrollView)?.centerPageContainer()
            if parent.toolState.isRulerActive {
                adjustRulerScaleIfNeeded()
            }
        }

        public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            // Re-render paper background crisply at the new zoom scale (without touching PKCanvasView's internal sublayers)
            let screenScale = scrollView.window?.screen.scale ?? UIScreen.main.scale
            let clampedZoom = min(max(scale, 1.0), PencilCanvasScrollView.maximumZoomScale)
            if let paperView = paperHostingController?.view {
                paperView.contentScaleFactor = screenScale * clampedZoom
                paperView.setNeedsDisplay()
            }
            if parent.toolState.isRulerActive {
                adjustRulerScaleIfNeeded()
            }
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let location = recognizer.location(in: pageContainerView)
                let zoomRect = CGRect(
                    x: location.x - 100,
                    y: location.y - 100,
                    width: 200,
                    height: 200
                )
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }

        @objc func handleHorizontalSwipe(_ recognizer: UISwipeGestureRecognizer) {
            guard let scrollView, scrollView.zoomScale <= 1.05 else { return }
            switch recognizer.direction {
            case .left:
                parent.onSwipeToNextPage?()
            case .right:
                parent.onSwipeToPreviousPage?()
            default:
                break
            }
        }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if gestureRecognizer is UISwipeGestureRecognizer {
                return true
            }
            return false
        }

        public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer is UISwipeGestureRecognizer {
                guard let scrollView else { return false }
                return scrollView.zoomScale <= 1.05
            }
            return true
        }

        // MARK: - PKCanvasViewDelegate & Scribble-to-Erase

        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isProgrammaticDrawingUpdate else { return }

            let currentDrawing = canvasView.drawing
            let priorDrawing = previousDrawingSnapshot

            // Check if exactly one new stroke was added on top of existing strokes
            if parent.isScribbleToEraseEnabled,
               parent.toolState.activeTool != .eraser,
               currentDrawing.strokes.count == priorDrawing.strokes.count + 1,
               !priorDrawing.strokes.isEmpty,
               let latestStroke = currentDrawing.strokes.last {

                let newStrokePoints = samplePoints(from: latestStroke.path)
                let existingTargets: [ExistingStrokeTarget] = priorDrawing.strokes.enumerated().map { index, stroke in
                    ExistingStrokeTarget(
                        id: index,
                        bounds: stroke.renderBounds,
                        samplePoints: samplePoints(from: stroke.path, maxSamples: 24)
                    )
                }

                let classification = ScribbleClassifier.classify(
                    stroke: StrokeSample(points: newStrokePoints),
                    existingStrokes: existingTargets,
                    isEnabled: parent.isScribbleToEraseEnabled
                )

                if classification.isScribbleErase {
                    let erasedSet = Set(classification.erasedStrokeIDs)
                    let survivingStrokes = priorDrawing.strokes.enumerated().compactMap { index, stroke in
                        erasedSet.contains(index) ? nil : stroke
                    }
                    let postEraseDrawing = PKDrawing(strokes: survivingStrokes)

                    // Apply as a single undoable step so Undo restores the pre-scribble strokes in one tap
                    applyUndoableDrawingReplacement(
                        from: priorDrawing,
                        to: postEraseDrawing,
                        on: canvasView,
                        actionName: "Scribble Erase"
                    )
                    return
                }
            }

            previousDrawingSnapshot = currentDrawing
            parent.onDrawingChanged(currentDrawing.dataRepresentation())
            notifyUndoState(for: canvasView)
        }

        private func applyUndoableDrawingReplacement(
            from oldDrawing: PKDrawing,
            to newDrawing: PKDrawing,
            on canvasView: PKCanvasView,
            actionName: String
        ) {
            isProgrammaticDrawingUpdate = true
            canvasView.drawing = newDrawing
            previousDrawingSnapshot = newDrawing
            isProgrammaticDrawingUpdate = false

            canvasView.undoManager?.registerUndo(withTarget: self) { coordinator in
                MainActor.assumeIsolated {
                    guard let canvas = coordinator.canvasView else { return }
                    coordinator.applyUndoableDrawingReplacement(
                        from: newDrawing,
                        to: oldDrawing,
                        on: canvas,
                        actionName: actionName
                    )
                }
            }
            canvasView.undoManager?.setActionName(actionName)
            parent.onDrawingChanged(newDrawing.dataRepresentation())
            notifyUndoState(for: canvasView)
        }

        private func samplePoints(from path: PKStrokePath, maxSamples: Int = 96) -> [CGPoint] {
            let count = path.count
            guard count > 0 else { return [] }
            if count <= maxSamples {
                return (0..<count).map { path[$0].location }
            }
            let strideStep = max(1, count / maxSamples)
            var pts: [CGPoint] = []
            var index = 0
            while index < count {
                pts.append(path[index].location)
                index += strideStep
            }
            if let last = path.last?.location, pts.last != last {
                pts.append(last)
            }
            return pts
        }
    }
}

/// `UIScrollView` subclass that keeps the A4 page centered with comfortable margins at any zoom scale.
final class CenteringScrollView: UIScrollView {
    weak var pageContainerView: UIView?
    private let workspaceMargin: CGFloat = Theme.Spacing.xLarge

    override func layoutSubviews() {
        super.layoutSubviews()
        centerPageContainer()
    }

    func centerPageContainer() {
        guard let pageContainerView else { return }
        let boundsSize = bounds.size
        let frameToCenter = pageContainerView.frame

        let horizontalInset = max(workspaceMargin, (boundsSize.width - frameToCenter.width) * 0.5)
        let verticalInset = max(workspaceMargin, (boundsSize.height - frameToCenter.height) * 0.5)

        contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }
}
