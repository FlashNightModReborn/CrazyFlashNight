# MPO 开关工具（mpo-toggle.ps1）

A/B 测试用的 **开发诊断工具**，开关 Windows 的 MPO（Multiplane Overlay，多平面叠加）。

## 它解决什么

CF7 launcher 的覆盖层是三层顶级窗口栈（InputShield 逐像素 ULW + 透明 WebView2 overlay + Flash HWND）。
DWM 会对这种窗口栈反复尝试 MPO —— 不断 promote/demote 叠加平面 —— 每次重配置在 present 队列插一个
stall，拖慢 SWF 帧时间，表现为卡顿 / WebView2「假死」。

这个工具开关 MPO，让该回归能在**低配机**上做 A/B 实测。它通过业界熟知的注册表值实现：

```
HKLM\SOFTWARE\Microsoft\Windows\Dwm\OverlayTestMode = 5    # 禁用 MPO
```

## ⚠️ 定位：仅限开发 / 诊断

这个工具**不是**生产方案，原因是 `OverlayTestMode`：

- **全系统、持久、未公开**（名字就叫 test mode）—— 影响整机所有程序，不限 CF7；
- 改动**在游戏退出后依然生效**，卸载游戏也不会自动还原；
- 需要**重启**才生效。

所以 shipping launcher **绝不能**写这个值。理由还包括：杀软 / SmartScreen 对「启动器写
`HKLM\Microsoft\Windows\Dwm`」是启发式命中目标，而 launcher 本身带反盗版 Guardian、本就「看起来可疑」，
再叠一条系统注册表写入会把判定线推得更危险；以及 Steam 口碑与支持成本。

**生产环境的修复必须是进程作用域的**（WebView2 / Chromium overlay flag、launcher 自己的 DXGI swapchain
配置、或终极的 Ruffle 单渲染面迁移）—— 不碰用户的 OS。本工具的产出是「证实 MPO 是病根」这个**结论**，
据此去做作用域修复，而不是把注册表写入晋升到生产。

唯一可接受的「全局开关」生产形态是：**文档化、用户主动开启**的排障选项 —— 永远不做静默默认。

## 用法

```powershell
# 查看当前状态（默认动作）
.\mpo-toggle.ps1
.\mpo-toggle.ps1 -Status

# 禁用 MPO（弹 UAC，写 OverlayTestMode=5）；需重启生效
.\mpo-toggle.ps1 -Disable
.\mpo-toggle.ps1 -Disable -Reboot      # 写入后自动重启（10 秒缓冲，shutdown /a 可取消）

# 还原到第一次 -Disable 之前的状态（弹 UAC）；需重启生效
.\mpo-toggle.ps1 -Restore
.\mpo-toggle.ps1 -Restore -Reboot
```

- **快照**：第一次 `-Disable` 时把改动前的原始状态（值 / 原本不存在）记到
  `%LOCALAPPDATA%\cfn-mpo-toggle\state.json`。`-Restore` 精确还原到该状态，不是无脑删。
- **重启检测**：`-Status` 会比对写入时与当前的开机时间，区分「已写待重启」vs「已生效」。
- **提权**：父进程只读注册表 / 管快照；只有裸写 / 裸删派给 UAC 子进程。

## 测试协议（低配机 A/B）

1. **基线**：跑会卡的场景（战斗 + 密集伤害数字），用 `tools\sample-launcher-gpu.ps1` 采 GPU 负载，
   重复 5 次记中位数（单点采样不可信）。同时记主观卡顿手感。
2. `.\mpo-toggle.ps1 -Disable -Reboot`
3. **对照**：重启后同一 build、同一场景，重复第 1 步的测量。
4. `.\mpo-toggle.ps1 -Restore -Reboot` 还原。

> 战斗场景方差大，务必多次重复取中位数；新旧区间若重叠，就还不是信号。

## 测量

- **GPU 负载**：`tools\sample-launcher-gpu.ps1` —— 已按进程组（launcher / flash / web_overlay /
  bootstrap）× 适配器 × 引擎类型给出均值 / 峰值。GPU% 是吞吐量指标，对 MPO stall 不够敏感。

- **定义性证据：PresentMon**（present mode 是二值的、无噪声 —— MPO 到底有没有变，看这个）：
  1. 下载 Intel PresentMon：<https://github.com/GameTechDev/PresentMon/releases>
  2. 跑会卡的场景时，采 20 秒全进程：
     ```
     PresentMon.exe --output_file cap.csv --timed 20
     ```
  3. 看 CSV 的 `PresentMode` 列里 CF7 相关进程（`Adobe Flash Player 20.exe` /
     `CRAZYFLASHER7MercenaryEmpire.exe` / `msedgewebview2.exe`）的行。
  4. MPO 生效时常见 `Hardware Composed: Independent Flip`；MPO 关闭后通常变为 `Composed: Flip`。
     **重点是禁用前后这一列不同** —— 这就是设置真的改变了合成路径的实锤。

## 文件

```
tools/mpo/
  mpo-toggle.ps1   开关本体（纯 ASCII，PS 5.1 兼容）
  README.md        本文件
```

状态文件 `%LOCALAPPDATA%\cfn-mpo-toggle\state.json` 是机器本地的，不入库。
