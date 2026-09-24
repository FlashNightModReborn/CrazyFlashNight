#nullable enable
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace CF7Launcher.Guardian.InputOwnership;

internal sealed record RawSourceStatus(ObservationPrefix Prefix, bool Healthy, bool Neutral, bool Eligible,
    string Reason, long Packets, long Recoveries, long DeviceChanges, long Dropped);
internal sealed record RawSourceBatch(ObservationPrefix Prefix, ObservedInputEdge[] Edges, int ScreenX, int ScreenY, uint MessageTime);

/// <summary>
/// Isolated-candidate Raw Input observer. Owns one dedicated message queue and
/// never swallows input, changes focus, synthesizes events or reads game data.
/// It refuses another in-process Raw Input owner instead of stealing its TLCs.
/// No normal launcher startup constructs this adapter yet. Its status is not an
/// authorization token: the routing adapter must serialize foreground, geometry,
/// observation-prefix drain and endpoint receipts before business dispatch.
/// </summary>
internal sealed class RawInputSource : NativeWindow, IDisposable
{
    private const int SnapshotMessage = 0x8051, StopMessage = 0x8052, FaultMessage = 0x8053, ControlMessage = 0x8054;
    private const uint InputFlags = 0x2100; // INPUTSINK | DEVNOTIFY, never NOLEGACY
    private readonly PhysicalInputLedger _ledger = new(RawDeviceLedger.SnapshotKeys);
    private readonly RawDeviceLedger _devices = new();
    private readonly ConcurrentQueue<RawSourceBatch> _batches = new();
    private sealed class ControlWork(Action execute, Action<Exception> reject)
    {
        private int state;
        internal void Execute() { if (Interlocked.CompareExchange(ref state, 1, 0) == 0) execute(); }
        internal void Reject(Exception error) { if (Interlocked.CompareExchange(ref state, 2, 0) == 0) reject(error); }
    }
    private readonly ConcurrentQueue<ControlWork> _controls = new();
    private readonly ManualResetEventSlim _started = new(false), _stopped = new(false);
    private readonly Thread _thread;
    private RawSourceStatus _status = new(new(1, 0), false, false, false, "boot_unknown", 0, 0, 0, 0);
    private long _packets, _recoveries, _deviceChanges, _dropped;
    private bool _disposed, _eligible, _registered, _sampling;
    private Exception? _startError;
    private string _registrationFailure = "";
    private HashSet<(IntPtr Handle, uint Type)> _topology = new();
    private string _environmentDiagnostic = "not_sampled";

    internal RawSourceStatus Status => Volatile.Read(ref _status);
    internal string EnvironmentDiagnostic => Volatile.Read(ref _environmentDiagnostic);
    internal bool TryRead(out RawSourceBatch? batch) => _batches.TryDequeue(out batch);
    // Subscribers run on the observer thread: bounded state updates / posting
    // only. Never perform UI, I/O, waits or application callbacks here.
    internal event Action<PhysicalInputLedger, RawSourceBatch>? BatchObserved;
    internal event Action<RawSourceStatus>? StatusChanged;

    internal Task<T> OnObserver<T>(Func<PhysicalInputLedger, bool, T> action)
    {
        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        if (_disposed || _stopped.IsSet || _controls.Count >= 64) {
            completion.SetException(new InvalidOperationException("Observer control lane unavailable")); return completion.Task;
        }
        var work = new ControlWork(() => {
            try { completion.TrySetResult(action(_ledger, NeutralFence())); }
            catch (Exception error) { completion.TrySetException(error); Fault("control_callback_failed"); }
        }, error => completion.TrySetException(error));
        _controls.Enqueue(work);
        if (!PostMessage(Handle, ControlMessage, IntPtr.Zero, IntPtr.Zero))
            work.Reject(new Win32Exception(Marshal.GetLastWin32Error()));
        return completion.Task;
    }

