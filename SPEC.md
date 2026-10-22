# SPEC.md — Notes app

## Vision
A handwriting-first notes app for iPad that does what paid apps put behind paywalls: proper organisation, reusable diagram shapes, tables, and (later) easy sharing with AI and a web view. Roughly "Notion with Apple Pencil, a bit more complex".

Primary use: university notes (lectures, wiring diagrams, handwritten maths, concept breakdowns) and designing verification plans for work. Single user for now.

---

## Milestone v1a — working notebook (BUILD THIS FIRST)

### Structure
- **Notebook → Section → Page.** One notebook per module, sections inside, pages inside sections.
- Sidebar navigation (`NavigationSplitView`): notebook list, then sections, then pages. Create, rename, reorder and delete at every level (delete asks for confirmation).
- Notebooks, sections and pages each have a permanent UUID.

### Pages
- A4 portrait only.
- Paper type: **lined, squared (grid) or blank**. Each notebook has a default; any page can override it. Changing a page's paper never touches its ink.
- Add a new page below the current one (inherits notebook default).
- Page thumbnails in the sidebar.

### Ink and tools
- Apple Pencil drawing via PencilKit. Four tools only: **pen, highlighter, eraser, ruler**. Colour choices only: no extra tool settings beyond what the system tool picker forces on us.
- Undo/redo (PencilKit's built-in).
- Pinch-to-zoom and pan; zoom range roughly 1x to 5x. Double-tap to reset.
- Finger draws nothing by default (pencil only); finger scrolls and zooms. Optional setting later.

### Scribble-to-erase
- After a stroke ends, if it looks like a scribble over existing ink, delete the scribble stroke and the strokes it covers.
- Heuristic (tune on device): many direction reversals, long path relative to bounding box, small-to-medium bounding box, and substantial overlap with existing strokes' bounds.
- The whole action is one undo step.
- It must not trigger on normal handwriting, circles, zigzag letters or underlines. False triggers are worse than missed scribbles, so err on the cautious side, and provide a setting to turn the feature off.

### Appearance
- Follow system light/dark mode. Both must be readable with every ink colour offered.

### Saving
- Autosave after each stroke (debounced) and on backgrounding.
- Reopening restores everything exactly.

### Definition of done for v1a
1. Create a notebook "Test", two sections, several pages, mixed paper types.
2. Write, highlight, erase, use the ruler; undo/redo works.
3. Scribble-to-erase works reliably on the iPad with the Pencil, without wrecking normal handwriting.
4. Force-quit and reopen: nothing is lost.
5. Light and dark mode both look right.
6. Unit tests pass for the data model and the scribble classifier.

---

## Roadmap (do not build yet; keep the data model compatible)

### v1b — objects and library
- Insert images onto a page.
- Basic shapes: rectangle, circle, arrow, line.
- Every object has the same handles: four corner dots to resize, a rectangle border to move, and a rotate handle sticking out.
- **Shape library:** lasso a drawing, "Save to library" with a label. Stored as ink strokes (so it can be recoloured) plus a transparent-background PNG preview. The library shows as a list of items saved in the current notebook. Tapping the notebook name at the top opens a scrollable list of notebooks to browse and pull items from. Paste = place as an object (resize, move, rotate). No connectors or snapping.
- Copy and paste of selected strokes and objects between pages and notebooks.

### v1c — structure
- **Tables:** a set grid (rows and columns, sized by the user) that the user then writes in by hand, e.g. columns for name / meaning / example. Ink is not locked to cells. Row and column resizing if practical.
- Links from one page to another (by page UUID), with a link object on the page.

### v2
- Typed text boxes, and typed headings with a heading list to jump between sections (Notion-style).
- Hidden transcript per page: handwriting converted to text with a copy button at the bottom, stored invisibly and never altering what is on screen. Work notebooks can be marked so they never go to AI features.

### v3
- Live sync between iPad and a web browser (backend TBD), web viewer.

### v4
- "Ask AI about this page" panel that uses the page's image and transcript directly, with no screenshots or pasting.

---

## Open questions (resolve during v1a)
- Pencil only for drawing, or let finger draw too? (Default: pencil only.)
- Keep Apple's tool picker as-is, or build a custom four-button toolbar if the extra controls get in the way?
- Scribble sensitivity thresholds: decided by testing on the iPad.
