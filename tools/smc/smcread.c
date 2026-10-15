// smcread KEY...: read AppleSMC keys (prints type and decoded value)
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
typedef struct { char major, minor, build, reserved[1]; uint16_t release; } V;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } P;
typedef struct { uint32_t dataSize, dataType; char dataAttributes; } KI;
typedef struct { uint32_t key; V vers; P pLimitData; KI keyInfo; char result, status, data8; uint32_t data32; unsigned char bytes[32]; } D;
static uint32_t k4(const char *s) { return (uint32_t)s[0]<<24 | (uint32_t)s[1]<<16 | (uint32_t)s[2]<<8 | (uint32_t)s[3]; }
int main(int argc, char **argv) {
    io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC")); io_connect_t c;
    if (!s || IOServiceOpen(s, mach_task_self(), 0, &c)) { puts("no AppleSMC"); return 1; }
    for (int i = 1; i < argc; i++) {
        D in = {0}, out = {0}; size_t sz = sizeof out;
        in.key = k4(argv[i]); in.data8 = 9;   // key info
        if (IOConnectCallStructMethod(c, 2, &in, sizeof in, &out, &sz) || out.result) { printf("%s: absent\n", argv[i]); continue; }
        KI ki = out.keyInfo; memset(&in, 0, sizeof in); in.key = k4(argv[i]); in.keyInfo.dataSize = ki.dataSize; in.data8 = 5; sz = sizeof out;
        memset(&out, 0, sizeof out);
        if (IOConnectCallStructMethod(c, 2, &in, sizeof in, &out, &sz) || out.result) { printf("%s: read error %d\n", argv[i], out.result); continue; }
        char t[5] = { ki.dataType>>24, ki.dataType>>16, ki.dataType>>8, ki.dataType, 0 };
        double v = 0;
        if (!strcmp(t, "sp78")) v = (int16_t)(out.bytes[0]<<8 | out.bytes[1]) / 256.0;
        else if (!strcmp(t, "flt ")) { float f; memcpy(&f, out.bytes, 4); v = f; }
        else if (!strcmp(t, "ui8 ")) v = out.bytes[0];
        else if (!strcmp(t, "ui16")) v = out.bytes[0]<<8 | out.bytes[1];
        else if (!strcmp(t, "fpe2")) v = (out.bytes[0]<<8 | out.bytes[1]) / 4.0;
        printf("%s [%s] = %.2f\n", argv[i], t, v);
    }
    return 0;
}
