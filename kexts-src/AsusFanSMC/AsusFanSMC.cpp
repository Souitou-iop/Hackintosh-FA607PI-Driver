// AsusFanSMC: ASUS laptop fans as Mac SMC fans (VirtualSMC plugin), so fan readers and fan-control apps work.
//
// Reads (every second, ATKD WMNB DSTS like Linux asus-wmi):
//   CPU fan 0x00110013, GPU fan 0x00110014 -> RPM = (value & 0xffff) * 100
// Publishes: FNum, F<n>Ac (actual), F<n>Mn / F<n>Mx, F<n>Tg (target, writable), F<n>Md (0 auto / 1 manual, writable),
//            TG0D = GPU temperature from sysctl debug.nvaccel_gpu_temp (NullMoth NVAccel), when present.
// Control: ASUS firmware takes no RPM, only an 8-point temperature -> duty curve per fan (DEVS 0x00110024 / 0x00110025).
//   Manual: every point of the curve becomes max(factory duty, target / F<n>Mx). The fan never runs slower than the
//           factory curve at the current temperature, so a low target cannot overheat the machine.
//   Auto (F<n>Md=0), shutdown, stop: the firmware's own curve comes back (thermal policy re-write, as asus-wmi does;
//           the factory curve is written back where there is no thermal policy device).
// Boot-arg -asusfanoff: the kext does nothing. -asusfanro: fans are read but not controllable (no Tg/Md keys).
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOTimerEventSource.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/RootDomain.h>
#include <libkern/c++/OSData.h>
#include <libkern/c++/OSNumber.h>
#include <sys/sysctl.h>
#include <stdatomic.h>
#include <stdarg.h>
#include <VirtualSMCSDK/kern_vsmcapi.hpp>

