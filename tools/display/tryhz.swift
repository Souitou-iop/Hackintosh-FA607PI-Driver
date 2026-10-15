// tryhz list                      -- all modes of the main display (looks-like, backing, Hz)
// tryhz <w> <h> <hz> [secs]       -- switch to that looks-like mode for <secs> (default 10), then back (recovery: via native first)
// tryhz <w> <h> <hz> keep         -- switch permanently
import CoreGraphics
import Foundation
let a = CommandLine.arguments, d = CGMainDisplayID(), cur = CGDisplayCopyDisplayMode(d)!
let all = CGDisplayCopyAllDisplayModes(d, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
func desc(_ m: CGDisplayMode) -> String { "\(m.width)x\(m.height) (backing \(m.pixelWidth)x\(m.pixelHeight)) @\(Int(m.refreshRate.rounded())) Hz" }
if a.count < 4 { for m in all where m.isUsableForDesktopGUI() && (m.pixelWidth > m.width || m.width >= 1920) { print(desc(m), m.pixelWidth > m.width ? "HiDPI" : "", m.ioDisplayModeID == cur.ioDisplayModeID && m.width == cur.width ? "<= current" : "") }; exit(0) }
let w = Int(a[1])!, h = Int(a[2])!, hz = Double(a[3])!
let hidpi = !(w == cur.pixelWidth && false)
guard let m = all.filter({ $0.width == w && $0.height == h && abs($0.refreshRate - hz) < 1 }).max(by: { $0.pixelWidth < $1.pixelWidth }) else { print("no mode \(w)x\(h)@\(hz)"); exit(3) }
func set(_ m: CGDisplayMode, _ o: CGConfigureOption) -> Int32 { var c: CGDisplayConfigRef?; CGBeginDisplayConfiguration(&c); CGConfigureDisplayWithDisplayMode(c, d, m, nil); return CGCompleteDisplayConfiguration(c, o).rawValue }
if a.count > 4 && a[4] == "keep" { print("kept \(desc(m)):", set(m, .permanently)); exit(0) }
let secs = a.count > 4 ? Double(a[4]) ?? 10 : 10
print("trying \(desc(m)) for \(Int(secs)) s:", set(m, .forSession)); fflush(stdout)
Thread.sleep(forTimeInterval: 1.5)
let now = CGDisplayCopyDisplayMode(d)!; print("  now:", desc(now)); fflush(stdout)
Thread.sleep(forTimeInterval: max(0, secs - 1.5))
if let nat = all.first(where: { $0.pixelWidth == $0.width && $0.width == cur.pixelWidth && abs($0.refreshRate - 60) < 1 }) { _ = set(nat, .forSession); Thread.sleep(forTimeInterval: 1) }
print("back to \(desc(cur)):", set(cur, .forSession))
