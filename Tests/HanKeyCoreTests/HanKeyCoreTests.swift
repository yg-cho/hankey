import XCTest
@testable import HanKeyCore

final class KeyMappingTests: XCTestCase {
    private let f18 = KeyMapping.f18Usage

    func testUsageCodes() {
        XCTAssertEqual(TriggerKey.capsLock.usage, 0x7_0000_0039)
        XCTAssertEqual(TriggerKey.rightCommand.usage, 0x7_0000_00E7)
        XCTAssertEqual(TriggerKey.rightOption.usage, 0x7_0000_00E6)
        XCTAssertEqual(TriggerKey.rightShift.usage, 0x7_0000_00E5)
        XCTAssertEqual(TriggerKey.rightControl.usage, 0x7_0000_00E4)
        XCTAssertEqual(f18, 0x7_0000_006D)
    }

    func testAddsEntryToEmptyMapping() {
        XCTAssertEqual(
            KeyMapping.merged(existing: [], trigger: .capsLock),
            [KeyMapEntry(src: 0x7_0000_0039, dst: f18)]
        )
    }

    func testSwitchingKeyReplacesOwnEntry() {
        let before = KeyMapping.merged(existing: [], trigger: .capsLock)
        XCTAssertEqual(
            KeyMapping.merged(existing: before, trigger: .rightCommand),
            [KeyMapEntry(src: TriggerKey.rightCommand.usage, dst: f18)]
        )
    }

    func testKeepsUnrelatedEntries() {
        let other = KeyMapEntry(src: 0x7_0000_0064, dst: 0x7_0000_0035)
        XCTAssertEqual(
            KeyMapping.merged(existing: [other], trigger: .rightOption),
            [other, KeyMapEntry(src: TriggerKey.rightOption.usage, dst: f18)]
        )
    }

    func testReplacesEntryWithSameSource() {
        let conflict = KeyMapEntry(src: TriggerKey.capsLock.usage, dst: 0x7_0000_0029)
        XCTAssertEqual(
            KeyMapping.merged(existing: [conflict], trigger: .capsLock),
            [KeyMapEntry(src: TriggerKey.capsLock.usage, dst: f18)]
        )
    }

    func testDisablingRemovesOnlyOwnEntry() {
        let other = KeyMapEntry(src: 0x7_0000_0064, dst: 0x7_0000_0035)
        let own = KeyMapEntry(src: TriggerKey.rightShift.usage, dst: f18)
        XCTAssertEqual(KeyMapping.merged(existing: [other, own], trigger: nil), [other])
    }

    func testInstantModeUsesF19AndReplacesF18Entry() {
        let f19 = KeyMapping.f19Usage
        XCTAssertEqual(f19, 0x7_0000_006E)
        let basic = KeyMapping.merged(existing: [], trigger: .rightControl)
        let instant = KeyMapping.merged(existing: basic, trigger: .rightControl, destination: f19)
        XCTAssertEqual(instant, [KeyMapEntry(src: TriggerKey.rightControl.usage, dst: f19)])
        XCTAssertEqual(KeyMapping.merged(existing: instant, trigger: .rightControl), basic)
        XCTAssertEqual(KeyMapping.merged(existing: instant, trigger: nil), [])
    }

    func testHidutilJSONRoundTrip() throws {
        let entries = KeyMapping.merged(existing: [], trigger: .capsLock)
        let json = KeyMapping.hidutilJSON(entries)
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertEqual(KeyMapping.entries(fromProperty: object?["UserKeyMapping"]), entries)
        XCTAssertEqual(KeyMapping.hidutilJSON([]), "{\"UserKeyMapping\":[]}")
    }

    func testEntriesFromUnexpectedProperty() {
        XCTAssertEqual(KeyMapping.entries(fromProperty: nil), [])
        XCTAssertEqual(KeyMapping.entries(fromProperty: "x"), [])
        XCTAssertEqual(KeyMapping.entries(fromProperty: [["HIDKeyboardModifierMappingSrc": 1]]), [])
    }
}

