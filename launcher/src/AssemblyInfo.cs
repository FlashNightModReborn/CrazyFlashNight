using System.Runtime.CompilerServices;

// 让 Launcher.Tests 可以访问 internal 成员（如 NativeHudOverlay.ComputeBoundsUnion）。
// 主程序用 dynamic-code-free，正常运行时不受影响。
[assembly: InternalsVisibleTo("Launcher.Tests")]
