# 商城 WebView 迁移实施计划（v8）

## Context

K 点商城从 Flash MC 迁移到 WebView2 overlay。同时建立通用面板框架供未来复用。

用户决策：购物车逻辑在 JS 侧；放弃装备预览；图标用 manifest.json `_1` 帧。

## v5→v6 修正记录

| # | 问题 | 修正 |
|---|---|---|
| 17 | TrySend 只覆盖预检查断线，不覆盖 Write/Flush 间断线；OnSocketReconnected 补发后不检查成功 | 接受 check→write 微窗口不可解；补发改为 TrySend 循环（失败不清标志，等下次重连） |
| 18 | shopPanelOpen 不检查发送结果，WebView 打开但 Flash 未暂停 | 改为先 TrySend → 成功才开面板 → 失败则不开面板 |
| 19 | D8 force_close 未清 _pendingReq，迟到回调仍可能弹错误对话框 | onForceClose 清空 _pendingReq；所有 pending 回调入口加 `if(!Panels.isOpen()) return` 守卫 |
| 20 | GuardianForm.OnPanelStateChanged private + 无 _webOverlay 字段 | 改为 public HandlePanelStateChanged + 新增 SetWebOverlay；Program.cs 显式接线 |

## v4→v5 修正记录

| # | 问题 | 修正 |
|---|---|---|
| 13 | shopPanelClose fire-and-forget | SendGameCommand 返回 bool + _pauseNeedsRestore |
| 14 | 断连/重连回调未 marshal | BeginInvoke |
| 15 | D5 vs D8 冲突 | D8 传输层优先 |
| 16 | _panelOpen 所有权 | WebOverlayForm 独占 |

## v3→v4 修正记录

| # | 问题 | 修正 |
|---|---|---|
| 9 | requestClose 3s 强退与"SharedObject唯一源"矛盾 | 改为 retry/discard 对话框 |
| 10 | socket 断连后暂停不恢复 | C# 断连事件 + `_pauseNeedsRestore` + 重连补发 |
| 11 | jsonParser 是 private | 局部 `new FastJSON()` |
| 12 | saveCart qty 校验弱 | 与 checkout 统一 |

## 历史修正（v1→v3 累计）

| # | 问题 | 修正 |
|---|---|---|
| 1 | overlay.local 不映射 data/ | bulkQuery 从 Flash 获取，预留 gamedata.local |
| 2 | localStorage 购物车与 SharedObject 串档 | Flash SharedObject 为唯一源，JS 仅内存 |
| 3 | ESC 不可达（WS_EX_NOACTIVATE） | C# KeyboardHook 通道 |
| 4 | 全屏遮罩与面板外透传矛盾 | 真 modal 设计 |
| 5 | Tooltip 无坐标闭环 | JS 原生 tooltip |
| 6 | JS 上送 price 参与结算 | Flash 为结算权威，JS 只发 {idx, qty} |
| 7 | `>=` vs `>`、关闭不存盘、暂停覆盖 | 保留 `>`；完整 4 步清理；暂停 save/restore |
| 8 | `_root.服务器` 空壳 | `_root.server.sendSocketMessage()` |
| 9-prev | 线程安全、ESC 非全屏、关闭竞态、qty 校验、socket 断连、UiData 泄漏、重复 id | 见 v3 记录 |

---

## 架构总览

```
┌──── WebView2 (overlay.html) ────────────────────────────┐
│  panels.js     面板生命周期 + modal + 命中区域             │
│  icons.js      manifest.json → icon URL                  │
│  kshop.js      K点商城面板                                │
│  panels.css    面板容器 + kshop样式                       │
│  uidata.js     新增 off() 方法                           │
├──── 已有基建 ────────────────────────────────────────────┤
│  bridge.js / notch.js / currency.js 等                   │
└─────────────────────────────────────────────────────────┘
         ↕ postMessage / PostToWeb
┌──── C# Launcher ────────────────────────────────────────┐
│  WebOverlayForm.cs   "panel" 消息 + SHOP 降级 + ESC 分发  │
│  ShopTask.cs         双层callId + 断连检测 + UI线程marshal │
│  KeyboardHook.cs     新增 _panelEscEnabled 独立标志       │
│  GuardianForm.cs     面板开关时 enable/disable panel ESC  │
│  TaskRegistry.cs     注册 shop_response                  │
└─────────────────────────────────────────────────────────┘
         ↕ XmlSocket JSON
┌──── Flash AS2 ──────────────────────────────────────────┐
│  商城系统_WebView.as                                      │
│    shopPanelOpen   暂停 save/restore                     │
│    shopPanelClose  保存购物车 + 自动存盘 + 恢复暂停        │
│    shopBulkQuery   返回完整目录+元数据+当前状态            │
│    shopCheckout    Flash查价、校验qty>0、扣K点             │
│    shopClaim       Flash查找已购买项、领取                  │
│    shopSaveCart    保存购物车到SharedObject                 │
│  全部通过 _root.server.sendSocketMessage() 回包           │
└─────────────────────────────────────────────────────────┘
```

---

## 七大关键设计决策

### D1: 数据加载 — bulkQuery 从 Flash 获取

kshop.json 启动时已由 Flash 加载到 `_root.kshop_list`。WebView 通过 `shopBulkQuery` 命令获取完整目录+物品元数据（displayname、majorType、level 等），一次 round-trip 拿齐所有数据。不需要 WebView 单独 fetch JSON。

预留 `gamedata.local` 虚拟主机映射（`SetVirtualHostNameToFolderMapping("gamedata.local", dataDir, Allow)`）供未来面板直接访问 data/ 目录。

### D2: SKU 键 — 数组索引而非 id

kshop.json 有 16 组重复 id（同物品跨分类出现两次）。旧 Flash 的 `商城物品查询` 按 `item[0]`（id）first-match，有状态不一致隐患。

**WebView 方案**: bulkQuery 返回有序数组，**数组索引即 SKU 键**。购物车条目为 `{idx: Number, qty: Number}`。Flash 收到 checkout/claim 时按索引从 `_root.kshop_list` 取条目，索引唯一，无歧义。

