//
//  PageEditorTextBoxTests.swift
//  NotesTests
//
//  Responsibility: Regression unit & UIKit-hosted integration tests for rotated `.textBox` auto-expansion,
//  cross-page/Delete/Style/Toolbar undo isolation, SF Symbol resolution, Lasso tap isolation,
//  handle hit-testing vs UITextView inset, top-edge rotate handle reachability, and 2-row toolbar pan guard.
//

import Foundation
import PencilKit
import SwiftUI
import Testing
import UIKit
@testable import Notes

@Suite("Features — PageEditor TextBox & Canvas Integration", .serialized)
@MainActor
struct PageEditorTextBoxTests {

    private func pumpMainRunLoop(seconds: TimeInterval = 0.08) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func forceLayoutSubtree(_ view: UIView) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        for child in view.subviews {
            forceLayoutSubtree(child)
        }
    }

    private func waitForSubview<T: UIView>(
        ofType type: T.Type,
        in root: UIView,
        timeout: TimeInterval = 5.0
    ) -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            forceLayoutSubtree(root)
            if let found = findSubview(ofType: type, in: root) {
                return found
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        forceLayoutSubtree(root)
        return findSubview(ofType: type, in: root)
    }

    private func findSubview<T: UIView>(ofType type: T.Type, in root: UIView) -> T? {
        if let match = root as? T {
            return match
        }
        for child in root.subviews {
            if let match = findSubview(ofType: type, in: child) {
                return match
            }
        }
        return nil
    }

    private func isDescendant(_ view: UIView?, of ancestor: UIView) -> Bool {
        guard let view else { return false }
        return view === ancestor || view.isDescendant(of: ancestor)
    }

    @Test("Insert menu Text Box SF Symbol resolves non-nil on iPadOS")
    func insertMenuTextBoxSymbolResolves() {
        #expect(UIImage(systemName: "character.textbox") != nil)
    }

    @Test("Rotated TextBox auto-expansion preserves width, expands height, and anchors rotated top-left corner at 0°, 90°, 180°, -90°, and 45°")
    func rotatedTextBoxAutoExpansionMathAndLiveEditor() {
        let angles: [CGFloat] = [0, .pi * 0.5, .pi, -.pi * 0.5, .pi * 0.25]
        for angle in angles {
            let initial = PageObject(
                frame: CGRect(x: 150, y: 220, width: 200, height: 60),
                rotation: angle,
                kind: .textBox(text: "Hello", style: TextBoxStyle())
            )
            let initialTopLeft = initial.rotatedCorners()[0]
            let expanded = TextBoxLayout.autoExpandedTextBox(initial, fittingBoxHeight: 140)
            let expandedTopLeft = expanded.rotatedCorners()[0]

            #expect(abs(expanded.width - initial.width) < 0.001)
            #expect(abs(expanded.height - 140) < 0.001)
            #expect(abs(expandedTopLeft.x - initialTopLeft.x) < 0.001)
            #expect(abs(expandedTopLeft.y - initialTopLeft.y) < 0.001)
        }

        // Live hosted UITextView auto-expansion at 90 degrees
        let rotated90 = PageObject(
            frame: CGRect(x: 150, y: 220, width: 200, height: 50),
            rotation: .pi * 0.5,
            kind: .textBox(text: "", style: TextBoxStyle())
        )
        var liveUpdated = rotated90
        let editor = TextBoxEditorView(
            pageID: UUID(),
            object: rotated90,
            allObjects: [rotated90],
            text: "",
            style: TextBoxStyle(),
            onLiveObjectUpdate: { updated in
                liveUpdated = updated
            },
            onCommitObjectsChange: { _, _ in }
        )
        let host = UIHostingController(rootView: editor.frame(width: 200, height: 50).padding(TextBoxLayout.editorOuterInset))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        pumpMainRunLoop()

        if let tv = waitForSubview(ofType: UITextView.self, in: host.view) {
            tv.text = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5"
            tv.delegate?.textViewDidChange?(tv)
            #expect(abs(liveUpdated.width - 200.0) < 0.001)
            #expect(liveUpdated.height > 80.0)
            let beforeTL = rotated90.rotatedCorners()[0]
            let afterTL = liveUpdated.rotatedCorners()[0]
            #expect(abs(afterTL.x - beforeTL.x) < 0.01)
            #expect(abs(afterTL.y - beforeTL.y) < 0.01)
        } else {
            Issue.record("Expected UITextView to mount inside TextBoxEditorView")
        }
    }

    @Test("Switching pages while TextBox has uncommitted edits never leaks Page 1 undo onto Page 2")
    func crossPageSwitchIsolatesTextBoxUndo() {
        let page1ID = UUID()
        let page2ID = UUID()
        let box1 = PageObject(
            frame: CGRect(x: 120, y: 120, width: 260, height: 110),
            kind: .textBox(text: "", style: TextBoxStyle())
        )
        let circle2 = PageObject(
            frame: CGRect(x: 140, y: 200, width: 120, height: 120),
            kind: .basicShape(kind: .circle, strokeColor: .blue, strokeWidth: 3)
        )

        var objectsByPage: [UUID: [PageObject]] = [
            page1ID: [box1],
            page2ID: [circle2]
        ]
        var activePageID = page1ID
        var selectedObjectID: UUID? = box1.id
        var undoTriggerCount = 0

        func makeCanvas(for pageID: UUID) -> PencilCanvasScrollView {
            PencilCanvasScrollView(
                pageID: pageID,
                paperType: .blank,
                initialDrawingData: nil,
                pageObjects: objectsByPage[pageID] ?? [],
                selectedObjectID: selectedObjectID,
                isLassoModeActive: false,
                toolState: DrawingToolState(),
                isScribbleToEraseEnabled: true,
                undoTriggerCount: undoTriggerCount,
                redoTriggerCount: 0,
                onDrawingChanged: { _ in },
                onSelectObject: { selectedObjectID = $0 },
                onUpdateObjectLive: { updated, _ in
                    objectsByPage[activePageID] = (objectsByPage[activePageID] ?? []).map {
                        $0.id == updated.id ? updated : $0
                    }
                },
                onReplaceAllObjects: { replaced in
                    objectsByPage[activePageID] = replaced
                }
            )
        }

        let initialCanvas = makeCanvas(for: page1ID)
        let coordinator = initialCanvas.makeCoordinator()
        let uiView = UIView(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
        let vc = UIViewController()
        vc.view = uiView
        window.rootViewController = vc
        window.makeKeyAndVisible()

        // Use UIHostingController for PencilCanvasScrollView so SwiftUI manages makeUIView/updateUIView/dismantleUIView
        let rootHost = UIHostingController(rootView: initialCanvas)
        vc.addChild(rootHost)
        rootHost.view.frame = uiView.bounds
        uiView.addSubview(rootHost.view)
        rootHost.didMove(toParent: vc)
        rootHost.view.layoutIfNeeded()
        pumpMainRunLoop(seconds: 0.12)

        guard let scrollView = waitForSubview(ofType: CenteringScrollView.self, in: rootHost.view),
              let tv = waitForSubview(ofType: UITextView.self, in: rootHost.view) else {
            Issue.record("Expected CenteringScrollView and UITextView on Page 1")
            return
        }
        _ = coordinator

        tv.text = "Page 1 Secret Note"
        tv.delegate?.textViewDidChange?(tv)
        pumpMainRunLoop(seconds: 0.05)

        // Switch to Page 2 while Page 1's TextBoxEditorView had uncommitted typing
        activePageID = page2ID
        selectedObjectID = nil
        rootHost.rootView = makeCanvas(for: page2ID)
        forceLayoutSubtree(rootHost.view)
        pumpMainRunLoop(seconds: 0.12)

        let canvasView = findSubview(ofType: PKCanvasView.self, in: scrollView)
        #expect(canvasView?.undoManager?.canUndo == false)

        // Attempt Undo on Page 2 — Page 2's circle must remain untouched
        undoTriggerCount += 1
        rootHost.rootView = makeCanvas(for: page2ID)
        forceLayoutSubtree(rootHost.view)
        pumpMainRunLoop(seconds: 0.08)

        #expect(objectsByPage[page2ID] == [circle2])
        #expect(canvasView?.undoManager?.canUndo == false)
    }

    @Test("Undo while typing, Delete after typing + Undo, and Bold style change after typing + Undo produce clean undo stacks without ghost resurrection")
    func textBoxUndoWhileTypingDeleteAndStyleChange() {
        let pageID = UUID()
        let box = PageObject(
            frame: CGRect(x: 120, y: 120, width: 260, height: 110),
            kind: .textBox(text: "", style: TextBoxStyle())
        )

        var objects: [PageObject] = []
        var selectedObjectID: UUID? = nil
        var undoTriggerCount = 0

        func makeCanvas() -> PencilCanvasScrollView {
            PencilCanvasScrollView(
                pageID: pageID,
                paperType: .blank,
                initialDrawingData: nil,
                pageObjects: objects,
                selectedObjectID: selectedObjectID,
                isLassoModeActive: false,
                toolState: DrawingToolState(),
                isScribbleToEraseEnabled: true,
                undoTriggerCount: undoTriggerCount,
                redoTriggerCount: 0,
                onDrawingChanged: { _ in },
                onSelectObject: { selectedObjectID = $0 },
                onUpdateObjectLive: { updated, _ in
                    objects = objects.map { $0.id == updated.id ? updated : $0 }
                },
                onReplaceAllObjects: { replaced in
                    objects = replaced
                    if let sel = selectedObjectID, !replaced.contains(where: { $0.id == sel }) {
                        selectedObjectID = nil
                    }
                },
                onDeleteObject: { objectID in
                    objects.removeAll { $0.id == objectID }
                    if selectedObjectID == objectID {
                        selectedObjectID = nil
                    }
                }
            )
        }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
        let rootHost = UIHostingController(rootView: makeCanvas())
        window.rootViewController = rootHost
        window.makeKeyAndVisible()
        rootHost.view.layoutIfNeeded()
        pumpMainRunLoop(seconds: 0.1)

        // 1. Insert empty box
        objects = [box]
        selectedObjectID = box.id
        rootHost.rootView = makeCanvas()
        forceLayoutSubtree(rootHost.view)
        pumpMainRunLoop(seconds: 0.12)

        guard let scrollView = waitForSubview(ofType: CenteringScrollView.self, in: rootHost.view),
              let canvasView = waitForSubview(ofType: PKCanvasView.self, in: rootHost.view),
              let tv = waitForSubview(ofType: UITextView.self, in: rootHost.view) else {
            Issue.record("Expected UITextView and PKCanvasView")
            return
        }

        // 2. Type "Hello World" and trigger Undo while focused
        tv.text = "Hello World"
        tv.delegate?.textViewDidChange?(tv)
        pumpMainRunLoop(seconds: 0.05)

        undoTriggerCount += 1
        rootHost.rootView = makeCanvas()
        forceLayoutSubtree(rootHost.view)
        pumpMainRunLoop(seconds: 0.1)

        // First Undo undoes typed text ONLY (box stays!)
        #expect(objects.count == 1)
        if case .textBox(let t, _) = objects.first?.kind {
            #expect(t == "")
        } else {
            Issue.record("Expected empty textBox after first Undo")
        }

        // Second Undo removes the box cleanly with zero ghost resurrection
        undoTriggerCount += 1
        rootHost.rootView = makeCanvas()
        forceLayoutSubtree(rootHost.view)
        pumpMainRunLoop(seconds: 0.12)

        #expect(objects.isEmpty)
        #expect(canvasView.undoManager?.canUndo == false)

        // 3. Re-insert, type "Keep", delete via coordinator/bridge flow, and verify Undo restores "Keep"
        objects = [box]
        selectedObjectID = box.id
        rootHost.rootView = makeCanvas()
        forceLayoutSubtree(rootHost.view)
        pumpMainRunLoop(seconds: 0.12)

        guard let tv2 = waitForSubview(ofType: UITextView.self, in: rootHost.view) else {
            Issue.record("Expected UITextView on re-insert")
            return
        }
        tv2.text = "Keep"
        tv2.delegate?.textViewDidChange?(tv2)
        pumpMainRunLoop(seconds: 0.05)

        // Simulate Trash button flow: flush pending text edit, delete object, commit deletion
        guard let coordinator = scrollView.delegate as? PencilCanvasScrollView.Coordinator else {
            Issue.record("Expected Coordinator as scrollView delegate")
            return
        }
        coordinator.textBoxUndoBridge.flushPendingEditIfNeeded()
        let beforeDelete = objects
        objects.removeAll { $0.id == box.id }
        selectedObjectID = nil
        let afterDelete = objects
        coordinator.registerUndoForObjectChange(pageID: pageID, from: beforeDelete, to: afterDelete, actionName: "Modify Object")
        rootHost.rootView = makeCanvas()
        forceLayoutSubtree(rootHost.view)
        pumpMainRunLoop(seconds: 0.12)
        #expect(objects.isEmpty)

        // Undo deletion -> restores box with "Keep"
        undoTriggerCount += 1
        rootHost.rootView = makeCanvas()
        forceLayoutSubtree(rootHost.view)
        pumpMainRunLoop(seconds: 0.1)
        #expect(objects.count == 1)
        if case .textBox(let restoredText, _) = objects.first?.kind {
            #expect(restoredText == "Keep")
        } else {
            Issue.record("Expected restored textBox with 'Keep'")
        }

        // 4. Select box, type "Styled", apply Bold, then Undo twice cleanly
        selectedObjectID = box.id
        rootHost.rootView = makeCanvas()
        forceLayoutSubtree(rootHost.view)
        pumpMainRunLoop(seconds: 0.12)

        guard let tv3 = waitForSubview(ofType: UITextView.self, in: rootHost.view) else {
            Issue.record("Expected UITextView for style test")
            return
        }
        tv3.text = "Styled"
        tv3.delegate?.textViewDidChange?(tv3)
        pumpMainRunLoop(seconds: 0.05)

        coordinator.textBoxUndoBridge.flushPendingEditIfNeeded()
        let beforeStyle = objects
        var boldStyle = TextBoxStyle()
        boldStyle.isBold = true
        let styledObj = beforeStyle[0].withTextBoxStyle(boldStyle)
        objects = [styledObj]
        coordinator.registerUndoForObjectChange(pageID: pageID, from: beforeStyle, to: objects, actionName: "Modify Object")
        rootHost.rootView = makeCanvas()
        forceLayoutSubtree(rootHost.view)
        pumpMainRunLoop(seconds: 0.08)

        // Undo 1 -> removes Bold, keeps "Styled"
        undoTriggerCount += 1
        rootHost.rootView = makeCanvas()
        forceLayoutSubtree(rootHost.view)
        pumpMainRunLoop(seconds: 0.08)
        if case .textBox(let t, let s) = objects.first?.kind {
            #expect(t == "Styled")
            #expect(s.isBold == false)
        } else {
            Issue.record("Expected 'Styled' unbolded after Undo 1")
        }

        // Undo 2 -> reverts "Styled" to "Keep"
        undoTriggerCount += 1
        rootHost.rootView = makeCanvas()
        forceLayoutSubtree(rootHost.view)
        pumpMainRunLoop(seconds: 0.08)
        if case .textBox(let t, let s) = objects.first?.kind {
            #expect(t == "Keep")
            #expect(s.isBold == false)
        } else {
            Issue.record("Expected 'Keep' after Undo 2")
        }
    }

    @Test("Lasso mode ignores single-finger taps over objects and does not select or exit Lasso mode")
    func lassoModeIgnoresSingleFingerTapOverObjects() {
        let box = PageObject(
            frame: CGRect(x: 150, y: 150, width: 220, height: 100),
            kind: .textBox(text: "Lasso Target", style: TextBoxStyle())
        )
        var selectedObjectID: UUID? = nil
        var isLassoActive = true

        let canvas = PencilCanvasScrollView(
            pageID: UUID(),
            paperType: .blank,
            initialDrawingData: nil,
            pageObjects: [box],
            selectedObjectID: selectedObjectID,
            isLassoModeActive: isLassoActive,
            toolState: DrawingToolState(),
            isScribbleToEraseEnabled: true,
            onDrawingChanged: { _ in },
            onSelectObject: { newID in
                if newID != nil {
                    isLassoActive = false
                }
                selectedObjectID = newID
            }
        )

        let coordinator = canvas.makeCoordinator()
        #expect(coordinator.shouldSingleFingerTapReceiveTouch(isInsideObjectsView: false, pointInPage: box.center) == false)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
        let rootHost = UIHostingController(rootView: canvas)
        window.rootViewController = rootHost
        window.makeKeyAndVisible()
        rootHost.view.layoutIfNeeded()
        pumpMainRunLoop(seconds: 0.08)

        if let scrollView = waitForSubview(ofType: CenteringScrollView.self, in: rootHost.view),
           let liveCoordinator = scrollView.delegate as? PencilCanvasScrollView.Coordinator,
           let tapRecognizer = liveCoordinator.singleFingerTapRecognizer {
            #expect(liveCoordinator.shouldSingleFingerTapReceiveTouch(isInsideObjectsView: false, pointInPage: box.center) == false)
            liveCoordinator.handleSingleFingerTap(tapRecognizer)
            #expect(selectedObjectID == nil)
            #expect(isLassoActive == true)
        } else {
            Issue.record("Expected CenteringScrollView and singleFingerTapRecognizer")
        }
    }

    @Test("Focused TextBox corner/border hit-testing does not shadow handles, top-edge rotate handle above y=0 is reachable, and 2-row toolbar pan guard covers bottom row")
    func focusedTextBoxHitTestingAndToolbarPanGuard() {
        let box = PageObject(
            frame: CGRect(x: 160, y: 100, width: 260, height: 110),
            kind: .textBox(text: "Hit Test Card", style: TextBoxStyle())
        )
        let canvas = PencilCanvasScrollView(
            pageID: UUID(),
            paperType: .blank,
            initialDrawingData: nil,
            pageObjects: [box],
            selectedObjectID: box.id,
            isLassoModeActive: false,
            toolState: DrawingToolState(),
            isScribbleToEraseEnabled: true,
            onDrawingChanged: { _ in }
        )

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
        let rootHost = UIHostingController(rootView: canvas)
        window.rootViewController = rootHost
        window.makeKeyAndVisible()
        rootHost.view.layoutIfNeeded()
        pumpMainRunLoop(seconds: 0.14)

        guard let scrollView = waitForSubview(ofType: CenteringScrollView.self, in: rootHost.view),
              let pageContainer = scrollView.pageContainerView,
              let tv = waitForSubview(ofType: UITextView.self, in: pageContainer) else {
            Issue.record("Expected UITextView inside pageContainerView")
            return
        }

        // Verify UIScribbleInteraction is attached to UITextView
        #expect(tv.interactions.contains { $0 is UIScribbleInteraction })

        // Corner centers, 4pt inner corner dots, and top border edges must NOT route to UITextView
        #expect(!isDescendant(pageContainer.hitTest(CGPoint(x: 160, y: 100), with: nil), of: tv))
        #expect(!isDescendant(pageContainer.hitTest(CGPoint(x: 164, y: 104), with: nil), of: tv))
        #expect(!isDescendant(pageContainer.hitTest(CGPoint(x: 290, y: 100), with: nil), of: tv))
        #expect(!isDescendant(pageContainer.hitTest(CGPoint(x: 290, y: 105), with: nil), of: tv))

        // Text interior MUST route unobstructed to UITextView
        #expect(isDescendant(pageContainer.hitTest(CGPoint(x: 290, y: 155), with: nil), of: tv))

        // 2-row toolbar pan guard covers bottom row (bounds.maxY + 64)
        let coordinator = scrollView.delegate as? PencilCanvasScrollView.Coordinator
        let bottomRowPoint = CGPoint(x: box.center.x, y: box.frame.maxY + 64)
        #expect(coordinator?.isPointOverSelectedObjectOrToolbar(bottomRowPoint) == true)

        // Top-edge rotate handle above y = 0 (box near top edge at y = 10) must be hit-testable
        let topEdgeBox = PageObject(
            frame: CGRect(x: 160, y: 10, width: 260, height: 110),
            kind: .textBox(text: "Top Edge", style: TextBoxStyle())
        )
        let topEdgeCanvas = PencilCanvasScrollView(
            pageID: UUID(),
            paperType: .blank,
            initialDrawingData: nil,
            pageObjects: [topEdgeBox],
            selectedObjectID: topEdgeBox.id,
            isLassoModeActive: false,
            toolState: DrawingToolState(),
            isScribbleToEraseEnabled: true,
            onDrawingChanged: { _ in }
        )
        rootHost.rootView = topEdgeCanvas
        forceLayoutSubtree(rootHost.view)
        pumpMainRunLoop(seconds: 0.14)

        guard let scrollView2 = waitForSubview(ofType: CenteringScrollView.self, in: rootHost.view),
              let pageContainer2 = scrollView2.pageContainerView else {
            Issue.record("Expected pageContainerView for top-edge rotate test")
            return
        }
        // Rotate handle sits ~19pt above top edge: y = 10 - 19 = -9
        let rotateHandleHit = pageContainer2.hitTest(CGPoint(x: 290, y: -9), with: nil)
        #expect(rotateHandleHit != nil)
    }
}
