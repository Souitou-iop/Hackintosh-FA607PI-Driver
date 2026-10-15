# oc-add.py <config.plist>: insert AsusFanSMC into Kernel > Add after the last VirtualSMC plugin (it needs Lilu and
# VirtualSMC loaded first), in place. Refuses if it is already listed.
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as f: p = plistlib.load(f)
add = p['Kernel']['Add']
names = [k.get('BundlePath') for k in add]
if 'AsusFanSMC.kext' in names: sys.exit('AsusFanSMC.kext is already in config.plist')
smc = ('VirtualSMC.kext', 'SMCBatteryManager.kext', 'SMCLightSensor.kext', 'AMDRyzenCPUPowerManagement.kext', 'SMCAMDProcessor.kext')
at = max((i for i, n in enumerate(names) if n in smc), default=-1)
if at < 0 or 'Lilu.kext' not in names[:at]: sys.exit('Lilu / VirtualSMC not found in Kernel > Add')
add.insert(at + 1, {'Arch': 'x86_64', 'BundlePath': 'AsusFanSMC.kext', 'Comment': 'ASUS fans as SMC fans (read + control, never below the factory curve)',
                    'Enabled': True, 'ExecutablePath': 'Contents/MacOS/AsusFanSMC', 'MaxKernel': '', 'MinKernel': '', 'PlistPath': 'Contents/Info.plist'})
with open(path, 'wb') as f: plistlib.dump(p, f, sort_keys=False)
for i in range(at - 1, at + 3): print(f'   {i:2d} {add[i]["BundlePath"]}')
