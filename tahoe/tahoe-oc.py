# tahoe-oc.py <config.plist> : OpenCore changes for macOS 26 that keep macOS 15 booting exactly as before.
#  - boot-args += -no_compat_check (macOS 26 drops iMacPro1,1; the model is NOT changed: changing it on an installed
#    system boot-loops, nullmoth #154), revpatch=sbvmm (RestrictEvents: OTA updates with SecureBootModel Disabled),
#    -ibtcompatbeta (Intel Bluetooth on 26)
#  - Kernel > Add: AirportItlwm-Tahoe.kext (laobamac d695c97 + fix 18, MinKernel 25.0.0) right after AirportItlwm.kext;
#    the Sequoia AirportItlwm.kext keeps its MaxKernel 24.99.99. AACELDOff stays capped at 24.99.99 (15.8.1 bluetoothd).
# Refuses to run twice; prints every change.
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as f: p = plistlib.load(f)
NV = p['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']
args = NV['boot-args'].split()
for a in ('-no_compat_check', 'revpatch=sbvmm', '-ibtcompatbeta'):
    if a not in args: args.append(a); print(f'boot-args: + {a}')
if any(a.startswith('revpatch=') and a != 'revpatch=sbvmm' for a in args): sys.exit('an existing revpatch= value needs merging by hand')
NV['boot-args'] = ' '.join(args)
dl = p['NVRAM'].get('Delete', {}).get('7C436110-AB2A-4BBB-A880-FE41995C9F82', [])
if 'boot-args' not in dl: sys.exit('NVRAM > Delete lacks boot-args: the new boot-args would not take effect')
add = p['Kernel']['Add']; names = [k.get('BundlePath') for k in add]
if 'AirportItlwm-Tahoe.kext' in names: sys.exit('AirportItlwm-Tahoe.kext is already in config.plist')
i = names.index('AirportItlwm.kext'); old = add[i]
if old.get('MaxKernel') != '24.99.99': sys.exit(f'AirportItlwm.kext MaxKernel is {old.get("MaxKernel")!r}, expected 24.99.99')
new = dict(old); new.update({'BundlePath': 'AirportItlwm-Tahoe.kext', 'Comment': 'AirportItlwm Tahoe (laobamac d695c97 + fix 18 init recovery)',
                             'MinKernel': '25.0.0', 'MaxKernel': '', 'Enabled': True})
add.insert(i + 1, new); print(f'Kernel > Add: + AirportItlwm-Tahoe.kext at {i + 1} (MinKernel 25.0.0); AirportItlwm.kext stays MaxKernel 24.99.99')
for k in add:
    if k['BundlePath'] == 'AACELDOff.kext': print(f'AACELDOff.kext MaxKernel {k.get("MaxKernel")} (unchanged)')
with open(path, 'wb') as f: plistlib.dump(p, f, sort_keys=False)
print('boot-args now:', NV['boot-args'])
