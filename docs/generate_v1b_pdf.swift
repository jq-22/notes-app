import Cocoa
import CoreGraphics

let pageWidth: CGFloat = 595.0
let pageHeight: CGFloat = 842.0
let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
let margin: CGFloat = 40.0
let contentWidth = pageWidth - margin * 2

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

func drawRoundedBox(
    _ ctx: CGContext,
    rect: CGRect,
    radius: CGFloat = 8.0,
    fill: NSColor,
    stroke: NSColor? = nil,
    lineWidth: CGFloat = 1.2
) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setFillColor(fill.cgColor)
    ctx.fillPath()
    if let stroke {
        ctx.addPath(path)
        ctx.setStrokeColor(stroke.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.strokePath()
    }
    ctx.restoreGState()
}

func drawText(
    _ text: String,
    in rect: CGRect,
    font: NSFont,
    color: NSColor = NSColor(srgbRed: 0.10, green: 0.12, blue: 0.16, alpha: 1.0),
    alignment: NSTextAlignment = .left,
    lineSpacing: CGFloat = 2.5
) {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineSpacing = lineSpacing
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: style
    ]
    NSString(string: text).draw(in: rect, withAttributes: attrs)
}

func drawArrow(
    _ ctx: CGContext,
    from start: CGPoint,
    to end: CGPoint,
    color: NSColor,
    lineWidth: CGFloat = 1.8
) {
    ctx.saveGState()
    ctx.setStrokeColor(color.cgColor)
    ctx.setFillColor(color.cgColor)
    ctx.setLineWidth(lineWidth)

    ctx.move(to: start)
    ctx.addLine(to: end)
    ctx.strokePath()

    let angle = atan2(end.y - start.y, end.x - start.x)
    let arrowLength: CGFloat = 7.5
    let arrowAngle: CGFloat = .pi / 6.0

    let p1 = CGPoint(
        x: end.x - arrowLength * cos(angle - arrowAngle),
        y: end.y - arrowLength * sin(angle - arrowAngle)
    )
    let p2 = CGPoint(
        x: end.x - arrowLength * cos(angle + arrowAngle),
        y: end.y - arrowLength * sin(angle + arrowAngle)
    )

    ctx.move(to: end)
    ctx.addLine(to: p1)
    ctx.addLine(to: p2)
    ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()
}

func drawPageHeaderAndFooter(_ ctx: CGContext, pageNumber: Int, totalPages: Int, sectionTitle: String) {
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(pageRect)

    // Top banner accent bar
    ctx.setFillColor(color(0x0284C7).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: pageWidth, height: 6))

    if pageNumber > 1 {
        drawText(
            "NOTES FOR iPadOS — MILESTONE v1b TECHNICAL DOCUMENTATION",
            in: CGRect(x: margin, y: 18, width: 340, height: 16),
            font: .systemFont(ofSize: 8.5, weight: .bold),
            color: color(0x64748B)
        )
        drawText(
            sectionTitle,
            in: CGRect(x: pageWidth - margin - 220, y: 18, width: 220, height: 16),
            font: .systemFont(ofSize: 8.5, weight: .semibold),
            color: color(0x0284C7),
            alignment: .right
        )
        ctx.setStrokeColor(color(0xE2E8F0).cgColor)
        ctx.setLineWidth(0.8)
        ctx.move(to: CGPoint(x: margin, y: 34))
        ctx.addLine(to: CGPoint(x: pageWidth - margin, y: 34))
        ctx.strokePath()
    }

    // Footer
    ctx.setStrokeColor(color(0xE2E8F0).cgColor)
    ctx.setLineWidth(0.8)
    ctx.move(to: CGPoint(x: margin, y: pageHeight - 34))
    ctx.addLine(to: CGPoint(x: pageWidth - margin, y: pageHeight - 34))
    ctx.strokePath()

    drawText(
        "github.com/jq-22/notes-app • Release v1b (Objects & Library)",
        in: CGRect(x: margin, y: pageHeight - 26, width: 300, height: 14),
        font: .systemFont(ofSize: 8.5, weight: .regular),
        color: color(0x64748B)
    )
    drawText(
        "Page \(pageNumber) of \(totalPages)",
        in: CGRect(x: pageWidth - margin - 120, y: pageHeight - 26, width: 120, height: 14),
        font: .systemFont(ofSize: 8.5, weight: .semibold),
        color: color(0x475569),
        alignment: .right
    )
}

