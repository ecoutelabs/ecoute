import SwiftUI
import AppKit

struct SongListView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var playback: PlaybackState

    struct SongRow: Identifiable {
        var id: UUID { track.id }
        let track: Track
        let album: Album
        // Index of this track within its album — needed to call play(album:trackIndex:)
        let albumTrackIndex: Int

        // Sort keys for the table columns.
        var title: String { track.titleSort ?? track.title }
        var artist: String { track.artistSort ?? track.artist }
        var albumTitle: String { album.titleSort ?? album.title }
        var genre: String { album.genres.first ?? "" }
        var year: String { album.year }
        var duration: TimeInterval { track.duration }
    }

    let filterText: String

    @State private var sortOrder: [KeyPathComparator<SongRow>] = []
    @State private var selection: Set<SongRow.ID> = []
    @SceneStorage("SongListColumns.v3") private var columnCustomization: TableColumnCustomization<SongRow>

    private var rows: [SongRow] {
        let rows: [SongRow] = viewModel.allTracks(query: filterText).compactMap { pair in
            guard let index = pair.album.tracks.firstIndex(where: { $0.id == pair.track.id }) else {
                return nil
            }
            return SongRow(track: pair.track, album: pair.album, albumTrackIndex: index)
        }
        return sortOrder.isEmpty ? rows : rows.sorted(using: sortOrder)
    }

    var body: some View {
        let rows = rows
        Table(rows, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            // Unlabeled leading column, as in Music: insets Title and holds the
            // now-playing indicator.
            TableColumn("") { row in
                if isCurrent(row) && playback.isPlaying {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                }
            }
            .width(16)
            .customizationID("indicator")

            TableColumn("Title", value: \.title) { row in
                Text(row.track.title)
                    .foregroundStyle(isCurrent(row) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 200)
            .customizationID("title")

            TableColumn("Artist", value: \.artist) { row in
                Text(row.track.artist).lineLimit(1)
            }
            .width(min: 60, ideal: 125, max: 300)
            .customizationID("artist")

            TableColumn("Album", value: \.albumTitle) { row in
                Text(row.album.title).lineLimit(1)
            }
            .width(min: 60, ideal: 125, max: 320)
            .customizationID("album")

            TableColumn("Genre", value: \.genre) { row in
                Text(row.genre).lineLimit(1)
            }
            .width(min: 50, ideal: 80, max: 160)
            .customizationID("genre")

            TableColumn("Year", value: \.year) { row in
                Text(row.year)
                    .monospacedDigit()
            }
            .width(min: 40, ideal: 44, max: 60)
            .customizationID("year")

            TableColumn("Time", value: \.duration) { row in
                Text(formattedDuration(row.duration))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 40, ideal: 46, max: 60)
            .customizationID("time")
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .background(FixedColumnWidths(defaults: [
            "": 16, "Title": 200, "Artist": 125, "Album": 125, "Genre": 80, "Year": 44, "Time": 46,
        ]))
        .contextMenu(forSelectionType: SongRow.ID.self) { _ in
            EmptyView()
        } primaryAction: { ids in
            guard let id = ids.first, let row = rows.first(where: { $0.id == id }) else { return }
            viewModel.play(album: row.album, trackIndex: row.albumTrackIndex)
        }
    }

    private func isCurrent(_ row: SongRow) -> Bool {
        viewModel.currentAlbum?.id == row.album.id
            && viewModel.currentTrackIndex == row.albumTrackIndex
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let total = max(Int(duration), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// SwiftUI's Table stretches its columns to fill the width. This finds the backing
/// NSTableView, turns that off and applies fixed widths (the user's saved widths, or
/// the defaults), so extra space is left empty after the last column, as in Music.
private struct FixedColumnWidths: NSViewRepresentable {
    /// Default width per column, keyed by column title.
    let defaults: [String: CGFloat]

    private static let storageKey = "SongListColumnWidths.v2"

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let root = view.window?.contentView,
                  let table = findTable(in: root) else { return }
            table.columnAutoresizingStyle = .noColumnAutoresizing
            // No type-to-select; bare letter keys are app shortcuts (e.g. F).
            table.allowsTypeSelect = false
            let saved = UserDefaults.standard.dictionary(forKey: Self.storageKey) as? [String: CGFloat] ?? [:]
            for column in table.tableColumns {
                if let width = saved[column.title] ?? defaults[column.title] {
                    column.width = width
                }
            }
            context.coordinator.observe(table)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView,
           table.headerView != nil,
           Set(table.tableColumns.map(\.title)) == Set(defaults.keys) {
            return table
        }
        for subview in view.subviews {
            if let table = findTable(in: subview) { return table }
        }
        return nil
    }

    final class Coordinator {
        private var observer: NSObjectProtocol?

        func observe(_ table: NSTableView) {
            observer = NotificationCenter.default.addObserver(
                forName: NSTableView.columnDidResizeNotification, object: table, queue: .main
            ) { _ in
                let widths = Dictionary(uniqueKeysWithValues: table.tableColumns.map { ($0.title, $0.width) })
                UserDefaults.standard.set(widths, forKey: FixedColumnWidths.storageKey)
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