#define LOG(fmt, ...) do { IOLog("AsusFanSMC: " fmt "\n", ##__VA_ARGS__); diag(fmt, ##__VA_ARGS__); } while (0)
// Everything LOG says also goes to the "Diagnostics" property (ioreg -rc AsusFanSMC): early-boot kernel messages are
// gone from the buffer by the time anyone looks.
static char gDiag[4096]; static size_t gDiagLen;
static void diag(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void diag(const char *fmt, ...)
{
	if (gDiagLen + 2 >= sizeof gDiag) return;
	va_list ap; va_start(ap, fmt);
	int n = vsnprintf(gDiag + gDiagLen, sizeof gDiag - gDiagLen - 1, fmt, ap);
	va_end(ap);
	if (n < 0) return;
	gDiagLen += (size_t)n < sizeof gDiag - gDiagLen - 1 ? (size_t)n : sizeof gDiag - gDiagLen - 2;
	gDiag[gDiagLen++] = '\n'; gDiag[gDiagLen] = 0;
}

static constexpr uint32_t kDSTS = 0x53545344, kDEVS = 0x53564544, kUnsupported = 0xFFFFFFFE, kPresence = 0x00010000;
static constexpr uint32_t kDevFan[2]   = { 0x00110013, 0x00110014 };   // CPU, GPU
static constexpr uint32_t kDevCurve[2] = { 0x00110024, 0x00110025 };
static constexpr uint32_t kDevPolicy = 0x00120075;
static constexpr int kPoints = 8;
static constexpr uint32_t kPollMS = 1000, kReassertTicks = 30;
static constexpr double kMinRPM = 0, kDefaultMaxRPM = 6000;

struct Curve { uint8_t temp[kPoints], pct[kPoints]; };

class AsusFanSMC;

// F<n>Ac: the last RPM the poller read
class FanActual : public VirtualSMCValue {
	_Atomic(uint16_t) *rpm;
protected:
	SMC_RESULT readAccess() override {
		*reinterpret_cast<uint16_t *>(data) = VirtualSMCAPI::encodeIntFp(SmcKeyTypeFpe2, atomic_load_explicit(rpm, memory_order_acquire));
		return SmcSuccess;
	}
public:
	FanActual(_Atomic(uint16_t) *r) : rpm(r) {}
};
// F<n>Mx: grows when a fan is seen faster than the current maximum
class FanMax : public VirtualSMCValue {
	_Atomic(uint16_t) *top;
protected:
	SMC_RESULT readAccess() override {
		*reinterpret_cast<uint16_t *>(data) = VirtualSMCAPI::encodeIntFp(SmcKeyTypeFpe2, atomic_load_explicit(top, memory_order_acquire));
		return SmcSuccess;
	}
public:
	FanMax(_Atomic(uint16_t) *m) : top(m) {}
};
// F<n>Tg / F<n>Md: store what was written (read back unchanged) and wake the poller. No ACPI here: the SMC write path
// is not a place to call into the firmware.
class FanWritable : public VirtualSMCValue {
	_Atomic(uint32_t) *generation;
protected:
	SMC_RESULT update(const SMC_DATA *src) override {
		SMC_RESULT r = VirtualSMCValue::update(src);
		if (r == SmcSuccess) atomic_fetch_add_explicit(generation, 1, memory_order_acq_rel);
		return r;
	}
public:
	FanWritable(_Atomic(uint32_t) *g) : generation(g) {}
	uint16_t raw16() const { return *reinterpret_cast<const uint16_t *>(data); }
	uint8_t raw8() const { return data[0]; }
};
// TG0D: GPU temperature from the NVIDIA driver, as the poller last read it. SMC reads arrive in VirtualSMC's trap
// handler, where nothing may block: no sysctl and no ACPI here.
class GPUTemp : public VirtualSMCValue {
	_Atomic(uint16_t) *celsius;
protected:
	SMC_RESULT readAccess() override {
		*reinterpret_cast<uint16_t *>(data) = VirtualSMCAPI::encodeSp(SmcKeyTypeSp78, (double)atomic_load_explicit(celsius, memory_order_acquire));
		return SmcSuccess;
	}
public:
	GPUTemp(_Atomic(uint16_t) *c) : celsius(c) {}
};

class EXPORT AsusFanSMC : public IOService {
	OSDeclareDefaultStructors(AsusFanSMC)

	IOACPIPlatformDevice *atk {nullptr};
	IOACPIPlatformDevice *ec {nullptr};   // EC with a TACH method (AsusSMC's way): used when DSTS has no speed
	IONotifier *vsmcNotifier {nullptr};
	IONotifier *powerNotifier {nullptr};
	IOWorkLoop *workloop {nullptr};
	IOTimerEventSource *poller {nullptr};
	VirtualSMCAPI::Plugin vsmcPlugin { "AsusFanSMC", parseModuleVersion("1.0.0"), VirtualSMCAPI::Version };

	int fans {0};
	bool control {false}, policyDev {false};
	uint32_t policy {0};
	Curve factory[2] {};
	Curve written[2] {};
	bool manualApplied[2] {};
	uint32_t ticks {0}, seenGeneration {0};
	_Atomic(uint16_t) rpm[2];
	_Atomic(uint16_t) maxRpm[2];
	_Atomic(uint32_t) generation;
	_Atomic(uint16_t) gpuCelsius;
	FanWritable *target[2] {}, *mode[2] {};

	int64_t wmi(uint32_t method, uint32_t a0, uint32_t a1 = 0, uint32_t a2 = 0, uint32_t a3 = 0, uint32_t a4 = 0, OSObject **out = nullptr);
	bool readCurve(int fan, Curve &c);
	bool writeCurve(int fan, const Curve &c);
	void apply(bool force);
	void restoreAuto(int fan, const char *why);
	void poll();
	uint16_t readRPM(int fan, int64_t *rawOut = nullptr);
	static bool vsmcHandler(void *sensors, void *refCon, IOService *vsmc, IONotifier *notifier);
	static IOReturn powerHandler(void *target, void *refCon, UInt32 type, IOService *provider, void *arg, vm_size_t size);
public:
	IOService *probe(IOService *provider, SInt32 *score) override;
	bool start(IOService *provider) override;
	void stop(IOService *provider) override;
};
OSDefineMetaClassAndStructors(AsusFanSMC, IOService)

// WMNB(0, method, args): the result is an integer, or a buffer for the fan-curve DSTS (returned in *out)
int64_t AsusFanSMC::wmi(uint32_t method, uint32_t a0, uint32_t a1, uint32_t a2, uint32_t a3, uint32_t a4, OSObject **out)
{
	uint32_t args[6] = { a0, a1, a2, a3, a4, 0 };
	OSObject *p[3] = { OSNumber::withNumber(0ULL, 32), OSNumber::withNumber(method, 32), OSData::withBytes(args, sizeof args) };
	OSObject *res = nullptr;
	IOReturn r = (p[0] && p[1] && p[2]) ? atk->evaluateObject("WMNB", &res, p, 3) : kIOReturnNoMemory;
	for (auto o : p) if (o) o->release();
	if (r != kIOReturnSuccess) { if (res) res->release(); return -1; }
	int64_t v = -2;   // a buffer
	if (OSNumber *n = OSDynamicCast(OSNumber, res)) v = n->unsigned32BitValue();
	if (out) *out = res; else if (res) res->release();
	return v;
}

bool AsusFanSMC::readCurve(int fan, Curve &c)
{
	// the factory curve of the current thermal policy; asus-wmi swaps 1 and 2 for this call
	uint32_t m = policy == 1 ? 2 : policy == 2 ? 1 : 0;   // curves exist for modes 0-2 only (3 has none: balanced's)
	OSObject *res = nullptr;
	int64_t v = wmi(kDSTS, kDevCurve[fan], m, 0, 0, 0, &res);
	OSData *d = OSDynamicCast(OSData, res);
	bool ok = v == -2 && d && d->getLength() >= 2 * kPoints;
	if (ok) {
		const uint8_t *b = static_cast<const uint8_t *>(d->getBytesNoCopy());
		for (int i = 0; i < kPoints; i++) { c.temp[i] = b[i]; c.pct[i] = b[i + kPoints]; }
		for (int i = 0; i < kPoints; i++) if (c.pct[i] > 100 || (i && c.temp[i] < c.temp[i - 1])) ok = false;
	}
	if (res) res->release();
	return ok;
}

bool AsusFanSMC::writeCurve(int fan, const Curve &c)
{
	uint32_t a1 = 0, a2 = 0, a3 = 0, a4 = 0;
	for (int i = 0; i < kPoints / 2; i++) {
		a1 |= (uint32_t)c.temp[i] << (8 * i);  a2 |= (uint32_t)c.temp[i + 4] << (8 * i);
		a3 |= (uint32_t)c.pct[i] << (8 * i);   a4 |= (uint32_t)c.pct[i + 4] << (8 * i);
	}
	int64_t v = wmi(kDEVS, kDevCurve[fan], a1, a2, a3, a4);
	return v >= 0 && v != kUnsupported;
}

void AsusFanSMC::restoreAuto(int fan, const char *why)
{
	bool ok;
	if (policyDev) ok = wmi(kDEVS, kDevPolicy, policy) >= 0;
	else ok = writeCurve(fan, factory[fan]);
	manualApplied[fan] = false;
	LOG("fan %d back to the firmware's curve (%s)%s", fan, why, ok ? "" : " -- the firmware refused");
}

void AsusFanSMC::apply(bool force)
{
	for (int f = 0; f < fans && control; f++) {
		bool manual = mode[f]->raw8() == 1;
		if (!manual) { if (manualApplied[f]) restoreAuto(f, "automatic mode"); continue; }
		double tg = VirtualSMCAPI::decodeFp(SmcKeyTypeFpe2, target[f]->raw16());
		double mx = atomic_load_explicit(&maxRpm[f], memory_order_acquire);
		int pct = mx > 0 ? (int)(tg * 100.0 / mx + 0.5) : 0;
		if (pct < 0) pct = 0;
		if (pct > 100) pct = 100;
		Curve c = factory[f];
		for (int i = 0; i < kPoints; i++) if (c.pct[i] < pct) c.pct[i] = (uint8_t)pct;   // never below the factory curve
		if (!force && manualApplied[f] && !memcmp(&c, &written[f], sizeof c)) continue;
		if (writeCurve(f, c)) {
			if (!manualApplied[f] || memcmp(&c, &written[f], sizeof c))
				LOG("fan %d manual: target %d rpm -> at least %d%% (curve %u/%u/%u/%u/%u/%u/%u/%u %%)", f, (int)tg, pct,
				    c.pct[0], c.pct[1], c.pct[2], c.pct[3], c.pct[4], c.pct[5], c.pct[6], c.pct[7]);
			written[f] = c; manualApplied[f] = true;
		} else LOG("fan %d: the firmware refused the curve", f);
	}
}

uint16_t AsusFanSMC::readRPM(int fan, int64_t *rawOut)
{
	int64_t v = wmi(kDSTS, kDevFan[fan]);
	if (rawOut) *rawOut = v;
	uint16_t r = (v >= 0 && (v & kPresence)) ? (uint16_t)((v & 0xffff) * 100) : 0;
	if (!r && ec) {
		OSNumber *arg = OSNumber::withNumber((unsigned long long)fan, 32);
		uint32_t t = 0;
		if (arg && ec->evaluateInteger("TACH", &t, (OSObject **)&arg, 1) == kIOReturnSuccess && t < 20000) r = (uint16_t)t;
		if (arg) arg->release();
	}
	return r;
}

void AsusFanSMC::poll()
{
	char raw[96]; size_t at = 0;
	for (int f = 0; f < fans; f++) {
		int64_t v = 0;
		uint16_t r = readRPM(f, &v);
		atomic_store_explicit(&rpm[f], r, memory_order_release);
		if (r > atomic_load_explicit(&maxRpm[f], memory_order_acquire)) atomic_store_explicit(&maxRpm[f], r, memory_order_release);
		at += (size_t)snprintf(raw + at, sizeof raw - at, "fan%d DSTS 0x%llx -> %u rpm; ", f, (unsigned long long)v, r);
	}
	int t = 0; size_t sz = sizeof t;
	atomic_store_explicit(&gpuCelsius, (uint16_t)(sysctlbyname("debug.nvaccel_gpu_temp", &t, &sz, nullptr, 0) == 0 && t > 0 && t < 125 ? t : 0),
	                      memory_order_release);
	if (ticks % 5 == 0) setProperty("LastReading", raw);
	uint32_t g = atomic_load_explicit(&generation, memory_order_acquire);
	bool changed = g != seenGeneration; seenGeneration = g;
	// re-assert a manual curve now and then: a policy key (Fn+F5) or a wake can reset it in the firmware
	bool reassert = ++ticks % kReassertTicks == 0;
	if (changed || reassert) apply(reassert);
	poller->setTimeoutMS(kPollMS);
}

IOService *AsusFanSMC::probe(IOService *provider, SInt32 *score)
{
	if (!IOService::probe(provider, score)) return nullptr;
	int off = 0;
	if (PE_parse_boot_argn("-asusfanoff", &off, sizeof off)) { LOG("off (-asusfanoff)"); return nullptr; }
	if (OSDictionary *m = IOService::nameMatching("AppleACPIPlatformExpert")) {
		IOService *acpi = IOService::waitForMatchingService(m); m->release();
		if (acpi) acpi->release();
	}
	OSDictionary *m = IOService::nameMatching("PNP0C14");
	OSIterator *it = m ? IOService::getMatchingServices(m) : nullptr;
	if (m) m->release();
	while (it && !atk) {
		IOACPIPlatformDevice *d = OSDynamicCast(IOACPIPlatformDevice, it->getNextObject());
		if (!d) break;
		OSObject *uid = nullptr;
		if (d->evaluateObject("_UID", &uid) == kIOReturnSuccess) {
			OSString *s = OSDynamicCast(OSString, uid);
			if (s && s->isEqualTo("ATK") && d->validateObject("WMNB") == kIOReturnSuccess) { atk = d; atk->retain(); }
		}
		if (uid) uid->release();
	}
	if (it) it->release();
	if (!atk) { LOG("no ASUS ATK WMI device (PNP0C14, _UID ATK, WMNB) -- not an ASUS laptop this kext knows"); return nullptr; }

	static const uint32_t survey[] = { 0x00110012, 0x00110013, 0x00110014, 0x00110018, 0x00110019, 0x00110031,
	                                   0x00120075, 0x00120057, 0x00050019 };
	for (uint32_t id : survey) LOG("survey DSTS 0x%08x = 0x%llx", id, (unsigned long long)wmi(kDSTS, id));
	static const uint32_t curves[] = { 0x00110024, 0x00110025, 0x00110032 };
	for (uint32_t id : curves) for (uint32_t md = 0; md < 3; md++) {
		OSObject *res = nullptr; int64_t v = wmi(kDSTS, id, md, 0, 0, 0, &res);
		OSData *d = OSDynamicCast(OSData, res);
		if (d) {
			char hex[3 * 32 + 1] = {}; const uint8_t *b = static_cast<const uint8_t *>(d->getBytesNoCopy());
			for (unsigned i = 0; i < d->getLength() && i < 32; i++) snprintf(hex + 3 * i, 4, "%02x ", b[i]);
			LOG("survey curve 0x%08x mode %u: buffer %u bytes: %s", id, md, d->getLength(), hex);
		} else LOG("survey curve 0x%08x mode %u: 0x%llx (%s)", id, md, (unsigned long long)v, res ? res->getMetaClass()->getClassName() : "nothing");
		if (res) res->release();
	}
	if (OSDictionary *em = IOService::nameMatching("PNP0C09")) {
		if (OSIterator *ei = IOService::getMatchingServices(em)) {
			while (!ec) { auto d = OSDynamicCast(IOACPIPlatformDevice, ei->getNextObject()); if (!d) break;
			              if (d->validateObject("TACH") == kIOReturnSuccess) { ec = d; ec->retain(); } }
			ei->release();
		}
		em->release();
	}
	LOG("EC TACH method: %s", ec ? "present (fallback for fan speed)" : "absent");
	for (int f = 0; f < 2; f++) {
		int64_t v = wmi(kDSTS, kDevFan[f]);
		LOG("DSTS fan %d (0x%08x) = 0x%llx", f, kDevFan[f], (unsigned long long)v);
		if (v < 0 || v == kUnsupported || !(v & kPresence)) break;
		fans = f + 1;
		atomic_init(&rpm[f], (uint16_t)((v & 0xffff) * 100));
		atomic_init(&maxRpm[f], (uint16_t)kDefaultMaxRPM);
	}
	if (!fans) { LOG("the firmware reports no fan speed -- nothing to publish"); return nullptr; }
	atomic_init(&generation, 0);
	atomic_init(&gpuCelsius, 0);

	int64_t pv = wmi(kDSTS, kDevPolicy);
	// 0 balanced, 1 turbo, 2 silent; newer firmware also reports 3 (seen here: 0x10003). Re-writing the value the
	// firmware reported hands the fans back to that mode.
	policyDev = pv >= 0 && pv != kUnsupported && (pv & kPresence) && (pv & 0xff) <= 3;
	policy = policyDev ? (uint32_t)(pv & 0xff) : 0;
	LOG("DSTS thermal policy (0x%08x) = 0x%llx -> %s", kDevPolicy, (unsigned long long)pv, policyDev ? "used to restore the firmware curve" : "absent");

	control = !PE_parse_boot_argn("-asusfanro", &off, sizeof off);
	for (int f = 0; f < fans && control; f++) {
		if (!readCurve(f, factory[f])) { LOG("fan %d: no factory curve (DSTS 0x%08x) -- read-only", f, kDevCurve[f]); control = false; break; }
		Curve &c = factory[f];
		LOG("fan %d factory curve: %u/%u/%u/%u/%u/%u/%u/%u C -> %u/%u/%u/%u/%u/%u/%u/%u %%", f,
		    c.temp[0], c.temp[1], c.temp[2], c.temp[3], c.temp[4], c.temp[5], c.temp[6], c.temp[7],
		    c.pct[0], c.pct[1], c.pct[2], c.pct[3], c.pct[4], c.pct[5], c.pct[6], c.pct[7]);
	}

	// VirtualSMC binary-searches a plugin's keys: they have to be added in alphabetical order
	for (int f = 0; f < fans; f++) {
		char n = (char)('0' + f);
		VirtualSMCAPI::addKey(SMC_MAKE_IDENTIFIER('F',n,'A','c'), vsmcPlugin.data,
			VirtualSMCAPI::valueWithFp(0, SmcKeyTypeFpe2, new FanActual(&rpm[f])));
		if (!control) continue;
		mode[f] = new FanWritable(&generation);
		VirtualSMCAPI::addKey(SMC_MAKE_IDENTIFIER('F',n,'M','d'), vsmcPlugin.data,
			VirtualSMCAPI::valueWithUint8(0, mode[f], SMC_KEY_ATTRIBUTE_READ | SMC_KEY_ATTRIBUTE_WRITE));
		VirtualSMCAPI::addKey(SMC_MAKE_IDENTIFIER('F',n,'M','n'), vsmcPlugin.data, VirtualSMCAPI::valueWithFp(kMinRPM, SmcKeyTypeFpe2));
		VirtualSMCAPI::addKey(SMC_MAKE_IDENTIFIER('F',n,'M','x'), vsmcPlugin.data,
			VirtualSMCAPI::valueWithFp(kDefaultMaxRPM, SmcKeyTypeFpe2, new FanMax(&maxRpm[f])));
		target[f] = new FanWritable(&generation);
		VirtualSMCAPI::addKey(SMC_MAKE_IDENTIFIER('F',n,'T','g'), vsmcPlugin.data,
			VirtualSMCAPI::valueWithFp(0, SmcKeyTypeFpe2, target[f], SMC_KEY_ATTRIBUTE_READ | SMC_KEY_ATTRIBUTE_WRITE));
	}
	VirtualSMCAPI::addKey(SMC_MAKE_IDENTIFIER('F','N','u','m'), vsmcPlugin.data, VirtualSMCAPI::valueWithUint8((uint8_t)fans));
	// always: the NVIDIA driver loads after this kext; until it answers, the key reads 0
	VirtualSMCAPI::addKey(SMC_MAKE_IDENTIFIER('T','G','0','D'), vsmcPlugin.data, VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new GPUTemp(&gpuCelsius)));
	LOG("%d fan(s), control %s, GPU temperature key TG0D", fans, control ? "on (never below the factory curve)" : "off");
	return this;
}

