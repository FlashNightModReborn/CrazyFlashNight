using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud.Dialogue;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// G0-1：插话输入控件的可判定部分（模型裁决 + 焦点门 + 热键放行）。
    /// 真机 IME/视觉属于人工验收，见交付说明；这里只锁定"源码级"行为。
    /// </summary>
    public sealed class DialogueInterjectInputTests
    {
        // ── 模型：长度、计数、发送裁决 ─────────────────────────────────────

        [Fact]
        public void ModelCapsAt150AndReportsCounter()
        {
            var model = new DialogueInterjectInputModel { Enabled = true };
            model.SetText(new string('字', 200));
            Assert.Equal(150, model.Length);
            Assert.Equal("150/150", model.CounterText);

            Assert.True(model.ApplyTextChange(new string('字', 151)));   // 超长 → 截断并回写
            Assert.Equal(150, model.Length);
            Assert.False(model.ApplyTextChange("短句"));
            Assert.Equal("短句", model.Text);
            Assert.Equal("2/150", model.CounterText);
        }

        [Fact]
        public void ComposingEnterOnlyConfirmsCandidateAndNeverSends()
        {
            var model = new DialogueInterjectInputModel { Enabled = true };
            model.SetText("你好");
            model.IsComposing = true;

            Assert.Equal(DialogueInterjectKeyResult.Swallow, model.HandleKey(true, false));
            Assert.Equal("你好", model.Text);                            // 文本不动 = 没发送

            model.IsComposing = false;
            Assert.Equal(DialogueInterjectKeyResult.Send, model.HandleKey(true, false));
        }

        [Fact]
        public void EnterDoesNotSendWhenDisabledOrEmpty()
        {
            var model = new DialogueInterjectInputModel { Enabled = false };
            model.SetText("有内容但禁用");
            Assert.Equal(DialogueInterjectKeyResult.Swallow, model.HandleKey(true, false));

            model.Enabled = true;
            model.Clear();
            Assert.Equal(DialogueInterjectKeyResult.Swallow, model.HandleKey(true, false));
        }

        [Fact]
        public void EscapeNeverClosesDialogueButLetsImeCancelComposition()
        {
            var model = new DialogueInterjectInputModel { Enabled = true };
            Assert.Equal(DialogueInterjectKeyResult.Swallow, model.HandleKey(false, true));

            model.IsComposing = true;
            Assert.Equal(DialogueInterjectKeyResult.None, model.HandleKey(false, true));
        }

        [Fact]
        public void FocusSuppressesGameHotkeys()
        {
            var model = new DialogueInterjectInputModel { Enabled = true };
            Assert.False(model.SuppressesGameHotkeys);
            model.Focused = true;
            Assert.True(model.SuppressesGameHotkeys);
        }

        // ── 低级键盘钩子：文字输入态全局放行 ─────────────────────────────

        private static bool Edge(KeyboardHook hook, uint vk, bool down)
        {
            IntPtr data = Marshal.AllocHGlobal(24);
            try
            {
                for (int offset = 0; offset < 24; offset += 4) Marshal.WriteInt32(data, offset, 0);
                Marshal.WriteInt32(data, unchecked((int)vk));
                return hook.ProcessKeyEdge(down ? 0x100 : 0x101, data) != IntPtr.Zero;
            }
            finally { Marshal.FreeHGlobal(data); }
        }

        [Fact]
        public void TextInputActivePassesEveryKeyThrough()
        {
            int advances = 0;
            using (var hook = new KeyboardHook())
            {
                hook.ReadAsyncKeyState = _ => 0;
                hook.LiveForegroundProbeForTests = () => true;
                hook.SetActivationProbe(() => true);
                hook.SetDialogueKeyProbe(vk => vk == 0x0D ? () => advances++ : null);

                hook.SetTextInputActive(true);
                // Enter 归输入框：不触发对话推进，也不被吞
                Assert.False(Edge(hook, 0x0D, true));
                Edge(hook, 0x0D, false);
                Assert.Equal(0, advances);
                // 游戏热键（W / Ctrl 修饰）与 Esc 一律放行
                Assert.False(Edge(hook, 0x57, true));
                Edge(hook, 0x57, false);
                Assert.False(Edge(hook, 0x1B, true));
                Edge(hook, 0x1B, false);

                hook.SetTextInputActive(false);
                Assert.True(Edge(hook, 0x0D, true));                    // 恢复：对话键重新被钩子吃掉
                Edge(hook, 0x0D, false);
                Assert.True(SpinWait.SpinUntil(() => advances == 1, 2000));
            }
        }

        // ── 宿主焦点门：输入框聚焦时不推进对话 ───────────────────────────

        private sealed class TaskHarness : IDisposable
        {
            internal readonly Control Anchor;
            internal readonly NativeDialogueWidget Widget;
            internal readonly NativeDialogueTask Task;
            internal bool Focused;

            internal TaskHarness()
            {
                Anchor = new Control { Size = new Size(1024, 576) };
                Widget = new NativeDialogueWidget(Anchor);
                Task = new NativeDialogueTask(Widget, a => a(), wire => true, () => true);
                Task.BookRetryScheduler = (ms, cb) => { };
                Task.InterjectInputFocused = () => Focused;
                Task.AdoptV2(new JObject
                {
                    ["version"] = 2, ["op"] = "book", ["kind"] = "inline",
                    ["requestId"] = "nd:5", ["sceneId"] = "scene.1",
                    ["mode"] = "ordinary", ["epoch"] = 1, ["startIndex"] = 0,
                    ["advanceKey"] = 13,
                    ["lines"] = new JArray(new JObject
                    {
                        ["name"] = "Andy Law", ["title"] = "雇佣兵", ["text"] = "第一句",
                        ["portrait"] = new JObject
                        {
                            ["kind"] = "static", ["key"] = "Andy Law", ["expression"] = "普通"
                        },
                        ["imageAction"] = "keep"
                    }, new JObject
                    {
                        ["name"] = "Andy Law", ["title"] = "雇佣兵", ["text"] = "第二句",
                        ["portrait"] = new JObject
                        {
                            ["kind"] = "static", ["key"] = "Andy Law", ["expression"] = "普通"
                        },
                        ["imageAction"] = "keep"
                    })
                });
            }

            public void Dispose()
            {
                try { Widget.Dispose(); } catch { }
                try { Anchor.Dispose(); } catch { }
            }
        }

        [Fact]
        public void FocusedInputBlocksAdvanceKeysAndAdvanceVerb()
        {
            using var h = new TaskHarness();
            Assert.NotNull(h.Task.CaptureKeyboardAction(13));            // 未聚焦：Enter 归对话

            h.Focused = true;
            Assert.Null(h.Task.CaptureKeyboardAction(13));               // 聚焦：Enter 归输入框
            Assert.Null(h.Task.CaptureKeyboardAction(27));               // 聚焦：Esc 不关对话

            string before = h.Widget.CurrentFrame.Text;
            h.Widget.InputRequested(h.Widget.CurrentFrame, "advance");   // 聚焦期间的迟到推进被丢弃
            Assert.Equal(before, h.Widget.CurrentFrame.Text);

            h.Focused = false;
            h.Widget.InputRequested(h.Widget.CurrentFrame, "advance");   // 失焦后恢复推进
            Assert.Equal("第二句", h.Widget.CurrentFrame.Text);
        }
    }
}
