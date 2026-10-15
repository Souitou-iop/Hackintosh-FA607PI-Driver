// AACELDOff: AirPods are silent on Intel Bluetooth (external-dongle mode) because bluetoothd picks Apple's vendor
// AAC-ELD codec (AVDTP_CODEC_APPLE_AACELD 0x80ff); SBC/AAC headphones play fine. bluetoothd skips AAC-ELD when its
// internal debug setting A2DP/DisableAACELD is true, but that setting is not read on customer builds. This patches the
// codec choice in bluetoothd's code page as it is validated (same mechanism as BlueToolFixup / BTLEFix):
//   macOS 15.8.1 (24H32) at 0x1004144d6: movb -0x42(%rbp),%r15b ; testb $1,%r15b ; jne +0x2f      -> jmp +0x2f
//   macOS 26.7.1 (25G241) at 0x1004815a1: movb -0x42(%rbp),%r15b ; testb %r15b,%r15b ; jne +0x2f -> jmp +0x2f
// (always "AAC-ELD disabled"). Boot-arg -aaceldoff_off disables the plugin.
//
// 1.1.0 also answers AppleHDA's resource requests on macOS 26 (from the friend's BTLEFix 1.0.6 part 5): 26 removed
// AppleHDA from the OS; put back in /Library/Apple/System/Library/Extensions and loaded from the auxiliary kernel
// collection, AppleHDADriver::startAction asks OSKextRequestResource for layoutN.xml.zlib / Platforms.xml.zlib and waits
// for ever (kernelmanagerd: "Cannot insert Kext com.apple.driver.AppleHDA ... into a restricted lookup table"). We read
// the file from the kext bundle and call the callback (AppleALC routes it and substitutes its own layout/platform data).
#include <Headers/plugin_start.hpp>
#include <Headers/kern_api.hpp>
#include <Headers/kern_util.hpp>
#include <Headers/kern_file.hpp>
#include <libkern/OSKextLib.h>
#include <sys/vnode.h>

extern "C" void kprintf(const char *fmt, ...);
#define alog(fmt, ...) do { kprintf("AACELDOff: " fmt "\n", ##__VA_ARGS__); IOLog("AACELDOff: " fmt "\n", ##__VA_ARGS__); } while (0)

static const uint8_t kFind15[] = { 0xe8, 0x3b, 0x09, 0x3d, 0x00, 0x44, 0x8a, 0x7d, 0xbe, 0x41, 0xf6, 0xc7, 0x01, 0x75, 0x2f,
                                   0x80, 0xbb, 0x58, 0x01, 0x00, 0x00, 0x00, 0x74, 0x26, 0x48, 0x89, 0xdf, 0xbe, 0xff, 0x00, 0x00, 0x00 };
static const uint8_t kRepl15[] = { 0xe8, 0x3b, 0x09, 0x3d, 0x00, 0x44, 0x8a, 0x7d, 0xbe, 0x41, 0xf6, 0xc7, 0x01, 0xeb, 0x2f,
                                   0x80, 0xbb, 0x58, 0x01, 0x00, 0x00, 0x00, 0x74, 0x26, 0x48, 0x89, 0xdf, 0xbe, 0xff, 0x00, 0x00, 0x00 };
static const uint8_t kFind26[] = { 0x44, 0x8a, 0x7d, 0xbe, 0x45, 0x84, 0xff, 0x75, 0x2f, 0x80, 0xbb, 0x58, 0x01, 0x00, 0x00, 0x00,
                                   0x74, 0x26, 0x48, 0x89, 0xdf, 0xbe, 0xff, 0x00, 0x00, 0x00 };
static const uint8_t kRepl26[] = { 0x44, 0x8a, 0x7d, 0xbe, 0x45, 0x84, 0xff, 0xeb, 0x2f, 0x80, 0xbb, 0x58, 0x01, 0x00, 0x00, 0x00,
                                   0x74, 0x26, 0x48, 0x89, 0xdf, 0xbe, 0xff, 0x00, 0x00, 0x00 };

static mach_vm_address_t orgValidate {};
static bool reported;

