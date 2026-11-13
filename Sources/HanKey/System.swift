import AppKit
import Carbon.HIToolbox
import HanKeyCore
import IOKit
import IOKit.hidsystem
import ServiceManagement

enum Shell {
    /// 실행 후 종료 코드를 돌려준다. 실행 자체가 안 되면 -1.
    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// HID 단계 키 바꾸기. `hidutil` 과 같은 `UserKeyMapping` 속성을 쓴다.
enum HIDRemapper {
    static func current() -> [KeyMapEntry] {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let value = IOHIDEventSystemClientCopyProperty(client, "UserKeyMapping" as CFString)
        return KeyMapping.entries(fromProperty: value)
    }

    @discardableResult
    static func apply(trigger: TriggerKey?, destination: UInt64 = KeyMapping.f18Usage) -> Bool {
        let entries = KeyMapping.merged(existing: current(), trigger: trigger, destination: destination)
        return Shell.run("/usr/bin/hidutil", ["property", "--set", KeyMapping.hidutilJSON(entries)]) == 0
    }
}

/// 시스템 단축키 환경설정(`com.apple.symbolichotkeys`) 읽기 · 쓰기와 실제 적용 값 확인.
struct HotKeyStore {
    var domain = "com.apple.symbolichotkeys"
    private let rootKey = "AppleSymbolicHotKeys" as CFString

    func read() -> [String: Any] {
        CFPreferencesAppSynchronize(domain as CFString)
        return CFPreferencesCopyAppValue(rootKey, domain as CFString) as? [String: Any] ?? [:]
    }

    @discardableResult
    func write(_ hotkeys: [String: Any]) -> Bool {
        CFPreferencesSetAppValue(rootKey, hotkeys as CFDictionary, domain as CFString)
        return CFPreferencesAppSynchronize(domain as CFString)
    }

    /// 바뀐 환경설정을 WindowServer 에 반영한다.
    static func activate() {
        Shell.run(
            "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings",
            ["-u"]
        )
    }

    private typealias GetValue = @convention(c) (
        Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt32>
    ) -> Int32
    private typealias IsEnabled = @convention(c) (Int32) -> Bool

    /// WindowServer 가 지금 쓰는 값이 F18 인가. 확인할 수 없으면 nil.
    static func liveIsF18() -> Bool? {
        guard let handle = dlopen(nil, RTLD_NOW),
              let getPointer = dlsym(handle, "CGSGetSymbolicHotKeyValue"),
              let enabledPointer = dlsym(handle, "CGSIsSymbolicHotKeyEnabled")
        else { return nil }
        let getValue = unsafeBitCast(getPointer, to: GetValue.self)
        let isEnabled = unsafeBitCast(enabledPointer, to: IsEnabled.self)
        var character: UInt16 = 0
        var keyCode: UInt16 = 0
        var modifiers: UInt32 = 0
        guard getValue(InputSourceHotKey.id, &character, &keyCode, &modifiers) == 0 else { return nil }
        return InputSourceHotKey.isF18(
            keyCode: Int(keyCode),
            modifiers: Int(modifiers),
            enabled: isEnabled(InputSourceHotKey.id)
        )
    }

    /// 반영이 조금 늦을 수 있어 잠깐 기다리며 확인한다.
    static func waitForLive(_ expected: Bool, timeout: TimeInterval = 2) -> Bool? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            guard let live = liveIsF18() else { return nil }
            if live == expected || Date() >= deadline { return live }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// 즉시 전환: F19 누름을 받는 전역 단축키. 누르는 순간 한 번만 불리고 키 반복에는 불리지 않는다.
final class PressHotKey {
    var onPress: (() -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    var isRegistered: Bool { !refs.isEmpty }

    /// 메인 스레드에서 부른다. 하나도 등록하지 못하면 false.
    func register() -> Bool {
        if isRegistered { return true }
        if handler == nil {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
            )
            InstallEventHandler(GetEventDispatcherTarget(), { _, _, userData in
                guard let userData else { return noErr }
                Unmanaged<PressHotKey>.fromOpaque(userData).takeUnretainedValue().onPress?()
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        // 앞 글자의 Shift 등이 아직 눌려 있어도 받도록 보조 키 조합을 모두 등록한다.
        let modifiers = [shiftKey, controlKey, optionKey, cmdKey]
        for mask in 0..<(1 << modifiers.count) {
            let flags = modifiers.enumerated().reduce(0) { $0 | (mask & (1 << $1.offset) != 0 ? $1.element : 0) }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x484B_4559), id: UInt32(mask + 1))
            if RegisterEventHotKey(UInt32(kVK_F19), UInt32(flags), id, GetEventDispatcherTarget(), 0, &ref) == noErr,
               let ref {
                refs.append(ref)
            }
        }
        return isRegistered
    }

    func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }
}

/// 입력 소스를 직접 바꾼다. 비밀번호 창 등 보안 입력 중에는 가상 키가 막히므로 그때만 쓴다.
enum InputSource {
    static var isSecureInput: Bool { IsSecureEventInputEnabled() }

    /// 선택할 수 있는 키보드 입력 소스 중 다음 것으로 넘긴다(둘이면 한영 전환).
    static func selectNext() {
        let filter = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable: true,
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              list.count > 1
        else { return }
        let current = id(of: TISCopyCurrentKeyboardInputSource().takeRetainedValue())
        let index = list.firstIndex { id(of: $0) == current } ?? -1
        TISSelectInputSource(list[(index + 1) % list.count])
    }

    private static func id(of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}

/// 시스템 단축키(F18)를 대신 눌러 준다. 손쉬운 사용 권한이 필요하다.
enum SyntheticKey {
    static var canPost: Bool { CGPreflightPostEventAccess() }

    static func requestAccess() {
        CGRequestPostEventAccess()
    }

    /// 누름과 뗌을 바로 이어 보낸다. 시스템은 뗄 때 전환하므로 실제 키를 오래 눌러도 즉시 바뀐다.
    static func tapF18() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: source, virtualKey: CGKeyCode(InputSourceHotKey.f18KeyCode), keyDown: down
            ) else { continue }
            // 눌려 있는 보조 키가 섞이지 않게 기능 키 플래그만 준다.
            event.flags = .maskSecondaryFn
            event.post(tap: .cghidEventTap)
        }
    }
}
