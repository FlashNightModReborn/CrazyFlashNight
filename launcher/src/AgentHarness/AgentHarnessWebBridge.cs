using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using Microsoft.Web.WebView2.Core;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.AgentHarness
{
    /// <summary>
    /// In-process WebView2 semantic DOM inspector, action dispatcher, and capture bridge.
    /// Operates directly on the active CoreWebView2 (Bootstrap, WebOverlay, CompositionHelp/Intelligence,
    /// or Transition Settlement) via UI-thread ExecuteScriptAsync so it remains deterministic in the
    /// background and under Windows Lock Screen without stealing Win32 focus.
    /// </summary>
    internal sealed class AgentHarnessWebBridge
    {
        private readonly GuardianForm _form;
        private readonly WebOverlayForm _webOverlay;
        private readonly PanelHostController _panelHost;
        private readonly SceneTransitionController _sceneTransition;
        private readonly GameLaunchFlow _launchFlow;
        private readonly AgentHarnessPolicy _policy;

        internal AgentHarnessWebBridge(
            GuardianForm form,
            WebOverlayForm webOverlay,
            PanelHostController panelHost,
            SceneTransitionController sceneTransition,
            GameLaunchFlow launchFlow,
            AgentHarnessPolicy policy)
        {
            _form = form;
            _webOverlay = webOverlay;
            _panelHost = panelHost;
            _sceneTransition = sceneTransition;
            _launchFlow = launchFlow;
            _policy = policy;
        }

        private Task<T> RunOnUiAsync<T>(Func<Task<T>> work, CancellationToken ct)
        {
            var tcs = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
            if (_form == null || _form.IsDisposed || !_form.IsHandleCreated)
            {
                tcs.TrySetException(new InvalidOperationException("host_form_unavailable"));
                return tcs.Task;
            }
            if (!_form.InvokeRequired)
            {
                _ = ExecuteAsync();
                return tcs.Task;
            }
            try
            {
                _form.BeginInvoke(new Action(delegate { _ = ExecuteAsync(); }));
            }
            catch (Exception ex)
            {
                tcs.TrySetException(ex);
            }
            return tcs.Task;

            async Task ExecuteAsync()
            {
                try
                {
                    ct.ThrowIfCancellationRequested();
                    T res = await work();
                    tcs.TrySetResult(res);
                }
                catch (Exception ex)
                {
                    tcs.TrySetException(ex);
                }
            }
        }

        private (CoreWebView2 Core, string SurfaceKind, string ActivePanel, string PanelInstanceId) ResolveTargetOnUi()
        {
            string panelName = _panelHost?.ActivePanelName;
            string instanceId = _panelHost?.ActivePanelInstanceId;

            if (_panelHost != null)
            {
                CoreWebView2 compCore = _panelHost.TryGetActiveHarnessWebCore(out string compKind);
                if (compCore != null)
                    return (compCore, compKind, panelName, instanceId);
            }

            if (_sceneTransition != null && _sceneTransition.OwnsCurtain)
            {
                CoreWebView2 transCore = _sceneTransition.SettlementSurface?.InternalCoreWebView2;
                if (transCore != null)
                    return (transCore, "scene_transition", panelName, instanceId);
            }

            string launchState = _launchFlow?.CurrentState;
            if (!string.Equals(launchState, "Ready", StringComparison.Ordinal) || _launchFlow?.RevealPerformed != true)
            {
                CoreWebView2 bootCore = _form?.BootstrapPanel?.InternalCoreWebView2;
                if (bootCore != null && _form.BootstrapPanel.Visible)
                    return (bootCore, "bootstrap", panelName, instanceId);
            }

            if (_webOverlay != null && (_panelHost?.IsPanelOpen == true || _webOverlay.InternalCoreWebView2 != null))
            {
                CoreWebView2 overlayCore = _webOverlay.InternalCoreWebView2;
                if (overlayCore != null)
                    return (overlayCore, "web_overlay", panelName, instanceId);
            }

            CoreWebView2 fallbackBoot = _form?.BootstrapPanel?.InternalCoreWebView2;
            if (fallbackBoot != null)
                return (fallbackBoot, "bootstrap", panelName, instanceId);

            return (null, "none", panelName, instanceId);
        }

        internal Task<JObject> SnapshotAsync(JObject options, CancellationToken ct)
        {
            int maxElements = options?.Value<int?>("maxElements") ?? 180;
            if (maxElements < 10) maxElements = 10;
            if (maxElements > 500) maxElements = 500;
            string rootSelector = options?.Value<string>("rootSelector") ?? "";

            return RunOnUiAsync(async () =>
            {
                var target = ResolveTargetOnUi();
                if (target.Core == null)
                {
                    return new JObject
                    {
                        ["success"] = false,
                        ["error"] = "no_active_webview",
                        ["surfaceKind"] = target.SurfaceKind,
                        ["activePanel"] = target.ActivePanel ?? "",
                        ["panelInstanceId"] = target.PanelInstanceId ?? ""
                    };
                }

                string js = BuildSnapshotScript(maxElements, rootSelector);
                string raw = await target.Core.ExecuteScriptAsync(js);
                JObject parsed = ParseExecuteScriptJsonObject(raw);
                parsed["success"] = true;
                parsed["surfaceKind"] = target.SurfaceKind;
                parsed["activePanel"] = target.ActivePanel ?? "";
                parsed["panelInstanceId"] = target.PanelInstanceId ?? "";
                return parsed;
            }, ct);
        }

        internal async Task<bool> WaitForInteractiveSurfaceAsync(DateTime deadline, CancellationToken ct)
        {
            const string probeJs = @"(function(){
  try {
    var pc = document.getElementById('panel-container');
    if (pc && window.getComputedStyle(pc).display === 'none') return false;
    var nodes = document.querySelectorAll('button,a[href],input,select,textarea,[role=""button""],[role=""tab""],[tabindex],[data-action],[data-slot],[data-item],[data-tab],[data-view]');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var st = window.getComputedStyle(el);
      if (!st || st.display === 'none' || st.visibility === 'hidden' || st.opacity === '0') continue;
      if (el.closest && el.closest('[hidden], [inert]')) continue;
      var r = el.getBoundingClientRect();
      if (r.width > 0 && r.height > 0) return true;
    }
    return false;
  } catch (_) { return false; }
})()";
            while (DateTime.UtcNow < deadline && !ct.IsCancellationRequested)
            {
                bool ready = false;
                try
                {
                    ready = await RunOnUiAsync(async () =>
                    {
                        var target = ResolveTargetOnUi();
                        if (target.Core == null) return false;
                        string raw = await target.Core.ExecuteScriptAsync(probeJs);
                        return string.Equals(raw?.Trim(), "true", StringComparison.OrdinalIgnoreCase);
                    }, ct);
                }
                catch { }
                if (ready)
                {
                    await Task.Delay(50, ct);
                    return true;
                }
                int waitMs = Math.Max(40, Math.Min(80, (int)(deadline - DateTime.UtcNow).TotalMilliseconds));
                await Task.Delay(waitMs, ct);
            }
            return false;
        }

        internal Task<JObject> ActAsync(JObject options, CancellationToken ct)
        {
            if (options == null)
                return Task.FromResult(new JObject { ["success"] = false, ["error"] = "missing_options" });

            return RunOnUiAsync(async () =>
            {
                var target = ResolveTargetOnUi();
                if (target.Core == null)
                {
                    return new JObject
                    {
                        ["success"] = false,
                        ["error"] = "no_active_webview",
                        ["surfaceKind"] = target.SurfaceKind
                    };
                }

                string js = BuildActScript(options);
                string raw = await target.Core.ExecuteScriptAsync(js);
                JObject parsed = ParseExecuteScriptJsonObject(raw);
                parsed["surfaceKind"] = target.SurfaceKind;
                parsed["activePanel"] = target.ActivePanel ?? "";
                parsed["panelInstanceId"] = target.PanelInstanceId ?? "";
                return parsed;
            }, ct);
        }

        internal Task<JObject> ScreenshotAsync(JObject options, CancellationToken ct)
        {
            string requestedPath = options?.Value<string>("outputPath");
            string fileName = "shot-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmssfff") + "-" + Guid.NewGuid().ToString("N").Substring(0, 6) + ".png";
            string resolvedPath;
            if (!string.IsNullOrWhiteSpace(requestedPath))
            {
                resolvedPath = Path.IsPathRooted(requestedPath)
                    ? Path.GetFullPath(requestedPath)
                    : Path.GetFullPath(Path.Combine(_policy.ProjectRoot, requestedPath));
            }
            else
            {
                resolvedPath = Path.Combine(_policy.StateRoot, "screenshots", fileName);
            }

            string allowedRoot = Path.GetFullPath(Path.Combine(_policy.ProjectRoot, "tmp"));
            if (!resolvedPath.StartsWith(allowedRoot, StringComparison.OrdinalIgnoreCase)
                && !resolvedPath.StartsWith(_policy.StateRoot, StringComparison.OrdinalIgnoreCase))
            {
                return Task.FromResult(new JObject
                {
                    ["success"] = false,
                    ["error"] = "screenshot_path_must_be_under_tmp"
                });
            }

            Directory.CreateDirectory(Path.GetDirectoryName(resolvedPath));

            return RunOnUiAsync(async () =>
            {
                var target = ResolveTargetOnUi();
                if (target.Core == null)
                {
                    return new JObject
                    {
                        ["success"] = false,
                        ["error"] = "no_active_webview",
                        ["surfaceKind"] = target.SurfaceKind
                    };
                }

                using var ms = new MemoryStream();
                await target.Core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, ms);
                byte[] bytes = ms.ToArray();
                File.WriteAllBytes(resolvedPath, bytes);
                return new JObject
                {
                    ["success"] = true,
                    ["surfaceKind"] = target.SurfaceKind,
                    ["activePanel"] = target.ActivePanel ?? "",
                    ["outputPath"] = resolvedPath,
                    ["byteLength"] = bytes.Length
                };
            }, ct);
        }

        private static JObject ParseExecuteScriptJsonObject(string raw)
        {
            if (string.IsNullOrEmpty(raw) || raw == "null")
                return new JObject { ["raw"] = raw };
            // CoreWebView2.ExecuteScriptAsync returns JSON-encoded string literal when script returns JSON.stringify(...)
            JToken outer = JToken.Parse(raw);
            if (outer.Type == JTokenType.String)
            {
                string inner = outer.Value<string>();
                if (!string.IsNullOrEmpty(inner))
                {
                    JToken parsedInner = JToken.Parse(inner);
                    if (parsedInner is JObject obj) return obj;
                    return new JObject { ["value"] = parsedInner };
                }
            }
            if (outer is JObject outerObj) return outerObj;
            return new JObject { ["value"] = outer };
        }

        private static string BuildSnapshotScript(int maxElements, string rootSelector)
        {
            string selLiteral = JsonConvert.ToString(rootSelector ?? "");
            return $@"(function() {{
  try {{
    var rootSel = {selLiteral};
    var root = rootSel ? document.querySelector(rootSel) : document.body;
    if (!root) return JSON.stringify({{ error: 'root_not_found', url: location.href, elements: [] }});
    var norm = function(s, max) {{
      if (s === null || s === undefined) return '';
      var t = String(s).replace(/\s+/g, ' ').trim();
      return max && t.length > max ? t.slice(0, max) : t;
    }};
    var isVisible = function(el) {{
      if (!el || el.nodeType !== 1) return false;
      var st = window.getComputedStyle(el);
      if (!st || st.display === 'none' || st.visibility === 'hidden' || st.opacity === '0') return false;
      if (el.closest && el.closest('[hidden], [inert]')) return false;
      var r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    }};
    var interactiveSelector = [
      'button', 'a[href]', 'input', 'select', 'textarea', 'summary',
      '[role=""button""]', '[role=""tab""]', '[role=""menuitem""]', '[role=""option""]',
      '[role=""checkbox""]', '[role=""radio""]', '[tabindex]',
      '[data-action]', '[data-slot]', '[data-item-id]', '[data-item]', '[data-tab]',
      '[data-view]', '[data-panel]', '[data-id]', '[onclick]',
      '.clickable', '.tab-btn', '.nav-btn', '.slot-card', '.item-slot', '.item-cell'
    ].join(',');
    var candidates = [];
    var seen = typeof Set === 'function' ? new Set() : null;
    var addEl = function(el) {{
      if (!el || el.nodeType !== 1) return;
      if (seen) {{ if (seen.has(el)) return; seen.add(el); }}
      else if (candidates.indexOf(el) >= 0) return;
      if (isVisible(el)) candidates.push(el);
    }};
    var matched = root.querySelectorAll(interactiveSelector);
    for (var i = 0; i < matched.length && candidates.length < {maxElements} * 2; i++) addEl(matched[i]);
    if (candidates.length < {maxElements}) {{
      var all = root.querySelectorAll('div, span, li');
      for (var j = 0; j < all.length && candidates.length < {maxElements}; j++) {{
        var c = all[j];
        var cs = window.getComputedStyle(c);
        if (cs && cs.cursor === 'pointer' && norm(c.innerText, 80).length > 0) addEl(c);
      }}
    }}
    var prevRefs = document.querySelectorAll('[data-cf7-harness-ref]');
    for (var p = 0; p < prevRefs.length; p++) prevRefs[p].removeAttribute('data-cf7-harness-ref');
    var elements = [];
    for (var k = 0; k < candidates.length && elements.length < {maxElements}; k++) {{
      var el = candidates[k];
      var refId = 'e' + (elements.length + 1);
      el.setAttribute('data-cf7-harness-ref', refId);
      var rect = el.getBoundingClientRect();
      var txt = norm(el.innerText || el.textContent || el.getAttribute('aria-label') || el.getAttribute('title') || el.getAttribute('placeholder') || el.value || '', 120);
      var tag = el.tagName ? el.tagName.toLowerCase() : '';
      var dataAttrs = {{}};
      var hasData = false;
      if (el.attributes) {{
        for (var a = 0; a < el.attributes.length; a++) {{
          var an = el.attributes[a].name;
          if (an && an.indexOf('data-') === 0 && an !== 'data-cf7-harness-ref') {{
            dataAttrs[an.slice(5)] = norm(el.attributes[a].value, 64);
            hasData = true;
          }}
        }}
      }}
      var cls = typeof el.className === 'string' ? el.className : '';
      elements.push({{
        ref: refId,
        tag: tag,
        type: el.type || undefined,
        role: el.getAttribute('role') || undefined,
        id: el.id || undefined,
        classes: norm(cls, 80) || undefined,
        text: txt,
        value: (tag === 'input' || tag === 'textarea' || tag === 'select') ? norm(el.value, 80) : undefined,
        disabled: !!(el.disabled || el.getAttribute('aria-disabled') === 'true' || /\b(disabled|is-disabled)\b/.test(cls)),
        selected: !!(el.selected || el.checked || el.getAttribute('aria-selected') === 'true' || el.getAttribute('aria-checked') === 'true' || /\b(active|selected|is-active|is-selected)\b/.test(cls)),
        data: hasData ? dataAttrs : undefined,
        rect: {{ x: Math.round(rect.left), y: Math.round(rect.top), w: Math.round(rect.width), h: Math.round(rect.height) }}
      }});
    }}
    var headings = [];
    var hNodes = root.querySelectorAll('h1,h2,h3,h4,[role=""heading""],[role=""alert""],.toast,.status,.banner,.panel-title,.panel-header');
    for (var h = 0; h < hNodes.length && headings.length < 30; h++) {{
      if (!isVisible(hNodes[h])) continue;
      var ht = norm(hNodes[h].innerText || hNodes[h].textContent, 140);
      if (ht) headings.push(ht);
    }}
    var active = document.activeElement;
    return JSON.stringify({{
      url: location.href,
      title: document.title || '',
      focusedRef: active && active.getAttribute ? active.getAttribute('data-cf7-harness-ref') : null,
      headings: headings,
      elementCount: elements.length,
      elements: elements
    }});
  }} catch (e) {{
    return JSON.stringify({{ error: 'snapshot_exception', message: String(e && e.message ? e.message : e) }});
  }}
}})()";
        }

        private static string BuildActScript(JObject options)
        {
            string optsJson = options.ToString(Formatting.None);
            return $@"(function() {{
  try {{
    var opts = {optsJson};
    var act = String(opts.action || 'click');
    if (act === 'eval' || act === 'eval_readonly') {{
      var expr = String(opts.script || '');
      if (!expr) return JSON.stringify({{ success: false, error: 'missing_script' }});
      var fn = new Function('return (' + expr + ')');
      var res = fn();
      return JSON.stringify({{ success: true, action: act, result: res === undefined ? null : res }});
    }}
    var el = null;
    if (opts.ref) {{
      el = document.querySelector('[data-cf7-harness-ref=""' + String(opts.ref).replace(/""/g, '') + '""]');
    }}
    if (!el && opts.selector) {{
      el = document.querySelector(String(opts.selector));
    }}
    if (!el && opts.text) {{
      var needle = String(opts.text).trim();
      var candidates = document.querySelectorAll('[data-cf7-harness-ref], button, a, [role=""button""], [role=""tab""], input, select');
      var partial = null;
      for (var i = 0; i < candidates.length; i++) {{
        var c = candidates[i];
        var cs = window.getComputedStyle(c);
        if (!cs || cs.display === 'none' || cs.visibility === 'hidden') continue;
        var t = (c.innerText || c.textContent || c.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim();
        if (t === needle) {{ el = c; break; }}
        if (!partial && t.indexOf(needle) >= 0) partial = c;
      }}
      if (!el) el = partial;
    }}
    if (act === 'press_key') {{
      var target = el || document.activeElement || document.body;
      var key = String(opts.key || 'Escape');
      var keyCode = key === 'Escape' ? 27 : key === 'Enter' ? 13 : key === 'Tab' ? 9 : 0;
      var evInit = {{ key: key, code: key, keyCode: keyCode, which: keyCode, bubbles: true, cancelable: true }};
      target.dispatchEvent(new KeyboardEvent('keydown', evInit));
      target.dispatchEvent(new KeyboardEvent('keyup', evInit));
      return JSON.stringify({{ success: true, action: act, key: key }});
    }}
    if (act === 'scroll') {{
      var sc = el || document.scrollingElement || document.documentElement;
      if (typeof opts.top === 'number') sc.scrollTop = opts.top;
      else if (typeof opts.deltaY === 'number') sc.scrollTop += opts.deltaY;
      return JSON.stringify({{ success: true, action: act, scrollTop: sc.scrollTop }});
    }}
    if (!el) return JSON.stringify({{ success: false, error: 'target_element_not_found', ref: opts.ref || null, selector: opts.selector || null, text: opts.text || null }});
    try {{ el.scrollIntoView({{ block: 'center', inline: 'center' }}); }} catch (_) {{}}
    var r = el.getBoundingClientRect();
    var cx = Math.round(r.left + r.width / 2);
    var cy = Math.round(r.top + r.height / 2);
    var mInit = {{ bubbles: true, cancelable: true, view: window, clientX: cx, clientY: cy }};
    if (act === 'hover') {{
      el.dispatchEvent(new MouseEvent('pointerover', mInit));
      el.dispatchEvent(new MouseEvent('mouseover', mInit));
      el.dispatchEvent(new MouseEvent('mouseenter', mInit));
      return JSON.stringify({{ success: true, action: act }});
    }}
    if (act === 'right_click') {{
      el.dispatchEvent(new MouseEvent('pointerdown', Object.assign({{ button: 2 }}, mInit)));
      el.dispatchEvent(new MouseEvent('mousedown', Object.assign({{ button: 2 }}, mInit)));
      el.dispatchEvent(new MouseEvent('contextmenu', Object.assign({{ button: 2 }}, mInit)));
      el.dispatchEvent(new MouseEvent('pointerup', Object.assign({{ button: 2 }}, mInit)));
      el.dispatchEvent(new MouseEvent('mouseup', Object.assign({{ button: 2 }}, mInit)));
      return JSON.stringify({{ success: true, action: act }});
    }}
    if (act === 'fill') {{
      var val = String(opts.value === undefined || opts.value === null ? '' : opts.value);
      try {{ el.focus(); }} catch (_) {{}}
      var proto = el.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
      var desc = Object.getOwnPropertyDescriptor(proto, 'value');
      if (desc && desc.set) desc.set.call(el, val);
      else el.value = val;
      el.dispatchEvent(new Event('input', {{ bubbles: true }}));
      el.dispatchEvent(new Event('change', {{ bubbles: true }}));
      return JSON.stringify({{ success: true, action: act, value: el.value }});
    }}
    if (act === 'select') {{
      var targetVal = opts.value !== undefined ? String(opts.value) : null;
      var targetLabel = opts.label !== undefined ? String(opts.label) : null;
      if (el.tagName === 'SELECT') {{
        var picked = false;
        for (var o = 0; o < el.options.length; o++) {{
          var opt = el.options[o];
          if ((targetVal !== null && opt.value === targetVal) || (targetLabel !== null && opt.text.trim() === targetLabel)) {{
            el.selectedIndex = o;
            picked = true;
            break;
          }}
        }}
        if (!picked) return JSON.stringify({{ success: false, error: 'select_option_not_found' }});
        el.dispatchEvent(new Event('input', {{ bubbles: true }}));
        el.dispatchEvent(new Event('change', {{ bubbles: true }}));
        return JSON.stringify({{ success: true, action: act, value: el.value }});
      }}
      el.click();
      return JSON.stringify({{ success: true, action: act }});
    }}
    if (act === 'double_click' || act === 'click') {{
      try {{ el.focus(); }} catch (_) {{}}
      el.dispatchEvent(new MouseEvent('pointerdown', Object.assign({{ button: 0 }}, mInit)));
      el.dispatchEvent(new MouseEvent('mousedown', Object.assign({{ button: 0 }}, mInit)));
      el.dispatchEvent(new MouseEvent('pointerup', Object.assign({{ button: 0 }}, mInit)));
      el.dispatchEvent(new MouseEvent('mouseup', Object.assign({{ button: 0 }}, mInit)));
      if (typeof el.click === 'function') el.click();
      else el.dispatchEvent(new MouseEvent('click', Object.assign({{ button: 0 }}, mInit)));
      if (act === 'double_click') el.dispatchEvent(new MouseEvent('dblclick', Object.assign({{ button: 0 }}, mInit)));
      return JSON.stringify({{
        success: true,
        action: act,
        tag: el.tagName ? el.tagName.toLowerCase() : '',
        text: (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 80)
      }});
    }}
    return JSON.stringify({{ success: false, error: 'unsupported_action', action: act }});
  }} catch (e) {{
    return JSON.stringify({{ success: false, error: 'act_exception', message: String(e && e.message ? e.message : e) }});
  }}
}})()";
        }
    }
}
