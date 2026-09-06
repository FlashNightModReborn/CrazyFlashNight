using CF7Launcher.Data;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Newtonsoft.Json.Linq;

internal sealed class MapWebViewSmoke : Form
{
    private readonly string root;
    private readonly WebView2 view = new WebView2 { Dock = DockStyle.Fill };
    private readonly System.Windows.Forms.Timer deadline = new System.Windows.Forms.Timer { Interval = 30000 };
    private JObject expected;
    private int phase;
    private bool finished;
    internal static int Result = 1;

    private static JToken NumberSemantics(JToken token)
    {
        var copy = token.DeepClone();
        foreach (var value in ((JContainer)copy).Descendants().OfType<JValue>().ToArray())
            if (value.Type == JTokenType.Integer || value.Type == JTokenType.Float) value.Value = value.Value<double>();
        return copy;
    }

    [STAThread] private static int Main(string[] args)
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        if (args.Length != 1) { Console.Error.WriteLine("需要项目根目录参数。"); return 2; }
        Application.EnableVisualStyles();
        Application.Run(new MapWebViewSmoke(Path.GetFullPath(args[0])));
        return Result;
    }
    private MapWebViewSmoke(string projectRoot)
    {
        root = projectRoot;
        ShowInTaskbar = false; Opacity = 0; Size = new Size(1280, 720);
        StartPosition = FormStartPosition.Manual; Location = new Point(-32000, -32000);
        Controls.Add(view);
        deadline.Tick += (_, _) => Finish(new TimeoutException("真实 WebView2 地图加载超时。"));
        Shown += async (_, _) =>
        {
            deadline.Start();
            try
            {
                expected = MapDefinition.Load(root);
                var env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(root, "tmp/map-workbench/webview-smoke-userdata"));
                await view.EnsureCoreWebView2Async(env);
                foreach (var host in new[] { "overlay.local", "map-probe.local" })
                    view.CoreWebView2.SetVirtualHostNameToFolderMapping(host, Path.Combine(root, "launcher/web"), CoreWebView2HostResourceAccessKind.Allow);
                await view.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync("window.__mapBootErrors=[];addEventListener('error',function(e){__mapBootErrors.push(e.message+' @ '+e.filename);});");
                await view.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(MapDefinition.BootstrapScript(expected));
                view.CoreWebView2.NavigationCompleted += CheckNavigation;
                view.CoreWebView2.Navigate("https://overlay.local/overlay.html");
            }
            catch (Exception error) { Finish(error); }
        };
    }
    private async void CheckNavigation(object sender, CoreWebView2NavigationCompletedEventArgs args)
    {
        if (finished) return;
        try
        {
            if (!args.IsSuccess) throw new Exception("WebView2 导航失败：" + args.WebErrorStatus);
            if (phase == 0)
            {
                var actual = JObject.Parse(await view.CoreWebView2.ExecuteScriptAsync("({definition:MapDefinitionData,hotspots:MapPanelData.getAllHotspotIds().length,pages:MapPanelData.getPageOrder().length,errors:__mapBootErrors})"));
                // JSON 290 与 290.0 在 JS 中是同一个 Number；精确比较数值，不使用误差容限。
                if (!JToken.DeepEquals(NumberSemantics(expected), NumberSemantics(actual["definition"])) || actual.Value<int>("hotspots") != 40 || actual.Value<int>("pages") != 4 || ((JArray)actual["errors"]).Count != 0)
                    throw new Exception("生产页面启动快照或脚本异常：pages=" + actual["pages"] + " hotspots=" + actual["hotspots"] + " errors=" + actual["errors"]);
                Console.WriteLine("PASS 真实 WebView2：生产 overlay.html 的启动数据逐字段等价，4 页 / 40 地点，零脚本错误。");
                await CheckAuthoringFrame();
                phase = 1;
                view.CoreWebView2.Navigate("https://map-probe.local/overlay.html");
            }
            else
            {
                if (await view.CoreWebView2.ExecuteScriptAsync("typeof MapDefinitionData") != "\"undefined\"") throw new Exception("地图启动数据越过来源边界。");
                Console.WriteLine("PASS 其他来源未注入地图启动数据。");
                Finish(null);
            }
        }
        catch (Exception error) { Finish(error); }
    }
    private async Task CheckAuthoringFrame()
    {
        await view.CoreWebView2.ExecuteScriptAsync("""
            window.__authoringProbe=null;
            var frame=document.createElement('iframe');frame.style.cssText='position:fixed;inset:0;width:100%;height:100%;border:0';
            window.addEventListener('message',function inspect(e){
                if(e.source!==frame.contentWindow||e.origin!==location.origin||!e.data||e.data.type!=='map-authoring-preview')return;
                if(e.data.event==='ready')frame.contentWindow.postMessage({type:'map-authoring-input',action:'state',session:'native-smoke',definition:MapDefinitionData,pageId:'base',kind:'scene',id:MapDefinitionData.pages.base.sceneVisuals[0].id,gender:'male',editing:true,rasterScale:1},location.origin);
                if(e.data.event==='error')window.__authoringProbe={pass:false,error:e.data.message};
                if(e.data.event==='loaded'){
                    var child=frame.contentWindow,x=MapDefinitionData.pages.base.sceneVisuals[0].rect.x;
                    var equal=JSON.stringify(child.MapDefinitionData)===JSON.stringify(MapDefinitionData);
                    child.MapDefinitionData.pages.base.sceneVisuals[0].rect.x+=1;
                    window.__authoringProbe={pass:equal&&MapDefinitionData.pages.base.sceneVisuals[0].rect.x===x&&child.document.querySelectorAll('.map-page-tab').length===4&&!!child.MapPanel.authoring};
                    window.removeEventListener('message',inspect);
                }
            });
            frame.src='https://overlay.local/modules/map/authoring/preview.html';document.body.appendChild(frame);
            """);
        for (int i = 0; i < 50; i++)
        {
            await Task.Delay(100);
            string json = await view.CoreWebView2.ExecuteScriptAsync("window.__authoringProbe");
            if (json == "null") continue;
            if (!JObject.Parse(json).Value<bool>("pass")) throw new Exception("作者预览子文档验证失败：" + json);
            Console.WriteLine("PASS 真实 WebView2：生产地图作者子文档加载，四页 UI 同源，草稿与父文档隔离。");
            return;
        }
        throw new TimeoutException("作者预览子文档未就绪。");
    }
    private void Finish(Exception error)
    {
        if (finished) return;
        finished = true; deadline.Stop();
        if (error != null) Console.Error.WriteLine(error.Message); else Result = 0;
        view.Dispose(); Close();
    }
}
