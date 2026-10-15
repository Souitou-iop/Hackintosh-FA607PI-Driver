// dm -- current mode of every online display
import CoreGraphics
var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
CGGetOnlineDisplayList(8, &ids, &n)
for d in ids.prefix(Int(n)) { if let m = CGDisplayCopyDisplayMode(d) {
  print(String(format: "%u %@ main %d: %dx%d backing %dx%d @ %.0f Hz", d, CGDisplayIsBuiltin(d) != 0 ? "built-in" : "external", CGDisplayIsMain(d), m.width, m.height, m.pixelWidth, m.pixelHeight, m.refreshRate)) } else { print(d, "off") } }
