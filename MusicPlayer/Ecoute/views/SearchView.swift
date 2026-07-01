import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var playback: PlaybackState
    @State private var query: String = ""

    private let albumColumns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 20)]

    private var albumResults: [Album] { Array(viewModel.filteredAlbums(query: query).prefix(5)) }
    private var artistResults: [String] { Array(viewModel.filteredArtists(query: query).prefix(5)) }
    private var trackResults: [(track: Track, album: Album)] { Array(viewModel.allTracks(query: query).prefix(10)) }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()

            if query.isEmpty {
                emptyPrompt
            } else if albumResults.isEmpty && artistResults.isEmpty && trackResults.isEmpty {
                noResults
            } else {
                results
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search library", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Results

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if !albumResults.isEmpty {
                    resultSection("Albums") {
                        LazyVGrid(columns: albumColumns, spacing: 20) {
                            ForEach(albumResults) { album in
                                AlbumCard(album: album, isPlaying: album.id == viewModel.currentAlbum?.id)
                                    .onTapGesture { viewModel.selectBrowsingAlbum(album) }
                            }
                        }
                    }
                }

                if !artistResults.isEmpty {
                    resultSection("Artists") {
                        VStack(spacing: 0) {
                            ForEach(artistResults, id: \.self) { artist in
                                BrowserRow(
                                    name: artist,
                                    isSelected: false,
                                    isPlaying: viewModel.currentAlbum.map {
                                        ($0.artist.isEmpty ? "Unknown Artist" : $0.artist) == artist
                                    } ?? false
                                ) {
                                    viewModel.navigateToArtist(artist)
                                }
                            }
                        }
                    }
                }

                if !trackResults.isEmpty {
                    resultSection("Songs") {
                        VStack(spacing: 0) {
                            ForEach(trackResults, id: \.track.id) { pair in
                                SearchTrackRow(
                                    track: pair.track,
                                    album: pair.album,
                                    isCurrent: viewModel.currentAlbum?.id == pair.album.id
                                        && viewModel.currentTrackIndex == pair.album.tracks.firstIndex(where: { $0.id == pair.track.id }),
                                    isPlaying: playback.isPlaying
                                        && viewModel.currentAlbum?.id == pair.album.id
                                        && viewModel.currentTrackIndex == pair.album.tracks.firstIndex(where: { $0.id == pair.track.id })
                                ) {
                                    if let idx = pair.album.tracks.firstIndex(where: { $0.id == pair.track.id }) {
                                        viewModel.play(album: pair.album, trackIndex: idx)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    @ViewBuilder
    private func resultSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
    }

    // MARK: - Empty states

    private var emptyPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Search your library")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Find albums, artists, and songs")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Text("No results for \u{201C}\(query)\u{201D}")
                .font(.headline)
            Text("Try a different search.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Track row

private struct SearchTrackRow: View {
    let track: Track
    let album: Album
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                album.coverImage
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline)
                        .foregroundStyle(isCurrent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    Text("\(track.artist) — \(album.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background {
                if isCurrent {
                    Color.accentColor.opacity(0.08)
                } else if isHovered {
                    Color.primary.opacity(0.06)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
