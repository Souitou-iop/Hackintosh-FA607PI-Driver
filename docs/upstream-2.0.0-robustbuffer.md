# NullMoth 2.0.0：robustBufferAccess 让纹理数组只剩元素 0

## 现象

- 2.0.0（官方包，以及合并了 2.0.0 的本补丁集）上，`catest sarray` 失败：16 个纹理的数组，每一页读到的都是元素 0。
- 实际影响：xterm.js / ANGLE 的字形图集用纹理数组，Claude 桌面端终端等 Electron 应用的文字又消失了（朋友修复 25 修过的问题）。
- 官方 1.15.0 插件也失败（它没有修复 25）；装了修复 25 的 1.15 插件在 2.0.0 的 NVK 上**通过**，所以问题在 2.0.0 插件。

## 定位

1. 组件替换：只把插件换回 1.15 → 通过；翻译器、NVK 换来换去 → 不影响。
2. 在合并后的插件上逐个回退上游 2.0.0 的提交（`tests/revert-one.sh`）：回退 `c69856f`（"Plugin: enable robustBufferAccess and imageCubeArray"）→ 通过。
3. 把页号写进输出的蓝色通道（`sarraypg` 变体）：页号到达片元着色器是对的，坏的是数组下标。
4. 把页号改用 256 字节的普通缓冲传入：仍然失败，排除“setBytes 太小被越界检查清零”。

## 根因

翻译器（修复 25）把 Metal 的 `array<texture2d<float>, 16>` 排成 **16 个连续的、各自 count = 1 的绑定**，插件的描述符集布局也是一个槽位一个绑定。
不开 robustBufferAccess 时，NVK 按连续的描述符内存寻址，`tex[k]` 正好落在第 k 个绑定上；开了以后，NVK 把描述符数组下标夹到该绑定自己的
`descriptorCount`（1）以内，于是所有元素都变成元素 0。

## 处理

`plugin/nvmtl_vk.c` 里 `robustBufferAccess` 改为默认关闭（与 1.15 相同），`nvrm610.conf` 写 `NVMTL_ROBUST_BUFFERS=1` 可打开。
`imageCubeArray` 照常打开。代价：越界读缓冲又可能触发 MMU fault（上游加它是为了魔兽世界在登录界面掉 GPU）。

更好的长期修法是让翻译器把纹理数组声明成单个 count = N 的绑定、插件布局与之对应，这样两个功能可以同时打开。

补丁：[`patches/nullmoth-2.0.0/per-fix/plugin-robustbuffer-optin.patch`](../patches/nullmoth-2.0.0/per-fix/plugin-robustbuffer-optin.patch)
