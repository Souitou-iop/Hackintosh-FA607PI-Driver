// dispctl list | internal off|on [perm]   — turn the built-in panel off/on (SkyLight CGSConfigureDisplayEnabled).
// Default scope = this login session (comes back after logout/reboot); "perm" = permanent.
// Safety: "off" refuses unless another display is online.
import CoreGraphics
import Foundation
typealias EnableFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
guard let sym = dlsym(h, "SLSConfigureDisplayEnabled") ?? dlsym(h, "CGSConfigureDisplayEnabled") else { print("no SLSConfigureDisplayEnabled"); exit(1) }
let enable = unsafeBitCast(sym, to: EnableFn.self)
func online() -> [CGDirectDisplayID] { var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0; CGGetOnlineDisplayList(16, &ids, &n); return Array(ids.prefix(Int(n))) }
func active() -> [CGDirectDisplayID] { var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0; CGGetActiveDisplayList(16, &ids, &n); return Array(ids.prefix(Int(n))) }
let a = CommandLine.arguments
if a.count < 3 { for d in online() { print(d, CGDisplayIsBuiltin(d) != 0 ? "built-in" : "external", active().contains(d) ? "active" : "OFF") }; exit(0) }
guard a[1] == "internal", let on = ["on": true, "off": false][a[2]] else { print("usage: dispctl list | internal off|on [perm]"); exit(2) }
guard let b = online().first(where: { CGDisplayIsBuiltin($0) != 0 }) else { print("no built-in display online"); exit(1) }
if !on && !active().contains(where: { $0 != b && CGDisplayIsBuiltin($0) == 0 }) { print("refusing: no external display is active"); exit(1) }
var cfg: CGDisplayConfigRef?; CGBeginDisplayConfiguration(&cfg)
let e = enable(cfg, b, on)
let c = CGCompleteDisplayConfiguration(cfg, a.count > 3 && a[3] == "perm" ? .permanently : .forSession)
print("built-in \(b) -> \(on ? "on" : "off"): enable \(e.rawValue) complete \(c.rawValue)")
