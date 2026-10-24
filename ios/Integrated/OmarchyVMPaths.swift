// Copyright 2026 Tom Ballard. MIT License.
import Foundation

enum OmarchyVMPaths {
    static func relocateDiagnosticPaths(at machine: URL) throws {
        let config = machine.appendingPathComponent("config.plist")
        let original = try Data(contentsOf: config)
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist = try PropertyListSerialization.propertyList(from: original, format: &format)
        var changed = false
        let revised = relocate(plist, to: machine, changed: &changed)
        guard changed else { return }
        let backup = machine.appendingPathComponent("config-before-diagnostic-path-migration.plist")
        if !FileManager.default.fileExists(atPath: backup.path) { try original.write(to: backup, options: .atomic) }
        try PropertyListSerialization.data(fromPropertyList: revised, format: format, options: 0).write(to: config, options: .atomic)
    }

    static func relocate(_ value: Any, to machine: URL, changed: inout Bool) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues { relocate($0, to: machine, changed: &changed) }
        }
        if let array = value as? [Any] { return array.map { relocate($0, to: machine, changed: &changed) } }
        guard let text = value as? String,
              text.hasSuffix("/boot-console.log") || text.hasSuffix("/boot-uart.log"),
              let beginning = text.range(of: "/private/var/mobile/Containers/Data/Application/") ?? text.range(of: "/var/mobile/Containers/Data/Application/"),
              let marker = text.range(of: "/Documents/iPhomarchy.utm/", range: beginning.lowerBound..<text.endIndex) else { return value }
        let suffix = text[marker.upperBound...]
        let result = String(text[..<beginning.lowerBound]) + machine.path + "/" + suffix
        changed = changed || result != text
        return result
    }
}
