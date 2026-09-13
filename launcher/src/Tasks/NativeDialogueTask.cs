using System;
using System.Drawing;
using System.Globalization;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud.Dialogue;

namespace CF7Launcher.Tasks
{
    /// <summary>AS2 持有对话权威；宿主只采用有序快照并回送一次当前行的输入。</summary>
    public sealed class NativeDialogueTask
    {
        public const string TaskKey = "native_dialogue";
        private readonly NativeDialogueWidget _widget;
        private readonly Action<Action> _dispatch;
        private readonly Func<string, bool> _send;
        private readonly Func<bool> _inputAllowed;
        private long _maxSequence;
        private long _transportEpoch;
        private volatile NativeDialogueFrame _current;
        private int _advanceKey = 13;
        private int _sentRevision;
        private string _sentVerb;
        private long _sentAt;
        private string _sceneImagePath;

        // 回调收到的位图由 task 在 widget 克隆后释放。资源解析不拥有剧情推进权。
        internal Action<NativeDialogueFrame, JObject, Action<Bitmap>> LoadPortrait;
        /// <summary>元数据感知立绘加载（优先于 LoadPortrait）：回调第二参 = 外部 SWF
        /// 作者取景的舞台逻辑矩形（可为 null）。与位图同属一次 revision 投递。</summary>
        internal Action<NativeDialogueFrame, JObject, Action<Bitmap, RectangleF?>> LoadPortraitWithRect;
        internal Action<string, Action<Bitmap>> LoadSceneImage;
        internal Func<JObject, string> ReceivePortraitResult;

        public string HandlePortraitResult(JObject message)
        {
            return ReceivePortraitResult?.Invoke(message) ?? "{\"success\":false}";
        }

        internal NativeDialogueTask(XmlSocketServer socket, NativeDialogueWidget widget,
            Action<Action> dispatch, Func<bool> inputAllowed = null)
            : this(widget, dispatch,
                wire => socket != null && socket.IsClientReady && socket.TrySend(wire), inputAllowed) { }

        internal NativeDialogueTask(NativeDialogueWidget widget, Action<Action> dispatch,
            Func<string, bool> send, Func<bool> inputAllowed = null)
        {
            _widget = widget ?? throw new ArgumentNullException(nameof(widget));
            _dispatch = dispatch ?? throw new ArgumentNullException(nameof(dispatch));
            _send = send ?? throw new ArgumentNullException(nameof(send));
            _inputAllowed = inputAllowed ?? (() => true);
            _widget.InputRequested = OnInput;
        }

        public string Handle(JObject message)
        {
            var payload = message?["payload"] as JObject;
            if (payload == null) return null;
            var copy = (JObject)payload.DeepClone();
            long epoch = Interlocked.Read(ref _transportEpoch);
            try { _dispatch(() => { if (epoch == Interlocked.Read(ref _transportEpoch)) Adopt(copy); }); }
            catch (ObjectDisposedException) { }
            catch (InvalidOperationException) { }
            return null;
        }

