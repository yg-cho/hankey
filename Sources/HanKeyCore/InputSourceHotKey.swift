import Foundation

/// 단축키를 바꾸기 전의 값. 종료하거나 끌 때 되돌리는 데 쓴다.
public enum HotKeyBackup {
    /// 원래 항목이 없었다(시스템 기본값).
    case absent
    case entry([String: Any])

    public var plist: [String: Any] {
        switch self {
        case .absent: return ["kind": "absent"]
        case .entry(let entry): return ["kind": "entry", "entry": entry]
        }
    }

    public init?(plist: [String: Any]?) {
        guard let plist, let kind = plist["kind"] as? String else { return nil }
        switch kind {
        case "absent":
            self = .absent
        case "entry":
            guard let entry = plist["entry"] as? [String: Any] else { return nil }
            self = .entry(entry)
        default:
            return nil
        }
    }
}

/// 시스템 단축키 "이전 입력 소스 선택"(`com.apple.symbolichotkeys` 60번) 값 계산.
public enum InputSourceHotKey {
    public static let id: Int32 = 60
    public static let key = "60"
    public static let f18KeyCode = 79
    /// 기능 키 표시 플래그(NSEvent.ModifierFlags.function).
    public static let functionFlag = 0x80_0000
    /// Shift · Control · Option · Command.
    static let userModifierMask = 0x1E_0000

    public static var f18Entry: [String: Any] {
        [
            "enabled": true,
            "value": [
                "parameters": [65535, f18KeyCode, functionFlag],
                "type": "standard",
            ] as [String: Any],
        ]
    }

    /// 보조 키 없이 F18 하나로 켜져 있는가.
    public static func isF18(keyCode: Int, modifiers: Int, enabled: Bool) -> Bool {
        enabled && keyCode == f18KeyCode && modifiers & userModifierMask == 0
    }

    /// 환경설정에 저장된 항목이 F18 인가.
    public static func isF18(_ entry: Any?) -> Bool {
        guard let dict = entry as? [String: Any],
              let enabled = (dict["enabled"] as? NSNumber)?.boolValue,
              let value = dict["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber],
              parameters.count >= 3
        else { return false }
        return isF18(keyCode: parameters[1].intValue, modifiers: parameters[2].intValue, enabled: enabled)
    }

    /// F18 로 연결한다. 이미 F18 이면 nil(바꿀 것 없음).
    public static func link(_ hotkeys: [String: Any]) -> (hotkeys: [String: Any], backup: HotKeyBackup)? {
        let current = hotkeys[key]
        if isF18(current) { return nil }
        var updated = hotkeys
        updated[key] = f18Entry
        let backup: HotKeyBackup = (current as? [String: Any]).map { .entry($0) } ?? .absent
        return (updated, backup)
    }

    /// 백업 값으로 되돌린다. 지금 값이 F18 이 아니면(사용자가 직접 바꿨으면) nil.
    public static func unlink(_ hotkeys: [String: Any], backup: HotKeyBackup) -> [String: Any]? {
        guard isF18(hotkeys[key]) else { return nil }
        var updated = hotkeys
        switch backup {
        case .absent: updated.removeValue(forKey: key)
        case .entry(let entry): updated[key] = entry
        }
        return updated
    }
}