final class InputSourceHotKeyTests: XCTestCase {
    private let ctrlSpace: [String: Any] = [
        "enabled": true,
        "value": ["parameters": [32, 49, 262144], "type": "standard"] as [String: Any],
    ]

    private func entry(keyCode: Int, modifiers: Int, enabled: Bool) -> [String: Any] {
        [
            "enabled": enabled,
            "value": ["parameters": [65535, keyCode, modifiers], "type": "standard"] as [String: Any],
        ]
    }

    func testRecognisesF18() {
        XCTAssertTrue(InputSourceHotKey.isF18(InputSourceHotKey.f18Entry))
        XCTAssertTrue(InputSourceHotKey.isF18(entry(keyCode: 79, modifiers: 0, enabled: true)))
        XCTAssertFalse(InputSourceHotKey.isF18(ctrlSpace))
        XCTAssertFalse(InputSourceHotKey.isF18(entry(keyCode: 79, modifiers: 0x80_0000, enabled: false)))
        XCTAssertFalse(InputSourceHotKey.isF18(entry(keyCode: 79, modifiers: 0x80_0000 | 0x10_0000, enabled: true)))
        XCTAssertFalse(InputSourceHotKey.isF18(nil))
        XCTAssertFalse(InputSourceHotKey.isF18(["enabled": true]))
    }

    func testLinkBacksUpCurrentEntry() throws {
        let hotkeys: [String: Any] = ["60": ctrlSpace, "61": ctrlSpace]
        let result = try XCTUnwrap(InputSourceHotKey.link(hotkeys))
        XCTAssertTrue(InputSourceHotKey.isF18(result.hotkeys["60"]))
        XCTAssertFalse(InputSourceHotKey.isF18(result.hotkeys["61"]))
        guard case .entry(let saved) = result.backup else { return XCTFail("백업이 항목이어야 한다") }
        XCTAssertEqual(saved as NSDictionary, ctrlSpace as NSDictionary)
    }

    func testLinkWithoutEntryBacksUpAbsent() throws {
        let result = try XCTUnwrap(InputSourceHotKey.link([:]))
        guard case .absent = result.backup else { return XCTFail("백업이 absent 여야 한다") }
    }

    func testLinkIsNoOpWhenAlreadyF18() {
        XCTAssertNil(InputSourceHotKey.link(["60": InputSourceHotKey.f18Entry]))
    }

    func testUnlinkRestoresBackup() throws {
        let linked = try XCTUnwrap(InputSourceHotKey.link(["60": ctrlSpace]))
        let restored = try XCTUnwrap(InputSourceHotKey.unlink(linked.hotkeys, backup: linked.backup))
        XCTAssertEqual(restored as NSDictionary, ["60": ctrlSpace] as NSDictionary)
    }

    func testUnlinkRemovesEntryWhenBackupAbsent() throws {
        let restored = try XCTUnwrap(
            InputSourceHotKey.unlink(["60": InputSourceHotKey.f18Entry], backup: .absent)
        )
        XCTAssertNil(restored["60"])
    }

    func testUnlinkLeavesUserChangedShortcut() {
        XCTAssertNil(InputSourceHotKey.unlink(["60": ctrlSpace], backup: .absent))
    }

    func testBackupPlistRoundTrip() throws {
        let plist = HotKeyBackup.entry(ctrlSpace).plist
        guard case .entry(let saved) = try XCTUnwrap(HotKeyBackup(plist: plist)) else {
            return XCTFail("항목으로 복원되어야 한다")
        }
        XCTAssertEqual(saved as NSDictionary, ctrlSpace as NSDictionary)
        guard case .absent = try XCTUnwrap(HotKeyBackup(plist: HotKeyBackup.absent.plist)) else {
            return XCTFail("absent 로 복원되어야 한다")
        }
        XCTAssertNil(HotKeyBackup(plist: nil))
        XCTAssertNil(HotKeyBackup(plist: ["kind": "other"]))
    }
}
