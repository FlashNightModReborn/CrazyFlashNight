# Flash 本地 SWF 信任与 Launcher 建连——trust 编码与 IPv6 loopback 踩坑

**类型**：Flash 平台行为实证 / 排障复盘
**触发**：测试员（中文深层安装路径 `F:\项目专用文件夹\旧的flash相关\...\CrazyFlashNight`）启动后卡在加载界面，launcher 反复 `socket_connect_timeout`；"别人没遇到"。
**结论先行**：真因是 **FlashPlayerTrust 配置文件编码**（无 BOM + 中文路径 + GBK 系统）导致 SWF 不受信、网络被静默拦截；另查出一个**真实但休眠**的 IPv4/IPv6 loopback 绑定隐患。两者都已修。本文记录排查链路、两个真坑、一个方法论陷阱，以及为何很多"看着对"的复现手段会骗人。

---

## 0. 症状与日志签名

每次启动固定死循环（节选自测试员 `launcher.log`）：

```
[XmlSocket] Listening on port 1924
[HTTP] Listening on port 1192
[FlashTrust] Lease acquired (created): C:\Users\<user>\AppData\Roaming\Macromedia\Flash Player\#Security\FlashPlayerTrust\cf7me.cfg
...
Guardian Flash Player started, PID=xxxx
Flash reparented to hidden host
LaunchFlow wait timeout: socket_connect_timeout   ← 10s 后必现
Flash Player exited, code=-1
```

关键观察：

- launcher 侧一切就绪（端口在听、trust 文件写出、WebView2/字体/地图都 OK）。
- Flash 进程**起得来、能 reparent**，但**从头到尾没有任何一条 socket 连接到达 1924**（状态停在 `WaitingConnect`，从未 `->WaitingHandshake`）。
- `[SolFileLocator] shareRoot missing: ...#SharedObjects`——这台机器 Flash 的 SharedObjects 根目录都不存在，说明它**从没成功跑通过任何 SWF**。

> **签名**：`socket_connect_timeout` + 服务端零连接 = "SWF 根本没能发起网络连接"。这是 **SWF 没拿到网络信任** 的通用签名——后面会看到 trust 失效和地址族错都会产生同一签名，所以单看这条不能区分病因。

---

## 1. 背景：本地 SWF 凭什么能连 socket

AS2 端建连链（`ServerManager.as`）：

```
读 launcher_ports.json(文件) → HTTP 探测 /testConnection → GET /getSocketPort → XMLSocket.connect("localhost", port)
```

