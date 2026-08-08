//
//  QueryEditorView.swift
//  PostgresGUI
//
//  Container for query editor. Owns ViewModel and passes data to QueryEditorComponent.
//

import SwiftUI
import SwiftData

struct QueryEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: QueryEditorViewModel?

    /// Check if the current query (for this saved query) is executing
    private var isCurrentQueryExecuting: Bool {
        if let currentSavedQueryId = appState.query.currentSavedQueryId {
            if appState.query.executingSavedQueryId == currentSavedQueryId {
                return true
            }
            if appState.query.executingSavedQueryId == nil {
                return appState.query.isExecutingQuery && !appState.query.isExecutingTableQuery
            }
            return false
        }

        // Ad-hoc (unsaved) editor query execution should still show progress.
        return appState.query.isExecutingQuery && !appState.query.isExecutingTableQuery
    }

    var body: some View {
        QueryEditorComponent(
            isExecuting: isCurrentQueryExecuting,
            statusMessage: appState.query.statusMessage,
            lastExecutedAt: appState.query.lastExecutedAt,
            displayedElapsedTime: appState.query.displayedElapsedTime,
            autocompleteMetadataProvider: appState.connection.databaseService.autocompleteMetadataProvider,
            queryText: Binding(
                get: { appState.query.queryText },
                set: { appState.query.queryText = $0 }
            ),
            onRunQuery: {
                Task {
                    await viewModel?.executeQuery()
                }
            },
            onCancelQuery: {
                tabManager.activeTab?.cancelQuery()
                appState.query.cancelCurrentQuery()
            }
        )
        .onAppear {
            viewModel = QueryEditorViewModel(
                appState: appState,
                tabManager: tabManager,
                modelContext: modelContext
            )
        }
        .alert("No Database Selected", isPresented: Binding(
            get: { viewModel?.showNoDatabaseAlert ?? false },
            set: { viewModel?.showNoDatabaseAlert = $0 }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Select a database from the sidebar before running queries.")
        }
        .alert("Failed to Save Query", isPresented: Binding(
            get: { viewModel?.showSaveErrorAlert ?? false },
            set: { viewModel?.showSaveErrorAlert = $0 }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel?.saveErrorMessage ?? "")
        }
        .alert("Query Timed Out", isPresented: Binding(
            get: { appState.query.showTimeoutAlert },
            set: { appState.query.showTimeoutAlert = $0 }
        )) {
            Button("Try Again") {
                appState.query.showTimeoutAlert = false
                appState.query.queryError = nil
                Task {
                    await viewModel?.executeQuery()
                }
            }
            Button("Cancel", role: .cancel) {
                appState.query.showTimeoutAlert = false
            }
        } message: {
            Text("The query took longer than \(Int(Constants.Timeout.databaseOperation)) seconds. The database may be slow or unresponsive.")
        }
        .onChange(of: appState.query.queryText) { _, newText in
            viewModel?.handleQueryTextChange(newText)
        }
    }
}