func beginFlippedPage(_ pdfContext: CGContext, mediaBox: inout CGRect, pageNumber: Int, totalPages: Int, sectionTitle: String) {
    pdfContext.beginPage(mediaBox: &mediaBox)
    pdfContext.saveGState()
    pdfContext.translateBy(x: 0, y: pageHeight)
    pdfContext.scaleBy(x: 1, y: -1)
    let nsContext = NSGraphicsContext(cgContext: pdfContext, flipped: true)
    NSGraphicsContext.current = nsContext
    drawPageHeaderAndFooter(pdfContext, pageNumber: pageNumber, totalPages: totalPages, sectionTitle: sectionTitle)
}

func endFlippedPage(_ pdfContext: CGContext) {
    NSGraphicsContext.current = nil
    pdfContext.restoreGState()
    pdfContext.endPage()
}

// MARK: - Page 1: Hero, Summary & Layered Architecture Diagram

func drawPage1(_ ctx: CGContext) {
    // Hero banner
    let heroRect = CGRect(x: margin, y: 28, width: contentWidth, height: 114)
    drawRoundedBox(ctx, rect: heroRect, radius: 12, fill: color(0x0F172A))

    drawText(
        "MILESTONE v1b — ARCHITECTURE & ENGINEERING GUIDE",
        in: CGRect(x: margin + 20, y: 44, width: contentWidth - 40, height: 16),
        font: .systemFont(ofSize: 9.5, weight: .bold),
        color: color(0x38BDF8)
    )
    drawText(
        "Objects, Freehand Lasso & Shape Library",
        in: CGRect(x: margin + 20, y: 62, width: contentWidth - 40, height: 28),
        font: .systemFont(ofSize: 20, weight: .bold),
        color: .white
    )
    drawText(
        "Interactive PageObjects • Freehand Ray-Casting Lasso • Cross-Notebook Clipboard • 31 Automated Tests",
        in: CGRect(x: margin + 20, y: 94, width: contentWidth - 40, height: 18),
        font: .systemFont(ofSize: 9.8, weight: .medium),
        color: color(0xCBD5E1)
    )
    drawText(
        "Target: iPadOS 26.5+ (iPad Only) | Repo: github.com/jq-22/notes-app | Release: v1b",
        in: CGRect(x: margin + 20, y: 115, width: contentWidth - 40, height: 16),
        font: .monospacedSystemFont(ofSize: 8.2, weight: .regular),
        color: color(0x94A3B8)
    )

    // Section 1: Executive Summary
    drawText(
        "1. Executive Summary — Milestone v1b Capabilities",
        in: CGRect(x: margin, y: 154, width: contentWidth, height: 20),
        font: .systemFont(ofSize: 13.5, weight: .bold),
        color: color(0x0F172A)
    )

    let cards: [(String, String, String, UInt32, UInt32)] = [
        ("Interactive PageObjects", "Basic Shapes & Images", "Rectangle, circle, arrow, line, and photo objects with 4-corner resizing, live rotation, move border, and dual end-bar handles for lines. Tap on page to deselect.", 0xEFF6FF, 0x1D4ED8),
        ("Freehand Lasso Tool", "Ray-Casting Selection", "Dotted lasso loop selection for ink strokes and objects. Translate together, recolour with swatches, duplicate, copy, cut, convert to reusable object, or delete.", 0xF0FDF4, 0x15803D),
        ("Cross-Notebook Clipboard", "System-Wide Copy & Paste", "Copy and paste ink strokes and page objects across sections and across distinct notebooks, preserving vector quality, scale, and aspect ratios.", 0xFAF5FF, 0x7E22CE),
        ("Notebook Shape Library", "Reusable Diagram Shapes", "Save any lassoed ink drawing with a custom label. Stored as raw ink + transparent PNG preview cards. Browse and pull saved shapes across notebooks with one tap.", 0xFFFBEB, 0xB45309)
    ]

    for (i, c) in cards.enumerated() {
        let col = i % 2
        let row = i / 2
        let x = margin + CGFloat(col) * ((contentWidth - 14) / 2 + 14)
        let y = 180 + CGFloat(row) * 70
        let w = (contentWidth - 14) / 2
        let box = CGRect(x: x, y: y, width: w, height: 62)

        drawRoundedBox(ctx, rect: box, radius: 8, fill: color(c.3), stroke: color(c.4).withAlphaComponent(0.35), lineWidth: 1.0)
        drawText(c.0, in: CGRect(x: x + 10, y: y + 8, width: w - 20, height: 14), font: .systemFont(ofSize: 10, weight: .bold), color: color(c.4))
        drawText(c.1, in: CGRect(x: x + 10, y: y + 22, width: w - 20, height: 12), font: .monospacedSystemFont(ofSize: 7.5, weight: .semibold), color: color(0x64748B))
        drawText(c.2, in: CGRect(x: x + 10, y: y + 36, width: w - 20, height: 22), font: .systemFont(ofSize: 7.6, weight: .regular), color: color(0x334155), lineSpacing: 1.2)
    }

    // Section 2: Architecture Diagram
    drawText(
        "2. Milestone v1b Layered Architecture & Data Flow",
        in: CGRect(x: margin, y: 332, width: contentWidth, height: 20),
        font: .systemFont(ofSize: 13.5, weight: .bold),
        color: color(0x0F172A)
    )
    drawText(
        "Strict unidirectional dependency: Domain ← Persistence ← Features ← App. Zero third-party dependencies.",
        in: CGRect(x: margin, y: 352, width: contentWidth, height: 14),
        font: .systemFont(ofSize: 8.5, weight: .regular),
        color: color(0x64748B)
    )

    let layers: [(String, String, String, UInt32, UInt32, [String])] = [
        ("Presentation Layer (Features & UI)", "PageEditorView, PencilCanvasScrollView, PageObjectsOverlayView, LassoSelectionOverlayView, ShapeLibraryPopoverView", "SwiftUI + UIKit interactive views handling PencilKit drawing, gesture translation, handle drags, and toolbars", 0xF1F5F9, 0x475569, ["PageObjectsOverlayView", "LassoOverlayView", "ShapeLibraryPopover"]),
        ("State & ViewModel (LibraryViewModel)", "LibraryViewModel (@Observable @MainActor)", "Coordinates selection, undo/redo triggers, clipboard copy/paste, shape library caching, and debounced persistence", 0xEFF6FF, 0x2563EB, ["Clipboard Engine", "Shape Lib Manager", "PageObject CRUD"]),
        ("Storage Boundary (Persistence)", "PageStore Protocol + FilePageStore Implementation", "Atomic file transactions: notebooks.json, Drawings/<id>.pkdrawing, Assets/<id>.dat, ShapeLibrary/<id>.json, Previews/<id>.png", 0xFDF4FF, 0x9333EA, ["FilePageStore", "Assets Storage", "ShapeLibrary IO"]),
        ("Domain Core (Domain Models)", "Notebook, NoteSection, Page, PageObject, LassoSelection, ShapeLibraryItem, ScribbleClassifier", "Pure Swift value types, geometry computations, ray-casting point-in-polygon algorithm, zero UI framework imports", 0xF0FDF4, 0x16A34A, ["PageObject Geometry", "Lasso Ray-Caster", "ShapeLibraryItem"])
    ]

    var yCur: CGFloat = 372
    for (idx, l) in layers.enumerated() {
        let box = CGRect(x: margin, y: yCur, width: contentWidth, height: 68)
        drawRoundedBox(ctx, rect: box, radius: 8, fill: color(l.3), stroke: color(l.4), lineWidth: 1.2)

        drawText(l.0, in: CGRect(x: box.minX + 12, y: box.minY + 8, width: 260, height: 14), font: .systemFont(ofSize: 10, weight: .bold), color: color(l.4))
        drawText(l.1, in: CGRect(x: box.maxX - 260, y: box.minY + 8, width: 248, height: 14), font: .monospacedSystemFont(ofSize: 7.5, weight: .medium), color: color(0x475569), alignment: .right)
        drawText(l.2, in: CGRect(x: box.minX + 12, y: box.minY + 24, width: contentWidth - 24, height: 16), font: .systemFont(ofSize: 7.8, weight: .regular), color: color(0x334155))

        // Subcomponents pills
        for (pIdx, pill) in l.5.enumerated() {
            let px = box.minX + 12 + CGFloat(pIdx) * 115
            let py = box.minY + 44
            let pBox = CGRect(x: px, y: py, width: 105, height: 16)
            drawRoundedBox(ctx, rect: pBox, radius: 4, fill: .white, stroke: color(l.4).withAlphaComponent(0.4), lineWidth: 0.8)
            drawText("• " + pill, in: CGRect(x: px + 4, y: py + 2.5, width: 97, height: 12), font: .monospacedSystemFont(ofSize: 7.0, weight: .semibold), color: color(l.4))
        }

        if idx < layers.count - 1 {
            drawArrow(ctx, from: CGPoint(x: pageWidth / 2, y: box.maxY), to: CGPoint(x: pageWidth / 2, y: box.maxY + 14), color: color(0x94A3B8), lineWidth: 1.5)
        }
        yCur += 82
    }

    // Bottom highlight box
    let infoBox = CGRect(x: margin, y: yCur + 6, width: contentWidth, height: 48)
    drawRoundedBox(ctx, rect: infoBox, radius: 8, fill: color(0xFEF2F2), stroke: color(0xF87171), lineWidth: 1.0)
    drawText("Data Integrity & Backward Compatibility Guarantee", in: CGRect(x: infoBox.minX + 12, y: infoBox.minY + 6, width: contentWidth - 24, height: 14), font: .systemFont(ofSize: 9, weight: .bold), color: color(0x991B1B))
    drawText("Milestone v1a notebook JSON files load seamlessly without migration scripts. The Page decoder defaults missing objects to an empty array [PageObject], ensuring existing student and work notebooks remain 100% intact.", in: CGRect(x: infoBox.minX + 12, y: infoBox.minY + 20, width: contentWidth - 24, height: 24), font: .systemFont(ofSize: 7.8, weight: .regular), color: color(0x7F1D1D), lineSpacing: 1.2)
}

