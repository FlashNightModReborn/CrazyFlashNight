using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Web.WebView2.Core;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.HitNumbers
{
    internal readonly struct HitNumberPreviewHttpResponse
    {
        internal HitNumberPreviewHttpResponse(
            int statusCode,
            string reasonPhrase,
            string contentType,
            byte[] body,
            int activeRows = 0,
            int omittedRows = 0)
        {
            StatusCode = statusCode;
            ReasonPhrase = reasonPhrase;
            ContentType = contentType;
            Body = body ?? Array.Empty<byte>();
            ActiveRows = activeRows;
            OmittedRows = omittedRows;
        }

        internal int StatusCode { get; }
        internal string ReasonPhrase { get; }
        internal string ContentType { get; }
        internal byte[] Body { get; }
        internal int ActiveRows { get; }
        internal int OmittedRows { get; }
    }

    /// <summary>
    /// 设置页实时伤害数字预览的独立虚拟主机资源处理器（不走文件夹映射，避免 WebView2 跳过 WebResourceRequested）。
    /// 严格绑定当前活动 settings panelInstanceId，只读响应二进制 PNG 帧，不触碰写锁或真实战斗运行态。
    /// </summary>
    internal static class HitNumberPreviewWebResources
    {
        internal const string VirtualHost = "cf7-hitpreview.local";
        internal const string Origin = "https://" + VirtualHost;
        internal const string AllowedOverlayOrigin = "https://overlay.local";

        private static readonly Regex ValidOpaque =
            new Regex("^[A-Za-z0-9._~-]{1,160}$", RegexOptions.Compiled);

        internal static JObject BuildCapability()
        {
            var presets = new JArray();
            IReadOnlyList<HitNumberPreviewPreset> catalog = HitNumberPreviewPresets.Catalog;
            for (int i = 0; i < catalog.Count; i++)
            {
                HitNumberPreviewPreset preset = catalog[i];
                presets.Add(new JObject
                {
                    ["id"] = preset.Id,
                    ["label"] = preset.Label,
                    ["description"] = preset.Description,
                    ["durationMs"] = preset.DurationMs,
                    ["representativeTimeMs"] = preset.RepresentativeTimeMs
                });
            }
            return new JObject
            {
                ["v"] = 1,
                ["origin"] = Origin,
                ["width"] = HitNumberPreviewSandbox.DefaultWidth,
                ["height"] = HitNumberPreviewSandbox.DefaultHeight,
                ["presets"] = presets
            };
        }

        internal static void Register(
            CoreWebView2 core,
            Func<HitNumberPreviewSandbox> sandboxProvider,
            Func<string> activeInstanceProvider)
        {
            if (core == null) throw new ArgumentNullException(nameof(core));
            core.AddWebResourceRequestedFilter(
                Origin + "/*",
                CoreWebView2WebResourceContext.All,
                CoreWebView2WebResourceRequestSourceKinds.Document);
            core.WebResourceRequested += (_, args) =>
            {
                if (!Uri.TryCreate(args.Request.Uri, UriKind.Absolute, out Uri uri)
                    || !string.Equals(uri.Host, VirtualHost, StringComparison.OrdinalIgnoreCase))
                {
                    return;
                }

                HitNumberPreviewHttpResponse response = Resolve(
                    args.Request.Uri,
                    args.Request.Method,
                    sandboxProvider?.Invoke(),
                    activeInstanceProvider?.Invoke());

                var headers = new StringBuilder(256);
                headers.Append("Content-Type: ").Append(response.ContentType).Append("\r\n");
                headers.Append("Cache-Control: no-store\r\n");
                headers.Append("X-Content-Type-Options: nosniff\r\n");
                headers.Append("Access-Control-Allow-Origin: ").Append(AllowedOverlayOrigin).Append("\r\n");
                if (response.StatusCode == 200)
                {
                    headers.Append("Access-Control-Expose-Headers: X-CF7-HitPreview-Rows, X-CF7-HitPreview-Omitted\r\n");
                    headers.Append("X-CF7-HitPreview-Rows: ")
                        .Append(response.ActiveRows.ToString(CultureInfo.InvariantCulture)).Append("\r\n");
                    headers.Append("X-CF7-HitPreview-Omitted: ")
                        .Append(response.OmittedRows.ToString(CultureInfo.InvariantCulture)).Append("\r\n");
                }
                args.Response = core.Environment.CreateWebResourceResponse(
                    new MemoryStream(response.Body, false),
                    response.StatusCode,
                    response.ReasonPhrase,
                    headers.ToString());
            };
        }

        internal static HitNumberPreviewHttpResponse Resolve(
            string uriString,
            string method,
            HitNumberPreviewSandbox sandbox,
            string activePanelInstanceId)
        {
            if (!string.Equals(method, "GET", StringComparison.OrdinalIgnoreCase))
                return TextError(405, "Method Not Allowed", "method_not_allowed");
            if (sandbox == null)
                return TextError(503, "Service Unavailable", "preview_unavailable");

            if (!TryParseFrameRequest(
                uriString,
                activePanelInstanceId,
                out HitNumberPreviewRequest request,
                out int statusCode,
                out string error))
            {
                return TextError(statusCode, statusCode == 403 ? "Forbidden" : statusCode == 404 ? "Not Found" : "Bad Request", error);
            }

            try
            {
                HitNumberPreviewFrameResult rendered = sandbox.RenderFrame(request);
                return new HitNumberPreviewHttpResponse(
                    200,
                    "OK",
                    "image/png",
                    rendered.PngBytes,
                    rendered.ActiveRows,
                    rendered.OmittedRows);
            }
            catch (ObjectDisposedException)
            {
                return TextError(503, "Service Unavailable", "preview_disposed");
            }
            catch (Exception errorEx)
            {
                LogManager.Log("[HitNumberPreview] render failed: " + errorEx.Message);
                return TextError(500, "Internal Server Error", "preview_render_failed");
            }
        }

        internal static bool TryParseFrameRequest(
            string uriString,
            string activePanelInstanceId,
            out HitNumberPreviewRequest request,
            out int statusCode,
            out string error)
        {
            request = default;
            statusCode = 400;
            error = "invalid_request";

            if (!Uri.TryCreate(uriString, UriKind.Absolute, out Uri uri)
                || !string.Equals(uri.Scheme, "https", StringComparison.OrdinalIgnoreCase)
                || !string.Equals(uri.Host, VirtualHost, StringComparison.OrdinalIgnoreCase))
            {
                statusCode = 400;
                error = "invalid_origin";
                return false;
            }
            if (!string.Equals(uri.AbsolutePath, "/frame", StringComparison.Ordinal))
            {
                statusCode = 404;
                error = "not_found";
                return false;
            }

            Dictionary<string, string> query = ParseQuery(uri.Query);
            if (!query.TryGetValue("instance", out string instance)
                || string.IsNullOrEmpty(activePanelInstanceId)
                || !ValidOpaque.IsMatch(instance)
                || !string.Equals(instance, activePanelInstanceId, StringComparison.Ordinal))
            {
                statusCode = 403;
                error = "panel_instance_mismatch";
                return false;
            }

            if (!query.TryGetValue("preset", out string presetId)
                || !HitNumberPreviewPresets.TryGet(presetId, out _))
            {
                error = "invalid_preset";
                return false;
            }

            if (!query.TryGetValue("mode", out string rawMode)
                || !TryParseMode(rawMode, out HitNumberDisplayMode mode))
            {
                error = "invalid_mode";
                return false;
            }

            int worldRowLimit = 24;
            if (query.TryGetValue("limit", out string rawLimit))
            {
                if (!int.TryParse(rawLimit, NumberStyles.Integer, CultureInfo.InvariantCulture, out worldRowLimit)
                    || worldRowLimit < 0 || worldRowLimit > 1000)
                {
                    error = "invalid_limit";
                    return false;
                }
            }

            int timeMs = 0;
            if (query.TryGetValue("t", out string rawTime))
            {
                if (!int.TryParse(rawTime, NumberStyles.Integer, CultureInfo.InvariantCulture, out timeMs)
                    || timeMs < 0 || timeMs > 60000)
                {
                    error = "invalid_time";
                    return false;
                }
            }

            int width = HitNumberPreviewSandbox.DefaultWidth;
            int height = HitNumberPreviewSandbox.DefaultHeight;
            bool hasWidth = query.TryGetValue("w", out string rawWidth);
            bool hasHeight = query.TryGetValue("h", out string rawHeight);
            if (hasWidth || hasHeight)
            {
                if (!hasWidth || !hasHeight
                    || !int.TryParse(rawWidth, NumberStyles.Integer, CultureInfo.InvariantCulture, out width)
                    || !int.TryParse(rawHeight, NumberStyles.Integer, CultureInfo.InvariantCulture, out height)
                    || width < HitNumberPreviewSandbox.MinimumWidth
                    || width > HitNumberPreviewSandbox.MaximumWidth
                    || height <= 0
                    || Math.Abs((long)width * 9L - (long)height * 16L) > 16L)
                {
                    error = "invalid_dimensions";
                    return false;
                }
            }

            bool showTargets = true;
            if (query.TryGetValue("targets", out string rawTargets))
            {
                if (string.Equals(rawTargets, "0", StringComparison.Ordinal)) showTargets = false;
                else if (string.Equals(rawTargets, "1", StringComparison.Ordinal)) showTargets = true;
                else
                {
                    error = "invalid_targets";
                    return false;
                }
            }

            request = new HitNumberPreviewRequest(presetId, mode, worldRowLimit, timeMs, width, height, showTargets);
            statusCode = 200;
            error = string.Empty;
            return true;
        }

        private static bool TryParseMode(string raw, out HitNumberDisplayMode mode)
        {
            switch (raw)
            {
                case "off":
                    mode = HitNumberDisplayMode.Off;
                    return true;
                case "balanced":
                    mode = HitNumberDisplayMode.Balanced;
                    return true;
                case "total":
                    mode = HitNumberDisplayMode.Total;
                    return true;
                case "classic":
                    mode = HitNumberDisplayMode.Classic;
                    return true;
                case "detail":
                    mode = HitNumberDisplayMode.Detail;
                    return true;
                default:
                    mode = HitNumberDisplayMode.Balanced;
                    return false;
            }
        }

        private static Dictionary<string, string> ParseQuery(string rawQuery)
        {
            var result = new Dictionary<string, string>(StringComparer.Ordinal);
            if (string.IsNullOrEmpty(rawQuery)) return result;
            string trimmed = rawQuery[0] == '?' ? rawQuery.Substring(1) : rawQuery;
            if (trimmed.Length == 0) return result;
            string[] pairs = trimmed.Split('&');
            for (int i = 0; i < pairs.Length; i++)
            {
                if (pairs[i].Length == 0) continue;
                int eq = pairs[i].IndexOf('=');
                string key = eq >= 0 ? pairs[i].Substring(0, eq) : pairs[i];
                string val = eq >= 0 ? pairs[i].Substring(eq + 1) : string.Empty;
                result[Uri.UnescapeDataString(key)] = Uri.UnescapeDataString(val);
            }
            return result;
        }

        private static HitNumberPreviewHttpResponse TextError(int statusCode, string reasonPhrase, string code)
        {
            return new HitNumberPreviewHttpResponse(
                statusCode,
                reasonPhrase,
                "text/plain; charset=utf-8",
                Encoding.UTF8.GetBytes(code ?? "error"));
        }
    }
}
