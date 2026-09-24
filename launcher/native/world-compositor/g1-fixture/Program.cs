// G1Host.exe：G1 工单跨进程夹具的 Host/驱动进程（不进正式 runtime 闭包）。
// 真实链路：本进程持有 owner 顶层窗与生产 WorldCompositionSurface/WorldCompositorController/
// NativePointerBridge（原样编译的生产源码）→ Start() 拉起真实 FlashInputBroker.exe →
// broker 把真实 FlashInputBridge.dll 以 WH_GETMESSAGE 注入 G1Target.exe 的 UI 线程 →
// 桥在目标内对子窗口做真 subclass。失焦由第三窗口真实取前台产生；队列积压由目标
// 按标志文件停泵模拟；断言依据目标日志 + broker STOP 行 + Host 分层状态。
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;

namespace G1Fixture
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            var opt = Options.Parse(args);
            Directory.CreateDirectory(opt.Evidence);
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            var fixture = new Fixture(opt);
            try { fixture.CreateUi(); }
            catch (Exception error) { fixture.HostLog("FATAL create-ui " + error); return 2; }
            _ = fixture.RunAsync();
            Application.Run(fixture.Owner);
            return fixture.ExitCode;
        }
    }

    internal sealed class Options
    {
        internal string Evidence, Root, Mode="queue";
        internal static Options Parse(string[] args)
        {
            var o = new Options();
            for (int i = 0; i + 1 < args.Length; i += 2)
            {
                if (args[i] == "--evidence") o.Evidence = Path.GetFullPath(args[i + 1]);
                else if (args[i] == "--mode") o.Mode=args[i+1];
                else if (args[i] == "--root") o.Root = Path.GetFullPath(args[i + 1]);
            }
            if (o.Evidence == null || o.Root == null) throw new ArgumentException("need --evidence <dir> --root <repo>");
            return o;
        }
    }

    internal sealed class Fixture
    {
        private readonly Options _opt;
        private readonly List<string> _asserts = new List<string>();
        private readonly StringBuilder _logAll = new StringBuilder();
        private StreamWriter _log;
        private Form _third;
        internal Form Owner;
        private WorldCompositionSurface _surface;
        private WorldCompositorController _controller;
        private NativePointerBridge _bridge;
        private Process _target, _brokerProc;
        private IntPtr _child;
        private int _targetPid; private uint _targetTid;
        private SharedInputStateView _view;
        private IntPtr _viewPtr;
        private uint _cmdMsg, _fillerMsg;
        private string _targetLogPath, _stallPath, _focusKillPath;
        internal int ExitCode = 1;
        private int _failures;
        private bool _injectLateInit;
        private ulong _retiringCookie;
        private long _lastSeq; private uint _lastEpoch;

        internal Fixture(Options opt) { _opt = opt; }

        // ---------- evidence ----------
        internal void HostLog(string text)
        {
            string line = DateTime.Now.ToString("HH:mm:ss.fff") + " " + text;
            _logAll.AppendLine(line);
            _log?.WriteLine(line); _log?.Flush();
            Console.WriteLine(line);
            if(_injectLateInit && text.Contains("event=world_pointer_close session="+_retiringCookie+" confirmed=True")) {
                _injectLateInit=false;
                File.WriteAllText(_stallPath,"1");PostCmd(4,0);
                PostMessage(_child,RegisterWindowMessage("CF7.WorldPointer.Control.v4"),new IntPtr(1),new IntPtr(unchecked((long)_retiringCookie)));
                _=Task.Run(async()=>{await Task.Delay(700);if(File.Exists(_stallPath))File.Delete(_stallPath);});
            }
        }
        private void Assert(bool ok, string name, string detail)
        {
            string line = "ASSERT " + (ok ? "PASS" : "FAIL") + " " + name + " :: " + detail;
            _asserts.Add(line); HostLog(line);
            if (!ok) _failures++;
        }
        // ---------- target log (written by G1Target.exe, read with full share) ----------
        private string _targetErr;
        private string TargetLog()
        {
            try {
                using var fs = new FileStream(_targetLogPath, FileMode.Open, FileAccess.Read,
                    FileShare.ReadWrite | FileShare.Delete);
                using var sr = new StreamReader(fs, Encoding.UTF8, true);
                return sr.ReadToEnd();
            } catch (Exception e) {
                if (_targetErr != e.GetType().Name + ":" + e.Message)
                    HostLog("target_log_read_error " + (_targetErr = e.GetType().Name + ":" + e.Message));
                return "";
            }
        }
        private int TargetIndex() { return TargetLog().Length; }
        private string TargetSince(int mark) { var t = TargetLog(); return t.Length > mark ? t.Substring(mark) : ""; }
        private async Task<bool> WaitTargetSince(int mark, string needle, int ms)
        {
            var sw = Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < ms) { if (TargetSince(mark).Contains(needle)) return true; await Task.Delay(20); }
            return false;
        }
        private bool LogHas(string needle) => _logAll.ToString().Contains(needle);
        private int HostIndex() => _logAll.Length;
        private string HostSince(int mark) { var t = _logAll.ToString(); return t.Length > mark ? t.Substring(mark) : ""; }
        private async Task<bool> WaitLog(string needle, int ms)
        {
            var sw = Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < ms) { if (LogHas(needle)) return true; await Task.Delay(25); }
            return false;
        }
        // ---------- shared page counters (second view of the broker's section) ----------
        private int Shared(int off) { return Marshal.ReadInt32(_viewPtr, off); }
        private string Snap() => $"minEpoch={Shared(56)} consumedSeq={Shared(60)} stale={Shared(64)} stopped={Shared(68)} unowned={Shared(72)} dup={Shared(76)} issued={Shared(80)}";
        // ---------- interop ----------
        [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern uint RegisterWindowMessage(string s);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr h, int n);
        [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
        [DllImport("user32.dll")] private static extern uint SendInput(uint n, INPUT[] inputs, int size);
        [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint from, uint to, bool attach);
        [DllImport("user32.dll")] private static extern IntPtr SetFocus(IntPtr h);
        [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
        [StructLayout(LayoutKind.Sequential)] private struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
        [StructLayout(LayoutKind.Sequential)] private struct INPUT { public uint type; public MOUSEINPUT mi; }
        // 真实物理点击（SendInput 走系统输入管线）。焦点归属由 win32k 在真实输入路径上
        // 自行裁决——跨进程子窗点击聚焦/失焦都产生真 WM_SETFOCUS/WM_KILLFOCUS 投递到
        // 目标线程队列，经桥真实窗过程。这是嵌入插件的真实聚焦模型；AttachThreadInput
        // 持久合并队列在"T2 停泵 + T1 激活"下会把宿主线程挂死（实测），已弃用。
        private void ClickAt(Point pt, string tag)
        {
            SetCursorPos(pt.X, pt.Y);
            var down = new INPUT { type = 0, mi = new MOUSEINPUT { dwFlags = 0x0002 } }; // MOUSEEVENTF_LEFTDOWN
            var up = new INPUT { type = 0, mi = new MOUSEINPUT { dwFlags = 0x0004 } };   // MOUSEEVENTF_LEFTUP
            uint sent = SendInput(2, new[] { down, up }, Marshal.SizeOf<INPUT>());
            HostLog($"real_click @{pt.X},{pt.Y} sent={sent} {tag}");
        }
        private async Task<bool> ClickActivate(Form win, string phase, bool caption = false)
        {
            if (!win.Visible) win.Show();
            if (GetForegroundWindow() == win.Handle) { HostLog($"click_skip {phase} already-fg"); return true; }
            // caption=true 点标题栏（避开子窗覆盖的客户区，免得这次激活点击变成子窗的真实 DOWN 噪声）
            var pt = caption
                ? new Point(win.Bounds.X + win.Bounds.Width / 2, win.Bounds.Y + 12)
                : win.PointToScreen(new Point(win.ClientSize.Width / 2, win.ClientSize.Height / 2));
            ClickAt(pt, phase + "_activate");
            var sw = Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < 9000)
            {
                if (GetForegroundWindow() == win.Handle) return true;
                // 真实点击被更高 Z 序的窗口截获时的兜底——仍是真实系统激活路径
                ShowWindow(win.Handle, 9); SetForegroundWindow(win.Handle);
                if (GetForegroundWindow() == win.Handle) return true;
                await Task.Delay(120);
            }
            HostLog($"click_timeout {phase} fg=0x{GetForegroundWindow().ToInt64():X}");
            return GetForegroundWindow() == win.Handle; // 单次末读，消除竞态二次读
        }
        private static FieldInfo F(object o, string n) => o.GetType().GetField(n, BindingFlags.NonPublic | BindingFlags.Instance);

        // ---------- steps ----------
        private void PostCmd(long w, long l) { PostMessage(_child, _cmdMsg, new IntPtr(w), new IntPtr(l)); }
        private void Mark(string tag, long lp) { HostLog("=== " + tag + " ==="); PostCmd(3, lp); }
        // 跨进程子窗键盘焦点：实测真实点击只激活顶层链（MOUSEACTIVATE 到达子窗但系统不
        // 给外部线程子窗授焦点）——这正是嵌入式插件宿主需要显式 SetFocus 的真实原因。
        // 跨线程 SetFocus 要在合并输入队列上下文里做：瞬时 AttachThreadInput（目标泵
        // 活着时才调用，绝不跨入停泵窗口——持久 attach 实测会把宿主线程挂死）。
        private async Task<bool> FocusChild(string phase)
        {
            await ClickActivate(Owner, phase + "_owner", caption: true); // 顶层链先真实前台
            int fm = TargetIndex();
            bool attached = AttachThreadInput(GetCurrentThreadId(), _targetTid, true);
            IntPtr prev = SetFocus(_child);
            if (attached) AttachThreadInput(GetCurrentThreadId(), _targetTid, false);
            HostLog($"setfocus {phase} attached={attached} prev=0x{prev.ToInt64():X} err={Marshal.GetLastWin32Error()}");
            // prev==child：簿记上子窗本就持有焦点（队列失活不剥夺跨线程子窗的焦点槽），
            // SetFocus 是 no-op、不会再有 SETFOCUS——已是聚焦态，直接成立。
            if (prev == _child) return true;
            return await WaitTargetSince(fm, "SETFOCUS", 4000);
        }
        private long Intake(int message, int tag)
        {
            // 生产入口：surface.IntakePointer（无按键 Down 推进 _inputEpoch）→ Drain →
            // bridge.Send（先写 issuedEpoch 再 PostMessage）。直接调 Drain 与 BeginInvoke
            // 调度等价——Drain 是同一生产方法；反射读私有计数器仅作证据关联。
            _surface.IntakePointer(message, _surface.PointToScreen(new Point(tag, tag)), 0);
            _lastSeq = (long)F(_surface, "_sequence").GetValue(_surface);
            _lastEpoch = (uint)F(_surface, "_inputEpoch").GetValue(_surface);
            _surface.Drain();
            HostLog($"intake msg=0x{message:X} tag={tag} epoch={_lastEpoch} seq={_lastSeq} | {Snap()}");
            return _lastSeq;
        }
        private async Task<bool> WaitConsumed(long seq, int ms)
        {
            var sw = Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < ms) { if (_bridge.EndpointConsumedSeq >= seq) return true; await Task.Delay(20); }
            return false;
        }
        private void Stall() { File.WriteAllText(_stallPath, "1"); }
        private void Resume() { if (File.Exists(_stallPath)) File.Delete(_stallPath); }
        private int _staleAtStall;
        private int CountDeliver(string seg, int tag) =>
            seg.Split('\n').Count(l => l.Contains("x=" + tag + " y=" + tag));
        private async Task<int> StallIntakeActivateResume(int tag, string phase, bool focusKill = false)
        {
            // 公共骨架：压停泵 → Host Down(tag) → 验证在队未见 → [可选] 目标侧真实
            // SetFocus(owner) 产生同步 KILLFOCUS（停泵窗口内抬 localFloor）→ 第三窗真实
            // 取前台 → 等焦点事件入队（泵仍停）。恢复泵与否由调用方决定；返回段起点索引。
            int mark = TargetIndex();
            Stall(); PostCmd(4, 0); // 唤醒阻塞中的 GetMessage，使泵在取下一包前先进入停泵
            Assert(await WaitTargetSince(mark, "STALL_BEGIN", 4000), phase + "_pump_stalled", "");
            long seq = Intake(0x201, tag);
            _staleAtStall = Shared(64);
            bool seen = await WaitConsumed(seq, 600);
            Assert(!seen, phase + "_down_queued_unseen", $"consumed={_bridge.EndpointConsumedSeq} seq={seq} while stalled");
            if (focusKill)
            {
                // 先让 owner 链真实前台（T1 队列活动是目标侧 attach+SetFocus 的前提），
                // 再落 focuskill 标志：目标在停泵循环内做真实 SetFocus(owner)→同步
                // KILLFOCUS 穿过桥 proc → localFloor 先于在队旧包抬升。
                await ClickActivate(Owner, phase + "_ownerfg", caption: true);
                HostLog($"{phase}_ownerfg_done fg=0x{GetForegroundWindow().ToInt64():X}");
                File.WriteAllText(_focusKillPath, "1");
                HostLog(phase + "_focuskill_flag_written");
                Assert(await WaitTargetSince(mark, "FOCUSKILL", 4000), phase + "_focuskill_fired",
                    "target-side real SetFocus(owner) while pump stalled");
            }
            // 真实点击第三窗激活 → owner 真失活 → 子窗 KILLFOCUS 进入 T2 队列（泵仍停）。
            // 判据是"真实失焦"本身：第三窗前台到位、或 owner 的 Deactivate 实事件已发、
            // 或前台确已易主（点击可能命中叠在上面的外部窗口——那也是一次真实前台转移）。
            int hmark = HostIndex();
            bool fgThird = await ClickActivate(_third, phase + "_third");
            await Task.Delay(450); // 失焦事件已进入目标输入队列（泵仍停）
            bool deact = HostSince(hmark).Contains("owner_deactivate_fired");
            IntPtr fgNow = GetForegroundWindow();
            Assert(fgThird || deact || fgNow != Owner.Handle, phase + "_real_focus_loss",
                $"fgThird={fgThird} deactivateLogged={deact} fgNow=0x{fgNow.ToInt64():X}");
            return mark;
        }
        private async Task Readmit(int tag, string phase)
        {
            Assert(await FocusChild(phase), phase + "_refocus", "");
            int rm = TargetIndex(); int staleBefore = Shared(64);
            long seq = Intake(0x201, tag);
            Assert(await WaitConsumed(seq, 5000), phase + "_readmit_consumed", $"seq={seq} epoch={_lastEpoch}");
            await Task.Delay(250);
            var seg = TargetSince(rm);
            Assert(CountDeliver(seg, tag) == 2, phase + "_readmit_exactly_once",
                $"deliveries@{tag}={CountDeliver(seg, tag)} (expect MOUSEMOVE+DOWN)");
            Assert(Shared(64) == staleBefore, phase + "_readmit_not_stale", $"stale={Shared(64)} before={staleBefore}");
            Intake(0x202, tag); await Task.Delay(200);
        }

        internal void CreateUi()
        {
            _log = new StreamWriter(Path.Combine(_opt.Evidence, "host.log"), false, Encoding.UTF8) { AutoFlush = true };
            LogManager.SetSink(m => HostLog("[prod] " + m));
            _cmdMsg = RegisterWindowMessage("CF7.G1.Cmd");
            _fillerMsg = RegisterWindowMessage("CF7.G1.Filler");
            _stallPath = Path.Combine(_opt.Evidence, "stall.flag");
            _focusKillPath = Path.Combine(_opt.Evidence, "focuskill.flag");
            _targetLogPath = Path.Combine(_opt.Evidence, "target.log");
            HostLog($"host pid={Environment.ProcessId} tid={GetCurrentThreadId()} cmdMsg=0x{_cmdMsg:X} fillerMsg=0x{_fillerMsg:X}");

            Owner = new Form { Text = "CF7 G1 Owner", StartPosition = FormStartPosition.Manual,
                Location = new Point(60, 60), ClientSize = new Size(560, 400) };
            Owner.Activated += (s, e) => HostLog($"owner_activated fg=0x{GetForegroundWindow().ToInt64():X}");
            Owner.Deactivate += (s, e) => HostLog($"owner_deactivate_fired fg=0x{GetForegroundWindow().ToInt64():X}");
            Owner.Show();
        }

        internal async Task RunAsync()
        {
            try {
                await Run();
                if(Environment.GetEnvironmentVariable("CF7_FOCUS_TRACE")=="1") {
                    await Task.Delay(250);
                    string recorded=_logAll.ToString();
                    Assert(recorded.Contains(" stage=9 "),"endpoint_trace_attached","separate mapping opened in actual target");
                    if(_opt.Mode!="failure" && _opt.Mode!="geometry" && _opt.Mode!="maximize") {
                        var enters=Regex.Matches(recorded,@"TRACE session=(\d+) ordinal=\d+ qpc=\d+ frequency=\d+ stage=1 seq=(\d+) epoch=\d+ msg=0x201 ");
                        bool paired=enters.Count>0;
                        foreach(Match entered in enters)paired &= Regex.IsMatch(recorded,
                            @"TRACE session="+entered.Groups[1].Value+@" ordinal=\d+ qpc=\d+ frequency=\d+ stage=2 seq="+entered.Groups[2].Value+@" epoch=\d+ msg=0x201 ");
                        Assert(paired,"endpoint_trace_original_enter_return","each Down entry has same-session/same-sequence return; not a business ACK");
                    }
                    Assert(!recorded.Contains("TRACE_GAP"),"endpoint_trace_no_overwrite_in_sample","bounded trace reports loss explicitly");
                }
                File.WriteAllLines(Path.Combine(_opt.Evidence,"summary.txt"),_asserts);
                ExitCode = _failures == 0 ? 0 : 1;
            }
            catch (Exception error) { HostLog("FATAL " + error); ExitCode = 2; }
            finally {
                // Even a failed assertion/exception must release only this run's
                // exact child and bridge. Never kill helpers by process name.
                try { if (File.Exists(_stallPath)) File.Delete(_stallPath); } catch { }
                try { _controller?.Dispose(); _bridge?.Dispose(); _view?.Dispose(); } catch { }
                try {
                    if (_target != null && !_target.HasExited) {
                        PostCmd(2, 0);
                        if (!_target.WaitForExit(3000)) _target.Kill();
                    }
                } catch { }
                try { _third?.Close(); Owner?.Close(); } catch { }
                _target?.Dispose();
                LogManager.SetSink(_ => { });
                Application.ExitThread();
            }
        }

        private async Task Run()
        {
            var rundir = AppContext.BaseDirectory;
            // ---------- 装配：owner 前台 + 真实目标进程 + 真实 broker/桥 ----------
            Assert(await ClickActivate(Owner, "owner-initial", caption: true),
                "owner_foreground", $"fg=0x{GetForegroundWindow().ToInt64():X}");
            _third = new Form { Text = "CF7 G1 Third", StartPosition = FormStartPosition.Manual,
                Location = new Point(820, 80), ClientSize = new Size(340, 220) };

            var hwndFile = Path.Combine(_opt.Evidence, "target.hwnd");
            // 先清掉可能来自上一轮的 stale 状态：旧 hwndfile 会让 WaitFile 秒过却指向死
            // 进程窗口；旧 stall.flag 会让新目标一进泵就停。两者都使证据失真。
            if (File.Exists(hwndFile)) File.Delete(hwndFile);
            if (File.Exists(_stallPath)) File.Delete(_stallPath);
            if (File.Exists(_focusKillPath)) File.Delete(_focusKillPath);
            _target = Process.Start(Path.Combine(rundir, "G1Target.exe"),
                $"--owner {(long)Owner.Handle} --log \"{_targetLogPath}\" --stall \"{_stallPath}\" --focuskill \"{_focusKillPath}\" --hwndfile \"{hwndFile}\"" + " --stress-iat " + (_opt.Mode=="renew" ? "1" : "0"));
            Assert(await WaitFile(hwndFile, 8000), "target_started", $"pid={_target?.Id}");
            var ids = File.ReadAllText(hwndFile);
            HostLog("target_ids " + ids.Trim());
            _child = new IntPtr(long.Parse(Regex.Match(ids, @"child=(\d+)").Groups[1].Value));
            _targetPid = int.Parse(Regex.Match(ids, @"pid=(\d+)").Groups[1].Value);
            _targetTid = uint.Parse(Regex.Match(ids, @"tid=(\d+)").Groups[1].Value);
            Assert(_targetPid == _target.Id, "target_pid_fresh",
                $"hwndfile pid={_targetPid} launched pid={_target.Id} (reject stale)");
            Assert(await WaitTargetSince(0, "PUMP_START", 8000), "target_pump", $"child=0x{_child.ToInt64():X} pid={_targetPid}");

            if(_opt.Mode=="geometry" || _opt.Mode=="maximize") {await RunGeometry();return;}

            _bridge = await NativePointerBridge.Start(_child, Owner.Handle);
            _brokerProc = (Process)F(_bridge, "_broker").GetValue(_bridge);
            HostLog($"broker pid={_brokerProc.Id} source=0x{_child.ToInt64():X} owner=0x{Owner.Handle.ToInt64():X}");
            _view = SharedInputStateView.Open($"Local\\CF7.WorldPointer.{_targetPid}.{_brokerProc.Id}",
                NativePointerBridge.InputMagic, NativePointerBridge.ProtocolVersion);
            _viewPtr = (IntPtr)F(_view, "_view").GetValue(_view);
            HostLog("shared_view " + Snap());

            _surface = new WorldCompositionSurface(() => _child, () => HostLog("focus_cb"), _bridge, _opt.Mode=="renew" ? 8u : WorldPointerMapper.EpochLimit) { Owner = Owner };
            _surface.Bounds = Owner.RectangleToScreen(Owner.ClientRectangle);
            _surface.Show();
            Assert(_surface.Visible, "surface_visible", $"bounds={_surface.Bounds}");

            // 桥 DLL 真实装载进目标进程的旁证。
            try {
                bool loaded = Process.GetProcessById(_targetPid).Modules
                    .Cast<ProcessModule>().Any(m => m.ModuleName == "FlashInputBridge.dll");
                Assert(loaded, "bridge_dll_in_target", "FlashInputBridge.dll in target module list");
            } catch (Exception e) { HostLog("module_check_error " + e.Message); }

            if(_opt.Mode=="renew") {await RunRenewals();return;}
            if(_opt.Mode=="failure") {await RunRestoreFailure();return;}
            // ---------- S0：准入基线（真实 SetFocus + 交付） ----------
            Mark("S0 sanity", 100);
            Assert(await FocusChild("s0"), "s0_child_focused", "target child holds real focus");
            int mark0 = TargetIndex();
            long s0 = Intake(0x201, 41);
            Assert(await WaitConsumed(s0, 5000), "s0_down_consumed", $"seq={s0} consumed={_bridge.EndpointConsumedSeq}");
            await Task.Delay(250);
            Assert(CountDeliver(TargetSince(mark0), 41) >= 2, "s0_down_delivered", "expect MOUSEMOVE+LBUTTONDOWN @41");
            Intake(0x202, 41); await Task.Delay(200);
            HostLog("s0_counters " + Snap());

            // ---------- S1：RCE-1 端点隔离探针（无 Host cancel；只验失焦下界机制） ----------
            Mark("S1 isolated endpoint probe (no host cancel)", 101);
            int mark1 = await StallIntakeActivateResume(42, "s1", focusKill: true);
            Resume();
            Assert(await WaitConsumed(_lastSeq, 5000), "s1_down_processed_after_resume", $"consumed={_bridge.EndpointConsumedSeq}");
            await Task.Delay(300);
            var seg1 = TargetSince(mark1);
            int delivered1 = CountDeliver(seg1, 42);
            int staleDelta1 = Shared(64) - _staleAtStall;
            bool killLogged = seg1.Contains("KILLFOCUS");
            int killAt = seg1.IndexOf("KILLFOCUS"), firstMouseAt = seg1.IndexOf("x=42 y=42");
            HostLog($"s1_seg killfocus={killLogged}@{killAt} firstMouse42@{firstMouseAt} delivered@42={delivered1} staleDelta={staleDelta1} {Snap()}");
            Assert(killLogged, "s1_killfocus_through_bridge", "real WM_KILLFOCUS observed in target log");
            Assert(delivered1 == 0, "s1_down_no_original_delivery", $"deliveries@42={delivered1} (posted-vs-input ordering probe)");
            Assert(staleDelta1 == (delivered1 == 0 ? 1 : 0), "s1_reject_consistent", $"staleDelta={staleDelta1} rejected={delivered1 == 0}");

            Intake(0x202, 88); await Task.Delay(150); // 物理抬起收尾旧手势：下一次 Down 才推进 epoch
            await Readmit(43, "s1");

            // ---------- S2：生产配对（真实 controller: owner.Deactivate→CancelPointer） ----------
            Mark("S2 production pairing (controller cancel on deactivate)", 102);
            var anchor = new Control();
            _controller = new WorldCompositorController(Owner, anchor, () => _child,
                () => false, m => HostLog("notify:" + m), _opt.Root, () => false, _ => { }, () => { });
            F(_controller, "_surface").SetValue(_controller, _surface);
            HostLog("controller_attached (real owner.Deactivate->CancelPointer wiring)");

            int mark2 = await StallIntakeActivateResume(44, "s2");
            Assert(await WaitLog("world_pointer_cancel", 5000), "s2_host_cancel_fired", "owner deactivate -> CancelPointer");
            await Task.Delay(400); // 共享下界先行落定，再恢复泵
            Resume();
            Assert(await WaitConsumed(_lastSeq, 5000), "s2_down_processed_after_resume", "");
            await Task.Delay(300);
            var seg2 = TargetSince(mark2);
            int staleDelta2 = Shared(64) - _staleAtStall;
            HostLog($"s2_seg delivered@44={CountDeliver(seg2, 44)} killfocus={seg2.Contains("KILLFOCUS")} cancelmode={seg2.Contains("CANCELMODE")} staleDelta={staleDelta2}");
            Assert(CountDeliver(seg2, 44) == 0, "s2_down_no_delivery", $"deliveries@44={CountDeliver(seg2, 44)}");
            Assert(staleDelta2 == 1, "s2_reject_counted", $"staleDelta={staleDelta2}");
            Assert(seg2.Contains("CANCELMODE"), "s2_cancel_packet_admitted", "cancel epoch>=floor -> delivered once");

            await Readmit(45, "s2");

            // ---------- S3：Cancel 包 Post 失败 → 共享下界单独兜底 ----------
            Mark("S3 cancel-post-failure via full queue", 103);
            int mark3 = TargetIndex();
            Stall(); PostCmd(4, 0); // 唤醒阻塞中的 GetMessage，让停泵先于后续入队包生效
            Assert(await WaitTargetSince(mark3, "STALL_BEGIN", 4000), "s3_pump_stalled", "");
            long s3 = Intake(0x201, 46);
            int staleAtS3 = Shared(64);
            Assert(!await WaitConsumed(s3, 600), "s3_down_queued_unseen", "");
            int fillers = 0;
            while (fillers < 60000 && PostMessage(_child, _fillerMsg, IntPtr.Zero, IntPtr.Zero)) fillers++;
            HostLog($"queue_full fillers_posted={fillers} | {Snap()}");
            Assert(fillers > 1000, "s3_queue_saturated", $"fillers={fillers}");
            _surface.CancelPointer("g1_queue_full");
            Assert(await WaitLog("post=post_failed", 4000), "s3_cancel_post_failed", "cancel packet could not be posted");
            Resume();
            Assert(await WaitConsumed(s3, 15000), "s3_down_processed_after_drain", $"consumed={_bridge.EndpointConsumedSeq}");
            await Task.Delay(400);
            var seg3 = TargetSince(mark3);
            int staleDelta3 = Shared(64) - staleAtS3;
            HostLog($"s3_seg delivered@46={CountDeliver(seg3, 46)} cancelmode={seg3.Contains("CANCELMODE")} staleDelta={staleDelta3} {Snap()}");
            Assert(CountDeliver(seg3, 46) == 0, "s3_down_no_delivery", "shared floor alone rejects it");
            Assert(staleDelta3 == 1, "s3_reject_counted", $"staleDelta={staleDelta3}");
            Assert(seg3.Contains("CANCELMODE"), "s3_persistent_cancel_delivered", "v4 broker control completes cancellation despite failed data Post");

            await Readmit(47, "s3");

            // R05: an already-delivered Down, then a full queue and CancelPostFailure,
            // no follow-up data. Poll control must clear the endpoint on recovery.
            await Readmit(48,"s4-prime");
            Intake(0x201,49);await Task.Delay(250);
            int s4mark=TargetIndex();
            File.WriteAllText(_stallPath,"1");PostCmd(4,0);
            await WaitTargetSince(s4mark,"STALL_BEGIN",4000);
            int filled=0;while(PostMessage(_child,_fillerMsg,IntPtr.Zero,IntPtr.Zero) && filled<12000)filled++;
            _surface.CancelPointer("s4_no_followup_data");
            int cancelTicket=Shared(104);
            File.Delete(_stallPath);
            var releaseWait=Stopwatch.StartNew();
            while(Shared(108)!=cancelTicket && releaseWait.ElapsedMilliseconds<8000)await Task.Delay(25);
            Assert(Shared(108)==cancelTicket && Shared(124)==0,"s4_release_without_followup_data",Snap());
            Assert(TargetSince(s4mark).Contains("CANCELMODE"),"s4_original_cancel","original cancellation observed");

            // ---------- 收尾：真实拆桥 → broker STOP 行 ----------
            Mark("teardown", 199);
            string finalSnap = Snap(); // broker 退出即销毁 section，先取末态
            _view.Dispose();
            _controller?.Dispose();
            _bridge.Dispose();
            Assert(await WaitLog("world_pointer_bridge STOP", 8000), "broker_stop_line", "STOP counters captured via LogManager");
            PostCmd(2, 0);
            try { _target.WaitForExit(5000); } catch { }
            HostLog("final " + finalSnap);
            HostLog($"RESULT failures={_failures} asserts={_asserts.Count}");
            File.WriteAllLines(Path.Combine(_opt.Evidence, "summary.txt"), _asserts);
        }

        [DllImport("user32.dll")] private static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint flags,uint timeout,out IntPtr result);
        private async Task RunRestoreFailure()
        {
            PostCmd(7,0);await Task.Delay(200);
            bool closed=await _bridge.CloseAsync();
            Assert(!closed,"restore_conflict_unconfirmed","must not report restoration or start successor");
            bool refused=false;try {var duplicate=await NativePointerBridge.Start(_child,Owner.Handle);duplicate.Dispose();}catch {refused=true;}
            Assert(refused,"restore_conflict_successor_refused","retiring broker still owns installation");
            Assert(!_target.HasExited,"restore_conflict_target_preserved","fixture target was not killed for recovery");
            PostCmd(2,0);_target.WaitForExit(5000);
            await Task.Delay(400);
            HostLog($"RESULT failures={_failures} asserts={_asserts.Count}");
            File.WriteAllLines(Path.Combine(_opt.Evidence,"summary.txt"),_asserts);
        }
        private async Task RunGeometry()
        {
            Owner.BackColor=Color.Magenta;
            _controller=new WorldCompositorController(Owner,Owner,()=>_child,()=>true,
                text=>HostLog("notify:"+text),_opt.Root,()=>true,
                scale=>SendMessageTimeout(_child,_cmdMsg,new IntPtr(11),new IntPtr((int)Math.Round(scale*100)),2,1000,out _),()=>{});
            _controller.Adopt(new WorldLightingFrame {Sequence=1,Scene=1,Ready=true,Light=7,Mode="光照",Parameters=new double[]{1,1,1,1,0,0,0,0}});
            _controller.ApplyRenderSelection(new RenderSelection(3,.67,"LOW"),0);
            var wait=Stopwatch.StartNew();
            while(!_controller.SchedulingAllowed && wait.ElapsedMilliseconds<15000)await Task.Delay(50);
            Assert(_controller.SchedulingAllowed,"geometry_capture_ready","real production Controller + native WGC/D3D");
            _surface=(WorldCompositionSurface)F(_controller,"_surface").GetValue(_controller);
            _bridge=_controller.InputBridgeForDiagnostics;
            if(_surface==null || !_surface.Visible)throw new InvalidOperationException("No visible presentation");
            var native=(NativeCompositorSession)F(_controller,"_native").GetValue(_controller);
            var stats=native.Read();
            Assert(stats.Width==(uint)Math.Round(Owner.ClientSize.Width*.67) && stats.Width<_surface.ClientSize.Width,
                "geometry_source_is_reduced","source="+stats.Width+"x"+stats.Height+" output="+_surface.ClientSize);
            IntPtr stable=_surface.Handle;int hidden=0;
            _surface.VisibleChanged+=(_,__)=>{if(!_surface.Visible)hidden++;};
            for(int i=0;i<4;i++) {
                Owner.Location=new Point(85+i*95,90+i*30);
                // Deliberately no render timer / UI pump between owner move and proof.
                System.Threading.Thread.Sleep(100);
                Assert(_surface.Visible && _surface.Handle==stable && _surface.Bounds==Owner.RectangleToScreen(Owner.ClientRectangle),
                    "geometry_follow_"+i,"stable visible P follows owner synchronously");
                Assert(CaptureCorner("move-"+i)==Color.FromArgb(31,173,89).ToArgb(),
                    "geometry_pixels_"+i,"far corner outside F raster remains the composed source color");
            }
            Assert(hidden==0,"geometry_never_exposed_source","no P hide during translation");
            // Detector counterexample: the old failure exposes the magenta parent
            // beyond the 67% source. This is only our disposable fixture window.
            _surface.Hide();Owner.Refresh();System.Threading.Thread.Sleep(100);
            Assert(CaptureCorner("negative-hidden")==Color.Magenta.ToArgb(),"geometry_hidden_counterexample_detected","same pixel would reject old hide behavior");
            _surface.Show();await Task.Delay(250);
            if(_opt.Mode=="maximize")await RunMaximizeGeometry(native);
            _controller.Dispose();
            Assert(await _bridge.CloseAsync(),"geometry_bridge_retired","no active game or player save involved");
            PostCmd(2,0);await _target.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));
        }
        private int CaptureCorner(string name, bool top=false)
        {
            Rectangle bounds=_surface.Bounds;
            using var bitmap=new Bitmap(bounds.Width,bounds.Height);
            using(var graphics=Graphics.FromImage(bitmap))graphics.CopyFromScreen(bounds.Location,Point.Empty,bounds.Size);
            bitmap.Save(Path.Combine(_opt.Evidence,name+".png"),System.Drawing.Imaging.ImageFormat.Png);
            Color pixel=top ? bitmap.GetPixel(60,0) : bitmap.GetPixel(bounds.Width-30,bounds.Height-30);
            HostLog("screen_proof "+name+" corner="+pixel+" bounds="+bounds);
            return pixel.ToArgb();
        }
        [StructLayout(LayoutKind.Sequential)] private struct GeometryRect {public int Left,Top,Right,Bottom;public Rectangle Rectangle=>Rectangle.FromLTRB(Left,Top,Right,Bottom);}
        [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd,out GeometryRect rect);
        [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hwnd,ref Point point);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd,out GeometryRect rect);
        [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd,int attribute,out GeometryRect rect,int size);
        private (Rectangle Source,Rectangle Capture,Rectangle Output) Geometry(NativeCompositorSession native=null)
        {
            GetClientRect(_child,out var rect);var origin=Point.Empty;ClientToScreen(_child,ref origin);
            DwmGetWindowAttribute(Owner.Handle,9,out var capture,Marshal.SizeOf<GeometryRect>());
            Rectangle resolved=capture.Rectangle;
            if(native!=null) {
                GetWindowRect(Owner.Handle,out var window);
                WorldCompositorController.TryResolveCaptureFrame(capture.Rectangle,window.Rectangle,native.ReadCaptureSize(),out resolved);
            }
            return(new Rectangle(origin,new Size(rect.Right,rect.Bottom)),resolved,Owner.RectangleToScreen(Owner.ClientRectangle));
        }
        private async Task RunMaximizeGeometry(NativeCompositorSession native)
        {
            _controller.ApplyRenderSelection(new RenderSelection(0,1,"MEDIUM"),0);
            await Ready("full_scale");
            SendMessageTimeout(_child,_cmdMsg,new IntPtr(12),new IntPtr(1),2,1000,out _);
            await Task.Delay(150);
            var outside=Geometry(native);
            Assert(!outside.Output.Contains(outside.Source) && outside.Capture.Contains(outside.Source),
                "source_outside_P_inside_S_counterexample",outside.ToString());
            await Ready("one_pixel_child_offset");
            await Task.Delay(100); // allow the submitted swapchain frame to reach DWM
            Assert(CaptureCorner("one-pixel-offset")==Color.FromArgb(31,173,89).ToArgb(),"offset_pixels_from_F","actual WGC ROI used despite F extending past P");
            Assert(CaptureCorner("one-pixel-top",top:true)==Color.FromArgb(31,173,89).ToArgb(),"offset_top_row_from_F","old P containment leaves parent pixels at the top");
            SendMessageTimeout(_child,_cmdMsg,new IntPtr(12),IntPtr.Zero,2,1000,out _);
            await Ready("offset_reset");
            for(int i=0;i<3;i++) {
                ulong generation=native.CaptureGeneration;IntPtr outputHwnd=_surface.Handle;ulong inputSession=_bridge.SessionIdentity;
                Owner.WindowState=FormWindowState.Maximized;await Ready("maximize_"+i);
                await Task.Delay(100);
                native.ReadCaptureSize();Assert(native.CaptureGeneration>generation,"maximize_recaptured_"+i,"new WGC session for new non-client geometry");
                Assert(_surface.Handle==outputHwnd && _bridge.SessionIdentity==inputSession,"maximize_kept_windows_input_"+i,"P HWND and input session unchanged");
                Assert(CaptureCorner("maximize-"+i)==Color.FromArgb(31,173,89).ToArgb(),"maximize_pixels_"+i,"full-size source covers output");
                Assert(CaptureCorner("maximize-top-"+i,top:true)==Color.FromArgb(31,173,89).ToArgb(),"maximize_top_row_"+i,"no stale caption strip above world");
                Owner.WindowState=FormWindowState.Normal;await Ready("restore_"+i);
                await Task.Delay(100);
                Assert(CaptureCorner("restore-top-"+i,top:true)==Color.FromArgb(31,173,89).ToArgb(),"restore_top_row_"+i,"normal origin also restored");
            }
            async Task Ready(string phase) {
                var wait=Stopwatch.StartNew();bool okay=false;
                do {
                    await Task.Delay(60);var g=Geometry(native);var s=native.Read();
                    var crop=(Rectangle)F(_controller,"_crop").GetValue(_controller);
                    okay=_controller.SchedulingAllowed && g.Capture.Contains(g.Source) && crop==WorldCompositorController.CalculateCrop(g.Source,g.Capture)
                        && s.Width==g.Source.Width && s.Height==g.Source.Height && _surface.Bounds==g.Output;
                }while(!okay && wait.ElapsedMilliseconds<6000);
                HostLog("geometry_phase="+phase+" "+Geometry(native)+" WGC="+native.ReadCaptureSize());
                Assert(okay,"geometry_settled_"+phase,"live F / S crop / P agree without a second user maximize");
            }
        }
        private async Task RunRenewals()
        {
            var anchor=new Panel();Owner.Controls.Add(anchor);
            _controller=new WorldCompositorController(Owner,anchor,()=>_child,()=>false,_=>{},_opt.Root,()=>false,_=>{},()=>{} ,8);
            _controller.BindInput(_bridge,_surface);
            ulong session=_bridge.SessionIdentity;
            bool refused=false;try {var duplicate=await NativePointerBridge.Start(_child,Owner.Handle);duplicate.Dispose();}catch {refused=true;}
            Assert(refused,"parallel_install_refused","same target instance remains singly owned");
            IntPtr stableSurface=_surface.Handle;
            int peekMark=TargetIndex();Stall();PostCmd(4,0);
            Assert(await WaitTargetSince(peekMark,"STALL_BEGIN",4000),"peek_stall","queue controlled");
            PostCmd(10,0);Intake(0x201,55);File.Delete(_stallPath);
            Assert(await WaitTargetSince(peekMark,"PEEK_SAVED present=1 msg=0",4000),"peek_copy_neutralized","PM_NOREMOVE copy is WM_NULL");
            await Task.Delay(150);Intake(0x202,55);await Task.Delay(150);
            Assert(CountDeliver(TargetSince(peekMark),55)==3,"peek_did_not_remove_input","real dequeue still delivers once");
            _injectLateInit=true;_retiringCookie=session;
            int tag=60;
            for(int cycle=1;cycle<=3;cycle++) {
                for(int i=0;i<12 && !_surface.InputRenewing && _controller.InputRenewals<cycle;i++) {
                    Intake(0x201,tag);await Task.Delay(60);Intake(0x202,tag);await Task.Delay(60);tag++;
                }
                var wait=Stopwatch.StartNew();
                while(_controller.InputRenewals<cycle && wait.ElapsedMilliseconds<20000)await Task.Delay(50);
                Assert(_controller.InputRenewals==cycle,"renew_"+cycle+"_completed","production Controller timer / CloseAsync / Start / Rebind");
                _bridge=_controller.InputBridgeForDiagnostics;
                Assert(_bridge.SessionIdentity!=session,"renew_"+cycle+"_fresh_session",_bridge.SessionIdentity.ToString());
                ulong oldSession=session;session=_bridge.SessionIdentity;
                uint control=RegisterWindowMessage("CF7.WorldPointer.Control.v4");
                SendMessageTimeout(_child,control,new IntPtr(3),new IntPtr(unchecked((long)oldSession)),2,1000,out IntPtr lateResult);
                Assert(lateResult==IntPtr.Zero && _bridge.IsAlive,"renew_"+cycle+"_late_retire_rejected","old control cannot close successor");
                if(cycle==1) {
                    int replayMark=TargetIndex();PostCmd(9,0);await Task.Delay(150);
                    string replay=TargetSince(replayMark);
                    Assert(replay.Contains("REPLAY_SAVED msg=0") && !replay.Contains("LBUTTONDOWN"),"retained_msg_cannot_replay","old copy dispatch after new READY has no input effect");
                }
                Assert(_surface.Handle==stableSurface,"renew_"+cycle+"_surface_stable","input renewal kept output HWND");
                _view.Dispose();_brokerProc=(Process)F(_bridge,"_broker").GetValue(_bridge);
                _view=SharedInputStateView.Open($"Local\\CF7.WorldPointer.{_targetPid}.{_brokerProc.Id}",NativePointerBridge.InputMagic,NativePointerBridge.ProtocolVersion);
                _viewPtr=(IntPtr)F(_view,"_view").GetValue(_view);
                int mark=TargetIndex();Intake(0x201,tag);await Task.Delay(200);Intake(0x202,tag);await Task.Delay(100);
                Assert(CountDeliver(TargetSince(mark),tag)==3,"renew_"+cycle+"_fresh_down_up","one MOVE + one Down + one Up, no pre-FocusChild");tag++;
            }
            bool closed=await _bridge.CloseAsync();Assert(closed,"renew_final_retired","exact broker exit and returned ticket");
            PostCmd(2,0);await _target.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));
            Assert(Regex.IsMatch(TargetLog(),@"IAT_READER calls=[1-9]\d*"),"iat_reader_during_renewals","background import queries survived retirement and rebind");
            HostLog($"RESULT failures={_failures} asserts={_asserts.Count}");
            File.WriteAllLines(Path.Combine(_opt.Evidence,"summary.txt"),_asserts);
        }

        private async Task<bool> WaitFile(string path, int ms)
        {
            var sw = Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < ms) { if (File.Exists(path) && new FileInfo(path).Length > 0) return true; await Task.Delay(50); }
            return false;
        }
    }
}
