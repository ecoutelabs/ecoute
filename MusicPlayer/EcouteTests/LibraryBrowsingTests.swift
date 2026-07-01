@testable import Ecoute
import XCTest

final class LibraryBrowsingTests: XCTestCase {

    // MARK: - Section selection

    @MainActor
    func testSelectSectionUpdatesSelectedSection() {
        let vm = AppViewModel()
        vm.selectSection(.artists)
        XCTAssertEqual(vm.selectedSection, .artists)
    }

    @MainActor
    func testSelectSectionClearsBrowsingAlbum() {
        let vm = AppViewModel()
        vm.selectBrowsingAlbum(makeAlbum(title: "Test", artist: "Artist", year: "2020"))
        XCTAssertNotNil(vm.browsingAlbum)

        vm.selectSection(.songs)
        XCTAssertNil(vm.browsingAlbum)
    }

    @MainActor
    func testSelectSectionSameValueStillClearsBrowsingAlbum() {
        let vm = AppViewModel()
        vm.selectBrowsingAlbum(makeAlbum(title: "Test", artist: "Artist", year: "2020"))
        vm.selectSection(.albums) // already .albums by default
        XCTAssertNil(vm.browsingAlbum)
    }

    // MARK: - Browsing album

    @MainActor
    func testSelectBrowsingAlbumSetsBrowsingAlbum() {
        let vm = AppViewModel()
        let album = makeAlbum(title: "Lift Yr. Skinny Fists", artist: "Godspeed You! Black Emperor", year: "2000")
        vm.selectBrowsingAlbum(album)
        XCTAssertEqual(vm.browsingAlbum?.id, album.id)
    }

    @MainActor
    func testClearBrowsingAlbumClearsBrowsingAlbum() {
        let vm = AppViewModel()
        vm.selectBrowsingAlbum(makeAlbum(title: "Test", artist: "Artist", year: "2020"))
        vm.clearBrowsingAlbum()
        XCTAssertNil(vm.browsingAlbum)
    }

    // MARK: - filteredAlbums

    @MainActor
    func testFilteredAlbumsReturnsAllWhenSearchEmpty() {
        let vm = AppViewModel()
        vm.library = [
            makeAlbum(title: "OK Computer", artist: "Radiohead", year: "1997"),
            makeAlbum(title: "Dummy", artist: "Portishead", year: "1994")
        ]
        vm.searchText = ""
        XCTAssertEqual(vm.filteredAlbums().count, 2)
    }

