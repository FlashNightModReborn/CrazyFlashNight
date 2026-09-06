using System.Net;
using CF7Launcher.Data;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

// CLI 只适配 stdin/stdout；浏览器开发服务器按显式 serve 启动，共用同一 C# 内核。
string root = Path.GetFullPath(args.Length > 1 ? args[1] : Environment.CurrentDirectory);
var store = new MapAuthoringStore(root);
JObject Execute(string text)
{
    try
    {
        if (text.Length > 256 * 1024) throw new InvalidDataException("请求过大。");
        return new JObject { ["success"] = true, ["data"] = store.Execute(JObject.Parse(text,
            new JsonLoadSettings { DuplicatePropertyNameHandling = DuplicatePropertyNameHandling.Error })) };
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
                    if (path != "/api" || req.Headers["Origin"] != origin || req.Headers["Host"] != "127.0.0.1:" + port || req.ContentLength64 < 1 || req.ContentLength64 > 256 * 1024) { res.StatusCode = 403; return; }
                    using var reader = new StreamReader(req.InputStream, MapDefinition.Utf8);
                    bytes = MapDefinition.Bytes(Execute(await reader.ReadToEndAsync())); res.ContentType = "application/json; charset=utf-8";
                }
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
