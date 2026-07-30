using System;
using System.IO;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class WebView2BrowserPolicyTests
    {
        [Theory]
        [InlineData(false, false, false, false, false, false, false, false)]
        [InlineData(true, false, false, true, true, true, false, false)]
        public void Resolve_ReturnsExactProductionAndDeveloperMatrix(
            bool developerMode,
            bool zoom,
            bool pinch,
            bool accelerators,
            bool devTools,
            bool contextMenus,
            bool autofill,
            bool passwordAutosave)
        {
            WebView2BrowserPolicy.SettingsSnapshot policy =
                WebView2BrowserPolicy.Resolve(developerMode);

            Assert.Equal(zoom, policy.IsZoomControlEnabled);
            Assert.Equal(pinch, policy.IsPinchZoomEnabled);
            Assert.Equal(
                accelerators,
                policy.AreBrowserAcceleratorKeysEnabled);
            Assert.Equal(devTools, policy.AreDevToolsEnabled);
            Assert.Equal(
                contextMenus,
                policy.AreDefaultContextMenusEnabled);
            Assert.Equal(autofill, policy.IsGeneralAutofillEnabled);
            Assert.Equal(
                passwordAutosave,
                policy.IsPasswordAutosaveEnabled);
        }

        [Fact]
        public void DeveloperMode_NeverReopensUserZoom()
        {
            WebView2BrowserPolicy.SettingsSnapshot policy =
                WebView2BrowserPolicy.Resolve(true);

            Assert.False(policy.IsZoomControlEnabled);
            Assert.False(policy.IsPinchZoomEnabled);
            Assert.False(policy.IsGeneralAutofillEnabled);
            Assert.False(policy.IsPasswordAutosaveEnabled);
        }

        [Theory]
        [InlineData("BootstrapPanel.cs", "BootstrapPanel")]
        [InlineData("WebOverlayForm.cs", "WebOverlayForm")]
        public void BothHostsApplySharedPolicyAfterEnsureAndBeforeNavigate(
            string fileName,
            string hostName)
        {
            string source = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Guardian", fileName));
            string initMethod = ExtractMethodBody(
                source,
                "private async void InitWebView2Async(");

            int ensure = initMethod.IndexOf(
                "EnsureCoreWebView2Async",
                StringComparison.Ordinal);
            int apply = initMethod.IndexOf(
                "WebView2BrowserPolicy.Apply(",
                StringComparison.Ordinal);
            int navigate = initMethod.IndexOf(
                ".Navigate(",
                StringComparison.Ordinal);

            Assert.True(ensure >= 0, hostName + " must ensure CoreWebView2.");
            Assert.True(apply > ensure, hostName + " must apply policy after EnsureCore.");
            Assert.True(navigate > apply, hostName + " must apply policy before Navigate.");
            Assert.Equal(
                1,
                CountOccurrences(
                    initMethod,
                    "WebView2BrowserPolicy.Apply("));
            string applySection =
                initMethod.Substring(apply, navigate - apply);
            Assert.Contains(
                "_webView.CoreWebView2.Settings",
                applySection,
                StringComparison.Ordinal);
            Assert.Contains(
                "_webView2DeveloperMode",
                applySection,
                StringComparison.Ordinal);
            Assert.Contains(
                "\"" + hostName + "\"",
                applySection,
                StringComparison.Ordinal);
            Assert.DoesNotContain(
                "Settings.AreDevToolsEnabled =",
                source,
                StringComparison.Ordinal);
            Assert.DoesNotContain(
                "Settings.AreDefaultContextMenusEnabled =",
                source,
                StringComparison.Ordinal);
        }

        [Fact]
        public void StartupWiringPassesExplicitConfigToBothHosts()
        {
            string program = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Program.cs"));
            string guardian = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Guardian", "GuardianForm.cs"));

            string guardianConstruction = ExtractSection(
                program,
                "GuardianForm form = new GuardianForm(",
                "_guardianForm = form;");
            string overlayConstruction = ExtractSection(
                program,
                "webOverlay = new WebOverlayForm(",
                "StartupDiagnostics.Mark(\"web_overlay.construct_ok\")");

            Assert.Contains(
                "config.WebView2DeveloperMode",
                guardianConstruction,
                StringComparison.Ordinal);
            Assert.Contains(
                "config.WebView2DeveloperMode",
                overlayConstruction,
                StringComparison.Ordinal);
            Assert.Contains(
                "bootstrapWebView2DeveloperMode",
                guardian,
                StringComparison.Ordinal);
            Assert.Contains(
                "new BootstrapPanel(",
                guardian,
                StringComparison.Ordinal);
        }

        private static string ExtractSection(
            string source,
            string startMarker,
            string endMarker)
        {
            int start = source.IndexOf(
                startMarker,
                StringComparison.Ordinal);
            Assert.True(start >= 0);
            int end = source.IndexOf(
                endMarker,
                start,
                StringComparison.Ordinal);
            Assert.True(end > start);
            return source.Substring(start, end - start);
        }

        private static string ExtractMethodBody(
            string source,
            string signatureMarker)
        {
            int signature = source.IndexOf(
                signatureMarker,
                StringComparison.Ordinal);
            Assert.True(signature >= 0);
            int openBrace = source.IndexOf('{', signature);
            Assert.True(openBrace > signature);

            int depth = 0;
            bool inString = false;
            bool inChar = false;
            bool escaped = false;
            bool lineComment = false;
            bool blockComment = false;
            for (int index = openBrace; index < source.Length; index++)
            {
                char current = source[index];
                char next =
                    index + 1 < source.Length ? source[index + 1] : '\0';
                if (lineComment)
                {
                    if (current == '\n') lineComment = false;
                    continue;
                }
                if (blockComment)
                {
                    if (current == '*' && next == '/')
                    {
                        blockComment = false;
                        index++;
                    }
                    continue;
                }
                if (inString || inChar)
                {
                    if (escaped)
                    {
                        escaped = false;
                        continue;
                    }
                    if (current == '\\')
                    {
                        escaped = true;
                        continue;
                    }
                    if (inString && current == '"') inString = false;
                    if (inChar && current == '\'') inChar = false;
                    continue;
                }
                if (current == '/' && next == '/')
                {
                    lineComment = true;
                    index++;
                    continue;
                }
                if (current == '/' && next == '*')
                {
                    blockComment = true;
                    index++;
                    continue;
                }
                if (current == '"')
                {
                    inString = true;
                    continue;
                }
                if (current == '\'')
                {
                    inChar = true;
                    continue;
                }
                if (current == '{') depth++;
                if (current != '}') continue;
                depth--;
                if (depth == 0)
                    return source.Substring(
                        openBrace,
                        index - openBrace + 1);
            }

            throw new InvalidDataException(
                "Unterminated method body: " + signatureMarker);
        }

        private static int CountOccurrences(string source, string value)
        {
            int count = 0;
            int offset = 0;
            while ((offset = source.IndexOf(
                value,
                offset,
                StringComparison.Ordinal)) >= 0)
            {
                count++;
                offset += value.Length;
            }
            return count;
        }

        private static string FindRepositoryFile(
            params string[] relativeParts)
        {
            DirectoryInfo current =
                new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                string candidate = current.FullName;
                foreach (string part in relativeParts)
                    candidate = Path.Combine(candidate, part);
                if (File.Exists(candidate))
                    return candidate;
                current = current.Parent;
            }

            throw new FileNotFoundException(
                "Unable to locate repository file: "
                + string.Join("/", relativeParts));
        }
    }
}
