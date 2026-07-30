using System;
using Microsoft.Web.WebView2.Core;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// BootstrapPanel 与 WebOverlayForm 共用的浏览器输入/调试面策略。
    /// 玩家缩放在两种模式下都关闭；只有显式 developer mode 才开放浏览器
    /// accelerator、DevTools 与默认右键菜单。两个本地游戏宿主都不承载
    /// 登录表单，因此自动填充与密码保存始终关闭，避免产生无主浏览器状态。
    /// </summary>
    internal static class WebView2BrowserPolicy
    {
        internal readonly struct SettingsSnapshot
        {
            internal SettingsSnapshot(
                bool isZoomControlEnabled,
                bool isPinchZoomEnabled,
                bool areBrowserAcceleratorKeysEnabled,
                bool areDevToolsEnabled,
                bool areDefaultContextMenusEnabled,
                bool isGeneralAutofillEnabled,
                bool isPasswordAutosaveEnabled)
            {
                IsZoomControlEnabled = isZoomControlEnabled;
                IsPinchZoomEnabled = isPinchZoomEnabled;
                AreBrowserAcceleratorKeysEnabled = areBrowserAcceleratorKeysEnabled;
                AreDevToolsEnabled = areDevToolsEnabled;
                AreDefaultContextMenusEnabled = areDefaultContextMenusEnabled;
                IsGeneralAutofillEnabled = isGeneralAutofillEnabled;
                IsPasswordAutosaveEnabled = isPasswordAutosaveEnabled;
            }

            internal bool IsZoomControlEnabled { get; }
            internal bool IsPinchZoomEnabled { get; }
            internal bool AreBrowserAcceleratorKeysEnabled { get; }
            internal bool AreDevToolsEnabled { get; }
            internal bool AreDefaultContextMenusEnabled { get; }
            internal bool IsGeneralAutofillEnabled { get; }
            internal bool IsPasswordAutosaveEnabled { get; }
        }

        internal static SettingsSnapshot Resolve(bool explicitDeveloperMode)
        {
            return new SettingsSnapshot(
                isZoomControlEnabled: false,
                isPinchZoomEnabled: false,
                areBrowserAcceleratorKeysEnabled: explicitDeveloperMode,
                areDevToolsEnabled: explicitDeveloperMode,
                areDefaultContextMenusEnabled: explicitDeveloperMode,
                isGeneralAutofillEnabled: false,
                isPasswordAutosaveEnabled: false);
        }

        internal static void Apply(
            CoreWebView2Settings settings,
            bool explicitDeveloperMode,
            string hostName)
        {
            if (settings == null)
                throw new ArgumentNullException(nameof(settings));

            SettingsSnapshot policy = Resolve(explicitDeveloperMode);
            settings.IsZoomControlEnabled = policy.IsZoomControlEnabled;
            settings.IsPinchZoomEnabled = policy.IsPinchZoomEnabled;
            settings.AreBrowserAcceleratorKeysEnabled =
                policy.AreBrowserAcceleratorKeysEnabled;
            settings.AreDevToolsEnabled = policy.AreDevToolsEnabled;
            settings.AreDefaultContextMenusEnabled =
                policy.AreDefaultContextMenusEnabled;
            settings.IsGeneralAutofillEnabled =
                policy.IsGeneralAutofillEnabled;
            settings.IsPasswordAutosaveEnabled =
                policy.IsPasswordAutosaveEnabled;

            LogManager.Log(
                "[WebView2Policy] host=" + (hostName ?? "(unknown)")
                + " developerMode=" + explicitDeveloperMode
                + " zoom=" + policy.IsZoomControlEnabled
                + " pinch=" + policy.IsPinchZoomEnabled
                + " accelerators=" + policy.AreBrowserAcceleratorKeysEnabled
                + " devTools=" + policy.AreDevToolsEnabled
                + " contextMenus=" + policy.AreDefaultContextMenusEnabled
                + " autofill=" + policy.IsGeneralAutofillEnabled
                + " passwordAutosave=" + policy.IsPasswordAutosaveEnabled);
        }
    }
}