```
catalog[0] = {idx:0, id:"S2017...", item:"the girl套装包", type:"特价商品", price:"20000", ...}
catalog[1] = {idx:1, ...}
...
catalog[261] = {idx:261, ...}
```

JS 购物车: `[{idx:3, qty:5}, {idx:100, qty:1}]`
Flash 收到后: `_root.kshop_list[3]` 反查价格和物品名。

### D3: 购物车持久化 — Flash SharedObject 为唯一源

- 打开面板 → Flash bulkQuery 返回当前 `_root.商城购物车`（旧格式）→ JS 转为 `[{idx, qty}]` 内存态
- 浏览/加购 → JS 内存修改
- 关闭面板 → JS 发 `saveCart` 给 Flash（含 `[{idx, qty}]`）→ Flash 重建数组写 SharedObject → **等 saveCart 响应后**才发 `close`
- 结账 → Flash 扣款 + 清空购物车 + 存盘
- 降级 → Flash 商城直接读同一 SharedObject

### D4: ESC 键 — 独立 `_panelEscEnabled` 标志

当前 ESC 拦截仅在全屏时启用（`_escEnabled`）。面板在非全屏下也需要 ESC 关闭。

**方案**: KeyboardHook 新增 `_panelEscEnabled` 标志，在 HookCallback 中：

```csharp
// 现有: Escape（全屏时）
if (vk == VK_ESCAPE && _escEnabled)
    shouldBlock = true;
// 新增: Escape（面板打开时）
if (vk == VK_ESCAPE && _panelEscEnabled)
    shouldBlock = true;
```

面板打开 → `SetPanelEscapeEnabled(true)` + 注册 ESC action 为面板关闭回调
面板关闭 → `SetPanelEscapeEnabled(false)` + 恢复 ESC action 为 `ToggleFullscreen`

**ESC action 优先级**: `_panelEscEnabled` 时 action 指向面板关闭；面板关闭后恢复原 action。两个 enabled 标志独立，不互相干扰。

**RegisterHotKey fallback**: 如果 KeyboardHook 安装失败，面板 ESC 功能不可用（可接受的降级——用户可点击遮罩关闭）。

### D5: 关闭链路 — 单入口 + 保存确认 + 无自动强退

**问题**: 遮罩点击、ESC、关闭按钮三路触发，加上 onClose 又发 saveCart 和 close，导致重复和竞态。v3 的 3s 强退会与"SharedObject 唯一源"矛盾，且迟到响应可二次 close。

**方案**: 统一为 `requestClose()` 单入口，**不设自动强退**：

```js
var _closing = false;
function requestClose() {
    if (_closing) return;  // 防重入
    _closing = true;
    // 1. 先保存购物车
    var cartPayload = _cart.map(function(c){ return {idx:c.idx, qty:c.qty}; });
    var reqId = 'wclose' + (++_reqSeq);
    _pendingReq[reqId] = function(resp) {
        delete _pendingReq[reqId]; // 确保只处理一次
        if (resp.success) {
            // 2. 保存成功 → 正式关闭
            doClose();
        } else {
            // 3. 保存失败 → 提示用户选择
            _closing = false;
            showSaveFailedDialog(resp.error);
            // 对话框按钮: "重试" → requestClose()  /  "放弃关闭" → 继续购物  /  "强制关闭(丢弃购物车)" → doClose()
        }
    };
    Bridge.send({type:'panel', cmd:'saveCart', callId:reqId, cart:cartPayload});
}

function doClose() {
    Panels.close();                                // 隐藏 DOM + 取消命中区域
    Bridge.send({type:'panel', cmd:'close'});      // 通知 C# → Flash shopPanelClose
    UiData.off('k', _kHandler);                    // 清理监听
    _closing = false;
}
```

**应用层错误场景处理**（D5 管辖，仅连接仍在时生效）:
- saveCart 响应 `success:false`（明确失败）→ 弹对话框：重试 / 放弃关闭（继续购物） / 强制关闭（丢弃购物车）
- saveCart 超时 `error:"timeout"`（状态未知：Flash 可能已落盘但回包丢失）→ 弹对话框：**仅** 重试 / 强制关闭。**不提供"继续购物"**，因为 JS 和 Flash 的购物车状态此时不一致

**传输层断连**（D8 管辖，优先级高于 D5）:
- socket 断连 → D8 直接 force_close，D5 流程被抢占（`_closing=false` 重置后 pending 回调无效）
- ShopTask 发送前检测断连返回 `error:"disconnected"` 时，D8 的 `OnSocketDisconnected` 几乎同时触发 → force_close 抢先执行 → D5 的 `_pendingReq` 回调到达时 panel 已关闭，`_closing=false`，静默丢弃

**无"迟到二次 close"**: `_pendingReq[reqId]` 只能触发一次（delete 后无法再匹配）。ShopTask 的 Timer 超时后也会 `_pending.Remove(fid)`，后续迟到的 Flash 响应找不到 fid → 静默丢弃。

Panels.js 的遮罩点击 → 调 `KShop.requestClose()`（不直接 close）
ESC → 调 `KShop.requestClose()`
关闭按钮 → 调 `KShop.requestClose()`

`Panels.close()` 本身不做业务逻辑，只负责 DOM 隐藏 + 命中区域更新。

### D6: 线程安全 — 全部经 BeginInvoke

KeyboardHook 回调在 ThreadPool（`KeyboardHook.cs:212`），XmlSocket 读循环在后台线程。所有到达 WebOverlayForm 的路径必须 marshal 到 UI 线程。

**ShopTask 修改**: `HandleFlashResponse` 被 MessageRouter 在 XmlSocket 线程调用。不直接调 PostToWeb，而是通过委托 `_invokeOnUI`：

```csharp
private Action<Action> _invokeOnUI;  // = form.BeginInvoke
public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

public void HandleFlashResponse(JObject msg, Action<string> respond)
{
    // ... 提取 webCallId ...
    string json = buildResponse(msg, webCallId);
    _invokeOnUI(() => _postToWeb(json));  // 确保 UI 线程
    respond(null);
}
```