bool AsusFanSMC::start(IOService *provider)
{
	if (!IOService::start(provider)) return false;
	setProperty("Diagnostics", gDiag);
	vsmcNotifier = VirtualSMCAPI::registerHandler(vsmcHandler, this);
	registerService();
	return vsmcNotifier != nullptr;
}

bool AsusFanSMC::vsmcHandler(void *sensors, void *refCon, IOService *vsmc, IONotifier *notifier)
{
	auto self = static_cast<AsusFanSMC *>(sensors);
	if (!self || !vsmc) return false;
	IOReturn r = vsmc->callPlatformFunction(VirtualSMCAPI::SubmitPlugin, true, sensors, &self->vsmcPlugin, nullptr, nullptr);
	if (r != kIOReturnSuccess) { if (r != kIOReturnUnsupported) LOG("plugin submission failed 0x%x", r); return false; }
	self->workloop = self->getWorkLoop();
	self->poller = IOTimerEventSource::timerEventSource(self, [](OSObject *o, IOTimerEventSource *) {
		if (auto me = OSDynamicCast(AsusFanSMC, o)) me->poll();
	});
	if (!self->workloop || !self->poller || self->workloop->addEventSource(self->poller) != kIOReturnSuccess) {
		LOG("no poller -- fan speeds stay at their boot values"); return false;
	}
	self->poller->setTimeoutMS(kPollMS);
	if (self->control) self->powerNotifier = registerPrioritySleepWakeInterest(&AsusFanSMC::powerHandler, self, nullptr);
	LOG("submitted to VirtualSMC, polling every %u ms", kPollMS);
	return true;
}

