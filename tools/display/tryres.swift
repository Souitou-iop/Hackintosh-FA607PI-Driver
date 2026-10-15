// tryres list                 -- HiDPI / native modes at the current refresh rate
// tryres <w> <h> [secs]       -- switch to looks-like <w>x<h> HiDPI for <secs> (default 15), then switch back
// tryres <w> <h> keep         -- switch permanently
import CoreGraphics
import Foundation
let a = CommandLine.arguments, d = CGMainDisplayID(), cur = CGDisplayCopyDisplayMode(d)!
let all = CGDisplayCopyAllDisplayModes(d, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
let here = all.filter { abs($0.refreshRate - cur.refreshRate) < 1 }
if a.count < 3 { for m in here where m.pixelWidth > m.width || m.pixelWidth == 2560 { print("\(m.width)x\(m.height)  backing \(m.pixelWidth)x\(m.pixelHeight)  \(Int(m.refreshRate)) Hz\(m.pixelWidth > m.width ? "  HiDPI" : "")") }; exit(0) }
let w = Int(a[1])!, h = Int(a[2])!
guard let m = here.first(where: { $0.width == w && $0.height == h && $0.pixelWidth > $0.width }) else { print("no HiDPI \(w)x\(h) at \(Int(cur.refreshRate)) Hz"); exit(3) }
func set(_ m: CGDisplayMode, _ o: CGConfigureOption) -> Int32 { var c: CGDisplayConfigRef?; CGBeginDisplayConfiguration(&c); CGConfigureDisplayWithDisplayMode(c, d, m, nil); return CGCompleteDisplayConfiguration(c, o).rawValue }
if a.count > 3 && a[3] == "keep" { print("kept \(w)x\(h):", set(m, .permanently)); exit(0) }
let secs = a.count > 3 ? Double(a[3]) ?? 15 : 15
print("trying \(w)x\(h) (backing \(m.pixelWidth)x\(m.pixelHeight)) for \(Int(secs)) s:", set(m, .forSession)); fflush(stdout)
Thread.sleep(forTimeInterval: secs)
print("back to \(cur.width)x\(cur.height):", set(cur, .forSession))
