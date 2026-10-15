# Hackintosh-FA607PI-Driver

华硕 **TUF Gaming A16（2024）FA607PI** 黑苹果（OpenCore）上，让 [NullMoth NVIDIA 驱动](https://github.com/nullmoth/nvidia-macos-driver)
在 **AMD 锐龙 + RTX 4070 Laptop（独显直连）** 上日常可用的一整套补丁、脚本和排错记录。当前组合：**macOS 26.7.1 Tahoe + NullMoth 2.0.0
（2.0.1 的驱动文件与 2.0.0 完全相同）+ 本仓库补丁**。

很多用户态修复来自朋友的仓库 [juren233/macOS-4060-laptop-driver-fix](https://github.com/juren233/macOS-4060-laptop-driver-fix)（RTX 4060 + Intel 平台），
本仓库在此基础上做了 **AMD 平台 / RTX 4070 / 华硕机型** 的移植，以及若干自己的内核与用户态修复。

> **这是什么 / 不是什么**
> - 是：对上游驱动**源码**的补丁（diff）、对上游二进制的**逐字节断言式补丁脚本**、自写的小内核扩展源码、安装/回滚脚本、测试程序和根因记录。
> - 不是：驱动本身。**本仓库不含任何 NullMoth / NVIDIA / Apple 的二进制、GSP 固件、EFI 或 `config.plist`**。驱动请从上游 Release 获取，
>   用 [`install/build-payload.sh`](install/build-payload.sh) 在本机构建打好补丁的安装包。
> - 只在下面这台机器上验证过。别的机器请逐项对照，**不要整套照抄**。

## 机型与硬件

| 部件 | 型号 | macOS 下的状态 |
|---|---|---|
| 机型 | ASUS TUF Gaming A16 (2024) **FA607PI** | SMBIOS `iMacPro1,1`，OpenCore 1.0.9 |
| CPU | AMD Ryzen 9 **7940HX**（Zen 4，16 核 32 线程） | AMD 内核补丁；温度/频率：SMCAMDProcessor + AMDRyzenCPUPowerManagement |
| 核显 | Radeon 610M | MUX 切到独显直连，核显不出现在 PCI 上 |
| 独显 | NVIDIA **GeForce RTX 4070 Laptop**（AD106，`10de:2860`，8 GB） | NullMoth 驱动 + 本仓库补丁：Metal 3、HiDPI、零拷贝翻转、硬件编解码 |
| 内屏 | BOE **NE160QDM-NYJ**，16″ 2560×1600 165 Hz | HiDPI（含高于面板分辨率的缩放模式） |
| 外接 | 4K/1440p DisplayPort 显示器（作者用的 2560×1440 144 Hz 面板，1920×1080 HiDPI 即 3840×2160 后备缓冲） | 热插拔（2.0.0 上游）、DDC/CI 亮度（`tools/nvddc`） |
| 内存 | 32 GB DDR5 | — |
| 硬盘 | WD PC SN560 1 TB + KIOXIA EXCERIA 500 GB（NVMe） | NVMeFix |
| 声卡 | Realtek **ALC256**（`alcid=77`） | macOS 26 已删除 AppleHDA：从 15.x KDK 放回（见 `install/stage13-tahoe-fixes.sh`） |
| 无线 | Intel **AX210**（`8086:2725`） | AirportItlwm（Tahoe 构建）+ IntelBluetoothFirmware / BlueToolFixup |
| 有线 | Realtek RTL8111（`10ec:8168`） | RealtekRTL8111 |
| 触控板 / 键盘 | I²C 触控板 / PS2 键盘 | VoodooI2C / VoodooPS2 |
| 电池 / 电源 | ACPI `ADP0` / EC | VirtualSMC + SMCBatteryManager；macOS 26 识别充电器需 `acpi/SSDT-ADP0`（修复 16） |
| 风扇 | 华硕 ATKD（WMI）双风扇 | 自写 `AsusFanSMC`：转速、曲线读到 SMC（修复 18） |

## 修复一览（当前 2.0.0 补丁集）

**K = 内核扩展，U = 用户态，P = 平台（ACPI / OpenCore / 小 kext）。** 位置都相对本仓库。

| # | 层 | 现象 | 根因（一句话） | 修复与效果 | 位置 |
|---|---|---|---|---|---|
| 1 | K | 外接 2560×1440 用不了 “1920×1080 HiDPI”；内屏没有 1920×1200 HiDPI | NVKMS 的 head scaler 只按 mode 尺寸取 ViewPortIn，后备缓冲比面板大时画面被裁 | NVRM 让 ViewPortIn = 图层源尺寸（硬件缩放），HiDPI 后备缓冲可以比面板大，仍走零拷贝翻转（朋友修复 1 的移植，偏移逐个重找） | `kexts/patch-nvrm-200.py` |
| 2 | K | 开机后约 60 秒内 Dock 等窗口不刷新 | 零拷贝翻转在桌面出现 60 秒后才切换 | `IOSleep(60000)` → 0，翻转在 WindowServer 首帧前就绪（朋友修复 2） | 同上 |
| 3 | K | **接外接 DP 显示器开机，登录时自动重启 2–3 次** | NVIDIA DisplayPort 库 `GroupImpl::insert()` 不查重，同一显示器进组两次，`LinkedList::next` 死循环，WindowServer 看门狗超时 | `insert()` 前检查是否已在组里（38 字节代码放在 `__TEXT` 尾部空隙）。原创修复 | `kexts/patch-nvrm-dpdup-200.py` |
| 4 | K | 2.0.0 上 HiDPI 缩放模式消失 | 2.0.0 把缩放/扫描输出上限改成“面板最大模式”，比面板大的后备缓冲（修复 1 需要的）不再被提供 | 上限改为 max(面板最大模式, 2× 开机分辨率)，保留 2.0.0 的超宽屏改进 | `kexts/patch-nvrmfb-200.py` |
| 5 | K | 拖动/新窗口时卡顿 | 每块新显存都经 BAR1 用 CPU 清零（非缓存写） | 跳过清零，保留金丝雀写入（朋友修复 26 的 NVRMFB 部分） | 同上 |
| 6 | K | 显卡温度、占用率在监控软件里没有；风扇控制拿不到 GPU 温度 | NullMoth 不提供 PerformanceStatistics 的温度/占用键 | NVAccel 每秒向 RM 查询，补 `Temperature(C)`、`Device Utilization %`，并提供 `sysctl debug.nvaccel_gpu_temp` | `patches/nullmoth-2.0.0/0003`（`per-fix/nvaccel-gpu-sensors.patch`） |
| 7 | K+U | 144 Hz 下桌面动画只有 94–104 帧（上游 issue #196） | WindowServer 每帧在 CPU 上等 GPU 完成（≈1.3 ms） | 帧栅栏：WindowServer 提交后即返回，交换在 NVAccel 的翻转线程里等 GPU → 140–143 帧 | `per-fix/nvaccel-196-frame-fence.patch`、`per-fix/plugin-196-ws-gpuwait.patch` |
| 8 | K+U | 最小化到 Dock 的窗口预览是空白（只剩图标） | 修复 7 让所有 WindowServer 命令缓冲都提前返回，Dock 快照在画完前被读走 | 只有“画到正在显示的表面”的命令缓冲提前返回（NVAccel 新 SCANOUT 查询），快照照旧等待 | `per-fix/*-dock-preview-scanout.patch` |
| 9 | U | 切换桌面卡顿 | Core Animation 每秒反复包装同一批 IOSurface，每次都重新导入显存（RM 分配 VA + DMA 映射，约 37% 的 WindowServer 时间） | 显存导入缓存（500 ms，256 MB 上限，NVAccel 释放显存即失效）：1011 → 22 µs/次 | `per-fix/plugin-vram-import-cache.patch` |
| 10 | U | **2.0.0 上 Claude 等 Electron 终端文字消失、纹理数组只显示第一个** | 2.0.0 打开了 `robustBufferAccess`，NVK 因此把描述符数组下标夹到每个绑定的数量（1），而翻译器把纹理数组排成连续的单个绑定 | 默认关闭（同 1.15），需要时 `nvrm610.conf` 写 `NVMTL_ROBUST_BUFFERS=1` 打开。官方 2.0.0 也有此问题 | `per-fix/plugin-robustbuffer-optin.patch`、[docs/upstream-2.0.0-robustbuffer.md](docs/upstream-2.0.0-robustbuffer.md) |
| 11 | U | 黑块、闪烁、Chrome/Steam/Electron 渲染错误、弹幕掉帧等 | 见朋友仓库各项 | 朋友修复 3、4、6、7、8、10、11、12、16、22、23、25、26（含跨进程写同步）、27–30、35 合并到 2.0.0 | `patches/nullmoth-2.0.0/0001`、`0002` |
| 12 | U | **UU 远程被控端一直“正在传输画面”** | 原版 H.264 NVENC 按旧架构写：NotSync 标志、bw8/bw16 布局与 Ada 的 t2d 不符、BAR 清零（7 dB / 110 Mbps 的花屏码流） | 移植朋友修复 15 到新版二进制：t2d 拷贝循环、NotSync、AVX 清零 → 42 dB / 4.9 Mbps，仍是**硬件编码** | `codec/nvenc/` |
| 13 | U | 驱动更新后 12 又坏了 | 官方安装包会装回原版编码器 | `build-payload.sh` 每次都对新版原版编码器重新打补丁 | `install/build-payload.sh` |
| 14 | P | 官方安装器装完 **内置声卡消失** | 安装器重建内核集合时没带 `/Library/Apple/System/Library/Extensions` 里的 AppleHDA | 安装器两处 `kmutil create` 加 `-b` AppleHDA 并校验 | `patches/nullmoth-2.0.0/0004-install-applehda.patch` |
| 15 | P | macOS 26 没有内置声卡 | Tahoe 删除了 AppleHDA；放回后它向 kernelmanagerd 请求 layout 资源被拒，启动时永远等待 | 从 15.x KDK 放回 AppleHDA、`kmutil -b` 编进辅助内核集合，AACELDOff 直接从 kext 包里读资源回应请求（朋友 BTLEFix 1.0.6 的做法） | `install/stage13-tahoe-fixes.sh`、`kexts-src/AACELDOff` |
| 16 | P | macOS 26 **识别不到充电器**；文件保险箱加密停在 0% 无法关闭 | DSDT 的 `ADP0._PSR` 读完 EC 后调用 AMD `ALIB(1)`，在 macOS 上无返回值（`AE_AML_NO_RETURN_VALUE`），整个 `_PSR` 失败 | OpenCore 把 `_PSR` 改名 `XPSR`，`SSDT-ADP0` 在 Darwin 下直接返回 EC 的值（用 acpiexec 在本机 ACPI 上复现验证） | `acpi/` |
| 17 | P | AirPods 连上但没有声音（普通 SBC/AAC 耳机正常） | Intel 蓝牙走外置模式时，bluetoothd 选了 Apple 私有的 AAC-ELD 编码；关闭它的调试开关在正式版里不读 | `AACELDOff`（Lilu 插件）在 bluetoothd 代码页校验时把选择改为“不用 AAC-ELD”（15.8.1 与 26.7.1 各一处） | `kexts-src/AACELDOff`、`tools/audio` |
| 18 | P | 风扇转速在 macOS 看不到、风扇软件不能控制 | 华硕风扇在 ATKD WMI 里，不在 SMC | `AsusFanSMC`（VirtualSMC 插件）：读 ATKD 转速，发布 `F<n>Ac/Tg/Md` 等 SMC 键；手动模式改写 8 点温度曲线且永不低于出厂曲线；`TG0D` 取修复 6 的 GPU 温度 | `kexts-src/AsusFanSMC` |
| 19 | P | 外接显示器亮度调不了 | NullMoth 没有 DDC/CI 路径 | `nvddc`：用户态通过 NVRM 用户客户端（与 NVK 相同的 RM escape）走 DP AUX-I²C / HDMI DDC 发 DDC/CI | `tools/nvddc` |
| 20 | P | 升级 macOS 26：更新准备失败 / 重启后回到 15 | 内核补丁让 bluetoothd 校验失败；`DisableVariableWrite` 挡住“启动到更新”的 NVRAM 写入；更新时驱动必须先停 | `update-26.sh`：`btoff`、临时关闭 DVW、`-nvoff` 停驱动、完成后恢复（基于朋友脚本） | `tahoe/` |

**已被上游 2.0.0 吸收、本仓库不再需要的**：显示器热插拔（#142）、面板物理尺寸（#199）、管线并行构建（#173/#177/#181/#188）、
IOSurface 写完才报 scheduled（#147）、显存跨 page-off 保留（#200）等。上游 2.0.0 的安全修复（#214）全部保留。

## 版本

| 组件 | 版本 | 说明 |
|---|---|---|
| NullMoth 驱动 | **2.0.0**（2.0.1 驱动文件相同） | 补丁按 `v2.0.0` 标签生成 |
| macOS | 26.7.1（25G241） | 15.x 时期的补丁见 `kexts/legacy-1.15.0/` 与 git 历史 |
| NVIDIA RM 源码 | open-gpu-kernel-modules **610.57.04** | 构建 NVAccel 用 |
| 编译器 | Xcode 26（Apple clang 17），`-mmacosx-version-min=15.0` | 与上游的二进制有寄存器分配差异，符号与字符串一致 |

## 使用

1. **备份 EFI**，确认 OpenCore 里有可用的 “Start once without NVIDIA driver” 之类的安全启动项。
2. 构建补丁版安装包（不需要 sudo）：
   ```bash
   UPSTREAM=~/nvidia-macos-driver PKGTAR=~/Downloads/nullmoth-nvidia-2.0.0.tar.gz \
   OGKM=~/open-gpu-kernel-modules VKH=~/Vulkan-Headers bash install/build-payload.sh ~/hackintosh/nm-2.0.0
   ```
3. 安装（上游安装器负责测试内核集合、完整备份、失败回滚；脚本另外保存并恢复你的 `nvrm610.conf`）：
   ```bash
   sudo HACK=~/hackintosh bash install/stage21-200.sh
   ```
   然后重启。撤销：`sudo HACK=~/hackintosh bash install/stage21-200.sh undo` 后重启。
4. 移植到以后的上游版本：见 [docs/porting.md](docs/porting.md)。
5. 平台类修复（16–20）各自独立，脚本都带备份与 `undo`，按需使用；`ESP_UUID` 等机器相关参数需要自己填。

**不要用 1401 Mac App 一键更新驱动**：它会装回原版文件，并重建不含 AppleHDA 的内核集合（内置声卡消失）。新版本请先移植补丁再装。

## 测试

`tests/` 是移植时用的回归测试（需要朋友仓库 `hidpi/catest` 里的测试程序和 `plugshim`）：

- `run-200.sh`：sarray（纹理数组）、slib、gfx4t、unitylock、chainstress、rparktest、tiledmips、rtcheck、earlyz、drawbench、upbench、newsurf、
  bench_vt_transfer 以及 10 项回归，新旧插件对照。2.0.0 补丁集全部通过，性能与 1.15 补丁集持平或略好。
- `xcmp.sh`：用新旧翻译器把本机着色器缓存（1442 个 AIR 模块）全部重新翻译并逐字节比较：完全一致。
- `wswscan.m` / `wswfake.m`：模拟内核验证修复 7、8（快照必须等到画完，屏幕帧可以提前返回）。
- `bisect-one.sh` / `revert-one.sh`：定位上游回归（修复 10 就是这样找到的）。

## 致谢与许可

- 朋友的仓库 [juren233/macOS-4060-laptop-driver-fix](https://github.com/juren233/macOS-4060-laptop-driver-fix)：大量用户态修复、NVENC/NVDEC 分析、macOS 26 升级流程。
- [NullMoth](https://github.com/nullmoth/nvidia-macos-driver)、metal2vulkan（Anees Iqbal）、NVIDIA open-gpu-kernel-modules、Mesa NVK、acidanthera、OpenIntelWireless 等上游项目。

来源与许可见 [NOTICE.md](NOTICE.md)：`.patch` 文件沿用被修改项目的许可证（插件/内核扩展补丁为 PolyForm Noncommercial 1.0.0，翻译器补丁为 LGPL-3.0-or-later），
原创脚本、kext 源码与文档为 GPL-3.0。与 NullMoth、NVIDIA、Apple、ASUS 均无关联，按“原样”提供，不作任何保证。

---

**English summary.** Patches, byte-patch scripts, small kexts and install scripts that make the NullMoth NVIDIA driver (2.0.0) usable on an
ASUS TUF Gaming A16 (2024) FA607PI hackintosh: Ryzen 9 7940HX, RTX 4070 Laptop (dGPU-direct), BOE 2560×1600 165 Hz panel, macOS 26.7.1.
Highlights: HiDPI modes above panel resolution, a fix for a DisplayPort-library infinite loop that reboot-looped login with an external monitor,
WindowServer GPU frame fence with a Dock-preview fix, VRAM import cache, GPU sensors, Ada H.264 NVENC fix (UU Remote), a 2.0.0 regression fix
(robustBufferAccess breaking texture arrays), AppleHDA-preserving installer, AC adapter SSDT for AMD `ALIB`, ASUS fan SMC plugin.
No NullMoth/NVIDIA/Apple binaries are included; build the patched package with `install/build-payload.sh`.