其中 **HTTP 探测和 XMLSocket 都是"网络访问"**。Flash Player 的本地 SWF 默认落在 `local-with-filesystem` 沙箱——**能读本地文件，但禁止任何网络**。要让本地 SWF 能联网，必须把它提升到 `local-trusted`，途径就是 **FlashPlayerTrust**：在
`%APPDATA%\Macromedia\Flash Player\#Security\FlashPlayerTrust\` 下放一个 `.cfg`，里面逐行列出受信目录/文件路径。

Launcher 用租约模式自动写这个文件（`FlashTrustManager.EnsureTrust`，退出时 `RevokeTrust`）。所以**只要 trust 没真正生效，HTTP 和 socket 会一起失败**——读端口文件不受影响（那是文件访问），但 `connect()` 虽返回 true，实际不发包，`onConnect` 永不触发。

---

## 2. 真坑 A：trust 文件编码（本次真因）

`FlashTrustManager` 用 `File.WriteAllText(trustFile, projectRoot)` 写 `cf7me.cfg`。**.NET（Core/5+/10）默认编码是 UTF-8 无 BOM**。实测：

```
File.WriteAllText 写 "F:\项目专用文件夹\..." → 首字节 46 3A 5C E9 A1 B9 ...   (无 EF BB BF)
'项'  UTF-8 = E9 A1 B9        GBK(936) = CF EE
中文系统 ANSI 代码页(ACP) = 936
```

Adobe 的配置文件处理规则：**`.cfg` 没有 BOM 时按系统默认代码页解释**。于是在 GBK 系统上，trust 文件里的 `E9 A1 B9...`（UTF-8 字节）被当成 GBK 解码 → 乱码 → **受信路径字符串 ≠ 实际 SWF 路径** → SWF 仍是 `local-with-filesystem` → 网络全禁 → `socket_connect_timeout`。

**为何"别人没遇到"**：纯 ASCII 安装路径下，UTF-8 无 BOM 的字节和 ASCII 完全一致，Flash 不管按 UTF-8 还是 GBK 都读对。**只有路径含非 ASCII（中文）字符时这个 bug 才发作**。这条单变量完美解释了"中文路径机器中招、英文路径没事"。

### 修复

`cf7me.cfg` 改为**带 BOM 的 UTF-8** 写入（`new UTF8Encoding(true)`），让 Flash 在任何默认代码页下都按 UTF-8 正确解析路径。`CRAZYFLASHER7MercenaryEmpire.bat` 里那条 `echo`（chcp 65001 下同样是无 BOM）改用 PowerShell 带 BOM 幂等写入。另加"安装路径含非 ASCII → 启动告警"，万一某些 Flash 构建不认 BOM，至少不让用户卡 10s 循环里干瞪眼。

> **遗留**：BOM 对 FlashPlayerTrust 文件是否 100% 生效，只能在中文路径真机确认——本机是 ASCII 路径，天然测不出这一步。用户侧永远有兜底：**装到纯英文路径**。

---

## 3. 真坑 B：IPv4-only 绑定 vs `localhost`→`::1`（真实但休眠）

排查中查出第二个**独立、单独就能产生同样症状**的隐患：

- **XMLSocket 服务端**：`new TcpListener(IPAddress.Loopback, port)` = **仅 IPv4 127.0.0.1**。
- **HTTP 服务端**：`HttpListener` 前缀 `http://localhost:port/`——http.sys 对 "localhost" 是**双栈**，IPv4/IPv6 loopback 都收。
- **AS2**：HTTP 走 `http://localhost`，socket 走 `connect("localhost", port)`。
- **现代 Windows**：`localhost` 第一顺位解析到 **`::1`**（hosts 里 localhost 行默认注释，交 DNS 解析器，::1 优先）。实测本机 `Dns.GetHostAddresses("localhost")` 返回 `::1` 在前、`127.0.0.1` 在后。

.NET 层实验坐实了机制：

| 绑定 | 连 127.0.0.1 | 连 ::1 |
|---|---|---|
| `IPAddress.Loopback`（现状，仅 v4） | ✅ | ❌ |
| `IPv6Any` + `IPv6Only=0`（双栈） | ✅ | ✅ |

理论上：HTTP 探测能成（http.sys 双栈）→ AS2 推进到 socket → `connect("localhost")` 走 ::1 → 我们只在 127.0.0.1 上听 → 连不上 → 超时。看起来比 trust 更"硬"。

**但它是休眠的。** 决定性反证来自**本机自己的 launcher 日志**（本机 = ASCII 路径 + `localhost`→::1）：

```
Spawning -> WaitingConnect
WaitingConnect -> WaitingHandshake     ← socket 3 秒内连上
-> Embedding -> WaitingGameReady -> Ready
```

即：在一台 ::1-first 的机器上，真实游戏照样连上了仅-IPv4 的 socket。说明**真实 Flash Player 会回退 ::1→127.0.0.1**（或建连握手链路兜住了），那个绑定不对称并不咬人。这正是"代码上看着像、真系统能容忍"的典型。

### 加固（防御未知环境）

仍把 `XmlSocketServer` 改成**双 loopback 监听**：同时在 `127.0.0.1` 和 `::1` 上 accept，兼容"只试 ::1 不回退"的极端环境。**关键：用 `IPv6Loopback`(::1) 而非 `IPv6Any`(::)**——后者会把端口绑到所有接口、暴露到外网，破坏"仅本机"约束。IPv6 被禁用的系统自动降级为仅 IPv4。回归测试见 `launcher/tests/Bus/XmlSocketDualStackTests.cs`。

