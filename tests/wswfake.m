// wswfake: the #196 plugin path against a simulated NVAccel (test build NVMTLDriver.196hook resolves nvmtl_wsw_testhook).
// Each frame fills a shared buffer with its index on the GPU, then -commitAndWaitUntilSubmitted. The fake kernel checks:
// every PEND gets exactly one DONE, DONE never precedes PEND, and at DONE the frame's GPU write is already visible.
#import <Metal/Metal.h>
#import <objc/message.h>
#include <stdatomic.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#define MAXF 4096
static _Atomic int pend[MAXF + 2], done[MAXF + 2];
static _Atomic int probes, bad, early, dupdone;
static volatile uint32_t *gBuf;
__attribute__((visibility("default"))) uint32_t nvmtl_wsw_testhook(uint32_t op, uint32_t seq) {
    if (op == 1) { atomic_fetch_add(&probes, 1); return 0x4e565731u; }
    if (!seq || seq > MAXF) { atomic_fetch_add(&bad, 1); return 0x80000002u; }
    if (op == 2) { if (atomic_fetch_add(&pend[seq], 1)) atomic_fetch_add(&bad, 1); return 0; }
    if (op == 3) {
        if (!atomic_load(&pend[seq])) atomic_fetch_add(&bad, 1);
        if (atomic_fetch_add(&done[seq], 1)) atomic_fetch_add(&dupdone, 1);
        // frame index = seq - 1; the buffer holds the newest finished frame's index + 1
        if (gBuf && gBuf[0] < seq) atomic_fetch_add(&early, 1);
        return 0;
    }
    atomic_fetch_add(&bad, 1); return 0x80000002u;
}
int main(int argc, char **argv) { @autoreleasepool {
    setprogname("WindowServer");
    int frames = argc > 1 ? atoi(argv[1]) : 600; if (frames > MAXF) frames = MAXF;
    id<MTLDevice> d = MTLCreateSystemDefaultDevice();
    id<MTLCommandQueue> q = [d newCommandQueue];
    id<MTLBuffer> b = [d newBufferWithLength:4096 options:MTLResourceStorageModeShared];
    gBuf = (volatile uint32_t *)b.contents; gBuf[0] = 0;
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:3840 height:2160 mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget; td.storageMode = MTLStorageModePrivate;
    id<MTLTexture> t = [d newTextureWithDescriptor:td];
    dispatch_semaphore_t inflight = dispatch_semaphore_create(3);
    int submittedOnly = 0, errors = 0; double sum = 0, worst = 0;
    for (int i = 0; i < frames; i++) { @autoreleasepool {
        dispatch_semaphore_wait(inflight, DISPATCH_TIME_FOREVER);
        id<MTLCommandBuffer> cb = [q commandBuffer];
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = t; rp.colorAttachments[0].loadAction = MTLLoadActionClear; rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        [[cb renderCommandEncoderWithDescriptor:rp] endEncoding];
        id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
        // value i+1 as little-endian bytes: fillBuffer writes one byte, so use a 4-byte copy from a staging buffer instead
        uint32_t v = (uint32_t)i + 1;
        id<MTLBuffer> src = [d newBufferWithBytes:&v length:4 options:MTLResourceStorageModeShared];
        [bl copyFromBuffer:src sourceOffset:0 toBuffer:b destinationOffset:0 size:4];
        [bl endEncoding];
        [cb addCompletedHandler:^(id<MTLCommandBuffer> c) { dispatch_semaphore_signal(inflight); }];
        uint64_t t0 = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
        BOOL ok = ((BOOL(*)(id, SEL))objc_msgSend)(cb, sel_registerName("commitAndWaitUntilSubmitted"));
        double ms = (clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) - t0) / 1e6; sum += ms; if (ms > worst) worst = ms;
        if (!ok) errors++;
        if (cb.status != MTLCommandBufferStatusCompleted) submittedOnly++;
    } }
    for (int i = 0; i < 3; i++) dispatch_semaphore_wait(inflight, DISPATCH_TIME_FOREVER);
    [[q commandBuffer] commit];
    usleep(200000);
    int missing = 0; for (int s = 1; s <= frames; s++) if (atomic_load(&pend[s]) != 1 || atomic_load(&done[s]) != 1) missing++;
    printf("frames %d probes %d | returned before completion %d | errors %d | pend/done mismatches %d dup DONE %d early DONE %d bad ops %d | call %.3f ms avg %.3f worst | buffer %u\n",
           frames, atomic_load(&probes), submittedOnly, errors, missing, atomic_load(&dupdone), atomic_load(&early), atomic_load(&bad), sum / frames, worst, gBuf[0]);
    int fail = errors || missing || atomic_load(&dupdone) || atomic_load(&early) || atomic_load(&bad) || !atomic_load(&probes);
    for (int i = 0; i < 3; i++) dispatch_semaphore_signal(inflight);
    puts(fail ? "FAIL" : "PASS"); fflush(stdout); return fail;
} }
