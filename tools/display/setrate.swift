// setrate <hz>: switch the main display to the same resolution at <hz> for this login session; prints the old Hz.
import CoreGraphics
import Foundation
let a = CommandLine.arguments
guard a.count >= 2, let hz = Double(a[1]) else { print("usage: setrate <hz>"); exit(2) }
let d = CGMainDisplayID(), cur = CGDisplayCopyDisplayMode(d)!
let opts = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
let all = CGDisplayCopyAllDisplayModes(d, opts) as? [CGDisplayMode] ?? []
if a.count > 2 && a[2] == "list" { for m in all where m.width == cur.width && m.height == cur.height { print(m.width, m.height, m.pixelWidth, m.pixelHeight, m.refreshRate) }; exit(0) }
guard let m = all.first(where: { $0.width == cur.width && $0.height == cur.height && $0.pixelWidth == cur.pixelWidth && abs($0.refreshRate - hz) < 1 })
else { print("no \(cur.width)x\(cur.height) mode at \(hz) Hz"); exit(3) }
var cfg: CGDisplayConfigRef?
CGBeginDisplayConfiguration(&cfg); CGConfigureDisplayWithDisplayMode(cfg, d, m, nil)
print("was \(cur.refreshRate) Hz -> \(m.refreshRate) Hz:", CGCompleteDisplayConfiguration(cfg, a.count > 2 && a[2] == "perm" ? .permanently : .forSession).rawValue)
