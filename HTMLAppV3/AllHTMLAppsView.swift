import SwiftUI
import UIKit

struct AllHTMLAppsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("librarySortMode") private var librarySortModeRaw = LibrarySortMode.alphabeticalAZ.rawValue
    @AppStorage("librarySortDateBasis") private var librarySortDateBasisRaw = LibrarySortDateBasis.modified.rawValue
    @AppStorage("libraryFavoritesOnTop") private var libraryFavoritesOnTop = true

    @State private var searchText = ""

    private var sortMode: LibrarySortMode {
        LibrarySortMode(rawValue: librarySortModeRaw) ?? .alphabeticalAZ
    }

    private var sortDateBasis: LibrarySortDateBasis {
        LibrarySortDateBasis(rawValue: librarySortDateBasisRaw) ?? .modified
    }

    private var visibleApps: [SavedHTMLApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = query.isEmpty ? store.apps : store.results(for: query)
        return LibrarySorter.sortedApps(
            candidates,
            mode: sortMode,
            dateBasis: sortDateBasis,
            favoritesOnTop: libraryFavoritesOnTop
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.apps.isEmpty {
                    ContentUnavailableViewCompat(
                        title: "No HTML Apps",
                        systemImage: "square.grid.2x2",
                        message: "Saved HTML apps will appear here regardless of which folder contains them."
                    )
                } else if visibleApps.isEmpty {
                    ContentUnavailableViewCompat(
                        title: "No Results",
                        systemImage: "magnifyingglass",
                        message: "Search checks every saved HTML app, including apps inside nested folders."
                    )
                } else {
                    List {
                        Section {
                            ForEach(visibleApps) { app in
                                Button {
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        store.launch(app)
                                    }
                                } label: {
                                    ListAppRow(app: app, refreshing: false)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                            store.launch(app)
                                        }
                                    } label: {
                                        Label("Open", systemImage: "play.fill")
                                    }
                                    Button {
                                        store.toggleFavorite(app)
                                    } label: {
                                        Label(
                                            app.isFavorite == true ? "Remove from Favorites" : "Favorite",
                                            systemImage: app.isFavorite == true ? "star.slash" : "star.fill"
                                        )
                                    }
                                    Button {
                                        UIPasteboard.general.string = app.id
                                    } label: {
                                        Label("Copy ID", systemImage: "number")
                                    }
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            }
                        } header: {
                            Text("\(visibleApps.count) of \(store.apps.count) HTML Apps")
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("All HTML Apps")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search all HTML apps")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