**ESC 回调修改**: GuardianForm 注册的 ESC action 在 ThreadPool 执行。回调内用 `BeginInvoke`：

```csharp
_kbHook.RegisterAction(0x1B, delegate {
    // ThreadPool 线程 → marshal 到 UI 线程
    try { this.BeginInvoke(new Action(OnPanelEsc)); } catch { }
});

private void OnPanelEsc()
{
    _webOverlay?.PostToWeb("{\"type\":\"panel_esc\"}");
}
```

### D8: 面板状态所有权 + Socket 断连 + 发送确认

#### 状态所有权

**`_panelOpen` 由 WebOverlayForm 独占持有**。GuardianForm 通过回调 `_onPanelStateChanged(bool)` 获知变化（仅用于 ESC 键管理），不持有自己的副本。

```
WebOverlayForm._panelOpen          ← 唯一 source of truth
WebOverlayForm._pauseNeedsRestore  ← Flash 暂停补偿标志
GuardianForm                       ← 通过回调管理 ESC 键，不持有面板状态
```

#### 优先级规则：D8(传输层) > D5(应用层)

| 场景 | 处理方 | 行为 |
|---|---|---|
| saveCart 返回 `success:false`（连接仍在） | D5 | 弹 retry/discard 对话框 |
| saveCart 返回 `error:"timeout"`（10s超时，连接状态未知） | D5 | 弹对话框（重试/强制关闭） |
| Socket 传输层断连（任何时刻） | **D8** | **立即强关面板，无对话框** |
| D5 对话框正在显示时 socket 断连 | **D8 抢占 D5** | 强关面板，对话框随面板 DOM 一起消失 |

D8 强关时设置 JS `_closing = false`，使得任何 D5 的 pending 回调即使迟到也不会再触发关闭。

#### TrySendGameCommand（M5: 新增方法，不修改现有 void SendGameCommand 签名）

见下方「补充设计点 M5」的完整定义。现有 `SendGameCommand` 保持 void 不变，面板代码使用 `TrySendGameCommand`。

HandlePanelMessage("close") 使用 TrySendGameCommand 返回值：
```csharp
case "close":
    if (!TrySendGameCommand("shopPanelClose"))
        _pauseNeedsRestore = true;  // 发送失败，记录待恢复
    _panelOpen = false;
    _onPanelStateChanged?.Invoke(false);
    break;
```

#### Socket 断连事件（C1: generation 守卫）

**需新增**: `XmlSocketServer.OnClientDisconnected` 事件。**必须在 `_generation == gen` 守卫内触发**（XmlSocketServer.cs:191），否则过期 ReadLoop 退出会触发虚假断连事件。

```csharp
// XmlSocketServer.cs
public event Action OnClientDisconnected;  // 新增

// ReadLoop 末尾 (line 188-195)，修改为:
lock (_clientLock)
{
    if (_generation == gen)  // 仅当前连接的 ReadLoop 才触发
    {
        CloseClientLocked();
        Action dcHandler = OnClientDisconnected;
        if (dcHandler != null) { try { dcHandler(); } catch {} }
    }
    // else: 过期 ReadLoop 退出，静默，不触发事件
}
```

#### WebOverlayForm 断连/重连处理

**全部经 BeginInvoke marshal 到 UI 线程**（ReadLoop 在后台线程触发事件）：

```csharp
// WebOverlayForm.cs
private bool _panelOpen;
private bool _pauseNeedsRestore;

public void OnSocketDisconnected()
{
    // 后台线程 → marshal
    if (this.InvokeRequired) { try { this.BeginInvoke(new Action(OnSocketDisconnected)); } catch {} return; }

    if (_panelOpen)
    {
        PostToWeb("{\"type\":\"panel_cmd\",\"cmd\":\"force_close\",\"reason\":\"disconnected\"}");
        _panelOpen = false;
        _onPanelStateChanged?.Invoke(false);
        _pauseNeedsRestore = true;
    }
}

public void OnSocketReconnected()
{
    // 后台线程 → marshal
    if (this.InvokeRequired) { try { this.BeginInvoke(new Action(OnSocketReconnected)); } catch {} return; }

    if (_pauseNeedsRestore)
    {
        // TrySend: 仅在发送成功时才清标志，失败则等下次重连重试
        if (TrySendGameCommand("shopPanelClose"))
            _pauseNeedsRestore = false;
        // else: 标志保留，下次 OnClientReady 会再次尝试
    }
}
```

Program.cs 接入：
```csharp
socketServer.OnClientDisconnected += webOverlay.OnSocketDisconnected;
socketServer.OnClientReady += webOverlay.OnSocketReconnected;
```

#### JS 侧 force_close + pending 清理

`panel_cmd` 的 `force_close` 分支已在 panels.js IIFE 内部处理（调用 `close()` + `KShop.onForceClose()`）。

KShop.onForceClose 必须清理所有 pending 状态。**C2: 必须在 IIFE return 中导出**：
```js
// KShop IIFE 内部
function onForceClose() {
    _pendingReq = {};      // 清空所有 pending 回调，迟到响应无处投递
    _closing = false;       // 重置关闭锁
    UiData.off('k', _kHandler);
    if (typeof Toast !== 'undefined') Toast.add('连接断开，商城已关闭');
}

// IIFE return 中:
return { requestClose: requestClose, onForceClose: onForceClose };
```

**所有 pending 回调入口加守卫**（防止 force_close 与迟到响应竞态）：
```js
_pendingReq[reqId] = function(resp) {
    if (!Panels.isOpen()) return;  // 面板已被强关，丢弃迟到响应
    delete _pendingReq[reqId];
    // ... 业务逻辑
};
```

#### 完整关闭链路矩阵

| 触发源 | saveCart | shopPanelClose | _pauseNeedsRestore | 用户感知 |
|---|---|---|---|---|
| 正常关闭(ESC/遮罩/按钮) | ✓ 等响应 | 成功后发 | 仅发送失败时设 | 无感 |
| saveCart 失败(连接在) | ✓ 弹对话框 | 用户选重试/放弃后 | 视发送结果 | retry/discard 对话框 |
| Socket 断连(面板开着) | ✗ 跳过 | ✗ 发不出 | ✓ 设 true | 面板消失 + toast |
| doClose 时 Send 失败 | ✓ 已完成 | ✗ Send 返回 false | ✓ 设 true | 无感(重连后恢复) |
| 重连 | — | ✓ 补发 | ✓ 清除 | 无感 |

