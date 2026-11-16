import AppKit
import PodBarCore

if CommandLine.arguments.contains("--diagnose") {
    do {
        let report = try BluetoothReport.parse(ProfilerRequest().readData())
        print("Bluetooth: \(report.power)")
        if report.devices.isEmpty { print("No paired AirPods found.") }
        for device in report.devices.sorted(by: { $0.name < $1.name }) {
            func value(_ n: Int?) -> String { n.map { "\($0)%" } ?? "--" }
            print("\(device.name): \(device.isConnected ? "connected" : "disconnected")")
            print("  L \(value(device.left)) / R \(value(device.right)) / Case \(value(device.caseBattery))")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("PodBar: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--watch-connections") {
        let monitor = BluetoothConnectionMonitor()
        func log(_ message: String) {
            FileHandle.standardOutput.write(Data("\(ISO8601DateFormatter().string(from: Date())) \(message)\n".utf8))
        }
        let report = try? BluetoothReport.parse(ProfilerRequest().readData())
        let names = Dictionary((report?.devices ?? []).map {
            (BluetoothReport.normalizedDeviceID($0.id), $0.name)
        }, uniquingKeysWith: { first, _ in first })
        monitor.onConnectionChange = { id, connected in
            log("\(names[id] ?? "AirPods"): \(connected ? "connected" : "disconnected") event")
        }
        monitor.start()
        monitor.updateDevices(report?.devices ?? [])
        log("Connection listener: \(monitor.isListening ? "registered" : "unavailable"); observing for 120 seconds")
        RunLoop.main.run(until: Date().addingTimeInterval(120))
        monitor.stop()
        log("Finished observing")
        return
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
