using System;
using System.Collections.Generic;
using System.Drawing;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// CompositeNotchSink fan-out 不变量。
    ///
    /// 关键回归：
    /// 1. 所有 sink 都收到调用（含 null sink 静默跳过）
    /// 2. 一个 sink 抛异常不阻断其他 sink（panel-only 切换时 webOverlay 短暂未就绪不能拖累 NativeHud）
    /// 3. 调用顺序保留（sink#0 先收到）
    /// 4. SetReady 也 fan-out
    /// </summary>
    public class CompositeNotchSinkTests
    {
        private sealed class RecordingSink : INotchSink
        {
            public List<string> Events = new List<string>();
            public bool ThrowOnAddNotice;
            public bool ThrowOnSetStatus;
            public bool ThrowOnClearStatus;
            public bool ThrowOnSetReady;
            public void AddNotice(string category, string text, Color accentColor)
            {
                Events.Add("notice:" + category + "|" + text);
                if (ThrowOnAddNotice) throw new InvalidOperationException("explode-notice");
            }
            public void SetStatusItem(string id, string label, string subLabel, Color accentColor)
            {
                Events.Add("status:" + id + "|" + label);
                if (ThrowOnSetStatus) throw new InvalidOperationException("explode-status");
            }
            public void ClearStatusItem(string id)
            {
                Events.Add("clear:" + id);
                if (ThrowOnClearStatus) throw new InvalidOperationException("explode-clear");
            }
            public void SetReady()
            {
                Events.Add("ready");
                if (ThrowOnSetReady) throw new InvalidOperationException("explode-ready");
            }
        }

        [Fact]
        public void AddNotice_FansOutToAllSinksInOrder()
        {
            RecordingSink a = new RecordingSink();
            RecordingSink b = new RecordingSink();
            CompositeNotchSink composite = new CompositeNotchSink(a, b);
            composite.AddNotice("combo", "DFA 波动拳", Color.Gold);
            Assert.Single(a.Events);
            Assert.Single(b.Events);
            Assert.Equal("notice:combo|DFA 波动拳", a.Events[0]);
            Assert.Equal("notice:combo|DFA 波动拳", b.Events[0]);
        }

        [Fact]
        public void NullSink_SilentlySkipped()
        {
            RecordingSink a = new RecordingSink();
            CompositeNotchSink composite = new CompositeNotchSink(null, a, null);
            composite.AddNotice("perf", "tick", Color.White);
            composite.SetStatusItem("id", "label", "sub", Color.White);
            composite.ClearStatusItem("id");
            composite.SetReady();
            Assert.Equal(4, a.Events.Count);
        }

        [Fact]
        public void SinkThrows_OtherSinksStillReceive()
        {
            RecordingSink a = new RecordingSink { ThrowOnAddNotice = true };
            RecordingSink b = new RecordingSink();
            CompositeNotchSink composite = new CompositeNotchSink(a, b);
            // 不应冒泡
            composite.AddNotice("combo", "Sync 招", Color.Cyan);
            Assert.Single(a.Events); // a 抛了但记录在前
            Assert.Single(b.Events); // b 仍然收到
        }

        [Fact]
        public void SetStatusItem_FansOut()
        {
            RecordingSink a = new RecordingSink();
            RecordingSink b = new RecordingSink();
            CompositeNotchSink composite = new CompositeNotchSink(a, b);
            composite.SetStatusItem("icon_bake", "Baking", "5/10", Color.Cyan);
            Assert.Single(a.Events);
            Assert.Single(b.Events);
            Assert.Contains("status:icon_bake", a.Events[0]);
        }

        [Fact]
        public void ClearStatusItem_FansOut()
        {
            RecordingSink a = new RecordingSink();
            RecordingSink b = new RecordingSink();
            CompositeNotchSink composite = new CompositeNotchSink(a, b);
            composite.ClearStatusItem("icon_bake");
            Assert.Equal("clear:icon_bake", a.Events[0]);
            Assert.Equal("clear:icon_bake", b.Events[0]);
        }

        [Fact]
        public void SetReady_FansOut()
        {
            RecordingSink a = new RecordingSink();
            RecordingSink b = new RecordingSink();
            CompositeNotchSink composite = new CompositeNotchSink(a, b);
            composite.SetReady();
            Assert.Equal("ready", a.Events[0]);
            Assert.Equal("ready", b.Events[0]);
        }

        [Fact]
        public void NullSinksArray_IsTreatedAsEmpty()
        {
            CompositeNotchSink composite = new CompositeNotchSink((INotchSink[])null);
            // 不应抛
            composite.AddNotice("anything", "anything", Color.Red);
            composite.SetReady();
        }
    }
}
