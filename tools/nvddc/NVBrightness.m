// NVBrightness: brightness keys + menu-bar slider for an external monitor on the NullMoth NVIDIA driver (DDC/CI via nvddc).
// Keys are taken over only while the mouse is on the external display; otherwise they pass through (built-in panel).
// Fn brightness keys: NX_KEYTYPE_BRIGHTNESS_UP/DOWN or F14/F15. Option+Shift = fine steps.
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>
#include <IOKit/hidsystem/ev_keymap.h>
#include "nvddc.h"

@interface OSDManager : NSObject
+ (instancetype)sharedManager;
- (void)showImage:(long long)img onDisplayID:(CGDirectDisplayID)d priority:(unsigned)p msecUntilFade:(unsigned)ms filledChunks:(unsigned)f totalChunks:(unsigned)t locked:(BOOL)l;
@end

static dispatch_queue_t gQ;
static int gCur = -1, gMax = 100, gReady;
static CFMachPortRef gTap;
static NSSlider *gSlider;
static NSStatusItem *gItem;

static CGDirectDisplayID externalDisplay(void) {
    CGDirectDisplayID ids[8]; uint32_t n = 0; CGGetOnlineDisplayList(8, ids, &n);
    for (uint32_t i = 0; i < n; i++) if (!CGDisplayIsBuiltin(ids[i]) && CGDisplayIsActive(ids[i])) return ids[i];
    return 0;
}
static BOOL mouseOnExternal(void) {
    CGDirectDisplayID ext = externalDisplay(); if (!ext) return NO;
    CGEventRef e = CGEventCreate(NULL); CGPoint p = CGEventGetLocation(e); CFRelease(e);
    CGDirectDisplayID d = 0; uint32_t n = 0; CGGetDisplaysWithPoint(p, 1, &d, &n);
    return n && d == ext;
}
static int ensure(void) {   // on gQ
    if (gReady) return 0;
    if (nvddc_open()) return -1;
    int c, m; if (nvddc_get(&c, &m)) { nvddc_close(); return -1; }
    gCur = c; gMax = m > 0 ? m : 100; gReady = 1; return 0;
}
static void showOSD(int v) {
    CGDirectDisplayID ext = externalDisplay(); if (!ext) return;
    static Class osd; if (!osd) { dlopen("/System/Library/PrivateFrameworks/OSD.framework/OSD", RTLD_LAZY); osd = NSClassFromString(@"OSDManager"); }
    unsigned chunks = (unsigned)lround((double)v / gMax * 64.0);
    [[osd sharedManager] showImage:1 onDisplayID:ext priority:0x1f4 msecUntilFade:1500 filledChunks:chunks totalChunks:64 locked:NO];
}
static void syncSlider(void) { dispatch_async(dispatch_get_main_queue(), ^{ gSlider.maxValue = gMax; gSlider.doubleValue = gCur; }); }
static void setValue(int v, BOOL osd) {
    dispatch_async(gQ, ^{
        if (ensure()) return;
        int x = v < 0 ? 0 : v > gMax ? gMax : v;
        if (nvddc_set(x)) { nvddc_close(); gReady = 0; if (ensure() || nvddc_set(x)) return; }   // reconnect once (sleep/replug)
        gCur = x; syncSlider();
        if (osd) dispatch_async(dispatch_get_main_queue(), ^{ showOSD(x); });
    });
}
static void step(int dir, BOOL fine) {
    dispatch_async(gQ, ^{
        if (ensure()) return;
        int s = fine ? (gMax + 63) / 64 : (gMax + 15) / 16;
        setValue(gCur + dir * s, YES);
    });
}

