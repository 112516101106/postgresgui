//
//  PostgresGUIApp.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData
import AppKit

@main
struct PostgresGUIApp: App {
    init() {
        #if DEBUG
        DebugLog.configureLogging()
        #endif
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ConnectionProfile.self,
            SavedQuery.self,
            QueryFolder.self,
            TabState.self,
            QueryHistory.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If migration fails, try to delete the old database
            // Critical errors should remain visible in Release builds
            Swift.print("⚠️ Failed to create ModelContainer: \(error)")
            Swift.print("⚠️ Attempting to delete old database and create fresh...")

            // Get the default store URL
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeURL = appSupportURL.appendingPathComponent("default.store")

            do {
                // Remove all store files
                let storeFiles = [
                    storeURL,
                    storeURL.appendingPathExtension("wal"),
                    storeURL.appendingPathExtension("shm")
                ]

                for file in storeFiles {
                    if FileManager.default.fileExists(atPath: file.path) {
                        try FileManager.default.removeItem(at: file)
                        DebugLog.print("✅ Removed: \(file.lastPathComponent)")
                    }
                }

                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even after cleanup: \(error)")
            }
        }
    }()

    var body: some Scene {
        Window("PostgresGUI", id: "main") {
            RootView()
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(action: openNewTab) {
                    Text("New Tab")
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button(action: closeCurrentTab) {
                    Text("Close Tab")
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            CommandGroup(after: .appInfo) {
                Button(action: {
                    if let url = URL(string: "https://postgresgui.com/support") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("Help and Support...", systemImage: "questionmark.circle")
                }

                Button(action: {
                    NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
                }) {
                    Label("Keyboard Shortcuts...", systemImage: "keyboard")
                }
            }

            CommandGroup(replacing: .help) {
                Button(action: {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }) {
                    Text("PostgresGUI Help")
                }
            }
        }

        Settings {
            SettingsView()
        }
    }

    // Menu commands can't access TabManager directly, so we use notifications.
    // RootView observes these and calls tabManager methods.
    private func openNewTab() {
        NotificationCenter.default.post(name: .createNewTab, object: nil)
    }
    private func closeCurrentTab() {
        NotificationCenter.default.post(name: .closeCurrentTab, object: nil)
    }
}

extension Notification.Name {
    static let createNewTab = Notification.Name("createNewTab")
    static let closeCurrentTab = Notification.Name("closeCurrentTab")
    static let showKeyboardShortcuts = Notification.Name("showKeyboardShortcuts")
    static let showHelp = Notification.Name("showHelp")
}
