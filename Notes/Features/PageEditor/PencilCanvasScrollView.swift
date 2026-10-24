//
//  PencilCanvasScrollView.swift
//  Notes
//
//  Responsibility: UIKit wrapper (`UIViewRepresentable`) hosting an A4 portrait `PKCanvasView` (595 x 842 pt) inside a zoomable/pannable `UIScrollView`.
//  Design notes:
//    - Paper background (`PaperBackgroundView` via `UIHostingController`) sits behind the transparent `PKCanvasView` inside the same zoom container view so paper and ink zoom together, while paper is never drawn into `PKDrawing`.
//    - Default Fit-to-Screen & Snap-to-Width:
//      * On initial layout and orientation/sidebar resize, sizes the page to fill the iPad viewport (`PageGeometry.defaultInitialZoomScale`) instead of leaving it at a tiny 1.0x box.
//      * When pinching near the Fit-to-Width scale (`±8%`), snaps cleanly to `fitWidthZoomScale` in both Portrait and Landscape.
//      * Double-tap toggles between Fit-to-Width and Fit-Whole-Page.
//    - Swipe Page Turning at Any Zoom + Slide Animation:
//      * Swiping left/right turns pages not only at base zoom, but also at any zoom level whenever the page fits horizontally (such as Fit-to-Width) or is scrolled to its left/right edge.
//      * Plays a smooth horizontal page-slide transition (`CATransition` `.push`) when moving to the next or previous page.
//  Dependencies: SwiftUI, UIKit, PencilKit, QuartzCore, Domain, DesignSystem.
//

import PencilKit
import QuartzCore
import SwiftUI
import UIKit

public struct PencilCanvasScrollView: UIViewRepresentable {
    public let pageID: UUID
    public let paperType: PaperType
    public let initialDrawingData: Data?
    public let pageObjects: [PageObject]
    public let selectedObjectID: UUID?
    public let toolState: DrawingToolState
    public let isScribbleToEraseEnabled: Bool
    public let undoTriggerCount: Int
    public let redoTriggerCount: Int
    public let canGoToPreviousPage: Bool
    public let assetDataProvider: (UUID) -> Data?
    public let onDrawingChanged: (Data) -> Void
    public let onSelectObject: (UUID?) -> Void
    public let onUpdateObjectLive: (PageObject) -> Void
    public let onReplaceAllObjects: ([PageObject]) -> Void
    public let onDuplicateObject: (UUID) -> Void
    public let onDeleteObject: (UUID) -> Void
    public let onUndoStateChanged: (Bool, Bool) -> Void
    public let onPencilDoubleTap: () -> Void
    public var onSwipeToNextPage: (() -> Void)?
    public var onSwipeToPreviousPage: (() -> Void)?

    public static let minimumZoomScale: CGFloat = 0.85
    public static let maximumZoomScale: CGFloat = 5.0
    public static let rulerScaleFactor: CGFloat = 0.75

    /// Minimum horizontal finger drag distance (in points) beyond the edge (or across the page) required to trigger a page turn.
    public static let pageTurnRequiredDragDistance: CGFloat = 115.0
    /// Minimum horizontal fling velocity (in points/sec) that can also assist a deliberate page turn when dragged at least 75 pt.
    public static let pageTurnMinimumFlingVelocity: CGFloat = 650.0
    /// Duration (in seconds) of the horizontal page-slide animation.
    public static let pageTurnAnimationDuration: CFTimeInterval = 0.42

