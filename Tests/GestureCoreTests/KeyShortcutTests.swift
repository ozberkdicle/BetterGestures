import Testing
@testable import GestureCore

struct KeyShortcutTests {
    @Test func parsesModifiersAndKey() throws {
        let s = try KeyShortcut(parsing: "cmd+shift+]")
        #expect(s.modifiers == [.command, .shift])
        #expect(s.keyCode == 30)
    }

    @Test func isCaseAndSpaceInsensitive() throws {
        let s = try KeyShortcut(parsing: " Cmd + W ")
        #expect(s.modifiers == [.command])
        #expect(s.keyCode == 13)
    }

    @Test func acceptsRawKeyCode() throws {
        let s = try KeyShortcut(parsing: "ctrl+keycode:48")
        #expect(s.modifiers == [.control])
        #expect(s.keyCode == 48)
    }

    @Test func rejectsInvalidInput() {
        #expect(throws: KeyShortcut.ParseError.empty) { try KeyShortcut(parsing: "  ") }
        #expect(throws: KeyShortcut.ParseError.missingKey("cmd+shift")) { try KeyShortcut(parsing: "cmd+shift") }
        #expect(throws: KeyShortcut.ParseError.unknownToken("hyper")) { try KeyShortcut(parsing: "hyper+w") }
        #expect(throws: KeyShortcut.ParseError.multipleKeys("cmd+a+b")) { try KeyShortcut(parsing: "cmd+a+b") }
    }

    @Test func recordedShortcutRoundTripsThroughText() throws {
        for code in UInt16(0)...126 {
            let recorded = KeyShortcut(modifiers: [.control, .shift], keyCode: code)
            let parsed = try KeyShortcut(parsing: recorded.text)
            #expect(parsed.sameKeys(as: recorded), "\(recorded.text)")
        }
    }

    @Test func canonicalTextUsesPreferredNamesAndOrder() {
        #expect(KeyShortcut(modifiers: [.command, .shift, .control], keyCode: 48).text == "ctrl+shift+cmd+tab")
        #expect(KeyShortcut(modifiers: [.command], keyCode: 51).text == "cmd+delete")
        #expect(KeyShortcut(modifiers: [], keyCode: 10).text == "keycode:10")
    }

    @Test func defaultConfigResolvesWithoutWarnings() {
        let resolved = GestureConfig.default.resolve()
        #expect(resolved.warnings.isEmpty)
        #expect(Set(resolved.bindings.keys) == [.fourFingerTap, .tipTapRight, .tipTapLeft])
    }

    @Test func configReportsBadEntriesAndKeepsGoodOnes() {
        let config = GestureConfig(gestures: ["fourFingerTap": "cmd+w", "bogus": "cmd+a", "tipTapLeft": "cmd+"])
        let resolved = config.resolve()
        #expect(resolved.bindings == [.fourFingerTap: try! KeyShortcut(parsing: "cmd+w")])
        #expect(resolved.warnings.count == 2)
    }
}
