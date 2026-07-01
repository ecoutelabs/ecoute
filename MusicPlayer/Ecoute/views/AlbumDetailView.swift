import SwiftUI
import AppKit

struct AlbumDetailView: View {
    let album: Album
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var playback: PlaybackState

    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        let color = colorScheme == .dark
            ? viewModel.browsingAlbumAccentColorDark
            : viewModel.browsingAlbumAccentColorLight
        if let color { return color }
        // Dark: #9B74BA (lum 0.230, 4.0:1 on #262728)
        // Light: #473559 (lum 0.046, 10.9:1 on #FFFFFF)
        return colorScheme == .dark
            ? Color(red: 0.608, green: 0.455, blue: 0.729)
            : Color(red: 0.482, green: 0.353, blue: 0.639)
    }

    private var accentForeground: Color {
        guard let ns = NSColor(accent).usingColorSpace(.deviceRGB) else { return .white }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.6 ? .black : .white
    }

    private var isCurrentAlbum: Bool {
        album.id == viewModel.currentAlbum?.id
    }

    private var hasMultipleDiscs: Bool {
        Set(album.tracks.map { $0.discNumber ?? 1 }).count > 1
    }


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                albumHeader
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 32)

                Divider()

                trackList

                footer
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .toolbar {
            if !viewModel.isNowPlayingExpanded {
                ToolbarItem(placement: .navigation) {
                    Button {
                        viewModel.clearBrowsingAlbum()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
        }
    }

    // MARK: - Album header

    private var albumHeader: some View {
        HStack(alignment: .top, spacing: 28) {
            album.coverImage
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)

            VStack(alignment: .leading, spacing: 10) {
                Text(album.title)
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(3)

                Text(album.artist)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .onTapGesture { viewModel.navigateToArtist(album.artist) }

                HStack(spacing: 6) {
                    if !album.year.isEmpty {
                        Text(album.year)
                        Text("·").foregroundStyle(.tertiary)
                    }
                    Text("\(album.tracks.count) song\(album.tracks.count == 1 ? "" : "s")")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    if isCurrentAlbum {
                        viewModel.togglePlayback()
                    } else {
                        viewModel.play(album: album, trackIndex: 0)
                    }
                } label: {
                    Label(
                        isCurrentAlbum && playback.isPlaying ? "Pause" : "Play",
                        systemImage: isCurrentAlbum && playback.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(accentForeground)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 220, alignment: .topLeading)
        }
    }

    // MARK: - Track list

    private var trackList: some View {
        VStack(spacing: 0) {
            ForEach(discSections, id: \.disc) { section in
                if hasMultipleDiscs {
                    Text("Disc \(section.disc)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(Array(section.tracks.enumerated()), id: \.element.id) { offset, track in
                    let globalIndex = section.startIndex + offset
                    let isCurrent = isCurrentAlbum && viewModel.currentTrackIndex == globalIndex
                    let isPlaying = isCurrent && playback.isPlaying

                    TrackRow(
                        track: track,
                        index: globalIndex,
                        isCurrent: isCurrent,
                        isPlaying: isPlaying,
                        albumArtist: album.artist,
                        accent: accent
                    ) {
                        viewModel.play(album: album, trackIndex: globalIndex)
                    }

                    if offset < section.tracks.count - 1 {
                        Divider()
                            .padding(.leading, 60)
                    }
                }

                if hasMultipleDiscs, section.disc != discSections.last?.disc {
                    Divider().padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        let totalSecs = max(Int(album.tracks.reduce(0) { $0 + $1.duration }), 0)
        let hours = totalSecs / 3600
        let minutes = (totalSecs % 3600) / 60
        let durationStr = hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
        return Text("\(album.tracks.count) song\(album.tracks.count == 1 ? "" : "s"), \(durationStr)")
            .font(.footnote)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Disc grouping

    private struct DiscSection {
        let disc: Int
        let startIndex: Int
        let tracks: [Track]
    }

    private var discSections: [DiscSection] {
        var sections: [DiscSection] = []
        var currentDisc = -1
        var currentTracks: [Track] = []
        var sectionStart = 0
        var globalIndex = 0

        for track in album.tracks {
            let disc = track.discNumber ?? 1
            if disc != currentDisc {
                if !currentTracks.isEmpty {
                    sections.append(DiscSection(disc: currentDisc, startIndex: sectionStart, tracks: currentTracks))
                }
                currentDisc = disc
                sectionStart = globalIndex
                currentTracks = []
            }
            currentTracks.append(track)
            globalIndex += 1
        }

        if !currentTracks.isEmpty {
            sections.append(DiscSection(disc: currentDisc, startIndex: sectionStart, tracks: currentTracks))
        }

        return sections
    }
}

// MARK: - Track row

private struct TrackRow: View {
    let track: Track
    let index: Int
    let isCurrent: Bool
    let isPlaying: Bool
    let albumArtist: String
    let accent: Color
    let onTap: () -> Void

    @State private var isHovered = false

    /// Splits "Artist feat. Someone" into ("Artist", "Someone"), handling feat./ft./featuring.
    private var parsedArtist: (base: String, featured: String?) {
        let pattern = "(?i)\\s+(feat\\.?|ft\\.?|featuring)\\s+"
        if let range = track.artist.range(of: pattern, options: .regularExpression) {
            return (String(track.artist[..<range.lowerBound]),
                    String(track.artist[range.upperBound...]))
        }
        return (track.artist, nil)
    }

    private var displayTitle: String {
        if let featured = parsedArtist.featured {
            return "\(track.title) (feat. \(featured))"
        }
        return track.title
    }

    private var displayArtist: String? {
        let base = parsedArtist.base
        return base != albumArtist ? base : nil
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Group {
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 15))
                            .foregroundStyle(accent)
                    } else {
                        let num = track.trackNumber > 0 ? track.trackNumber : (index + 1)
                        Text("\(num)")
                            .font(.system(size: 15).monospacedDigit())
                            .foregroundStyle(isCurrent ? AnyShapeStyle(accent) : AnyShapeStyle(.tertiary))
                    }
                }
                .frame(width: 44, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayTitle)
                        .font(.system(size: 15))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(accent) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    if let artist = displayArtist {
                        Text(artist)
                            .font(.system(size: 12))
                            .foregroundStyle(isCurrent ? AnyShapeStyle(accent.opacity(0.8)) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(formattedDuration(track.duration))
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 8)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background {
                if isCurrent {
                    accent.opacity(0.08)
                } else if isHovered {
                    Color.primary.opacity(0.06)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let total = max(Int(duration), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
