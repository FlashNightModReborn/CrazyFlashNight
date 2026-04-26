using System;
using System.Drawing;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 把单一 INotchSink 入口 fan-out 到多个 sink。
    ///
    /// 用途：useNativeHud=true 时 N 前缀通知既要送到 web overlay（兼容旧渲染），
    /// 也要送到 NativeHudOverlay（让 ComboWidget 等 native consumer 收到 category="combo" 通知）。
    /// 任一 sink 抛异常都不影响其他 sink；所有错误进 launcher.log。
    ///
    /// SetReady 仅在所有非 null sink 上各调一次；不传染状态。
    /// </summary>
    public class CompositeNotchSink : INotchSink
    {
        private readonly INotchSink[] _sinks;

        public CompositeNotchSink(params INotchSink[] sinks)
        {
            _sinks = sinks ?? new INotchSink[0];
        }

        public void AddNotice(string category, string text, Color accentColor)
        {
            for (int i = 0; i < _sinks.Length; i++)
            {
                INotchSink s = _sinks[i];
                if (s == null) continue;
                try { s.AddNotice(category, text, accentColor); }
                catch (Exception ex) { LogManager.Log("[CompositeNotch] AddNotice sink#" + i + " threw: " + ex.Message); }
            }
        }

        public void SetStatusItem(string id, string label, string subLabel, Color accentColor)
        {
            for (int i = 0; i < _sinks.Length; i++)
            {
                INotchSink s = _sinks[i];
                if (s == null) continue;
                try { s.SetStatusItem(id, label, subLabel, accentColor); }
                catch (Exception ex) { LogManager.Log("[CompositeNotch] SetStatusItem sink#" + i + " threw: " + ex.Message); }
            }
        }

        public void ClearStatusItem(string id)
        {
            for (int i = 0; i < _sinks.Length; i++)
            {
                INotchSink s = _sinks[i];
                if (s == null) continue;
                try { s.ClearStatusItem(id); }
                catch (Exception ex) { LogManager.Log("[CompositeNotch] ClearStatusItem sink#" + i + " threw: " + ex.Message); }
            }
        }

        public void SetReady()
        {
            for (int i = 0; i < _sinks.Length; i++)
            {
                INotchSink s = _sinks[i];
                if (s == null) continue;
                try { s.SetReady(); }
                catch (Exception ex) { LogManager.Log("[CompositeNotch] SetReady sink#" + i + " threw: " + ex.Message); }
            }
        }
    }
}
