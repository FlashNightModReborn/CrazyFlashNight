using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using CF7Launcher.Guardian.InputOwnership;

// Real OS observation fixture only. No game, Flash, save, business grant, or
// formal runtime. Stimuli below are explicitly declared machine injection.
internal sealed class InputOwnershipProbe : Form
{
    private readonly string _output;
    private readonly System.Windows.Forms.Timer _timer = new() { Interval = 20 };
    private readonly List<object> _checks = new();
    private readonly Stopwatch _elapsed = Stopwatch.StartNew();
    private RawInputSource? _source;
    private int _step;
    private long _generation, _packets;
    private bool _held, _registrationStolen;
    private RawSourceStatus? _last;
    private readonly Label _label = new() { Dock = DockStyle.Fill, Padding = new Padding(16) };
    private int _result = 2;

    [STAThread] private static int Main(string[] args)
    {
        if (args.Length != 1) return 2;
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2); Application.EnableVisualStyles();
        using var probe = new InputOwnershipProbe(Path.GetFullPath(args[0])); Application.Run(probe); return probe._result;
    }
    private InputOwnershipProbe(string output)
    {
        _output = output; Directory.CreateDirectory(output);
        Text = "CF7 C1 input foundation automatic probe";
        StartPosition = FormStartPosition.Manual; Location = new(140, 120); ClientSize = new(720, 240);
        Controls.Add(_label);
        File.WriteAllText(Path.Combine(output, "identity.json"), JsonSerializer.Serialize(new {
            pid = Environment.ProcessId, utc = DateTime.UtcNow, exe = Environment.ProcessPath,
            sha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "InputOwnershipProbe.dll")))),
            declaredInjectedStimuli = true, businessInputGranted = false, C1Acceptance = false }));
        Shown += (_, _) => {
            try { _source = new RawInputSource(); _timer.Start(); }
            catch (Exception error) { File.WriteAllText(Path.Combine(_output, "startup-error.txt"), error.ToString()); BeginInvoke(Close); }
        };
        _timer.Tick += (_, _) => Tick();
        FormClosed += (_, _) => {
            _timer.Stop(); if (_held) InjectShift(false);
            if (_registrationStolen) SetRegistration(false);
            try { _source?.Dispose(); } catch (Exception error) { Check("observer_retired", false, error.Message); _result = 2; }
            File.WriteAllText(Path.Combine(output, "result.json"), JsonSerializer.Serialize(new { result = _result, checks = _checks, C1Acceptance = false }, new JsonSerializerOptions { WriteIndented = true }));
        };
    }
    private void Tick()
    {
        if (File.Exists(Path.Combine(_output, "stop.request"))) { Close(); return; }
        if (_source == null) return;
        while (_source.TryRead(out _)) { } // consume without recording external key identities
        var status = _source.Status;
        if (status != _last)
        {
            _last = status;
            File.AppendAllText(Path.Combine(_output, "observations.jsonl"), JsonSerializer.Serialize(new { ms = _elapsed.ElapsedMilliseconds, step = _step, status }) + "\n");
        }
        _label.Text = $"只读自动来源测试，无游戏与业务输入。\n步骤：{_step}\n{status}\n首次激活后自动运行，结果写入本轮证据目录。";
        if (_elapsed.ElapsedMilliseconds > 45000) { Check("automatic_probe_timeout", false, status); Close(); return; }
        GetWindowThreadProcessId(GetForegroundWindow(), out uint pid);
        bool foreground = pid == (uint)Environment.ProcessId;
        // The continue flag is written only after exact foreground verification
        // by the setup runner. It does not provide neutral proof or repair focus later.
        if (!File.Exists(Path.Combine(_output, "continue.flag"))) return;
        if (!foreground) { Check("unexpected_foreground_loss", false, status); Close(); return; }
        switch (_step)
        {
            case 0:
                if (!status.Eligible || !status.Healthy || !status.Neutral) return;
                Check("cold_neutral_without_calibration", true, status); _packets = status.Packets;
                if (!InjectShift(true)) { Close(); return; } _step++; break;
            case 1:
                if (status.Packets <= _packets || status.Neutral) return;
                Check("raw_shift_makes_non_neutral", true, status); _generation = status.Prefix.Generation;
                _source.RequestFaultControl(); _step++; break;
            case 2:
                if (status.Prefix.Generation <= _generation || !status.Healthy || !status.Eligible || status.Reason != "held") return;
                Check("source_recovered_while_preheld_remains_blocked", !status.Neutral, status);
                if (status.Neutral) { Close(); return; }
                _generation = status.Prefix.Generation; _packets = status.Packets;
                if (!InjectShift(false)) { Close(); return; } _step++; break;
            case 3:
                if (!status.Neutral || status.Packets <= _packets) return;
                Check("actual_up_recovers_same_source_generation", status.Prefix.Generation == _generation, status);
                _generation = status.Prefix.Generation; SetRegistration(true); _step++; break;
            case 4:
                if (status.Prefix.Generation <= _generation || status.Healthy) return;
                Check("registration_takeover_blocks_observation", !status.Neutral, status);
                SetRegistration(false); _step++; break;
            case 5:
                if (!status.Healthy || !status.Neutral || !status.Eligible) return;
                Check("registration_release_allows_real_reregistration", true, status);
                _source.Dispose(); _source = null;
                Check("observer_retired", true, null); _result = 0; Close(); break;
        }
    }
    private void Check(string name, bool pass, object? detail) => _checks.Add(new { name, pass, detail });
    private bool InjectShift(bool down)
    {
        var input = new Input { Type = 1, Key = new KeyInput { Scan = 42, Flags = (uint)(8 | (down ? 0 : 2)), Extra = new UIntPtr(0xC110) } };
        bool sent = SendInput(1, new[] { input }, Marshal.SizeOf<Input>()) == 1;
        Check(down ? "declared_shift_down_sent" : "declared_shift_up_sent", sent, null);
        if (sent) _held = down; return sent;
    }
    private void SetRegistration(bool steal)
    {
        var registrations = new[] { new Device { Page = 1, Usage = 2, Flags = steal ? 0x2100u : 1, Target = steal ? Handle : IntPtr.Zero }, new Device { Page = 1, Usage = 6, Flags = steal ? 0x2100u : 1, Target = steal ? Handle : IntPtr.Zero } };
        if (!RegisterRawInputDevices(registrations, 2, (uint)Marshal.SizeOf<Device>())) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        _registrationStolen = steal;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Device { public ushort Page, Usage; public uint Flags; public IntPtr Target; }
    [StructLayout(LayoutKind.Sequential)] private struct KeyInput { public ushort Key, Scan; public uint Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Explicit, Size = 40)] private struct Input { [FieldOffset(0)] public uint Type; [FieldOffset(8)] public KeyInput Key; }
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterRawInputDevices(Device[] devices, uint count, uint size);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
}
