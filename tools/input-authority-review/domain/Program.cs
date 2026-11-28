using System.ComponentModel;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Loader;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

internal static class Program
{
    private const BindingFlags Instance = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance;
    private const BindingFlags Static = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static;
    private const string Guardian = "CF7Launcher.Guardian.";

    private const uint MouseMove = 0x0200;
    private const uint LeftDown = 0x0201;
    private const uint LeftUp = 0x0202;

    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern IntPtr GetThreadDesktop(uint threadId);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] private static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool GetUserObjectInformationW(IntPtr handle, int index, StringBuilder info, int length, out int needed);
    [DllImport("user32.dll")] private static extern IntPtr SendMessageW(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    private static object Invoke(object target, string method, params object[] args)
    {
        var member = target.GetType().GetMethods(Instance).Single(candidate =>
        {
            var parameters = candidate.GetParameters();
            return candidate.Name == method && parameters.Length >= args.Length &&
                parameters.Skip(args.Length).All(parameter => parameter.IsOptional);
        });
        if (member.GetParameters().Length == args.Length)
            return member.Invoke(target, args);
        return member.Invoke(target, args.Concat(member.GetParameters().Skip(args.Length)
            .Select(parameter => parameter.DefaultValue)).ToArray());
    }

    private static object Property(object target, string name) => target.GetType().GetProperty(name, Instance).GetValue(target);
    private static object Field(object target, string name) => target.GetType().GetField(name, Instance).GetValue(target);
    private static object Construct(Type type, params object[] args) => Activator.CreateInstance(type, Instance, null, args, null);

    private static string DesktopName(IntPtr desktop)
    {
        var name = new StringBuilder(256);
        if (!GetUserObjectInformationW(desktop, 2, name, name.Capacity * sizeof(char), out _))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        return name.ToString();
    }

    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Length != 5) return 64;
        string runId = args[3];
        string startedUtc = DateTimeOffset.UtcNow.ToString("O");
        var rows = new List<Trial>();

        void Write(object data)
        {
            using var output = new FileStream(args[2], FileMode.CreateNew, FileAccess.Write);
            JsonSerializer.Serialize(output, data, new JsonSerializerOptions { WriteIndented = true });
        }

        try
        {
            string desktop = DesktopName(GetThreadDesktop(GetCurrentThreadId()));
            IntPtr input = OpenInputDesktop(0, false, 1 /* DESKTOP_READOBJECTS */);
            string inputDesktop;
            try { inputDesktop = DesktopName(input); }
            finally { if (input != IntPtr.Zero) CloseDesktop(input); }
            if (desktop != "CF7Review-" + runId || desktop == inputDesktop)
                throw new InvalidOperationException("This probe requires its own non-input desktop.");

            string runtime = Path.GetFullPath(args[0]);
            string corePath = Path.Combine(runtime, "CRAZYFLASHER7MercenaryEmpire.Core.dll");
            string coreSha256;
            using (var coreBytes = File.OpenRead(corePath)) coreSha256 = Convert.ToHexString(SHA256.HashData(coreBytes));
            if (!string.Equals(coreSha256, args[4], StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("The candidate Core bytes changed.");
            AssemblyLoadContext.Default.Resolving += (context, name) =>
            {
                var path = Path.Combine(runtime, name.Name + ".dll");
                return File.Exists(path) ? context.LoadFromAssemblyPath(path) : null;
            };

            var core = AssemblyLoadContext.Default.LoadFromAssemblyPath(corePath);
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            string web = Path.Combine(Path.GetFullPath(args[1]), "launcher", "web");
            foreach (string target in new[] { "close", "tab:items" })
            {
                foreach (bool move in new[] { false, true })
                {
                    rows.Add(RunTrial(core, web, target, "geometry-first", "world-only", move));
                    rows.Add(RunTrial(core, web, target, "geometry-first", "stable", move));
                    rows.Add(RunTrial(core, web, target, "stable-first", "stable", move));
                    rows.Add(RunTrial(core, web, target, "stable-first", "world-only", move));
                }
                rows.Add(RunTrial(core, web, target, "cancellation-control", "local-geometry", true));
            }
            Write(new
            {
                schema = "cf7-modifier-domain-probe.v1", runId, pid = Environment.ProcessId, startedUtc,
                completedUtc = DateTimeOffset.UtcNow.ToString("O"), desktop, inputDesktop,
                corePath = core.Location, coreSha256, stimulus = "known_hwnd_wm_messages",
                trials = rows,
            });
            return rows.All(row => row.Passed) ? 0 : 2;
        }
        catch (Exception exception)
        {
            Write(new { schema = "cf7-modifier-domain-probe.v1", runId, pid = Environment.ProcessId, startedUtc,
                error = exception.GetBaseException().ToString(), trials = rows });
            return 1;
        }
    }

    private static Trial RunTrial(Assembly core, string web, string target, string order, string mutation, bool move)
    {
        var mode = core.GetType(Guardian + "InputOwnership.PassiveFlashInputMode", true);
        var authority = Construct(core.GetType(Guardian + "InputOwnership.SessionInputAuthority", true), Enum.Parse(mode, "Disabled"));
        Invoke(authority, "Connect", 1);
        var output = new object[] { null, false };
        if (!(bool)Invoke(authority, "TryTakeOutput", output)) throw new InvalidOperationException("No bind");
        string bind = (string)Property(output[0], "Payload");
        Invoke(authority, "SetForeground", true, null, null);
        Invoke(authority, "SetBusinessEligible", true, "fixture_ready");
        if (!(bool)Invoke(authority, "Receive", 1, bind.Replace("|Bind|", "|Capability|")) ||
            !(bool)Invoke(authority, "TryTakeOutput", new object[] { null, false }) ||
            !(bool)Invoke(authority, "ObserveKey", (int)Keys.D, true) ||
            !(bool)Invoke(authority, "ObserveKey", (int)Keys.LShiftKey, true))
            throw new InvalidOperationException("Game grant and held D/Shift are preconditions.");

        using var owner = new Form { ShowInTaskbar = false, StartPosition = FormStartPosition.Manual, Bounds = new Rectangle(18, 18, 1060, 600) };
        owner.Show();
        using var task = (IDisposable)Construct(core.GetType("CF7Launcher.Tasks.ModifierTask", true),
            (Func<bool>)(() => true), (Func<string, bool>)(_ => true), 12000);
        var surfaceType = core.GetType(Guardian + "ModifierNativeSurface", true);
        using var surface = (Form)Construct(surfaceType, owner, web, Path.GetTempPath(), task, null);
        Invoke(surface, "BindInputAuthority", authority, authority);
        if (!(bool)Invoke(surface, "ResumePanel", new Rectangle(23, 23, 1016, 550)))
            throw new InvalidOperationException("Modifier surface was not shown.");

        var layout = core.GetType(Guardian + "ModifierNativeLayout", true);
        string field = target == "close" ? "Close" : "ItemsTab";
        var rect = (Rectangle)layout.GetField(field, Static).GetValue(null);
        var client = (Rectangle)layout.GetMethod("ToClient", Static, new[] { typeof(Rectangle), typeof(Size) })
            .Invoke(null, new object[] { rect, surface.ClientSize });
        var point = new Point(client.Left + client.Width / 2, client.Top + client.Height / 2);
        string TargetAtPoint()
        {
            var logical = layout.GetMethod("ToLogical", Static).Invoke(null, new object[] { point, surface.ClientSize });
            return (string)Invoke(surface, "HitAction", logical);
        }
        if (TargetAtPoint() != target || (bool)Invoke(surface, "IsTitleDragPoint", point))
            throw new InvalidOperationException("Modifier hit target changed.");

        int closes = 0;
        surfaceType.GetEvent("CloseRequested", Instance).GetAddMethod(true).Invoke(surface, new object[] { (Action)(() => closes++) });
        var packed = (IntPtr)((point.Y << 16) | (ushort)point.X);
        string TicketTarget = "modifier.button." + target;
        int ActionCount() => target == "close" ? closes : ((string)Field(surface, "_activeTab") == "items" ? 1 : 0);
        bool IsSettled(object ticket) => Field(surface, "_pointerTicket") == null &&
            !(bool)Invoke(authority, "ValidatePointerCommit", ticket, TicketTarget) && !surface.Capture;

        var beforeBounds = surface.Bounds;
        int beforeDpi = surface.DeviceDpi;
        long beforeGeneration = Convert.ToInt64(Field(surface, "_sessionGeneration"));
        long geometryBefore = Convert.ToInt64(Property(authority, "CurrentGeometryVersion"));
        long keyboardEpoch = Convert.ToInt64(Property(authority, "CurrentKeyboardEpoch"));
        long pointerEpoch = Convert.ToInt64(Property(authority, "CurrentPointerEpoch"));
        string held = (string)Property(authority, "AdmittedHex");
        int actionsBefore = ActionCount();
        SendMessageW(surface.Handle, LeftDown, (IntPtr)1, packed);
        object ticket = Field(surface, "_pointerTicket") ?? throw new InvalidOperationException("Down did not acquire a pointer ticket.");
        bool validOnDown = (bool)Invoke(authority, "ValidatePointerCommit", ticket, TicketTarget);
        int earlyCommit = ActionCount() - actionsBefore;
        if (mutation == "world-only") Invoke(authority, "ChangeWorldGeometry");
        if (mutation == "local-geometry") surface.Left += 12;
        long geometryAfter = Convert.ToInt64(Property(authority, "CurrentGeometryVersion"));
        bool localUnchanged = surface.Bounds == beforeBounds && surface.DeviceDpi == beforeDpi &&
            Convert.ToInt64(Field(surface, "_sessionGeneration")) == beforeGeneration;
        string hitBeforeUp = TargetAtPoint();
        bool validBeforeMove = (bool)Invoke(authority, "ValidatePointerCommit", ticket, TicketTarget);
        if (move) SendMessageW(surface.Handle, MouseMove, (IntPtr)1, packed);
        bool validBeforeUp = Field(surface, "_pointerTicket") != null &&
            (bool)Invoke(authority, "ValidatePointerCommit", ticket, TicketTarget);
        SendMessageW(surface.Handle, LeftUp, IntPtr.Zero, packed);
        int actionDelta = ActionCount() - actionsBefore;
        bool settled = IsSettled(ticket);
        bool keyboardUnchanged = (bool)Property(authority, "IsGameKeyboardAdmitted") &&
            Convert.ToInt64(Property(authority, "CurrentKeyboardEpoch")) == keyboardEpoch &&
            (string)Property(authority, "AdmittedHex") == held;
        bool pointerEpochUnchanged = Convert.ToInt64(Property(authority, "CurrentPointerEpoch")) == pointerEpoch;

        int? freshActionDelta = null;
        bool? freshSettled = null;
        if (mutation == "local-geometry")
        {
            int beforeFresh = ActionCount();
            SendMessageW(surface.Handle, LeftDown, (IntPtr)1, packed);
            object freshTicket = Field(surface, "_pointerTicket");
            SendMessageW(surface.Handle, LeftUp, IntPtr.Zero, packed);
            freshActionDelta = ActionCount() - beforeFresh;
            freshSettled = freshTicket != null && IsSettled(freshTicket);
        }
        bool expectedLocal = mutation != "local-geometry";
        bool passed = validOnDown && earlyCommit == 0 && keyboardUnchanged && pointerEpochUnchanged && hitBeforeUp == target &&
            settled && localUnchanged == expectedLocal && (geometryAfter != geometryBefore) == (mutation == "world-only") &&
            validBeforeMove == expectedLocal && validBeforeUp == expectedLocal && actionDelta == (expectedLocal ? 1 : 0) &&
            (expectedLocal || (freshActionDelta == 1 && freshSettled == true));
        return new Trial(target, order, mutation, move, validOnDown, earlyCommit, geometryBefore, geometryAfter,
            localUnchanged, hitBeforeUp, validBeforeMove, validBeforeUp, actionDelta, settled, freshActionDelta,
            freshSettled, keyboardUnchanged, pointerEpochUnchanged, passed);
    }

    private record Trial(string Target, string Order, string Mutation, bool Move, bool ValidOnDown, int EarlyCommit,
        long GeometryBefore, long GeometryAfter, bool LocalUnchanged, string HitBeforeUp, bool ValidBeforeMove,
        bool ValidBeforeUp, int ActionDelta, bool Settled, int? FreshActionDelta, bool? FreshSettled,
        bool KeyboardUnchanged, bool PointerEpochUnchanged, bool Passed);
}
