// nvddc — DDC/CI (monitor brightness etc.) for external displays on the NullMoth NVIDIA driver, from user space.
// Talks to NVRM's user client (the same RM escapes NVK uses) and sends DDC/CI over DP AUX-I2C or the HDMI DDC bus.
//   nvddc list                     displays, signal type
//   nvddc get [vcp]                read a VCP feature (default 0x10 = brightness): current/max
//   nvddc set <value> [vcp]        write a VCP feature
//   nvddc up|down [step]           brightness +/- step (default 6)
// Option -d <displayId hex> picks the display (default: the first connected non-embedded one).
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include "nvtypes.h"
#include "nvos.h"
#include "nvstatus.h"
#include "nv_escape.h"
#include "nv-ioctl.h"
#include "class/cl0000.h"
#include "class/cl0080.h"
#include "class/cl2080.h"
#include "class/cl0073.h"
#include "class/cl402c.h"
#include "ctrl/ctrl0000/ctrl0000gpu.h"
#include "ctrl/ctrl0073/ctrl0073system.h"
#include "ctrl/ctrl0073/ctrl0073dfp.h"
#include "ctrl/ctrl0073/ctrl0073dp.h"
#include "ctrl/ctrl0073/ctrl0073specific.h"
#include "ctrl/ctrl402c.h"

enum { SEL_ESC = 1, SEL_BINDFD = 3 };
static io_connect_t gConn; static int gFd = -1; static NvHandle hClient, hDevice = 0xdd000001, hSub = 0xdd000002, hDisp = 0xdd000003, hI2c = 0xdd000004;
static int verbose;

static int esc(uint32_t cmd, void *p, uint32_t size) {
    uint64_t in = cmd; size_t out = size;
    kern_return_t kr = IOConnectCallMethod(gConn, SEL_ESC, &in, 1, p, size, NULL, NULL, p, &out);
    if (kr && verbose) fprintf(stderr, "esc 0x%x -> 0x%x\n", cmd, kr);
    return kr ? -1 : 0;
}
static NvU32 rmAlloc(NvHandle parent, NvHandle *obj, NvU32 cls, void *params, NvU32 psize) {
    NVOS21_PARAMETERS p = { .hRoot = hClient, .hObjectParent = parent, .hObjectNew = *obj, .hClass = cls, .pAllocParms = params, .paramsSize = psize };
    if (esc(NV_ESC_RM_ALLOC, &p, sizeof p)) return NV_ERR_GENERIC;
    *obj = p.hObjectNew; return p.status;
}
static NvU32 rmCtrl(NvHandle obj, NvU32 cmd, void *params, NvU32 size) {
    NVOS54_PARAMETERS p = { .hClient = hClient, .hObject = obj, .cmd = cmd, .params = params, .paramsSize = size };
    if (esc(NV_ESC_RM_CONTROL, &p, sizeof p)) return NV_ERR_GENERIC;
    return p.status;
}
static void rmFree(NvHandle obj) { NVOS00_PARAMETERS p = { .hRoot = hClient, .hObjectParent = hClient, .hObjectOld = obj }; esc(NV_ESC_RM_FREE, &p, sizeof p); }

static int rmOpen(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("NVRM"));
    if (!svc) { fprintf(stderr, "no NVRM service\n"); return -1; }
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0 /* ctl */, &gConn); IOObjectRelease(svc);
    if (kr) { fprintf(stderr, "IOServiceOpen NVRM: 0x%x\n", kr); return -1; }
    int fd = gFd = open("/dev/null", O_RDONLY | O_CLOEXEC); uint64_t in = (uint64_t)fd;
    IOConnectCallScalarMethod(gConn, SEL_BINDFD, &in, 1, NULL, NULL);
    NvU32 st;
    hClient = 0;
    { NVOS21_PARAMETERS p = { .hClass = NV01_ROOT_CLIENT }; if (esc(NV_ESC_RM_ALLOC, &p, sizeof p) || p.status) { fprintf(stderr, "alloc client: 0x%x\n", p.status); return -1; } hClient = p.hObjectNew; }
    nv_ioctl_card_info_t ci[4]; memset(ci, 0, sizeof ci);
    if (esc(NV_ESC_CARD_INFO, ci, sizeof ci) || !ci[0].valid) { fprintf(stderr, "card info failed\n"); return -1; }
    NV0000_CTRL_GPU_GET_ID_INFO_V2_PARAMS id = { .gpuId = ci[0].gpu_id };
    if ((st = rmCtrl(hClient, NV0000_CTRL_CMD_GPU_GET_ID_INFO_V2, &id, sizeof id))) { fprintf(stderr, "GET_ID_INFO_V2: 0x%x\n", st); return -1; }
    NV0080_ALLOC_PARAMETERS a80 = { .deviceId = id.deviceInstance, .hClientShare = hClient };
    if ((st = rmAlloc(hClient, &hDevice, NV01_DEVICE_0, &a80, sizeof a80))) { fprintf(stderr, "alloc device: 0x%x\n", st); return -1; }
    NV2080_ALLOC_PARAMETERS a20 = { .subDeviceId = id.subDeviceInstance };
    if ((st = rmAlloc(hDevice, &hSub, NV20_SUBDEVICE_0, &a20, sizeof a20))) { fprintf(stderr, "alloc subdevice: 0x%x\n", st); return -1; }
    if ((st = rmAlloc(hDevice, &hDisp, NV04_DISPLAY_COMMON, NULL, 0))) { fprintf(stderr, "alloc display common: 0x%x\n", st); return -1; }
    return 0;
}
static void rmClose(void) { if (hClient) rmFree(hClient); }

