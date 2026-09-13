using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Dialogue;
using CF7Launcher.Guardian.Hud.Dialogue;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class NativeDialogueTaskTests
    {
        private static JObject Frame(int sequence = 1, int revision = 1, string imageAction = "keep")
        {
            return new JObject
            {
                ["version"] = 1, ["op"] = "show", ["requestId"] = "nd:" + sequence,
                ["sceneId"] = "scene.1", ["revision"] = revision,
                ["lineIndex"] = revision - 1, ["lineCount"] = 38,
                ["name"] = "Andy Law", ["title"] = "雇佣兵", ["text"] = "他说：\"你好\"。",
                ["portrait"] = new JObject { ["kind"] = "static", ["key"] = "Andy Law", ["expression"] = "普通" },
                ["imageAction"] = imageAction, ["imagePath"] = "flashswf/images/task_images/任务栏提示.png"
            };
        }

        [Fact]
        public void ShowHideReorderDoesNotResurrectRetiredDialogue()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeDialogueWidget(anchor);
            var task = new NativeDialogueTask(widget, a => a(), _ => true);
            task.Adopt(Frame());
            task.Adopt(new JObject { ["version"] = 1, ["op"] = "hide", ["requestId"] = "nd:1", ["sceneId"] = "scene.1" });
            task.Adopt(Frame());
            Assert.Null(widget.CurrentFrame);
            task.Adopt(Frame(2));
            task.Adopt(Frame(1, 2));
            Assert.Equal("nd:2", widget.CurrentFrame.RequestId);
        }

        [Fact]
        public void DelayedCloseCannotCloseNewLineAndDoubleClickSendsOnce()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeDialogueWidget(anchor);
            var sent = new List<string>();
            var task = new NativeDialogueTask(widget, a => a(), wire => { sent.Add(wire); return true; });
            task.Adopt(Frame());
            var old = widget.CurrentFrame;
            task.Adopt(Frame(1, 2));
            widget.InputRequested(old, "close");
            Assert.Empty(sent);
            widget.InputRequested(widget.CurrentFrame, "advance");
            widget.InputRequested(widget.CurrentFrame, "advance");
            Assert.Single(sent);
            JObject command = JObject.Parse(sent[0].TrimEnd('\0'));
            Assert.Equal(2, command.Value<int>("revision"));
            Assert.Equal("nativeDialogueAction", command.Value<string>("action"));
        }

        [Fact]
        public void TransportRejectionDoesNotConsumeManualRetry()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeDialogueWidget(anchor);
            int calls = 0;
            var task = new NativeDialogueTask(widget, a => a(), _ => ++calls > 1);
            task.Adopt(Frame());
            widget.InputRequested(widget.CurrentFrame, "close");
            widget.InputRequested(widget.CurrentFrame, "close");
            Assert.Equal(2, calls);
        }

        [Fact]
        public void CapturedKeyAndDisconnectAreSafeAfterUiDisposal()
        {
            using var anchor = new Control();
            using var widget = new NativeDialogueWidget(anchor, () => new Rectangle(0, 0, 1024, 576));
            var task = new NativeDialogueTask(widget, _ => throw new ObjectDisposedException("fixture"), _ => true);
            task.Adopt(Frame());
            Action key = task.CaptureKeyboardAction(13);
            Assert.NotNull(key);
            key();
            task.HandleTransportDisconnected();
        }

        [Fact]
        public void CloseIsNotLostBehindAdvanceDebounce()
        {
            using var anchor = new Control();
            using var widget = new NativeDialogueWidget(anchor);
            var sent = new List<string>();
            var task = new NativeDialogueTask(widget, a => a(), wire => { sent.Add(wire); return true; });
            task.Adopt(Frame());
            widget.InputRequested(widget.CurrentFrame, "advance");
            widget.InputRequested(widget.CurrentFrame, "close");
            widget.InputRequested(widget.CurrentFrame, "close");
            Assert.Equal(2, sent.Count);
        }

        [Fact]
        public void DisconnectionInvalidatesShowAlreadyQueuedOnUiThread()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeDialogueWidget(anchor);
            var queue = new Queue<Action>();
            var task = new NativeDialogueTask(widget, queue.Enqueue, _ => true);
            task.Handle(new JObject { ["payload"] = Frame() });
            task.HandleTransportDisconnected();
            while (queue.Count > 0) queue.Dequeue()();
            Assert.Null(widget.CurrentFrame);
        }

        [Fact]
        public void KeepImageLineRetainsSubscriptionWhenPreviousLoadIsLate()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeDialogueWidget(anchor);
            var paths = new List<string>();
            var task = new NativeDialogueTask(widget, a => a(), _ => true);
            task.LoadSceneImage = (path, callback) => paths.Add(path);
            task.Adopt(Frame(1, 1, "show"));
            task.Adopt(Frame(1, 2, "keep"));
            task.Adopt(Frame(1, 3, "clear"));
            task.Adopt(Frame(1, 4, "keep"));
            Assert.Equal(2, paths.Count);
            Assert.Equal(paths[0], paths[1]);
        }

        [Theory]
        [InlineData("nd:0")]
        [InlineData("nd:01")]
        [InlineData("nd:+1")]
        [InlineData("nd:1e2")]
        public void NonCanonicalRequestIdentityIsRejected(string identity)
        {
            JObject p = Frame(); p["requestId"] = identity;
            Assert.False(NativeDialogueTask.TryParse(p, out _, out _, out _));
        }

        [Fact]
        public void WebCannotForgeDialogueAuthority()
        {
            Assert.False(WebOverlayForm.IsWebTaskRouterIngressAllowed("native_dialogue"));
            Assert.True(WebOverlayForm.IsWebTaskRouterIngressAllowed("dialogue_portrait_result"));
            JObject p = Frame(); p["revision"] = "1";
            Assert.False(NativeDialogueTask.TryParse(p, out _, out _, out _));
        }

        [Fact]
        public void PortraitIdentityIncludesIndependentActorExpressionAndAssetVersion()
        {
            JObject a = DialoguePortraitService.NormalizeAppearance(new JObject { ["gender"] = "男", ["face"] = "1", ["hair"] = "短发" });
            JObject b = DialoguePortraitService.NormalizeAppearance(new JObject { ["gender"] = "男", ["face"] = "2", ["hair"] = "短发" });
            string key = DialoguePortraitService.DollKey(a, "普通", "assets1");
            Assert.NotEqual(key, DialoguePortraitService.DollKey(b, "普通", "assets1"));
            Assert.NotEqual(key, DialoguePortraitService.DollKey(a, "愤怒", "assets1"));
            Assert.NotEqual(key, DialoguePortraitService.DollKey(a, "普通", "assets2"));
        }

        [Fact]
        public void PortraitDecoderDoesNotAcceptLootIconSize()
        {
            using var image = new Bitmap(256, 256);
            using var stream = new MemoryStream();
            image.Save(stream, ImageFormat.Png);
            Assert.Null(DialoguePortraitService.DecodeResult(Convert.ToBase64String(stream.ToArray())));
        }

        [Theory]
        [InlineData("../outside.png")]
        [InlineData("C:/private.png")]
        [InlineData("https://example.com/a.png")]
        [InlineData("/outside.png")]
        public void ImagePathsStayWithinAssetRoot(string path)
        {
            Assert.Null(DialoguePortraitService.SafeChild(Path.GetTempPath(), path));
        }
    }
}
