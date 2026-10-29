//
//  EcouteApp.swift
//  Ecoute
//
//  Created by Bennett Zug on 11/24/25.
//

import SwiftUI

@main
struct EcouteApp: App {
    @StateObject private var viewModel = AppViewModel()

    init() {
        // No window tabs; frees ⌘T for the command bar.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    private func go(to section: LibrarySection) {
        viewModel.isCommandPaletteVisible = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            viewModel.isNowPlayingExpanded = false
        }
        viewModel.selectSection(section)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(viewModel.playback)
                .windowToolbarFullScreenVisibility(.onHover)
                .presentedWindowToolbarStyle(.unifiedCompact)
                
        }
        .defaultSize(width: 1020, height: 760)
        .commands {
            // The sidebar is always shown; drop View > Hide Sidebar.
            CommandGroup(replacing: .sidebar) {}

            CommandMenu("Controls") {
                Button("Next Track") { viewModel.playNext() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous Track") { viewModel.playPrevious() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
            }

            CommandMenu("Go") {
                Button("Command Bar") { viewModel.isCommandPaletteVisible.toggle() }
                    .keyboardShortcut("t", modifiers: .command)
                Divider()
                Button("Home") { go(to: .home) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Albums") { go(to: .albums) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Artists") { go(to: .artists) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Songs") { go(to: .songs) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Genres") { go(to: .genres) }
                    .keyboardShortcut("5", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(viewModel)
                .environmentObject(viewModel.playback)
        }
    }
}
