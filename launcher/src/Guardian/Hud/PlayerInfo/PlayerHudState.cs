#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed record PlayerHudVitals(double Hp, double HpMax, double Mp, double MpMax,
    double Shield, double ShieldMax, bool ShieldPresent, double Poise,
    double Experience, double ExperienceStart, double ExperienceEnd, int Level,
    string Name, double SkillPoints, bool Paused, bool Decorations, bool ShieldReady, PlayerHudPoise? PoiseDetail = null);
internal sealed record PlayerHudPoise(double Threshold, bool HasStaggerBand, string Phase);
internal sealed record PlayerHudSkill(int Slot, string Key, string Icon, string Hotkey,
    int Level, bool Equipped, bool WriteBlocked);
internal sealed record PlayerHudDrug(int Slot, string Name, string Icon, string Hotkey, double Count);
internal sealed record PlayerHudLoadout(long Revision, long DrugRevision, int Bank,
    string SwitchKey, PlayerHudSkill[] Skills, PlayerHudDrug[] Drugs);
internal sealed record PlayerHudCombat(string Mode, string[] Ammo, bool WeaponVisible,
    string WeaponName, string WeaponKey, double WeaponMp, double WeaponCooldown);
internal readonly record struct PlayerHudCooldown(bool Ready, double Step, double Total)
{
    internal double Fraction => Ready ? 1 : Total > 0 ? Math.Clamp(Step / Total, 0, 1) : 0;
}
internal sealed record PlayerHudBuff(string Id, bool Timed, double Total, double Remaining);
internal sealed record PlayerHudSnapshot(long Epoch, long Sequence, PlayerHudVitals Vitals,
    PlayerHudCombat Combat, PlayerHudLoadout Loadout, PlayerHudCooldown[] Cooldowns, PlayerHudBuff[] Buffs);
internal sealed record PlayerHudActionResult(string ActionId, bool Success, string Error, bool Changed);

/// <summary>One atomic adoption point. Missing groups retain data only inside an established epoch.</summary>
internal sealed class PlayerHudState
{
    internal const int MaximumEncodedLength = 131072;
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    private readonly Dictionary<string, JToken> _groups = new(StringComparer.Ordinal);
    private long _epoch;
    private long _sequence;
    internal PlayerHudSnapshot? Snapshot { get; private set; }
    internal event Action? Changed;
    internal event Action<PlayerHudActionResult>? ActionResult;
    internal long LastReceivedMilliseconds { get; private set; }
    internal long AcceptedPackets { get; private set; }
    internal long RejectedPackets { get; private set; }
    internal long ReceivedBytes { get; private set; }

    internal void Disconnect()
    {
        _groups.Clear(); _epoch = 0; _sequence = 0; Snapshot = null;
        Changed?.Invoke();
    }

    internal bool Receive(string encoded, long now)
    {
        try
        {
            if (encoded.Length == 0 || encoded.Length > MaximumEncodedLength) throw new FormatException("payload_size");
            var json = StrictUtf8.GetString(Convert.FromBase64String(encoded));
            using var input = new StringReader(json);
            using var reader = new JsonTextReader(input) { MaxDepth = 12, DateParseHandling = DateParseHandling.None };
            var packet = JObject.Load(reader, new JsonLoadSettings { DuplicatePropertyNameHandling = DuplicatePropertyNameHandling.Error });
            if (reader.Read()) throw new FormatException("trailing_json");
            if (Integer(packet["v"], 1, 1) != 1) throw new FormatException("version");
            if (packet["result"] is JObject result)
            {
                Keys(packet, "v", "result");
                Keys(result, "actionId", "success", "error", "changed");
                var id = Text(result["actionId"], 96);
                if (!id.StartsWith("ph:", StringComparison.Ordinal)) throw new FormatException("action_id");
                var success = Boolean(result["success"]);
                var error = Text(result["error"], 64);
                if ((success && error.Length != 0) || (!success && error.Length == 0)) throw new FormatException("malformed_success");
                var changed = Boolean(result["changed"]);
                ActionResult?.Invoke(new(id, success, error, changed));
                return true;
            }
            Keys(packet, "v", "epoch", "seq", "full", "visible", "groups");
            var epoch = Integer(packet["epoch"], 1, 9007199254740991);
            var sequence = Integer(packet["seq"], 1, 9007199254740991);
            var full = Boolean(packet["full"]);
            var visible = Boolean(packet["visible"]);
            if (epoch < _epoch || (epoch == _epoch && sequence <= _sequence)) return false;
            if (epoch != _epoch && !full) return false;
            if (!visible)
            {
                if (!full || packet["groups"] != null) throw new FormatException("invalid_clear");
                _epoch = epoch; _sequence = sequence; _groups.Clear(); Snapshot = null;
                LastReceivedMilliseconds = now; AcceptedPackets++; ReceivedBytes += encoded.Length;
                Changed?.Invoke(); return true;
            }
            var incoming = Object(packet["groups"]);
            Keys(incoming, "vitals", "combat", "loadout", "cooldowns", "buffs");
            var candidate = full ? new Dictionary<string, JToken>(StringComparer.Ordinal)
                : new Dictionary<string, JToken>(_groups, StringComparer.Ordinal);
            foreach (var property in incoming.Properties()) candidate[property.Name] = property.Value;
            if (candidate.Count != 5) throw new FormatException("incomplete_full_state");
            // Parse every group before changing any current field.
            var next = new PlayerHudSnapshot(epoch, sequence,
                ReadVitals(candidate["vitals"]), ReadCombat(candidate["combat"]), ReadLoadout(candidate["loadout"]),
                ReadCooldowns(candidate["cooldowns"]), ReadBuffs(candidate["buffs"]));
            var dirty = epoch != _epoch || Snapshot == null || candidate.Any(p => !_groups.TryGetValue(p.Key, out var old) || !JToken.DeepEquals(old, p.Value));
            _groups.Clear(); foreach (var pair in candidate) _groups.Add(pair.Key, pair.Value);
            Snapshot = next; _epoch = epoch; _sequence = sequence;
            LastReceivedMilliseconds = now; AcceptedPackets++; ReceivedBytes += encoded.Length;
            if (dirty) Changed?.Invoke();
            return true;
        }
        catch (Exception ex) when (ex is JsonException or FormatException or InvalidCastException or OverflowException or DecoderFallbackException)
        {
            RejectedPackets++; return false;
        }
    }

