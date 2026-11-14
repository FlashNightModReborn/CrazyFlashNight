# Flash CS6 32 位虚拟地址空间耗尽取证与单机宿主对照档案（2026-11-14）

**文档角色**：单机样本证据与专项取证复盘（`LOCAL_ONLY` 对照参考，非跨机器全局指令）。  
**最后核对代码基线**：commit `c475797b8afaf37e9b5fe7d805ca932a668d4ed8`（2026-11-14；含 21 份现场崩溃转储反汇编归因与同源码单变量对照实测）。

> **适用边界声明**：本文记录主力开发机（Windows 10/11 x64 + 绿色便携版 Flash CS6 `12.0.0.481`）在 5 小时级长程自动化施工中频繁触发空指针崩溃的完整取证链与单变量对照数据。文中涉及宿主兼容层（`RUNASADMIN` / `WIN7RTM`）与计划任务提权桥接的结论属于**该类绿色版宿主的机器画像**，不得当作所有开发机的默认前置；跨机器通用操作规范以 [`scripts/FlashCS6自动化编译.md`](../scripts/FlashCS6自动化编译.md) 与 [`agentsDoc/testing-details.md`](../agentsDoc/testing-details.md#flash-core) 为唯一权威。原始 `.mdmp` 二进制转储已归档至本机仓库外诊断目录，不入库。

---

## 1. 现象与核心结论速览

长程施工中观察到三类典型现象：

1. 每次编辑 XFL 后采用 close + reopen + 编译的自动化循环，数十分钟至数小时后 `Flash.exe` 高概率发生 `0xC0000005`（空指针写/读访问违例）或 `0xC0000374`（堆损坏弹窗卡死）。
2. 单纯关闭打开的 XFL 文档甚至偶发重启 CS6 后，连续重编大型目标（尤以 `scripts/asLoader/asLoader.xfl` 为甚）仍可能迅速复发；**重启 Windows 操作系统后故障率显著回落**。
3. 编译期偶发伴随 AS2 `32K` 分支上限报错与自动重试，重试期间极易直接原生崩溃退出。

经二进制反汇编、21 份 `.mdmp` 转储量化对账与同源码 A/B 实测，根因链条完全闭合：

- **普遍架构定律（所有机器共通）**：
  1. `Flash.exe` 是启用了 `LARGE_ADDRESS_AWARE` 的 **32 位 x86 进程**，在 64 位 Windows（WoW64）下用户态虚拟地址空间（VA）硬上限为 **`4,095.9 MiB`（`0xFFEFFFFF`）**。
  2. CS6 内置 AS2 编译器使用通过 `_atexit` 注册的**进程级全局单例 AST/符号内存池**（`0x1E30ED4`）。**调用 `fl.closeDocument()` 关闭 XFL 文档几乎不释放该池已保留的 VA slab**；只有退出 `Flash.exe` 进程才会回收。
  3. 随着项目规模增长，`asLoader` 已达 **823 个 AS2 类、`asLoader.swf` 7.23 MB**（对比 2026-07-21 基线仅 1.04 MB）。干净宿主单次发布 `asLoader` 的峰值 `VirtualSize` 已达 **`3.75 GiB`~`3.97 GiB`**，逼近 32 位 4 GiB 悬崖。
  4. 编译器内存池按 **2 倍几何级数扩容**（`64 MiB → 128 MiB → 256 MiB`），且内部调用 `operator new(size, std::nothrow)`。一旦进程剩余最大连续空闲 VA 段不足以容纳下一次倍增分配，分配器返回 `NULL (0)`，而编译器多处热路径**未做空指针判空便直接解引用写入**，表现为 `EAX=0` / `ECX=0` / `EDI=0` 的空指针崩溃。
- **本机特定放大器（便携绿色版宿主画像）**：
  1. 绿色免安装版因缺少 MSI 安装器写入的 HKLM COM/Licensing 注册表项，依赖 `~ RUNASADMIN` 提权运行；此前额外叠加了 **`WIN7RTM`** 兼容标志，强制注入 `AcLayers.dll`（2.63 MiB）并改用 Windows 7 兼容堆策略。
  2. 同源码单变量实测证明：**仅保留 `~ RUNASADMIN`、移除 `WIN7RTM` 后**，`asLoader` 单次发布峰值 VA 从 **`3,970.5 MiB` 降至 `3,754.6 MiB`（释放 `215.9 MiB` 连续地址裕量，4 GiB 安全余量从 `125.4 MiB` 扩大至 `341.3 MiB`，达 `2.72x`）**，且单次编译 CPU 耗时从 **`804.5 s` 降至 `605.4 s`（提速 `24.7%`）**。
  3. **为何重启电脑有效**：并非系统物理内存或页面文件耗尽（崩溃时刻系统自动托管页面文件仍有 `6.81 GiB`~`20.05 GiB` 提交裕量），而是 64 位 Windows 的 WoW64 系统 DLL（`KnownDlls` / ASLR 映像基址）在每次开机时固定基址，叠加长程会话中残留脏 `Flash.exe` 实例、`AcLayers.dll` 碎片化垫片及偶发 0 字节 `.aso` 磁盘缓存；重启电脑同时清空了残留宿主并重洗了 32 位高地址区系统 DLL 映射布局，恢复了最大的连续可用 VA 区间。

---

## 2. 二进制与反汇编证据链（`Flash.exe` 12.0.0.481）

对 `<GREEN_CS6_DIR>\Flash.exe`（PE ImageBase `0x00400000`，TimeDateStamp `2012-04-06`）与崩溃现场指令流的静态核验结果如下：

| 项目 | 机器真源核验值 | 工程含义 |
|------|----------------|----------|
| PE `Machine` / `Characteristics` | `0x014C` (I386) / `0x0122` (`LARGE_ADDRESS_AWARE`) | WoW64 下理论最高可用 VA 为 `4,095.9 MiB`，不可能通过加物理内存突破 4 GiB |
| CRT 运行库 | `MSVCR100.dll` (`10.0.40219.473`) | 32 位 VC10 堆管理；大块分配直接落入 `NtAllocateVirtualMemory` |
| 全局编译器池单例 | `Flash.exe+0x1071470` → 全局指针 `0x1E30ED4` | 首次编译时惰性构造，通过 `_atexit` (`+0x1071420`) 注册析构；**文档关闭不触发释放** |
| 倍增块分配器 | `Flash.exe+0x10718A0` → `Flash.exe+0x106DBB0` | 容量不足时按 `oldCap * 2` 申请新连续块，经 `0x00401000` 调 `operator new(bytes, std::nothrow)` |
| 空指针解引用点 A | `Flash.exe+0x10876E5`：`mov [eax+8], edx`（`EAX=0`） | AST 节点分配返回 `0` 后未判空直接写字段（高频 VA 耗尽现场） |
| 空指针解引用点 B | `Flash.exe+0x10630E9`：`mov [eax], ecx`（`EAX=0`） | 符号/类型表扩容返回 `0` 后直接写首字段 |
| 空指针解引用点 C | `Flash.exe+0x10653DA`：`mov [eax], edx`（`EAX=0`） | 类编译中间表项分配失败或前序异常状态传播 |
| 空指针解引用点 D | `Flash.exe+0x1062FB0`：`cmp byte ptr [ecx+9], 0`（`ECX=0`） | **非 OOM**：AS2 包通配 `import pkg.*` / 跨类符号消解为空时的前端空指针 bug |
| CRT 拷贝解引用点 E | `msvcr100.dll+0x10A4E` / `+0x1ED7`（`EDI=0`） | `malloc` 返回 `NULL` 后直接传入 `memcpy` / `memmove` 目标地址 |
| 堆损坏与弹窗阻塞 | `ntdll.dll` `0xC0000374` (`STATUS_HEAP_CORRUPTION`) | 异常退出路径或损坏结构析构触发；若弹出 `"FlashPro Fatal Exception"` 模态框会阻塞后台 JSFL |

---

## 3. 21 份现场 Minidump 分类对账表

样本范围：历史归档转储 `#17..#20, #29..#30, #41..#44, #50` 与 2026-11-14 长程施工转储 `#51..#60`（共 21 份，均取自 `MINIDUMP_MISC_INFO_2` / `VM_COUNTERS` 与异常上下文）。

| 分类桶 | 命中转储编号 | 异常码与崩溃偏移 | 崩溃时 `VirtualSize` / `PeakVirtual` | 进程存活时长 | 根因定性 |
|--------|--------------|------------------|--------------------------------------|--------------|----------|
| **桶 1：低水位确定性编译前端 Bug** | `#41, #42, #43, #44` | `0xC0000005` @ `Flash.exe+0x1062FB0` (`ECX=0`) | `1,288` ~ `1,422 MiB` | `17` ~ `64 s` | **非内存耗尽**：`TestLoader` 特定 wildcard import / 类解析触发 CS6 AS2 前端空指针 |
| **桶 1b：中低水位单次编译异常** | `#50` | `0xC0000005` @ `Flash.exe+0x10653DA` (`EAX=0`) | `1,951 MiB` / `1,962 MiB` | `118 s` | 中等水位编译异常（非 4 GiB 顶格耗尽） |
| **桶 2：脏宿主累积 / 同进程重编 VA 耗尽** | `#17, #18, #29, #30, #51, #52, #53, #55, #57, #58, #59, #60` | `0xC0000005` @ `+0x10876E5`, `+0x10630E9`, `msvcr100+0x10A4E`, `msvcr100+0x1ED7` | `3,340` ~ `3,918 MiB`（峰值最高 `3,922 MiB`） | `249` ~ `5,332 s` | **主力瓶颈（12/21）**：前序编译残留高水位 VA 或同进程触发 32K 二次重试，倍增块撞击 4 GiB 上限 |
| **桶 3：长开机后期连续块挤压 VA 失败** | `#54, #56` | `0xC0000005` @ `Flash.exe+0x10876E5` (`EAX=0`) | `3,121` ~ `3,154 MiB` | `147` ~ `178 s` | 新近启动宿主在 `3.15 GiB` 处即无法拿到 `256 MiB` 连续块（高地址 DLL 布局分割 + `WIN7RTM` 垫片占用） |
| **桶 4：非 AS2 编辑操作 / 堆损坏** | `#19` / `#20` | `#19`: `0xC0000094` (除零 `@+0x521BC5`)<br>`#20`: `0xC0000374` (`ntdll+0xF1C99`) | `#19`: `536 MiB`<br>`#20`: `1,303 MiB` | `612 s` / `1,840 s` | `#19` 为界面/时间轴算术除零；`#20` 为原生堆损坏 |

> **关键证伪说明**：对 `#51..#60` 核对系统 `Win32_PageFileSetting` 与转储时刻系统 Commit 余量确认，本机启用了 `AutomaticManagedPagefile = True`，崩溃瞬间系统级空闲可提交内存仍有 **`6.81 GiB` ~ `20.05 GiB`**。因此 `3.15 GiB`~`3.92 GiB` 处的 `std::nothrow` 失败纯粹是 **单进程 32 位 4 GiB 虚拟地址空间连续段耗尽**，而非整机物理内存或虚拟内存不足。

---

## 4. 单变量对照实测：移除 `WIN7RTM` 与文档关闭驻留验证

在代码基线 `c475797b8afaf37e9b5fe7d805ca932a668d4ed8`（823 个 AS2 类，`aso` 缓存健康：1,179 个文件、0 个零字节文件）上，固定同一编译命令 `compile_test.ps1 -Target publish`（隐式 `doc.publish()` + `-VerifySwf scripts/asLoader.swf` + 类归属门 + 继承顺序门），仅改变 `HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers` 中的 `WIN7RTM` 标志，实测结果如下：

| 指标 | 对照组 A：`~ RUNASADMIN WIN7RTM`（旧配置） | 实验组 B：`~ RUNASADMIN`（移除 `WIN7RTM`） | 净变化与结论 |
|------|--------------------------------------------|--------------------------------------------|--------------|
| `AcLayers.dll` 注入状态 | 已加载（占用 `2.63 MiB` + Win7 堆垫片激活） | **未加载** | 消除兼容层堆拦截与地址分割 |
| 冷启动空编辑器 `VirtualSize` / `Private` | `471.5 MiB` / `70.1 MiB` | **`447.6 MiB`** / **`68.0 MiB`** | 空载基线降低 `23.9 MiB` |
| `asLoader` 完整发布 CPU 时间 | `804.50 s` | **`605.44 s`**（墙钟 `644 s`） | **每次发布节省 `199.1 s`（提速 `24.7%`）** |
| 编译结果与产物字节数 | `0/0` 错误，`7,234,840 B`，门禁全绿 | `0/0` 错误，`7,234,840 B`，门禁全绿 | 绿色版在纯 `RUNASADMIN` 下完全正常工作 |
| 生命周期峰值 `PeakVirtualSize` | **`3,970.5 MiB`**（占 4 GiB 的 **`96.9%`**） | **`3,754.6 MiB`**（占 4 GiB 的 **`91.7%`**） | **峰值 VA 下降 `215.9 MiB`** |
| 距离 `4,095.9 MiB` 硬顶剩余裕量 | **仅剩 `125.4 MiB`**（极度脆弱） | **扩大至 `341.3 MiB`** | **安全裕量提升至 `2.72` 倍** |
| 采样峰值 `PrivateBytes` 提交量 | `3,352.5 MiB` | **`3,129.4 MiB`** | 私有内存提交减少 `223.1 MiB` |
| JSFL 关闭 `asLoader.xfl` 后驻留 `VirtualSize` | **`3,968.4 MiB`**（仅释放 `2.1 MiB`） | **`3,749.4 MiB`**（仅释放 `5.2 MiB`） | **实锤关闭文档不释放编译器 VA 池** |

**直接推论**：
1. 任何一轮 `asLoader` 发布结束后，该 `Flash.exe` 实例已驻留在 `3.75 GiB` 水位，**绝对不能**再承接下一轮 `asLoader` 编译或大型测试套件，否则必然撞击 `4,095.9 MiB` 硬顶崩溃。`scripts/compile_test.ps1` 据此引入了编译前 `VirtualSize` 水位自动轮换门（`asLoader` 阈值 `700 MiB`，其余目标 `2,400 MiB`）。
2. 在本机基准硬件上，冷编译 823 类 `asLoader` 实际耗时约 `605~805 s`；早期 `150~180 s` 超时建议对应的是 `1.04 MB` 时期的旧体量，过短的 `-TimeoutSeconds` 只会人为制造 `[TIMEOUT]` 与 `compile_state_uncertain.marker` 假故障。

---

## 5. 三道容量墙的工程边界：32K vs 64K vs 4 GiB

排查 CS6 编译故障时，必须严格区分以下三道完全不同层级的容量限制，避免误判药方：

| 限制名称 | 精确字节上限 | 作用粒度 | 底层格式原因 | 典型表征与治理归属 |
|----------|--------------|----------|--------------|--------------------|
| **32K 分支墙** | `32,767 Bytes` (`SI16`) | **单个 AS2 `class` 文件**总字节码（及超大 `if/switch/loop` 块） | AVM1 `ActionIf` (`0x9D`) / `ActionJump` (`0x99`) 跳转偏移量为**有符号 16 位整数**；CS6 将整个类定义包裹在 `DoInitAction` 的 `if (!_global.Pkg.Cls)` 条件跳转体内 | 编译器报 `branch exceeds 32K range`。<br>1) 真越界（类字节码 > 32 KB）：必须拆分类 / 委托静态 helper；<br>2) 贴墙类（`28~31.9 KB`）切 XFL 时偶发陈旧 `.aso` 假阳性：`compile_action.jsfl` 会同进程重试一次，但在 `asLoader` 3.75 GiB 水位下同进程重试极易触发 4 GiB OOM，应保持单类远离 28 KB 警戒线 |
| **64K 函数墙** | `65,535 Bytes` (`UI16`) | **单个函数或单帧脚本体**（如 `TestLoader` 聚合测试函数） | SWF `DefineFunction` / `DefineFunction2` 头部的 `codeSize` 字段为**无符号 16 位整数**，越界会静默截断或绕回 | 由 `node tools/swf-function-sizes.js --max 60000` 硬门拦截；超限时拆分测试 runner 或帧脚本 |
| **4 GiB 地址墙** | `4,095.9 MiB` (WoW64 LAA) | **整个 `Flash.exe` 进程**单次编译加载的全部类 AST 与符号表总和 | 32 位进程指针寻址上限 + 全局单例倍增池不随关文档释放 | 进程无报错直接消失或 `0xC0000005`（峰值 VA > `3.1 GiB`）。短期靠宿主冷轮换 + 去 `WIN7RTM` 维持约 `341 MiB` 余量；中长期若 `asLoader` 突破 ~880–900 类，必须通过“外置大脑”静态死代码清理与模块拆分减重 |

