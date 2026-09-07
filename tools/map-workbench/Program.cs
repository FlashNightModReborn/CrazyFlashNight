using System.Net;
using CF7Launcher.Data;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

// CLI 只适配 stdin/stdout；浏览器开发服务器按显式 serve 启动，共用同一 C# 内核。
string root = Path.GetFullPath(args.Length > 1 ? args[1] : Environment.CurrentDirectory);
if (args.FirstOrDefault() == "validate-content")
{
    // 纯只读检查，不创建作者回执，也不恢复或修改未完成批次。
    try
    {
        var definition = MapDefinition.Load(root);
        MapRuleEvaluator.Need(definition.Value<int>("version") == 2, "地图定义须完成第二阶段迁移。");
        var tasks = MapTaskCatalog.Load(root); tasks.ValidateBindings(definition);
        MapAuthoringPlan.ValidateTaskReferences(definition, tasks.Tasks);
        MapAssetCandidates.ValidatePublished(root, definition);
        var world = new MapRuntimeWorld(root, definition);
        var unavailable = new JArray(world.Occurrences.Properties().Where(p => p.Value.Value<bool>("ready") != true).Select(p => p.Value.DeepClone()));
        Console.WriteLine(new JObject { ["success"] = true, ["pages"] = ((JArray)definition["pageOrder"]).Count,
            ["locations"] = ((JObject)definition["locations"]).Count, ["tasks"] = tasks.Tasks.Count,
            ["taskNpcLabels"] = tasks.NpcLabels(definition), ["unreadyWorldBindings"] = unavailable,
            ["runtimeSourceCount"] = world.SourceHashes.Count }.ToString(Formatting.None)); return 0;
    }
    catch (Exception e) { Console.WriteLine(new JObject { ["success"] = false, ["error"] = e.Message }.ToString(Formatting.None)); return 1; }
}
if (args.FirstOrDefault() == "render-definition")
{
    try { Console.WriteLine(MapDomainDefinition.WebProjection(MapDefinition.Load(root)).ToString(Formatting.None)); return 0; }
    catch (Exception e) { Console.Error.WriteLine(e.Message); return 1; }
}
if (args.FirstOrDefault() == "prepare-definition")
{
    try
    {
        var definition = MapDefinition.Parse(MapDefinition.Utf8.GetBytes(Console.In.ReadToEnd()));
        MapWorldCatalog.Load(root).EnrichBindings(definition);
        new MapAssetCandidates(root).Resolve(definition);
        MapTaskCatalog.Load(root).ValidateBindings(definition);
        var runtimeWorld = new MapRuntimeWorld(root, definition);
        Console.WriteLine(new JObject { ["success"] = true, ["definition"] = definition, ["runtimeSourceCount"] = runtimeWorld.SourceHashes.Count }.ToString(Formatting.None)); return 0;
    }
    catch (Exception e) { Console.WriteLine(new JObject { ["success"] = false, ["error"] = e.Message }.ToString(Formatting.None)); return 1; }
}
if (args.FirstOrDefault() == "catalog")
{
    try
    {
        var tasks = MapTaskCatalog.Load(root); var world = MapWorldCatalog.Load(root).Json();
        world["tasks"] = tasks.Summary(); world["taskDigest"] = tasks.Digest; world["chains"] = new JArray(tasks.Chains);
        Console.WriteLine(new JObject { ["success"] = true, ["catalog"] = world }.ToString(Formatting.None)); return 0;
    }
    catch (Exception e) { Console.WriteLine(new JObject { ["success"] = false, ["error"] = e.Message }.ToString(Formatting.None)); return 1; }
}
if (args.FirstOrDefault() == "project")
{
    // 无状态、零写的离线剧情方案投影，使用与 Host 相同的定义校验和求值器。
    try
    {
        string inputText = Console.In.ReadToEnd();
        if (inputText.Length > 16 * 1024 * 1024) throw new InvalidDataException("离线投影输入过大。");
        var input = MapProjectFiles.Json(MapDefinition.Utf8.GetBytes(inputText));
        var definition = MapDefinition.Parse(MapDefinition.Bytes((JObject)input["definition"]));
        var facts = input["facts"] as JArray ?? new JArray(input["facts"]?.DeepClone() ?? new JObject());
        if (facts.Count > 1024) throw new InvalidDataException("离线方案过多。");
        var results = new JArray();
        foreach (JObject fact in facts)
        {
            var result = MapDomainService.Project(definition, fact, input["tasks"] as JObject, input["worldBindings"] as JObject);
            results.Add(input.Value<bool?>("summary") == true ? new JObject {
                ["unlocks"] = result["snapshot"]["unlocks"], ["avatarVisibility"] = result["snapshot"]["avatarVisibility"],
                ["currentLocationId"] = result["currentLocationId"], ["delivery"] = result["delivery"], ["hudMode"] = result["hudMode"] } : result);
        }
        Console.WriteLine(new JObject { ["success"] = true, ["results"] = results, ["webDefinition"] = MapDomainDefinition.WebProjection(definition),
            ["hud"] = MapDefinition.Hud(definition), ["requiredFacts"] = MapRuleEvaluator.RequiredFacts(definition) }.ToString(Formatting.None));
        return 0;
    }
    catch (Exception e) { Console.WriteLine(new JObject { ["success"] = false, ["error"] = e.Message }.ToString(Formatting.None)); return 1; }
}
var store = new MapAuthoringStore(root);
JObject Execute(string text)
{
    try
    {
        if (text.Length > 256 * 1024) throw new InvalidDataException("请求过大。");
        return new JObject { ["success"] = true, ["data"] = store.Execute(MapProjectFiles.Json(MapDefinition.Utf8.GetBytes(text))) };
    }
    catch (Exception e) { return new JObject { ["success"] = false, ["error"] = e.Message }; }
}
if (args.FirstOrDefault() == "serve")
{
    int port = args.Length > 2 ? int.Parse(args[2]) : 18765;
    string origin = "http://127.0.0.1:" + port;
    using var server = new HttpListener(); server.Prefixes.Add(origin + "/"); server.Start();
    Console.WriteLine("地图工作台开发页：" + origin);
    while (true)
    {
        var context = await server.GetContextAsync();
        _ = Task.Run(async () =>
        {
            try
            {
                var req = context.Request; var res = context.Response; string path = req.Url.AbsolutePath;
                byte[] bytes;
                res.Headers["Cache-Control"] = "no-store";
                if (req.HttpMethod == "POST")
                {
                    long limit = path == "/asset-upload" ? MapAssetCodec.MaxBytes : 256 * 1024;
                    if ((path != "/api" && path != "/asset-upload") || req.Headers["Origin"] != origin || req.Headers["Host"] != "127.0.0.1:" + port || req.ContentLength64 < 1 || req.ContentLength64 > limit) { res.StatusCode = 403; return; }
                    var input = new byte[(int)req.ContentLength64]; await req.InputStream.ReadExactlyAsync(input);
                    if (path == "/asset-upload")
                    {
                        JObject result;
                        try { result = new JObject { ["success"] = true, ["data"] = store.StageImage(input, Uri.UnescapeDataString(req.Headers["X-Map-File-Name"] ?? "导入图片")) }; }
                        catch (Exception e) { result = new JObject { ["success"] = false, ["error"] = e.Message }; }
                        bytes = MapDefinition.Bytes(result);
                    }
                    else bytes = MapDefinition.Bytes(Execute(MapDefinition.Utf8.GetString(input)));
                    res.ContentType = "application/json; charset=utf-8";
                }
                else if (req.HttpMethod != "GET" && req.HttpMethod != "HEAD") { res.StatusCode = 405; return; }
                else if (path == "/modules/map-definition.js")
                {
                    bytes = MapDefinition.Utf8.GetBytes(MapDefinition.Script(MapDefinition.Load(root))); res.ContentType = "application/javascript; charset=utf-8";
                }
                else
                {
                    string web = Path.GetFullPath(Path.Combine(root, "launcher/web"));
                    string file = path == "/" ? Path.Combine(root, "tools/map-workbench/harness.html") : Path.GetFullPath(Path.Combine(web, Uri.UnescapeDataString(path).TrimStart('/')));
                    if (path != "/" && !file.StartsWith(web + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) { res.StatusCode = 403; return; }
                    if (!File.Exists(file)) { res.StatusCode = 404; return; }
                    MapProjectFiles.PlainPath(file);
                    bytes = await File.ReadAllBytesAsync(file);
                    res.ContentType = Path.GetExtension(file) switch { ".html" => "text/html; charset=utf-8", ".js" => "application/javascript; charset=utf-8", ".json" => "application/json; charset=utf-8", ".css" => "text/css; charset=utf-8", ".webp" => "image/webp", ".png" => "image/png", ".svg" => "image/svg+xml", _ => "application/octet-stream" };
                }
                res.ContentLength64 = bytes.Length; await res.OutputStream.WriteAsync(bytes);
            }
            catch { context.Response.StatusCode = 500; }
            finally { context.Response.Close(); }
        });
    }
}
else if (args.FirstOrDefault() == "hud") Console.WriteLine(MapDefinition.Hud(MapDefinition.Load(root)).ToString());
else
{
    var result = Execute(args.FirstOrDefault() == "read" ? "{\"op\":\"read\"}" : Console.In.ReadToEnd());
    Console.WriteLine(result.ToString(Formatting.None));
    return result.Value<bool>("success") ? 0 : 1;
}
return 0;
