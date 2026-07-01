import SwiftUI

struct ArtistListView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let filterText: String

    var body: some View {
        TwoPanelBrowserView(
            items: viewModel.artists,
            selectedItem: viewModel.selectedArtist,
            onSelectItem: { viewModel.selectedArtist = $0 },
            isItemPlaying: { artist in
                viewModel.currentAlbum.map {
                    ($0.artist.isEmpty ? "Unknown Artist" : $0.artist) == artist
                } ?? false
            },
            albumsForItem: { viewModel.albumsForArtist($0) },
            currentAlbumID: viewModel.currentAlbum?.id,
            onSelectAlbum: { viewModel.selectBrowsingAlbum($0) },
            filterText: filterText
        )
    }
}
