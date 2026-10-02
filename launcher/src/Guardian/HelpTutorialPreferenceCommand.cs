using System;
using System.Linq;
using System.Text.RegularExpressions;
using CF7Launcher.Config;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    // The help endpoint can only turn off automatic tutorial popups. It cannot
    // call settings RPCs, change another preference, or access game state.
    internal sealed class HelpTutorialPreferenceCommand
    {
        private readonly UserPrefs _prefs;
        private readonly Func<bool> _save;
        private string _instance, _callId;
        private JObject _result;
        private static readonly Regex Opaque = new("^[A-Za-z0-9._~-]{1,160}\\z");

        internal HelpTutorialPreferenceCommand(UserPrefs prefs, Func<bool> save)
        {
            _prefs = prefs ?? throw new ArgumentNullException(nameof(prefs));
            _save = save ?? throw new ArgumentNullException(nameof(save));
        }

        internal JObject Handle(JObject request, string activeInstance)
        {
            string[] fields = { "type", "cmd", "version", "callId", "panelInstanceId" };
            if (request == null || request.Count != fields.Length || fields.Any(f => !request.ContainsKey(f))
                || request["type"]?.Type != JTokenType.String || request.Value<string>("type") != "tutorial_preference"
                || request["cmd"]?.Type != JTokenType.String || request.Value<string>("cmd") != "disable_auto_open"
                || request["version"]?.Type != JTokenType.Integer || request["version"].ToString() != "1"
                || request["callId"]?.Type != JTokenType.String || !Opaque.IsMatch(request.Value<string>("callId"))
                || request["panelInstanceId"]?.Type != JTokenType.String || !Opaque.IsMatch(request.Value<string>("panelInstanceId"))) return null;
            string instance = request.Value<string>("panelInstanceId"), call = request.Value<string>("callId");
            if (string.IsNullOrEmpty(activeInstance) || instance != activeInstance)
                return Result(instance, call, false, "panel_instance_expired");
            if (_instance == instance && _callId == call) return (JObject)_result.DeepClone();

            bool previous = _prefs.TutorialsAutoOpen, saved = !previous;
            if (previous)
            {
                _prefs.TutorialsAutoOpen = false;
                try { saved = _save(); } catch { saved = false; }
                if (!saved) _prefs.TutorialsAutoOpen = previous;
            }
            _instance = instance; _callId = call;
            _result = Result(instance, call, saved, saved ? null : "save_failed");
            return (JObject)_result.DeepClone();
        }

        private JObject Result(string instance, string call, bool ok, string error) => new()
        {
            ["type"] = "tutorial_preference_result", ["version"] = 1,
            ["panelInstanceId"] = instance, ["callId"] = call, ["ok"] = ok,
            ["tutorialsAutoOpen"] = _prefs.TutorialsAutoOpen, ["error"] = error
        };

        internal static bool IsResultFor(JObject message, string instance)
        {
            string[] fields = { "type", "version", "panelInstanceId", "callId", "ok", "tutorialsAutoOpen", "error" };
            return message != null && !string.IsNullOrEmpty(instance) && message.Count == fields.Length
                && fields.All(message.ContainsKey) && message["type"]?.Type == JTokenType.String
                && message.Value<string>("type") == "tutorial_preference_result"
                && message["version"]?.Type == JTokenType.Integer && message["version"].ToString() == "1"
                && message["panelInstanceId"]?.Type == JTokenType.String && message.Value<string>("panelInstanceId") == instance
                && message["callId"]?.Type == JTokenType.String && Opaque.IsMatch(message.Value<string>("callId"))
                && message["ok"]?.Type == JTokenType.Boolean && message["tutorialsAutoOpen"]?.Type == JTokenType.Boolean
                && message["error"]?.Type is JTokenType.String or JTokenType.Null;
        }
    }
}
