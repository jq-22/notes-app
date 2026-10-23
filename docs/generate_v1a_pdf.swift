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
    // Background
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(pageRect)

    // Top banner accent bar
    ctx.setFillColor(color(0x1E3A8A).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: pageWidth, height: 6))

    if pageNumber > 1 {
        drawText(
            "NOTES FOR iPadOS — MILESTONE v1a TECHNICAL DOCUMENTATION",
            in: CGRect(x: margin, y: 18, width: 340, height: 16),
            font: .systemFont(ofSize: 8.5, weight: .bold),
            color: color(0x64748B)
        )
        drawText(
            sectionTitle,
            in: CGRect(x: pageWidth - margin - 200, y: 18, width: 200, height: 16),
            font: .systemFont(ofSize: 8.5, weight: .semibold),
            color: color(0x1E3A8A),
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
        "github.com/jq-22/notes-app • Release v1a",
        in: CGRect(x: margin, y: pageHeight - 26, width: 260, height: 14),
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
    // Flip coordinate system so (0,0) is top-left (like UIKit/SwiftUI)
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

// MARK: - Page 1: Cover, Overview & Layered Architecture Diagram

func drawPage1(_ ctx: CGContext) {
    // Hero banner
    let heroRect = CGRect(x: margin, y: 28, width: contentWidth, height: 112)
    drawRoundedBox(ctx, rect: heroRect, radius: 12, fill: color(0x0F172A))

    drawText(
        "MILESTONE v1a — ARCHITECTURE & ENGINEERING GUIDE",
        in: CGRect(x: margin + 20, y: 44, width: contentWidth - 40, height: 16),
        font: .systemFont(ofSize: 9.5, weight: .bold),
        color: color(0x38BDF8)
    )
    drawText(
        "Notes for iPadOS (\"Notion with Apple Pencil\")",
        in: CGRect(x: margin + 20, y: 62, width: contentWidth - 40, height: 28),
        font: .systemFont(ofSize: 20, weight: .bold),
        color: .white
    )
    drawText(
        "Native Swift 6 • SwiftUI + UIKit/PencilKit • Strict Layered Architecture • 25 Automated Unit Tests",
        in: CGRect(x: margin + 20, y: 94, width: contentWidth - 40, height: 18),
        font: .systemFont(ofSize: 9.8, weight: .medium),
        color: color(0xCBD5E1)
    )
    drawText(
        "Target: iPadOS 26.5+ (iPad Only) | Repo: github.com/jq-22/notes-app | Release: v1a",
        in: CGRect(x: margin + 20, y: 114, width: contentWidth - 40, height: 16),
        font: .monospacedSystemFont(ofSize: 8.2, weight: .regular),
        color: color(0x94A3B8)
    )

    // Section 1: What Was Built in v1a
    drawText(
        "1. Executive Summary — What Was Built in Milestone v1a",
        in: CGRect(x: margin, y: 152, width: contentWidth, height: 20),
        font: .systemFont(ofSize: 13.5, weight: .bold),
        color: color(0x0F172A)
    )
    drawText(
        "Milestone v1a delivers a complete, production-structured handwriting notebook app for iPadOS. The codebase is organized into four strict dependency layers (Domain ← Persistence ← Features ← App) so business logic, geometric heuristics, and persistence are 100% unit-testable without UIKit or the simulator.",
        in: CGRect(x: margin, y: 173, width: contentWidth, height: 48),
        font: .systemFont(ofSize: 9.6, weight: .regular),
        color: color(0x334155),
        lineSpacing: 2.0
    )

    // 2x3 Feature Summary Cards
    let cards: [(String, String, UInt32)] = [
        ("Notebook → Section → Page", "3-column NavigationSplitView with permanent UUIDs, create/rename/reorder/delete (with confirmation), and multi-page batch move/delete.", 0xEFF6FF),
        ("A4 Paper Layer & Live Thumbnails", "595×842 pt A4 portrait canvas. Separate Lined, Squared, and Blank paper background layer + per-page overrides and live ink sidebar thumbnails.", 0xF0FDF4),
        ("Custom 4-Tool Popover & Ballpoint Pen", "Compact top-bar tool menu: Monoline Ballpoint Pen, Highlighter, Rubber (Object/Stroke vs Pixel), and 25%-scaled Ruler toggle + explicit Black/White swatches.", 0xFEFCE8),
        ("Apple Pencil Double-Tap & Undo/Redo", "UIPencilInteraction double-tap toggles between active Pen/Highlighter and Rubber. Top-left Full Screen toggle + Undo and Redo stroke buttons.", 0xFDF2F8),
        ("Scribble-to-Erase (1-Step Undo)", "Pure geometric classifier (ScribbleClassifier) detects back-and-forth scribbles over existing ink and removes covered strokes in a single undo step.", 0xF5F3FF),
        ("Fit-Width Zoom, Swipes & PDF Export", "Opens at Fit-to-Width in portrait/landscape, snaps to width on pinch, turns/creates pages on deliberate horizontal drag (0.42s slide), and exports vector PDFs.", 0xECFEFF)
    ]

    let cardW: CGFloat = (contentWidth - 12) / 2
    let cardH: CGFloat = 68
    for (i, card) in cards.enumerated() {
        let col = CGFloat(i % 2)
        let row = CGFloat(i / 2)
        let rect = CGRect(x: margin + col * (cardW + 12), y: 224 + row * (cardH + 8), width: cardW, height: cardH)
        drawRoundedBox(ctx, rect: rect, radius: 7, fill: color(card.2), stroke: color(0xCBD5E1), lineWidth: 0.8)
        drawText(
            card.0,
            in: CGRect(x: rect.minX + 10, y: rect.minY + 6, width: cardW - 20, height: 15),
            font: .systemFont(ofSize: 9.5, weight: .bold),
            color: color(0x0F172A)
        )
        drawText(
            card.1,
            in: CGRect(x: rect.minX + 10, y: rect.minY + 22, width: cardW - 20, height: 44),
            font: .systemFont(ofSize: 8.1, weight: .regular),
            color: color(0x334155),
            lineSpacing: 1.3
        )
    }

    // Section 2: Diagram 1 — Layered Architecture & Dependency Graph
    drawText(
        "2. Diagram 1 — Layered Architecture (Domain ← Persistence ← Features ← App)",
        in: CGRect(x: margin, y: 462, width: contentWidth, height: 20),
        font: .systemFont(ofSize: 12.0, weight: .bold),
        color: color(0x0F172A)
    )

    let diagRect = CGRect(x: margin, y: 484, width: contentWidth, height: 312)
    drawRoundedBox(ctx, rect: diagRect, radius: 10, fill: color(0xF8FAFC), stroke: color(0xCBD5E1), lineWidth: 1.0)

    // Draw 4 horizontal layer bands inside diagRect
    let layers: [(title: String, subtitle: String, files: [String], bg: UInt32, border: UInt32, y: CGFloat, h: CGFloat)] = [
        (
            "APP LAYER (Composition Root)",
            "Imports: Features, Persistence, Domain",
            ["NotesApp.swift (@main WindowGroup: wires FilePageStore → LibraryViewModel → LibraryRootView)"],
            0xE0E7FF, 0x4F46E5, 496, 48
        ),
        (
            "FEATURES & DESIGN SYSTEM (SwiftUI + PencilKit)",
            "Imports: Persistence (PageStore), Domain",
            [
                "Library/LibraryViewModel.swift",
                "Library/LibraryRootView.swift",
                "Library/PageThumbnailView.swift",
                "Library/PagePDFExporter.swift",
                "PageEditor/PageEditorView.swift",
                "PageEditor/PencilCanvasScrollView.swift",
                "PageEditor/DrawingToolMenuButton.swift",
                "PageEditor/PaperBackgroundView.swift"
            ],
            0xDBEAFE, 0x2563EB, 558, 92
        ),
        (
            "PERSISTENCE LAYER (Protocol + Atomic Disk I/O)",
            "Imports: Domain, Foundation ONLY",
            [
                "PageStore.swift (Protocol + PageStoreError)",
                "FilePageStore.swift (notebooks.json + Drawings/<uuid>.pkdrawing)"
            ],
            0xDCFCE7, 0x16A34A, 664, 52
        ),
        (
            "DOMAIN LAYER (Pure Value Types & Geometry)",
            "Imports: Foundation & CoreGraphics ONLY",
            [
                "Notebook.swift",
                "NoteSection.swift",
                "Page.swift",
                "PaperType.swift (PageGeometry)",
                "ScribbleClassifier.swift",
                "DrawingToolState.swift"
            ],
            0xFEF3C7, 0xD97706, 730, 56
        )
    ]

    for layer in layers {
        let box = CGRect(x: margin + 14, y: layer.y, width: contentWidth - 28, height: layer.h)
        drawRoundedBox(ctx, rect: box, radius: 7, fill: color(layer.bg), stroke: color(layer.border), lineWidth: 1.3)
        drawText(
            layer.title,
            in: CGRect(x: box.minX + 10, y: box.minY + 5, width: 265, height: 14),
            font: .systemFont(ofSize: 8.5, weight: .bold),
            color: color(layer.border)
        )
        drawText(
            layer.subtitle,
            in: CGRect(x: box.maxX - 210, y: box.minY + 5, width: 200, height: 14),
            font: .systemFont(ofSize: 7.6, weight: .medium),
            color: color(0x475569),
            alignment: .right
        )

        if layer.files.count <= 2 {
            let joined = layer.files.joined(separator: "  •  ")
            drawText(
                joined,
                in: CGRect(x: box.minX + 10, y: box.minY + 23, width: box.width - 20, height: 22),
                font: .monospacedSystemFont(ofSize: 7.4, weight: .medium),
                color: color(0x0F172A)
            )
        } else {
            let cols = (layer.files.count > 6) ? 2 : 3
            let pillW = (box.width - 20 - CGFloat(cols - 1) * 6) / CGFloat(cols)
            for (idx, f) in layer.files.enumerated() {
                let c = idx % cols
                let r = idx / cols
                let pillRect = CGRect(
                    x: box.minX + 10 + CGFloat(c) * (pillW + 6),
                    y: box.minY + 22 + CGFloat(r) * 16,
                    width: pillW,
                    height: 14
                )
                drawRoundedBox(ctx, rect: pillRect, radius: 3, fill: .white, stroke: color(layer.border, alpha: 0.35), lineWidth: 0.6)
                drawText(
                    f,
                    in: CGRect(x: pillRect.minX + 5, y: pillRect.minY + 2, width: pillW - 10, height: 11),
                    font: .monospacedSystemFont(ofSize: 7.3, weight: .medium),
                    color: color(0x1E293B)
                )
            }
        }
    }

    // Arrows between layers showing dependency direction downward (App -> Features -> Persistence -> Domain)
    let centerX = margin + contentWidth * 0.5
    drawArrow(ctx, from: CGPoint(x: centerX, y: 544), to: CGPoint(x: centerX, y: 557), color: color(0x475569))
    drawArrow(ctx, from: CGPoint(x: centerX, y: 650), to: CGPoint(x: centerX, y: 663), color: color(0x475569))
    drawArrow(ctx, from: CGPoint(x: centerX, y: 716), to: CGPoint(x: centerX, y: 729), color: color(0x475569))
}

// MARK: - Page 2: Domain Data Model, UUID Hierarchy & Storage Layout Diagram

func drawPage2(_ ctx: CGContext) {
    drawText(
        "3. Diagram 2 — Domain Data Model (UUID Hierarchy) & Disk Storage Layout",
        in: CGRect(x: margin, y: 46, width: contentWidth, height: 20),
        font: .systemFont(ofSize: 13.5, weight: .bold),
        color: color(0x0F172A)
    )
    drawText(
        "Every Notebook, NoteSection, and Page has a permanent UUID. Nothing is keyed by title or array index, so reordering, moving pages across sections, and future page links/sync never corrupt references. Drawing bytes (PKDrawing) are stored in separate per-page files.",
        in: CGRect(x: margin, y: 65, width: contentWidth, height: 42),
        font: .systemFont(ofSize: 9.2, weight: .regular),
        color: color(0x334155),
        lineSpacing: 1.8
    )

    let modelBox = CGRect(x: margin, y: 108, width: contentWidth, height: 225)
    drawRoundedBox(ctx, rect: modelBox, radius: 10, fill: color(0xF8FAFC), stroke: color(0xCBD5E1), lineWidth: 1.0)

    // 3 Entity boxes horizontally: Notebook -> NoteSection -> Page
    let boxW: CGFloat = 152
    let boxH: CGFloat = 128
    let yTop: CGFloat = 120

    let nbRect = CGRect(x: margin + 12, y: yTop, width: boxW, height: boxH)
    let secRect = CGRect(x: margin + 181, y: yTop, width: boxW, height: boxH)
    let pgRect = CGRect(x: margin + 350, y: yTop, width: boxW, height: boxH)

    drawRoundedBox(ctx, rect: nbRect, radius: 7, fill: .white, stroke: color(0x2563EB), lineWidth: 1.4)
    drawRoundedBox(ctx, rect: CGRect(x: nbRect.minX, y: nbRect.minY, width: boxW, height: 22), radius: 7, fill: color(0x2563EB))
    drawText("struct Notebook", in: CGRect(x: nbRect.minX + 8, y: nbRect.minY + 4, width: boxW - 16, height: 14), font: .monospacedSystemFont(ofSize: 9, weight: .bold), color: .white)
    drawText(
        "• id: UUID (permanent)\n• title: String\n• defaultPaperType: PaperType\n• sections: [NoteSection]\n• createdAt / updatedAt\n──────────────\n+ addSection()\n+ deleteSection(id:)\n+ moveSections()",
        in: CGRect(x: nbRect.minX + 8, y: nbRect.minY + 25, width: boxW - 16, height: 100),
        font: .monospacedSystemFont(ofSize: 7.4, weight: .regular),
        color: color(0x1E293B),
        lineSpacing: 1.2
    )

    drawRoundedBox(ctx, rect: secRect, radius: 7, fill: .white, stroke: color(0x0D9488), lineWidth: 1.4)
    drawRoundedBox(ctx, rect: CGRect(x: secRect.minX, y: secRect.minY, width: boxW, height: 22), radius: 7, fill: color(0x0D9488))
    drawText("struct NoteSection", in: CGRect(x: secRect.minX + 8, y: secRect.minY + 4, width: boxW - 16, height: 14), font: .monospacedSystemFont(ofSize: 9, weight: .bold), color: .white)
    drawText(
        "• id: UUID (permanent)\n• title: String\n• pages: [Page]\n• createdAt / updatedAt\n──────────────\n+ addPage(afterPageID:)\n+ deletePage(id:)\n+ deletePages(ids:)\n+ movePages()",
        in: CGRect(x: secRect.minX + 8, y: secRect.minY + 25, width: boxW - 16, height: 100),
        font: .monospacedSystemFont(ofSize: 7.4, weight: .regular),
        color: color(0x1E293B),
        lineSpacing: 1.2
    )

    drawRoundedBox(ctx, rect: pgRect, radius: 7, fill: .white, stroke: color(0x7C3AED), lineWidth: 1.4)
    drawRoundedBox(ctx, rect: CGRect(x: pgRect.minX, y: pgRect.minY, width: boxW, height: 22), radius: 7, fill: color(0x7C3AED))
    drawText("struct Page", in: CGRect(x: pgRect.minX + 8, y: pgRect.minY + 4, width: boxW - 16, height: 14), font: .monospacedSystemFont(ofSize: 9, weight: .bold), color: .white)
    drawText(
        "• id: UUID (permanent)\n• title: String\n• paperTypeOverride:\n    PaperType? (.lined |\n    .squared | .blank)\n• createdAt / updatedAt\n──────────────\n+ effectivePaperType()",
        in: CGRect(x: pgRect.minX + 8, y: pgRect.minY + 25, width: boxW - 16, height: 100),
        font: .monospacedSystemFont(ofSize: 7.4, weight: .regular),
        color: color(0x1E293B),
        lineSpacing: 1.2
    )

    drawArrow(ctx, from: CGPoint(x: nbRect.maxX + 2, y: yTop + 60), to: CGPoint(x: secRect.minX - 2, y: yTop + 60), color: color(0x475569))
    drawText("1..*", in: CGRect(x: nbRect.maxX, y: yTop + 44, width: 20, height: 12), font: .systemFont(ofSize: 7.5, weight: .bold), color: color(0x475569), alignment: .center)

    drawArrow(ctx, from: CGPoint(x: secRect.maxX + 2, y: yTop + 60), to: CGPoint(x: pgRect.minX - 2, y: yTop + 60), color: color(0x475569))
    drawText("1..*", in: CGRect(x: secRect.maxX, y: yTop + 44, width: 20, height: 12), font: .systemFont(ofSize: 7.5, weight: .bold), color: color(0x475569), alignment: .center)

    // Disk layout boxes inside modelBox bottom
    let jsonBox = CGRect(x: margin + 12, y: 262, width: 255, height: 60)
    let pkBox = CGRect(x: margin + 282, y: 262, width: 220, height: 60)

    drawRoundedBox(ctx, rect: jsonBox, radius: 6, fill: color(0xEFF6FF), stroke: color(0x3B82F6), lineWidth: 1.1)
    drawText("Application Support/NotesAppStorage/notebooks.json", in: CGRect(x: jsonBox.minX + 8, y: jsonBox.minY + 5, width: jsonBox.width - 16, height: 13), font: .monospacedSystemFont(ofSize: 7.5, weight: .bold), color: color(0x1D4ED8))
    drawText("Atomic JSON file storing [Notebook] hierarchy metadata.\nPreserves sub-second Date precision & permanent UUIDs.", in: CGRect(x: jsonBox.minX + 8, y: jsonBox.minY + 20, width: jsonBox.width - 16, height: 36), font: .systemFont(ofSize: 7.8, weight: .regular), color: color(0x334155), lineSpacing: 1.3)

    drawRoundedBox(ctx, rect: pkBox, radius: 6, fill: color(0xF5F3FF), stroke: color(0x8B5CF6), lineWidth: 1.1)
    drawText(".../Drawings/<page-uuid>.pkdrawing", in: CGRect(x: pkBox.minX + 8, y: pkBox.minY + 5, width: pkBox.width - 16, height: 13), font: .monospacedSystemFont(ofSize: 7.5, weight: .bold), color: color(0x6D28D9))
    drawText("Binary PKDrawing.dataRepresentation() per page.\nDebounced 400ms after stroke; flushed on background.", in: CGRect(x: pkBox.minX + 8, y: pkBox.minY + 20, width: pkBox.width - 16, height: 36), font: .systemFont(ofSize: 7.8, weight: .regular), color: color(0x334155), lineSpacing: 1.3)

    drawArrow(ctx, from: CGPoint(x: nbRect.midX, y: nbRect.maxY + 2), to: CGPoint(x: nbRect.midX, y: jsonBox.minY - 2), color: color(0x3B82F6))
    drawArrow(ctx, from: CGPoint(x: pgRect.midX, y: pgRect.maxY + 2), to: CGPoint(x: pgRect.midX, y: pkBox.minY - 2), color: color(0x8B5CF6))

    // Section 4: Diagram 3 — PageEditor Coordinate Stack, Zoom & Tool Pipeline
    drawText(
        "4. Diagram 3 — PageEditor View Stack, Fit-to-Width Zoom & 4-Tool Pipeline",
        in: CGRect(x: margin, y: 348, width: contentWidth, height: 20),
        font: .systemFont(ofSize: 12.5, weight: .bold),
        color: color(0x0F172A)
    )

    let editorDiag = CGRect(x: margin, y: 372, width: contentWidth, height: 210)
    drawRoundedBox(ctx, rect: editorDiag, radius: 10, fill: color(0xF8FAFC), stroke: color(0xCBD5E1), lineWidth: 1.0)

    // Left side: Visual layer stack
    let stackOuter = CGRect(x: margin + 14, y: 384, width: 245, height: 186)
    drawRoundedBox(ctx, rect: stackOuter, radius: 8, fill: color(0xE2E8F0), stroke: color(0x64748B), lineWidth: 1.2)
    drawText("CenteringScrollView (UIScrollView)", in: CGRect(x: stackOuter.minX + 10, y: stackOuter.minY + 6, width: 225, height: 14), font: .monospacedSystemFont(ofSize: 8.2, weight: .bold), color: color(0x0F172A))
    drawText("• Fit-to-Width initial zoom & ±8% pinch snap\n• Double-tap toggles Fit-Width ↔ Fit-Whole-Page\n• Deliberate horizontal drag (≥115pt) turns page", in: CGRect(x: stackOuter.minX + 10, y: stackOuter.minY + 21, width: 225, height: 36), font: .systemFont(ofSize: 7.8, weight: .regular), color: color(0x334155), lineSpacing: 1.3)

    let pageCont = CGRect(x: stackOuter.minX + 12, y: stackOuter.minY + 60, width: 221, height: 118)
    drawRoundedBox(ctx, rect: pageCont, radius: 6, fill: .white, stroke: color(0x2563EB), lineWidth: 1.2)
    drawText("pageContainerView (A4: 595 × 842 pt)", in: CGRect(x: pageCont.minX + 8, y: pageCont.minY + 5, width: 205, height: 13), font: .monospacedSystemFont(ofSize: 8.0, weight: .bold), color: color(0x1D4ED8))

    let layer1 = CGRect(x: pageCont.minX + 10, y: pageCont.minY + 23, width: 201, height: 40)
    drawRoundedBox(ctx, rect: layer1, radius: 5, fill: color(0xFEF9C3), stroke: color(0xCA8A04), lineWidth: 1.0)
    drawText("Layer 1 (Back): PaperBackgroundView", in: CGRect(x: layer1.minX + 6, y: layer1.minY + 4, width: 190, height: 12), font: .monospacedSystemFont(ofSize: 7.5, weight: .bold), color: color(0x854D0E))
    drawText("SwiftUI Canvas (.lined / .squared / .blank)\nRe-rasterizes at screenScale × zoomScale", in: CGRect(x: layer1.minX + 6, y: layer1.minY + 17, width: 190, height: 22), font: .systemFont(ofSize: 7.3, weight: .regular), color: color(0x713F12), lineSpacing: 1.1)

    let layer2 = CGRect(x: pageCont.minX + 10, y: pageCont.minY + 69, width: 201, height: 42)
    drawRoundedBox(ctx, rect: layer2, radius: 5, fill: color(0xDBEAFE), stroke: color(0x2563EB), lineWidth: 1.0)
    drawText("Layer 2 (Front): PKCanvasView", in: CGRect(x: layer2.minX + 6, y: layer2.minY + 4, width: 190, height: 12), font: .monospacedSystemFont(ofSize: 7.5, weight: .bold), color: color(0x1E40AF))
    drawText("Transparent (.clear), .pencilOnly policy\noverrideUserInterfaceStyle = .light (true B&W)", in: CGRect(x: layer2.minX + 6, y: layer2.minY + 17, width: 190, height: 22), font: .systemFont(ofSize: 7.3, weight: .regular), color: color(0x1E3A8A), lineSpacing: 1.1)

    // Right side: DrawingToolMenuButton & DrawingToolState
    let toolBox = CGRect(x: margin + 272, y: 384, width: 230, height: 186)
    drawRoundedBox(ctx, rect: toolBox, radius: 8, fill: .white, stroke: color(0x0D9488), lineWidth: 1.2)
    drawText("DrawingToolMenuButton + DrawingToolState", in: CGRect(x: toolBox.minX + 10, y: toolBox.minY + 6, width: 210, height: 14), font: .monospacedSystemFont(ofSize: 8.0, weight: .bold), color: color(0x0F766E))
    drawText(
        "1. Pen >\n   • PKInkingTool(.monoline) ballpoint (constant width)\n   • Size (1–24 pt), Opacity (15–100%), 8 colours\n   • Explicit Black & White (no dark-mode inversion)\n2. Highlighter >\n   • PKInkingTool(.marker)\n   • Size (6–40 pt), Opacity (15–100%), 8 colours\n3. Rubber >\n   • Object/Stroke (.vector) vs Pixel (.bitmap + size)\n   • Apple Pencil Double-Tap toggles Pen/Highlighter ↔ Rubber\n4. Ruler\n   • Toggles canvasView.isRulerActive (scaled 0.75×)",
        in: CGRect(x: toolBox.minX + 10, y: toolBox.minY + 24, width: 210, height: 156),
        font: .systemFont(ofSize: 7.8, weight: .regular),
        color: color(0x1E293B),
        lineSpacing: 1.6
    )

    drawArrow(ctx, from: CGPoint(x: toolBox.minX - 2, y: 477), to: CGPoint(x: stackOuter.maxX + 2, y: 477), color: color(0x0D9488))

    // Section 5: Diagram 4 — Scribble-to-Erase Decision Pipeline
    drawText(
        "5. Diagram 4 — Scribble-to-Erase Heuristic & Single-Step Undo Pipeline",
        in: CGRect(x: margin, y: 598, width: contentWidth, height: 20),
        font: .systemFont(ofSize: 13.5, weight: .bold),
        color: color(0x0F172A)
    )

    let scribBox = CGRect(x: margin, y: 620, width: contentWidth, height: 174)
    drawRoundedBox(ctx, rect: scribBox, radius: 10, fill: color(0xF8FAFC), stroke: color(0xCBD5E1), lineWidth: 1.0)

    let stepW: CGFloat = 116
    let stepH: CGFloat = 86
    let stepY: CGFloat = 632
    let steps: [(String, String, UInt32)] = [
        ("1. Stroke Ends", "PKCanvasViewDelegate\ncanvasViewDrawingDidChange\nSamples PKStrokePath\nvertices (≥4pt step).", 0xDBEAFE),
        ("2. Shape Metrics", "Checks:\n• Path / Diag ≥ 3.8\n• Sharp turns (≥125°) ≥ 4\n• Axis flips ≥ 4\n• Net disp ≤ 0.45", 0xFEF3C7),
        ("3. Overlap Test", "Expands scribble bbox\nby 6pt; finds existing\nstrokes with ≥25%\npoint/area overlap.", 0xF3E8FF),
        ("4. 1-Step Undo", "Replaces PKDrawing\nwith surviving strokes &\nregisters 1 Undo action\non canvas.undoManager.", 0xDCFCE7)
    ]

    for (idx, st) in steps.enumerated() {
        let sx = margin + 12 + CGFloat(idx) * (stepW + 9)
        let sRect = CGRect(x: sx, y: stepY, width: stepW, height: stepH)
        drawRoundedBox(ctx, rect: sRect, radius: 6, fill: color(st.2), stroke: color(0x64748B), lineWidth: 1.0)
        drawText(st.0, in: CGRect(x: sx + 6, y: stepY + 5, width: stepW - 12, height: 13), font: .systemFont(ofSize: 8.5, weight: .bold), color: color(0x0F172A))
        drawText(st.1, in: CGRect(x: sx + 6, y: stepY + 20, width: stepW - 12, height: 62), font: .systemFont(ofSize: 7.5, weight: .regular), color: color(0x334155), lineSpacing: 1.3)
        if idx < steps.count - 1 {
            drawArrow(ctx, from: CGPoint(x: sRect.maxX + 1, y: stepY + 43), to: CGPoint(x: sRect.maxX + 8, y: stepY + 43), color: color(0x475569))
        }
    }

    drawText(
        "False-Positive Protection (Verified in ScribbleClassifierTests): Straight underlines (0 reversals), closed circles (smooth turning angles < 125°), and 4-segment zigzag letters like 'W' or 'M' (only 3 corners and path/diagonal < 3.8) are strictly rejected so normal handwriting is never accidentally erased.",
        in: CGRect(x: margin + 12, y: 726, width: contentWidth - 24, height: 60),
        font: .systemFont(ofSize: 8.5, weight: .medium),
        color: color(0x334155),
        lineSpacing: 1.8
    )
}

// MARK: - Page 3: Complete File-by-File Reference & Verification Matrix

func drawPage3(_ ctx: CGContext) {
    drawText(
        "6. Complete Codebase File-by-File Reference (What is What)",
        in: CGRect(x: margin, y: 46, width: contentWidth, height: 20),
        font: .systemFont(ofSize: 13.5, weight: .bold),
        color: color(0x0F172A)
    )

    let tableRows: [(file: String, layer: String, responsibility: String)] = [
        ("Notes/App/NotesApp.swift", "App", "App entry point (@main). Instantiates FilePageStore and injects it into LibraryViewModel."),
        ("Notes/Domain/Notebook.swift", "Domain", "Root aggregate struct with permanent UUID, title, defaultPaperType, and ordered [NoteSection]."),
        ("Notes/Domain/NoteSection.swift", "Domain", "Section value type holding ordered [Page], addPage(afterPageID:), deletePages(ids:), and movePages()."),
        ("Notes/Domain/Page.swift", "Domain", "Page metadata struct with permanent UUID, title validation, and optional paperTypeOverride."),
        ("Notes/Domain/PaperType.swift", "Domain", "PaperType enum (.lined, .squared, .blank) and PageGeometry (A4 595×842pt, fit-width & snap math)."),
        ("Notes/Domain/ScribbleClassifier.swift", "Domain", "Pure geometric scribble-to-erase classifier with named threshold constants in Configuration."),
        ("Notes/Domain/DrawingToolState.swift", "Domain", "Value type for Pen/Highlighter/Rubber/Ruler, sizes, opacities, Black/White colours, and Pencil double-tap."),
        ("Notes/Persistence/PageStore.swift", "Persistence", "Protocol boundary separating [Notebook] metadata from per-page drawing Data + PageStoreError."),
        ("Notes/Persistence/FilePageStore.swift", "Persistence", "Atomic file persistence in Application Support (notebooks.json + Drawings/<page-uuid>.pkdrawing)."),
        ("Notes/Features/Library/LibraryViewModel.swift", "Features", "@Observable @MainActor coordinator: CRUD, selection, 400ms debounced autosave, swipe nav, batch ops."),
        ("Notes/Features/Library/LibraryRootView.swift", "Features", "3-column NavigationSplitView, context menus, rename/delete dialogs, and multi-page selection bar."),
        ("Notes/Features/Library/PageThumbnailView.swift", "Features", "A4 aspect-ratio sidebar thumbnail rendering PaperBackgroundView + live PKDrawing preview."),
        ("Notes/Features/Library/PagePDFExporter.swift", "Features", "Multi-page A4 vector PDF renderer combining paper lines/grid and PKDrawing strokes for sharing."),
        ("Notes/Features/PageEditor/PageEditorView.swift", "Features", "Hosts canvas + top toolbar (Full Screen, Undo/Redo, 4-Tool menu, Scribble toggle, Paper picker)."),
        ("Notes/Features/PageEditor/PencilCanvasScrollView.swift", "Features", "UIKit UIScrollView + PKCanvasView: fit/snap width, 0.42s slide page turn, ruler scaling, scribble undo."),
        ("Notes/Features/PageEditor/DrawingToolMenuButton.swift", "Features", "Compact top-bar popover matching sketch: Pen >, Highlighter >, Rubber >, and Ruler toggle."),
        ("Notes/Features/PageEditor/PaperBackgroundView.swift", "Features", "SwiftUI Canvas rendering Lined (with margin), Squared grid, or Blank paper behind the ink layer."),
        ("Notes/DesignSystem/Theme.swift", "Design", "Single source of truth for adaptive colours, spacing, typography, and thumbnail dimensions.")
    ]

    var yCursor: CGFloat = 70
    let rowH: CGFloat = 24.5

    // Table Header
    let headerRect = CGRect(x: margin, y: yCursor, width: contentWidth, height: 20)
    drawRoundedBox(ctx, rect: headerRect, radius: 4, fill: color(0x1E293B))
    drawText("File Path", in: CGRect(x: margin + 8, y: yCursor + 4, width: 195, height: 12), font: .systemFont(ofSize: 8.2, weight: .bold), color: .white)
    drawText("Layer", in: CGRect(x: margin + 206, y: yCursor + 4, width: 52, height: 12), font: .systemFont(ofSize: 8.2, weight: .bold), color: .white)
    drawText("Responsibility & Key Types", in: CGRect(x: margin + 262, y: yCursor + 4, width: contentWidth - 268, height: 12), font: .systemFont(ofSize: 8.2, weight: .bold), color: .white)
    yCursor += 22

    for (idx, row) in tableRows.enumerated() {
        let bg = (idx % 2 == 0) ? color(0xF8FAFC) : NSColor.white
        let rRect = CGRect(x: margin, y: yCursor, width: contentWidth, height: rowH)
        drawRoundedBox(ctx, rect: rRect, radius: 2, fill: bg, stroke: color(0xE2E8F0), lineWidth: 0.5)
        drawText(row.file, in: CGRect(x: margin + 6, y: yCursor + 4, width: 198, height: rowH - 4), font: .monospacedSystemFont(ofSize: 7.1, weight: .semibold), color: color(0x1E3A8A))
        drawText(row.layer, in: CGRect(x: margin + 206, y: yCursor + 4, width: 52, height: rowH - 4), font: .systemFont(ofSize: 7.5, weight: .bold), color: color(0x475569))
        drawText(row.responsibility, in: CGRect(x: margin + 262, y: yCursor + 3, width: contentWidth - 268, height: rowH - 4), font: .systemFont(ofSize: 7.5, weight: .regular), color: color(0x1E293B), lineSpacing: 1.1)
        yCursor += rowH
    }

    // Section 7: Unit Test Suite & Verification Summary
    yCursor += 14
    drawText(
        "7. Automated Test Suite & Hardware Verification Summary (25 / 25 Passing)",
        in: CGRect(x: margin, y: yCursor, width: contentWidth, height: 18),
        font: .systemFont(ofSize: 13.0, weight: .bold),
        color: color(0x0F172A)
    )
    yCursor += 22

    let testSuites: [(String, String, String)] = [
        ("NotebookHierarchyTests (6 tests)", "NotesTests/Domain/NotebookHierarchyTests.swift", "Verifies paper override resolution, title sanitization, inserting pages below current page, permanent UUID preservation on reorder, safe no-op deletes, and PageGeometry fit/snap-to-width math."),
        ("ScribbleClassifierTests (6 tests)", "NotesTests/Domain/ScribbleClassifierTests.swift", "Synthetic stroke arrays verifying scribble over existing ink triggers erase, while straight lines, closed circles, zigzag 'W'/'M' letters, empty-space scribbles, and disabled toggles never false-trigger."),
        ("DrawingToolStateTests (3 tests)", "NotesTests/Domain/DrawingToolStateTests.swift", "Verifies Apple Pencil double-tap toggling between Pen/Highlighter and Rubber, stroke width/opacity clamping, and independent Ruler toggling."),
        ("FilePageStoreTests (4 tests)", "NotesTests/Persistence/FilePageStoreTests.swift", "Verifies empty store initialization, full Notebook JSON round-trip with sub-second Date precision, isolated per-page .pkdrawing lifecycle, and corrupted JSON error surfacing."),
        ("LibraryViewModelTests (6 tests)", "NotesTests/Features/LibraryViewModelTests.swift", "Verifies full hierarchy creation & relaunch restore, drawing cleanup on delete, error alert surfacing, 400ms debounced autosave & page-switch flush, swipe page navigation, and multi-page batch move/delete/PDF export.")
    ]

    for suite in testSuites {
        let box = CGRect(x: margin, y: yCursor, width: contentWidth, height: 42)
        drawRoundedBox(ctx, rect: box, radius: 6, fill: color(0xF0FDF4), stroke: color(0x86EFAC), lineWidth: 0.9)
        drawText("✓  " + suite.0, in: CGRect(x: box.minX + 8, y: box.minY + 4, width: 230, height: 13), font: .systemFont(ofSize: 8.5, weight: .bold), color: color(0x166534))
        drawText(suite.1, in: CGRect(x: box.maxX - 250, y: box.minY + 4, width: 242, height: 13), font: .monospacedSystemFont(ofSize: 7.2, weight: .regular), color: color(0x15803D), alignment: .right)
        drawText(suite.2, in: CGRect(x: box.minX + 8, y: box.minY + 18, width: contentWidth - 16, height: 22), font: .systemFont(ofSize: 7.6, weight: .regular), color: color(0x1E293B), lineSpacing: 1.1)
        yCursor += 46
    }
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/Notes-v1a-Documentation.pdf"
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

beginFlippedPage(pdfContext, mediaBox: &mediaBox, pageNumber: 2, totalPages: 3, sectionTitle: "2. Data Model, View Stack & Scribble Pipeline")
drawPage2(pdfContext)
endFlippedPage(pdfContext)

beginFlippedPage(pdfContext, mediaBox: &mediaBox, pageNumber: 3, totalPages: 3, sectionTitle: "3. File Reference & Verification Matrix")
drawPage3(pdfContext)
endFlippedPage(pdfContext)

pdfContext.closePDF()
print("Generated PDF at \(outputURL.path)")
