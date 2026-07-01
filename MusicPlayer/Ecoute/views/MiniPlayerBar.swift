import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var playback: PlaybackState
    let onExpand: () -> Void

    private var progress: CGFloat {
        guard playback.duration > 0 else { return 0 }
        return min(CGFloat(playback.position / playback.duration), 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            mainRow
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            progressBar
        }
        .frame(maxWidth: 620)
        .floatingGlass(cornerRadius: 50)
        .clipShape(RoundedRectangle(cornerRadius: 50, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 6)
    }

    // MARK: - Main row

    private var mainRow: some View {
        HStack(spacing: 16) {
            transportSection

            // Cover + info — tapping expands the player
            Button(action: onExpand) {
                HStack(spacing: 10) {
                    if let album = viewModel.currentAlbum {
                        album.coverImage
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    if let album = viewModel.currentAlbum,
                       let track = album.tracks[safe: viewModel.currentTrackIndex] {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onExpand) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Transport controls

    private var transportSection: some View {
        HStack(spacing: 20) {
            Button { viewModel.playPrevious() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)

            Button { viewModel.togglePlayback() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 22)
            }
            .buttonStyle(.plain)

            Button { viewModel.playNext() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.2))
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: max(geo.size.width * progress, 3))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Glass effect helper (kept for NowPlayingView use)

extension View {
    @ViewBuilder
    func floatingGlass(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                }
        }
    }
}