---

## 4. 排除项：Unicode 命令行（坑 C，未成立）

`ProcessManager` 用 `Process.Start` + `UseShellExecute=false`（= CreateProcessW），中文 SWF 路径按 UTF-16 正确传入。本机 SA 播放器跑中文……（本机 ASCII 路径）+ CreateProcessW 正确，故老 Flash SA "Unicode 命令行解析不可靠"这条优先级最低、本次不成立。仅在"老 Flash SA 内部用 ANSI argv"这一极窄假设下才会炸，可由 ASCII 路径实验间接排除。

---

## 5. 方法论陷阱：为什么很多"复现"会骗人

这次最贵的教训不在结论，而在**复现手段本身不可靠**。试图用本机隔离 #A/#B 时踩了一串：

1. **CS6 `testMovie` 的作者环境 socket 沙箱 ≠ 独立播放器**。testMovie 的 SWF 被作者环境**自动 local-trusted**；手动 `Adobe Flash Player 20.exe` 跑则靠 FlashPlayerTrust。两者沙箱行为不同，结论不能互推。
2. **裸 socket 桩复刻不了 Flash 的 socket policy 握手**。Flash XMLSocket 连任意端口前要 socket 策略文件：默认**先探 843 master policy**，失败再回退到目标端口内联请求 `<policy-file-request/>`。裸桩不应答、或被 843 探测 + 多路并发串行化污染，导致 `onConnect` 永不回、桩零连接——看着像"连不上"，其实是握手没走通。
3. **`System.security.loadPolicyFile` 反而把连接整个抑制**。加了它之后桩从"收到 1 个连接"变成"零连接"，是干扰项不是修复。
4. **debug player 写 trace、release projector 不写**。靠 `flashlog.txt` 判断时，分不清是没跑还是没 trace。
5. **手动写的 trust `.cfg` 可能根本没生效**——我手动跑 SA 播放器那次，连显式 `127.0.0.1` 对照都零连接，恰恰是"trust 没生效→网络静默全禁"，**反而精确复现了测试员的症状**，但对隔离 IPv6 毫无帮助。

> **铁律**：验证 launcher↔Flash 的**建连 / socket / trust** 问题，**不要**用 `compile_test`/`testMovie` 或裸 socket 桩。要用**真 launcher**（`--bus-only` / `tools/cfn-cli.sh`），它正确处理 policy 内联应答 + 写 trust，是唯一忠实的复现环境。最终定论也不是靠造实验，而是靠**读本机真 launcher 日志**直接看到成功建连。

---

## 6. 判别器（留给下次真机排障）

`/testConnection`、`/getSocketPort` 现在记入站日志，含**远端地址族**。在出故障的真机上一眼判病因：

- 两端点**被命中** → trust 已生效（SWF 能联网）→ 病因在 socket 层（查 #B / IPv6；尤其"HTTP 走 IPv6 而 socket 失败"就是 #B 现场签名）。
- 两端点**从没命中** → SWF 未受信（#A，多为中文路径 trust 编码）。

---

## 7. 一句话清单

- 本地 SWF 要联网 → 必须 FlashPlayerTrust 受信；trust 没生效的签名 = `connect()=true` 但服务端零连接 + `socket_connect_timeout`。
- trust `.cfg` **必须带 BOM**，否则非 ASCII 路径在 GBK 系统被读乱 → 受信失败（已固化进 `FlashTrustManager`）。
- `localhost` 在现代 Windows 优先 `::1`；仅-IPv4 绑定是真实隐患但**真 Flash 会回退**，故休眠。加固用 `::1` loopback，**绝不用 `IPv6Any`**。
- 复现 Flash↔launcher 连接问题只信**真 launcher**，不信 testMovie / 裸桩。
- 定病因优先**读真机日志**，其次才造实验。