// MARK: - Page 2: Objects, Handles & Freehand Lasso Algorithms

func drawPage2(_ ctx: CGContext) {
    drawText(
        "3. PageObject Architecture & Transform Geometry",
        in: CGRect(x: margin, y: 44, width: contentWidth, height: 20),
        font: .systemFont(ofSize: 13.5, weight: .bold),
        color: color(0x0F172A)
    )

    let objectCards: [(String, String, String, String)] = [
        ("Unified Handle System", "Corner Dots + Move Border + Rotate Handle", "Rectangles, circles, and images feature 4 circular corner handles (min 44pt touch target) that anchor the diagonally opposite corner during resizing. A top rotation stalk allows 360-degree freeform rotation. Dragging inside the dashed border translates the object.", "PageObject.swift"),
        ("Dual End-Bar Line Handles", "Opposite-End Anchored Scaling", "Lines and Arrows employ an intuitive engineering blueprint design: two perpendicular end-bar handles for resizing and stretching in either direction while pinning the opposing endpoint, paired with a central rotation handle for angular orientation.", "LineEndpointHandle"),
        ("Vector Basic Shapes", "Rectangle, Circle, Arrow, Line", "Rendered via native SwiftUI vector shapes and CoreGraphics paths, supporting stroke thickness and the 8 Theme ink colour presets with automatic dark mode contrast.", "BasicShapeKind"),
        ("Independent Asset Storage", "Assets/<asset-uuid>.dat Separation", "Inserted photos and images are normalized to PNG data and persisted in a dedicated Assets/ folder referenced by UUID, keeping the main notebooks.json metadata lightweight and instant to serialize.", "FilePageStore")
    ]

    for (i, c) in objectCards.enumerated() {
        let col = i % 2
        let row = i / 2
        let x = margin + CGFloat(col) * ((contentWidth - 14) / 2 + 14)
        let y = 70 + CGFloat(row) * 82
        let w = (contentWidth - 14) / 2
        let box = CGRect(x: x, y: y, width: w, height: 74)

        drawRoundedBox(ctx, rect: box, radius: 8, fill: color(0xF8FAFC), stroke: color(0xCBD5E1), lineWidth: 1.0)
        drawText(c.0, in: CGRect(x: x + 10, y: y + 8, width: w - 20, height: 14), font: .systemFont(ofSize: 9.5, weight: .bold), color: color(0x0F172A))
        drawText(c.1, in: CGRect(x: x + 10, y: y + 22, width: w - 20, height: 12), font: .monospacedSystemFont(ofSize: 7.2, weight: .semibold), color: color(0x0284C7))
        drawText(c.2, in: CGRect(x: x + 10, y: y + 36, width: w - 20, height: 32), font: .systemFont(ofSize: 7.5, weight: .regular), color: color(0x334155), lineSpacing: 1.1)
    }

    // Section 4: Freehand Lasso Pipeline & Ray-Casting Algorithm
    drawText(
        "4. Freehand Lasso Ray-Casting & Selection Engine",
        in: CGRect(x: margin, y: 246, width: contentWidth, height: 20),
        font: .systemFont(ofSize: 13.5, weight: .bold),
        color: color(0x0F172A)
    )
    drawText(
        "LassoSelection.swift implements pure geometric point-in-polygon ray-casting to accurately capture ink strokes and objects.",
        in: CGRect(x: margin, y: 266, width: contentWidth, height: 14),
        font: .systemFont(ofSize: 8.5, weight: .regular),
        color: color(0x64748B)
    )

    let steps: [(String, String, String)] = [
        ("1. Loop Tracing", "User draws a freehand loop using finger or pencil. The system records raw points into a closed LassoPolygon, rendering a high-contrast animated dotted stroke.", "LassoSelectionOverlayView"),
        ("2. Ray-Casting Enclosure", "Ray-casting Jordan Curve algorithm casts horizontal rays to test points. An ink stroke is enclosed if ≥60% of its sample points fall inside the polygon; objects are enclosed if their center falls inside.", "LassoPolygon.contains(point:)"),
        ("3. Unified Translation", "Dragging inside the bounding box moves enclosed ink strokes and PageObjects in real time. PencilKit canvas temporarily hides selected strokes to eliminate duplicate rendering.", "ActiveLassoSelection"),
        ("4. Floating Action Menu", "Floating menu provides one-tap actions: Recolour (applying ink swatches to enclosed strokes), Copy, Cut, Convert to Object (freezes strokes as PageObject), Save to Library, and Delete.", "LassoActionToolbar")
    ]

    var stepY: CGFloat = 286
    for s in steps {
        let box = CGRect(x: margin, y: stepY, width: contentWidth, height: 50)
        drawRoundedBox(ctx, rect: box, radius: 6, fill: color(0xF0FDF4), stroke: color(0x86EFAC), lineWidth: 0.9)
        drawText(s.0, in: CGRect(x: box.minX + 10, y: box.minY + 6, width: 140, height: 14), font: .systemFont(ofSize: 9.0, weight: .bold), color: color(0x166534))
        drawText(s.2, in: CGRect(x: box.maxX - 200, y: box.minY + 6, width: 190, height: 14), font: .monospacedSystemFont(ofSize: 7.2, weight: .semibold), color: color(0x15803D), alignment: .right)
        drawText(s.1, in: CGRect(x: box.minX + 10, y: box.minY + 22, width: contentWidth - 20, height: 24), font: .systemFont(ofSize: 7.7, weight: .regular), color: color(0x1E293B), lineSpacing: 1.1)
        stepY += 56
    }

    // Section 5: StrokeGroup Conversion & Recolouring Logic
    drawText(
        "5. StrokeGroup Object Transformation & Recolouring",
        in: CGRect(x: margin, y: 520, width: contentWidth, height: 20),
        font: .systemFont(ofSize: 13.5, weight: .bold),
        color: color(0x0F172A)
    )

    let codeBox = CGRect(x: margin, y: 544, width: contentWidth, height: 236)
    drawRoundedBox(ctx, rect: codeBox, radius: 8, fill: color(0x0F172A))

    let codeSnippet = """
    // Notes/Domain/PageObject.swift — StrokeGroup Recolouring & Transformation
    extension PageObject {
        public func withTintColor(_ newColor: InkColorPreset) -> PageObject {
            guard case .strokeGroup(let data, let w, let h, _) = self.kind,
                  let originalDrawing = try? PKDrawing(data: data) else {
                return self
            }
            // Recolor all ink strokes while preserving stroke widths and pressure profiles
            var recoloredStrokes: [PKStroke] = []
            for stroke in originalDrawing.strokes {
                var ink = stroke.ink
                ink.color = newColor.uiColor
                let newStroke = PKStroke(ink: ink, path: stroke.path, transform: stroke.transform, mask: stroke.mask)
                recoloredStrokes.append(newStroke)
            }
            let updatedDrawing = PKDrawing(strokes: recoloredStrokes)
            let updatedData = updatedDrawing.dataRepresentation()
            var copy = self
            copy.kind = .strokeGroup(drawingData: updatedData, sourceBoundsWidth: w, sourceBoundsHeight: h, tintColorOverride: newColor)
            return copy
        }
    }
    """
    drawText(codeSnippet, in: CGRect(x: codeBox.minX + 14, y: codeBox.minY + 12, width: contentWidth - 28, height: 212), font: .monospacedSystemFont(ofSize: 7.5, weight: .regular), color: color(0x38BDF8), lineSpacing: 1.8)
}