    public init(
        pageID: UUID,
        paperType: PaperType,
        initialDrawingData: Data?,
        pageObjects: [PageObject] = [],
        selectedObjectID: UUID? = nil,
        toolState: DrawingToolState,
        isScribbleToEraseEnabled: Bool,
        undoTriggerCount: Int = 0,
        redoTriggerCount: Int = 0,
        canGoToPreviousPage: Bool = false,
        assetDataProvider: @escaping (UUID) -> Data? = { _ in nil },
        onDrawingChanged: @escaping (Data) -> Void,
        onSelectObject: @escaping (UUID?) -> Void = { _ in },
        onUpdateObjectLive: @escaping (PageObject) -> Void = { _ in },
        onReplaceAllObjects: @escaping ([PageObject]) -> Void = { _ in },
        onDuplicateObject: @escaping (UUID) -> Void = { _ in },
        onDeleteObject: @escaping (UUID) -> Void = { _ in },
        onUndoStateChanged: @escaping (Bool, Bool) -> Void = { _, _ in },
        onPencilDoubleTap: @escaping () -> Void = {},
        onSwipeToNextPage: (() -> Void)? = nil,
        onSwipeToPreviousPage: (() -> Void)? = nil
    ) {
        self.pageID = pageID
        self.paperType = paperType
        self.initialDrawingData = initialDrawingData
        self.pageObjects = pageObjects
        self.selectedObjectID = selectedObjectID
        self.toolState = toolState
        self.isScribbleToEraseEnabled = isScribbleToEraseEnabled
        self.undoTriggerCount = undoTriggerCount
        self.redoTriggerCount = redoTriggerCount
        self.canGoToPreviousPage = canGoToPreviousPage
        self.assetDataProvider = assetDataProvider
        self.onDrawingChanged = onDrawingChanged
        self.onSelectObject = onSelectObject
        self.onUpdateObjectLive = onUpdateObjectLive
        self.onReplaceAllObjects = onReplaceAllObjects
        self.onDuplicateObject = onDuplicateObject
        self.onDeleteObject = onDeleteObject
        self.onUndoStateChanged = onUndoStateChanged
        self.onPencilDoubleTap = onPencilDoubleTap
        self.onSwipeToNextPage = onSwipeToNextPage
        self.onSwipeToPreviousPage = onSwipeToPreviousPage
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private var isInteractiveObjectMode: Bool {
        selectedObjectID != nil
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
        scrollView.onViewportSizeChanged = { [weak coordinator = context.coordinator] newSize in
            coordinator?.handleViewportSizeChanged(newSize)
        }

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

        // 2. PageObjects overlay layer (Basic Shapes, Images, Library/Stroke objects + unified handles)
        let objectsHost = UIHostingController(rootView: context.coordinator.makeObjectsOverlayView())
        objectsHost.view.frame = pageContainer.bounds
        objectsHost.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        objectsHost.view.backgroundColor = .clear
        objectsHost.view.isOpaque = false
        objectsHost.view.layer.cornerRadius = Theme.CornerRadius.page
        objectsHost.view.clipsToBounds = false
        objectsHost.view.isUserInteractionEnabled = isInteractiveObjectMode
        pageContainer.addSubview(objectsHost.view)

        // 3. Transparent PKCanvasView layer on top of paper (exact working setup)
        let canvasView = PKCanvasView(frame: pageContainer.bounds)
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .pencilOnly
        canvasView.isScrollEnabled = false // Outer UIScrollView handles scrolling and zooming
        canvasView.delegate = context.coordinator
        pageContainer.addSubview(canvasView)

        // 4. Apple Pencil double-tap interaction -> switch to Rubber (Eraser) and back
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvasView.addInteraction(pencilInteraction)

        scrollView.addSubview(pageContainer)
        scrollView.pageContainerView = pageContainer
        scrollView.contentSize = PageGeometry.a4Size

        // Double-tap with finger to toggle between Fit-Width and Fit-Whole-Page
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.addGestureRecognizer(doubleTap)

        // Single-tap with finger on scrollView to select a placed PageObject even when in Pen/Highlighter mode
        let singleFingerTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleFingerTap(_:))
        )
        singleFingerTap.numberOfTapsRequired = 1
        singleFingerTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        singleFingerTap.cancelsTouchesInView = false
        singleFingerTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleFingerTap)

        context.coordinator.scrollView = scrollView
        context.coordinator.pageContainerView = pageContainer
        context.coordinator.paperHostingController = paperHost
        context.coordinator.objectsHostingController = objectsHost
        context.coordinator.canvasView = canvasView

        context.coordinator.loadPageIfNeeded(pageID: pageID, data: initialDrawingData, objects: pageObjects)
        context.coordinator.syncObjectsLayerInteraction(isInteractive: isInteractiveObjectMode)
        context.coordinator.applyToolState(toolState, to: canvasView)

        return scrollView
    }

    public func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.paperHostingController?.rootView = PaperBackgroundView(paperType: paperType)
        context.coordinator.loadPageIfNeeded(pageID: pageID, data: initialDrawingData, objects: pageObjects)
        context.coordinator.recordExternalObjectAdditionOrDeletionIfNeeded(currentObjects: pageObjects)
        context.coordinator.objectsHostingController?.rootView = context.coordinator.makeObjectsOverlayView()
        context.coordinator.syncObjectsLayerInteraction(isInteractive: isInteractiveObjectMode)
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
        var objectsHostingController: UIHostingController<PageObjectsOverlayView>?
        weak var canvasView: PKCanvasView?

        private var currentLoadedPageID: UUID?
        private var isProgrammaticDrawingUpdate = false
        private var isProgrammaticObjectsUpdate = false
        private var previousDrawingSnapshot = PKDrawing()
        private var previousObjectsSnapshot: [PageObject] = []
        private var lastAppliedToolState: DrawingToolState?
        private var lastHandledUndoTriggerCount: Int = 0
        private var lastHandledRedoTriggerCount: Int = 0
        private var hasAppliedInitialZoom = false
        private var isTrackingFitWidth = true
        private var pendingTransitionSubtype: CATransitionSubtype?
        private var dragStartWasAtLeftEdge = false
        private var dragStartWasAtRightEdge = false

        init(parent: PencilCanvasScrollView) {
            self.parent = parent
            self.lastHandledUndoTriggerCount = parent.undoTriggerCount
            self.lastHandledRedoTriggerCount = parent.redoTriggerCount
            self.previousObjectsSnapshot = parent.pageObjects
        }

        func makeObjectsOverlayView() -> PageObjectsOverlayView {
            let interactive = parent.selectedObjectID != nil
            return PageObjectsOverlayView(
                objects: parent.pageObjects,
                selectedObjectID: parent.selectedObjectID,
                isInteractive: interactive,
                assetDataProvider: parent.assetDataProvider,
                onSelectObject: { [weak self] selectedID in
                    self?.parent.onSelectObject(selectedID)
                },
                onUpdateObjectLive: { [weak self] updatedObject in
                    guard let self else { return }
                    self.isProgrammaticObjectsUpdate = true
                    self.parent.onUpdateObjectLive(updatedObject)
                    self.isProgrammaticObjectsUpdate = false
                },
                onCommitObjectsChange: { [weak self] before, after in
                    self?.registerUndoForObjectChange(from: before, to: after, actionName: "Modify Object")
                },
                onDuplicateObject: { [weak self] objectID in
                    self?.parent.onDuplicateObject(objectID)
                },
                onDeleteObject: { [weak self] objectID in
                    guard let self else { return }
                    self.isProgrammaticObjectsUpdate = true
                    self.parent.onDeleteObject(objectID)
                    self.isProgrammaticObjectsUpdate = false
                }
            )
        }

        func syncObjectsLayerInteraction(isInteractive: Bool) {
            guard let pageContainerView,
                  let objectsView = objectsHostingController?.view,
                  let canvasView else { return }

            objectsView.isUserInteractionEnabled = isInteractive
            canvasView.isUserInteractionEnabled = !isInteractive

            if isInteractive {
                // Bring objectsView to front while manipulating handles so corner dots and floating bar sit above ink
                pageContainerView.bringSubviewToFront(objectsView)
            } else {
                // Keep PKCanvasView in front when drawing so Apple Pencil ink renders over objects seamlessly
                pageContainerView.bringSubviewToFront(canvasView)
            }
        }

        func recordExternalObjectAdditionOrDeletionIfNeeded(currentObjects: [PageObject]) {
            guard !isProgrammaticObjectsUpdate else {
                previousObjectsSnapshot = currentObjects
                return
            }
            if currentObjects.count != previousObjectsSnapshot.count {
                let before = previousObjectsSnapshot
                let after = currentObjects
                previousObjectsSnapshot = currentObjects
                registerUndoForObjectChange(from: before, to: after, actionName: "Object Change")
            } else {
                previousObjectsSnapshot = currentObjects
            }
        }

        private func registerUndoForObjectChange(
            from oldObjects: [PageObject],
            to newObjects: [PageObject],
            actionName: String
        ) {
            previousObjectsSnapshot = newObjects
            guard let canvasView, oldObjects != newObjects else { return }
            canvasView.undoManager?.registerUndo(withTarget: self) { coordinator in
                MainActor.assumeIsolated {
                    guard let canvas = coordinator.canvasView else { return }
                    coordinator.applyUndoableObjectsReplacement(
                        from: newObjects,
                        to: oldObjects,
                        on: canvas,
                        actionName: actionName
                    )
                }
            }
            canvasView.undoManager?.setActionName(actionName)
            notifyUndoState(for: canvasView)
        }

        private func applyUndoableObjectsReplacement(
            from oldObjects: [PageObject],
            to newObjects: [PageObject],
            on canvasView: PKCanvasView,
            actionName: String
        ) {
            isProgrammaticObjectsUpdate = true
            previousObjectsSnapshot = newObjects
            parent.onReplaceAllObjects(newObjects)
            isProgrammaticObjectsUpdate = false

            canvasView.undoManager?.registerUndo(withTarget: self) { coordinator in
                MainActor.assumeIsolated {
                    guard let canvas = coordinator.canvasView else { return }
                    coordinator.applyUndoableObjectsReplacement(
                        from: newObjects,
                        to: oldObjects,
                        on: canvas,
                        actionName: actionName
                    )
                }
            }
            canvasView.undoManager?.setActionName(actionName)
            notifyUndoState(for: canvasView)
        }

        // MARK: - Viewport Sizing & Snap-to-Width

        func handleViewportSizeChanged(_ viewportSize: CGSize) {
            guard let scrollView, viewportSize.width > 100, viewportSize.height > 100 else { return }

            let fitPage = PageGeometry.fitWholePageZoomScale(forViewportSize: viewportSize)
            scrollView.minimumZoomScale = min(0.85, fitPage)

            if !hasAppliedInitialZoom {
                hasAppliedInitialZoom = true
                isTrackingFitWidth = true
                let initialScale = PageGeometry.defaultInitialZoomScale(forViewportSize: viewportSize)
                applyZoomScaleAndScrollToTop(initialScale, on: scrollView, animated: false)
            } else if isTrackingFitWidth {
                let targetScale = PageGeometry.defaultInitialZoomScale(forViewportSize: viewportSize)
                if abs(scrollView.zoomScale - targetScale) > 0.01 {
                    scrollView.setZoomScale(targetScale, animated: true)
                    scrollView.centerPageContainer()
                }
            }
        }

        private func applyZoomScaleAndScrollToTop(_ scale: CGFloat, on scrollView: CenteringScrollView, animated: Bool) {
            let clamped = min(max(scale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
            scrollView.setZoomScale(clamped, animated: animated)
            scrollView.centerPageContainer()
            let topOffset = CGPoint(
                x: -scrollView.contentInset.left,
                y: -scrollView.contentInset.top
            )
            scrollView.setContentOffset(topOffset, animated: animated)
            updatePaperRenderScale(for: clamped, in: scrollView)
        }

        private func updatePaperRenderScale(for zoomScale: CGFloat, in scrollView: UIScrollView) {
            let screenScale = scrollView.window?.screen.scale ?? UIScreen.main.scale
            let clampedZoom = min(max(zoomScale, 1.0), PencilCanvasScrollView.maximumZoomScale)
            if let paperView = paperHostingController?.view {
                paperView.contentScaleFactor = screenScale * clampedZoom
                paperView.setNeedsDisplay()
            }
            if let objectsView = objectsHostingController?.view {
                objectsView.contentScaleFactor = screenScale * clampedZoom
                objectsView.setNeedsDisplay()
            }
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
                    pkTool = PKInkingTool(.monoline, color: color, width: state.penWidth)
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
                    if canvasView.drawing != previousDrawingSnapshot {
                        previousDrawingSnapshot = canvasView.drawing
                        parent.onDrawingChanged(canvasView.drawing.dataRepresentation())
                    }
                    notifyUndoState(for: canvasView)
                }
            }
            if redoTriggerCount != lastHandledRedoTriggerCount {
                lastHandledRedoTriggerCount = redoTriggerCount
                if canvasView.undoManager?.canRedo == true {
                    canvasView.undoManager?.redo()
                    if canvasView.drawing != previousDrawingSnapshot {
                        previousDrawingSnapshot = canvasView.drawing
                        parent.onDrawingChanged(canvasView.drawing.dataRepresentation())
                    }
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

        // MARK: - Page Loading & Slide Transition

        func loadPageIfNeeded(pageID: UUID, data: Data?, objects: [PageObject]) {
            guard currentLoadedPageID != pageID, let canvasView else { return }
            let isSwitchingFromAnotherPage = (currentLoadedPageID != nil)
            currentLoadedPageID = pageID
            isProgrammaticDrawingUpdate = true
            isProgrammaticObjectsUpdate = true
            defer {
                isProgrammaticDrawingUpdate = false
                isProgrammaticObjectsUpdate = false
            }

            // Play smooth page-slide animation when switching pages
            if isSwitchingFromAnotherPage, let pageContainerView {
                let transition = CATransition()
                transition.type = .push
                transition.subtype = pendingTransitionSubtype ?? .fromRight
                transition.duration = PencilCanvasScrollView.pageTurnAnimationDuration
                transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                pageContainerView.layer.add(transition, forKey: "pageTurnSlide")
                pendingTransitionSubtype = nil
            }

            previousObjectsSnapshot = objects

            if let data, let decoded = try? PKDrawing(data: data) {
                canvasView.drawing = decoded
                previousDrawingSnapshot = decoded
            } else {
                let empty = PKDrawing()
                canvasView.drawing = empty
                previousDrawingSnapshot = empty
            }
            canvasView.undoManager?.removeAllActions()

            // Preserve the user's current zoom scale across page turns, and scroll to the top of the new page
            if let scrollView {
                scrollView.centerPageContainer()
                let topOffset = CGPoint(
                    x: -scrollView.contentInset.left,
                    y: max(-scrollView.contentInset.top, scrollView.contentOffset.y * 0 - scrollView.contentInset.top)
                )
                scrollView.setContentOffset(topOffset, animated: false)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, let canvas = self.canvasView else { return }
                canvas.becomeFirstResponder()
                self.notifyUndoState(for: canvas)
            }
        }

        // MARK: - UIScrollViewDelegate & Snap-to-Width

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
            let viewportWidth = scrollView.bounds.width
            let fitWidth = PageGeometry.fitWidthZoomScale(forViewportWidth: viewportWidth)
            let snapped = PageGeometry.snappedZoomScale(scale, fitWidthScale: fitWidth)

            let finalScale: CGFloat
            if abs(snapped - scale) > 0.001 {
                finalScale = snapped
                isTrackingFitWidth = true
                scrollView.setZoomScale(snapped, animated: true)
                (scrollView as? CenteringScrollView)?.centerPageContainer()
            } else {
                finalScale = scale
                isTrackingFitWidth = abs(scale - fitWidth) < 0.02
            }

            updatePaperRenderScale(for: finalScale, in: scrollView)
            if parent.toolState.isRulerActive {
                adjustRulerScaleIfNeeded()
            }
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            let fitWidth = PageGeometry.fitWidthZoomScale(forViewportWidth: scrollView.bounds.width)
            let fitPage = PageGeometry.fitWholePageZoomScale(forViewportSize: scrollView.bounds.size)

            if abs(scrollView.zoomScale - fitWidth) > 0.06 {
                // Snap to Fit-Width
                isTrackingFitWidth = true
                scrollView.setZoomScale(fitWidth, animated: true)
                scrollView.centerPageContainer()
                updatePaperRenderScale(for: fitWidth, in: scrollView)
            } else {
                // Toggle down to Fit-Whole-Page
                isTrackingFitWidth = false
                scrollView.setZoomScale(fitPage, animated: true)
                scrollView.centerPageContainer()
                updatePaperRenderScale(for: fitPage, in: scrollView)
            }
        }

        @objc func handleSingleFingerTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  parent.selectedObjectID == nil,
                  let pageContainerView,
                  !parent.pageObjects.isEmpty else {
                return
            }
            let locationInPage = recognizer.location(in: pageContainerView)
            // Check from topmost object (highest zIndex) down
            let sortedTopDown = parent.pageObjects.sorted { lhs, rhs in
                if lhs.zIndex == rhs.zIndex {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.zIndex > rhs.zIndex
            }
            if let hitObject = sortedTopDown.first(where: { $0.contains(pagePoint: locationInPage, tolerance: 8.0) }) {
                parent.onSelectObject(hitObject.id)
            }
        }

        // MARK: - Deliberate Horizontal Drag Page Turning at Any Zoom

        public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            let edgeStates = horizontalEdgeStates(in: scrollView)
            dragStartWasAtLeftEdge = edgeStates.atLeftEdge
            dragStartWasAtRightEdge = edgeStates.atRightEdge
        }

        public func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            let translation = scrollView.panGestureRecognizer.translation(in: scrollView)
            let horizontalDistance = abs(translation.x)
            let verticalDistance = abs(translation.y)

            // Require a predominantly horizontal gesture (at least 1.5x more horizontal than vertical)
            guard horizontalDistance > verticalDistance * 1.5 else { return }

            let panicSpeedPtPerSec = abs(velocity.x) * 1000.0
            let meetsDistanceThreshold = horizontalDistance >= PencilCanvasScrollView.pageTurnRequiredDragDistance
            let meetsFastFlingThreshold = (horizontalDistance >= 75.0 && panicSpeedPtPerSec >= PencilCanvasScrollView.pageTurnMinimumFlingVelocity)
            guard meetsDistanceThreshold || meetsFastFlingThreshold else { return }

            if translation.x < 0 && dragStartWasAtRightEdge {
                // Dragged right-to-left (Next / New page)
                pendingTransitionSubtype = .fromRight
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onSwipeToNextPage?()
                }
            } else if translation.x > 0 && dragStartWasAtLeftEdge && parent.canGoToPreviousPage {
                // Dragged left-to-right (Previous page)
                pendingTransitionSubtype = .fromLeft
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onSwipeToPreviousPage?()
                }
            }
        }

        private func horizontalEdgeStates(in scrollView: UIScrollView) -> (atLeftEdge: Bool, atRightEdge: Bool) {
            let scaledPageWidth = PageGeometry.a4Width * scrollView.zoomScale
            let fitWidthMax = scrollView.bounds.width - (PageGeometry.viewportPadding * 1.5)

            // If the page fits horizontally (including Fit-to-Width mode), it is simultaneously at both horizontal edges
            if scaledPageWidth <= fitWidthMax + 8.0 {
                return (true, true)
            }

            let minOffsetX = -scrollView.contentInset.left
            let maxOffsetX = scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right
            let edgeTolerance: CGFloat = 20.0

            let atLeft = scrollView.contentOffset.x <= (minOffsetX + edgeTolerance)
            let atRight = scrollView.contentOffset.x >= (maxOffsetX - edgeTolerance)
            return (atLeft, atRight)
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

/// `UIScrollView` subclass that keeps the A4 page centered with comfortable margins at any zoom scale and notifies when the viewport size changes (e.g. rotation or sidebar toggle).
final class CenteringScrollView: UIScrollView {
    weak var pageContainerView: UIView?
    var onViewportSizeChanged: ((CGSize) -> Void)?
    private var lastReportedViewportSize: CGSize = .zero
    private let workspaceMargin: CGFloat = PageGeometry.viewportPadding

    override func layoutSubviews() {
        super.layoutSubviews()
        centerPageContainer()
        let currentSize = bounds.size
        if abs(currentSize.width - lastReportedViewportSize.width) > 1.0 ||
           abs(currentSize.height - lastReportedViewportSize.height) > 1.0 {
            lastReportedViewportSize = currentSize
            onViewportSizeChanged?(currentSize)
        }
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
