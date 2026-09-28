import XCTest
@testable import RemoteVoiceRestoreCore

final class InputSourceControllerTests: XCTestCase {
    func testKeyboardModeSkipsNonKeyboardInputMethod() {
        let selected: [[String: Any]] = [
            ["Bundle ID": "com.apple.inputmethod.ironwood",
             "InputSourceKind": "Non Keyboard Input Method"],
            ["Bundle ID": "com.bytedance.inputmethod.doubaoime",
             "Input Mode": "com.bytedance.inputmethod.doubaoime.pinyin",
             "InputSourceKind": "Input Mode"]
        ]

        XCTAssertEqual(TISInputSourceController.keyboardMode(in: selected),
                       "com.bytedance.inputmethod.doubaoime.pinyin")
    }
}