        internal void Adopt(JObject payload)
        {
            NativeDialogueFrame frame;
            long sequence;
            bool hide;
            if (!TryParse(payload, out frame, out sequence, out hide))
            {
                LogManager.Log("[NativeDialogue] rejected malformed snapshot");
                return;
            }
            if (sequence < _maxSequence) return;
            var previous = _current;
            if (hide)
            {
                // hide 也形成墓碑：排队中较早的 show 不得重新打开同一请求。
                if (sequence == _maxSequence && previous != null
                    && previous.SceneId != frame.SceneId) return;
                _maxSequence = sequence;
                if (previous == null || previous.RequestId == frame.RequestId || sequence > SequenceOf(previous.RequestId))
                {
                    _current = null;
                    _sceneImagePath = null;
                    _sentRevision = 0;
                    _widget.Reset();
                }
                return;
            }
            if (sequence == _maxSequence)
            {
                if (previous == null || previous.RequestId != frame.RequestId
                    || previous.SceneId != frame.SceneId || frame.Revision <= previous.Revision) return;
            }
            else
            {
                _sceneImagePath = null;
                _widget.Reset();
            }
            _maxSequence = sequence;
            _current = frame;
            _sentRevision = 0;
            int advanceKey;
            _advanceKey = Int(payload, "advanceKey", 1, 254, out advanceKey) ? advanceKey : 13;
            if (frame.ImageAction == "clear") _sceneImagePath = null;
            else if (frame.ImageAction == "show") _sceneImagePath = frame.ImagePath;
            _widget.ShowFrame(frame);

            var appearance = payload["portrait"]?["appearance"] as JObject;
            if (LoadPortraitWithRect != null)
                LoadPortraitWithRect(frame, appearance,
                    (bitmap, stageRect) => CompleteBitmap(frame, bitmap, stageRect, false));
            else
                LoadPortrait?.Invoke(frame, appearance,
                    bitmap => CompleteBitmap(frame, bitmap, null, false));
            // keep 行同样订阅当前图片，防止前一行的异步加载在换行后被 revision 门丢掉。
            if (!string.IsNullOrEmpty(_sceneImagePath))
                LoadSceneImage?.Invoke(_sceneImagePath, bitmap => CompleteBitmap(frame, bitmap, null, true));
        }

        /// <summary>位图 + 作者取景矩形（stageRect）同属一次 revision 的原子投递：
        /// 迟到帧 ReferenceEquals 门先拦，SetPortrait 再按 request/revision 双验，
        /// 过期包连图带元数据整体丢弃，不改动新句取景。</summary>
        private void CompleteBitmap(NativeDialogueFrame frame, Bitmap bitmap,
            RectangleF? stageRect, bool sceneImage)
        {
            if (bitmap == null) return;
            try
            {
                _dispatch(() =>
                {
                    using (bitmap)
                    {
                        if (!ReferenceEquals(_current, frame)) return;
                        if (sceneImage) _widget.SetSceneImage(frame.RequestId, frame.Revision, bitmap);
                        else _widget.SetPortrait(frame.RequestId, frame.Revision, bitmap, stageRect);
                    }
                });
            }
            catch { bitmap.Dispose(); }
        }

        private void OnInput(NativeDialogueFrame frame, string verb)
        {
            var current = _current;
            if (current == null || frame.RequestId != current.RequestId || frame.SceneId != current.SceneId
                || frame.Revision != current.Revision || !_inputAllowed()
                || (_sentRevision == frame.Revision && _sentVerb == verb && Environment.TickCount64 - _sentAt < 750)
                || (verb != "advance" && verb != "close")) return;
            var command = new JObject
            {
                ["task"] = "cmd", ["action"] = "nativeDialogueAction",
                ["requestId"] = frame.RequestId, ["sceneId"] = frame.SceneId,
                ["revision"] = frame.Revision, ["verb"] = verb
            };
            bool sent = false;
            try { sent = _send(command.ToString(Formatting.None) + "\0"); }
            catch (Exception ex) { LogManager.Log("[NativeDialogue] input transport: " + ex.Message); }
            if (sent) { _sentRevision = frame.Revision; _sentVerb = verb; _sentAt = Environment.TickCount64; }
        }

        /// <summary>低级钩子只捕获当前行；UI 回调再次验证，迟到按键不能推进下一行。</summary>
        internal Action CaptureKeyboardAction(uint virtualKey)
        {
            var frame = _current;
            if (frame == null || !_widget.Visible || !_inputAllowed()) return null;
            bool close = virtualKey == 27;
            if (!close && virtualKey != 13 && virtualKey != _advanceKey) return null;
            return () =>
            {
                try
                {
                    _dispatch(() =>
                    {
                        if (!ReferenceEquals(frame, _current) || !_widget.Visible || !_inputAllowed()) return;
                        if (close) _widget.TryClose(); else _widget.TryAdvance();
                    });
                }
                catch (ObjectDisposedException) { }
                catch (InvalidOperationException) { }
            };
        }

