import XCTest

final class PortableAIUITests: XCTestCase {
    @MainActor
    func testOpenQRScannerForDiagnostics() throws {
        let app = XCUIApplication()
        app.launch()

        // If already paired, go back to pairing so Scan is available.
        let forget = app.buttons["Forget server"]
        if forget.waitForExistence(timeout: 3) {
            forget.tap()
        }

        let scan = app.buttons["Scan QR code"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5), "Scan QR code button missing — may not be on PairingView")
        scan.tap()

        // Keep scanner up long enough for camera logs to flush.
        sleep(8)

        let cancel = app.buttons["Cancel"]
        if cancel.exists {
            cancel.tap()
        }
    }
}
