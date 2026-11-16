import Foundation
import CoreFoundation

public struct PodDevice: Equatable {
    public let id: String
    public let name: String
    public let isConnected: Bool
    public let left: Int?
    public let right: Int?
    public let caseBattery: Int?
    public let combined: Int?
}

public struct BluetoothReport: Equatable {
    public enum Power: Equatable { case on, off, unknown }
    public let power: Power
    public let devices: [PodDevice]

    /// Connected devices take priority. A stable order avoids switching on each refresh.
    public var primaryDevice: PodDevice? {
        devices.sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            let a = $0.name.localizedCaseInsensitiveContains("Pro")
            let b = $1.name.localizedCaseInsensitiveContains("Pro")
            if a != b { return a }
            return $0.id < $1.id
        }.first
    }

    public static func normalizedDeviceID(_ id: String) -> String {
        id.lowercased().replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
    }

    /// Connection events are newer than the profiler's cached battery report.
    public func disconnecting(deviceIDs: Set<String>) -> BluetoothReport {
        let ids = Set(deviceIDs.map(Self.normalizedDeviceID))
        return BluetoothReport(power: power, devices: devices.map { device in
            guard ids.contains(Self.normalizedDeviceID(device.id)) else { return device }
            return PodDevice(id: device.id, name: device.name, isConnected: false,
                             left: nil, right: nil, caseBattery: nil, combined: nil)
        })
    }

    public static func parse(_ data: Data) throws -> BluetoothReport {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reports = root["SPBluetoothDataType"] as? [[String: Any]],
              reports.contains(where: { !$0.isEmpty }) else {
            throw ProfilerError.unavailable
        }
        var power: Power = .unknown
        var devices: [String: PodDevice] = [:]
        for report in reports {
            if let controller = report["controller_properties"] as? [String: Any] {
                let state = (controller["controller_state"] as? String ?? "").lowercased()
                if ["attrib_on", "on", "yes"].contains(state) { power = .on }
                else if ["attrib_off", "off", "no"].contains(state), power != .on { power = .off }
            }
            for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
                for item in report[key] as? [[String: Any]] ?? [] {
                    for (name, raw) in item {
                        guard let fields = raw as? [String: Any], isAirPods(name: name, fields: fields) else { continue }
                        let id = fields["device_address"] as? String ?? name
                        // Disconnected system reports can retain old battery fields. Never display them.
                        let online = connected && power != .off
                        let device = PodDevice(
                            id: id, name: name, isConnected: online,
                            left: online ? percentage(fields["device_batteryLevelLeft"]) : nil,
                            right: online ? percentage(fields["device_batteryLevelRight"]) : nil,
                            caseBattery: online ? percentage(fields["device_batteryLevelCase"]) : nil,
                            combined: online ? percentage(fields["device_batteryLevel"]) : nil
                        )
                        if devices[id]?.isConnected != true { devices[id] = device }
                    }
                }
            }
        }
        return BluetoothReport(power: power, devices: Array(devices.values))
    }

    private static func isAirPods(name: String, fields: [String: Any]) -> Bool {
        if name.localizedCaseInsensitiveContains("AirPods") { return true }
        let vendor = (fields["device_vendorID"] as? String ?? "").lowercased()
        guard vendor.contains("0x004c") || vendor.contains("apple") else { return false }
        let product = (fields["device_productID"] as? String ?? "").lowercased()
        // AirPods generations, including the user's Pro 2 USB-C (0x2024).
        let products: Set<String> = ["0x2002", "0x200e", "0x200f", "0x2013", "0x2014", "0x2019", "0x2024"]
        return products.contains(product)
            || fields["device_batteryLevelLeft"] != nil
            || fields["device_batteryLevelRight"] != nil
            || fields["device_serialNumberLeft"] != nil
            || fields["device_serialNumberRight"] != nil
    }

    static func percentage(_ value: Any?) -> Int? {
        let number: Int?
        if let raw = value as? String {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let digits = (text.hasSuffix("%") ? String(text.dropLast()) : text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            number = Int(digits)
        } else if let raw = value as? NSNumber, CFGetTypeID(raw) != CFBooleanGetTypeID() {
            let value = raw.doubleValue
            guard value.isFinite, value >= 0, value <= 100, value.rounded() == value else { return nil }
            number = Int(value)
        } else { number = nil }
        guard let number, (0...100).contains(number) else { return nil }
        return number
    }
}
