import XCTest
@testable import FeatureMusic
@testable import FeatureIndicators
@testable import FeatureCalendar
@testable import FeatureShelf
@testable import FeatureClipboard

@MainActor
final class LyricsTests: XCTestCase {
    func testParsesLRCWithMultipleTags() {
        let lines = LyricsService.parseLRC("""
        [ar: Artist]
        [00:01.50] Первая
        [00:10.00][01:00.25] Припев
        [00:05.00]
        """)
        XCTAssertEqual(lines.map(\.time), [1.5, 5, 10, 60.25])
        XCTAssertEqual(lines.map(\.text), ["Первая", "", "Припев", "Припев"])
    }

    func testCurrentIndex() {
        let lines = [LyricLine(time: 1, text: "a"), LyricLine(time: 5, text: "b"), LyricLine(time: 9, text: "c")]
        XCTAssertNil(LyricsService.currentIndex(lines, at: 0.5))
        XCTAssertEqual(LyricsService.currentIndex(lines, at: 1), 0)
        XCTAssertEqual(LyricsService.currentIndex(lines, at: 6), 1)
        XCTAssertEqual(LyricsService.currentIndex(lines, at: 100), 2)
    }

    func testStateFromResponse() {
        XCTAssertEqual(LyricsService.state(from: ["instrumental": true]), .instrumental)
        XCTAssertEqual(LyricsService.state(from: ["plainLyrics": "a\n\nb"]), .plain(["a", "b"]))
        XCTAssertEqual(LyricsService.state(from: ["syncedLyrics": "[00:02.00] x"]), .synced([LyricLine(time: 2, text: "x")]))
        XCTAssertNil(LyricsService.state(from: [:]))
    }
}

final class HeadphonesTests: XCTestCase {
    func testParsesSystemProfilerJSON() throws {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[
          {"AirPods Pro":{"device_batteryLevelCase":"8\\u00a0%","device_batteryLevelLeft":"100\\u00a0%","device_batteryLevelRight":"75\\u00a0%"}},
          {"Mouse":{"device_minorType":"Mouse"}},
          {"Beats Solo":{"device_batteryLevelMain":"40 %"}}
        ]}]}
        """
        let list = HeadphonesBattery.parse(Data(json.utf8))
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0], HeadphonesBattery(name: "AirPods Pro", left: 100, right: 75, caseLevel: 8, main: nil))
        XCTAssertEqual(list[0].symbol, "airpodspro")
        XCTAssertEqual(list[1].main, 40)
        XCTAssertEqual(list[1].symbol, "beats.headphones")
    }
}

final class MeetingLinkTests: XCTestCase {
    func testFindsLinkInNotes() {
        let url = MeetingLink.find(url: nil, location: "Переговорка 3",
                                   notes: "Подключайтесь: https://us02web.zoom.us/j/123456?pwd=abc спасибо")
        XCTAssertEqual(url?.host, "us02web.zoom.us")
    }

    func testIgnoresOrdinaryLinks() {
        XCTAssertNil(MeetingLink.find(url: URL(string: "https://example.com"), location: nil, notes: "https://google.com"))
        XCTAssertNotNil(MeetingLink.find(url: URL(string: "https://meet.google.com/abc-defg-hij"), location: nil, notes: nil))
        XCTAssertNotNil(MeetingLink.find(url: nil, location: "https://telemost.yandex.ru/j/123", notes: nil))
    }
}

final class ShelfActionsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testRenameKeepsExtension() throws {
        let file = dir.appendingPathComponent("a.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let renamed = try ShelfActions.rename(file, to: "отчёт")
        XCTAssertEqual(renamed.lastPathComponent, "отчёт.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testRenameRejectsTakenAndBadNames() throws {
        let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.txt")
        try "1".write(to: a, atomically: true, encoding: .utf8)
        try "2".write(to: b, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ShelfActions.rename(a, to: "b"))
        XCTAssertThrowsError(try ShelfActions.rename(a, to: "x/y"))
    }

    func testZipSeveralFiles() throws {
        let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.txt")
        try "1".write(to: a, atomically: true, encoding: .utf8)
        try "2".write(to: b, atomically: true, encoding: .utf8)
        let zip = try ShelfActions.zip([a, b])
        XCTAssertEqual(zip.lastPathComponent, "Архив.zip")
        let size = try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 100)
    }

    func testUniqueURL() throws {
        try "1".write(to: dir.appendingPathComponent("f.jpg"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ShelfActions.uniqueURL(in: dir, base: "f", ext: "jpg").lastPathComponent, "f 2.jpg")
    }
}

final class ClipItemTests: XCTestCase {
    func testDecodesOldHistoryWithoutPins() throws {
        let old = #"[{"id":"7C9F4C9E-6B1B-4C68-9D7B-2F0E6C1A1E11","text":"hello","date":700000000,"appName":"Safari"}]"#
        let items = try JSONDecoder().decode([ClipItem].self, from: Data(old.utf8))
        XCTAssertEqual(items.first?.text, "hello")
        XCTAssertEqual(items.first?.pinned, false)
    }

    func testImagesAreNotEncoded() throws {
        let item = ClipItem(text: "", image: Data([1, 2, 3]))
        let json = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        XCTAssertFalse(json.contains("image"))
    }
}
