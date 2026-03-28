// CAS (Contrast Adaptive Sharpening) Shader 源码 + 运行时编译
// 优先运行时编译 HLSL；如果 d3dcompiler_47.dll 缺失，回退到预编译字节码

using System;
using CF7Launcher.Guardian;

namespace CF7Launcher.Render
{
    static class CasShaderBytecode
    {
        // ── HLSL 源码 ──

        public static readonly string VertexShaderSource =
            "struct VSOut { float4 pos : SV_Position; float2 uv : TEXCOORD0; };\n" +
            "VSOut main(uint vid : SV_VertexID) {\n" +
            "    VSOut o;\n" +
            "    float2 raw = float2((vid << 1) & 2, vid & 2);\n" +
            "    o.pos = float4(raw * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);\n" +
            "    o.uv = float2(raw.x, 1.0 - raw.y);\n" + // Y 翻转：GDI bitmap top-down vs D3D11 UV
            "    return o;\n" +
            "}\n";

        // CAS 5-tap cross pattern: 自适应边缘锐化
        public static readonly string PixelShaderSource =
            "cbuffer CASParams : register(b0) {\n" +
            "    float sharpness;\n" +
            "    float2 texelSize;\n" +
            "    float _pad;\n" +
            "};\n" +
            "Texture2D srcTex : register(t0);\n" +
            "SamplerState samp : register(s0);\n" +
            "\n" +
            "float4 main(float2 uv : TEXCOORD0) : SV_Target {\n" +
            "    float3 b = srcTex.Sample(samp, uv + float2(0.0, -texelSize.y)).rgb;\n" +
            "    float3 d = srcTex.Sample(samp, uv + float2(-texelSize.x, 0.0)).rgb;\n" +
            "    float3 e = srcTex.Sample(samp, uv).rgb;\n" +
            "    float3 f = srcTex.Sample(samp, uv + float2(texelSize.x, 0.0)).rgb;\n" +
            "    float3 h = srcTex.Sample(samp, uv + float2(0.0, texelSize.y)).rgb;\n" +
            "    float3 mn = min(min(d, e), min(f, min(b, h)));\n" +
            "    float3 mx = max(max(d, e), max(f, max(b, h)));\n" +
            "    float3 amp = sqrt(saturate(min(mn, 1.0 - mx) / mx));\n" +
            "    float3 w = amp * (-0.125 * sharpness);\n" +
            "    float3 result = (b + d + f + h) * w + e * (1.0 - 4.0 * w);\n" +
            "    return float4(saturate(result), 1.0);\n" +
            "}\n";

        // ── 运行时编译 ──

        /// <summary>
        /// 尝试运行时编译 HLSL。成功返回字节码 byte[]，失败返回 null。
        /// 需要系统有 d3dcompiler_47.dll。
        /// </summary>
        public static byte[] CompileShader(string source, string entryPoint, string profile)
        {
            try
            {
                SharpDX.D3DCompiler.CompilationResult result =
                    SharpDX.D3DCompiler.ShaderBytecode.Compile(
                        source, entryPoint, profile,
                        SharpDX.D3DCompiler.ShaderFlags.OptimizationLevel3,
                        SharpDX.D3DCompiler.EffectFlags.None);

                if (result.HasErrors)
                {
                    LogManager.Log("[Shader] Compile error: " + result.Message);
                    return null;
                }

                byte[] bytecode = new byte[result.Bytecode.Data.Length];
                Array.Copy(result.Bytecode.Data, bytecode, bytecode.Length);
                result.Dispose();
                return bytecode;
            }
            catch (Exception ex)
            {
                LogManager.Log("[Shader] Compile exception (d3dcompiler_47.dll missing?): " + ex.Message);
                return null;
            }
        }

        /// <summary>
        /// 获取 VS 字节码：优先运行时编译，失败用预编译。
        /// </summary>
        public static byte[] GetVertexShaderBytecode()
        {
            byte[] bc = CompileShader(VertexShaderSource, "main", "vs_4_0");
            if (bc != null) return bc;
            LogManager.Log("[Shader] Using precompiled VS bytecode");
            return PrecompiledVS;
        }

        /// <summary>
        /// 获取 PS 字节码：优先运行时编译，失败用预编译。
        /// </summary>
        public static byte[] GetPixelShaderBytecode()
        {
            byte[] bc = CompileShader(PixelShaderSource, "main", "ps_4_0");
            if (bc != null) return bc;
            LogManager.Log("[Shader] Using precompiled PS bytecode");
            return PrecompiledPS;
        }

        // ── 预编译字节码（占位，首次运行时编译成功后可以替换） ──
        // 如果运行时编译可用，这些不会被使用。
        // 后续可用工具从 .cso 文件生成这些 byte[]。

        internal static readonly byte[] PrecompiledVS = null;
        internal static readonly byte[] PrecompiledPS = null;
    }
}
