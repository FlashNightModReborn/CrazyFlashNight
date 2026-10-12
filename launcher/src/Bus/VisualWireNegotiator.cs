using System;
using System.Linq;
using System.Globalization;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Bus;

// Format negotiation has no authority over projectile ownership or gameplay.
// This candidate offers Q1-R only; scene poses retain the existing wire.
internal sealed class VisualWireNegotiator
{
    private readonly object _gate = new();
    private readonly Func<string, int, bool> _send;
    private readonly bool _offerQ1;
    private int _generation, _latestGeneration;
    private string _token, _selected, _commit;
    private bool _q1Active;
    internal int Rejected { get; private set; }

    internal VisualWireNegotiator(bool offerQ1, Func<string, int, bool> send)
    { _offerQ1 = offerQ1; _send = send; }

    internal void Ready(int generation)
    {
        string offer;
        lock (_gate)
        {
            if (generation < 1 || generation <= _latestGeneration) return;
            _generation = _latestGeneration = generation;
            _token = Guid.NewGuid().ToString("N");
            _selected = _commit = null; _q1Active = false;
            offer = new JObject {
                ["task"] = "visual_wire_offer", ["version"] = 1, ["token"] = _token, ["offerId"] = 1,
                ["channels"] = new JObject { ["f5"] = _offerQ1 ? new JArray("q1", "legacy") : new JArray("legacy"),
                    ["scenePose"] = new JArray("legacy") },
                ["f5Quant"] = new JObject { ["profile"] = "q64-safe-v1", ["allowed"] = false,
                    ["denominator"] = 64, ["absXY"] = 8192, ["maxCameraScale"] = 4,
                    ["maxCameraOffset"] = 8192, ["maxAbsScalePercent"] = 400,
                    ["maxCatalogRadius"] = 128, ["maxOutputScale"] = 4 }
            }.ToString(Formatting.None);
        }
        _send(offer + "\0", generation);
    }

    internal void Disconnected(int generation)
    {
        lock (_gate)
        {
            if (generation != _generation) return;
            _generation = 0; _token = _selected = _commit = null; _q1Active = false;
        }
    }

    internal string Select(JObject message, int generation)
    {
        lock (_gate)
        {
            if (generation < 1 || generation != _generation) return null;
            bool valid = Exact(message, "task", "version", "token", "offerId", "channels", "f5QuantProfile")
                && Encoding.UTF8.GetByteCount(message.ToString(Formatting.None)) <= 4096
                && Integer(message["version"], 1) && Integer(message["offerId"], 1)
                && message["task"]?.Type == JTokenType.String && (string)message["task"] == "visual_wire_select"
                && message["token"]?.Type == JTokenType.String && (string)message["token"] == _token
                && message["f5QuantProfile"]?.Type == JTokenType.String && (string)message["f5QuantProfile"] == "none"
                && message["channels"] is JObject channels && Exact(channels, "f5", "scenePose")
                && channels["f5"]?.Type == JTokenType.String
                && channels["scenePose"]?.Type == JTokenType.String && (string)channels["scenePose"] == "legacy"
                && ((string)channels["f5"] == "legacy" || (_offerQ1 && (string)channels["f5"] == "q1"));
            if (!valid) { Rejected++; return null; }
            string selected = (string)message["channels"]["f5"];
            if (_selected != null)
            {
                if (_selected != selected) { Rejected++; return null; }
                return _commit;
            }
            // Set decoder admission before the router sends this response.
            _selected = selected;
            _commit = new JObject { ["task"] = "visual_wire_commit", ["version"] = 1,
                ["token"] = _token, ["offerId"] = 1,
                ["channels"] = new JObject { ["f5"] = selected, ["scenePose"] = "legacy" },
                ["f5QuantProfile"] = "none", ["qAllowed"] = false }.ToString(Formatting.None);
            return _commit;
        }
    }

    internal bool CanDecodeQ1(int generation, int offerId)
    { lock (_gate) return generation == _generation && generation > 0 && offerId == 1 && _selected == "q1"; }

    internal bool LegacyRetired(int generation)
    { lock (_gate) return generation == _generation && _q1Active; }

    internal bool ActivateQ1(int generation)
    {
        lock (_gate)
        {
            if (generation != _generation || generation < 1 || _selected != "q1") return false;
            _q1Active = true; return true;
        }
    }

    internal static bool Exact(JObject value, params string[] names)
        => value != null && value.Count == names.Length && names.All(name => value.Property(name) != null);
    private static bool Integer(JToken value, int expected)
        => value?.Type == JTokenType.Integer
            && long.TryParse(value.ToString(Formatting.None), NumberStyles.None, CultureInfo.InvariantCulture, out long number)
            && number == expected;
}
