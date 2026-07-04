import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct UpdateCheckPolicyTests {
    @Test func testVersionComparisonMatrix() {
        XCTAssertTrue(UpdateCheckPolicy.isNewer(remote: "0.2.0", current: "0.1.0"), "Minor bump is newer")
        XCTAssertTrue(UpdateCheckPolicy.isNewer(remote: "1.0.0", current: "0.9.9"), "Major bump is newer")
        XCTAssertTrue(UpdateCheckPolicy.isNewer(remote: "0.1.1", current: "0.1.0"), "Patch bump is newer")
        XCTAssertTrue(UpdateCheckPolicy.isNewer(remote: "0.1.0.1", current: "0.1.0"), "Extra segment counts")
        XCTAssertTrue(UpdateCheckPolicy.isNewer(remote: "v0.2.0", current: "0.1.0"), "v prefix normalizes")

        XCTAssertFalse(UpdateCheckPolicy.isNewer(remote: "0.1.0", current: "0.1.0"), "Same version is not newer")
        XCTAssertFalse(UpdateCheckPolicy.isNewer(remote: "0.1.0", current: "0.2.0"), "Older is not newer")
        XCTAssertFalse(UpdateCheckPolicy.isNewer(remote: "0.1", current: "0.1.0"), "Missing segment pads to zero")
        XCTAssertFalse(UpdateCheckPolicy.isNewer(remote: "0.2.0-beta", current: "0.1.0"), "Non-numeric segments stay conservative")
        XCTAssertFalse(UpdateCheckPolicy.isNewer(remote: "", current: "0.1.0"), "Empty remote is not newer")
    }

    @Test func testNormalizedVersionStripsPrefix() {
        XCTAssertEqual(UpdateCheckPolicy.normalizedVersion("v0.1.0"), "0.1.0", "Lowercase v strips")
        XCTAssertEqual(UpdateCheckPolicy.normalizedVersion("V2.0"), "2.0", "Uppercase V strips")
        XCTAssertEqual(UpdateCheckPolicy.normalizedVersion(" 0.1.0 "), "0.1.0", "Whitespace trims")
    }

    @Test func testParseReleaseFromGitHubJSON() throws {
        let json = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/shinteni/prompt-island/releases/tag/v0.2.0",
          "name": "Vibelsland Free 0.2.0"
        }
        """.data(using: .utf8)!
        let release = UpdateCheckPolicy.parseRelease(from: json)
        XCTAssertEqual(release?.version, "0.2.0", "Tag parses without the v prefix")
        XCTAssertEqual(
            release?.pageURL.absoluteString,
            "https://github.com/shinteni/prompt-island/releases/tag/v0.2.0",
            "Release page URL parses"
        )
    }

    @Test func testParseReleaseFallbacksAndFailures() {
        let missingURL = """
        {"tag_name": "0.3.0"}
        """.data(using: .utf8)!
        XCTAssertEqual(
            UpdateCheckPolicy.parseRelease(from: missingURL)?.pageURL,
            UpdateCheckPolicy.releasesPageURL,
            "Missing html_url falls back to the releases page"
        )

        XCTAssertTrue(
            UpdateCheckPolicy.parseRelease(from: Data("not json".utf8)) == nil,
            "Malformed payloads parse to nil"
        )
        XCTAssertTrue(
            UpdateCheckPolicy.parseRelease(from: Data("{}".utf8)) == nil,
            "Payloads without tag_name parse to nil"
        )
        XCTAssertTrue(
            UpdateCheckPolicy.parseRelease(from: Data(#"{"tag_name": "v"}"#.utf8)) == nil,
            "Empty version after normalization parses to nil"
        )
    }

    @Test func testAutoCheckDefaultsToDisabledAndDecodesLegacyConfig() throws {
        XCTAssertFalse(AppConfiguration.default.autoCheckUpdates, "Auto update check is opt-in")

        let legacyConfig = """
        {
          "enableClaude": true,
          "enableCodexCLI": true,
          "enableCodexDesktop": true,
          "enableSounds": true,
          "soundTheme": "soft",
          "doNotDisturb": false,
          "launchAtLogin": false,
          "islandPosition": "topCenter",
          "approvalTimeoutSeconds": 7200,
          "maxVisibleSessions": 5
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: legacyConfig)
        XCTAssertFalse(decoded.autoCheckUpdates, "Legacy configs without the key stay disabled")
    }
}
