import AppKit
import HanKeyCore

// 진단용: 현재 상태만 출력하고 끝낸다. 아무것도 바꾸지 않는다.
if CommandLine.arguments.contains("--status") {
    let store = HotKeyStore()
    let mapping = HIDRemapper.current()
    print("키 매핑 항목: \(mapping.count)")
    for entry in mapping {
        print("  0x\(String(entry.src, radix: 16)) → 0x\(String(entry.dst, radix: 16))")
    }
    print("환경설정 단축키 F18: \(InputSourceHotKey.isF18(store.read()[InputSourceHotKey.key]))")
    print("실제 적용 단축키 F18: \(HotKeyStore.liveIsF18().map(String.init) ?? "확인 불가")")
    print("즉시 전환 권한(손쉬운 사용): \(SyntheticKey.canPost)")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