### D9: JSON 序列化 — 局部 FastJSON 实例

`ServerManager.jsonParser` 是 `private`（ServerManager.as:75）。虽然 AS2 运行时不强制 private，但依赖未公开成员不稳妥。

**方案**: 在 `商城系统_WebView.as` 顶部创建独立 FastJSON 实例：

```actionscript
var _shopJson:FastJSON = new FastJSON();

// 所有回包使用 _shopJson.stringify(resp) 代替 _root.server.jsonParser.stringify(resp)
// 发送: _root.server.sendSocketMessage(_shopJson.stringify(resp))
```

FastJSON 是 public class，无外部依赖，可安全实例化。

### D7: 结算安全 — Flash 全权威 + qty 校验

JS 发 `{idx, qty}` → Flash 按 idx 从 `_root.kshop_list` 查条目取价格。

```actionscript
// qty 校验
var qty = Number(items[i].qty);
if (isNaN(qty) || qty <= 0 || qty != Math.floor(qty)) continue; // 跳过无效
```

保持原始 `>` 运算符（`虚拟币 > total`）。

---

## 实施步骤

### Step 1: UiData.off + 基建准备

**修改:** `launcher/web/modules/uidata.js`

新增 `off` 方法（~8行）：

```js
function off(key, handler) {
    if (!handlers[key]) return;
    for (var i = handlers[key].length - 1; i >= 0; i--) {
        if (handlers[key][i] === handler) {
            handlers[key].splice(i, 1);
            break;
        }
    }
}
// 导出
return { on: on, off: off, onLegacy: onLegacy, dispatch: dispatch };
```

KShop 在 `onOpen` 注册、`close` 时反注册，防止监听泄漏。

---

### Step 2: 面板框架

**新建:** `launcher/web/modules/panels.js`

```js
var Panels = (function() {
    var _registry = {};
    var _active = null;
    var _container, _backdrop, _content;

    function init() {
        _container = document.getElementById('panel-container');
        _backdrop  = document.getElementById('panel-backdrop');
        _content   = document.getElementById('panel-content');
        _backdrop.addEventListener('click', function() { triggerRequestClose(); });
    }

    function open(id, initData) {
        if (_active === id) return;
        if (_active) close();
        var panel = _registry[id];
        if (!panel) return;
        if (!panel._el) {
            panel._el = panel.create(_content);
            _content.appendChild(panel._el);
        }
        panel._el.style.display = '';
        _container.style.display = '';
        if (panel.onOpen) panel.onOpen(panel._el, initData);
        _active = id;
        setTimeout(function() {
            if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
        }, 50);
    }

    // close() 纯 DOM 操作，不做业务逻辑
    function close() {
        if (!_active) return;
        var panel = _registry[_active];
        if (panel && panel._el) panel._el.style.display = 'none';
        _container.style.display = 'none';
        _active = null;
        setTimeout(function() {
            if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
        }, 50);
    }

    // ESC / 遮罩点击 → 通知当前面板的 onRequestClose
    function triggerRequestClose() {
        if (_active && _registry[_active] && _registry[_active].onRequestClose) {
            _registry[_active].onRequestClose();
        }
    }

    // C# 指令 — IIFE 内部注册，直接访问内部变量（仅注册一次）
    Bridge.on('panel_cmd', function(data) {
        if (data.cmd === 'open') open(data.panel, data.initData);
        else if (data.cmd === 'close') close();
        else if (data.cmd === 'force_close') {
            close();
            if (typeof KShop !== 'undefined') KShop.onForceClose();
        }
    });
    Bridge.on('panel_esc', triggerRequestClose);

    return {
        register: function(id, opts) { _registry[id] = opts; },
        open: open, close: close,
        isOpen: function() { return _active !== null; },
        getActive: function() { return _active; },
        getHitRects: function(pushRect) {
            if (_active && _container && _container.style.display !== 'none') pushRect(_container);
        },
        init: init
    };
})();
```

**新建:** `launcher/web/modules/icons.js` — 完整代码见下方「补充设计点 H2」。

**新建:** `launcher/web/css/panels.css`

```css
#panel-container { position:fixed; inset:0; z-index:1000; display:none; pointer-events:auto; }
#panel-backdrop  { position:absolute; inset:0; background:rgba(0,0,0,0.55); }
#panel-content   { position:absolute; inset:5% 8%; z-index:1; display:flex; flex-direction:column;
                   pointer-events:auto; }
#panel-tooltip   { position:fixed; z-index:1100; pointer-events:none; display:none;
                   background:rgba(20,20,24,0.95); border:1px solid rgba(255,255,255,0.15);
                   border-radius:6px; padding:8px 12px; color:#ddd; font-size:13px;
                   max-width:280px; }
```

**修改:** `launcher/web/overlay.html`

在 `</body>` 前追加 DOM：
```html
<div id="panel-container" style="display:none">
  <div id="panel-backdrop"></div>
  <div id="panel-content"></div>
</div>
<div id="panel-tooltip"></div>
```

CSS 引用（overlay.css 之后）：`<link rel="stylesheet" href="css/panels.css">`

JS 引用（combo.js 之后）：
```html
<script src="modules/panels.js"></script>
<script src="modules/icons.js"></script>
<script src="modules/kshop.js"></script>
```

load 事件追加 init：
```js
window.addEventListener('load', function() {
    Panels.init();
    Bridge.send({ type: 'ready' });
});
```

**修改:** `launcher/web/modules/notch.js` — `reportRect()` 函数

在 **notch.js:323**（`var ghm = ...` 和 `if (ghm && ghm.classList...` 之后）、**324 行** `Bridge.send({ type: 'interactiveRect', r: rects })` **之前**，插入：
```js
        // 面板系统命中区域
        if (typeof Panels !== 'undefined') Panels.getHitRects(pushRect);
```

