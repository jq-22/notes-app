# Architecture — Notes (iPadOS)

## Overview
Native iPadOS handwriting and structured notes app ("Notion with Apple Pencil").
Current milestone: **v1a — working notebook** (Step 1: Notebook → Section → Page hierarchy, navigation, paper layer, and persistence).

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
  Persistence/                        Storage boundary & implementation (depends on Domain + Foundation only)
    PageStore.swift                   PageStore protocol + PageStoreError
    FilePageStore.swift               Atomic file persistence (notebooks.json + Drawings/<page-uuid>.pkdrawing)
  Features/
    Library/
      LibraryViewModel.swift          @Observable @MainActor state & CRUD coordinator with autosave & error surfacing
      LibraryRootView.swift           3-column NavigationSplitView (Notebooks -> Sections & Pages -> Detail)
      PageThumbnailView.swift         A4 aspect-ratio sidebar thumbnail showing paper pattern & page index
    PageEditor/
      PaperBackgroundView.swift       SwiftUI Canvas drawing lined/squared/blank background layer (never touches ink)
      PageCanvasPlaceholderView.swift Scrollable A4 portrait workspace & per-page paper override toolbar
  DesignSystem/
    Theme.swift                       Centralized colours, spacing, fonts, and corner radii (light/dark adaptive)
NotesTests/
  Domain/
    NotebookHierarchyTests.swift      Unit tests for Notebook, NoteSection, Page, PaperType
  Persistence/
    FilePageStoreTests.swift          Unit tests for FilePageStore round-trip, drawing separation, and error paths
  Features/
    LibraryViewModelTests.swift       Unit tests for LibraryViewModel with InMemoryPageStore
```

## Dependency Direction
`Domain` ← `Persistence` ← `Features` ← `App`
- `Domain` imports only `Foundation` and `CoreGraphics`.
- `Persistence` separates lightweight metadata (`notebooks.json`) from heavy drawing blobs (`Drawings/<page-uuid>.pkdrawing`).
- `Features` depend on `PageStore` via initializer injection so `LibraryViewModel` is unit-tested with an in-memory fake (`InMemoryPageStore`).

## Key Decisions
1. **`NoteSection` naming**: Named `NoteSection` in `Domain` so it never collides with SwiftUI's `Section` view builder inside `Features`.
2. **Permanent UUIDs everywhere**: `Notebook`, `NoteSection`, and `Page` are keyed strictly by `UUID`. Reordering mutates array positions without changing UUIDs.
3. **Full sub-second `Date` fidelity in `FilePageStore`**: Uses `JSONEncoder`/`JSONDecoder` default `Date` strategy so `Equatable` checks after save/load preserve exact sub-second timestamps.
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
