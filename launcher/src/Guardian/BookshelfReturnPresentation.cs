using System;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    // The existing bookshelf stays opaque while AS2 replaces the player below it.
    // Admission comes only from the validated return receipt, never from Web intent.
    internal sealed class BookshelfReturnPresentation
    {
        private readonly Func<string, bool> _owns;
        private readonly Func<bool> _releasePause, _assertPause;
        private readonly Func<string, bool> _post;
        private readonly Func<DateTime> _now;
        private readonly Func<bool> _visible;
        private readonly Action _restoreOrder;
        private string _instance;
        private JObject _projection;
        private string _posted;
        private DateTime _retryAt;
        private bool _acknowledged;
        private bool _released, _sceneComplete, _sceneRetired, _terminal;
        internal BookshelfReturnPresentation(Func<string, bool> owns, Func<bool> releasePause,
            Func<bool> assertPause, Func<string, bool> post, Func<bool> visible, Action restoreOrder = null, Func<DateTime> now = null)
        { _owns = owns; _releasePause = releasePause; _assertPause = assertPause; _post = post; _visible = visible; _restoreOrder = restoreOrder; _now = now ?? (() => DateTime.UtcNow); }
        internal string Instance => _instance != null && _owns(_instance) ? _instance : null;
        internal bool Active => Instance != null;
        internal bool Loading => Active && !_sceneRetired;
        internal bool CanPresent => Active && _visible();
        internal void RestoreOrder() { if (CanPresent) _restoreOrder?.Invoke(); }
        internal void RetryPauseRestore() { if (_sceneRetired && !_sceneComplete) CompleteScene(); }
        internal void Observe(string instance, JObject receipt)
        {
            if (!_owns(instance) || receipt.Value<string>("kind") != "return") return;
            string phase = receipt.Value<string>("phase");
            if (phase == "switching")
            {
                if (_instance != instance) { _instance = instance; _projection = null; _posted = null; _retryAt = DateTime.MinValue; _acknowledged = false; _released = _sceneComplete = _sceneRetired = _terminal = false; }
                if (_sceneRetired) CompleteScene();
                else if (!_released && !_sceneComplete) _released = _releasePause();
            }
            else if (phase is "applied" or "expired" && _instance == instance)
            {
                _terminal = true;
                if (_sceneRetired) CompleteScene();
                // Expiry can precede the fallback scene's final frame.
                if (_sceneComplete) _instance = null;
            }
        }
        internal bool Post(JObject projection)
        {
            string instance = Instance;
            if (instance == null || !CanPresent) return false;
            var copy = (JObject)projection.DeepClone();
            copy["type"] = "bookshelf_transition"; copy["panelInstanceId"] = instance;
            string serialized = copy.ToString(Newtonsoft.Json.Formatting.None);
            DateTime now = _now();
            if (serialized == _posted && (_acknowledged || now < _retryAt)) return false;
            if (!_post(serialized)) return false;
            _projection = (JObject)projection.DeepClone();
            _posted = serialized; _acknowledged = false; _retryAt = now.AddMilliseconds(750);
            LogManager.Log("event=bookshelf_transition_post id=" + projection.Value<string>("requestId")
                + " revision=" + projection.Value<int>("revision") + " phase=" + projection.Value<string>("phase"));
            return true;
        }
        internal void Confirm(JObject receipt)
        {
            if (!Active || _projection == null || receipt == null) return;
            foreach (string key in new[] { "requestId", "revision", "generation" })
                if (!JToken.DeepEquals(receipt[key], _projection[key])) return;
            string kind = receipt.Value<string>("kind"), phase = _projection.Value<string>("phase");
            if (kind == "covered" && (phase == "cover" || phase == "loading")
                || kind == "revealed" && phase == "reveal") _acknowledged = true;
        }
        internal void CompleteScene()
        {
            if (!Active || _sceneComplete) return;
            _sceneRetired = true;
            // Loading's last frame must retire before the ordinary Web pause returns.
            if (_released && !_assertPause()) return;
            _released = false;
            if (_projection != null && !_post(new JObject { ["type"] = "bookshelf_transition_complete",
                ["panelInstanceId"] = _instance, ["requestId"] = _projection["requestId"],
                ["revision"] = _projection["revision"], ["generation"] = _projection["generation"]
            }.ToString(Newtonsoft.Json.Formatting.None))) return;
            _sceneComplete = true;
            if (_terminal) _instance = null;
        }
    }
}