---

### Step 3: C# 通信层

#### `launcher/src/Tasks/ShopTask.cs` (新建, ~200行)

核心要点：
- 双层 callId 映射 (`Dictionary<int, string> _pending`)
- 发送前检查 `_socket.IsClientReady`，不满足立即返回错误
- `HandleFlashResponse` 经 `_invokeOnUI` marshal 到 UI 线程再 PostToWeb
- 10s 超时 Timer，超时后 marshal 到 UI 线程返回错误
- **H1: `_disposed` 标志 + `Dispose()` 方法**，防止应用退出后 Timer 回调触发 BeginInvoke 异常

```csharp
public class ShopTask : IDisposable
{
    private readonly XmlSocketServer _socket;
    private Action<string> _postToWeb;
    private Action<Action> _invokeOnUI;
    private readonly Dictionary<int, string> _pending;
    private readonly Dictionary<int, Timer> _timers;
    private int _seq;
    private readonly object _lock = new object();
    private volatile bool _disposed;

    public ShopTask(XmlSocketServer socket) { _socket = socket; _pending = new ...; _timers = new ...; }
    public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
    public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

    public void Dispose()
    {
        _disposed = true;
        lock (_lock) { foreach (var t in _timers.Values) t.Dispose(); _timers.Clear(); _pending.Clear(); }
    }

    public void HandleWebRequest(string cmd, JObject parsed)
    {
        string webCallId = parsed.Value<string>("callId");
        if (string.IsNullOrEmpty(webCallId)) return;

        // 断连检测
        if (!_socket.IsClientReady)
        {
            RespondOnUI(webCallId, "{\"success\":false,\"error\":\"disconnected\"}");
            return;
        }

        int fid;
        lock (_lock) { fid = ++_seq; _pending[fid] = webCallId; }

        // 超时
        var timer = new Timer(_ => {
            if (_disposed) return;  // H1: 应用退出后不触发
            string wid;
            lock (_lock) {
                if (!_pending.TryGetValue(fid, out wid)) return;
                _pending.Remove(fid); _timers.Remove(fid);
            }
            RespondOnUI(wid, "{\"success\":false,\"error\":\"timeout\"}");
        }, null, 10000, Timeout.Infinite);
        lock (_lock) { _timers[fid] = timer; }

        // 构造 Flash 命令
        string action = "shop" + char.ToUpper(cmd[0]) + cmd.Substring(1);
        var flashMsg = new JObject();
        flashMsg["task"] = "cmd";
        flashMsg["action"] = action;
        flashMsg["callId"] = fid;
        // 复制 payload 字段（cart, idx 等）
        foreach (var prop in parsed.Properties())
        {
            if (prop.Name != "type" && prop.Name != "cmd" && prop.Name != "callId")
                flashMsg[prop.Name] = prop.Value;
        }
        _socket.Send(flashMsg.ToString(Formatting.None) + "\0");
    }

    // MessageRouter 在 XmlSocket 线程调用
    public void HandleFlashResponse(JObject msg, Action<string> respond)
    {
        int fid = msg.Value<int>("callId");
        string wid;
        lock (_lock) {
            if (!_pending.TryGetValue(fid, out wid)) { respond(null); return; }
            _pending.Remove(fid);
            Timer t; if (_timers.TryGetValue(fid, out t)) { t.Dispose(); _timers.Remove(fid); }
        }
        msg.Remove("task");
        msg["type"] = "panel_resp";
        msg["callId"] = wid;
        string json = msg.ToString(Formatting.None);
        _invokeOnUI(() => _postToWeb(json));  // marshal 到 UI 线程
        respond(null);
    }

    private void RespondOnUI(string webCallId, string body)
    {
        var obj = JObject.Parse(body);
        obj["type"] = "panel_resp";
        obj["callId"] = webCallId;
        string json = obj.ToString(Formatting.None);
        _invokeOnUI(() => _postToWeb(json));
    }
}
```

#### `launcher/src/Guardian/WebOverlayForm.cs` (修改)

1. 新增字段：
   ```csharp
   private ShopTask _shopTask;
   private Action<bool> _onPanelStateChanged;
   ```

2. 新增方法：
   ```csharp
   public void SetShopTask(ShopTask task) {
       _shopTask = task;
       task.SetPostToWeb(PostToWeb);
       task.SetInvoker(a => { try { this.BeginInvoke(a); } catch {} });
   }
   public void SetPanelStateCallback(Action<bool> cb) { _onPanelStateChanged = cb; }
   ```

3. `OnWebMessageReceived` 新增 `"panel"` 分支

4. `HandlePanelMessage`:
   ```csharp
   private void HandlePanelMessage(string json)
   {
       JObject parsed;
       try { parsed = JObject.Parse(json); } catch { return; }
       string cmd = parsed.Value<string>("cmd");
       if (cmd == null) return;
       switch (cmd)
       {
           case "close":
               if (!TrySendGameCommand("shopPanelClose"))
                   _pauseNeedsRestore = true;  // 发送失败，重连后补发
               _panelOpen = false;
               _onPanelStateChanged?.Invoke(false);
               break;
           case "bulkQuery":
           case "checkout":
           case "claim":
           case "saveCart":
               _shopTask?.HandleWebRequest(cmd, parsed);
               break;
       }
   }
   ```

5. `HandleButtonClick("SHOP")`:
   ```csharp
   case "SHOP":
       if (_webFailed)
           SendGameCommand("openShop");
       else
       {
           // 先确认 Flash 能收到暂停指令，再开面板
           if (TrySendGameCommand("shopPanelOpen"))
           {
               PostToWeb("{\"type\":\"panel_cmd\",\"cmd\":\"open\",\"panel\":\"kshop\"}");
               _panelOpen = true;
               _onPanelStateChanged?.Invoke(true);
           }
           // else: socket 不可用，不开面板（用户会看到按钮无反应，可接受的降级）
       }
       break;
   ```

#### `launcher/src/Guardian/KeyboardHook.cs` (修改)

