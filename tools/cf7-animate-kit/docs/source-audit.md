# 来源审计：醉尘仙 AN 插件 v10.6 破解激活包（黑盒行为记录）

> 本文件是对 `~/Downloads/自用限制插件`（仓库 `tmp/zuichenxian-plugin-analysis/` 有先前反编译产物）的**黑盒行为说明**，
> 用于解释"哪些合法维护功能存在"。**cf7-animate-kit 不引用、不复用其任何一行实现**（见 [clean-room-boundary.md](clean-room-boundary.md)）。

## 1. 身份

下载包名为"自用限制插件"，实为商业付费 Adobe Animate 扩展 **"醉尘仙 AN 插件 v10.6"**（淘宝/抖音 @醉尘仙工作室 出售）的**离线破解激活包**。Python 源码经 `uncompyle6` 反编译。包内：

| 文件 | 实质 |
|---|---|
| `Setup_Denetworked.exe` (`Setup_source.py`) | tkinter GUI：装 SWF + 算号 + 伪造 `.sol` + 删 UI 状态 + 改 hosts；另含正经维护小工具 |
| `ZCX_Sol_Generator.exe` (`ZCX_Sol_Generator.py`) | 离线 `.sol` 伪造器，含凭空生成合法用户码的 `make_valid_consum_code` |
| `patch_plugin.py` | 二进制 patch 插件 SWF，把远程校验 URL 改死端口 |

## 2. 被绕过的四层 DRM（仅记录，不复刻）

1. **机器绑定**：`active_code = MD5(MAC + "FUCKYOU").hexdigest().upper()` 切 5 组
   `[5:10]-[0:5]-[10:15]-[20:25]-[15:20]`。MAC 归一化为大写 `-` 分隔 17 位。
2. **用户码本地校验**（`consum_code`，12 位，首位可字母，后 11 位数字）的 4 条 mod-10 约束：
   `d2=(d9+d11)%10`、`d10=(d1+d3)%10`、`d5=(d6+d8+d10)%10`、`d7=(d2+d4+d6)%10`。
   默认码 `Z74876011658` 实测满足全部四条。生成器随机化"自由位"、反推其余位即可凭空造码。
3. **状态存储**：Flash SharedObject `.sol`（AMF0 二进制），文件名
   `ZCXGZS_2024_AD2F561A8_0002.sol`，含 `mac_address/recomm_code/active_code/consum_code`。
   破解手工拼 `TCSO` 字节写入所有 `#SharedObjects/*/localhost` 候选目录，并删 `0000.sol` UI 状态缓存。
4. **远程 kill-switch**：插件请求 `https://www.pispik.com/moyu/plugin/verify?user_code=...` 期望返回 `OK`，
   否则判非法回退。`patch_plugin.py` 把 SWF 层层解包（DoSWF：外层 DefineBinaryData→XOR+zlib→内层 loader+UI→再一层
   DefineBinaryData→XOR+zlib→真 UI SWF），在 ABC 常量池里把 URL 改成 `http://127.0.0.1:9/aaa...`（**等字节长度**，
   保住常量池长度字段），请求静默失败→`Event.COMPLETE` 永不触发→保持激活；并把 `pispik.com`/`cilisucai.com` 写入 hosts 作双保险。

## 3. 可光明正大复刻的正经维护功能（`Setup_source.py` function_1~6）

装/更新/删插件 SWF、清 WindowSWF tmp 缓存、改 `jvm.ini` 的 `-Xmx/-Xms`（扩内存）、收侧边（改 `fl_dictionary_*.dat`：
删 `PI_MAX_WIDTH/PI_MIN_WIDTH` 行、把"自动调整字距"缩成"自动"）、打开 WindowSWF/Commands 目录、复制机器码（纯字符串）、
SharedObject 诊断。

> cf7-animate-kit 的 **capability ①（AN 维护）** 与 **capability ②（通用 `.sol`/AMF0 编解码技术）** 即取材于本节的"正经功能"和
> ".sol 是 AMF0 二进制"这一**技术事实**，全部从零依公开 Adobe + AMF0 规范重写；第 2 节的算号/伪造/绕校验/改 hosts 一律不实现。

## 4. SOL/AMF0 格式（技术事实，公开规范，本工具据此独立实现）

- 信封：`00 BF | u32 BE length(=fileSize-6) | "TCSO" | 6 字节 pad(0x000400000000) | u16 nameLen+name | u32 amfVersion | body`。
- body：重复 `u16 nameLen + name + AMF0 value + 0x00 trailer` 直到 EOF。
- 引用语义（对真 Adobe Flash 实测，见仓库 `amf0-help/sol_parser`）：仅复杂类型（Object/TypedObject/ECMAArray/StrictArray）占引用槽，
  按 body DFS 前序编号；真 Flash 用索引 0 占隐式 root，故 body 引用 `raw` 解析为 `byIndex[raw-1]`，回指 root 写作 `0x0D` Unsupported。
- 本工具 `core/AmfCodec` 对 `amf0-help/sol_parser`（Rust `flash_lso`）的输出做字节级 + JSON 投影双重 oracle 校验（见 `packages/core/tests`）。
