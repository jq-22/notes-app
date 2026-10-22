# Architecture — Notes (iPadOS)

## Overview
Native iPadOS handwriting and structured notes app ("Notion with Apple Pencil").
Current milestone: **v1a — working notebook** (Complete: Notebook → Section → Page hierarchy, navigation, paper layer, PencilKit ink canvas, 4-tool picker, zoom/pan, scribble-to-erase with 1-step undo, live sidebar thumbnails, and debounced/background autosave).

## Directory & Module Map
```
Notes/
  App/
    NotesApp.swift                    Entry point & composition root; injects FilePageStore into LibraryViewModel
  Domain/                             Pure Swift models & logic (no UI or persistence imports)
    PaperType.swift                   PaperType (lined, squared, blank) & PageGeometry (A4 595x842 pt constants)
    Page.swift                        Page metadata value type (UUID, title, optional PaperType override, timestamps)
    NoteSection.swift                 Section value type holding ordered [Page] & pure move/insert/delete logic
    Notebook.swift                    Root aggregate holding ordered [NoteSection] and default PaperType
    ScribbleClassifier.swift          Pure geometric scribble-to-erase classifier with named threshold constants
  Persistence/                        Storage boundary & implementation (depends on Domain + Foundation only)
    PageStore.swift                   PageStore protocol + PageStoreError
    FilePageStore.swift               Atomic file persistence (notebooks.json + Drawings/<page-uuid>.pkdrawing)
  Features/
    Library/
      LibraryViewModel.swift          @Observable @MainActor state, CRUD, debounced drawing autosave, & error surfacing
      LibraryRootView.swift           3-column NavigationSplitView (Notebooks -> Sections & Pages -> Detail)
      PageThumbnailView.swift         A4 aspect-ratio sidebar thumbnail showing paper pattern, live PKDrawing preview, & page index
    PageEditor/
      PaperBackgroundView.swift       SwiftUI Canvas drawing lined/squared/blank background layer (never touches ink)
      PencilCanvasScrollView.swift    UIKit UIScrollView (1x-5x zoom) + PKCanvasView + 4-tool PKToolPicker + scribble-to-erase
      PageEditorView.swift            Page editor container with toolbar controls (scribble toggle, paper picker, add page below)
  DesignSystem/
    Theme.swift                       Centralized colours, spacing, fonts, and corner radii (light/dark adaptive)
NotesTests/
  Domain/
    NotebookHierarchyTests.swift      Unit tests for Notebook, NoteSection, Page, PaperType
    ScribbleClassifierTests.swift     Synthetic stroke unit tests (scribble, straight line, circle, zigzag 'W'/'M', overlap, toggle)
  Persistence/
    FilePageStoreTests.swift          Unit tests for FilePageStore round-trip, drawing separation, and error paths
  Features/
    LibraryViewModelTests.swift       Unit tests for LibraryViewModel CRUD, debounced autosave, and error surfacing
```

## Dependency Direction
`Domain` ← `Persistence` ← `Features` ← `App`
- `Domain` imports only `Foundation` and `CoreGraphics`.
- `Persistence` separates lightweight metadata (`notebooks.json`) from heavy drawing blobs (`Drawings/<page-uuid>.pkdrawing`).
- `Features` depend on `PageStore` via initializer injection so `LibraryViewModel` is unit-tested with an in-memory fake (`InMemoryPageStore`).

## Key Decisions
1. **`NoteSection` naming**: Named `NoteSection` in `Domain` so it never collides with SwiftUI's `Section` view builder inside `Features`.
2. **Permanent UUIDs everywhere**: `Notebook`, `NoteSection`, and `Page` are keyed strictly by `UUID`. Reordering mutates array positions without changing UUIDs.
3. **Pure `ScribbleClassifier` in `Domain`**: Takes `StrokeSample` and `[ExistingStrokeTarget]` (`CGPoint`/`CGRect`) so synthetic stroke tests run without a simulator or UIKit. In `PencilCanvasScrollView`, when `ScribbleClassifier` triggers, the scribble stroke and covered strokes are removed in one `undoManager` operation so a single Undo restores the erased ink.
4. **Target configuration**: `Notes.xcodeproj` uses Xcode 16+ `PBXFileSystemSynchronizedRootGroup` (automatically picks up files added to `Notes/` and `NotesTests/`), `TARGETED_DEVICE_FAMILY = 2` (iPad only), and `IPHONEOS_DEPLOYMENT_TARGET = 26.0`.

## Verified Commands
- **Compile & typecheck Domain + Persistence + LibraryViewModel via Command Line Tools (`swiftc`)**:
  ```bash
  swiftc -parse-as-library \
    Notes/Domain/*.swift \
    Notes/Persistence/*.swift \
    Notes/Features/Library/LibraryViewModel.swift \
    -module-name Notes -emit-module -emit-library -o /tmp/libNotes.dylib && rm -f /tmp/libNotes.dylib
  ```
- **Xcode Build & Test (once Xcode.app finishes installing)**:
  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  xcrun simctl list devices available | grep -i iPad
  xcodebuild test -project Notes.xcodeproj -scheme Notes -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'
  ```
