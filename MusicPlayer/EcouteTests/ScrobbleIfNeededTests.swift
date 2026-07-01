@testable import Ecoute
import XCTest

/// Scrobble rules under test:
/// - duration must be > 30s
/// - session key + start date required
/// - listen time must reach min(50% duration, 240s)
/// - listen time is actual playback, not just position; seeks don't count as listening
/// - only once per track session
final class ScrobbleIfNeededTests: XCTestCase {
    private let scrobbleHost = "ws.audioscrobbler.com"

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.allowedHost = scrobbleHost
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.allowedHost = nil
        super.tearDown()
    }

    @MainActor
    func testScrobbleWhenThresholdMetWithSessionAndStartDate() async throws {
        let expectation = expectation(description: "scrobble sent")
        MockURLProtocol.requestHandler = { request in
            expectation.fulfill()
            let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let track = Track(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            title: "Long Enough",
            duration: 200,
            trackNumber: 1,
            artist: "Artist"
        )
        let album = Album(title: "Album", artist: "Artist", year: "2024", coverData: nil, tracks: [track])
        let (vm, _, advance) = makeVM(track: track, album: album)

        vm.playback.position = 120 // meets 50% threshold
        advance(120)
        vm.scrobbleIfNeeded()

        await fulfillment(of: [expectation], timeout: 0.5)
    }

    @MainActor
    func testDoesNotScrobbleWhenDurationTooShort() async throws {
        let expectation = expectation(description: "no scrobble short track")
        expectation.isInverted = true
        MockURLProtocol.requestHandler = { request in
            expectation.fulfill()
            let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let track = Track(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            title: "Too Short",
            duration: 30,
            trackNumber: 1,
            artist: "Artist"
        )
        let album = Album(title: "Album", artist: "Artist", year: "2024", coverData: nil, tracks: [track])
        let (vm, _, advance) = makeVM(track: track, album: album)

        vm.playback.position = 40
        advance(40)
        vm.scrobbleIfNeeded()

        await fulfillment(of: [expectation], timeout: 0.3)
    }

    @MainActor
    func testDoesNotScrobbleWithoutSessionKey() async throws {
        let expectation = expectation(description: "no scrobble without session")
        expectation.isInverted = true
        MockURLProtocol.requestHandler = { request in
            expectation.fulfill()
            let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let track = Track(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            title: "Needs Session",
            duration: 180,
            trackNumber: 1,
            artist: "Artist"
        )
        let album = Album(title: "Album", artist: "Artist", year: "2024", coverData: nil, tracks: [track])
        let (vm, _, advance) = makeVM(track: track, album: album, sessionKey: nil)

        vm.playback.position = 120
        advance(120)
        vm.scrobbleIfNeeded()

        await fulfillment(of: [expectation], timeout: 0.3)
    }

    @MainActor
    func testDoesNotScrobbleWithoutStartDate() async throws {
        let expectation = expectation(description: "no scrobble without start date")
        expectation.isInverted = true
        MockURLProtocol.requestHandler = { request in
            expectation.fulfill()
            let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let track = Track(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            title: "Needs Start Date",
            duration: 180,
            trackNumber: 1,
            artist: "Artist"
        )
        let album = Album(title: "Album", artist: "Artist", year: "2024", coverData: nil, tracks: [track])
        let (vm, _, advance) = makeVM(track: track, album: album, setStartDate: false)

        vm.playback.position = 120
        advance(120)
        vm.scrobbleIfNeeded()

        await fulfillment(of: [expectation], timeout: 0.3)
    }

    @MainActor
    func testDoesNotScrobbleWhenAlreadyScrobbled() async throws {
        let first = expectation(description: "first scrobble")
        let noSecond = expectation(description: "no second scrobble")
        noSecond.isInverted = true
        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if callCount == 1 {
                first.fulfill()
            } else {
                noSecond.fulfill()
            }
            let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let track = Track(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            title: "Single Scrobble",
            duration: 200,
            trackNumber: 1,
            artist: "Artist"
        )
        let album = Album(title: "Album", artist: "Artist", year: "2024", coverData: nil, tracks: [track])
        let (vm, _, advance) = makeVM(track: track, album: album)

        vm.playback.position = 150
        advance(150)
        vm.scrobbleIfNeeded() // first scrobble

        vm.scrobbleIfNeeded() // should no-op if flag existed; currently will likely fail

        await fulfillment(of: [first], timeout: 0.5)
        await fulfillment(of: [noSecond], timeout: 0.3)
    }

    @MainActor
    func testSeekNearEndWithoutEnoughListenDoesNotScrobble() async throws {
        let expectation = expectation(description: "seek near end should not scrobble")
        expectation.isInverted = true
        MockURLProtocol.requestHandler = { request in
            expectation.fulfill()
            let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let track = Track(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            title: "Short With Seek",
            duration: 45,
            trackNumber: 1,
            artist: "Artist"
        )
        let album = Album(title: "Album", artist: "Artist", year: "2024", coverData: nil, tracks: [track])
        let (vm, current, advance) = makeVM(track: track, album: album)

        vm.playback.position = 10 // listen 10s
        advance(10)
        vm.scrobbleIfNeeded()

        vm._testSeekListening(to: 40, isPlaying: true, now: current()) // jump near end
        vm.playback.position = 40
        advance(3) // only a few seconds after seek; total real listen ~13s < 22.5s threshold
        vm.scrobbleIfNeeded()

        await fulfillment(of: [expectation], timeout: 0.3)
    }

    @MainActor
    func testLongTrackSeekToEndWithoutListeningDoesNotScrobble() async throws {
        let expectation = expectation(description: "long track skip should not scrobble")
        expectation.isInverted = true
        MockURLProtocol.requestHandler = { request in
            expectation.fulfill()
            let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let track = Track(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            title: "Long Skip",
            duration: 600,
            trackNumber: 1,
            artist: "Artist"
        )
        let album = Album(title: "Album", artist: "Artist", year: "2024", coverData: nil, tracks: [track])
        let (vm, current, advance) = makeVM(track: track, album: album)

        advance(5) // brief initial listen
        vm._testSeekListening(to: 500, isPlaying: true, now: current()) // jump well past threshold
        vm.playback.position = 500
        vm.scrobbleIfNeeded()

        await fulfillment(of: [expectation], timeout: 0.5)
    }

    @MainActor
    func testScrobbleFiresOnManualNext() async throws {
        let expectation = self.expectation(description: "scrobble on manual next")
        let noSecond = self.expectation(description: "no second scrobble on manual next")
        noSecond.isInverted = true
        var didFulfill = false
        var didFulfillNoSecond = false
        MockURLProtocol.requestHandler = { request in
            guard let body = ScrobbleIfNeededTests.bodyData(from: request),
                  let bodyString = String(data: body, encoding: .utf8),
                  ScrobbleIfNeededTests.decodeForm(bodyString)["method"] == "track.scrobble" else {
                let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            if didFulfill {
                if !didFulfillNoSecond {
                    didFulfillNoSecond = true
                    noSecond.fulfill()
                }
            } else {
                didFulfill = true
                expectation.fulfill()
            }
            let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let track = Track(url: URL(fileURLWithPath: "/tmp/test.mp3"), title: "Track 1", duration: 200, trackNumber: 1, artist: "Artist")
        let album = Album(title: "Album", artist: "Artist", year: "2024", coverData: nil, tracks: [track, track])
        let (vm, _, advance) = makeVM(track: track, album: album)
        vm.playback.position = 150
        advance(150)

        vm.playNext(autoAdvance: false)

        await fulfillment(of: [expectation], timeout: 0.5)
        await fulfillment(of: [noSecond], timeout: 0.2)
    }

    @MainActor
    func testScrobbleDoesNotFireOnManualNextWhenBelowThreshold() async throws {
        let expectation = expectation(description: "no scrobble on manual next below threshold")
        expectation.isInverted = true
        MockURLProtocol.requestHandler = { request in
            guard let body = ScrobbleIfNeededTests.bodyData(from: request),
                  let bodyString = String(data: body, encoding: .utf8),
                  ScrobbleIfNeededTests.decodeForm(bodyString)["method"] == "track.scrobble" else {
                let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            expectation.fulfill()
            let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let track = Track(url: URL(fileURLWithPath: "/tmp/test.mp3"), title: "Track 1", duration: 200, trackNumber: 1, artist: "Artist")
        let album = Album(title: "Album", artist: "Artist", year: "2024", coverData: nil, tracks: [track, track])
        let (vm, _, advance) = makeVM(track: track, album: album)
        vm.playback.position = 50
        advance(50)

        vm.playNext(autoAdvance: false)

        await fulfillment(of: [expectation], timeout: 0.3)
    }

    @MainActor
    func testScrobbleFiresOnManualPrevious() async throws {
        let expectation = self.expectation(description: "scrobble on manual previous")
        let noSecond = self.expectation(description: "no second scrobble on manual previous")
        noSecond.isInverted = true
        var didFulfill = false
        var didFulfillNoSecond = false
        MockURLProtocol.requestHandler = { request in
            guard let body = ScrobbleIfNeededTests.bodyData(from: request),
                  let bodyString = String(data: body, encoding: .utf8),
                  ScrobbleIfNeededTests.decodeForm(bodyString)["method"] == "track.scrobble" else {
                let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            if didFulfill {
                if !didFulfillNoSecond {
                    didFulfillNoSecond = true
                    noSecond.fulfill()
                }
            } else {
                didFulfill = true
                expectation.fulfill()
            }
            let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let track = Track(url: URL(fileURLWithPath: "/tmp/test.mp3"), title: "Track 1", duration: 200, trackNumber: 1, artist: "Artist")
        let album = Album(title: "Album", artist: "Artist", year: "2024", coverData: nil, tracks: [track, track])
        let (vm, _, advance) = makeVM(track: track, album: album)
        vm.playback.position = 150
        advance(150)

        vm.playPrevious()

        await fulfillment(of: [expectation], timeout: 0.5)
        await fulfillment(of: [noSecond], timeout: 0.2)
    }

    @MainActor
    func testScrobbleFiresOnHandleTrackFinished() async throws {
        let expectation = self.expectation(description: "scrobble on track finish")
        let noSecond = self.expectation(description: "no second scrobble on track finish")
        noSecond.isInverted = true
        var didFulfill = false
        var didFulfillNoSecond = false
        MockURLProtocol.requestHandler = { request in
            guard let body = ScrobbleIfNeededTests.bodyData(from: request),
                  let bodyString = String(data: body, encoding: .utf8),
                  ScrobbleIfNeededTests.decodeForm(bodyString)["method"] == "track.scrobble" else {
                let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            if didFulfill {
                if !didFulfillNoSecond {
                    didFulfillNoSecond = true
                    noSecond.fulfill()
                }
            } else {
                didFulfill = true
                expectation.fulfill()
            }
            let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let track = Track(url: URL(fileURLWithPath: "/tmp/test.mp3"), title: "Track 1", duration: 200, trackNumber: 1, artist: "Artist")
        let album = Album(title: "Album", artist: "Artist", year: "2024", coverData: nil, tracks: [track])
        let (vm, _, advance) = makeVM(track: track, album: album)
        vm.playback.position = 200
        advance(200)

        // Simulate end-of-track callback
        vm.scrobbleIfNeeded()

        await fulfillment(of: [expectation], timeout: 0.5)
        await fulfillment(of: [noSecond], timeout: 0.2)
    }

    @MainActor
    func testScrobbleFiresForTrackJustAboveDurationThreshold() async throws {
        let expectation = expectation(description: "scrobble fires for 31s track")
        MockURLProtocol.requestHandler = { request in
            expectation.fulfill()
            let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let track = Track(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            title: "Just Long Enough",
            duration: 31, // exactly 1s above the 30s minimum
            trackNumber: 1,
            artist: "Artist"
        )
        let album = Album(title: "Album", artist: "Artist", year: "2024", coverData: nil, tracks: [track])
        let (vm, _, advance) = makeVM(track: track, album: album)

        advance(16) // 16s > 50% of 31s threshold
        vm.playback.position = 16
        vm.scrobbleIfNeeded()

        await fulfillment(of: [expectation], timeout: 0.5)
    }

    @MainActor
    func testPauseDoesNotScrobbleEvenAboveThreshold() async throws {
        let expectation = self.expectation(description: "no scrobble on pause")
        expectation.isInverted = true
        MockURLProtocol.requestHandler = { request in
            guard let body = ScrobbleIfNeededTests.bodyData(from: request),
                  let bodyString = String(data: body, encoding: .utf8),
                  ScrobbleIfNeededTests.decodeForm(bodyString)["method"] == "track.scrobble" else {
                let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            expectation.fulfill()
            let url = request.url ?? URL(string: "https://\(self.scrobbleHost)")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let track = Track(url: URL(fileURLWithPath: "/tmp/test.mp3"), title: "Track 1", duration: 200, trackNumber: 1, artist: "Artist")
        let album = Album(title: "Album", artist: "Artist", year: "2024", coverData: nil, tracks: [track])
        let (vm, _, advance) = makeVM(track: track, album: album)

        vm.playback.position = 150
        advance(150)
        vm.playback.isPlaying = true
        vm.togglePlayback() // pause; should not trigger scrobble

        await fulfillment(of: [expectation], timeout: 0.3)
    }
}

// MARK: - Helpers

@MainActor
private extension ScrobbleIfNeededTests {
    func makeVM(
        track: Track,
        album: Album,
        sessionKey: String? = "SESSION",
        startTime: Date = Date(timeIntervalSince1970: 1_700_000_000),
        setStartDate: Bool = true
    ) -> (AppViewModel, () -> Date, (TimeInterval) -> Void) {
        var now = startTime
        let vm = AppViewModel()
        vm.currentAlbum = album
        vm.currentTrackIndex = 0
        vm.playback.position = 0
        vm._testSetLastFMSessionKey(sessionKey)
        if setStartDate {
            vm._testSetCurrentTrackStartDate(startTime)
        }
        vm._testSetNowProvider { now }
        vm._testStartListening(now: now)

        let current: () -> Date = { now }
        let advance: (TimeInterval) -> Void = { delta in
            now = now.addingTimeInterval(delta)
        }
        return (vm, current, advance)
    }

    static func decodeForm(_ body: String) -> [String: String] {
        var dict: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            dict[key] = value
        }
        return dict
    }

    static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody, !body.isEmpty {
            return body
        }
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }
            return data.isEmpty ? nil : data
        }
        return nil
    }
}