新增独立标志：
```csharp
private volatile bool _panelEscEnabled;  // 与 _escEnabled 独立

public void SetPanelEscapeEnabled(bool enabled) { _panelEscEnabled = enabled; }
```

HookCallback 中追加判断（在现有 ESC 判断之后）：
```csharp
if (vk == VK_ESCAPE && _panelEscEnabled)
    shouldBlock = true;
```

#### `launcher/src/Guardian/GuardianForm.cs` (修改)

新增字段和方法：
```csharp
private WebOverlayForm _webOverlay;  // 新增

public void SetWebOverlay(WebOverlayForm overlay) { _webOverlay = overlay; }  // 新增

/// <summary>
/// 面板状态变化回调（由 WebOverlayForm 调用，可能来自任意线程）。
/// </summary>
public void HandlePanelStateChanged(bool open)  // 新增, public
{
    if (this.InvokeRequired) { try { this.BeginInvoke(new Action<bool>(HandlePanelStateChanged), open); } catch {} return; }

    if (open)
    {
        if (_kbHook != null)
        {
            _kbHook.SetPanelEscapeEnabled(true);
            _kbHook.RegisterAction(0x1B, delegate {
                // KeyboardHook 回调在 ThreadPool → marshal 到 UI 线程
                try { this.BeginInvoke(new Action(() => {
                    _webOverlay?.PostToWeb("{\"type\":\"panel_esc\"}");
                })); } catch {}
            });
        }
    }
    else
    {
        if (_kbHook != null)
        {
            _kbHook.SetPanelEscapeEnabled(false);
            // 恢复 ESC 原始行为
            _kbHook.RegisterAction(0x1B, delegate { ToggleFullscreen(); });
        }
    }
}
```

#### Program.cs 接线（完整）

```csharp
// 实例化
ShopTask shopTask = new ShopTask(socketServer);

// WebOverlayForm 依赖注入
webOverlay.SetShopTask(shopTask);
webOverlay.SetPanelStateCallback(guardianForm.HandlePanelStateChanged);

// GuardianForm 依赖注入
guardianForm.SetWebOverlay(webOverlay);

// Socket 事件订阅
socketServer.OnClientDisconnected += webOverlay.OnSocketDisconnected;
socketServer.OnClientReady += webOverlay.OnSocketReconnected;

// TaskRegistry 注册
TaskRegistry.RegisterAll(router, ..., shopTask);
```

#### `launcher/src/Bus/TaskRegistry.cs` (修改)
- `RegisterAll` 签名追加 `ShopTask shopTask`
- `router.RegisterAsync("shop_response", shopTask.HandleFlashResponse);`

#### `launcher/src/Program.cs` (修改)
完整接线见 Step 3 「Program.cs 接线（完整）」代码块。

---

### Step 4: Flash 侧命令

**新建:** `scripts/逻辑系统分区/商城系统_WebView.as` (UTF-8 BOM)

```actionscript
// JSON 序列化器（不依赖 ServerManager 私有 jsonParser）
var _shopJson:FastJSON = new FastJSON();

// ========== 面板暂停 save/restore ==========
_root._shopPrevPause = undefined;

_root.gameCommands["shopPanelOpen"] = function(params) {
    _root._shopPrevPause = _root.暂停;
    _root.暂停 = true;
};

_root.gameCommands["shopPanelClose"] = function(params) {
    // 复刻 关闭商城() 的完整清理链
    // 保存购物车: 已由 saveCart 命令在 close 前执行
    // 自动存盘:
    _root.自动存盘();
    // 恢复暂停:
    if (_root._shopPrevPause !== undefined) {
        _root.暂停 = _root._shopPrevPause;
        _root._shopPrevPause = undefined;
    }
};

// ========== 批量查询 ==========
_root.gameCommands["shopBulkQuery"] = function(params) {
    var callId = params.callId;
    var catalog = [];
    for (var i = 0; i < _root.kshop_list.length; i++) {
        var entry = _root.kshop_list[i];
        var itemData = org.flashNight.arki.item.ItemUtil.getItemData(entry.item);
        var attrs = _root.根据物品名查找全部属性(entry.item);
        if (itemData != undefined && attrs != undefined) {
            catalog.push({
                idx:         i,   // ← 数组索引即 SKU 键
                id:          entry.id,
                item:        entry.item,
                type:        entry.type,
                price:       entry.price,
                displayname: String(itemData.displayname || entry.item),
                majorType:   String(attrs[2]),
                subType:     String(attrs[3]),
                level:       Number(attrs[9]),
                icon:        String(attrs[1])
            });
        }
    }
    // 将旧格式购物车转为 idx 格式
    var cartMigrated = [];
    for (var c = 0; c < _root.商城购物车.length; c++) {
        var cartItem = _root.商城购物车[c];
        // 旧格式 [id, name, type, price, qty] → 找 idx
        for (var k = 0; k < _root.kshop_list.length; k++) {
            if (_root.kshop_list[k].id == cartItem[0]
            && (_root.kshop_list[k].type == cartItem[2] || cartItem[2] == undefined)) { // M2: type 二次确认
                cartMigrated.push({idx: k, qty: Number(cartItem[cartItem.length - 1])});
                break;
            }
        }
    }
    var resp = {
        task: "shop_response", callId: callId, success: true,
        catalog: catalog,
        playerLevel: Number(_root.等级),
        reverseLevel: Number(_root.主角被动技能.逆向.启用 ? _root.主角被动技能.逆向.等级 : 0),
        kpoints: Number(_root.虚拟币),
        cart: cartMigrated,
        purchased: _root.商城已购买物品
    };
    _root.server.sendSocketMessage(_shopJson.stringify(resp));
};

// ========== 结账 ==========
_root.gameCommands["shopCheckout"] = function(params) {
    var items = params.cart; // [{idx:3, qty:5}, ...]
    var callId = params.callId;
    var total = 0;
    var resolved = [];

    for (var i = 0; i < items.length; i++) {
        var idx = Number(items[i].idx);
        var qty = Number(items[i].qty);
        // 安全校验
        if (isNaN(idx) || idx < 0 || idx >= _root.kshop_list.length) continue;
        if (isNaN(qty) || qty <= 0 || qty != Math.floor(qty)) continue;
        var entry = _root.kshop_list[idx];
        total += Number(entry.price) * qty;
        resolved.push([entry.id, entry.item, entry.type, entry.price, qty]);
    }

    var resp = { task: "shop_response", callId: callId };
    if (_root.虚拟币 > total) {   // 保持原始 > 语义
        _root.虚拟币 -= total;
        for (var j = 0; j < resolved.length; j++) {
            _root.商城已购买物品.push(resolved[j]);
        }
        _root.存盘商城已购买物品();
        _root.清空购物车();
        _root.保存购物车();
        _root.soundEffectManager.playSound("收银机.mp3");
        resp.success = true;
        resp.newBalance = _root.虚拟币;
        resp.purchased = _root.商城已购买物品;
    } else {
        resp.success = false;
        resp.error = "insufficient_kpoints";
        resp.balance = _root.虚拟币;
    }
    _root.server.sendSocketMessage(_shopJson.stringify(resp));
};

// ========== 领取 ==========
_root.gameCommands["shopClaim"] = function(params) {
    var claimIdx = params.purchasedIdx; // 已购买列表中的索引
    var callId = params.callId;
    var resp = { task: "shop_response", callId: callId };

    if (claimIdx < 0 || claimIdx >= _root.商城已购买物品.length) {
        resp.success = false; resp.error = "item_not_found";
    } else {
        var item = _root.商城已购买物品[claimIdx];
        var itemName = item[1];
        var qty = Number(item[item.length - 1]);  // S1: 与旧代码模式一致
        if (isNaN(qty) || qty <= 0) qty = 1;

        if (_root.物品栏.背包.getFirstVacancy() == -1) {
            resp.success = false; resp.error = "inventory_full";
        } else if (org.flashNight.arki.item.ItemUtil.singleAcquire(itemName, qty)) {
            _root.商城已购买物品.splice(claimIdx, 1);
            _root.存盘商城已购买物品();
            resp.success = true;
            resp.purchased = _root.商城已购买物品;
        } else {
            resp.success = false; resp.error = "acquire_failed";
        }
    }
    _root.server.sendSocketMessage(_shopJson.stringify(resp));
};

// ========== 保存购物车 ==========
_root.gameCommands["shopSaveCart"] = function(params) {
    var cart = params.cart; // [{idx, qty}, ...]
    var callId = params.callId;
    _root.商城购物车 = [];
    for (var i = 0; i < cart.length; i++) {
        var idx = Number(cart[i].idx);
        var qty = Number(cart[i].qty);
        if (isNaN(idx) || idx < 0 || idx >= _root.kshop_list.length) continue;
        if (isNaN(qty) || qty <= 0 || qty != Math.floor(qty)) continue; // 与 checkout 统一校验
        var entry = _root.kshop_list[idx];
        _root.商城购物车.push([entry.id, entry.item, entry.type, entry.price, qty]);
    }
    _root.保存购物车();
    var resp = { task: "shop_response", callId: callId, success: true };
    _root.server.sendSocketMessage(_shopJson.stringify(resp));
};
```