    @MainActor
    func testFilteredAlbumsFiltersByAlbumTitle() {
        let vm = AppViewModel()
        vm.library = [
            makeAlbum(title: "OK Computer", artist: "Radiohead", year: "1997"),
            makeAlbum(title: "Dummy", artist: "Portishead", year: "1994")
        ]
        vm.searchText = "ok"
        let results = vm.filteredAlbums()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "OK Computer")
    }

    @MainActor
    func testFilteredAlbumsFiltersByArtist() {
        let vm = AppViewModel()
        vm.library = [
            makeAlbum(title: "OK Computer", artist: "Radiohead", year: "1997"),
            makeAlbum(title: "Dummy", artist: "Portishead", year: "1994")
        ]
        vm.searchText = "portishead"
        let results = vm.filteredAlbums()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Dummy")
    }

    @MainActor
    func testFilteredAlbumsSortsByArtistThenYear() {
        let vm = AppViewModel()
        vm.library = [
            makeAlbum(title: "Kid A", artist: "Radiohead", year: "2000"),
            makeAlbum(title: "Dummy", artist: "Portishead", year: "1994"),
            makeAlbum(title: "OK Computer", artist: "Radiohead", year: "1997")
        ]
        vm.searchText = ""
        let titles = vm.filteredAlbums().map(\.title)
        XCTAssertEqual(titles, ["Dummy", "OK Computer", "Kid A"])
    }

    // MARK: - allTracks sorting

    @MainActor
    func testAllTracksSortsByArtistThenTrackNumber() {
        let vm = AppViewModel()
        let albumB = makeAlbum(title: "Album B", artist: "B Artist", year: "2020", tracks: [
            makeTrack(title: "B1", artist: "B Artist", trackNumber: 1),
            makeTrack(title: "B2", artist: "B Artist", trackNumber: 2)
        ])
        let albumA = makeAlbum(title: "Album A", artist: "A Artist", year: "2019", tracks: [
            makeTrack(title: "A1", artist: "A Artist", trackNumber: 1)
        ])
        vm.library = [albumB, albumA]

        let all = vm.allTracks()

        XCTAssertEqual(all.map(\.track.title), ["A1", "B1", "B2"])
    }

    @MainActor
    func testAllTracksSortsByAlbumYearWithinArtist() {
        let vm = AppViewModel()
        let newer = makeAlbum(title: "Newer", artist: "Same Artist", year: "2020", tracks: [
            makeTrack(title: "New Song", artist: "Same Artist", trackNumber: 1)
        ])
        let older = makeAlbum(title: "Older", artist: "Same Artist", year: "2010", tracks: [
            makeTrack(title: "Old Song", artist: "Same Artist", trackNumber: 1)
        ])
        vm.library = [newer, older]

        let all = vm.allTracks()

        XCTAssertEqual(all.map(\.track.title), ["Old Song", "New Song"])
    }

    @MainActor
    func testAllTracksSortsByDiscThenTrackNumberWithinAlbum() {
        let vm = AppViewModel()
        let album = makeAlbum(title: "Double Album", artist: "Artist", year: "2000", tracks: [
            makeTrack(title: "D2T1", artist: "Artist", trackNumber: 1, discNumber: 2),
            makeTrack(title: "D1T2", artist: "Artist", trackNumber: 2, discNumber: 1),
            makeTrack(title: "D1T1", artist: "Artist", trackNumber: 1, discNumber: 1)
        ])
        vm.library = [album]

        let all = vm.allTracks()

        XCTAssertEqual(all.map(\.track.title), ["D1T1", "D1T2", "D2T1"])
    }

    // MARK: - allTracks search filtering

    @MainActor
    func testAllTracksFiltersByTrackTitle() {
        let vm = AppViewModel()
        vm.library = [
            makeAlbum(title: "Album", artist: "Artist", year: "2000", tracks: [
                makeTrack(title: "Fearless", artist: "Artist", trackNumber: 1),
                makeTrack(title: "Love Story", artist: "Artist", trackNumber: 2)
            ])
        ]
        vm.searchText = "love"

        XCTAssertEqual(vm.allTracks().map(\.track.title), ["Love Story"])
    }

    @MainActor
    func testAllTracksFiltersByAlbumTitle() {
        let vm = AppViewModel()
        vm.library = [
            makeAlbum(title: "Fearless", artist: "Taylor Swift", year: "2008", tracks: [
                makeTrack(title: "Track 1", artist: "Taylor Swift", trackNumber: 1)
            ]),
            makeAlbum(title: "After Hours", artist: "The Weeknd", year: "2020", tracks: [
                makeTrack(title: "Track 2", artist: "The Weeknd", trackNumber: 1)
            ])
        ]
        vm.searchText = "fearless"

        XCTAssertEqual(vm.allTracks().map(\.track.title), ["Track 1"])
    }

    @MainActor
    func testAllTracksFiltersByArtist() {
        let vm = AppViewModel()
        vm.library = [
            makeAlbum(title: "Album A", artist: "Radiohead", year: "1997", tracks: [
                makeTrack(title: "Paranoid Android", artist: "Radiohead", trackNumber: 1)
            ]),
            makeAlbum(title: "Album B", artist: "Portishead", year: "1994", tracks: [
                makeTrack(title: "Sour Times", artist: "Portishead", trackNumber: 1)
            ])
        ]
        vm.searchText = "radiohead"

        XCTAssertEqual(vm.allTracks().map(\.track.title), ["Paranoid Android"])
    }

    @MainActor
    func testAllTracksEmptySearchReturnsAll() {
        let vm = AppViewModel()
        vm.library = [
            makeAlbum(title: "Album", artist: "Artist", year: "2000", tracks: [
                makeTrack(title: "T1", artist: "Artist", trackNumber: 1),
                makeTrack(title: "T2", artist: "Artist", trackNumber: 2)
            ])
        ]
        vm.searchText = ""

        XCTAssertEqual(vm.allTracks().count, 2)
    }

    // MARK: - Helpers

    private func makeAlbum(
        title: String,
        artist: String,
        year: String,
        tracks: [Track]? = nil
    ) -> Album {
        Album(
            title: title,
            artist: artist,
            year: year,
            coverData: nil,
            tracks: tracks ?? [makeTrack(title: "Track", artist: artist, trackNumber: 1)]
        )
    }

    private func makeTrack(
        title: String,
        artist: String,
        trackNumber: Int,
        discNumber: Int? = nil
    ) -> Track {
        Track(
            url: URL(fileURLWithPath: "/tmp/\(title).mp3"),
            title: title,
            duration: 200,
            discNumber: discNumber,
            trackNumber: trackNumber,
            artist: artist
        )
    }
}