typedef struct { NvU32 id, signal, edp; } Disp;
static int listDisplays(Disp *out, int max) {
    NV0073_CTRL_SYSTEM_GET_SUPPORTED_PARAMS sup = { 0 };
    if (rmCtrl(hDisp, NV0073_CTRL_CMD_SYSTEM_GET_SUPPORTED, &sup, sizeof sup)) return -1;
    NV0073_CTRL_SYSTEM_GET_CONNECT_STATE_PARAMS cs = { .displayMask = sup.displayMask,
        .flags = NV0073_CTRL_SYSTEM_GET_CONNECT_STATE_FLAGS_METHOD_CACHED };   // no new detection: what NVKMS last saw
    NvU32 st = rmCtrl(hDisp, NV0073_CTRL_CMD_SYSTEM_GET_CONNECT_STATE, &cs, sizeof cs);
    if (st) { fprintf(stderr, "GET_CONNECT_STATE: 0x%x\n", st); return -1; }
    if (verbose) { NV0073_CTRL_SYSTEM_GET_SUPPORTED_PARAMS sp = { 0 }; NvU32 s2 = rmCtrl(hDisp, NV0073_CTRL_CMD_SYSTEM_GET_SUPPORTED, &sp, sizeof sp);
                   fprintf(stderr, "connected mask 0x%x; supported 0x%x (st 0x%x)\n", cs.displayMask, sp.displayMask, s2); }
    int n = 0;
    for (int b = 0; b < 32 && n < max; b++) if (cs.displayMask & (1u << b)) {
        NV0073_CTRL_DFP_GET_INFO_PARAMS di = { .displayId = 1u << b };
        NvU32 s3 = rmCtrl(hDisp, NV0073_CTRL_CMD_DFP_GET_INFO, &di, sizeof di);
        if (verbose) fprintf(stderr, "display 0x%x DFP_GET_INFO st 0x%x flags 0x%x\n", 1u << b, s3, di.flags);
        if (s3) continue;
        out[n].id = 1u << b; out[n].signal = di.flags & 7; out[n].edp = (di.flags >> 15) & 1; n++;
    }
    return n;
}

