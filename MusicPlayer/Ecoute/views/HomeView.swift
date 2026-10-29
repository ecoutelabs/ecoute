import SwiftUI

/// Rows of albums to get playing quickly: recently played, recently added, and
/// the library's biggest genres.
struct HomeView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private let rowLimit = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if viewModel.library.isEmpty {
                    Text("Your library is empty. Choose a music folder in Settings.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                } else {
                    row("Jump Back In", albums: viewModel.recentAlbums)
                    row("Recently Added", albums: viewModel.recentlyAddedAlbums)
                    ForEach(viewModel.topGenres(limit: 3), id: \.self) { genre in
                        row(genre, albums: viewModel.albumsForGenre(genre)) {
                            viewModel.selectSection(.genres)
                            viewModel.selectedGenre = genre
                        }
                    }
                }
            }
            .padding(.vertical, 24)
            // Room for the floating mini player.
            .padding(.bottom, 80)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    @ViewBuilder
    private func row(_ title: String, albums: [Album], onShowAll: (() -> Void)? = nil) -> some View {
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                    Spacer()
                    if let onShowAll {
                        Button("See All", action: onShowAll)
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 20) {
                        ForEach(albums.prefix(rowLimit)) { album in
                            HomeAlbumTile(album: album)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .scrollIndicators(.never)
            }
        }
    }
}

private struct HomeAlbumTile: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let album: Album

    var body: some View {
        AlbumCard(album: album, isPlaying: album.id == viewModel.currentAlbum?.id)
            .frame(width: 170)
            .onTapGesture { viewModel.selectBrowsingAlbum(album) }
    }
}
