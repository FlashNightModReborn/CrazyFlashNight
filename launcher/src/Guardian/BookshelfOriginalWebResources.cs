using System;
using System.IO;
using Microsoft.Web.WebView2.Core;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian
{
    internal static class BookshelfOriginalWebResources
    {
        // Ruffle allowNetworking is not an effective security boundary. Chromium
        // enforces this policy on the isolated movie document and its subresources.
        internal const string ContentSecurityPolicy = "default-src 'none'; "
            + "script-src 'self' 'wasm-unsafe-eval'; style-src 'unsafe-inline'; "
            + "connect-src 'self'; img-src 'self' data:; font-src 'none'; "
            + "worker-src 'self' blob:; media-src 'self' blob:; "
            + "frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; "
            + "frame-ancestors https://overlay.local";
        internal static void Register(CoreWebView2 core, Func<BookshelfOriginalContent> content)
        {
            // The two-argument overload omits iframe subresource requests.
            core.AddWebResourceRequestedFilter(BookshelfOriginalContent.Origin + "/*", CoreWebView2WebResourceContext.All,
                CoreWebView2WebResourceRequestSourceKinds.Document);
            core.WebResourceRequested += (_, args) => {
                if (!Uri.TryCreate(args.Request.Uri, UriKind.Absolute, out var uri) || uri.Host != BookshelfOriginalContent.VirtualHost) return;
                BookshelfOriginalContent.Resource resource;
                try { resource = content()?.Resolve(args.Request.Uri, args.Request.Method); }
                catch { resource = null; }
                resource ??= new BookshelfOriginalContent.Resource { Status = 404, Bytes = Array.Empty<byte>(), Mime = "text/plain" };
                string headers = "Content-Type: " + resource.Mime + "\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n"
                    + "Referrer-Policy: no-referrer\r\nContent-Security-Policy: " + ContentSecurityPolicy + "\r\n";
                args.Response = core.Environment.CreateWebResourceResponse(new MemoryStream(resource.Bytes, false),
                    resource.Status, resource.Status == 200 ? "OK" : "Not Found", headers);
            };
            core.FrameCreated += (_, created) => {
                var frame = created.Frame;
                if (frame.Name != "bookshelf-original") return;
                frame.NavigationStarting += (_, navigation) => {
                    var service = content();
                    if (service == null || !service.IsPlayerNavigation(navigation.Uri)) navigation.Cancel = true;
                };
                // No Frame.WebMessageReceived or native Host objects are registered.
            };
        }
    }
}