---

## 6. 其他开发机只读自检脚本（Host Fingerprint Probe）

换机或排查疑似 CS6 环境问题时，可在非管理员 PowerShell 中运行以下**纯只读**自检脚本，快速判断当前机器属于“标准免提权安装”还是“需提权兼容桥接安装”，并检查 VA 水位与 `.aso` 缓存健康度：

```powershell
chcp.com 65001 | Out-Null
$layersPaths = @(
    'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
)
Write-Host '=== 1. AppCompat Layers (Flash.exe) ==='
foreach ($lp in $layersPaths) {
    if (Test-Path $lp) {
        $props = Get-ItemProperty -Path $lp
        $props.PSObject.Properties | Where-Object { $_.Name -match 'Flash\.exe$' } | ForEach-Object {
            Write-Host ("[{0}] {1} = {2}" -f $lp, $_.Name, $_.Value)
        }
    }
}

Write-Host "`n=== 2. Scheduled Tasks (FlashCS6Task / CompileTriggerTask) ==="
foreach ($tn in @('FlashCS6Task', 'CompileTriggerTask')) {
    $t = Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue
    if ($null -eq $t) {
        Write-Host ("{0}: <NOT REGISTERED>" -f $tn)
    } else {
        $act = $t.Actions | Select-Object -First 1
        Write-Host ("{0}: State={1} | RunLevel={2} | Limit={3} | Execute={4} | Args={5}" -f
            $tn, $t.State, $t.Principal.RunLevel, $t.Settings.ExecutionTimeLimit, $act.Execute, $act.Arguments)
    }
}

Write-Host "`n=== 3. ASO Cache Health ==="
$asoBase = Join-Path $env:LOCALAPPDATA 'Adobe\Flash CS6'
if (Test-Path $asoBase) {
    $asoFiles = @(Get-ChildItem -Path $asoBase -Recurse -Filter '*.aso' -File -ErrorAction SilentlyContinue)
    $zeroFiles = @($asoFiles | Where-Object { $_.Length -eq 0 })
    Write-Host ("ASO total={0}, zero-byte={1}" -f $asoFiles.Count, $zeroFiles.Count)
    $zeroFiles | ForEach-Object { Write-Host ("  [ZERO-BYTE] {0} ({1})" -f $_.FullName, $_.LastWriteTime) }
}

Write-Host "`n=== 4. Live Flash.exe VA Telemetry ==="
Get-Process -Name Flash -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host ("PID={0} | Virtual={1:N1} MiB | PeakVirtual={2:N1} MiB / 4095.9 MiB | Private={3:N1} MiB | Responding={4}" -f
        $_.Id, ($_.VirtualMemorySize64 / 1MB), ($_.PeakVirtualMemorySize64 / 1MB), ($_.PrivateMemorySize64 / 1MB), $_.Responding)
}
```