// shutdown, restart and sleep hand the fans back to the firmware; after a wake the manual curve is written again
IOReturn AsusFanSMC::powerHandler(void *target, void *refCon, UInt32 type, IOService *provider, void *arg, vm_size_t size)
{
	auto me = static_cast<AsusFanSMC *>(target);
	if (me && me->workloop && (type == kIOMessageSystemWillPowerOff || type == kIOMessageSystemWillRestart ||
	                           type == kIOMessageSystemWillSleep || type == kIOMessageSystemHasPoweredOn)) {
		me->workloop->runAction([](OSObject *o, void *t, void *, void *, void *) -> IOReturn {
			auto self = static_cast<AsusFanSMC *>(o);
			UInt32 msg = (UInt32)(uintptr_t)t;
			if (msg == kIOMessageSystemHasPoweredOn) {
				bool any = false;
				for (int f = 0; f < self->fans; f++) any |= self->mode[f] && self->mode[f]->raw8() == 1;
				if (any) self->apply(true);
			} else for (int f = 0; f < self->fans; f++) if (self->manualApplied[f])
				self->restoreAuto(f, msg == kIOMessageSystemWillSleep ? "sleep" : "shutdown");
			return kIOReturnSuccess;
		}, me, (void *)(uintptr_t)type);
	}
	if (type == kIOMessageSystemWillSleep || type == kIOMessageSystemWillPowerOff || type == kIOMessageSystemWillRestart ||
	    type == kIOMessageCanSystemSleep)
		acknowledgeSleepWakeNotification(refCon);
	return kIOReturnSuccess;
}

void AsusFanSMC::stop(IOService *provider)
{
	if (poller) poller->cancelTimeout();
	if (powerNotifier) { powerNotifier->remove(); powerNotifier = nullptr; }
	for (int f = 0; f < fans; f++) if (manualApplied[f]) restoreAuto(f, "stop");
	IOService::stop(provider);
}