    internal static PlayerHudVitals ReadVitals(JToken token)
    {
        var o = Object(token);
        Keys(o, "hp", "mp", "shield", "shieldPresent", "shieldReady", "poise", "poiseDetail", "experience", "level", "name", "sp", "paused", "decorations");
        var hp = Numbers(o["hp"], 2); var mp = Numbers(o["mp"], 2);
        var shield = Numbers(o["shield"], 2); var xp = Numbers(o["experience"], 3);
        return new(hp[0], hp[1], mp[0], mp[1], shield[0], shield[1], Boolean(o["shieldPresent"]),
            Number(o["poise"]), xp[0], xp[1], xp[2], (int)Integer(o["level"], 0, 99999),
            Text(o["name"], 192), Number(o["sp"]), Boolean(o["paused"]), Boolean(o["decorations"]), Boolean(o["shieldReady"]),
            o["poiseDetail"] == null ? null : ReadPoise(o["poiseDetail"]!));
    }
    private static PlayerHudPoise ReadPoise(JToken token)
    {
        var o = Object(token); Keys(o, "threshold", "hasStaggerBand", "phase");
        var threshold = Number(o["threshold"]); var hasBand = Boolean(o["hasStaggerBand"]); var phase = Text(o["phase"], 16);
        if (threshold < 0 || threshold > 1 || (!hasBand && threshold != 0) ||
            phase is not ("buffer" or "stagger" or "break" or "rigid" or "air" or "down" or "unavailable"))
            throw new FormatException("poise_detail");
        return new(threshold, hasBand, phase);
    }

    private static PlayerHudCombat ReadCombat(JToken token)
    {
        var o = Object(token); Keys(o, "mode", "ammo", "weapon");
        var mode = Text(o["mode"], 32);
        if (!new[] { "", "手枪", "手枪2", "长枪", "兵器", "手雷", "空手", "双枪", "长枪副武器" }.Contains(mode)) throw new FormatException("mode");
        var ammo = Array(o["ammo"], 4).Select(t => Text(t, 64)).ToArray();
        var weapon = Object(o["weapon"]); Keys(weapon, "visible", "name", "mp", "cooldownMs", "key");
        return new(mode, ammo, Boolean(weapon["visible"]), Text(weapon["name"], 128), Text(weapon["key"], 32),
            Number(weapon["mp"]), Number(weapon["cooldownMs"]));
    }

