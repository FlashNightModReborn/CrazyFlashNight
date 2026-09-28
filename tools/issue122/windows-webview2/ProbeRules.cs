using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;

internal static class ProbeRules
{
    internal static string Classify(bool[] gpuRawChunked, bool[] gpuChunkedNonindexed, bool[] softwareRawChunked, bool verified)
    {
        if (gpuRawChunked.Length != 2 || gpuChunkedNonindexed.Length != 2 || softwareRawChunked.Length != 2)
            throw new ArgumentException("Both camera matrices are required.");
        if (!verified) return "backend_identity_not_sufficient";
        if (gpuRawChunked.All(x => !x) && gpuChunkedNonindexed.All(x => x) && softwareRawChunked.All(x => x))
            return "gpu_uint32_path_reproduced";
        if (gpuRawChunked.All(x => x) && gpuChunkedNonindexed.All(x => x) && softwareRawChunked.All(x => x))
            return "not_reproduced_in_isolated_webview2";
        return "mixed_result_manual_review_required";
    }

    internal static bool SamePixels(JObject a, JObject b)
    {
        string x = a["png"]?.Value<string>("pixelSha256"), y = b["png"]?.Value<string>("pixelSha256");
        if (x == null || y == null || !Regex.IsMatch(x, "^[a-f0-9]{64}$") || !Regex.IsMatch(y, "^[a-f0-9]{64}$"))
            throw new InvalidOperationException("Missing or invalid pixel evidence.");
        if (a["png"].Value<int>("width") <= 0 || a["png"].Value<int>("height") <= 0 ||
            b["png"].Value<int>("width") <= 0 || b["png"].Value<int>("height") <= 0)
            throw new InvalidOperationException("Missing pixel dimensions.");
        return x == y && a["png"].Value<int>("width") == b["png"].Value<int>("width") &&
            a["png"].Value<int>("height") == b["png"].Value<int>("height");
    }

    internal static string BackendKind(JObject gl)
    {
        string renderer = gl?.Value<string>("unmaskedRenderer") ?? "";
        if (Regex.IsMatch(renderer, "SwiftShader|llvmpipe|softpipe|WARP|Basic Render Driver", RegexOptions.IgnoreCase))
            return "software";
        if (Regex.IsMatch(renderer, "Intel|NVIDIA|AMD|ATI|Radeon|GeForce|UHD|Iris", RegexOptions.IgnoreCase))
            return "hardware";
        return "unknown";
    }

    internal static bool VerifiedBackends(IReadOnlyList<JObject> cells)
    {
        if (cells.Count != 10) return false;
        foreach (string lane in new[] { "gpu", "software" })
        {
            var rows = cells.Where(c => c.Value<string>("backend") == lane).ToArray();
            if (rows.Length != (lane == "gpu" ? 6 : 4)) return false;
            if (rows.Any(c => BackendKind(c["gl"] as JObject) != (lane == "gpu" ? "hardware" : "software"))) return false;
            if (rows.Select(c => c["gl"]?.Value<string>("unmaskedRenderer")).Distinct().Count() != 1) return false;
            if (rows.Select(c => c.Value<string>("browserVersion")).Distinct().Count() != 1) return false;
            if (rows.Any(c => c.Value<bool>("pixelsStable") != true)) return false;
        }
        return cells.Select(c => c.Value<string>("browserVersion")).Distinct().Count() == 1;
    }

    internal static void RunTests(string output)
    {
        int passed = 0;
        void Check(string name, bool value)
        {
            if (!value) throw new Exception("Self-test failed: " + name);
            passed++;
        }
        var yes = new[] { true, true };
        var no = new[] { false, false };
        Check("all controls identical", Classify(yes, yes, yes, true) == "not_reproduced_in_isolated_webview2");
        Check("both cameras isolate Uint32", Classify(no, yes, yes, true) == "gpu_uint32_path_reproduced");
        Check("only original camera differs", Classify(new[] { false, true }, yes, yes, true) == "mixed_result_manual_review_required");
        Check("only current camera differs", Classify(new[] { true, false }, yes, yes, true) == "mixed_result_manual_review_required");
        Check("non-indexed control fails", Classify(no, new[] { false, true }, yes, true) == "mixed_result_manual_review_required");
        Check("software control fails", Classify(no, yes, new[] { false, true }, true) == "mixed_result_manual_review_required");
        Check("hardware lane may be fallback", Classify(no, yes, yes, false) == "backend_identity_not_sufficient");
        Check("masked renderer is insufficient", BackendKind(new JObject { ["renderer"] = "WebKit WebGL" }) == "unknown");
        Check("SwiftShader", BackendKind(new JObject { ["unmaskedRenderer"] = "ANGLE (Google, Vulkan SwiftShader Device)" }) == "software");
        Check("WARP", BackendKind(new JObject { ["unmaskedRenderer"] = "ANGLE (Microsoft Basic Render Driver Direct3D11)" }) == "software");
        Check("hardware identity", BackendKind(new JObject { ["unmaskedRenderer"] = "ANGLE (Intel, Intel UHD Graphics 630 Direct3D11)" }) == "hardware");
        bool missingRejected = false;
        try { SamePixels(new JObject(), new JObject()); } catch (InvalidOperationException) { missingRejected = true; }
        Check("two missing hashes never match", missingRejected);
        bool cameraRejected = false;
        try { Classify(new[] { true }, yes, yes, true); } catch (ArgumentException) { cameraRejected = true; }
        Check("incomplete matrix rejected", cameraRejected);
        Check("incomplete backend matrix rejected", !VerifiedBackends(Array.Empty<JObject>()));
        File.WriteAllText(output, new JObject { ["status"] = "passed", ["checks"] = passed }.ToString());
    }
}
