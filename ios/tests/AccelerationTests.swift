import Foundation

@main
struct AccelerationTests {
    enum FixtureError: Error { case helperFailed, assertion(String) }
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw FixtureError.assertion(message) }
    }

    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var total: UInt32 = 0
        for index in stride(from: 0, to: bytes.count, by: 2) {
            total += UInt32(bytes[index]) << 8
            if index + 1 < bytes.count { total += UInt32(bytes[index + 1]) }
        }
        while total > 65535 { total = (total & 65535) + (total >> 16) }
        return ~UInt16(total)
    }

    static func packets() throws {
        // A TCP SYN to the phone's developer service, with real IPv4 and TCP checksums.
        var bytes: [UInt8] = [0x45, 0, 0, 40, 0, 1, 0x40, 0, 64, 6, 0, 0, 10, 7, 1, 1, 10, 7, 0, 1,
                             0xc0, 0x01, 0xc0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0x50, 2, 0xff, 0xff, 0, 0, 0, 0]
        let ip = checksum(Array(bytes[0..<20]))
        bytes[10] = UInt8(ip >> 8); bytes[11] = UInt8(ip & 255)
        let pseudo = Array(bytes[12..<20]) + [0, 6, 0, 20]
        let tcp = checksum(pseudo + Array(bytes[20...]))
        bytes[36] = UInt8(tcp >> 8); bytes[37] = UInt8(tcp & 255)
        let response = try require(OmarchyLoopbackPacket.reflected(Data(bytes)))
        let reflected = Array(response)
        try check(checksum(Array(reflected[0..<20])) == 0, "Reflection broke IPv4 checksum")
        try check(checksum(Array(reflected[12..<20]) + [0, 6, 0, 20] + Array(reflected[20...])) == 0, "Reflection broke TCP checksum")
        try check(Array(reflected[12..<16]) == [10, 7, 0, 1], "Incorrect response source")
        try check(Array(reflected[16..<20]) == [10, 7, 1, 1], "Incorrect response destination")
        try check(Array(reflected[20...]) == Array(bytes[20...]), "Reflection changed TCP data")
        try check(OmarchyLoopbackPacket.reflected(Data(bytes.prefix(19))) == nil, "Truncated IP accepted")
        bytes[16] = 8
        try check(OmarchyLoopbackPacket.reflected(Data(bytes)) == nil, "Non-local traffic accepted")
        bytes[16] = 10; bytes[0] = 0x4f
        try check(OmarchyLoopbackPacket.reflected(Data(bytes)) == nil, "Invalid header length accepted")
        bytes[0] = 0x65
        try check(OmarchyLoopbackPacket.reflected(Data(bytes)) == nil, "IPv6 accepted as IPv4")
    }

    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw FixtureError.assertion("Missing fixture value") }
        return value
    }

    @MainActor
    static func launchGate() async throws {
        do {
            try await OmarchyJITLaunchGate.waitForDebugger(attached: { false }, completed: { .failure(FixtureError.helperFailed) })
            throw FixtureError.assertion("Launched after helper failure")
        } catch FixtureError.helperFailed {}
        do {
            try await OmarchyJITLaunchGate.waitForDebugger(attached: { false }, completed: { .success(()) })
            throw FixtureError.assertion("Accepted success without debugger")
        } catch OmarchyAccelerationError.message {}
        do {
            try await OmarchyJITLaunchGate.waitForDebugger(timeout: 0, attached: { false }, completed: { nil })
            throw FixtureError.assertion("Missing debugger did not time out")
        } catch OmarchyAccelerationError.message {}
        try await OmarchyJITLaunchGate.waitForDebugger(attached: { true }, completed: { nil })
        let cancelled = Task {
            try await OmarchyJITLaunchGate.waitForDebugger(attached: { false }, completed: { nil })
        }
        cancelled.cancel()
        do { try await cancelled.value; throw FixtureError.assertion("Cancelled launch continued") }
        catch is CancellationError {}
    }

    static func relocatedPaths() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vm = root.appendingPathComponent("iPhomarchy.utm")
        try files.createDirectory(at: vm, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let config: [String: Any] = ["QEMU": ["AdditionalArguments": [
            "file:/private/var/mobile/Containers/Data/Application/OLD/Documents/iPhomarchy.utm/Data/boot-uart.log",
            "file,id=bootlog,path=/var/mobile/Containers/Data/Application/OLD/Documents/iPhomarchy.utm/Data/boot-console.log",
            "file:/var/mobile/Containers/Data/Application/OTHER/Documents/unrelated.log"]]]
        let original = try PropertyListSerialization.data(fromPropertyList: config, format: .binary, options: 0)
        let configURL = vm.appendingPathComponent("config.plist")
        try original.write(to: configURL)
        let disk = vm.appendingPathComponent("omarchy.qcow2")
        try Data("existing user disk".utf8).write(to: disk)
        try OmarchyVMPaths.relocateDiagnosticPaths(at: vm)
        let revised = try Data(contentsOf: configURL)
        let decoded = try require(PropertyListSerialization.propertyList(from: revised, format: nil) as? [String: [String: [String]]])
        let arguments = try require(decoded["QEMU"]?["AdditionalArguments"])
        try check(arguments[0] == "file:" + vm.path + "/Data/boot-uart.log", "Old UART container path retained")
        try check(arguments[1] == "file,id=bootlog,path=" + vm.path + "/Data/boot-console.log", "Old console container path retained")
        try check(arguments[2].contains("OTHER/Documents/unrelated.log"), "Unrelated argument changed")
        let backup = try Data(contentsOf: vm.appendingPathComponent("config-before-diagnostic-path-migration.plist"))
        try check(backup == original, "Original config not backed up")
        try OmarchyVMPaths.relocateDiagnosticPaths(at: vm)
        try check(tryData(configURL) == revised, "Migration was not idempotent")
        try check(tryData(disk) == Data("existing user disk".utf8), "User disk changed")
    }

    static func tryData(_ url: URL) -> Data? { try? Data(contentsOf: url) }

    static func pairingFileBounds() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("pairing fixture".utf8).write(to: url)
        let small = try OmarchyPairingFile.read(url)
        try check(small == Data("pairing fixture".utf8), "Pairing bytes changed")
        try Data(repeating: 0, count: OmarchyPairingFile.maximumBytes + 1).write(to: url)
        do {
            _ = try OmarchyPairingFile.read(url)
            throw FixtureError.assertion("Oversized pairing file was read")
        } catch OmarchyAccelerationError.message {}
        try Data().write(to: url)
        do {
            _ = try OmarchyPairingFile.read(url)
            throw FixtureError.assertion("Empty pairing file was accepted")
        } catch OmarchyAccelerationError.message {}
    }

    static func main() async throws {
        try packets()
        try await launchGate()
        try relocatedPaths()
        try pairingFileBounds()
        print("Acceleration: packet checksums/filtering, launch failure/timeout/cancellation and data-preserving path migration passed.")
    }
}
