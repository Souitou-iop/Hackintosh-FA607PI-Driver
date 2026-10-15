# 来源与许可说明 / Sources and licences

本仓库是**独立的个人补丁/脚本集**，与 NullMoth Systems、NVIDIA、Apple、ASUS、AMD、Intel 无关联。

| 内容 | 来源 | 许可 |
|------|------|------|
| `patches/nullmoth-2.0.0/0001-plugin.patch`、`0003-nvaccel.patch`、`0004-install-applehda.patch`，`per-fix/plugin-*`、`per-fix/nvaccel-*` | 对 <https://github.com/nullmoth/nvidia-macos-driver> 插件 / NVAccel / 安装器的修改；其中包含 [juren233/macOS-4060-laptop-driver-fix](https://github.com/juren233/macOS-4060-laptop-driver-fix) 的修复 | 沿用上游：PolyForm Noncommercial 1.0.0（全文 [LICENSE-PolyForm-Noncommercial-1.0.0.txt](LICENSE-PolyForm-Noncommercial-1.0.0.txt)） |
| `patches/nullmoth-2.0.0/0002-translator.patch` | 对 metal2vulkan（Anees Iqbal）衍生的 NullMoth 翻译器的修改 | LGPL-3.0-or-later（[LICENSE-LGPL-3.0.txt](LICENSE-LGPL-3.0.txt)） |
| `kexts/*.py`、`codec/nvenc/*` | 逐字节断言式补丁脚本（偏移 + 原字节 + 新字节 / 汇编片段），不含被修改的二进制 | GPL-3.0（见 [LICENSE](LICENSE)） |
| `codec/nvenc/*.s`、`mk.py` | 移植自朋友仓库修复 15 | GPL-3.0 |
| `tahoe/` | 基于朋友仓库的 macOS 26 升级/救援脚本修改 | GPL-3.0 |
| `kexts-src/AsusFanSMC`、`kexts-src/AACELDOff`（依赖 Lilu / VirtualSMC），`acpi/`、`tools/`、`install/`、`tests/`、文档 | 原创（AACELDOff 的 AppleHDA 资源回应思路来自朋友的 BTLEFix 1.0.6） | GPL-3.0 |

**本仓库不包含**：NullMoth/NVIDIA 的任何二进制、GSP 固件、Apple 系统文件（AppleHDA、KDK）、OpenCore `config.plist` / EFI、ACPI 转储、序列号等机器信息。
使用者须自行遵守上游驱动与 macOS 的许可条款。补丁文件里的代码属于被修改的上游项目，沿用该上游的许可证，不因本仓库的 GPL-3.0 而改变。

Required Notice: Copyright (c) 2026 NullMoth Systems (https://nullmothsystems.com)
