//
//  PencilCanvasScrollView.swift
//  Notes
//
//  Responsibility: UIKit wrapper (`UIViewRepresentable`) hosting an A4 portrait `PKCanvasView` (595 x 842 pt) inside a zoomable/pannable `UIScrollView` (1x to 5x zoom, double-tap to reset).
//  Design notes:
//    - Paper background (`PaperBackgroundView` via `UIHostingController`) sits behind the transparent `PKCanvasView` inside the same zoom container view so paper and ink zoom together, while paper is never drawn into `PKDrawing`.
//    - Uses `PKCanvasView.tool` and `PKCanvasView.isRulerActive` driven by `DrawingToolState` (hiding Apple's floating `PKToolPicker` palette).
//    - Sharp Zoom Rendering: When `UIScrollView` scales `pageContainerView` up to `zoomScale`, UIKit does not automatically increase the backing raster scale of sublayers, which makes strokes and paper lines look blurry when zoomed in. In `scrollViewDidZoom` and `scrollViewDidEndZooming`, we update `contentScaleFactor` (screenScale * zoomScale) on the canvas, paper view, and their sublayers so strokes and rule lines stay crisp up to 5x zoom.
//    - Apple Pencil Double-Tap: Attaches a `UIPencilInteraction` to the canvas view so double-tapping the Apple Pencil switches to Rubber (Eraser) and back.
//    - Input Policy & Navigation:
//      * When `toolState.allowsFingerDrawing == false` (Pencil-only mode): `drawingPolicy = .pencilOnly`, 1-finger pans/scrolls, and 1-finger horizontal swipes turn pages.
//      * When `toolState.allowsFingerDrawing == true` (Draw with Finger mode): `drawingPolicy = .anyInput`, 1-finger draws on the canvas, and 2-finger pan/pinch/swipe navigates and turns pages.
//      * Also observes Apple Pencil touch/hover (`PencilPresenceMonitorGestureRecognizer`) so if the user touches or hovers with an Apple Pencil while in Finger mode, `onPencilDetected` can automatically switch back to Pencil-only mode.
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
    public let onPencilDetected: () -> Void
    public var onSwipeToNextPage: (() -> Void)?
    public var onSwipeToPreviousPage: (() -> Void)?

    public static let minimumZoomScale: CGFloat = 1.0
    public static let maximumZoomScale: CGFloat = 5.0

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
        onPencilDetected: @escaping () -> Void = {},
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
        self.onPencilDetected = onPencilDetected
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

        // 2. Transparent PKCanvasView layer on top of paper
        let canvasView = PKCanvasView(frame: pageContainer.bounds)
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isScrollEnabled = false // Outer UIScrollView handles scrolling and zooming
        canvasView.delegate = context.coordinator
        pageContainer.addSubview(canvasView)

        // 3. Apple Pencil double-tap interaction -> switch to Rubber (Eraser) and back
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvasView.addInteraction(pencilInteraction)

        // 4. Passive Apple Pencil touch detector so if the user draws with Apple Pencil while in Finger mode, we know the Pencil is active
        let pencilDetector = PencilTouchDetectorGestureRecognizer(onPencilTouch: {
            context.coordinator.parent.onPencilDetected()
        })
        pencilDetector.cancelsTouchesInView = false
        pencilDetector.delaysTouchesBegan = false
        pencilDetector.delaysTouchesEnded = false
        canvasView.addGestureRecognizer(pencilDetector)

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

        // Horizontal page-turn swipe recognizers (1-finger in Pencil mode, 2-finger in Finger-drawing mode)
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
        context.coordinator.swipeLeftRecognizer = swipeLeft
        context.coordinator.swipeRightRecognizer = swipeRight

        context.coordinator.loadPageIfNeeded(pageID: pageID, data: initialDrawingData)
        context.coordinator.applyToolState(toolState, to: canvasView, scrollView: scrollView)

        return scrollView
    }

    public func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.paperHostingController?.rootView = PaperBackgroundView(paperType: paperType)
        context.coordinator.loadPageIfNeeded(pageID: pageID, data: initialDrawingData)
        if let canvasView = context.coordinator.canvasView {
            context.coordinator.applyToolState(toolState, to: canvasView, scrollView: scrollView)
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
        weak var swipeLeftRecognizer: UISwipeGestureRecognizer?
        weak var swipeRightRecognizer: UISwipeGestureRecognizer?

        private var currentLoadedPageID: UUID?
        private var isProgrammaticDrawingUpdate = false
        private var previousDrawingSnapshot = PKDrawing()
        private var lastHandledUndoTriggerCount: Int = 0
        private var lastHandledRedoTriggerCount: Int = 0

        init(parent: PencilCanvasScrollView) {
            self.parent = parent
            self.lastHandledUndoTriggerCount = parent.undoTriggerCount
            self.lastHandledRedoTriggerCount = parent.redoTriggerCount
        }

        // MARK: - Tool State & Input Policy

        func applyToolState(_ state: DrawingToolState, to canvasView: PKCanvasView, scrollView: UIScrollView) {
            // 1. Construct the PKTool from DrawingToolState
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

            // 2. Toggle PencilKit's native ruler overlay
            if canvasView.isRulerActive != state.isRulerActive {
                canvasView.isRulerActive = state.isRulerActive
            }

            // 3. Input policy:
            //    - Pencil-only mode (allowsFingerDrawing == false): Pencil draws; 1-finger pans/swipes.
            //    - Finger-drawing mode (allowsFingerDrawing == true): 1-finger draws; 2-fingers pan/swipe.
            let targetPolicy: PKCanvasViewDrawingPolicy = state.allowsFingerDrawing ? .anyInput : .pencilOnly
            if canvasView.drawingPolicy != targetPolicy {
                canvasView.drawingPolicy = targetPolicy
            }

            let minTouchesForNav = state.minimumTouchCountForNavigationSwipes
            if scrollView.panGestureRecognizer.minimumNumberOfTouches != minTouchesForNav {
                scrollView.panGestureRecognizer.minimumNumberOfTouches = minTouchesForNav
            }
            swipeLeftRecognizer?.numberOfTouchesRequired = minTouchesForNav
            swipeRightRecognizer?.numberOfTouchesRequired = minTouchesForNav
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
            // Fallback for older iOS delegate signature if invoked
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
            if let scrollView {
                updateSharpRenderingScale(for: scrollView.zoomScale)
            }
            if !canvasView.isFirstResponder {
                DispatchQueue.main.async {
                    canvasView.becomeFirstResponder()
                    self.notifyUndoState(for: canvasView)
                }
            } else {
                notifyUndoState(for: canvasView)
            }
        }

        // MARK: - UIScrollViewDelegate & Sharp Zoom Rendering

        public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            pageContainerView
        }

        public func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? CenteringScrollView)?.centerPageContainer()
        }

        public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            updateSharpRenderingScale(for: scale)
        }

        /// Updates the backing raster scale of `pageContainerView`, `paperHostingController.view`, `canvasView`, and their sublayers so strokes and paper lines re-rasterize crisply when zoomed in up to 5x.
        private func updateSharpRenderingScale(for zoomScale: CGFloat) {
            let screenScale = scrollView?.window?.screen.scale ?? UIScreen.main.scale
            let clampedZoom = min(max(zoomScale, 1.0), PencilCanvasScrollView.maximumZoomScale)
            let effectiveScale = screenScale * clampedZoom

            if let pageContainerView {
                Self.applyContentScaleRecursively(effectiveScale, to: pageContainerView)
            }
            canvasView?.setNeedsDisplay()
            paperHostingController?.view.setNeedsDisplay()
        }

        private static func applyContentScaleRecursively(_ scale: CGFloat, to view: UIView) {
            view.contentScaleFactor = scale
            view.layer.contentsScale = scale
            for sublayer in view.layer.sublayers ?? [] {
                sublayer.contentsScale = scale
                sublayer.setNeedsDisplay()
            }
            for subview in view.subviews {
                applyContentScaleRecursively(scale, to: subview)
            }
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1.0, animated: true)
                updateSharpRenderingScale(for: 1.0)
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

/// Passive touch observer that detects when an Apple Pencil (`.pencil`) touches the canvas without consuming or delaying any touches.
final class PencilTouchDetectorGestureRecognizer: UIGestureRecognizer {
    private let onPencilTouch: () -> Void

    init(onPencilTouch: @escaping () -> Void) {
        self.onPencilTouch = onPencilTouch
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if touches.contains(where: { $0.type == .pencil }) {
            onPencilTouch()
        }
        state = .failed
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
