// audiodev list | audiodev input "<name substring>" | audiodev output "<name substring>"
import CoreAudio
import Foundation
func prop<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ v: inout T) -> OSStatus {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var n = UInt32(MemoryLayout<T>.size); return AudioObjectGetPropertyData(obj, &a, 0, nil, &n, &v) }
var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var sz: UInt32 = 0; AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz)
var ids = [AudioObjectID](repeating: 0, count: Int(sz) / 4); AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz, &ids)
func name(_ id: AudioObjectID) -> String { var s: CFString = "" as CFString; _ = prop(id, kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal, &s); return s as String }
func chans(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
    var ad = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var n: UInt32 = 0; guard AudioObjectGetPropertyDataSize(id, &ad, 0, nil, &n) == 0, n > 0 else { return 0 }
    let p = UnsafeMutableRawPointer.allocate(byteCount: Int(n), alignment: 16); defer { p.deallocate() }
    AudioObjectGetPropertyData(id, &ad, 0, nil, &n, p)
    return UnsafeMutableAudioBufferListPointer(p.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) } }
var di = AudioObjectID(0), dout = AudioObjectID(0)
_ = prop(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal, &di)
_ = prop(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, &dout)
let args = CommandLine.arguments
if args.count < 3 { for id in ids { print(String(format: "%3d in %d out %d %@%@ %@", id, chans(id, kAudioObjectPropertyScopeInput), chans(id, kAudioObjectPropertyScopeOutput), id == di ? "[default in]" : "", id == dout ? "[default out]" : "", name(id))) }; exit(0) }
let input = args[1] == "input"
guard var t = ids.first(where: { name($0).localizedCaseInsensitiveContains(args[2]) && chans($0, input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput) > 0 }) else { print("not found"); exit(1) }
var sa = AudioObjectPropertyAddress(mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
print("set default \(args[1]) -> \(name(t)):", AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &sa, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &t))
