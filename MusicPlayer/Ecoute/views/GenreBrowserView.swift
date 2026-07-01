import SwiftUI

struct GenreBrowserView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let filterText: String

    var body: some View {
        TwoPanelBrowserView(
            items: viewModel.allGenres(),
            selectedItem: viewModel.selectedGenre,
            onSelectItem: { viewModel.selectedGenre = $0 },
            isItemPlaying: { _ in false },
            albumsForItem: { viewModel.albumsForGenre($0) },
            currentAlbumID: viewModel.currentAlbum?.id,
            onSelectAlbum: { viewModel.selectBrowsingAlbum($0) },
            filterText: filterText
        )
    }
}
