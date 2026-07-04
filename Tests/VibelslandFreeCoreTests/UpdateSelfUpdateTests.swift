import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct UpdateSelfUpdateTests {
    @Test func testParseReleaseExtractsSelfUpdateAssets() {
        let json = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/shinteni/prompt-island/releases/tag/v0.2.0",
          "assets": [
            {"name": "Source.tar.gz", "browser_download_url": "https://example.com/src.tar.gz"},
            {"name": "Vibelsland-Free-0.2.0-macos.zip", "browser_download_url": "https://example.com/app.zip"},
            {"name": "Vibelsland-Free-0.2.0-macos.zip.sha256", "browser_download_url": "https://example.com/app.zip.sha256"}
          ]
        }
        """.data(using: .utf8)!
        let release = UpdateCheckPolicy.parseRelease(from: json)
        XCTAssertEqual(release?.archiveName, "Vibelsland-Free-0.2.0-macos.zip", "Archive asset is found by suffix")
        XCTAssertEqual(release?.archiveURL?.absoluteString, "https://example.com/app.zip", "Archive URL parses")
        XCTAssertEqual(release?.checksumURL?.absoluteString, "https://example.com/app.zip.sha256", "Checksum pairs with the archive")
        XCTAssertTrue(release?.supportsSelfUpdate == true, "Complete assets enable self-update")
    }

    @Test func testParseReleaseWithoutAssetsDisablesSelfUpdate() {
        let noAssets = """
        {"tag_name": "v0.2.0", "html_url": "https://example.com/r"}
        """.data(using: .utf8)!
        let release = UpdateCheckPolicy.parseRelease(from: noAssets)
        XCTAssertTrue(release?.supportsSelfUpdate == false, "Missing assets disable self-update")

        let zipOnly = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://example.com/r",
          "assets": [
            {"name": "Vibelsland-Free-0.2.0-macos.zip", "browser_download_url": "https://example.com/app.zip"}
          ]
        }
        """.data(using: .utf8)!
        let zipRelease = UpdateCheckPolicy.parseRelease(from: zipOnly)
        XCTAssertTrue(zipRelease?.supportsSelfUpdate == false, "A zip without its checksum cannot self-update")
        XCTAssertEqual(zipRelease?.archiveName, "Vibelsland-Free-0.2.0-macos.zip", "Archive still parses for display")
    }

    @Test func testChecksumContentParsing() {
        let hash = String(repeating: "ab", count: 32)
        XCTAssertEqual(
            UpdateCheckPolicy.parseChecksumContent("\(hash)  app.zip\n", expectedArchiveName: "app.zip"),
            hash,
            "shasum format parses"
        )
        XCTAssertEqual(
            UpdateCheckPolicy.parseChecksumContent("\(hash) *app.zip", expectedArchiveName: "app.zip"),
            hash,
            "Binary-mode asterisk prefix is tolerated"
        )
        XCTAssertTrue(
            UpdateCheckPolicy.parseChecksumContent("\(hash)  other.zip", expectedArchiveName: "app.zip") == nil,
            "Filename mismatch rejects the checksum"
        )
        XCTAssertTrue(
            UpdateCheckPolicy.parseChecksumContent("nothex  app.zip", expectedArchiveName: "app.zip") == nil,
            "Non-hex hash rejects"
        )
        XCTAssertTrue(
            UpdateCheckPolicy.parseChecksumContent(String(repeating: "a", count: 63) + "  app.zip", expectedArchiveName: "app.zip") == nil,
            "Wrong-length hash rejects"
        )
        XCTAssertTrue(
            UpdateCheckPolicy.parseChecksumContent("", expectedArchiveName: "app.zip") == nil,
            "Empty content rejects"
        )
    }
}
