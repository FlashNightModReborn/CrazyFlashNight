using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using CF7Launcher.Guardian.InputOwnership;

// Passive source experiment, not a C1 input owner. Never sends input, captures
// the mouse, changes foreground, opens game data, or grants business input.
// Only mouse buttons / modifier transitions are retained, never typed text.
internal sealed class PhysicalInputProbe : Form
{
    private readonly string output;
    private readonly Label status=new(){Dock=DockStyle.Fill,AutoSize=false,Padding=new Padding(18),Font=new System.Drawing.Font("Microsoft YaHei UI",11)};
    private readonly System.Windows.Forms.Timer timer=new(){Interval=100};
    private readonly Observer observer=new();
    private readonly List<object> evidence=new();
    private int ticks;
    private readonly bool injectedControl;
    private bool controlSent;
    [STAThread] private static int Main(string[] args)
    {
        if(args.Length<1 || args.Length>2 || (args.Length==2 && args[1]!="--injected-control"))return 2;
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);Application.EnableVisualStyles();
        Application.Run(new PhysicalInputProbe(Path.GetFullPath(args[0]),args.Length==2));return 0;
    }
    private PhysicalInputProbe(string path,bool injected)
    {
        injectedControl=injected;
        output=path;Directory.CreateDirectory(path);
        Text="CF7 物理输入来源观察（不运行游戏）";StartPosition=FormStartPosition.Manual;Location=new System.Drawing.Point(120,100);ClientSize=new System.Drawing.Size(760,340);
        Controls.Add(status);timer.Tick+=(_,_)=>UpdateStatus();
        Shown+=(_,_)=>{observer.Start();timer.Start();};
        FormClosed+=(_,_)=>{
            timer.Stop();observer.Dispose();Drain();
            File.WriteAllText(Path.Combine(output,"summary.json"),JsonSerializer.Serialize(new{kind="passive_source_probe_not_C1_acceptance",businessInputGranted=false,observer.RawMouse,observer.RawModifiers,observer.UnmarkedMouse,observer.InjectedMouse,observer.UnmarkedModifiers,observer.InjectedModifiers,observer.KeyboardCallbacks,observer.Dropped,observer.SnapshotMatches,observer.SnapshotRejected,records=evidence.Count},new JsonSerializerOptions{WriteIndented=true}));
        };
        File.WriteAllText(Path.Combine(output,"identity.json"),JsonSerializer.Serialize(new{pid=Environment.ProcessId,utc=DateTime.UtcNow,host=Environment.ProcessPath,injectedControl,sha256=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory,"PhysicalInputProbe.dll")))),businessInputGranted=false}));
    }
    private void Drain()
    {
        var lines=new StringBuilder();while(observer.Records.TryDequeue(out var record)){evidence.Add(record);lines.AppendLine(JsonSerializer.Serialize(record));}
        if(lines.Length>0)File.AppendAllText(Path.Combine(output,"observations.jsonl"),lines.ToString());
    }
    private void UpdateStatus()
    {
        if(File.Exists(Path.Combine(output,"stop.request"))){Close();return;}
        Drain();if(++ticks%5==0)observer.RequestSnapshot();
        if(injectedControl && !controlSent && ticks>=30){controlSent=observer.InjectModifierControl();if(controlSent)observer.RequestPendingSnapshotControl();}
        status.Text="此窗口只观察输入来源，不打开游戏或存档，也不授予业务输入。\n\n"
            +"请在窗口内按住左键，Alt-Tab 切到其他窗口后松开，再返回；\n然后短按一次左右鼠标键，以及 Ctrl / Shift / Alt。\n结束后关闭此窗口，记录自动保存。无需按遍五个鼠标键。\n\n"
            +$"未标记注入的鼠标边沿：{observer.UnmarkedMouse}　注入鼠标边沿：{observer.InjectedMouse}\n"
            +$"Raw Input 鼠标边沿：{observer.RawMouse}　修饰键边沿：{observer.RawModifiers}　键盘回调：{observer.KeyboardCallbacks}\n"
            +$"合格上下文内双快照一致：{observer.SnapshotMatches}　未采纳：{observer.SnapshotRejected}\n"
            +$"记录丢弃：{observer.Dropped}　{observer.State}\n\n"+(injectedControl?"本轮为显式机器注入对照；":"")+"这些计数不是 C1 或焦点问题验收通过的标志。";
    }

    private sealed class Observer : NativeWindow, IDisposable
    {
        internal readonly ConcurrentQueue<object> Records=new();
        internal long UnmarkedMouse,InjectedMouse,RawMouse,UnmarkedModifiers,InjectedModifiers,RawModifiers,KeyboardCallbacks,SnapshotMatches,SnapshotRejected,Dropped;
        internal string State="启动中";
        private readonly int[] keys={1,2,4,5,6,16,17,18,160,161,162,163,164,165};
        private readonly PhysicalInputLedger ledger=new(new[]{1,2,4,5,6,16,17,18,160,161,162,163,164,165});
        private readonly RawModifierTracker rawModifierShadow=new();
        private Thread? thread;
        private IntPtr mouseHook,keyHook;
        private HookProc? mouseProc,keyProc;
        private long serial;
        private readonly ManualResetEventSlim stopped=new(false);
        private bool disposed;
        private bool forcePendingSnapshot;
        internal void Start()
        {
            thread=new Thread(()=>{
                try {
                    CreateHandle(new CreateParams{Caption="CF7 passive input observer",Parent=new IntPtr(-3)});
                    mouseProc=Mouse;keyProc=Keyboard;
                    mouseHook=SetWindowsHookEx(14,mouseProc,GetModuleHandle(null),0);
                    keyHook=SetWindowsHookEx(13,keyProc,GetModuleHandle(null),0);
                    var devices=new[]{new Device{Page=1,Usage=2,Flags=0x100,Target=Handle},new Device{Page=1,Usage=6,Flags=0x100,Target=Handle}};
                    if(mouseHook==IntPtr.Zero || keyHook==IntPtr.Zero || !RegisterRawInputDevices(devices,2,(uint)Marshal.SizeOf<Device>()))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                    // This ledger is only a hypothesis under observation. A
                    // successful install does not certify future hook continuity.
                    ledger.ConfirmSources(ledger.Prefix);State="已登记；观测连续性尚未认证";
                    Record("registered",new{generation=ledger.Prefix.Generation,mouseHook=mouseHook.ToInt64(),keyboardHook=keyHook.ToInt64(),thread=GetCurrentThreadId()});Application.Run();
                } catch(Exception e){State="失败："+e.Message;Record("fault",new{error=e.GetType().Name,message=e.Message});}
                finally {
                    if(mouseHook!=IntPtr.Zero)UnhookWindowsHookEx(mouseHook);
                    if(keyHook!=IntPtr.Zero)UnhookWindowsHookEx(keyHook);
                    if(Handle!=IntPtr.Zero) {
                        RegisterRawInputDevices(new[]{new Device{Page=1,Usage=2,Flags=1},new Device{Page=1,Usage=6,Flags=1}},2,(uint)Marshal.SizeOf<Device>());
                        DestroyHandle();
                    }
                    stopped.Set();
                }
            }){IsBackground=true,Name="CF7 passive input observer"};thread.SetApartmentState(ApartmentState.STA);thread.Start();
        }
        private void Record(string kind,object detail)
        {
            if(Records.Count>=4096){Interlocked.Increment(ref Dropped);ledger.Invalidate("trace_overflow");return;}
            Records.Enqueue(new{kind,serial=Interlocked.Increment(ref serial),qpc=Stopwatch.GetTimestamp(),frequency=Stopwatch.Frequency,detail});
        }
        internal bool InjectModifierControl()
        {
            GetWindowThreadProcessId(GetForegroundWindow(),out uint pid);if(pid!=(uint)Environment.ProcessId)return false;
            Record("declared_native_SendInput_control",new{key="VK_CONTROL",inputSource="injected",businessGrant=false});
            var down=new Input{Type=1,Key=new KeyInput{Key=17,Extra=new UIntPtr(0xC109)}};
            var up=new Input{Type=1,Key=new KeyInput{Key=17,Flags=2,Extra=new UIntPtr(0xC109)}};
            uint sent=SendInput(2,new[]{down,up},Marshal.SizeOf<Input>());
            if(sent==1)SendInput(1,new[]{up},Marshal.SizeOf<Input>());
            Record("declared_native_SendInput_result",new{sent});
            // Distinguish virtual-key-only injection from a scan-code injection;
            // neither is labelled hardware input.
            down.Key.Key=0;down.Key.Scan=0x1D;down.Key.Flags=8;
            up.Key.Key=0;up.Key.Scan=0x1D;up.Key.Flags=10;
            sent=SendInput(2,new[]{down,up},Marshal.SizeOf<Input>());
            if(sent==1)SendInput(1,new[]{up},Marshal.SizeOf<Input>());
            Record("declared_scan_SendInput_result",new{sent});
            return true;
        }
        private IntPtr Mouse(int code,IntPtr wp,IntPtr lp)
        {
            if(code>=0) {
                int message=wp.ToInt32();var d=Marshal.PtrToStructure<MouseData>(lp);
                int key=message is 0x201 or 0x202?1:message is 0x204 or 0x205?2:message is 0x207 or 0x208?4:message is 0x20B or 0x20C?((d.Data>>16)==1?5:6):0;
                if(key!=0) {
                    bool down=message is 0x201 or 0x204 or 0x207 or 0x20B,injected=(d.Flags&1)!=0;
                    if(injected)Interlocked.Increment(ref InjectedMouse);else Interlocked.Increment(ref UnmarkedMouse);
                    ledger.Observe(ledger.Prefix.Generation,key,down,injected?InputObservationSource.Injected:InputObservationSource.Unmarked);
                    Record("ll_mouse",new{key,down,injected,time=d.Time,extra=d.Extra.ToUInt64(),foreground=GetForegroundWindow().ToInt64()});
                }
            }
            return CallNextHookEx(mouseHook,code,wp,lp);
        }
        private IntPtr Keyboard(int code,IntPtr wp,IntPtr lp)
        {
            Interlocked.Increment(ref KeyboardCallbacks);
            if(code>=0) {
                var d=Marshal.PtrToStructure<KeyData>(lp);
                // Bucket only; never retain non-modifier key identities or text.
                Record("ll_keyboard_callback",new{code,message=wp.ToInt32(),modifier=d.Key is 16 or 17 or 18 || d.Key>=160 && d.Key<=165,injected=(d.Flags&0x10)!=0});
                if(d.Key is 16 or 17 or 18 || d.Key>=160 && d.Key<=165) {
                    bool down=wp.ToInt32() is 0x100 or 0x104,injected=(d.Flags&0x10)!=0;
                    if(injected)Interlocked.Increment(ref InjectedModifiers);else Interlocked.Increment(ref UnmarkedModifiers);
                    ledger.Observe(ledger.Prefix.Generation,(int)d.Key,down,injected?InputObservationSource.Injected:InputObservationSource.Unmarked);
                    Record("ll_modifier",new{key=d.Key,scan=d.Scan,flags=d.Flags,down,injected,time=d.Time});
                }
            }
            return CallNextHookEx(keyHook,code,wp,lp);
        }
        internal void RequestSnapshot(){if(Handle!=IntPtr.Zero)PostMessage(Handle,0x8001,IntPtr.Zero,IntPtr.Zero);}
        internal void RequestPendingSnapshotControl(){if(Handle!=IntPtr.Zero)PostMessage(Handle,0x8004,IntPtr.Zero,IntPtr.Zero);}
        protected override void WndProc(ref Message m)
        {
            if(m.Msg==0x8002){Application.ExitThread();return;}
            if(m.Msg==0x8004){forcePendingSnapshot=true;Sample();return;}
            if(m.Msg==0x8001){Sample();return;}
            if(m.Msg==0xFF)ReadRaw(m.LParam);
            base.WndProc(ref m); // foreground WM_INPUT cleanup remains owned by Windows
        }
        private void ReadRaw(IntPtr handle)
        {
            uint size=0;uint header=(uint)Marshal.SizeOf<RawHeader>();
            if(GetRawInputData(handle,0x10000003,IntPtr.Zero,ref size,header)!=0 || size<header || size>16384){Record("raw_error",new{size});return;}
            IntPtr buffer=Marshal.AllocHGlobal((int)size);
            try {
                if(GetRawInputData(handle,0x10000003,buffer,ref size,header)!=size){Record("raw_error",new{size});return;}
                var head=Marshal.PtrToStructure<RawHeader>(buffer);IntPtr body=IntPtr.Add(buffer,(int)header);int time=GetMessageTime();
                if(head.Type==0 && size>=header+24) {
                    int flags=(ushort)Marshal.ReadInt16(body,4);
                    if((flags&0x3FF)!=0){Interlocked.Add(ref RawMouse,System.Numerics.BitOperations.PopCount((uint)(flags&0x3FF)));Record("raw_mouse",new{flags=flags&0x3FF,time,device=head.Device.ToInt64()});}
                } else if(head.Type==1 && size>=header+16) {
                    int key=(ushort)Marshal.ReadInt16(body,6);
                    if(key is 16 or 17 or 18 || key>=160 && key<=165){
                        int flags=(ushort)Marshal.ReadInt16(body,2),scan=(ushort)Marshal.ReadInt16(body,0);
                        Interlocked.Increment(ref RawModifiers);Record("raw_modifier",new{key,flags,scan,time,device=head.Device.ToInt64()});
                        var disposition=rawModifierShadow.Observe(head.Device.ToInt64(),key,scan,flags,out var state);
                        Record("raw_modifier_shadow",new{disposition=disposition.ToString(),state,businessGrant=false});
                    }
                }
            } finally {Marshal.FreeHGlobal(buffer);}
        }
        private void Sample()
        {
            IntPtr foreground=GetForegroundWindow();GetWindowThreadProcessId(foreground,out uint pid);
            // Restrict qualification to this same-process foreground. External
            // Up is still observed; an external foreground's zero query is never
            // accepted as a baseline by this experiment.
            if(pid!=(uint)Environment.ProcessId){Interlocked.Increment(ref SnapshotRejected);return;}
            IntPtr desktop=OpenInputDesktop(0,false,0x9);
            try {
                string active=DesktopName(desktop),ours=DesktopName(GetThreadDesktop(GetCurrentThreadId()));
                bool registered=RegistrationsMatch();
                bool eligible=desktop!=IntPtr.Zero && active.Length!=0 && active==ours && GetSystemMetrics(23)==0 && registered;
                var fence=ledger.Prefix;var first=keys.ToDictionary(k=>k,k=>(GetAsyncKeyState(k)&0x8000)!=0);
                var second=keys.ToDictionary(k=>k,k=>(GetAsyncKeyState(k)&0x8000)!=0);
                bool actualDrained=((GetQueueStatus(0x407)>>16)&0x407)==0;
                bool forcedPending=forcePendingSnapshot;forcePendingSnapshot=false;
                bool drained=actualDrained && !forcedPending;
                eligible &= GetForegroundWindow()==foreground;
                bool accepted=ledger.TryReconcile(fence,first,second,eligible,drained);
                if(accepted)Interlocked.Increment(ref SnapshotMatches);else Interlocked.Increment(ref SnapshotRejected);
                Record("snapshot_observation",new{accepted,eligible,drained,actualDrained,forcedPending,registered,activeDesktop=active,threadDesktop=ours,prefix=ledger.Prefix,blockReason=ledger.BlockReason,down=second.Where(kv=>kv.Value).Select(kv=>kv.Key).ToArray(),businessGrant=false});
            } finally {if(desktop!=IntPtr.Zero)CloseDesktop(desktop);}
        }
        private bool RegistrationsMatch()
        {
            uint count=0;uint size=(uint)Marshal.SizeOf<Device>();
            if(GetRegisteredRawInputDevices(null,ref count,size)==uint.MaxValue || count>32)return false;
            var devices=new Device[count];if(GetRegisteredRawInputDevices(devices,ref count,size)==uint.MaxValue)return false;
            return new ushort[]{2,6}.All(usage=>devices.Any(d=>d.Page==1 && d.Usage==usage && d.Target==Handle && (d.Flags&0x100)!=0));
        }
        private static string DesktopName(IntPtr desktop)
        {
            if(desktop==IntPtr.Zero)return "";var name=new StringBuilder(256);
            return GetUserObjectInformation(desktop,2,name,512,out _)?name.ToString():"";
        }
        public void Dispose()
        {
            if(disposed)return;disposed=true;
            if(Handle!=IntPtr.Zero)PostMessage(Handle,0x8002,IntPtr.Zero,IntPtr.Zero);
            if(thread!=null && !stopped.Wait(3000))Record("stop_unconfirmed",new{businessGrant=false});
        }
        private delegate IntPtr HookProc(int code,IntPtr wp,IntPtr lp);
        [StructLayout(LayoutKind.Sequential)] private struct Point {public int X,Y;}
        [StructLayout(LayoutKind.Sequential)] private struct MouseData {public Point Point;public uint Data,Flags,Time;public UIntPtr Extra;}
        [StructLayout(LayoutKind.Sequential)] private struct KeyData {public uint Key,Scan,Flags,Time;public UIntPtr Extra;}
        [StructLayout(LayoutKind.Sequential)] private struct Device {public ushort Page,Usage;public uint Flags;public IntPtr Target;}
        [StructLayout(LayoutKind.Sequential)] private struct RawHeader {public uint Type,Size;public IntPtr Device,Parameter;}
        [StructLayout(LayoutKind.Sequential)] private struct KeyInput {public ushort Key,Scan;public uint Flags,Time;public UIntPtr Extra;}
        [StructLayout(LayoutKind.Explicit,Size=40)] private struct Input {[FieldOffset(0)] public uint Type;[FieldOffset(8)]public KeyInput Key;}
        [DllImport("user32.dll",SetLastError=true)] private static extern uint SendInput(uint count,Input[] input,int size);
        [DllImport("user32.dll",SetLastError=true)] private static extern IntPtr SetWindowsHookEx(int kind,HookProc fn,IntPtr module,uint thread);
        [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr h);
        [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr h,int code,IntPtr wp,IntPtr lp);
        [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr h,int msg,IntPtr wp,IntPtr lp);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
        [DllImport("user32.dll")] private static extern uint GetQueueStatus(uint flags);
        [DllImport("user32.dll")] private static extern int GetMessageTime();
        [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
        [DllImport("user32.dll",SetLastError=true)] private static extern bool RegisterRawInputDevices(Device[] devices,uint count,uint size);
        [DllImport("user32.dll")] private static extern uint GetRegisteredRawInputDevices([Out] Device[]? devices,ref uint count,uint size);
        [DllImport("user32.dll")] private static extern uint GetRawInputData(IntPtr h,uint command,IntPtr data,ref uint size,uint headerSize);
        [DllImport("user32.dll",SetLastError=true)] private static extern IntPtr OpenInputDesktop(uint flags,bool inherit,uint access);
        [DllImport("user32.dll")] private static extern IntPtr GetThreadDesktop(uint thread);
        [DllImport("user32.dll")] private static extern bool CloseDesktop(IntPtr desktop);
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern bool GetUserObjectInformation(IntPtr h,int index,StringBuilder data,uint length,out uint needed);
        [DllImport("kernel32.dll")] private static extern IntPtr GetModuleHandle(string? name);
        [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    }
}
