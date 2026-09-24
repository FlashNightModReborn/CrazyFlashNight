namespace CF7Launcher.Guardian.UnifiedHost;

// Launch options for the shared input host. DiagnosticCommands defaults
// to false: probe-driven delayed replies, source disconnect and fault
// injection stay closed unless an explicit fixture opts in. Both the fixture
// and the verified Core candidate branch consume this shared runtime.
internal sealed class UnifiedHostOptions
{
    internal string ProjectRoot = "";
    internal string Evidence = "";
    internal string Mode = "";
    internal bool DiagnosticCommands;
    internal UnifiedSceneProfile Scene = UnifiedSceneProfile.C1;
}

// Closed profiles choose executable modules and logical geometry together.
// Callers cannot supply arbitrary SWF names or independently change hit mapping.
internal sealed record UnifiedSceneProfile
{
    internal static readonly UnifiedSceneProfile C1 = new(
        "C1Bootstrap.swf", "C1Island.swf", "launcher/native/world-compositor/input-ownership-fixture", 640, 360);
    // Construction profile only; public candidate CLI remains closed until the
    // real actor/domain validation is complete. Assets are captured with the module.
    internal static readonly UnifiedSceneProfile B1 = new(
        "RuntimeBootstrap.swf", "RuntimeWorld.swf", "launcher/native/world-compositor/base-input-fixture", 1024, 576,
        87, 65, 83, 68, 37, 38, 39, 40);
    internal bool RequiresLoadBarrier => Module == "RuntimeWorld.swf";
    internal System.Collections.Generic.IReadOnlyList<string> Dependencies => RequiresLoadBarrier ? BaseDependencies : System.Array.Empty<string>();
    private static readonly System.Collections.Generic.IReadOnlyList<string> BaseDependencies = System.Array.AsReadOnly(new[] {
        "flashswf/levels/基地场景合集.swf", "flashswf/arts/things0.swf",
        "flashswf/arts/new/素材库-地图元件.swf", "flashswf/arts/新版人物文字信息.swf"
    });
    private UnifiedSceneProfile(string bootstrap, string module, string directory, int width, int height, params int[] movementKeys)
    {
        Bootstrap = bootstrap; Module = module; Directory = directory; Width = width; Height = height;
        MovementKeys = System.Array.AsReadOnly((int[])movementKeys.Clone());
    }
    internal string Bootstrap { get; }
    internal string Module { get; }
    internal string Directory { get; }
    internal int Width { get; }
    internal int Height { get; }
    internal System.Collections.Generic.IReadOnlyList<int> MovementKeys { get; }
}