**加载链**: 搜索 `商城系统_兼容.as` 的 `#include` 位置，在其后追加。实现时用 grep 定位。

**待确认**: `_root.server` 是否为 ServerManager 单例引用（通信_fs_本地服务器.as:10 赋值 `_root.server = ServerManager.getInstance()`）。

---

### Step 5: K 点商城 UI

**新建:** `launcher/web/modules/kshop.js` (~400行)

注册面板：
```js
Panels.register('kshop', {
    create: function(container) { /* 构建 DOM */ },
    onOpen: function(el, initData) { /* 请求 bulkQuery, 渲染 */ },
    onRequestClose: function() { KShop.requestClose(); }
    // 注意: 无 onClose。关闭逻辑由 requestClose 控制
});
```

数据模型与 D2/D3/D5 一致。

K 点监听生命周期：
```js
var _kHandler = function(v) { _kpoints = Number(v); updateBalance(); };
// onOpen:
UiData.on('k', _kHandler);
// close (在 requestClose 的 Panels.close() 后):
UiData.off('k', _kHandler);
```

Tooltip: JS 原生 `#panel-tooltip`，hover 时填充元数据并跟随光标。

非卖品: `type === '非卖品'` → 隐藏购买按钮/+−按钮，仅展示。

分类: 从 catalog 动态提取 unique type 列表（避免硬编码 15 个分类名）。

---

### Step 6: 编译 + 集成验证

1. AS2 文件写入后 `python -c "..."` 确认 BOM
2. 定位 `#include` 加载链，追加新文件
3. `bash scripts/compile_test.sh` 编译 Flash
4. `dotnet build` 编译 Launcher
5. 端到端测试

---

## 关键文件清单

| 文件 | 操作 |
|---|---|
| `launcher/web/modules/panels.js` | 新建 |
| `launcher/web/modules/icons.js` | 新建 |
| `launcher/web/modules/kshop.js` | 新建 |
| `launcher/web/css/panels.css` | 新建 |
| `launcher/src/Tasks/ShopTask.cs` | 新建 |
| `scripts/逻辑系统分区/商城系统_WebView.as` | 新建 |
| `launcher/web/modules/uidata.js` | 修改（+off 方法） |
| `launcher/web/overlay.html` | 修改（+DOM +CSS +JS引用 +init） |
| `launcher/web/modules/notch.js` | 修改（reportRect 1行） |
| `launcher/src/Guardian/WebOverlayForm.cs` | 修改 |
| `launcher/src/Guardian/KeyboardHook.cs` | 修改（+_panelEscEnabled） |
| `launcher/src/Guardian/GuardianForm.cs` | 修改（+ESC管理） |
| `launcher/src/Bus/TaskRegistry.cs` | 修改 |
| `launcher/src/Bus/XmlSocketServer.cs` | 修改（+OnClientDisconnected 事件） |
| `launcher/src/Program.cs` | 修改 |
| 帧脚本加载链 | 修改（#include 1行） |

## 补充设计点

