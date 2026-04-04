using Mono.Cecil;
using Mono.Cecil.Cil;
using System;
using System.IO;
using System.Linq;

// === Assembly-CSharp.dll Patcher ===
// Patches BIsAppInstalled → BIsSubscribedApp to check ownership instead of installation

string dllPath = args[0];
string outputPath = args.Length > 1 ? args[1] : Path.Combine(Path.GetDirectoryName(dllPath)!, "Assembly-CSharp.patched.dll");

// Load with Steamworks reference resolution
string managedDir = Path.GetDirectoryName(dllPath)!;
var resolver = new DefaultAssemblyResolver();
resolver.AddSearchDirectory(managedDir);

var readerParams = new ReaderParameters {
    AssemblyResolver = resolver,
    ReadWrite = false
};

using var assembly = AssemblyDefinition.ReadAssembly(dllPath, readerParams);
var module = assembly.MainModule;

int patchCount = 0;

// Find all methods in all types
foreach (var type in module.Types)
{
    foreach (var method in type.Methods)
    {
        if (!method.HasBody) continue;

        var instructions = method.Body.Instructions;
        for (int i = 0; i < instructions.Count; i++)
        {
            var instr = instructions[i];
            if (instr.OpCode != OpCodes.Call && instr.OpCode != OpCodes.Callvirt)
                continue;

            if (instr.Operand is not MethodReference methodRef)
                continue;

            // Patch BIsAppInstalled → BIsSubscribedApp
            if (methodRef.Name == "BIsAppInstalled" && methodRef.DeclaringType.Name == "SteamApps")
            {
                // Find BIsSubscribedApp in the same declaring type's module
                // Both have signature: bool (AppId_t)
                var steamAppsType = methodRef.DeclaringType;
                var subscribedRef = new MethodReference("BIsSubscribedApp", methodRef.ReturnType, steamAppsType) {
                    HasThis = methodRef.HasThis
                };
                foreach (var p in methodRef.Parameters)
                    subscribedRef.Parameters.Add(new ParameterDefinition(p.ParameterType));

                instr.Operand = subscribedRef;
                patchCount++;

                Console.WriteLine($"  [PATCH] {type.Name}.{method.Name}: BIsAppInstalled → BIsSubscribedApp");
            }
        }
    }
}

if (patchCount == 0)
{
    Console.WriteLine("WARNING: No patches applied!");
    Environment.Exit(1);
}

Console.WriteLine($"\nTotal patches: {patchCount}");
assembly.Write(outputPath);
Console.WriteLine($"Written to: {outputPath}");
