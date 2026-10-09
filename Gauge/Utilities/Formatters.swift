import Foundation
import SwiftUI
import AppKit

enum Fmt {
    private static let binary: ByteCountFormatter = { let f = ByteCountFormatter(); f.countStyle = .binary; f.allowsNonnumericFormatting = false; return f }()
    private static let decimal: ByteCountFormatter = { let f = ByteCountFormatter(); f.countStyle = .decimal; f.allowsNonnumericFormatting = false; return f }()

    static func bytes(_ b: UInt64, _ units: ByteUnits = .binary) -> String {
        (units == .binary ? binary : decimal).string(fromByteCount: Int64(clamping: b))
    }
    static func bytesD(_ b: Double, _ units: ByteUnits = .binary) -> String { bytes(UInt64(max(0, b)), units) }

    static func rate(_ bps: Double, _ units: ByteUnits = .binary) -> String {
        if bps < 1 { return "0 KB/s" }
        let s = bytesD(bps, units)
        return s + "/s"
    }

    /// Compact rate for the menu bar, e.g. "1.2M".
    static func compactRate(_ bps: Double) -> String {
        switch bps {
        case ..<1_000: return String(format: "%.0fB", bps)
        case ..<1_000_000: return String(format: "%.0fK", bps / 1_000)
        case ..<1_000_000_000: return String(format: "%.1fM", bps / 1_000_000)
        default: return String(format: "%.1fG", bps / 1_000_000_000)
        }
    }

    static func percent(_ v: Double, decimals: Int = 1) -> String { String(format: "%.\(decimals)f%%", v) }

    /// Converts a "100 == one core" figure to the user's chosen normalisation.
    static func cpu(_ raw: Double, cores: Int, _ norm: CPUNormalization) -> Double {
        norm == .machine ? raw / Double(max(1, cores)) : raw
    }

    static func power(_ mw: Double) -> String {
        mw >= 1000 ? String(format: "%.2f W", mw / 1000) : String(format: "%.0f mW", mw)
    }
}

enum Severity: Int, Comparable {
    case normal, elevated, high
    static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    var color: Color { self == .high ? .red : self == .elevated ? .orange : .accentColor }

    /// `rawCPU`: 100 == one core. Elevated at ~1 core, high at ≥ half the machine.
    static func cpu(_ rawCPU: Double, cores: Int) -> Severity {
        if rawCPU >= 50 * Double(max(cores, 1)) { return .high }
        if rawCPU >= 100 { return .elevated }
        return .normal
    }
    static func memory(_ bytes: UInt64, total: UInt64) -> Severity {
        guard total > 0 else { return .normal }
        let f = Double(bytes) / Double(total)
        return f >= 0.25 ? .high : f >= 0.10 ? .elevated : .normal
    }
}

@MainActor
final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()
    func icon(forBundlePath path: String?, fallbackSymbol: String = "gearshape") -> NSImage {
        let k = (path ?? "symbol:" + fallbackSymbol) as NSString
        if let i = cache.object(forKey: k) { return i }
        let img: NSImage
        if let path { img = NSWorkspace.shared.icon(forFile: path) }
        else { img = NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: nil) ?? NSImage() }
        img.size = NSSize(width: 32, height: 32)
        cache.setObject(img, forKey: k)
        return img
    }
}
