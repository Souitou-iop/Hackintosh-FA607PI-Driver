// vimptest: re-wrap the same IOSurface as a texture N times (Core Animation's flatten cache during a desktop switch).
// Each round: wrap -> clear to value i on the GPU -> drop; wrap again -> blit to a buffer -> check; CPU lock -> check.
// Prints wrap cost and whether the plugin's VRAM import cache let go of the surface after idling.
#import <Metal/Metal.h>
#import <IOSurface/IOSurface.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) { @autoreleasepool {
    int n = argc > 1 ? atoi(argv[1]) : 300; const int W = 1920, H = 1080;
    id<MTLDevice> d = MTLCreateSystemDefaultDevice(); id<MTLCommandQueue> q = [d newCommandQueue];
    NSDictionary *p = @{ (id)kIOSurfaceWidth: @(W), (id)kIOSurfaceHeight: @(H), (id)kIOSurfaceBytesPerElement: @4,
                         (id)kIOSurfaceBytesPerRow: @(W * 4), (id)kIOSurfacePixelFormat: @(0x42475241) };
    IOSurfaceRef s = IOSurfaceCreate((__bridge CFDictionaryRef)p);
    const CFIndex rc0 = CFGetRetainCount(s);
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:W height:H mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead; td.storageMode = MTLStorageModeShared;
    id<MTLBuffer> rb = [d newBufferWithLength:(NSUInteger)W * H * 4 options:MTLResourceStorageModeShared];
    int bad = 0, badcpu = 0; double wrapNs = 0;
    for (int i = 0; i < n; i++) { @autoreleasepool {
        const unsigned v = (unsigned)(i % 250) + 3;
        uint64_t t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        id<MTLTexture> t = [d newTextureWithDescriptor:td iosurface:s plane:0];
        wrapNs += clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0;
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = t; rp.colorAttachments[0].loadAction = MTLLoadActionClear; rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(v / 255.0, 0, 0, 1);
        id<MTLCommandBuffer> cb = [q commandBuffer]; [[cb renderCommandEncoderWithDescriptor:rp] endEncoding]; [cb commit]; [cb waitUntilCompleted];
        t = nil;
        t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        id<MTLTexture> t2 = [d newTextureWithDescriptor:td iosurface:s plane:0];
        wrapNs += clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0;
        cb = [q commandBuffer]; id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
        [bl copyFromTexture:t2 sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(W, H, 1)
                   toBuffer:rb destinationOffset:0 destinationBytesPerRow:W * 4 destinationBytesPerImage:(NSUInteger)W * H * 4];
        [bl endEncoding]; [cb commit]; [cb waitUntilCompleted];
        const uint8_t *px = (const uint8_t *)rb.contents;   // BGRA: red is byte 2
        if (px[2] != v || px[((size_t)H / 2 * W + W / 2) * 4 + 2] != v || px[((size_t)W * H - 1) * 4 + 2] != v) bad++;
        t2 = nil;
        if (i % 10 == 0) {
            IOSurfaceLock(s, kIOSurfaceLockReadOnly, NULL);
            const uint8_t *c = (const uint8_t *)IOSurfaceGetBaseAddress(s);
            if (c[2] != v || c[((size_t)H / 2 * W + W / 2) * 4 + 2] != v) badcpu++;
            IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL);
        }
    } }
    const CFIndex rcBusy = CFGetRetainCount(s);
    usleep(1500000);
    const CFIndex rcIdle = CFGetRetainCount(s);
    printf("rounds %d: GPU readback wrong %d, CPU lock wrong %d | wrap %.1f us avg | surface retains: start %ld, after loop %ld, after 1.5 s idle %ld\n",
           n, bad, badcpu, wrapNs / (2.0 * n) / 1000.0, (long)rc0, (long)rcBusy, (long)rcIdle);
    int fail = bad || badcpu || rcIdle != rc0;
    puts(fail ? "FAIL" : "PASS"); fflush(stdout);
    CFRelease(s); return fail;
} }