        public void HandleTransportDisconnected()
        {
            long epoch = Interlocked.Increment(ref _transportEpoch);
            try { _dispatch(() =>
            {
                if (epoch != Interlocked.Read(ref _transportEpoch)) return;
                _current = null;
                _maxSequence = 0;
                _sentRevision = 0;
                _sceneImagePath = null;
                _widget.Reset();
            }); }
            catch (ObjectDisposedException) { }
            catch (InvalidOperationException) { }
        }

        internal static bool TryParse(JObject p, out NativeDialogueFrame frame, out long sequence, out bool hide)
        {
            frame = null; sequence = 0; hide = false;
            int version, revision, index, count;
            string request, scene, op;
            if (p == null || !Int(p, "version", 1, 1, out version)
                || !Text(p, "requestId", 32, out request) || (sequence = SequenceOf(request)) < 1
                || !Text(p, "sceneId", 128, out scene) || scene.Length == 0
                || !Text(p, "op", 4, out op) || (op != "hide" && op != "show")) return false;
            hide = op == "hide";
            frame = new NativeDialogueFrame { RequestId = request, SceneId = scene };
            if (hide) return true;
            string name, title, text, key, expression, kind, imageAction, imagePath;
            var portrait = p["portrait"] as JObject;
            if (!Int(p, "revision", 1, int.MaxValue, out revision)
                || !Int(p, "lineCount", 1, 4096, out count)
                || !Int(p, "lineIndex", 0, count - 1, out index)
                || !Text(p, "name", 256, out name) || !Text(p, "title", 256, out title)
                || !Text(p, "text", 32768, out text) || portrait == null
                || !Text(portrait, "key", 256, out key) || !Text(portrait, "expression", 80, out expression)
                || !Text(portrait, "kind", 8, out kind) || (kind != "static" && kind != "doll")
                || !Text(p, "imageAction", 5, out imageAction)
                || (imageAction != "keep" && imageAction != "show" && imageAction != "clear")) return false;
            imagePath = "";
            if (imageAction == "show" && (!Text(p, "imagePath", 512, out imagePath) || imagePath.Length == 0)) return false;
            if (kind == "doll" && !(portrait["appearance"] is JObject)) return false;
            frame.Revision = revision; frame.LineIndex = index; frame.LineCount = count;
            frame.Name = name; frame.Title = title; frame.Text = text;
            frame.PortraitKey = key; frame.Expression = expression; frame.IsDoll = kind == "doll";
            var normalizedAppearance = frame.IsDoll
                ? CF7Launcher.Guardian.Dialogue.DialoguePortraitService.NormalizeAppearance(
                    (JObject)portrait["appearance"]) : null;
            if (frame.IsDoll && normalizedAppearance == null) return false;
            frame.AppearanceIdentity = normalizedAppearance?.ToString(Formatting.None) ?? "";
            frame.ImageAction = imageAction; frame.ImagePath = imagePath;
            return true;
        }

        private static long SequenceOf(string request)
        {
            long value;
            if (request == null || !request.StartsWith("nd:", StringComparison.Ordinal)
                || !long.TryParse(request.Substring(3), NumberStyles.None, CultureInfo.InvariantCulture, out value)
                || value < 1 || request != "nd:" + value.ToString(CultureInfo.InvariantCulture)) return 0;
            return value;
        }

        private static bool Text(JObject p, string key, int max, out string value)
        {
            value = null;
            if (p[key]?.Type != JTokenType.String) return false;
            value = p[key].Value<string>();
            return value.Length <= max && value.IndexOf('\0') < 0;
        }

        private static bool Int(JObject p, string key, int min, int max, out int value)
        {
            value = 0;
            if (p[key]?.Type != JTokenType.Integer) return false;
            long number;
            if (!long.TryParse(p[key].ToString(), out number) || number < min || number > max) return false;
            value = (int)number; return true;
        }
    }
}
