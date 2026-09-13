using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class PortraitWebViewFactAttribute : FactAttribute
    {
        public PortraitWebViewFactAttribute()
        {
            if (Environment.GetEnvironmentVariable("CF7_TEST_PORTRAIT_WEBVIEW") != "1")
                Skip = "显式设置 CF7_TEST_PORTRAIT_WEBVIEW=1 才启动隔离真实 WebView2";
        }
    }

    public class PortraitWebViewRuntimeTests
    {
        [PortraitWebViewFact]
        public async Task RealRuntimeNeverRequestsConvolutionSvgIncludingPngFailure()
        {
            var completion = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
            var thread = new Thread(() => {
                string root = AppContext.BaseDirectory;
                while (!File.Exists(Path.Combine(root, "AGENTS.md")))
                    root = Directory.GetParent(root)?.FullName ?? throw new Exception("Repository missing");
                string udf = Path.Combine(root, "tmp", "portrait-webview-" + Guid.NewGuid().ToString("N"));
                using (var form = new Form { Width = 640, Height = 480, ShowInTaskbar = false })
                using (var view = new WebView2 { Dock = DockStyle.Fill })
                using (var timer = new System.Windows.Forms.Timer { Interval = 45000 })
                {
                    form.Controls.Add(view);
                    int svgRequests = 0;
                    string version = null, browserPath = null;
                    bool failPng = false;
                    Action<Exception> fail = error => { completion.TrySetException(error); form.Close(); };
                    timer.Tick += (_, _) => fail(new TimeoutException("WebView portrait fixture timeout"));
                    form.Shown += async (_, _) => {
                        try
                        {
                            var env = await CoreWebView2Environment.CreateAsync(null, udf);
                            await view.EnsureCoreWebView2Async(env);
                            version = env.BrowserVersionString;
                            using (var browser = Process.GetProcessById((int)view.CoreWebView2.BrowserProcessId))
                                browserPath = browser.MainModule.FileName;
                            view.CoreWebView2.ProcessFailed += (_, e) => fail(new Exception("ProcessFailed: " + e.ProcessFailedKind));
                            view.CoreWebView2.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
                            view.CoreWebView2.WebResourceRequested += (_, e) => {
                                var uri = new Uri(e.Request.Uri);
                                if (uri.Host != "cf7-portrait.test") return;
                                if (uri.AbsolutePath.EndsWith(".svg", StringComparison.OrdinalIgnoreCase)) svgRequests++;
                                string webRoot = Path.GetFullPath(Path.Combine(root, "launcher", "web")) + Path.DirectorySeparatorChar;
                                string path = Path.GetFullPath(Path.Combine(webRoot, Uri.UnescapeDataString(uri.AbsolutePath.TrimStart('/'))));
                                if (!path.StartsWith(webRoot, StringComparison.OrdinalIgnoreCase)) throw new Exception("fixture path escape");
                                if (failPng && uri.Query.Contains("missing=1"))
                                    e.Response = env.CreateWebResourceResponse(new MemoryStream(), 404, "Fixture missing PNG", "Cache-Control: no-store");
                                else
                                {
                                    string type = path.EndsWith(".js") ? "text/javascript" : path.EndsWith(".json") ? "application/json"
                                        : path.EndsWith(".svg") ? "image/svg+xml" : "image/png";
                                    e.Response = env.CreateWebResourceResponse(new MemoryStream(File.ReadAllBytes(path)), 200, "OK",
                                        "Content-Type: " + type + "\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: *");
                                }
                            };
                            view.CoreWebView2.WebMessageReceived += async (_, e) => {
                                try
                                {
                                    string message = e.TryGetWebMessageAsString();
                                    if (message == "normal_pass")
                                    {
                                        failPng = true;
                                        await view.CoreWebView2.CallDevToolsProtocolMethodAsync("Network.clearBrowserCache", "{}");
                                        await view.ExecuteScriptAsync("run(true)");
                                        return;
                                    }
                                    if (message != "fallback_pass") throw new Exception(message);
                                    Assert.Equal(0, svgRequests);
                                    string evidence = new JObject { ["browserVersion"] = version, ["browserPath"] = browserPath,
                                        ["hostPath"] = Environment.ProcessPath, ["svgRequests"] = svgRequests,
                                        ["cases"] = 4, ["scope"] = "isolated WebView2 asset loading; not loot/gameplay acceptance" }.ToString();
                                    File.WriteAllText(Path.Combine(udf, "result.json"), evidence);
                                    completion.TrySetResult(evidence);
                                    form.Close();
                                }
                                catch (Exception error) { fail(error); }
                            };
                            view.NavigateToString("""
                                <body><script>window.CF7_PORTRAIT_ROOT='https://cf7-portrait.test/assets/enemy-portraits/';
                                window.CF7_PORTRAIT_LEGACY_ROOT='https://cf7-portrait.test/assets/pets/';</script>
                                <script src="https://cf7-portrait.test/modules/portrait-resolver.js"></script>
                                <script>
                                async function run(fallback) { try {
                                  if(fallback) {
                                    const manifest=JSON.parse(JSON.stringify(await EnemyPortraits.loadManifest()));
                                    for(const entry of Object.values(manifest.entries)) for(const variant of Object.values(entry.variants))
                                      if(variant.subject?.pngFallback) variant.subject.pngFallback.url+='?missing=1';
                                    EnemyPortraits.__setManifestForTests(manifest);
                                  }
                                  for (const ref of ['敌人-方舟妖姬','敌人-拟态投影']) {
                                    const box=document.createElement('div'), img=document.createElement('img'); img.crossOrigin='anonymous';
                                    box.append(img); document.body.append(box);
                                    await EnemyPortraits.mount(box,img,{portraitRef:ref});
                                    await new Promise((ok,bad)=>{const start=Date.now();const t=setInterval(()=>{
                                      if(img.complete && img.naturalWidth && box.dataset.portraitSource){clearInterval(t);ok();}
                                      else if(Date.now()-start>5000){clearInterval(t);bad(Error('image timeout'));}
                                    },20);});
                                    const expected=fallback?'legacy':'png';
                                    if(box.dataset.portraitSource!==expected)throw Error('unexpected '+box.dataset.portraitSource);
                                    if(!fallback){ const c=document.createElement('canvas'); c.width=c.height=32;
                                      const g=c.getContext('2d');g.drawImage(img,0,0,32,32);
                                      if(!g.getImageData(0,0,32,32).data.some((v,i)=>i%4===3&&v>0))throw Error('empty PNG'); }
                                    box.remove();
                                  }
                                  chrome.webview.postMessage(fallback?'fallback_pass':'normal_pass');
                                } catch(e){chrome.webview.postMessage(String(e));} }
                                run(false);
                                </script>
                                """);
                        }
                        catch (Exception error) { fail(error); }
                    };
                    timer.Start();
                    Application.Run(form);
                }
            });
            thread.IsBackground = true;
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            string result = await completion.Task.WaitAsync(TimeSpan.FromSeconds(60));
            Assert.True(thread.Join(5000), "WebView fixture must dispose its own host");
            Assert.Contains("browserVersion", result);
        }
    }
}
