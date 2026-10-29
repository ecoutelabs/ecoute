import SwiftUI

struct TwoPanelBrowserView: View {
    enum ThumbnailStyle {
        /// First album cover, cropped to a circle (artists).
        case circle
        /// 2×2 mosaic of album covers (genres).
        case mosaic
    }

    let items: [String]
    let selectedItem: String?
    let onSelectItem: (String) -> Void
    let isItemPlaying: (String) -> Bool
    let albumsForItem: (String) -> [Album]
    let currentAlbumID: UUID?
    let onSelectAlbum: (Album) -> Void
    let onPlayAlbum: (Album) -> Void
    var thumbnailStyle: ThumbnailStyle = .circle
    var filterText: String = ""

    private var filteredItems: [String] {
        guard !filterText.isEmpty else { return items }
        let q = filterText.lowercased()
        return items.filter { $0.lowercased().contains(q) }
    }

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 20)]

    var body: some View {
        HStack(spacing: 0) {
            itemList
                .frame(width: 240)

            Divider()

            if let item = selectedItem {
                detail(for: item)
            } else {
                Color.clear
            }
        }
        .onAppear(perform: selectDefaultItem)
        .onChange(of: items) { _, _ in selectDefaultItem() }
    }

    /// Never open to an empty pane: pick what's playing, else the first item.
    private func selectDefaultItem() {
        guard selectedItem == nil || !items.contains(selectedItem!) else { return }
        if let item = items.first(where: isItemPlaying) ?? items.first {
            onSelectItem(item)
        }
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredItems, id: \.self) { item in
                        BrowserRow(
                            name: item,
                            isSelected: selectedItem == item,
                            isPlaying: isItemPlaying(item),
                            thumbnail: thumbnail(for: item)
                        ) {
                            onSelectItem(item)
                        }
                        .id(item)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onAppear {
                if let selectedItem { proxy.scrollTo(selectedItem, anchor: .center) }
            }
        }
    }

    private func thumbnail(for item: String) -> AnyView {
        let albums = albumsForItem(item)
        switch thumbnailStyle {
        case .circle:
            return AnyView(
                coverOrPlaceholder(albums.first)
                    .clipShape(Circle())
            )
        case .mosaic:
            return AnyView(
                Group {
                    if albums.count >= 4 {
                        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                            GridRow { cover(albums[0]); cover(albums[1]) }
                            GridRow { cover(albums[2]); cover(albums[3]) }
                        }
                    } else {
                        coverOrPlaceholder(albums.first)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            )
        }
    }

    private func cover(_ album: Album) -> some View {
        album.coverImage
            .resizable()
            .aspectRatio(1, contentMode: .fill)
    }

    @ViewBuilder
    private func coverOrPlaceholder(_ album: Album?) -> some View {
        if let album {
            cover(album)
        } else {
            Color.primary.opacity(0.08)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private func detail(for item: String) -> some View {
        let albums = albumsForItem(item)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(for: item, albums: albums)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(albums) { album in
                        AlbumCard(album: album, isPlaying: album.id == currentAlbumID)
                            .onTapGesture { onSelectAlbum(album) }
                    }
                }
            }
            .padding(24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    private func header(for item: String, albums: [Album]) -> some View {
        HStack(alignment: .center) {
            Text(item)
                .font(.system(size: 28, weight: .bold))
                .lineLimit(1)
            Spacer()
            if let first = albums.first {
                Button {
                    onPlayAlbum(first)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
    }
}

// MARK: - Row

struct BrowserRow: View {
    let name: String
    let isSelected: Bool
    let isPlaying: Bool
    var thumbnail: AnyView? = nil
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                if let thumbnail {
                    thumbnail
                        .frame(width: 28, height: 28)
                }
                Text(name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
