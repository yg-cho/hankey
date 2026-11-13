import Foundation

/// 한영 전환에 쓸 수 있는 키.
public enum TriggerKey: String, CaseIterable, Sendable {
    case capsLock
    case rightCommand
    case rightOption
    case rightShift
    case rightControl

    /// HID 키보드 페이지(0x07) 사용 코드.
    public var usage: UInt64 {
        let code: UInt64
        switch self {
        case .capsLock: code = 0x39
        case .rightControl: code = 0xE4
        case .rightShift: code = 0xE5
        case .rightOption: code = 0xE6
        case .rightCommand: code = 0xE7
        }
        return KeyMapping.keyboardPage | code
    }

    public var title: String {
        switch self {
        case .capsLock: return "Caps Lock"
        case .rightCommand: return "오른쪽 Command"
        case .rightOption: return "오른쪽 Option"
        case .rightShift: return "오른쪽 Shift"
        case .rightControl: return "오른쪽 Control"
        }
    }
}

public struct KeyMapEntry: Equatable, Sendable {
    public var src: UInt64
    public var dst: UInt64

    public init(src: UInt64, dst: UInt64) {
        self.src = src
        self.dst = dst
    }
}

public enum KeyMapping {
    public static let keyboardPage: UInt64 = 0x7_0000_0000
    /// 시스템 단축키가 연결되는 키. 기본 방식에서는 선택한 키를 이 키로 바꾼다.
    public static let f18Usage: UInt64 = keyboardPage | 0x6D
    /// 즉시 전환 방식에서 선택한 키가 바뀌는 대상. 앱이 누름을 받아 F18 을 대신 눌러 준다.
    public static let f19Usage: UInt64 = keyboardPage | 0x6E
    static let ownDestinations: Set<UInt64> = [f18Usage, f19Usage]

    static let srcKey = "HIDKeyboardModifierMappingSrc"
    static let dstKey = "HIDKeyboardModifierMappingDst"

    /// 기존 매핑에서 우리 항목(F18 · F19 로 가는 것)을 걷어내고, `trigger` 가 있으면 새 항목을 붙인다.
    /// 같은 키에서 출발하는 다른 항목은 충돌하므로 교체한다.
    public static func merged(
        existing: [KeyMapEntry], trigger: TriggerKey?, destination: UInt64 = f18Usage
    ) -> [KeyMapEntry] {
        var result = existing.filter { !ownDestinations.contains($0.dst) }
        guard let trigger else { return result }
        result.removeAll { $0.src == trigger.usage }
        result.append(KeyMapEntry(src: trigger.usage, dst: destination))
        return result
    }

    /// `hidutil property --set` 에 넘길 JSON.
    public static func hidutilJSON(_ entries: [KeyMapEntry]) -> String {
        let items = entries.map { "{\"\(srcKey)\":\($0.src),\"\(dstKey)\":\($0.dst)}" }
        return "{\"UserKeyMapping\":[\(items.joined(separator: ","))]}"
    }

    /// HID 이벤트 시스템에서 읽은 `UserKeyMapping` 값을 항목으로 바꾼다. 형식이 다르면 빈 배열.
    public static func entries(fromProperty value: Any?) -> [KeyMapEntry] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let src = (dict[srcKey] as? NSNumber)?.uint64Value,
                  let dst = (dict[dstKey] as? NSNumber)?.uint64Value
            else { return nil }
            return KeyMapEntry(src: src, dst: dst)
        }
    }
}
