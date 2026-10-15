// extmode <w> <h> <hz>: put the external display in looks-like <w>x<h> HiDPI at <hz> for this login session.
// WindowServer only saves modes for the display sets it was in when they were set, and the login agent turns the
// built-in panel off for the session, so the external came back at its native 2560x1440 after every restart.
// Waits up to 30 s for the external display and the mode to appear.
import CoreGraphics
import Foundation
let a = CommandLine.arguments
guard a.count == 4, let w = Int(a[1]), let h = Int(a[2]), let hz = Double(a[3]) else { print("usage: extmode <w> <h> <hz>"); exit(2) }
func online() -> [CGDirectDisplayID] { var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0; CGGetOnlineDisplayList(16, &ids, &n); return Array(ids.prefix(Int(n))) }
for attempt in 0..<30 {
    if attempt > 0 { Thread.sleep(forTimeInterval: 1) }
    guard let d = online().first(where: { CGDisplayIsBuiltin($0) == 0 }) else { continue }
    let modes = CGDisplayCopyAllDisplayModes(d, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
    guard let m = modes.first(where: { $0.width == w && $0.height == h && $0.pixelWidth > $0.width && abs($0.refreshRate - hz) < 1 }) else { continue }
    if let cur = CGDisplayCopyDisplayMode(d), cur.ioDisplayModeID == m.ioDisplayModeID { print("display \(d) already \(w)x\(h) HiDPI @ \(Int(hz)) Hz"); exit(0) }
    var c: CGDisplayConfigRef?; CGBeginDisplayConfiguration(&c)
    CGConfigureDisplayWithDisplayMode(c, d, m, nil)
    let r = CGCompleteDisplayConfiguration(c, .forSession)
    print("display \(d) -> \(w)x\(h) HiDPI (backing \(m.pixelWidth)x\(m.pixelHeight)) @ \(Int(m.refreshRate)) Hz: \(r.rawValue)")
    exit(r == .success ? 0 : 1)
}
print("no external display with \(w)x\(h) HiDPI at \(Int(hz)) Hz after 30 s"); exit(3)