static void patchedValidatePage(vnode_t vp, memory_object_t pager, memory_object_offset_t off, const void *data,
                                int *validated, int *tainted, int *nx) {
	FunctionCast(patchedValidatePage, orgValidate)(vp, pager, off, data, validated, tainted, nx);
	char path[PATH_MAX]; int len = PATH_MAX;
	if (vn_getpath(vp, path, &len) == 0 && UNLIKELY(strcmp(path, "/usr/sbin/bluetoothd") == 0)) {
		bool hit = getKernelVersion() >= KernelVersion::Tahoe
			? KernelPatcher::findAndReplace(const_cast<void *>(data), PAGE_SIZE, kFind26, sizeof kFind26, kRepl26, sizeof kRepl26)
			: KernelPatcher::findAndReplace(const_cast<void *>(data), PAGE_SIZE, kFind15, sizeof kFind15, kRepl15, sizeof kRepl15);
		if (hit && !reported) {
			reported = true;
			alog("bluetoothd A2DP codec choice patched (AAC-ELD skipped)");
		}
	}
}

// ---- AppleHDA resource requests (macOS 26) ----
static mach_vm_address_t orgRequestResource {};
static const char *kHdaDirs[] {
	"/Library/Apple/System/Library/Extensions/AppleHDA.kext/Contents/Resources/",
	"/Library/Extensions/AppleHDA.kext/Contents/Resources/",
};

static bool hdaResourceNameOk(const char *n) {
	if (!n || !n[0] || strlen(n) > 40) return false;
	for (const char *c = n; *c; c++) {
		if (*c == '/' || *c == '\\' || (*c == '.' && c[1] == '.')) return false;
	}
	return strncmp(n, "layout", 6) == 0 || strncmp(n, "Platforms", 9) == 0;
}

static OSReturn patchedRequestResource(const char *kextId, const char *name, OSKextRequestResourceCallback cb, void *ctx,
                                       OSKextRequestTag *tagOut) {
	if (kextId && cb && strcmp(kextId, "com.apple.driver.AppleHDA") == 0 && hdaResourceNameOk(name)) {
		uint8_t *buf = nullptr;
		size_t size = 0;
		char path[256];
		for (size_t i = 0; i < arrsize(kHdaDirs) && !buf; i++) {
			snprintf(path, sizeof(path), "%s%s", kHdaDirs[i], name);
			buf = FileIO::readFileToBuffer(path, size);
		}
		alog("AppleHDA resource %s: %s (%lu bytes)", name, buf ? "served from the bundle" : "not found", (unsigned long)size);
		if (tagOut) *tagOut = kOSKextRequestTagInvalid;
		if (buf) cb(kOSKextRequestTagInvalid, kOSReturnSuccess, buf, (uint32_t)size, ctx);
		else cb(kOSKextRequestTagInvalid, kOSKextReturnNotFound, nullptr, 0, ctx);
		if (buf) Buffer::deleter(buf);
		return kOSReturnSuccess;
	}
	return FunctionCast(patchedRequestResource, orgRequestResource)(kextId, name, cb, ctx, tagOut);
}

static void pluginStart() {
	alog("start");
	lilu.onPatcherLoadForce([](void *, KernelPatcher &patcher) {
		KernelPatcher::RouteRequest r("_cs_validate_page", patchedValidatePage, orgValidate);
		if (!patcher.routeMultipleLong(KernelPatcher::KernelID, &r, 1)) alog("failed to route cs_validate_page");
		patcher.clearError();
		if (getKernelVersion() >= KernelVersion::Tahoe) {
			KernelPatcher::RouteRequest rr("__ZN6OSKext15requestResourceEPKcS1_PFvjiPKvjPvES4_Pj", patchedRequestResource, orgRequestResource);
			if (!patcher.routeMultipleLong(KernelPatcher::KernelID, &rr, 1)) alog("failed to route OSKext::requestResource");
			else alog("routed OSKext::requestResource (AppleHDA resources)");
			patcher.clearError();
		}
	});
}

static const char *bootargOff[] { "-aaceldoff_off" };
static const char *bootargDebug[] { "-aaceldoffdbg" };
static const char *bootargBeta[] { "-aaceldoffbeta" };

PluginConfiguration ADDPR(config) {
	xStringify(PRODUCT_NAME),
	parseModuleVersion(xStringify(MODULE_VERSION)),
	LiluAPI::AllowNormal | LiluAPI::AllowSafeMode,
	bootargOff, arrsize(bootargOff),
	bootargDebug, arrsize(bootargDebug),
	bootargBeta, arrsize(bootargBeta),
	KernelVersion::Sequoia,
	KernelVersion::Tahoe,
	pluginStart
};
