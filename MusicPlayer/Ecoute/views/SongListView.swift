import SwiftUI

struct SongListView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var playback: PlaybackState

    struct SongRow: Identifiable {
        var id: UUID { track.id }
        let track: Track
        let album: Album
        // Index of this track within its album — needed to call play(album:trackIndex:)
        let albumTrackIndex: Int
    }

    let filterText: String

    private var rows: [SongRow] {
        viewModel.allTracks(query: filterText).compactMap { pair in
            guard let index = pair.album.tracks.firstIndex(where: { $0.id == pair.track.id }) else {
                return nil
            }
            return SongRow(track: pair.track, album: pair.album, albumTrackIndex: index)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    ForEach(rows) { row in
                        let isCurrent = viewModel.currentAlbum?.id == row.album.id
                            && viewModel.currentTrackIndex == row.albumTrackIndex

                        SongRowView(
                            row: row,
                            isCurrent: isCurrent,
                            isPlaying: isCurrent && playback.isPlaying,
                            onTap: { viewModel.play(album: row.album, trackIndex: row.albumTrackIndex) }
                        )
                        .background(
                            isCurrent
                                ? Color.accentColor.opacity(0.08)
                                : Color.clear
                        )
                    }
                } header: {
                    columnHeaders
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    // MARK: - Column headers

    private var columnHeaders: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Indicator column
                Color.clear.frame(width: 44)

                Text("Title")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Artist")
                    .frame(width: 180, alignment: .leading)
                Text("Album")
                    .frame(width: 200, alignment: .leading)
                Text("Time")
                    .frame(width: 52, alignment: .trailing)
                    .padding(.trailing, 16)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(.background)

            Divider()
        }
    }
}

// MARK: - Song row

private struct SongRowView: View {
    let row: SongListView.SongRow
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Playing indicator
                Group {
                    if isPlaying {
                        Image(systemName: "waveform")
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Color.clear
                    }
                }
                .font(.caption)
                .frame(width: 36, alignment: .center)

                // Title
                Text(row.track.title)
                    .font(.subheadline)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Artist
                Text(row.track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 180, alignment: .leading)

                // Album
                Text(row.album.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 200, alignment: .leading)

                // Duration
                Text(formattedDuration(row.track.duration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 52, alignment: .trailing)
                    .padding(.trailing, 8)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let total = max(Int(duration), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
