import SwiftUI

struct AlbumGridView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let filterText: String

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 330), spacing: 20)]

    var body: some View {
        Group {
            if viewModel.library.isEmpty {
                emptyLibraryPrompt
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(viewModel.filteredAlbums(query: filterText)) { album in
                            AlbumCard(album: album, isPlaying: album.id == viewModel.currentAlbum?.id)
                                .onTapGesture {
                                    viewModel.selectBrowsingAlbum(album)
                                }
                        }
                    }
                    .padding(24)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
            }
        }
    }

    private var emptyLibraryPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.house")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No music library")
                .font(.headline)
            Text("Open Settings to choose your music folder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Album card (reused by TwoPanelBrowserView)

struct AlbumCard: View {
    let album: Album
    let isPlaying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            album.coverImage
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    if isPlaying {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.6), lineWidth: 2)
                    }
                }
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(album.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !album.year.isEmpty {
                    Text(album.year)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
