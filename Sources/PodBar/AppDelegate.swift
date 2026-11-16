import AppKit
import ServiceManagement
import PodBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let nameItem = NSMenuItem()
    private let stateItem = NSMenuItem()
    private let leftItem = NSMenuItem()
    private let rightItem = NSMenuItem()
    private let caseItem = NSMenuItem()
    private let noteItem = NSMenuItem()
    private let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
    private let loginItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLogin), keyEquivalent: "")
    private var report: BluetoothReport?
    private var lastRead: Date?
    private var failure: String?
    private var request: ProfilerRequest?
    private var generation = 0
    private var timer: Timer?
    private var sleeping = false
    private let connectionMonitor = BluetoothConnectionMonitor()
    private var reconnectingDeviceID: String?
    private var connectionRetriesRemaining = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Finder and login-item launches can overlap. Keep a single menu bar item.
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "PodBar.Battery"
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleNone
        menu.autoenablesItems = false
        menu.delegate = self
        for item in [nameItem, stateItem, leftItem, rightItem, caseItem, noteItem] {
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        refreshItem.target = self
        loginItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(loginItem)
        let settings = NSMenuItem(title: "蓝牙设置…", action: #selector(openBluetooth), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let hint = NSMenuItem(title: "按住 ⌘ 拖动，可移到电池旁", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        let quit = NSMenuItem(title: "退出 PodBar", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        connectionMonitor.onConnectionChange = { [weak self] id, connected in
            self?.connectionChanged(deviceID: id, connected: connected)
        }
        connectionMonitor.start()
        render()
        refreshNow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        request?.cancel()
        connectionMonitor.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Finder/Spotlight reopening keeps settings and Quit reachable while the item is hidden.
        refreshNow()
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        return false
    }

    func menuWillOpen(_ menu: NSMenu) {
        render()
        if !sleeping, Date().timeIntervalSince(lastRead ?? .distantPast) >= 15 { refreshNow() }
    }

    @objc private func refreshNow() {
        guard request == nil, !sleeping else { return }
        timer?.invalidate()
        // Never retain an old reading across a long stall or a wake transition.
        if Date().timeIntervalSince(lastRead ?? .distantPast) > 150 { report = nil }
        let request = ProfilerRequest()
        self.request = request
        generation += 1
        let currentGeneration = generation
        render()
        request.start { [weak self] result in
            guard let self, self.generation == currentGeneration, !self.sleeping else { return }
            self.request = nil
            switch result {
            case .success(let report):
                self.connectionMonitor.updateDevices(report.devices)
                self.report = report.disconnecting(deviceIDs: self.connectionMonitor.disconnectedDeviceIDs)
                self.lastRead = Date()
                self.failure = nil
            case .failure(let error):
                self.report = nil
                self.lastRead = nil
                self.failure = error.localizedDescription
            }
            self.render()
            self.scheduleAfterReading()
        }
    }

    private func connectionChanged(deviceID: String, connected: Bool) {
        guard !sleeping else { return }
        // Invalidate an in-flight report from before the transition, then query immediately.
        generation += 1
        request?.cancel()
        request = nil
        failure = nil
        if !connected {
            report = report?.disconnecting(deviceIDs: [deviceID])
            render()
        }
        reconnectingDeviceID = connected ? deviceID : nil
        connectionRetriesRemaining = connected ? 3 : 0
        refreshNow()
    }

    private func scheduleAfterReading() {
        if let id = reconnectingDeviceID, connectionRetriesRemaining > 0 {
            let device = report?.devices.first { BluetoothReport.normalizedDeviceID($0.id) == id }
            // The Bluetooth connection can precede system_profiler's battery update.
            if device?.isConnected != true || device?.left == nil || device?.right == nil {
                connectionRetriesRemaining -= 1
                scheduleRefresh(after: 2)
                return
            }
        }
        reconnectingDeviceID = nil
        connectionRetriesRemaining = 0
        scheduleRefresh(after: report?.primaryDevice?.isConnected == true ? 60 : 120)
    }

    private func scheduleRefresh(after interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(refreshNow), userInfo: nil, repeats: false)
        timer.tolerance = interval > 10 ? 5 : 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func willSleep() {
        sleeping = true
        generation += 1
        timer?.invalidate()
        request?.cancel()
        request = nil
        connectionMonitor.stop()
        reconnectingDeviceID = nil
        connectionRetriesRemaining = 0
        report = nil
        lastRead = nil
        render()
    }

    @objc private func didWake() {
        sleeping = false
        failure = nil
        connectionMonitor.start()
        render()
        scheduleRefresh(after: 2)
    }

    private func render() {
        let device = report?.primaryDevice
        let image = StatusRenderer.image(left: device?.left, right: device?.right)
        statusItem.button?.image = image
        // Explicit length avoids AppKit adding automatic horizontal image padding.
        statusItem.length = image.size.width
        // Retain the item and background timer so a later connection can reveal it again.
        statusItem.isVisible = device?.isConnected == true && !sleeping
        nameItem.attributedTitle = NSAttributedString(string: device?.name ?? "PodBar", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ])

        let status: String
        if sleeping { status = "Mac 已休眠，等待唤醒" }
        else if let failure { status = failure }
        else if report?.power == .off { status = "蓝牙已关闭" }
        else if device?.isConnected == true {
            if device?.left == nil && device?.right == nil { status = "已连接 · 系统暂未报告左右耳电量" }
            else { status = "已连接 · \(readTime)读取" }
        } else if device != nil { status = "未连接到这台 Mac" }
        else if request != nil { status = "正在读取 AirPods…" }
        else if report?.power == .unknown { status = "系统暂未提供蓝牙状态" }
        else { status = "未发现已配对的 AirPods" }
        stateItem.title = status
        leftItem.title = "左耳\t\(percent(device?.left))"
        rightItem.title = "右耳\t\(percent(device?.right))"
        caseItem.title = "充电盒\t\(percent(device?.caseBattery))"

        let note: String
        if device?.isConnected == true {
            if let combined = device?.combined, device?.left == nil && device?.right == nil {
                note = "系统仅提供整体电量：\(combined)%"
            } else if device?.caseBattery != nil {
                note = "充电盒为系统最近报告值，合盖后可能不更新"
            } else { note = "打开充电盒靠近 Mac，可尝试更新盒子电量" }
        } else { note = "连接 AirPods 后自动显示；也可点击立即刷新" }
        noteItem.attributedTitle = NSAttributedString(string: note, attributes: [.font: NSFont.systemFont(ofSize: 11)])
        refreshItem.title = request == nil ? "立即刷新" : "正在刷新…"
        refreshItem.isEnabled = request == nil && !sleeping
        updateLoginItem()
        let accessibility = "PodBar，\(device?.name ?? "AirPods")，\(status)，左耳 \(percent(device?.left))，右耳 \(percent(device?.right))"
        statusItem.button?.toolTip = nil
        statusItem.button?.setAccessibilityLabel(accessibility)
    }

    private var readTime: String {
        guard let lastRead else { return "刚刚" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: lastRead)
    }

    private func percent(_ value: Int?) -> String { value.map { "\($0)%" } ?? "--" }

    private func updateLoginItem() {
        let status = SMAppService.mainApp.status
        loginItem.state = status == .enabled ? .on : (status == .requiresApproval ? .mixed : .off)
        loginItem.title = status == .requiresApproval ? "登录时启动 · 需在系统设置中允许…" : "登录时启动"
    }

    @objc private func toggleLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法更新登录启动设置"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        updateLoginItem()
    }

    @objc private func openBluetooth() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}
