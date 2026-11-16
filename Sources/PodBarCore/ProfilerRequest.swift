import Foundation
import Darwin

public enum ProfilerError: LocalizedError, Equatable {
    case unavailable, timedOut, cancelled, failed(Int32)
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "系统暂未提供蓝牙信息"
        case .timedOut: return "读取蓝牙信息超时"
        case .cancelled: return "读取已取消"
        case .failed(let code): return "系统蓝牙查询失败（\(code)）"
        }
    }
}

/// One bounded, cancellable subprocess. It never scans, connects, or changes Bluetooth settings.
public final class ProfilerRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false
    private let executable: String
    private let arguments: [String]
    private let timeout: TimeInterval

    public init(executable: String = "/usr/sbin/system_profiler",
                arguments: [String] = ["SPBluetoothDataType", "-json", "-detailLevel", "basic", "-timeout", "10"],
                timeout: TimeInterval = 12) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
    }

    public func start(completion: @escaping (Result<BluetoothReport, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try BluetoothReport.parse(self.readData()) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    public func cancel() { stop(timedOut: false) }

    private func stop(timedOut: Bool) {
        lock.lock()
        if timedOut { self.timedOut = true } else { cancelled = true }
        let current = process
        if let current, current.isRunning { current.terminate() }
        lock.unlock()
        // Some system processes ignore SIGTERM. Bound shutdown as well as the query itself.
        if let current {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                if current.isRunning { kill(current.processIdentifier, SIGKILL) }
            }
        }
    }

    public func readData() throws -> Data {
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "en_US.UTF-8"
        task.environment = environment
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice

        lock.lock()
        if cancelled { lock.unlock(); throw ProfilerError.cancelled }
        process = task
        do { try task.run() }
        catch { process = nil; lock.unlock(); throw error }
        lock.unlock()

        let deadline = DispatchWorkItem { [weak self] in self?.stop(timedOut: true) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
        // Drain stdout before waiting, so the pipe cannot deadlock when the report is large.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        deadline.cancel()
        try? output.fileHandleForReading.close()
        lock.lock()
        process = nil
        let wasCancelled = cancelled
        let didTimeOut = timedOut
        lock.unlock()
        if wasCancelled { throw ProfilerError.cancelled }
        if didTimeOut { throw ProfilerError.timedOut }
        guard task.terminationStatus == 0 else { throw ProfilerError.failed(task.terminationStatus) }
        return data
    }
}