    private static PlayerHudLoadout ReadLoadout(JToken token)
    {
        var o = Object(token); Keys(o, "revision", "skills", "drugRevision", "bank", "drugs", "switchKey");
        var revision = Integer(o["revision"], 0, 9007199254740991);
        var drugRevision = Integer(o["drugRevision"], 0, 9007199254740991);
        var bank = (int)Integer(o["bank"], 0, 1);
        var skills = Array(o["skills"], 12).Select((t, index) =>
        {
            var s = Object(t); Keys(s, "slot", "equipped", "skillKey", "keyLabel", "stateHealth", "writeBlocked", "level", "iconKey", "mp", "cooldownMs");
            if (Integer(s["slot"], 1, 12) != index + 1) throw new FormatException("skill_slot");
            var equipped = Boolean(s["equipped"]);
            var key = OptionalText(s["skillKey"], 128); var icon = OptionalText(s["iconKey"], 128);
            var level = s["level"] == null || s["level"]!.Type == JTokenType.Null ? 0 : (int)Integer(s["level"], 0, 9999);
            if (equipped && (key.Length == 0 || icon.Length == 0 || level == 0)) throw new FormatException("equipped_skill");
            return new PlayerHudSkill(index + 1, key, icon, Text(s["keyLabel"], 32), level, equipped, Boolean(s["writeBlocked"]));
        }).ToArray();
        var drugs = Array(o["drugs"], 4).Select((t, index) =>
        {
            var d = Object(t); Keys(d, "slot", "name", "icon", "count", "key");
            if (Integer(d["slot"], 0, 7) != bank * 4 + index) throw new FormatException("drug_slot");
            var count = Number(d["count"]); if (count < 0) throw new FormatException("drug_count");
            return new PlayerHudDrug(bank * 4 + index, Text(d["name"], 128), Text(d["icon"], 128), Text(d["key"], 32), count);
        }).ToArray();
        return new(revision, drugRevision, bank, Text(o["switchKey"], 32), skills, drugs);
    }

    private static PlayerHudCooldown[] ReadCooldowns(JToken token) => Array(token, 18).Select(t =>
    {
        var values = Numbers(t, 3);
        if ((values[0] != 0 && values[0] != 1) || values[1] < 0 || values[2] < 0 || (values[0] == 0 && values[2] <= 0)) throw new FormatException("cooldown");
        return new PlayerHudCooldown(values[0] == 1, values[1], values[2]);
    }).ToArray();

    private static PlayerHudBuff[] ReadBuffs(JToken token)
    {
        if (token is not JArray rows || rows.Count > 256) throw new FormatException("buff_count");
        var ids = new HashSet<string>(StringComparer.Ordinal);
        return rows.Select(t =>
        {
            var b = Object(t); Keys(b, "id", "timed", "total", "remaining");
            var id = Text(b["id"], 96); if (id.Length == 0 || !ids.Add(id)) throw new FormatException("buff_id");
            var total = Number(b["total"]); var remain = Number(b["remaining"]);
            if (total < 0 || remain < 0) throw new FormatException("buff_timer");
            return new PlayerHudBuff(id, Boolean(b["timed"]), total, remain);
        }).ToArray();
    }

    private static JObject Object(JToken? token) => token as JObject ?? throw new FormatException("object");
    private static JArray Array(JToken? token, int count) => token is JArray a && a.Count == count ? a : throw new FormatException("array_count");
    private static double[] Numbers(JToken? token, int count) => Array(token, count).Select(Number).ToArray();
    private static double Number(JToken? token)
    {
        if (token == null || (token.Type != JTokenType.Integer && token.Type != JTokenType.Float)) throw new FormatException("number");
        var value = token.Value<double>();
        return double.IsFinite(value) && Math.Abs(value) <= 1e15 ? value : throw new FormatException("finite_number");
    }
    private static long Integer(JToken? token, long min, long max)
    {
        var n = Number(token); return n >= min && n <= max && n == Math.Floor(n) ? (long)n : throw new FormatException("integer");
    }
    private static bool Boolean(JToken? token) => token?.Type == JTokenType.Boolean ? token.Value<bool>() : throw new FormatException("boolean");
    private static string OptionalText(JToken? token, int max) => token == null || token.Type == JTokenType.Null ? "" : Text(token, max);
    private static string Text(JToken? token, int max)
    {
        if (token?.Type != JTokenType.String) throw new FormatException("string");
        var text = token.Value<string>()!; if (text.Length > max) throw new FormatException("string_length");
        for (var i = 0; i < text.Length; i++)
        {
            if (char.IsHighSurrogate(text[i])) { if (++i >= text.Length || !char.IsLowSurrogate(text[i])) throw new FormatException("surrogate"); }
            else if (char.IsLowSurrogate(text[i]) || text[i] == '\0') throw new FormatException("surrogate");
        }
        return text;
    }
    private static void Keys(JObject value, params string[] names)
    {
        foreach (var p in value.Properties()) if (!names.Contains(p.Name, StringComparer.Ordinal)) throw new FormatException("unknown_field");
    }
}
