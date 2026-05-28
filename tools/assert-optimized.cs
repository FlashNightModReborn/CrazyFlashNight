// assert-optimized.cs —— 出厂产物优化护栏（file-based app，net10 SDK）
//
// 背景：历史上 launcher 卡顿的真因是误把 Debug 构建（DebuggableAttribute 的
// DisableOptimizations=256 置位 → 运行时 JIT 优化被关）当作发布产物提交。详见
// memory: launcher-perf-debug-vs-release。net10 走 `dotnet publish -c Release`
// 本应永远优化，但本工具把"产物必须是优化版"从流程纪律升级为脚本强制校验：
// 把 Debug 产物溜进发布目录这一失败模式物理堵死。
//
// 用法：dotnet run tools/assert-optimized.cs -- <managed.dll> [<more.dll> ...]
// 退出码：0 = 全部优化；2 = 至少一个含 DisableOptimizations（Debug）；3 = 用法/读取错误。
//
// 实现：用 BCL 自带的 PEReader/MetadataReader 直接读 assembly 级
// DebuggableAttribute 的原始 blob，不解析依赖、不联网、不实例化目标程序集。

using System;
using System.IO;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;

if (args.Length == 0)
{
    Console.Error.WriteLine("[assert-optimized] usage: dotnet run tools/assert-optimized.cs -- <dll> [<dll> ...]");
    Environment.Exit(3);
}

int failed = 0;
foreach (var path in args)
{
    if (!File.Exists(path))
    {
        Console.Error.WriteLine($"[assert-optimized] FAIL: file not found: {path}");
        failed++;
        continue;
    }

    int modes;
    bool found;
    try
    {
        found = TryReadDebuggingModes(path, out modes);
    }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"[assert-optimized] FAIL: cannot read metadata of {path}: {ex.Message}");
        failed++;
        continue;
    }

    string name = Path.GetFileName(path);
    if (!found)
    {
        // DebuggableAttribute 缺失 = csc 在 /optimize+ /debug- 下未写入该属性 → JIT 默认优化。
        Console.WriteLine($"[assert-optimized] OK   {name}: no DebuggableAttribute (JIT optimizes)");
        continue;
    }

    bool disableOpt = (modes & 256) != 0; // DebuggingModes.DisableOptimizations
    if (disableOpt)
    {
        Console.Error.WriteLine($"[assert-optimized] FAIL {name}: DebuggingModes={modes} 含 DisableOptimizations(256) → 这是 Debug 构建，JIT 优化被关");
        failed++;
    }
    else
    {
        Console.WriteLine($"[assert-optimized] OK   {name}: DebuggingModes={modes} (no DisableOptimizations)");
    }
}

if (failed > 0)
{
    Console.Error.WriteLine($"[assert-optimized] {failed} 个产物未通过优化校验。发布目录里不允许出现 Debug/未优化产物。");
    Environment.Exit(2);
}
Console.WriteLine("[assert-optimized] all artifacts optimized.");
return;

// 读取 assembly 级 DebuggableAttribute 的 DebuggingModes。返回 false 表示该属性不存在。
static bool TryReadDebuggingModes(string path, out int modes)
{
    modes = 0;
    using var fs = File.OpenRead(path);
    using var pe = new PEReader(fs);
    if (!pe.HasMetadata) throw new BadImageFormatException("no CLI metadata (native image?)");
    var mr = pe.GetMetadataReader();

    foreach (var h in mr.GetAssemblyDefinition().GetCustomAttributes())
    {
        var ca = mr.GetCustomAttribute(h);
        if (!AttrName(mr, ca).EndsWith("DebuggableAttribute", StringComparison.Ordinal)) continue;

        var blob = mr.GetBlobReader(ca.Value);
        blob.ReadUInt16(); // prolog 0x0001
        // 现代 Roslyn 用 DebuggableAttribute(DebuggingModes) 的 Int32 enum 构造器（固定参 4 字节）。
        // 兼容旧的 DebuggableAttribute(bool isJITTrackingEnabled, bool isJITOptimizerDisabled) 构造器。
        if (blob.RemainingBytes >= 6) // 4(int32) + 2(named-arg count)
        {
            modes = blob.ReadInt32();
        }
        else
        {
            blob.ReadBoolean();                 // isJITTrackingEnabled
            bool jitOptimizerDisabled = blob.ReadBoolean();
            modes = jitOptimizerDisabled ? 256 : 0; // 映射到 DisableOptimizations 位
        }
        return true;
    }
    return false;
}

static string AttrName(MetadataReader mr, CustomAttribute ca)
{
    EntityHandle declType;
    if (ca.Constructor.Kind == HandleKind.MemberReference)
        declType = mr.GetMemberReference((MemberReferenceHandle)ca.Constructor).Parent;
    else
        declType = mr.GetMethodDefinition((MethodDefinitionHandle)ca.Constructor).GetDeclaringType();

    if (declType.Kind == HandleKind.TypeReference)
        return mr.GetString(mr.GetTypeReference((TypeReferenceHandle)declType).Name);
    if (declType.Kind == HandleKind.TypeDefinition)
        return mr.GetString(mr.GetTypeDefinition((TypeDefinitionHandle)declType).Name);
    return "";
}