### H2: icons.js 完整方案

```js
var Icons = (function() {
    var _map = null, _loading = false, _queue = [];
    return {
        load: function(cb) {
            if (_map) { cb(); return; }
            _queue.push(cb);
            if (_loading) return;
            _loading = true;
            // manifest.json 约 180KB，通过 overlay.local 虚拟主机加载（同域，无 CORS）
            fetch('icons/manifest.json')
                .then(function(r) { return r.json(); })
                .then(function(d) { _map = d; for (var i = 0; i < _queue.length; i++) _queue[i](); _queue = []; })
                .catch(function() { _map = {}; for (var i = 0; i < _queue.length; i++) _queue[i](); _queue = []; });
        },
        // 返回 icon URL 或 null（调用方显示占位图/空白）
        resolve: function(name) {
            if (!_map || !_map[name] || !_map[name].f1) return null;
            return 'icons/' + _map[name].f1;
        }
    };
})();
```

manifest.json 结构：`{"物品名": {"f1": "hash_1.png", "f2": "hash_2.png"}, ...}`，仅使用 `f1`。
图标文件位于 `launcher/web/icons/`，通过 `overlay.local` 虚拟主机服务。
图标缺失时 `resolve` 返回 `null`，商品卡片中 `<img>` 设 `onerror` 隐藏或显示占位色块。

### M1: bulkQuery 跳过无效商品的处理

bulkQuery 中 `if (itemData != undefined && attrs != undefined)` 会静默跳过无法查询到属性的商品。WebView 收到的 catalog 长度可能 < 262。

**处理**: JS 侧按收到的 catalog 渲染，不假设与 kshop.json 长度一致。若实现时发现有商品被跳过，在 Flash trace 中记录警告以便排查数据问题。

### M2: 购物车迁移 first-match 对重复 ID 的处理

旧购物车按 id first-match 查找 idx。16 组重复 id 中所有条目都是同名同价（仅分类不同），first-match 映射到的条目与用户预期一致（价格相同）。

**额外保护**: 迁移时比较 `kshop_list[k].type == cartItem[2]` 做二次确认，不匹配则回退到 first-match。

### M3: CSS z-index 确认

已确认 overlay.css 中最高 z-index 为 200。`#panel-container` 使用 `z-index:1000`，`#panel-tooltip` 使用 `z-index:1100`，不冲突。

### M4: SHOP 按钮发送失败时的用户反馈

shopPanelOpen 发送失败时，在 C# 侧添加 toast 提示：

```csharp
case "SHOP":
    if (_webFailed)
        SendGameCommand("openShop");
    else if (!TrySendGameCommand("shopPanelOpen"))
        SendToast("商城暂时不可用");  // M4: 用户反馈
    else { ... }
    break;
```

### M5: TrySendGameCommand 而非修改现有签名

新增独立方法，不改动现有 `SendGameCommand` 的 void 签名（零影响现有调用方）：

```csharp
private bool TrySendGameCommand(string action)
{
    if (_socketServer == null || !_socketServer.IsClientReady) return false;
    _socketServer.Send("{\"task\":\"cmd\",\"action\":\"" + action + "\"}\0");
    return true;
}
private bool TrySendGameCommand(string action, string extraJsonFields)
{
    if (_socketServer == null || !_socketServer.IsClientReady) return false;
    _socketServer.Send("{\"task\":\"cmd\",\"action\":\"" + action + "\"," + extraJsonFields + "}\0");
    return true;
}
```

面板相关代码使用 `TrySendGameCommand`，其他现有调用方不受影响。

### S1: shopClaim 数量取法

```actionscript
var qty = Number(item[item.length - 1]);  // 与旧代码模式一致，不硬编码 item[4]
```

### S2: checkout 防双击

JS 侧结账按钮加锁：
```js
var _checkingOut = false;
function checkout() {
    if (_checkingOut) return;
    _checkingOut = true;
    // ... 发 checkout 请求 ...
    _pendingReq[reqId] = function(resp) {
        _checkingOut = false;
        // ... 处理响应
    };
}
```

## 验证清单

1. **面板框架**: open/close/ESC/遮罩点击 → 全部走 requestClose → saveCart → close
2. **ESC 全覆盖**: 全屏+面板 → 关面板；非全屏+面板 → 关面板；非全屏无面板 → ESC 穿透；全屏无面板 → 退出全屏
3. **线程安全**: KeyboardHook ESC → BeginInvoke → PostToWeb；ShopTask Flash 响应 → BeginInvoke → PostToWeb
4. **数据通路**: bulkQuery 262条完整返回；callId 映射正确
5. **SKU 键**: 重复 id 商品各自独立加购/结算/领取
6. **结算安全**: JS 发 {idx,qty} → Flash 查价 → qty<=0 跳过 → `>` 语义
7. **暂停**: 对话中开商城 → 关后恢复暂停态
8. **关闭清理**: saveCart 成功 → shopPanelClose → 自动存盘 → 恢复暂停
9. **监听泄漏**: 多次开关面板后 UiData 'k' handler 数量不增长
10. **降级**: `_webFailed` → Flash 商城正常可用；Socket 断连 → 即时错误
11. **关闭防重入**: 快速双击关闭按钮/ESC → 只执行一次
12. **saveCart 失败**: 显示 retry/discard 对话框，不自动强退
13. **Socket 中途断连**: 面板强制关闭 + _pendingReq 清空 + 重连后 Flash 暂停恢复
14. **saveCart qty 校验**: 小数/负数/NaN 全被过滤，与 checkout 一致
15. **JSON 序列化**: `_shopJson` 独立实例，不访问 ServerManager private 字段
16. **shopPanelOpen 发送失败**: 面板不打开（按钮无反应）
17. **补发失败不清标志**: OnSocketReconnected 补发 shopPanelClose 若失败 → 标志保留 → 下次重连再试
18. **迟到响应守卫**: force_close 后迟到的 pending 回调 → `if(!Panels.isOpen()) return` 静默丢弃
19. **接线编译**: GuardianForm.HandlePanelStateChanged public + SetWebOverlay + Program.cs 完整接线
