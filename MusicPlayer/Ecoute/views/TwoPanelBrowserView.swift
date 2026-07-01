import SwiftUI

struct TwoPanelBrowserView: View {
    let items: [String]
    let selectedItem: String?
    let onSelectItem: (String) -> Void
    let isItemPlaying: (String) -> Bool
    let albumsForItem: (String) -> [Album]
    let currentAlbumID: UUID?
    let onSelectAlbum: (Album) -> Void
    var filterText: String = ""

    private var filteredItems: [String] {
        guard !filterText.isEmpty else { return items }
        let q = filterText.lowercased()
        return items.filter { $0.lowercased().contains(q) }
    }

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 330), spacing: 20)]

    var body: some View {
        HStack(spacing: 0) {
            itemList
                .frame(width: 320)

            Divider()

            if let item = selectedItem {
                albumGrid(for: item)
            } else {
                Color.clear
            }
        }
    }

    private var itemList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredItems, id: \.self) { item in
                        BrowserRow(
                            name: item,
                            isSelected: selectedItem == item,
                            isPlaying: isItemPlaying(item)
                        ) {
                            onSelectItem(item)
                        }
                    }
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
    }

    @ViewBuilder
    private func albumGrid(for item: String) -> some View {
        let albums = albumsForItem(item)
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(albums) { album in
                    AlbumCard(album: album, isPlaying: album.id == currentAlbumID)
                        .onTapGesture { onSelectAlbum(album) }
                }
            }
            .padding(24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }
}

// MARK: - Row

struct BrowserRow: View {
    let name: String
    let isSelected: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Spacer()
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

