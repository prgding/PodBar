import Foundation
import IOBluetooth
import PodBarCore

/// Passive system notifications only: no inquiry, pairing, or connect/disconnect commands.
@MainActor
final class BluetoothConnectionMonitor: NSObject {
    var onConnectionChange: ((String, Bool) -> Void)?
    private var connectionNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var knownDeviceIDs: Set<String> = []
    private var devices: [String: IOBluetoothDevice] = [:]
    private var disconnectedByEvent: Set<String> = []
    private var lastConnectEventUptime: [String: TimeInterval] = [:]
    private var active = false

    var isListening: Bool { connectionNotification != nil }

    // A report may briefly lag behind a disconnect event. Prevent stale data reappearing.
    // Recheck the system's cached connection state so a missed reconnect can still recover.
    var disconnectedDeviceIDs: Set<String> {
        disconnectedByEvent.filter { devices[$0]?.isConnected() != true }
    }

    func start() {
        guard !active else { return }
        active = true
        connectionNotification = IOBluetoothDevice.register(forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:)))
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] {
            if isRelevant(device) { track(device) }
        }
    }

    func updateDevices(_ reportedDevices: [PodDevice]) {
        guard active else { return }
        for reported in reportedDevices {
            knownDeviceIDs.insert(BluetoothReport.normalizedDeviceID(reported.id))
            if let device = IOBluetoothDevice(addressString: reported.id) { track(device) }
        }
    }

    func stop() {
        active = false
        connectionNotification?.unregister()
        connectionNotification = nil
        for notification in disconnectNotifications.values { notification.unregister() }
        disconnectNotifications.removeAll()
        devices.removeAll()
        disconnectedByEvent.removeAll()
        lastConnectEventUptime.removeAll()
    }

    private func isRelevant(_ device: IOBluetoothDevice) -> Bool {
        guard let address = device.addressString else { return false }
        return knownDeviceIDs.contains(BluetoothReport.normalizedDeviceID(address))
            || device.name?.localizedCaseInsensitiveContains("AirPods") == true
    }

    private func track(_ device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        let id = BluetoothReport.normalizedDeviceID(address)
        knownDeviceIDs.insert(id)
        devices[id] = device
        guard device.isConnected(), disconnectNotifications[id] == nil else { return }
        disconnectNotifications[id] = device.register(forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:)))
    }

    // The framework does not promise a callback queue. Serialize all state with the app's UI.
    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification,
                                                   device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        let notificationID = ObjectIdentifier(notification)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active,
                  self.connectionNotification.map(ObjectIdentifier.init) == notificationID,
                  let device = IOBluetoothDevice(addressString: address), self.isRelevant(device) else { return }
            let id = BluetoothReport.normalizedDeviceID(address)
            self.disconnectedByEvent.remove(id)
            self.track(device)
            // AirPods can emit several identical connect callbacks for a single transition.
            // Deliver the first immediately, without launching redundant profiler processes.
            let now = ProcessInfo.processInfo.systemUptime
            if let last = self.lastConnectEventUptime[id], now - last < 1 { return }
            self.lastConnectEventUptime[id] = now
            self.onConnectionChange?(id, true)
        }
    }

    @objc nonisolated private func deviceDisconnected(_ notification: IOBluetoothUserNotification,
                                                      device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        let notificationID = ObjectIdentifier(notification)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active else { return }
            let id = BluetoothReport.normalizedDeviceID(address)
            // Ignore callbacks from an old registration after sleep or a rapid reconnect.
            guard self.disconnectNotifications[id].map(ObjectIdentifier.init) == notificationID else { return }
            self.disconnectNotifications.removeValue(forKey: id)?.unregister()
            self.disconnectedByEvent.insert(id)
            self.lastConnectEventUptime.removeValue(forKey: id)
            self.onConnectionChange?(id, false)
        }
    }
}