// ---- I2C transport (7-bit address 0x37 = DDC/CI) ----
static Disp gD;
static NvU32 gPort = ~0u;
static int dpI2c(int read, const NvU8 *wbuf, NvU8 *rbuf, NvU32 len) {
    // one AUX transaction carries <= 16 bytes; MOT=1 keeps the I2C transaction open between chunks, then an address-only stop
    NvU32 done = 0;
    while (done < len) {
        NV0073_CTRL_DP_AUXCH_CTRL_PARAMS p = { .displayId = gD.id, .addr = 0x37, .retryTimeMs = 10 };
        NvU32 chunk = len - done > 16 ? 16 : len - done;
        p.cmd = (0u << 3) /* I2C */ | (1u << 2) /* MOT */ | (read ? 1u : 0u);
        p.size = chunk - 1;   // RM takes size-1 (AUX length field)
        if (!read) memcpy(p.data, wbuf + done, chunk);
        NvU32 st = rmCtrl(hDisp, NV0073_CTRL_CMD_DP_AUXCH_CTRL, &p, sizeof p);
        if (verbose) fprintf(stderr, "aux %s %u: st 0x%x reply %u size %u\n", read ? "rd" : "wr", chunk, st, p.replyType, p.size);
        if (st || p.replyType != NV0073_CTRL_DP_AUXCH_REPLYTYPE_ACK) return -1;
        if (read) { NvU32 got = p.size; if (got == 0 || got > chunk) return -1; memcpy(rbuf + done, p.data, got); done += got; }
        else done += chunk;
    }
    NV0073_CTRL_DP_AUXCH_CTRL_PARAMS s = { .displayId = gD.id, .addr = 0x37, .bAddrOnly = NV_TRUE, .retryTimeMs = 10 };
    s.cmd = read ? 1u : 0u;   // MOT=0: stop
    rmCtrl(hDisp, NV0073_CTRL_CMD_DP_AUXCH_CTRL, &s, sizeof s);
    return 0;
}
static int hdmiI2c(int read, const NvU8 *wbuf, NvU8 *rbuf, NvU32 len) {
    NV402C_CTRL_I2C_TRANSACTION_PARAMS p; memset(&p, 0, sizeof p);
    p.portId = (NvU8)gPort; p.flags = 0; p.deviceAddress = 0x37 << 1;
    p.transType = NV402C_CTRL_I2C_TRANSACTION_TYPE_I2C_BUFFER_RW;
    NvU8 buf[64]; if (!read) memcpy(buf, wbuf, len);
    p.transData.i2cBufferData.bWrite = read ? NV_FALSE : NV_TRUE;
    p.transData.i2cBufferData.messageLength = len;
    p.transData.i2cBufferData.pMessage = (NvP64)(uintptr_t)buf;
    NvU32 st = rmCtrl(hI2c, NV402C_CTRL_CMD_I2C_TRANSACTION, &p, sizeof p);
    if (verbose) fprintf(stderr, "i2c %s %u: st 0x%x\n", read ? "rd" : "wr", len, st);
    if (st) return -1;
    if (read) memcpy(rbuf, buf, len);
    return 0;
}
static int i2c(int read, const NvU8 *w, NvU8 *r, NvU32 len) {
    return gD.signal == NV0073_CTRL_DFP_FLAGS_SIGNAL_DISPLAYPORT ? dpI2c(read, w, r, len) : hdmiI2c(read, w, r, len);
}
static int ddcSetup(void) {
    if (gD.signal == NV0073_CTRL_DFP_FLAGS_SIGNAL_DISPLAYPORT) return 0;
    NV0073_CTRL_SPECIFIC_GET_I2C_PORTID_PARAMS pp = { .displayId = gD.id };
    NvU32 st = rmCtrl(hDisp, NV0073_CTRL_CMD_SPECIFIC_GET_I2C_PORTID, &pp, sizeof pp);
    if (st) { fprintf(stderr, "GET_I2C_PORTID: 0x%x\n", st); return -1; }
    gPort = pp.ddcPortId - 1;   // RM returns 1-based ids, 0 = none
    if (verbose) fprintf(stderr, "ddc port %u (comm %u)\n", pp.ddcPortId, pp.commPortId);
    if (pp.ddcPortId == 0) { fprintf(stderr, "display has no DDC port\n"); return -1; }
    if ((st = rmAlloc(hSub, &hI2c, NV40_I2C, NULL, 0))) { fprintf(stderr, "alloc NV40_I2C: 0x%x\n", st); return -1; }
    return 0;
}

// ---- DDC/CI ----
static int vcpGet(NvU8 vcp, int *cur, int *max) {
    NvU8 w[5] = { 0x51, 0x82, 0x01, vcp, 0 }; w[4] = 0x6e ^ w[0] ^ w[1] ^ w[2] ^ w[3];
    for (int attempt = 0; attempt < 3; attempt++) {
        if (i2c(0, w, NULL, sizeof w)) { usleep(50000); continue; }
        usleep(50000);
        NvU8 r[12] = { 0 };
        if (i2c(1, NULL, r, 11)) { usleep(50000); continue; }
        if (verbose) { for (int i = 0; i < 11; i++) fprintf(stderr, "%02x ", r[i]); fprintf(stderr, "\n"); }
        NvU8 x = 0x50; for (int i = 0; i < 10; i++) x ^= r[i];
        if (r[1] != 0x88 || r[2] != 0x02 || r[4] != vcp || x != r[10]) { usleep(50000); continue; }
        if (r[3] != 0) { fprintf(stderr, "monitor: VCP 0x%02x unsupported\n", vcp); return -1; }
        *max = r[6] << 8 | r[7]; *cur = r[8] << 8 | r[9]; return 0;
    }
    return -1;
}
static int vcpSet(NvU8 vcp, int v) {
    NvU8 w[7] = { 0x51, 0x84, 0x03, vcp, (NvU8)(v >> 8), (NvU8)v, 0 };
    w[6] = 0x6e ^ w[0] ^ w[1] ^ w[2] ^ w[3] ^ w[4] ^ w[5];
    for (int attempt = 0; attempt < 3; attempt++) { if (!i2c(0, w, NULL, sizeof w)) { usleep(50000); return 0; } usleep(50000); }
    return -1;
}