// MARK: - Page 3: Notebook Shape Library, Persistence & Verification Matrix

func drawPage3(_ ctx: CGContext) {
    drawText(
        "6. Notebook Shape Library & Cross-Notebook Reuse",
        in: CGRect(x: margin, y: 44, width: contentWidth, height: 20),
        font: .systemFont(ofSize: 13.5, weight: .bold),
        color: color(0x0F172A)
    )

    let libCards: [(String, String, String)] = [
        ("Transparent PNG Previews", "Saved shapes render transparent preview cards via PKDrawing.image(from:scale:) under light trait mode, ensuring crisp display regardless of app theme.", "ShapeLibrary/Previews/<id>.png"),
        ("Cross-Notebook Drawer", "Tapping the notebook title at the top of ShapeLibraryPopoverView opens a drawer allowing students to pull diagram symbols saved in any course notebook.", "ShapeLibraryPopoverView.swift"),
        ("Placing as PageObject", "Placing an item creates a centered, resizable, and rotatable .strokeGroup PageObject. Users can reposition and recolour placed shapes freely.", "placeShapeLibraryItem()")
    ]

    for (i, c) in libCards.enumerated() {
        let x = margin + CGFloat(i) * ((contentWidth - 16) / 3 + 8)
        let w = (contentWidth - 16) / 3
        let box = CGRect(x: x, y: 70, width: w, height: 86)
        drawRoundedBox(ctx, rect: box, radius: 8, fill: color(0xFEFCE8), stroke: color(0xFDE047), lineWidth: 1.0)
        drawText(c.0, in: CGRect(x: x + 8, y: box.minY + 8, width: w - 16, height: 14), font: .systemFont(ofSize: 9.0, weight: .bold), color: color(0x854D0E))
        drawText(c.1, in: CGRect(x: x + 8, y: box.minY + 24, width: w - 16, height: 38), font: .systemFont(ofSize: 7.4, weight: .regular), color: color(0x713F12), lineSpacing: 1.1)
        drawText(c.2, in: CGRect(x: x + 8, y: box.minY + 66, width: w - 16, height: 12), font: .monospacedSystemFont(ofSize: 6.8, weight: .semibold), color: color(0xA16207))
    }

    // Section 7: Persistence Directory Map
    drawText(
        "7. File Storage Layout (Zero Database, Pure Files)",
        in: CGRect(x: margin, y: 168, width: contentWidth, height: 20),
        font: .systemFont(ofSize: 13.5, weight: .bold),
        color: color(0x0F172A)
    )

    let fileBox = CGRect(x: margin, y: 192, width: contentWidth, height: 96)
    drawRoundedBox(ctx, rect: fileBox, radius: 8, fill: color(0xF8FAFC), stroke: color(0xE2E8F0), lineWidth: 1.0)

    let fileLayout = """
    Documents/
      ├── notebooks.json                         # Lightweight metadata: hierarchy, PaperTypes, [PageObject] geometry
      ├── Drawings/<page-uuid>.pkdrawing         # High-density PencilKit binary drawing data
      ├── Assets/<asset-uuid>.dat                # Inserted image and photo binary payloads (PNG/JPEG)
      └── ShapeLibrary/
          ├── <notebook-uuid>.json               # Saved diagram shapes: labels, raw stroke data, bounds
          └── Previews/<item-uuid>.png           # Transparent thumbnail previews for instant popover rendering
    """
    drawText(fileLayout, in: CGRect(x: fileBox.minX + 12, y: fileBox.minY + 8, width: contentWidth - 24, height: 80), font: .monospacedSystemFont(ofSize: 7.5, weight: .regular), color: color(0x1E293B), lineSpacing: 1.4)

    // Section 8: Automated Test Verification Matrix
    drawText(
        "8. Automated Verification Matrix — 31 Tests Passing",
        in: CGRect(x: margin, y: 300, width: contentWidth, height: 20),
        font: .systemFont(ofSize: 13.5, weight: .bold),
        color: color(0x0F172A)
    )
    drawText(
        "Verified on iPad Pro 13-inch (M5) Simulator via Xcode 26.6 / iOS 26.5 SDK. 100% test pass rate.",
        in: CGRect(x: margin, y: 320, width: contentWidth, height: 14),
        font: .systemFont(ofSize: 8.5, weight: .regular),
        color: color(0x64748B)
    )

    let suites: [(String, String, String)] = [
        ("PageObjectTests (5 tests)", "NotesTests/Domain/PageObjectTests.swift", "Verifies move/4-corner resize anchoring opposite corner, rotation with rotated hit-testing, line endpoint handle stretching, and backward-compatible v1a JSON decoding."),
        ("LassoSelectionTests (2 tests)", "NotesTests/Domain/LassoSelectionTests.swift", "Verifies pure ray-casting point-in-polygon math, sample-point threshold enclosure, object center detection, and tiny tap rejection."),
        ("FilePageStoreTests (6 tests)", "NotesTests/Persistence/FilePageStoreTests.swift", "Verifies notebook round-trip, drawing separation, asset storage lifecycle, shape library JSON persistence, and preview PNG file operations."),
        ("LibraryViewModelTests (9 tests)", "NotesTests/Features/LibraryViewModelTests.swift", "Verifies PageObject lifecycle, cross-notebook clipboard copy/paste, shape library save/load/place/delete, debounced autosave, and batch move/delete."),
        ("ScribbleClassifierTests (6 tests)", "NotesTests/Domain/ScribbleClassifierTests.swift", "Verifies synthetic scribble detection over strokes, circle/zigzag non-triggering, and undo grouping."),
        ("NotebookHierarchyTests (3 tests)", "NotesTests/Domain/NotebookHierarchyTests.swift", "Verifies UUID permanence during reordering, paper overrides, and title sanitization.")
    ]

    var suiteY: CGFloat = 340
    for s in suites {
        let box = CGRect(x: margin, y: suiteY, width: contentWidth, height: 40)
        drawRoundedBox(ctx, rect: box, radius: 6, fill: color(0xF0FDF4), stroke: color(0x86EFAC), lineWidth: 0.9)
        drawText("✓  " + s.0, in: CGRect(x: box.minX + 8, y: box.minY + 4, width: 230, height: 13), font: .systemFont(ofSize: 8.5, weight: .bold), color: color(0x166534))
        drawText(s.1, in: CGRect(x: box.maxX - 250, y: box.minY + 4, width: 242, height: 13), font: .monospacedSystemFont(ofSize: 7.2, weight: .regular), color: color(0x15803D), alignment: .right)
        drawText(s.2, in: CGRect(x: box.minX + 8, y: box.minY + 18, width: contentWidth - 16, height: 20), font: .systemFont(ofSize: 7.6, weight: .regular), color: color(0x1E293B), lineSpacing: 1.1)
        suiteY += 44
    }

    // Section 9: Next Milestone Preview (v1c)
    let nextBox = CGRect(x: margin, y: suiteY + 6, width: contentWidth, height: 60)
    drawRoundedBox(ctx, rect: nextBox, radius: 8, fill: color(0xEFF6FF), stroke: color(0x60A5FA), lineWidth: 1.0)
    drawText("Roadmap: Milestone v1c — Structure (Next Up)", in: CGRect(x: nextBox.minX + 12, y: nextBox.minY + 6, width: contentWidth - 24, height: 14), font: .systemFont(ofSize: 9.5, weight: .bold), color: color(0x1D4ED8))
    drawText("• Tables: Set grid (user-configured rows & columns) rendered on the paper layer. Freehand handwriting inside cells without ink clipping. Dynamic row/column resizing.\n• Page-to-Page Links: Permanent UUID-based link badges placed on pages allowing instant cross-linking between concepts, lecture sections, and reference notes.", in: CGRect(x: nextBox.minX + 12, y: nextBox.minY + 22, width: contentWidth - 24, height: 32), font: .systemFont(ofSize: 7.8, weight: .regular), color: color(0x1E40AF), lineSpacing: 1.2)
}

// MARK: - Main Execution

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/Notes-v1b-Documentation.pdf"
let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

var mediaBox = pageRect
guard let consumer = CGDataConsumer(url: outputURL as CFURL),
      let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
    fatalError("Failed to create PDF context")
}

beginFlippedPage(pdfContext, mediaBox: &mediaBox, pageNumber: 1, totalPages: 3, sectionTitle: "1. Overview & Architecture Diagram")
drawPage1(pdfContext)
endFlippedPage(pdfContext)

beginFlippedPage(pdfContext, mediaBox: &mediaBox, pageNumber: 2, totalPages: 3, sectionTitle: "2. PageObjects, Handles & Lasso Engine")
drawPage2(pdfContext)
endFlippedPage(pdfContext)

beginFlippedPage(pdfContext, mediaBox: &mediaBox, pageNumber: 3, totalPages: 3, sectionTitle: "3. Shape Library, Storage & Verification")
drawPage3(pdfContext)
endFlippedPage(pdfContext)

pdfContext.closePDF()
print("Generated PDF at \(outputURL.path)")
