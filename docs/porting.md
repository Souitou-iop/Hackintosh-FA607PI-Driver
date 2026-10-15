# 移植到新版 NullMoth

每次上游发版都按这个顺序来（2.0.0 就是这样移植的）。**先比较安装包**：2.0.1 这类版本驱动文件与上一版逐字节相同，根本不用重装。

```bash
# 新旧安装包里哪些文件变了
join -j2 <(sort -k2 old/SHA256SUMS) <(sort -k2 new/SHA256SUMS) | awk '$2!=$3'
```

## 内核扩展（二进制补丁）

1. `kexts/findsites.py <旧原版> <新原版> <偏移:名字>...`：用旧版补丁点前后最长的唯一字节窗口在新版里定位。2.0.0 上 NVRM 的 kapi 部分整体 +0x280、autoGo +0x60。
2. 复制上一版的 `patch-*.py`，只改偏移；脚本对每个字节都做“原字节或已打补丁字节”断言，对不上会拒绝执行。
3. 补丁点前后 64 字节一致时，代码可以视为相同；否则要读反汇编重新设计（2.0.0 的 NVRMFB 缩放上限就是重写的，见 `patch-nvrmfb-200.py` 与 `caps.s`）。
4. 代码洞（`patch-nvrm-dpdup-200.py`）放在 `__TEXT` 末尾的全零空隙，脚本会检查空隙确实为零。

## 用户态与 NVAccel（源码补丁）

1. 插件、翻译器：在我们的分支上 `git apply -3` 上游 `旧tag..新tag` 的差异（要先 `git fetch` 上游的两个 tag，三方合并才有原始 blob），逐个解决冲突。
2. NVAccel：上游 `kexts/NVRM` 是我们分支的基底，直接换基底后 cherry-pick 我们的提交。
3. 先用未改动的新版源码构建一次，和官方二进制比较符号与字符串，确认工具链与 open-gpu-kernel-modules 版本对得上。
4. 构建插件要 `-mmacosx-version-min=15.0`：Xcode 26 默认部署目标是 26，上游安装器的运行时检查会标成“需要 macOS 26”。

## 测试

- `tests/run-200.sh`：新旧插件对照的全部回归（需要朋友仓库的 catest 和 plugshim；新插件要配新 NVK：`SHIM_ICD`）。
- `tests/xcmp.sh`：本机着色器缓存全部重译，逐字节比较 SPIR-V。
- 有回归时：`tests/bisect-one.sh <上游提交>`（单独构建上游某个提交）、`tests/revert-one.sh <上游提交>`（在我们的分支上回退它）。

## 安装器

上游 `install.sh` 每版都要重新打 `0004-install-applehda.patch`（否则内置声卡消失），并重新生成 `SHA256SUMS`。`build-payload.sh` 已包含这些步骤。
