using System;
using System.Drawing;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 把单一 INotchSink 入口 fan-out 到多个 sink。
    ///
    /// 任一 sink 抛异常都不影响其他 sink；所有错误进 launcher.log。
    ///
    /// **Category 路由**：第二组 sink 可注入 `AcceptCategory` 谓词；返回 false 时该 category 不路由给本 sink。
    ///
    /// SetReady / SetStatusItem / ClearStatusItem 不走 category 路由，所有 sink 都收。
    ///
    /// 注：useNativeHud=false 分支拆除后生产侧不再装配本类（notchSink 直接是 NativeHudOverlay）；
    /// 类保留给 CompositeNotchSinkTests 与潜在的未来 fan-out 需求。
    /// </summary>
    public class CompositeNotchSink : INotchSink
    {
        public sealed class Entry
        {
            public readonly INotchSink Sink;
            /// <summary>null = 接收所有 category；非 null = 仅在谓词返回 true 时接收 AddNotice。</summary>
            public readonly Predicate<string> AcceptCategory;
            public Entry(INotchSink sink, Predicate<string> acceptCategory)
            {
                Sink = sink;
                AcceptCategory = acceptCategory;
            }
        }

        private readonly Entry[] _entries;

        /// <summary>原构造函数：所有 sink 接收所有 category。</summary>
        public CompositeNotchSink(params INotchSink[] sinks)
        {
            if (sinks == null) { _entries = new Entry[0]; return; }
            _entries = new Entry[sinks.Length];
            for (int i = 0; i < sinks.Length; i++) _entries[i] = new Entry(sinks[i], null);
        }

        /// <summary>category-aware 构造：每个 sink 可声明 AcceptCategory 谓词。</summary>
        public CompositeNotchSink(params Entry[] entries)
        {
            _entries = entries ?? new Entry[0];
        }

        public void AddNotice(string category, string text, Color accentColor)
        {
            for (int i = 0; i < _entries.Length; i++)
            {
                Entry e = _entries[i];
                if (e == null || e.Sink == null) continue;
                if (e.AcceptCategory != null)
                {
                    bool accept;
                    try { accept = e.AcceptCategory(category); }
                    catch (Exception ex)
                    {
                        LogManager.Log("[CompositeNotch] AcceptCategory sink#" + i + " threw: " + ex.Message);
                        accept = false; // 出错保守不路由
                    }
                    if (!accept) continue;
                }
                try { e.Sink.AddNotice(category, text, accentColor); }
                catch (Exception ex) { LogManager.Log("[CompositeNotch] AddNotice sink#" + i + " threw: " + ex.Message); }
            }
        }

        public void SetStatusItem(string id, string label, string subLabel, Color accentColor)
        {
            for (int i = 0; i < _entries.Length; i++)
            {
                Entry e = _entries[i];
                if (e == null || e.Sink == null) continue;
                try { e.Sink.SetStatusItem(id, label, subLabel, accentColor); }
                catch (Exception ex) { LogManager.Log("[CompositeNotch] SetStatusItem sink#" + i + " threw: " + ex.Message); }
            }
        }

        public void ClearStatusItem(string id)
        {
            for (int i = 0; i < _entries.Length; i++)
            {
                Entry e = _entries[i];
                if (e == null || e.Sink == null) continue;
                try { e.Sink.ClearStatusItem(id); }
                catch (Exception ex) { LogManager.Log("[CompositeNotch] ClearStatusItem sink#" + i + " threw: " + ex.Message); }
            }
        }

        public void SetReady()
        {
            for (int i = 0; i < _entries.Length; i++)
            {
                Entry e = _entries[i];
                if (e == null || e.Sink == null) continue;
                try { e.Sink.SetReady(); }
                catch (Exception ex) { LogManager.Log("[CompositeNotch] SetReady sink#" + i + " threw: " + ex.Message); }
            }
        }
    }
}
