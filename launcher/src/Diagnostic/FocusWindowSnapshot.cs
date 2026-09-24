using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Runtime.InteropServices;

namespace CF7Launcher.Diagnostic
{
    // WindowFromPoint 是候选命中窗口；只有本进程 WndProc/OnMouse* 能证明实际收消息。
    internal static class FocusWindowSnapshot
    {
        internal static Func<IntPtr> FlashWindow;

        // 多 HUD 实例注册表：以 HWND 为键记录 owner、实例标识与输入快照 probe，
        // 取代旧的全局 Hud/Owner 唯一槽（多实例共存时最后创建者胜出，归属被冒认）。
        // RegistryGate 是叶锁：持锁内只做字典操作与 win32 查询；probe 一律在锁外调用，
        // 也不在本锁内取 FocusTrace.Gate，避免与 _widgetsLock→Gate 构成环。
        private sealed class HudEntry
        {
            internal IntPtr Hwnd;
            internal IntPtr Owner;
            internal string Instance;
            internal long Seq;
            internal Func<Point, object> Probe;
        }

        private static readonly object RegistryGate = new object();
        private static readonly Dictionary<IntPtr, HudEntry> _huds = new Dictionary<IntPtr, HudEntry>();
        private static long _hudInstanceSeq;

        // 归属结论：Registered=true 表示 Hwnd 命中注册表。
        // Via 区分证据等级：receiver=本进程 WndProc/OnMouse* 已证明投递；
        // window_from_point=OS 顶层候选；bounds_contains=几何上唯一包含命中点的注册 HUD；
        // ambiguous=多个注册 HUD 重叠无法唯一归属；unattributed=找不到归属实例。
        internal sealed class HudAttribution
        {
            internal IntPtr Hwnd;
            internal IntPtr Owner;
            internal string Instance;
            internal string Via;
            internal bool Registered;
            internal long[] Candidates;
        }

        internal static void RegisterHud(IntPtr hwnd, IntPtr owner, Func<Point, object> probe)
        {
            if (hwnd == IntPtr.Zero) return;
            lock (RegistryGate)
            {
                HudEntry existing;
                long seq = _huds.TryGetValue(hwnd, out existing) ? existing.Seq : ++_hudInstanceSeq;
                _huds[hwnd] = new HudEntry { Hwnd = hwnd, Owner = owner, Probe = probe,
                    Seq = seq, Instance = "hud." + seq };
            }
        }

        internal static void UnregisterHud(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero) return;
            lock (RegistryGate) { _huds.Remove(hwnd); }
        }

        internal static int RegisteredHudCount { get { lock (RegistryGate) return _huds.Count; } }

        internal static bool IsHudRegistered(IntPtr hwnd)
        {
            lock (RegistryGate) return _huds.ContainsKey(hwnd);
        }

        // 实例标识供事件携带；未注册返回 null，由调用方写成 "unknown"。
        internal static string HudInstance(IntPtr hwnd)
        {
            lock (RegistryGate)
            {
                HudEntry entry;
                return _huds.TryGetValue(hwnd, out entry) ? entry.Instance : null;
            }
        }

        // 失效句柄惰性剔除：正常销毁走 UnregisterHud；这里兜住未走注销的残留，
        // 防止已销毁 HWND 继续冒认为注册 HUD。
        private static void PruneInvalidLocked()
        {
            List<IntPtr> dead = null;
            foreach (KeyValuePair<IntPtr, HudEntry> kv in _huds)
            {
                if (!IsWindow(kv.Key))
                {
                    if (dead == null) dead = new List<IntPtr>();
                    dead.Add(kv.Key);
                }
            }
            if (dead == null) return;
            for (int i = 0; i < dead.Count; i++) _huds.Remove(dead[i]);
        }

        // 接收者已知的归属（WndProc/OnMouse* 路径传入自己的 HWND）。
        internal static HudAttribution ForReceiver(IntPtr receiver)
        {
            var attribution = new HudAttribution { Hwnd = receiver, Via = "receiver" };
            if (receiver == IntPtr.Zero)
            {
                attribution.Via = "unattributed";
                return attribution;
            }
            lock (RegistryGate)
            {
                PruneInvalidLocked();
                HudEntry entry;
                if (_huds.TryGetValue(receiver, out entry))
                {
                    attribution.Owner = entry.Owner;
                    attribution.Instance = entry.Instance;
                    attribution.Registered = true;
                }
            }
            return attribution;
        }

        // 按命中点归属：WindowFromPoint 命中的注册 HUD 优先；否则几何上唯一包含
        // 该点的可见注册 HUD 作为次一级候选；零个或多个候选都不得冒认。
        internal static HudAttribution AttributeHudAt(Point point)
        {
            var attribution = new HudAttribution { Via = "unattributed" };
            try
            {
                IntPtr hit = WindowFromPoint(point);
                lock (RegistryGate)
                {
                    PruneInvalidLocked();
                    HudEntry direct;
                    if (_huds.TryGetValue(hit, out direct))
                    {
                        attribution.Hwnd = direct.Hwnd;
                        attribution.Owner = direct.Owner;
                        attribution.Instance = direct.Instance;
                        attribution.Via = "window_from_point";
                        attribution.Registered = true;
                        return attribution;
                    }
                    List<HudEntry> containing = null;
                    foreach (HudEntry entry in _huds.Values)
                    {
                        Rect bounds;
                        if (IsWindowVisible(entry.Hwnd) && GetWindowRect(entry.Hwnd, out bounds)
                            && point.X >= bounds.left && point.X < bounds.right
                            && point.Y >= bounds.top && point.Y < bounds.bottom)
                        {
                            if (containing == null) containing = new List<HudEntry>();
                            containing.Add(entry);
                        }
                    }
                    if (containing != null && containing.Count == 1)
                    {
                        HudEntry entry = containing[0];
                        attribution.Hwnd = entry.Hwnd;
                        attribution.Owner = entry.Owner;
                        attribution.Instance = entry.Instance;
                        attribution.Via = "bounds_contains";
                        attribution.Registered = true;
                    }
                    else if (containing != null)
                    {
                        attribution.Via = "ambiguous";
                        attribution.Candidates = containing.Select(e => e.Hwnd.ToInt64()).ToArray();
                    }
                }
            }
            catch { /* 归属失败保持 unattributed，不冒认。 */ }
            return attribution;
        }

