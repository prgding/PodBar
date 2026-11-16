import XCTest
@testable import PodBarCore

final class BluetoothReportTests: XCTestCase {
    private func parse(_ contents: String) throws -> BluetoothReport {
        try BluetoothReport.parse(Data(contents.utf8))
    }

    func testRealPro2Report() throws {
        let report = try parse("""
        {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},
        "device_connected":[{"AirPods Pro 2":{"device_productID":"0x2024","device_vendorID":"0x004C",
        "device_batteryLevelLeft":"100%","device_batteryLevelRight":"100%","device_batteryLevelCase":"73%"}}]}]}
        """)
        XCTAssertEqual(report.power, .on)
        XCTAssertEqual(report.primaryDevice?.left, 100)
        XCTAssertEqual(report.primaryDevice?.right, 100)
        XCTAssertEqual(report.primaryDevice?.caseBattery, 73)
        XCTAssertEqual(report.primaryDevice?.isConnected, true)
    }

    func testDisconnectedCachedBatteryIsDiscarded() throws {
        let report = try parse("""
        {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},
        "device_not_connected":[{"AirPods Pro":{"device_batteryLevelLeft":"82%","device_batteryLevelRight":"91%","device_batteryLevelCase":"75%","device_batteryLevel":"90%"}}]}]}
        """)
        XCTAssertEqual(report.primaryDevice?.isConnected, false)
        XCTAssertNil(report.primaryDevice?.left)
        XCTAssertNil(report.primaryDevice?.right)
        XCTAssertNil(report.primaryDevice?.caseBattery)
        XCTAssertNil(report.primaryDevice?.combined)
    }

    func testRenamedAirPodsAndNonAirPodsFiltering() throws {
        let report = try parse("""
        {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},"device_connected":[
        {"我的耳机":{"device_productID":"0x2024","device_vendorID":"0x004C","device_batteryLevelLeft":"0 %"}},
        {"Magic Mouse":{"device_productID":"0x030d","device_vendorID":"0x004C","device_batteryLevel":"80%"}},
        {"Sony":{"device_vendorID":"0x054C","device_batteryLevel":"100%"}}]}]}
        """)
        XCTAssertEqual(report.devices.count, 1)
        XCTAssertEqual(report.primaryDevice?.name, "我的耳机")
        XCTAssertEqual(report.primaryDevice?.left, 0)
        XCTAssertNil(report.primaryDevice?.right)
    }

    func testOnlyCombinedBatteryDoesNotInventStereoReadings() throws {
        let report = try parse("""
        {"SPBluetoothDataType":[{"device_connected":[{"AirPods":{"device_batteryLevel":"88%"}}]}]}
        """)
        XCTAssertEqual(report.primaryDevice?.combined, 88)
        XCTAssertNil(report.primaryDevice?.left)
        XCTAssertNil(report.primaryDevice?.right)
    }

    func testPowerOffInvalidatesContradictoryCachedReadings() throws {
        let report = try parse("""
        {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_off"},
        "device_connected":[{"AirPods":{"device_batteryLevelLeft":"70%"}}]}]}
        """)
        XCTAssertEqual(report.power, .off)
        XCTAssertEqual(report.primaryDevice?.isConnected, false)
        XCTAssertNil(report.primaryDevice?.left)
    }

    func testUnavailableReportIsNotTreatedAsNoDevices() {
        for data in ["{}", "{\"SPBluetoothDataType\":[{}]}", "{\"SPBluetoothDataType\":[]}", "[]", "not json"] {
            XCTAssertThrowsError(try parse(data))
        }
    }

    func testConnectedDeviceWinsAndDuplicateCannotOverwriteIt() throws {
        let report = try parse("""
        {"SPBluetoothDataType":[{"device_connected":[{"AirPods B":{"device_address":"b","device_batteryLevelRight":"45%"}}],
        "device_not_connected":[{"AirPods Pro A":{"device_address":"a"}},{"AirPods B":{"device_address":"b","device_batteryLevelRight":"99%"}}]}]}
        """)
        XCTAssertEqual(report.devices.count, 2)
        XCTAssertEqual(report.primaryDevice?.name, "AirPods B")
        XCTAssertEqual(report.primaryDevice?.right, 45)
    }

    func testBatteryValidation() {
        XCTAssertEqual(BluetoothReport.percentage(" 73 % "), 73)
        XCTAssertEqual(BluetoothReport.percentage("0%"), 0)
        XCTAssertEqual(BluetoothReport.percentage(NSNumber(value: 100)), 100)
        for value: Any in ["255%", "-1%", "Unknown", "12.5%", "NaN", "80%%", NSNumber(value: true), NSNumber(value: 12.5), NSNull()] {
            XCTAssertNil(BluetoothReport.percentage(value), "Unexpected percentage for \(value)")
        }
    }

    func testDisconnectEventOverridesStaleConnectedReportAndClearsAllBatteryFields() throws {
        let report = try parse("""
        {"SPBluetoothDataType":[{"device_connected":[{"AirPods Pro":{"device_address":"AA:BB:CC:DD:EE:FF",
        "device_batteryLevelLeft":"82%","device_batteryLevelRight":"91%","device_batteryLevelCase":"75%","device_batteryLevel":"90%"}}]}]}
        """)
        let updated = report.disconnecting(deviceIDs: ["aa-bb-cc-dd-ee-ff"])
        XCTAssertEqual(updated.primaryDevice?.isConnected, false)
        XCTAssertNil(updated.primaryDevice?.left)
        XCTAssertNil(updated.primaryDevice?.right)
        XCTAssertNil(updated.primaryDevice?.caseBattery)
        XCTAssertNil(updated.primaryDevice?.combined)
        // A subsequent connection must be able to use a fresh report normally.
        XCTAssertEqual(report.disconnecting(deviceIDs: []).primaryDevice?.left, 82)
    }

    func testDisconnectEventLeavesAnotherConnectedPairVisible() throws {
        let report = try parse("""
        {"SPBluetoothDataType":[{"device_connected":[
        {"AirPods Pro A":{"device_address":"AA:BB:CC:DD:EE:01","device_batteryLevelLeft":"80%"}},
        {"AirPods Pro B":{"device_address":"AA:BB:CC:DD:EE:02","device_batteryLevelRight":"45%"}}]}]}
        """)
        let updated = report.disconnecting(deviceIDs: ["aa-bb-cc-dd-ee-01"])
        XCTAssertEqual(updated.primaryDevice?.name, "AirPods Pro B")
        XCTAssertEqual(updated.primaryDevice?.right, 45)
        XCTAssertEqual(updated.primaryDevice?.isConnected, true)
    }
}
