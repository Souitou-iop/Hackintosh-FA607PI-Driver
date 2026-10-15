// fps: a 1920x1080 CAMetalLayer window that clears to a new colour every frame (issue #196's test), for N seconds.
// Prints app frames/s and on-screen presents/s (debug.nvaccel_iop_flips delta).
import AppKit
import Metal
import QuartzCore
func flips() -> Int64 { var v: Int64 = 0; var n = MemoryLayout<Int64>.size; sysctlbyname("debug.nvaccel_iop_flips", &v, &n, nil, 0); return v }
let secs = Double(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "8") ?? 8
let app = NSApplication.shared; app.setActivationPolicy(.regular)
let dev = MTLCreateSystemDefaultDevice()!; let q = dev.makeCommandQueue()!
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1920, height: 1080), styleMask: [.titled], backing: .buffered, defer: false)
let layer = CAMetalLayer(); layer.device = dev; layer.pixelFormat = .bgra8Unorm; layer.displaySyncEnabled = true
let v = NSView(frame: win.contentView!.bounds); v.wantsLayer = true; v.layer = layer; win.contentView = v
layer.drawableSize = CGSize(width: 1920 * win.backingScaleFactor, height: 1080 * win.backingScaleFactor)
win.center(); win.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
DispatchQueue.global().async {
    Thread.sleep(forTimeInterval: 1.0)
    var frames = 0; let f0 = flips(); let t0 = CACurrentMediaTime()
    while CACurrentMediaTime() - t0 < secs {
        autoreleasepool {
            guard let d = layer.nextDrawable() else { return }
            let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = d.texture
            rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
            let h = Double(frames % 120) / 120.0
            rp.colorAttachments[0].clearColor = MTLClearColor(red: h, green: 1 - h, blue: 0.5, alpha: 1)
            let cb = q.makeCommandBuffer()!; cb.makeRenderCommandEncoder(descriptor: rp)!.endEncoding()
            cb.present(d); cb.commit(); frames += 1
        }
    }
    let dt = CACurrentMediaTime() - t0
    print(String(format: "app %.1f frames/s, on screen %.1f presents/s over %.1f s", Double(frames) / dt, Double(flips() - f0) / dt, dt))
    exit(0)
}
app.run()
