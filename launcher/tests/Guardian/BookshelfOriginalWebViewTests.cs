using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Config;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class BookshelfWebViewFactAttribute : FactAttribute
    {
        public BookshelfWebViewFactAttribute()
        {
            if (Environment.GetEnvironmentVariable("CF7_TEST_BOOKSHELF_WEBVIEW") != "1")
                Skip = "显式设置 CF7_TEST_BOOKSHELF_WEBVIEW=1 与 CF7_TEST_BOOKSHELF_ROOT 才启动隔离 WebView2";
        }
    }
    public class BookshelfOriginalWebViewTests
    {
        private sealed class InactiveTestForm : Form
        {
            protected override bool ShowWithoutActivation => true;
        }

        [BookshelfWebViewFact]
        public async Task IsolatedNativeHandlerLoadsOriginalAndExchangesOnlyPlayerControls()
        {
            string root = Environment.GetEnvironmentVariable("CF7_TEST_BOOKSHELF_ROOT");
            Assert.True(!string.IsNullOrEmpty(root) && File.Exists(Path.Combine(root, "AGENTS.md")));
            string requestedChapter = Environment.GetEnvironmentVariable("CF7_TEST_BOOKSHELF_CHAPTER") ?? "1";
            Assert.True(int.TryParse(requestedChapter, out int chapter) && chapter >= 1 && chapter <= 6);
            string profile = Path.Combine(Path.GetTempPath(), "cf7-bookshelf-webview-" + Guid.NewGuid().ToString("N"));
            var completion = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
            var thread = new Thread(() => {
                using var content = new BookshelfOriginalContent(root, (instance, token) => instance == "bookshelf.fixture" && token == "bookshelf.fixture");
                using var form = new InactiveTestForm { Width = 1000, Height = 650, ShowInTaskbar = false,
                    StartPosition = FormStartPosition.Manual, Location = new Point(-10000, -10000) };
                using var view = new WebView2 { Dock = DockStyle.Fill };
                using var timer = new System.Windows.Forms.Timer { Interval = 45000 };
                form.Controls.Add(view);
                var events = new List<string>(); var frames = new List<CoreWebView2Frame>();
                void Fail(Exception error) { completion.TrySetException(error); form.Close(); }
                timer.Tick += async (_, _) => {
                    timer.Stop();
                    try {
                        events.Add("parent: " + await view.ExecuteScriptAsync("JSON.stringify({href:location.href,states:typeof states==='undefined'?null:states,body:document.body.innerText})"));
                        foreach (var frame in frames) events.Add("frame: " + await frame.ExecuteScriptAsync("JSON.stringify({href:location.href,origin:location.origin,securityOrigin:window.origin,base:document.baseURI,ruffle:typeof window.RufflePlayer,script:document.querySelector('script')?.src,resources:performance.getEntriesByType('resource').map(e=>e.name),ready:document.readyState,html:document.documentElement.outerHTML})"));
                    } catch (Exception error) { events.Add(error.GetType().Name); }
                    File.WriteAllText(Path.Combine(profile, "failure.json"), new JArray(events).ToString());
                    Fail(new TimeoutException("Isolated bookshelf WebView2 timeout: " + string.Join(" | ", events)));
                };
                form.Shown += async (_, _) => {
                    try
                    {
                        var request = JObject.Parse("""
                            {"type":"panel","panel":"bookshelf","domain":"bookshelf-original","cmd":"prepare",
                            "callId":"original.fixture","panelInstanceId":"bookshelf.fixture",
                            "payload":{"v":1,"token":"bookshelf.fixture","chapter":1,"language":"cn"}}
                            """);
                        request["payload"]["chapter"] = chapter;
                        var prepared = await content.ExecuteAsync(request);
                        Assert.True(prepared.Value<bool>("success"), prepared.ToString());
                        var environment = await CoreWebView2Environment.CreateAsync(null, profile);
                        await view.EnsureCoreWebView2Async(environment);
                        WebView2BrowserPolicy.Apply(view.CoreWebView2.Settings, false, "Bookshelf isolated test");
                        BookshelfOriginalWebResources.Register(view.CoreWebView2, () => content);
                        view.CoreWebView2.FrameCreated += (_, created) => {
                            frames.Add(created.Frame); events.Add("frame created: " + created.Frame.Name);
                            created.Frame.NavigationStarting += (_, navigation) => events.Add("frame navigation: " + navigation.Uri + " cancelled=" + navigation.Cancel);
                        };
                        view.CoreWebView2.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
                        view.CoreWebView2.WebResourceRequested += (_, e) => events.Add("resource: " + new Uri(e.Request.Uri).AbsolutePath + " status=" + e.Response?.StatusCode);
                        await view.CoreWebView2.CallDevToolsProtocolMethodAsync("Runtime.enable", "{}");
                        await view.CoreWebView2.CallDevToolsProtocolMethodAsync("Log.enable", "{}");
                        view.CoreWebView2.GetDevToolsProtocolEventReceiver("Runtime.exceptionThrown").DevToolsProtocolEventReceived += (_, e) => events.Add("script exception: " + e.ParameterObjectAsJson);
                        view.CoreWebView2.GetDevToolsProtocolEventReceiver("Log.entryAdded").DevToolsProtocolEventReceived += (_, e) => events.Add("browser log: " + e.ParameterObjectAsJson);
                        view.CoreWebView2.ProcessFailed += (_, e) => Fail(new Exception("ProcessFailed: " + e.ProcessFailedKind));
                        view.CoreWebView2.AddWebResourceRequestedFilter("https://overlay.local/*", CoreWebView2WebResourceContext.All);
                        view.CoreWebView2.WebResourceRequested += (_, e) => {
                            var uri = new Uri(e.Request.Uri); if (uri.Host != "overlay.local") return;
                            string html = """
                                <!doctype html><style>html,body,iframe{width:100%;height:100%;margin:0;border:0}</style>
                                <iframe name="bookshelf-original" sandbox="allow-scripts allow-same-origin" allow="autoplay" src="
                                """ + prepared.Value<string>("playerUrl") + """
                                "></iframe><script>
                                const frame=document.querySelector('iframe'),states=[];
                                addEventListener('message',e=>{
                                  if(e.source!==frame.contentWindow || e.origin!=='https://cf7-originals.local'
                                    || e.data.channel!=='bookshelf-original.v1')return;
                                  states.push(e.data.state);
                                  if(e.data.state==='error'){chrome.webview.postMessage('player_error');return;}
                                  if(states.length===1)frame.contentWindow.postMessage({...e.data,action:'pause'},e.origin);
                                  else if(states.length===2)frame.contentWindow.postMessage({...e.data,action:'play'},e.origin);
                                  else chrome.webview.postMessage(states.join(','));
                                });</script>
                                """;
                            e.Response = environment.CreateWebResourceResponse(new MemoryStream(System.Text.Encoding.UTF8.GetBytes(html)),
                                200, "OK", "Content-Type: text/html; charset=utf-8\r\nCache-Control: no-store");
                        };
                        view.CoreWebView2.WebMessageReceived += (_, e) => {
                            try
                            {
                                Assert.True(BookshelfOriginalContent.IsOverlaySource(e.Source));
                                Assert.Equal("playing,paused,playing", e.TryGetWebMessageAsString());
                                var access = SteamCollectionAccess.CreateReader(root)();
                                string report = new JObject { ["browserVersion"] = environment.BrowserVersionString,
                                    ["hostPath"] = Environment.ProcessPath, ["source"] = e.Source,
                                    ["chapter"] = chapter, ["developmentContent"] = access.IsDevelopment,
                                    ["states"] = "playing,paused,playing", ["collectionStatus"] = access.Ready ? "ready" : access.Error,
                                    ["scope"] = "isolated production WebView2 resource handler and original content access; fixture admission; no CF7 save/Steam-entry E2E" }.ToString();
                                File.WriteAllText(Path.Combine(profile, "result.json"), report);
                                completion.TrySetResult(report); form.Close();
                            }
                            catch (Exception error) { Fail(error); }
                        };
                        view.CoreWebView2.Navigate("https://overlay.local/overlay.html"); timer.Start();
                    }
                    catch (Exception error) { Fail(error); }
                };
                Application.Run(form);
            });
            thread.SetApartmentState(ApartmentState.STA); thread.Start();
            string evidence = await completion.Task.WaitAsync(TimeSpan.FromSeconds(55));
            Assert.Contains("playing,paused,playing", evidence);
            Assert.True(thread.Join(5000), "Isolated WebView2 thread must close");
            Console.WriteLine("Bookshelf isolated WebView2: " + evidence);
            Console.WriteLine("Bookshelf isolated WebView2 evidence: " + Path.Combine(profile, "result.json"));
        }
    }
}