    internal RawInputSource()
    {
        _thread = new Thread(Run) { IsBackground = true, Name = "CF7 isolated Raw Input source" };
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();
        if (!_started.Wait(5000)) {
            _disposed = true;
            if (Handle != IntPtr.Zero) PostMessage(Handle, StopMessage, IntPtr.Zero, IntPtr.Zero);
            throw new TimeoutException("Raw Input observer did not start");
        }
        if (_startError != null) throw new InvalidOperationException("Raw Input observer failed", _startError);
    }

    private void Run()
    {
        try
        {
            CreateHandle(new CreateParams { Caption = "CF7 isolated input source", Parent = new IntPtr(-3) });
            if (_disposed) return;
            if (!TryRegister()) throw new InvalidOperationException("Raw Input registration: " + _registrationFailure);
            if (SetTimer(Handle, new UIntPtr(1), 50, IntPtr.Zero) == UIntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            _started.Set(); Application.Run();
        }
        catch (Exception error)
        {
            _startError = error; Fault("observer_exception"); _started.Set();
        }
        finally
        {
            if (Handle != IntPtr.Zero)
            {
                KillTimer(Handle, new UIntPtr(1));
                // Registration is per-process. Never remove a registration now
                // owned by another component, even during failed startup.
                var ours = Registrations()?.Where(device => device.Page == 1 && device.Usage is 2 or 6 && device.Target == Handle)
                    .Select(device => new Device { Page = 1, Usage = device.Usage, Flags = 1 }).ToArray();
                if (ours is { Length: > 0 }) RegisterRawInputDevices(ours, (uint)ours.Length, (uint)Marshal.SizeOf<Device>());
                DestroyHandle();
            }
            _ledger.Invalidate("observer_stopped"); Publish(); _stopped.Set();
            while (_controls.TryDequeue(out var control)) control.Reject(new ObjectDisposedException(nameof(RawInputSource)));
        }
    }

    internal void RequestSnapshot() { if (!_disposed && Handle != IntPtr.Zero) PostMessage(Handle, SnapshotMessage, IntPtr.Zero, IntPtr.Zero); }
    // Explicit fault injection for automated negative controls; never a fake
    // success path. Recovery uses the same real registration/snapshot code.
    internal void RequestFaultControl() { if (!_disposed && Handle != IntPtr.Zero) PostMessage(Handle, FaultMessage, IntPtr.Zero, IntPtr.Zero); }

    protected override void WndProc(ref Message message)
    {
        try
        {
            if (message.Msg == StopMessage) { Application.ExitThread(); return; }
            if (message.Msg == FaultMessage) { Fault("declared_source_fault"); return; }
            if (message.Msg == ControlMessage) {
                if (_controls.TryDequeue(out var control)) control.Execute();
                Publish(); return;
            }
            if (message.Msg == SnapshotMessage || message.Msg == 0x113) { Sample(); return; }
            if (message.Msg == 0xFE) CheckTopology();
            if (message.Msg == 0xFF) ReadRaw(message.LParam);
        }
        catch (Exception) { Fault("observer_message_failure"); }
        base.WndProc(ref message); // DefWindowProc owns foreground WM_INPUT cleanup
    }

    private bool TryRegister()
    {
        var current = Registrations();
        if (current == null) { _registrationFailure = "enumeration failed"; return false; }
        if (current.Any(device => device.Page == 1 && device.Usage is 2 or 6 && device.Target != Handle))
        { _registrationFailure = "foreign owner: " + string.Join(";", current.Select(device => $"{device.Page}/{device.Usage}/{device.Flags:X}/{device.Target:X}")); return false; }
        var desired = new[] { new Device { Page = 1, Usage = 2, Flags = InputFlags, Target = Handle }, new Device { Page = 1, Usage = 6, Flags = InputFlags, Target = Handle } };
        if (!RegisterRawInputDevices(desired, 2, (uint)Marshal.SizeOf<Device>()))
        { _registrationFailure = "register failed: " + Marshal.GetLastWin32Error(); return false; }
        if (!RegistrationsMatch())
        { _registrationFailure = "readback mismatch: " + string.Join(";", (Registrations() ?? Array.Empty<Device>()).Select(device => $"{device.Page}/{device.Usage}/{device.Flags:X}/{device.Target:X}")); return false; }
        var topology = ReadTopology();
        if (topology == null) { _registrationFailure = "device enumeration failed"; return false; }
        _topology = topology;
        _registered = true; _devices.Reset();
        _ledger.ConfirmSources(_ledger.Prefix); _recoveries++; Publish(); return true;
    }

    private void Fault(string reason)
    {
        _ledger.Invalidate(reason); _registered = false; _devices.Reset(); _eligible = false;
        while (_batches.TryDequeue(out _)) { }
        Publish();
    }

    private void ReadRaw(IntPtr handle)
    {
        if (!_registered || !RegistrationsMatch()) { Fault("registration_lost"); return; }
        uint size = 0, headerSize = (uint)Marshal.SizeOf<RawHeader>();
        if (GetRawInputData(handle, 0x10000003, IntPtr.Zero, ref size, headerSize) != 0 || size < headerSize || size > 16384)
        { Fault("raw_size_invalid"); return; }
        IntPtr memory = Marshal.AllocHGlobal((int)size);
        try
        {
            uint actual = GetRawInputData(handle, 0x10000003, memory, ref size, headerSize);
            if (actual != size) { Fault("raw_read_failed"); return; }
            var header = Marshal.PtrToStructure<RawHeader>(memory);
            if (header.Size != size) { Fault("raw_header_invalid"); return; }
            if (header.Device != IntPtr.Zero && !_topology.Contains((header.Device, header.Type))) { Fault("unknown_raw_device"); return; }
            IntPtr data = IntPtr.Add(memory, (int)headerSize);
            RawPacketResult result; RawKeyChange[] changes;
            if (header.Type == 0 && size >= headerSize + 24)
                result = _devices.Mouse(header.Device.ToInt64(), (ushort)Marshal.ReadInt16(data, 4), out changes);
            else if (header.Type == 1 && size >= headerSize + 16)
                result = _devices.Keyboard(header.Device.ToInt64(), (ushort)Marshal.ReadInt16(data, 6),
                    (ushort)Marshal.ReadInt16(data, 0), (ushort)Marshal.ReadInt16(data, 2), out changes);
            else { Fault("raw_type_invalid"); return; }
            _packets++;
            if (result == RawPacketResult.Invalid) { Fault("raw_packet_ambiguous"); return; }
            if (result == RawPacketResult.Ignored) { Publish(); return; }
            var edges = changes.Select(change => _ledger.Observe(_ledger.Prefix.Generation, change.Key, change.Down, InputObservationSource.Unmarked)!.Value).ToArray();
            if (_batches.Count >= 256) { _dropped++; Fault("consumer_queue_overflow"); return; }
            uint position = GetMessagePos();
            var batch = new RawSourceBatch(_ledger.Prefix, edges, (short)(position & 0xffff), (short)(position >> 16), unchecked((uint)GetMessageTime()));
            _batches.Enqueue(batch); Publish(); BatchObserved?.Invoke(_ledger, batch);
        }
        finally { Marshal.FreeHGlobal(memory); }
    }

    private void Sample()
    {
        if (_sampling) return;
        _sampling = true;
        IntPtr desktop = IntPtr.Zero;
        try
        {
            if (!_registered && !TryRegister()) { Publish(); return; }
            if (!RegistrationsMatch()) { Fault("registration_lost"); return; }
            if (!CheckTopology()) return;
            var foreground = GetForegroundWindow(); GetWindowThreadProcessId(foreground, out uint pid);
            desktop = OpenInputDesktop(0, false, 0x9);
            string active = DesktopName(desktop), ours = DesktopName(GetThreadDesktop(GetCurrentThreadId()));
            Volatile.Write(ref _environmentDiagnostic, $"inputDesktopOpen={desktop != IntPtr.Zero};activeDesktop={active};threadDesktop={ours};foreground={foreground};foregroundPid={pid};observerPid={Environment.ProcessId}");
            _eligible = pid == (uint)Environment.ProcessId && desktop != IntPtr.Zero && active.Length > 0 && active == ours && GetSystemMetrics(23) == 0;
            if (!_eligible) { _ledger.RequireReconciliation("query_environment_unqualified"); Publish(); return; }
            // Do not let a timer snapshot consume a new Down before its queued
            // Raw packet arrives (that turns the real Begin into a duplicate).
            // A qualified continuous stream owns known state. Snapshots rebuild
            // Unknown/pre-held state; NeutralFence independently gates grants.
            if (_ledger.HasQualifiedBaseline && !_devices.HasUnattributedHolds) { Publish(); return; }
            var fence = _ledger.Prefix;
            var before = RawDeviceLedger.SnapshotKeys.ToDictionary(key => key, key => (GetAsyncKeyState(key) & 0x8000) != 0);
            var after = RawDeviceLedger.SnapshotKeys.ToDictionary(key => key, key => (GetAsyncKeyState(key) & 0x8000) != 0);
            bool drained = ((GetQueueStatus(0x407) >> 16) & 0x407) == 0;
            if (!RegistrationsMatch()) { Fault("registration_lost"); return; }
            bool stableEnvironment = GetForegroundWindow() == foreground;
            if (!stableEnvironment) { _eligible = false; _ledger.RequireReconciliation("foreground_raced"); Publish(); return; }
            if (!_devices.SnapshotConsistent(before) || !_devices.SnapshotConsistent(after))
                _ledger.RequireReconciliation("device_snapshot_conflict");
            // A healthy idle check must not continuously invalidate a READY
            // round. Reconcile when needed; any pending/racing/held observation
            // still revokes the proof. No poll invents an input edge.
            else if (!(_ledger.IsNeutral && drained && before.Values.All(down => !down) && after.Values.All(down => !down))
                && _ledger.TryReconcile(fence, before, after, true, drained)) _devices.Reconcile(after);
            Publish();
        }
        finally { if (desktop != IntPtr.Zero) CloseDesktop(desktop); _sampling = false; }
    }

    private void Publish()
    {
        var next = new RawSourceStatus(_ledger.Prefix, _ledger.SourcesHealthy, _ledger.IsNeutral, _eligible,
            _ledger.BlockReason, _packets, _recoveries, _deviceChanges, _dropped);
        var previous = Status; Volatile.Write(ref _status, next);
        if (next != previous) {
            try { StatusChanged?.Invoke(next); }
            catch (Exception) { StatusChanged = null; BatchObserved = null; Fault("status_consumer_failed"); }
        }
    }

    private bool NeutralFence()
    {
        if (!_ledger.IsNeutral || !_eligible || !_registered || !RegistrationsMatch()
            || ((GetQueueStatus(0x407) >> 16) & 0x407) != 0) return false;
        var foreground = GetForegroundWindow(); GetWindowThreadProcessId(foreground, out uint pid);
        if (pid != (uint)Environment.ProcessId || GetSystemMetrics(23) != 0) return false;
        IntPtr desktop = OpenInputDesktop(0, false, 0x9);
        try {
            string active = DesktopName(desktop);
            if (desktop == IntPtr.Zero || active.Length == 0 || active != DesktopName(GetThreadDesktop(GetCurrentThreadId()))) return false;
            // Observe current state without writing it into the edge ledger.
            // A Down ahead of Raw prevents grant, but remains a real new Begin.
            for (int pass = 0; pass < 2; pass++)
                foreach (int key in RawDeviceLedger.SnapshotKeys) if ((GetAsyncKeyState(key) & 0x8000) != 0) return false;
            return GetForegroundWindow() == foreground && RegistrationsMatch() && ((GetQueueStatus(0x407) >> 16) & 0x407) == 0;
        } finally { if (desktop != IntPtr.Zero) CloseDesktop(desktop); }
    }

    private bool CheckTopology()
    {
        var current = ReadTopology();
        if (current != null && current.SetEquals(_topology)) return true;
        _deviceChanges++; Fault("device_topology_changed"); return false;
    }
    private static HashSet<(IntPtr, uint)>? ReadTopology()
    {
        uint count = 0, size = (uint)Marshal.SizeOf<RawDevice>();
        if (GetRawInputDeviceList(null, ref count, size) == uint.MaxValue || count > 1024) return null;
        if (count == 0) return new();
        var devices = new RawDevice[count];
        uint actual = GetRawInputDeviceList(devices, ref count, size);
        if (actual == uint.MaxValue || actual > devices.Length) return null;
        return devices.Take((int)actual).Where(device => device.Type is 0 or 1).Select(device => (device.Handle, device.Type)).ToHashSet();
    }

    private bool RegistrationsMatch()
    {
        var current = Registrations();
        // This Windows build returns INPUTSINK (0x100) without DEVNOTIFY after
        // successfully registering 0x2100. Verify routing/legacy flags exactly;
        // DEVNOTIFY registration success is separate from its readback mask.
        return current != null && new ushort[] { 2, 6 }.All(usage => current.Any(device => device.Page == 1 && device.Usage == usage && device.Target == Handle && (device.Flags & ~0x2000u) == 0x100));
    }
    private static Device[]? Registrations()
    {
        uint count = 0, size = (uint)Marshal.SizeOf<Device>();
        if (GetRegisteredRawInputDevices(null, ref count, size) == uint.MaxValue || count > 128) return null;
        if (count == 0) return Array.Empty<Device>();
        var result = new Device[count];
        uint actual = GetRegisteredRawInputDevices(result, ref count, size);
        return actual == uint.MaxValue || actual > result.Length ? null : result.Take((int)actual).ToArray();
    }
    private static string DesktopName(IntPtr desktop)
    {
        if (desktop == IntPtr.Zero) return "";
        var name = new StringBuilder(256);
        return GetUserObjectInformation(desktop, 2, name, 512, out _) ? name.ToString() : "";
    }
    public void Dispose()
    {
        if (_disposed) return; _disposed = true;
        if (Handle != IntPtr.Zero && !PostMessage(Handle, StopMessage, IntPtr.Zero, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
        if (!_stopped.Wait(5000)) throw new TimeoutException("Raw Input observer retirement unconfirmed");
    }

    [StructLayout(LayoutKind.Sequential)] private struct Device { public ushort Page, Usage; public uint Flags; public IntPtr Target; }
    [StructLayout(LayoutKind.Sequential)] private struct RawHeader { public uint Type, Size; public IntPtr Device, Parameter; }
    [StructLayout(LayoutKind.Sequential)] private struct RawDevice { public IntPtr Handle; public uint Type; }
    [DllImport("user32.dll")] private static extern uint GetRawInputDeviceList([Out] RawDevice[]? devices, ref uint count, uint size);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterRawInputDevices(Device[] devices, uint count, uint size);
    [DllImport("user32.dll")] private static extern uint GetRegisteredRawInputDevices([Out] Device[]? devices, ref uint count, uint size);
    [DllImport("user32.dll")] private static extern uint GetRawInputData(IntPtr input, uint command, IntPtr data, ref uint size, uint headerSize);
    [DllImport("user32.dll")] private static extern uint GetQueueStatus(uint flags);
    [DllImport("user32.dll")] private static extern uint GetMessagePos();
    [DllImport("user32.dll")] private static extern int GetMessageTime();
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] private static extern IntPtr GetThreadDesktop(uint id);
    [DllImport("user32.dll")] private static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetUserObjectInformation(IntPtr handle, int index, StringBuilder data, uint length, out uint needed);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll", SetLastError = true)] private static extern bool PostMessage(IntPtr window, int message, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll", SetLastError = true)] private static extern UIntPtr SetTimer(IntPtr window, UIntPtr id, uint interval, IntPtr callback);
    [DllImport("user32.dll")] private static extern bool KillTimer(IntPtr window, UIntPtr id);
}
