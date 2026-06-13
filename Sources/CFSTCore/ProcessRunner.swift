import Foundation

public struct CFSTRunResult: Sendable {
    public var results: [SpeedTestResult]
    public var standardOutput: String
    public var standardError: String
    public var resultFileURL: URL

    public init(results: [SpeedTestResult], standardOutput: String, standardError: String, resultFileURL: URL) {
        self.results = results
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.resultFileURL = resultFileURL
    }
}

public struct CFSTProcessRunner: Sendable {
    public var executableURL: URL
    public var resourceDirectoryURL: URL

    public init(executableURL: URL, resourceDirectoryURL: URL) {
        self.executableURL = executableURL
        self.resourceDirectoryURL = resourceDirectoryURL
    }

    public static func bundled(bundle: Bundle = .main) throws -> CFSTProcessRunner {
        let arch = ProcessInfo.processInfo.machineHardwareName
        let preferredName = arch == "x86_64" ? "cfst-darwin-amd64" : "cfst-darwin-arm64"
        if let executable = bundle.url(forResource: preferredName, withExtension: nil) {
            return CFSTProcessRunner(executableURL: executable, resourceDirectoryURL: executable.deletingLastPathComponent())
        }
        if arch == "x86_64", bundle.url(forResource: "cfst-darwin-arm64", withExtension: nil) != nil {
            throw CFSTError.missingBinary("cfst-darwin-amd64。当前包只内置了 Apple Silicon 版本，请提供 Intel 版 cfst_darwin_amd64 后重新打包。")
        }
        if let executable = bundle.url(forResource: "cfst", withExtension: nil) {
            return CFSTProcessRunner(executableURL: executable, resourceDirectoryURL: executable.deletingLastPathComponent())
        }
        throw CFSTError.missingBinary(preferredName)
    }

    public func run(template: SpeedTestTemplate) async throws -> CFSTRunResult {
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw CFSTError.missingBinary(executableURL.path)
        }

        let runDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CFSTManager", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let resultURL = runDirectory.appendingPathComponent("result.csv")
        let ipFileURL = resourceDirectoryURL.appendingPathComponent(template.ipMode.defaultIPFileName)
        let arguments = try template.makeArguments(outputPath: resultURL.path, ipFilePath: ipFileURL.path)

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = runDirectory

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            let outputBuffer = LockedDataBuffer()
            let errorBuffer = LockedDataBuffer()

            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                outputBuffer.append(data)
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                errorBuffer.append(data)
            }

            process.terminationHandler = { process in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                let finalOutputData = outputBuffer.data()
                let finalErrorData = errorBuffer.data()
                let output = String(data: finalOutputData, encoding: .utf8) ?? ""
                let error = String(data: finalErrorData, encoding: .utf8) ?? ""
                do {
                    guard process.terminationStatus == 0 else {
                        throw CFSTError.processFailed(process.terminationStatus, output + "\n" + error)
                    }
                    let results = try CSVParser.parseSpeedTestResults(fileURL: resultURL)
                    continuation.resume(returning: CFSTRunResult(
                        results: results,
                        standardOutput: output,
                        standardError: error,
                        resultFileURL: resultURL
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        let copy = storage
        lock.unlock()
        return copy
    }
}

private extension ProcessInfo {
    var machineHardwareName: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        if machine.last == 0 {
            machine.removeLast()
        }
        return String(decoding: machine.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
