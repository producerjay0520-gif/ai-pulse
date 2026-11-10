import SwiftUI
import AppKit
import UserNotifications
import AIPulseCore

@main
struct AIPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 메뉴바 아이콘·패널·설정 창은 StatusBarController(AppKit)가 직접 관리한다.
        // SwiftUI App 은 최소 하나의 Scene 이 필요해서 빈 Settings 를 둔다.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppearanceController.applySaved()
        Notifier.shared.setup(delegate: self)
        PulseStore.shared.start()
        StatusBarController.shared.install()
    }

    /// 이미 실행 중일 때 Spotlight/Finder 에서 다시 열면 패널을 창으로 띄운다 (메뉴바 아이콘이 가려진 경우 대비)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusBarController.shared.showPanelWindow()
        return false
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let key = response.notification.request.content.userInfo["sessionKey"] as? String
        Task { @MainActor in
            if let key, let session = PulseStore.shared.session(forKey: key) {
                TerminalJumper.focus(session)
            }
        }
        completionHandler()
    }
}

/// 메뉴바 아이콘(NSStatusItem), 팝오버, 대체 패널 창, 설정 창
@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var panelWindow: NSWindow?
    private(set) var settingsWindow: NSWindow?
    private(set) var onboardingWindow: NSWindow?
    private var labelTimer: Timer?

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true
        if let button = item.button {
            button.image = Self.symbol("waveform")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "AI Pulse"
        }
        statusItem = item

        let hosting = NSHostingController(rootView: PopoverView().environment(PulseStore.shared))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true

        updateLabel()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { StatusBarController.shared.updateLabel() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        labelTimer = timer

        if !UserDefaults.standard.bool(forKey: Prefs.onboarded) {
            showOnboarding()
        }
    }

    // MARK: Onboarding

    func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView {
                UserDefaults.standard.set(true, forKey: Prefs.onboarded)
                StatusBarController.shared.closeOnboarding()
            }
            .environment(PulseStore.shared)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "AI Pulse 시작하기"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            restoreAccessoryPolicy(whenClosing: window)
            onboardingWindow = window
        }
        // 닫기 버튼으로 닫아도 다시 뜨지 않게 한 번 보여 주면 완료로 본다
        UserDefaults.standard.set(true, forKey: Prefs.onboarded)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    /// 창이 닫히면 Dock 아이콘 없는 메뉴바 앱으로 돌아간다 (다른 창이 열려 있으면 유지)
    private func restoreAccessoryPolicy(whenClosing window: NSWindow) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let controller = StatusBarController.shared
                let others = [controller.settingsWindow, controller.onboardingWindow]
                    .compactMap { $0 }
                    .filter { $0 !== window && $0.isVisible }
                if others.isEmpty { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }

    func closeOnboarding() {
        onboardingWindow?.close()
        // 첫 실행 직후 메뉴바 아이콘 위치를 알려 주기 위해 패널을 한 번 열어 준다
        togglePopover(nil)
    }

    // MARK: Label

    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "AI Pulse")
        image?.isTemplate = true
        return image
    }

    private var lastLabel: (String, String) = ("", "")

    func updateLabel() {
        guard let button = statusItem?.button else { return }
        let content = MenuBarContent.compute(PulseStore.shared)
        guard content.symbol != lastLabel.0 || content.text != lastLabel.1 else { return }
        lastLabel = (content.symbol, content.text)
        button.image = Self.symbol(content.symbol)
        button.title = content.text.isEmpty ? "" : " " + content.text
    }

    // MARK: Popover

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else {
            showPanelWindow()
            return
        }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    /// 메뉴바 아이콘 없이 쓰는 떠 있는 패널 창 (화면 오른쪽 위)
    func showPanelWindow() {
        closePopover()
        if panelWindow == nil {
            let hosting = NSHostingController(rootView: PopoverView().environment(PulseStore.shared))
            hosting.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "AI Pulse"
            window.level = .floating
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            panelWindow = window
        }
        guard let window = panelWindow else { return }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16, y: frame.maxY - size.height - 12))
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Settings

    func showSettings() {
        closePopover()
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView().environment(PulseStore.shared))
            let window = NSWindow(contentViewController: hosting)
            window.title = "AI Pulse 설정"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            restoreAccessoryPolicy(whenClosing: window)
            settingsWindow = window
        }
        // 메뉴바 전용 앱은 설정 창이 뒤로 숨기 쉬워 열려 있는 동안만 일반 앱으로 전환
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

/// 메뉴바에 보여줄 아이콘과 글자
enum MenuBarContent {
    @MainActor
    static func compute(_ store: PulseStore) -> (symbol: String, text: String) {
        let approvals = store.pendingApprovals
        let state = store.aggregateState
        if approvals > 0 { return ("hand.raised.fill", "\(approvals)") }
        if state == .error { return ("exclamationmark.triangle.fill", "") }
        if let lead = store.orderedSessions.first, lead.state.isActive, let p = lead.progress {
            return ("waveform", "\(Int((p * 100).rounded()))%")
        }
        if state?.isActive == true { return ("waveform.path.ecg", "") }
        return ("waveform", "")
    }
}
