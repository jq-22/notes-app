//
//  NotesApp.swift
//  Notes
//
//  Responsibility: App entry point and composition root. Wires Persistence and Library together.
//

import SwiftUI

@main
struct NotesApp: App {
    @State private var viewModel: LibraryViewModel

    init() {
        let store = FilePageStore()
        _viewModel = State(initialValue: LibraryViewModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            LibraryRootView(viewModel: viewModel)
        }
    }
}
