import AppKit
import HanKeyCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store = HotKeyStore()
    private let defaults = UserDefaults.standard
    /// 시스템 설정을 바꾸는 작업은 순서대로 한 줄로 처리한다.
    private let work = DispatchQueue(label: "hankey.work")

    private let pressHotKey = PressHotKey()
    /// 즉시 전환 방식으로 동작 중인가(메인 스레드에서만 읽고 쓴다).
    private var instant = false
    private var lastPress = Date.distantPast
    private var permissionTimer: Timer?

    private let triggerDefaultsKey = "triggerKey"
    private let backupDefaultsKey = "hotKeyBackup"

    private var trigger: TriggerKey? {
        get { defaults.string(forKey: triggerDefaultsKey).flatMap(TriggerKey.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: triggerDefaultsKey) }
    }

    private var backup: HotKeyBackup? {
        get { HotKeyBackup(plist: defaults.dictionary(forKey: backupDefaultsKey)) }
        set { defaults.set(newValue?.plist, forKey: backupDefaultsKey) }
    }

    // MARK: - 실행 · 종료

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "HanKey")
            image?.isTemplate = true
            button.image = image
            if image == nil { button.title = "한" }
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        pressHotKey.onPress = { [weak self] in self?.pressed() }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(reapplyMapping), name: NSWorkspace.didWakeNotification, object: nil
        )

        // 키를 고른 적이 없으면 시스템 설정을 건드리지 않는다.
        if let trigger { activate(trigger) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard trigger != nil else { return }
        pressHotKey.unregister()
        work.sync { self.disable() }
    }

    // MARK: - 적용 · 해제

    /// 메인 스레드에서 부른다. 권한이 있으면 즉시 전환, 없으면 기본 방식(뗄 때 전환)으로 건다.
    private func activate(_ key: TriggerKey) {
        instant = SyntheticKey.canPost && pressHotKey.register()
        if !instant { pressHotKey.unregister() }
        let destination = instant ? KeyMapping.f19Usage : KeyMapping.f18Usage
        work.async { self.enable(key, destination: destination) }
    }

    private func deactivate() {
        instant = false
        pressHotKey.unregister()
        work.async { self.disable() }
    }

    /// work 큐에서 실행.
    private func enable(_ key: TriggerKey, destination: UInt64) {
        HIDRemapper.apply(trigger: key, destination: destination)
        if let linked = InputSourceHotKey.link(store.read()) {
            backup = linked.backup
            store.write(linked.hotkeys)
            HotKeyStore.activate()
        } else if HotKeyStore.liveIsF18() == false {
            // 환경설정은 F18 인데 아직 반영되지 않은 상태.
            HotKeyStore.activate()
        }
        _ = HotKeyStore.waitForLive(true)
    }

    /// work 큐에서 실행.
    private func disable() {
        HIDRemapper.apply(trigger: nil)
        guard let backup else { return }
        if let restored = InputSourceHotKey.unlink(store.read(), backup: backup) {
            store.write(restored)
            HotKeyStore.activate()
            _ = HotKeyStore.waitForLive(false)
        }
        self.backup = nil
    }

    /// 즉시 전환: 고른 키를 누른 순간 불린다.
    private func pressed() {
        let now = Date()
        // 키보드 접점 떨림으로 한 번 누름이 두 번 들어오는 경우를 거른다.
        guard now.timeIntervalSince(lastPress) > 0.08 else { return }
        lastPress = now
        if InputSource.isSecureInput {
            InputSource.selectNext()
        } else {
            SyntheticKey.tapF18()
        }
    }

    private var isLinked: Bool {
        HotKeyStore.liveIsF18() ?? InputSourceHotKey.isF18(store.read()[InputSourceHotKey.key])
    }

    // MARK: - 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        // 메뉴를 열 때마다 권한 변화와 풀린 매핑(재부팅 · 키보드 재연결)을 반영한다.
        if let trigger {
            if SyntheticKey.canPost != instant {
                activate(trigger)
            } else {
                reapplyMapping()
            }
        }

        menu.removeAllItems()
        let trigger = self.trigger
        let linked = isLinked

        let status: String
        if let trigger {
            if !linked {
                status = "⚠︎ 시스템 단축키 연결 안 됨"
            } else {
                status = "동작 중 — \(trigger.title) · " + (instant ? "누르는 즉시 전환" : "키를 뗄 때 전환")
            }
        } else {
            status = "한영 전환 키를 선택하세요"
        }
        menu.addItem(label(status))
        menu.addItem(.separator())

        for key in TriggerKey.allCases {
            let item = NSMenuItem(title: key.title, action: #selector(selectKey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key.rawValue
            item.state = key == trigger ? .on : .off
            menu.addItem(item)
        }
        let off = NSMenuItem(title: "사용 안 함", action: #selector(selectKey(_:)), keyEquivalent: "")
        off.target = self
        off.state = trigger == nil ? .on : .off
        menu.addItem(off)

        if trigger != nil, !linked {
            menu.addItem(.separator())
            menu.addItem(action("다시 연결", #selector(relink)))
            menu.addItem(action("키보드 설정 열기…", #selector(openKeyboardSettings)))
            menu.addItem(label("단축키 › 입력 소스 › 이전 입력 소스 선택에 고른 키를 등록"))
        }
        if trigger != nil, !instant {
            menu.addItem(.separator())
            menu.addItem(action("누르는 즉시 전환 켜기… (손쉬운 사용 권한)", #selector(requestInstant)))
        }

        menu.addItem(.separator())
        let login = action("로그인 시 실행", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(action("HanKey 종료", #selector(quit)))
    }

    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - 동작

    @objc private func selectKey(_ sender: NSMenuItem) {
        let key = (sender.representedObject as? String).flatMap(TriggerKey.init(rawValue:))
        guard key != trigger else { return }
        if key == .capsLock, NSEvent.modifierFlags.contains(.capsLock) {
            alert("Caps Lock 이 켜져 있습니다", "켜진 채로 바꾸면 끌 수 없게 됩니다. Caps Lock 을 끈 뒤 다시 선택해 주세요.")
            return
        }
        trigger = key
        if let key {
            activate(key)
        } else {
            deactivate()
        }
    }

    @objc private func relink() {
        guard let trigger else { return }
        activate(trigger)
        work.async {
            if HotKeyStore.liveIsF18() == false {
                DispatchQueue.main.async {
                    self.alert(
                        "시스템 단축키를 자동으로 연결하지 못했습니다",
                        "키보드 설정 › 키보드 단축키 › 입력 소스 › 이전 입력 소스 선택을 누른 뒤 \(trigger.title) 키를 눌러 등록해 주세요."
                    )
                }
            }
        }
    }

    /// 손쉬운 사용 권한을 요청하고, 허용되면 바로 즉시 전환으로 바꾼다.
    @objc private func requestInstant() {
        SyntheticKey.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        permissionTimer?.invalidate()
        let started = Date()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            if SyntheticKey.canPost, let trigger = self.trigger {
                timer.invalidate()
                self.activate(trigger)
            } else if Date().timeIntervalSince(started) > 300 {
                timer.invalidate()
            }
        }
    }

    @objc private func reapplyMapping() {
        guard let trigger else { return }
        let destination = instant ? KeyMapping.f19Usage : KeyMapping.f18Usage
        work.async { HIDRemapper.apply(trigger: trigger, destination: destination) }
    }

    @objc private func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            alert("로그인 항목을 바꾸지 못했습니다", error.localizedDescription)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
