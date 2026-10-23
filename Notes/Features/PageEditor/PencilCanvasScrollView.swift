//
//  PencilCanvasScrollView.swift
//  Notes
//
//  Responsibility: UIKit wrapper (`UIViewRepresentable`) hosting an A4 portrait `PKCanvasView` (595 x 842 pt) inside a zoomable/pannable `UIScrollView` (1x to 5x zoom, double-tap to reset).
//  Design notes:
//    - Paper background (`PaperBackgroundView` via `UIHostingController`) sits behind the transparent `PKCanvasView` inside the same zoom container view so paper and ink zoom together, while paper is never drawn into `PKDrawing`.
//    - `PKToolPicker` is configured with only the 4 allowed tools: pen, highlighter (`.marker`), eraser, and ruler (`showsRulerActive = true`).
//    - `drawingPolicy = .pencilOnly` so finger touches scroll and zoom by default.
//    - After a new stroke completes (`canvasViewDrawingDidChange`), runs `ScribbleClassifier.classify(...)`. If a scribble-to-erase gesture is detected over existing strokes, replaces the drawing with the pre-scribble drawing minus covered strokes and registers an undo operation on `canvasView.undoManager` so Undo restores the erased strokes in one step.
//  Dependencies: SwiftUI, UIKit, PencilKit, Domain, DesignSystem.
//

import PencilKit
import SwiftUI
import UIKit

public struct PencilCanvasScrollView: UIViewRepresentable {
    public let pageID: UUID
    public let paperType: PaperType
    public let initialDrawingData: Data?
    public let isScribbleToEraseEnabled: Bool
    public let onDrawingChanged: (Data) -> Void
    public var onSwipeToNextPage: (() -> Void)?
    public var onSwipeToPreviousPage: (() -> Void)?

    public static let minimumZoomScale: CGFloat = 1.0
    public static let maximumZoomScale: CGFloat = 5.0

    public init(
        pageID: UUID,
        paperType: PaperType,
        initialDrawingData: Data?,
        isScribbleToEraseEnabled: Bool,
        onDrawingChanged: @escaping (Data) -> Void,
        onSwipeToNextPage: (() -> Void)? = nil,
        onSwipeToPreviousPage: (() -> Void)? = nil
    ) {
        self.pageID = pageID
        self.paperType = paperType
        self.initialDrawingData = initialDrawingData
        self.isScribbleToEraseEnabled = isScribbleToEraseEnabled
        self.onDrawingChanged = onDrawingChanged
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
        canvasView.drawingPolicy = .pencilOnly
        canvasView.isScrollEnabled = false // Outer UIScrollView handles scrolling and zooming
        canvasView.delegate = context.coordinator
        pageContainer.addSubview(canvasView)

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

        // Finger swipe right -> next / new page; finger swipe left -> previous page (active when unzoomed)
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

        // Load initial drawing for pageID
        context.coordinator.loadPageIfNeeded(pageID: pageID, data: initialDrawingData)
        context.coordinator.configureToolPicker(for: canvasView)

        return scrollView
    }

    public func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.paperHostingController?.rootView = PaperBackgroundView(paperType: paperType)
        context.coordinator.loadPageIfNeeded(pageID: pageID, data: initialDrawingData)
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var parent: PencilCanvasScrollView
        weak var scrollView: CenteringScrollView?
        weak var pageContainerView: UIView?
        var paperHostingController: UIHostingController<PaperBackgroundView>?
        weak var canvasView: PKCanvasView?

        private var toolPicker: PKToolPicker?
        private var currentLoadedPageID: UUID?
        private var isProgrammaticDrawingUpdate = false
        private var previousDrawingSnapshot = PKDrawing()

        init(parent: PencilCanvasScrollView) {
            self.parent = parent
        }

        func configureToolPicker(for canvasView: PKCanvasView) {
            // Trim tool picker to the 4 spec tools: Pen, Highlighter (marker), Eraser, and Ruler.
            let defaultPen = PKInkingTool(.pen, color: .label, width: 3.0)
            let defaultHighlighter = PKInkingTool(.marker, color: .systemYellow, width: 18.0)
            let defaultEraser = PKEraserTool(.vector)

            let picker: PKToolPicker
            if #available(iOS 18.0, *) {
                let items: [PKToolPickerItem] = [
                    PKToolPickerInkingItem(type: .pen, color: .label, width: 3.0),
                    PKToolPickerInkingItem(type: .marker, color: .systemYellow, width: 18.0),
                    PKToolPickerEraserItem(type: .vector),
                    PKToolPickerRulerItem()
                ]
                picker = PKToolPicker(toolItems: items)
            } else {
                picker = PKToolPicker()
            }

            picker.selectedTool = defaultPen
            picker.showsDrawingPolicyControls = false
            picker.addObserver(canvasView)
            picker.setVisible(true, forFirstResponder: canvasView)
            self.toolPicker = picker

            // Suppress unused warning on older SDK fallback constants
            _ = (defaultHighlighter, defaultEraser)

            DispatchQueue.main.async {
                canvasView.becomeFirstResponder()
            }
        }

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
            scrollView?.setZoomScale(1.0, animated: false)
        }

        // MARK: - UIScrollViewDelegate

        public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            pageContainerView
        }

        public func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? CenteringScrollView)?.centerPageContainer()
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
            case .right:
                parent.onSwipeToNextPage?()
            case .left:
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
