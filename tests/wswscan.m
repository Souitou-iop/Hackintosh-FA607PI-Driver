// wswscan: #196 with the SCANOUT op, against a simulated NVAccel (test plugin build with NVMTL_WSW_TESTHOOK).
// Pretends to be WindowServer. Two IOSurfaces: "fb" (the fake kernel says it is on a display) and "snap" (a Dock snapshot).
// Each round: a heavy frame into fb (must return before completion at least sometimes), then a snapshot into snap whose
// pixels are read by the CPU right after -commitAndWaitUntilSubmitted (must always be complete and correct).
#import <Metal/Metal.h>
#import <IOSurface/IOSurface.h>
#import <objc/message.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
static uint32_t gFbId;
static _Atomic int scanYes, scanNo, pends, dones, probes, bad;
__attribute__((visibility("default"))) uint32_t nvmtl_wsw_testhook(uint32_t op, uint32_t seq) {
    if (op == 1) { atomic_fetch_add(&probes, 1); return 0x4e565731u; }
    if (op == 2) { atomic_fetch_add(&pends, 1); return 0; }
    if (op == 3) { atomic_fetch_add(&dones, 1); return 0; }
    if (op == 4) { if (seq == gFbId) { atomic_fetch_add(&scanYes, 1); return 0x4e565731u; } atomic_fetch_add(&scanNo, 1); return 0x80000002u; }
    atomic_fetch_add(&bad, 1); return 0x80000002u;
}
static IOSurfaceRef mksurf(int w, int h) {
    return IOSurfaceCreate((__bridge CFDictionaryRef)@{ (id)kIOSurfaceWidth: @(w), (id)kIOSurfaceHeight: @(h), (id)kIOSurfaceBytesPerElement: @4,
                                                       (id)kIOSurfacePixelFormat: @('BGRA') });
}
static id<MTLTexture> wrap(id<MTLDevice> d, IOSurfaceRef s, int w, int h) {
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead; td.storageMode = MTLStorageModeManaged;
    return [d newTextureWithDescriptor:td iosurface:s plane:0];
}
static BOOL cws(id<MTLCommandBuffer> cb) { return ((BOOL(*)(id, SEL))objc_msgSend)(cb, sel_registerName("commitAndWaitUntilSubmitted")); }
int main(int argc, char **argv) { @autoreleasepool {
    setprogname("WindowServer");
    int rounds = argc > 1 ? atoi(argv[1]) : 200;
    id<MTLDevice> d = MTLCreateSystemDefaultDevice(); id<MTLCommandQueue> q = [d newCommandQueue];
    const int FW = 3840, FH = 2160, SW = 512, SH = 320;
    IOSurfaceRef fb = mksurf(FW, FH), snap = mksurf(SW, SH); gFbId = IOSurfaceGetID(fb);
    id<MTLTexture> fbt = wrap(d, fb, FW, FH);
    int fbEarly = 0, snapEarly = 0, snapWrong = 0;
    for (int i = 0; i < rounds; i++) { @autoreleasepool {
        // screen frame: several full-screen clears so the GPU work takes a while
        id<MTLCommandBuffer> cb = [q commandBuffer];
        for (int k = 0; k < 8; k++) {
            MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
            rp.colorAttachments[0].texture = fbt; rp.colorAttachments[0].loadAction = MTLLoadActionClear; rp.colorAttachments[0].storeAction = MTLStoreActionStore;
            rp.colorAttachments[0].clearColor = MTLClearColorMake(k / 8.0, 0, 0, 1);
            [[cb renderCommandEncoderWithDescriptor:rp] endEncoding];
        }
        cws(cb); if (cb.status != MTLCommandBufferStatusCompleted) fbEarly++;
        // snapshot: a fresh texture over the snapshot surface each time (WindowServer makes one per capture), cleared to a
        // colour that changes every round, then read on the CPU at once
        id<MTLTexture> st = wrap(d, snap, SW, SH);
        const double g = (double)((i * 37) % 251 + 2) / 255.0;
        id<MTLCommandBuffer> c2 = [q commandBuffer];
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = st; rp.colorAttachments[0].loadAction = MTLLoadActionClear; rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, g, 0, 1);
        [[c2 renderCommandEncoderWithDescriptor:rp] endEncoding];
        cws(c2); if (c2.status != MTLCommandBufferStatusCompleted) snapEarly++;
        IOSurfaceLock(snap, kIOSurfaceLockReadOnly, NULL);
        const uint8_t *px = IOSurfaceGetBaseAddress(snap); const size_t row = IOSurfaceGetBytesPerRow(snap);
        const uint8_t want = (uint8_t)(g * 255.0 + 0.5); int wrongPx = 0;
        for (int y = 0; y < SH; y += 31) for (int x = 0; x < SW; x += 29) { const uint8_t *p = px + y * row + x * 4; if (abs((int)p[1] - want) > 1 || p[3] != 255) wrongPx++; }
        IOSurfaceUnlock(snap, kIOSurfaceLockReadOnly, NULL);
        if (wrongPx) snapWrong++;
    } }
    [[q commandBuffer] commit]; usleep(200000);
    printf("rounds %d | screen frames returned before completion %d | snapshots returned before completion %d, read wrong %d | SCANOUT yes %d no %d | PEND %d DONE %d probes %d bad %d\n",
           rounds, fbEarly, snapEarly, snapWrong, atomic_load(&scanYes), atomic_load(&scanNo), atomic_load(&pends), atomic_load(&dones), atomic_load(&probes), atomic_load(&bad));
    int fail = snapEarly || snapWrong || !fbEarly || atomic_load(&pends) != atomic_load(&dones) || atomic_load(&bad);
    puts(fail ? "FAIL" : "PASS"); return fail;
} }