// ---- library API (NVBrightness.app) ----
void nvddc_close(void);
int nvddc_open(void) {
    if (rmOpen()) { nvddc_close(); return -1; }
    Disp ds[16]; int n = listDisplays(ds, 16), found = 0;
    for (int i = 0; i < n; i++) if (!ds[i].edp) { gD = ds[i]; found = 1; break; }
    if (!found || ddcSetup()) { nvddc_close(); return -1; }
    return 0;
}
void nvddc_close(void) { rmClose(); hClient = 0; if (gConn) { IOServiceClose(gConn); gConn = 0; } if (gFd >= 0) { close(gFd); gFd = -1; } }
int nvddc_get(int *cur, int *max) { return vcpGet(0x10, cur, max); }
int nvddc_set(int v) { return vcpSet(0x10, v); }

#ifndef NVDDC_LIB
int main(int argc, char **argv) {
    NvU32 want = 0; int a = 1;
    while (a < argc && argv[a][0] == '-') {
        if (!strcmp(argv[a], "-v")) verbose = 1;
        else if (!strcmp(argv[a], "-d") && a + 1 < argc) want = (NvU32)strtoul(argv[++a], NULL, 16);
        a++;
    }
    const char *cmd = a < argc ? argv[a++] : "list";
    if (rmOpen()) return 1;
    Disp ds[16]; int n = listDisplays(ds, 16);
    if (n < 0) { rmClose(); return 1; }
    static const char *sig[] = { "TMDS(HDMI/DVI)", "LVDS", "SDI", "DisplayPort", "DSI", "WRBK", "?", "?" };
    if (!strcmp(cmd, "list")) {
        for (int i = 0; i < n; i++) printf("display 0x%08x  %s%s\n", ds[i].id, sig[ds[i].signal], ds[i].edp ? " (embedded panel)" : "");
        rmClose(); return 0;
    }
    int found = 0;
    for (int i = 0; i < n; i++) if (want ? ds[i].id == want : !ds[i].edp) { gD = ds[i]; found = 1; break; }
    if (!found) { fprintf(stderr, "no external display found\n"); rmClose(); return 1; }
    if (ddcSetup()) { rmClose(); return 1; }
    int rc = 0, cur = 0, max = 0;
    if (!strcmp(cmd, "get")) {
        NvU8 vcp = a < argc ? (NvU8)strtoul(argv[a], NULL, 16) : 0x10;
        if (vcpGet(vcp, &cur, &max)) { fprintf(stderr, "DDC read failed\n"); rc = 1; } else printf("%d %d\n", cur, max);
    } else if (!strcmp(cmd, "set") && a < argc) {
        int v = atoi(argv[a]); NvU8 vcp = a + 1 < argc ? (NvU8)strtoul(argv[a + 1], NULL, 16) : 0x10;
        if (vcpSet(vcp, v)) { fprintf(stderr, "DDC write failed\n"); rc = 1; }
    } else if (!strcmp(cmd, "up") || !strcmp(cmd, "down")) {
        int step = a < argc ? atoi(argv[a]) : 6;
        if (vcpGet(0x10, &cur, &max)) { fprintf(stderr, "DDC read failed\n"); rc = 1; }
        else {
            int v = cur + (cmd[0] == 'u' ? step : -step); if (v < 0) v = 0; if (v > max) v = max;
            if (vcpSet(0x10, v)) { fprintf(stderr, "DDC write failed\n"); rc = 1; } else printf("%d %d\n", v, max);
        }
    } else { fprintf(stderr, "usage: nvddc [-v] [-d id] list|get [vcp]|set <v> [vcp]|up|down [step]\n"); rc = 2; }
    rmClose(); return rc;
}
#endif