static CGEventRef tapCB(CGEventTapProxy proxy, CGEventType type, CGEventRef ev, void *ctx) {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) { CGEventTapEnable(gTap, true); return ev; }
    int dir = 0; BOOL fine = NO;
    if (type == (CGEventType)NSEventTypeSystemDefined) {
        NSEvent *e = [NSEvent eventWithCGEvent:ev];
        if (e.subtype != 8) return ev;
        long d1 = e.data1; int key = (int)((d1 & 0xFFFF0000) >> 16), down = ((d1 & 0xFF00) >> 8) == 0xA;
        if (key != NX_KEYTYPE_BRIGHTNESS_UP && key != NX_KEYTYPE_BRIGHTNESS_DOWN) return ev;
        if (!mouseOnExternal()) return ev;
        if (down) { dir = key == NX_KEYTYPE_BRIGHTNESS_UP ? 1 : -1; fine = (e.modifierFlags & (NSEventModifierFlagOption | NSEventModifierFlagShift)) == (NSEventModifierFlagOption | NSEventModifierFlagShift); }
    } else if (type == kCGEventKeyDown || type == kCGEventKeyUp) {
        int64_t kc = CGEventGetIntegerValueField(ev, kCGKeyboardEventKeycode);
        if (kc != 107 && kc != 113) return ev;   // F14 / F15
        if (!mouseOnExternal()) return ev;
        if (type == kCGEventKeyDown) { dir = kc == 113 ? 1 : -1; CGEventFlags f = CGEventGetFlags(ev); fine = (f & kCGEventFlagMaskAlternate) && (f & kCGEventFlagMaskShift); }
    } else return ev;
    if (dir) step(dir, fine);
    return NULL;   // swallow (also the key-up)
}

@interface App : NSObject <NSApplicationDelegate, NSMenuDelegate>
@end
@implementation App
- (void)sliderMoved:(NSSlider *)s { setValue((int)lround(s.doubleValue), NO); }
- (void)menuWillOpen:(NSMenu *)m { dispatch_async(gQ, ^{ if (!ensure()) { int c, mx; if (!nvddc_get(&c, &mx)) { gCur = c; gMax = mx; } syncSlider(); } }); }
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    gQ = dispatch_queue_create("nvddc", DISPATCH_QUEUE_SERIAL);
    gItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    gItem.button.image = [NSImage imageWithSystemSymbolName:@"sun.max" accessibilityDescription:@"External brightness"];
    NSMenu *m = [NSMenu new]; m.delegate = self;
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 34)];
    gSlider = [NSSlider sliderWithValue:50 minValue:0 maxValue:100 target:self action:@selector(sliderMoved:)];
    gSlider.frame = NSMakeRect(14, 6, 192, 22); gSlider.continuous = YES; [v addSubview:gSlider];
    NSMenuItem *si = [NSMenuItem new]; si.view = v;
    [m addItemWithTitle:@"External display brightness" action:nil keyEquivalent:@""]; [m addItem:si];
    [m addItem:NSMenuItem.separatorItem];
    [m addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@""];
    gItem.menu = m;
    NSDictionary *o = @{ (__bridge id)kAXTrustedCheckOptionPrompt: @YES };
    if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)o)) NSLog(@"NVBrightness: grant Accessibility, then relaunch");
    CGEventMask mask = (1ull << NSEventTypeSystemDefined) | CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp);
    gTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask, tapCB, NULL);
    if (gTap) {
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(NULL, gTap, 0), kCFRunLoopCommonModes);
        CGEventTapEnable(gTap, true);
    } else NSLog(@"NVBrightness: no event tap (Accessibility not granted) - slider only");
    dispatch_async(gQ, ^{ if (!ensure()) syncSlider(); else NSLog(@"NVBrightness: no external DDC display yet"); });
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidWakeNotification object:nil queue:nil usingBlock:^(NSNotification *x) {
        dispatch_async(gQ, ^{ if (gReady) { nvddc_close(); gReady = 0; } });
    }];
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *a = NSApplication.sharedApplication;
        a.activationPolicy = NSApplicationActivationPolicyAccessory;
        App *d = [App new]; a.delegate = d; [a run];
    }
    return 0;
}
