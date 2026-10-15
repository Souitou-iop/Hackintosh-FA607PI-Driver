// wswtest: pose as WindowServer and drive -commitAndWaitUntilSubmitted (the swap path of #196).
// argv[1] = frames. Prints how many frames came back already completed (CPU-wait fallback) vs only submitted.
#import <Metal/Metal.h>
#import <objc/message.h>
#include <stdlib.h>
#include <stdio.h>
int main(int argc, char **argv) { @autoreleasepool {
    setprogname("WindowServer");
    int frames = argc > 1 ? atoi(argv[1]) : 200;
    id<MTLDevice> d = MTLCreateSystemDefaultDevice();
    if (!d) { puts("no device"); return 1; }
    id<MTLCommandQueue> q = [d newCommandQueue];
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1920 height:1080 mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead; td.storageMode = MTLStorageModePrivate;
    id<MTLTexture> t = [d newTextureWithDescriptor:td];
    int completed = 0, submitted = 0, errors = 0; double worst = 0, sum = 0;
    for (int i = 0; i < frames; i++) { @autoreleasepool {
        id<MTLCommandBuffer> cb = [q commandBuffer];
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = t; rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore; rp.colorAttachments[0].clearColor = MTLClearColorMake((i & 1), 0.5, 0.2, 1);
        [[cb renderCommandEncoderWithDescriptor:rp] endEncoding];
        uint64_t t0 = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
        BOOL ok = ((BOOL(*)(id, SEL))objc_msgSend)(cb, sel_registerName("commitAndWaitUntilSubmitted"));
        double ms = (clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) - t0) / 1e6; sum += ms; if (ms > worst) worst = ms;
        MTLCommandBufferStatus st = cb.status;
        if (!ok || st == MTLCommandBufferStatusError) errors++;
        else if (st == MTLCommandBufferStatusCompleted) completed++; else submitted++;
        [cb waitUntilCompleted];
    } }
    printf("frames %d: returned completed %d, only submitted %d, errors %d; call %.3f ms avg, %.3f ms worst\n", frames, completed, submitted, errors, sum / frames, worst);
    return errors ? 1 : 0;
} }