        // 按 hwnd 取该实例注册的 probe 快照；probe 在 RegistryGate 外调用。
        // 未注册/无 probe/抛错都返回显式 unavailable，绝不退回到别的 HUD。
        internal static object CaptureHudInput(IntPtr hwnd, Point point)
        {
            Func<Point, object> probe;
            lock (RegistryGate)
            {
                HudEntry entry;
                if (!_huds.TryGetValue(hwnd, out entry) || entry.Probe == null)
                    return new { unavailable = "unregistered_receiver", hwnd = hwnd.ToInt64() };
                probe = entry.Probe;
            }
            try { return probe(point); }
            catch { return new { unavailable = "snapshot_failed", hwnd = hwnd.ToInt64() }; }
        }

        // 廉价路径：目标外点击只做一次前台窗口句柄采样，不做全量 Describe。
        internal static IntPtr ForegroundHandle()
        {
            try { return GetForegroundWindow(); } catch { return IntPtr.Zero; }
        }

        internal static object At(Point point)
        {
            return At(point, AttributeHudAt(point));
        }

        internal static object At(Point point, IntPtr receiver)
        {
            return At(point, receiver != IntPtr.Zero ? ForReceiver(receiver) : AttributeHudAt(point));
        }

        internal static object At(Point point, HudAttribution attribution)
        {
            try
            {
                using (FocusTrace.ObserveSnapshot())
                {
                    if (attribution == null) attribution = new HudAttribution { Via = "unattributed" };
                    IntPtr foreground = GetForegroundWindow();
                    IntPtr candidate = WindowFromPoint(point);
                    object[] huds;
                    lock (RegistryGate)
                    {
                        PruneInvalidLocked();
                        huds = DescribeRegistryLocked();
                    }
                    return new { foreground = Describe(foreground), hitCandidate = Describe(candidate),
                        hud = Describe(attribution.Hwnd), owner = Describe(attribution.Owner),
                        hudAttribution = new { hwnd = attribution.Hwnd.ToInt64(),
                            instance = attribution.Instance, via = attribution.Via,
                            registered = attribution.Registered, candidates = attribution.Candidates },
                        huds,
                        flash = Describe(FlashWindow == null ? IntPtr.Zero : FlashWindow()),
                        actualExternalReceiver = "unknown" };
                }
            }
            catch { return new { snapshot = "unavailable" }; }
        }

        private static object[] DescribeRegistryLocked()
        {
            var list = new List<object>();
            foreach (HudEntry entry in _huds.Values.OrderBy(e => e.Seq))
            {
                Rect bounds;
                bool rectAvailable = GetWindowRect(entry.Hwnd, out bounds);
                list.Add(new { hwnd = entry.Hwnd.ToInt64(), owner = entry.Owner.ToInt64(),
                    instance = entry.Instance, visible = IsWindowVisible(entry.Hwnd),
                    rectAvailable, bounds });
            }
            return list.ToArray();
        }

        internal static object Describe(IntPtr hwnd)
        {
            uint pid;
            uint tid = GetWindowThreadProcessId(hwnd, out pid);
            var gui = new GuiThreadInfo { size = Marshal.SizeOf<GuiThreadInfo>() };
            bool available = hwnd != IntPtr.Zero && tid != 0 && GetGUIThreadInfo(tid, ref gui);
            Rect bounds;
            bool rectAvailable = GetWindowRect(hwnd, out bounds);
            return new { hwnd = hwnd.ToInt64(), pid, tid, visible = IsWindowVisible(hwnd),
                parent = GetParent(hwnd).ToInt64(), rootOwner = GetAncestor(hwnd, 3).ToInt64(),
                previous = GetWindow(hwnd, 3).ToInt64(), next = GetWindow(hwnd, 2).ToInt64(),
                style = GetWindowLongW(hwnd, -16), exStyle = GetWindowLongW(hwnd, -20),
                rectAvailable, bounds, guiAvailable = available,
                guiFlags = available ? (int?)gui.flags : null,
                menuOwner = available ? (long?)gui.menuOwner.ToInt64() : null,
                moveSize = available ? (long?)gui.moveSize.ToInt64() : null,
                focus = available ? (long?)gui.focus.ToInt64() : null,
                capture = available ? (long?)gui.capture.ToInt64() : null,
                active = available ? (long?)gui.active.ToInt64() : null };
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Rect { public int left, top, right, bottom; }
        [StructLayout(LayoutKind.Sequential)]
        private struct GuiThreadInfo
        {
            public int size, flags;
            public IntPtr active, focus, capture, menuOwner, moveSize, caret;
            public Rect caretRect;
        }
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(Point point);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] private static extern bool GetGUIThreadInfo(uint tid, ref GuiThreadInfo info);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h, out Rect rect);
        [DllImport("user32.dll")] internal static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr h);
        [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr h);
        [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr h, uint flag);
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr h, uint command);
        [DllImport("user32.dll")] private static extern int GetWindowLongW(IntPtr h, int index);
    }
}
