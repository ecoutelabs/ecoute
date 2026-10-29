import SwiftUI

struct GenreBrowserView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let filterText: String

    var body: some View {
        TwoPanelBrowserView(
            items: viewModel.allGenres(),
            selectedItem: viewModel.selectedGenre,
            onSelectItem: { viewModel.selectedGenre = $0 },
            isItemPlaying: { viewModel.currentAlbum?.genres.contains($0) ?? false },
            albumsForItem: { viewModel.albumsForGenre($0) },
            currentAlbumID: viewModel.currentAlbum?.id,
            onSelectAlbum: { viewModel.selectBrowsingAlbum($0) },
            onPlayAlbum: { viewModel.play(album: $0) },
            thumbnailStyle: .mosaic,
            filterText: filterText
        )
    }
}
