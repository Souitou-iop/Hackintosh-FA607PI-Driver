# oc-add.py <config.plist>: insert AMDRyzenCPUPowerManagement + SMCAMDProcessor into Kernel > Add after VirtualSMC's
# last entry (VirtualSMC / SMCBatteryManager / SMCLightSensor), in place. Refuses if either is already listed.
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as f: p = plistlib.load(f)
add = p['Kernel']['Add']
names = [k.get('BundlePath') for k in add]
for k in ('AMDRyzenCPUPowerManagement.kext', 'SMCAMDProcessor.kext'):
    if k in names: sys.exit(f'{k} is already in config.plist')
at = max((i for i, n in enumerate(names) if n in ('VirtualSMC.kext', 'SMCBatteryManager.kext', 'SMCLightSensor.kext')), default=-1)
if at < 0: sys.exit('VirtualSMC not found in Kernel > Add')
new = [{'Arch': 'x86_64', 'BundlePath': f'{n}.kext', 'Comment': f'{n} 0.7.2f1 (CPU sensors)', 'Enabled': True,
        'ExecutablePath': f'Contents/MacOS/{n}', 'MaxKernel': '', 'MinKernel': '', 'PlistPath': 'Contents/Info.plist'}
       for n in ('AMDRyzenCPUPowerManagement', 'SMCAMDProcessor')]
add[at + 1:at + 1] = new
with open(path, 'wb') as f: plistlib.dump(p, f, sort_keys=False)
for i in range(at - 1, at + 4): print(f'   {i:2d} {add[i]["BundlePath"]}')
