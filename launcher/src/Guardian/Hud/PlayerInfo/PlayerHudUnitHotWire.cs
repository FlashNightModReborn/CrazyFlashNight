#nullable enable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using CF7Launcher.Guardian.Hud.Loot;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed record PlayerHudAlly(int Slot, long Id, long Generation, string Role, string Name,
    string Icon, IReadOnlyDictionary<string, string>? Doll, string PortraitKey,
    double Hp, double HpMax, double Shield, double ShieldMax, bool Down, bool Protected);
internal sealed record PlayerHudAllyRoster(PlayerHudAlly[] Rows, PlayerHudAlly[] Overflow);

internal sealed partial class PlayerHudState
{
    internal bool NeedsUnitSync { get; private set; }

    private static JObject DecodeJsonPacket(string encoded)
    {
        var json = StrictUtf8.GetString(Convert.FromBase64String(encoded));
        using var input = new StringReader(json);
        using var reader = new JsonTextReader(input) { MaxDepth = 12, DateParseHandling = DateParseHandling.None };
        var packet = JObject.Load(reader, new JsonLoadSettings { DuplicatePropertyNameHandling = DuplicatePropertyNameHandling.Error });
        if (reader.Read()) throw new FormatException("trailing_json");
        return packet;
    }

    internal const int OrdinaryAllySeats = 20;
    internal const int MaximumVisibleAllies = OrdinaryAllySeats + 64;
    internal const int MaximumOverflowAllies = 256;

    private static PlayerHudAllyRoster ReadAllies(JToken token)
    {
        var group = Object(token);
        Keys(group, "rows", "overflow");
        var identities = new HashSet<(long, long)>();
        var slots = new HashSet<int>();
        PlayerHudAlly[] ReadRows(string name)
        {
            int maximum = name == "rows" ? MaximumVisibleAllies : MaximumOverflowAllies;
            if (group[name] is not JArray rows || rows.Count > maximum) throw new FormatException("ally_rows");
            var result = new PlayerHudAlly[rows.Count];
            for (int i = 0; i < rows.Count; i++)
            {
                var row = Object(rows[i]);
                Keys(row, "slot", "id", "generation", "role", "name", "icon", "doll", "hp", "shield", "down", "protected");
                int slot = (int)Integer(row["slot"], -1, MaximumVisibleAllies - 1);
                long id = Integer(row["id"], 1, 1_000_000_000_000_000);
                long generation = Integer(row["generation"], 1, 1_000_000_000_000_000);
                bool keep = Boolean(row["protected"]);
                if (!identities.Add((generation, id)) || (name == "overflow" ? slot != -1 : slot < 0 || !slots.Add(slot) || (slot >= OrdinaryAllySeats && !keep)))
                    throw new FormatException("ally_slot_or_id");
                string role = Text(row["role"], 8), label = Text(row["name"], 192), icon = OptionalText(row["icon"], 128);
                if (role is not ("merc" or "pet" or "map") || label.Length == 0) throw new FormatException("ally_identity");
                var doll = row["doll"] is JObject ? ReadFocusDoll(row["doll"]!) : null;
                if (doll == null && row["doll"] != null && row["doll"]!.Type != JTokenType.Null) throw new FormatException("ally_doll");
                var hp = Numbers(row["hp"], 2); var shield = Numbers(row["shield"], 2);
                if (hp[1] <= 0 || shield[1] < 0) throw new FormatException("ally_resource");
                result[i] = new(slot,id,generation,role,label,icon,doll,doll == null ? icon : DollPortraitKey.Compute(doll),
                    hp[0],hp[1],shield[0],shield[1],Boolean(row["down"]),keep);
            }
            return result;
        }
        return new(ReadRows("rows"), ReadRows("overflow"));
    }

    private readonly HashSet<long> _hotSeen = new();
    private bool _focusJsonDirty, _alliesJsonDirty;

    private static long WireInteger(ReadOnlySpan<char> text, long min, long max)
    {
        if (!long.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out long number) ||
            number < min || number > max) throw new FormatException("hot_integer");
        return number;
    }

    private static long WireSignedInteger(ReadOnlySpan<char> text, long min, long max)
    {
        if (text.Length == 0 || text[0] == '+' ||
            !long.TryParse(text, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out long number) ||
            number < min || number > max) throw new FormatException("hot_integer");
        return number;
    }

    private static double WireDouble(ReadOnlySpan<char> text)
    {
        if (text.Length == 0 || text.Length > 32) throw new FormatException("hot_number");
        if (long.TryParse(text, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out long integer) &&
            integer >= -1_000_000_000_000_000 && integer <= 1_000_000_000_000_000) return integer;
        const NumberStyles style = NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint | NumberStyles.AllowExponent;
        if (!double.TryParse(text, style, CultureInfo.InvariantCulture, out double n) || !double.IsFinite(n) || Math.Abs(n) > 1e15)
            throw new FormatException("hot_number");
        return n;
    }

    private static JValue ToJsonNumber(double value) =>
        value == Math.Truncate(value) && value >= -1_000_000_000_000_000 && value <= 1_000_000_000_000_000
            ? new JValue((long)value)
            : new JValue(value);

    private static JValue WireNumber(string text) => ToJsonNumber(WireDouble(text.AsSpan()));

    private static bool TryNextToken(ref ReadOnlySpan<char> rest, char sep, out ReadOnlySpan<char> token)
    {
        int idx = rest.IndexOf(sep);
        if (idx < 0)
        {
            token = rest;
            rest = ReadOnlySpan<char>.Empty;
            return false;
        }
        token = rest.Slice(0, idx);
        rest = rest.Slice(idx + 1);
        return true;
    }

    private static int SplitRecordFields(ReadOnlySpan<char> record, Span<Range> ranges)
    {
        int count = 0;
        int start = 0;
        for (int i = 0; i <= record.Length; i++)
        {
            if (i == record.Length || record[i] == ',')
            {
                if (count >= ranges.Length) return -1;
                ranges[count++] = new Range(start, i);
                start = i + 1;
            }
        }
        return count;
    }

    private void SyncDirtyJsonShadow()
    {
        if (_focusJsonDirty)
        {
            _focusJsonDirty = false;
            if (Snapshot?.FocusTargets is { } targets && _groups.TryGetValue("focusTarget", out var ft) && ft is JArray fa)
            {
                int n = Math.Min(targets.Length, fa.Count);
                for (int i = 0; i < n; i++)
                {
                    if (fa[i] is not JObject row) continue;
                    var t = targets[i];
                    row["hp"] = new JArray(ToJsonNumber(t.Hp), ToJsonNumber(t.HpMax));
                    if (t.Hits == 0) row.Remove("hits");
                    else row["hits"] = new JValue((long)t.Hits);
                    bool hadExt = row["flags"] != null || t.ShieldMax > 0 || t.Shield > 0 || t.Poise >= 0 || t.Flags != 0 || t.HitSeq > 0;
                    if (hadExt)
                    {
                        row["shield"] = new JArray(ToJsonNumber(t.Shield), ToJsonNumber(t.ShieldMax));
                        row["poise"] = new JValue((long)t.Poise);
                        row["flags"] = new JValue((long)t.Flags);
                        if (t.HitSeq == 0) row.Remove("hitSeq");
                        else row["hitSeq"] = new JValue(t.HitSeq);
                    }
                }
            }
        }
        if (_alliesJsonDirty)
        {
            _alliesJsonDirty = false;
            if (Snapshot?.Allies is { } allies && _groups.TryGetValue("allies", out var al) && al is JObject ao)
            {
                SyncAllyArrayShadow(ao["rows"] as JArray, allies.Rows);
                SyncAllyArrayShadow(ao["overflow"] as JArray, allies.Overflow);
            }
        }
    }

    private static void SyncAllyArrayShadow(JArray? array, PlayerHudAlly[] items)
    {
        if (array == null) return;
        int n = Math.Min(items.Length, array.Count);
        for (int i = 0; i < n; i++)
        {
            if (array[i] is not JObject row) continue;
            var a = items[i];
            row["hp"] = new JArray(ToJsonNumber(a.Hp), ToJsonNumber(a.HpMax));
            row["shield"] = new JArray(ToJsonNumber(a.Shield), ToJsonNumber(a.ShieldMax));
            row["down"] = new JValue(a.Down);
        }
    }

    private bool ReceiveTypedHotPacket(string wire, long now)
    {
        if (wire.Length > 16384) throw new FormatException("hot_length");
        var span = wire.AsSpan();
        if (!TryNextToken(ref span, ';', out var headerSpan)) throw new FormatException("hot_rows");
        Span<Range> fields = stackalloc Range[12];
        if (SplitRecordFields(headerSpan, fields) != 3 || !headerSpan[fields[0]].SequenceEqual("~1".AsSpan()))
            throw new FormatException("hot_header");
        long epoch = WireInteger(headerSpan[fields[1]], 1, 1_000_000_000_000_000);
        long sequence = WireInteger(headerSpan[fields[2]], 1, 1_000_000_000_000_000);
        if (epoch < _epoch || (epoch == _epoch && sequence <= _sequence)) return false;
        if (NeedsUnitSync || epoch != _epoch || sequence != _sequence + 1 || Snapshot == null) throw new FormatException("hot_base");

        var previous = Snapshot;
        PlayerHudFocusTarget[]? focusEdits = null;
        PlayerHudAlly[]? visibleEdits = null, overflowEdits = null;
        _hotSeen.Clear();
        var changes = PlayerHudGroups.None;
        bool focusTouched = false, alliesTouched = false;
        int recordCount = 0;

        bool more = true;
        while (more)
        {
            more = TryNextToken(ref span, ';', out var rec);
            recordCount++;
            if (recordCount > 64) throw new FormatException("hot_rows");

            int fieldCount = SplitRecordFields(rec, fields);
            if (fieldCount < 6) throw new FormatException("hot_item");
            var kindSpan = rec[fields[0]];
            if (kindSpan.Length != 1) throw new FormatException("hot_item");
            char kind = kindSpan[0];
            bool focus = kind == 'f';
            if ((!focus && kind is not ('a' or 'o')) || (focus ? fieldCount is not (6 or 11) : fieldCount != 9))
                throw new FormatException("hot_item");

            int index = (int)WireInteger(rec[fields[1]], 0, int.MaxValue);
            long seenKey = ((long)kind << 32) | (uint)index;
            if (!_hotSeen.Add(seenKey)) throw new FormatException("hot_index");
            long id = WireInteger(rec[fields[2]], 1, 1_000_000_000_000_000);
            int h = focus ? 3 : 4;
            double hp = WireDouble(rec[fields[h]]);
            double hpMax = WireDouble(rec[fields[h + 1]]);
            if (hpMax <= 0) throw new FormatException("hot_hp_max");

            if (focus)
            {
                if (previous.FocusTargets == null || index >= previous.FocusTargets.Length || !_groups.ContainsKey("focusTarget"))
                    throw new FormatException("hot_index");
                var old = previous.FocusTargets[index];
                if (old.Id != id) throw new FormatException("hot_identity");
                int hits = (int)WireInteger(rec[fields[5]], 0, 999999);
                if (fieldCount == 11)
                {
                    double shCur = WireDouble(rec[fields[6]]);
                    double shMax = WireDouble(rec[fields[7]]);
                    if (shCur < 0 || shMax < 0) throw new FormatException("hot_shield");
                    int poise = (int)WireSignedInteger(rec[fields[8]], -1, 255);
                    int flags = (int)WireInteger(rec[fields[9]], 0, 15);
                    long hitSeq = WireInteger(rec[fields[10]], 0, 9007199254740991);
                    bool rowChanged = old.Hp != hp || old.HpMax != hpMax || old.Hits != hits
                        || old.Shield != shCur || old.ShieldMax != shMax || old.Poise != poise
                        || old.Flags != flags || old.HitSeq != hitSeq;
                    if (rowChanged)
                    {
                        focusEdits ??= (PlayerHudFocusTarget[])previous.FocusTargets.Clone();
                        focusEdits[index] = old with { Hp = hp, HpMax = hpMax, Hits = hits, Shield = shCur, ShieldMax = shMax, Poise = poise, Flags = flags, HitSeq = hitSeq };
                        changes |= PlayerHudGroups.Focus;
                        focusTouched = true;
                    }
                }
                else
                {
                    bool rowChanged = old.Hp != hp || old.HpMax != hpMax || old.Hits != hits;
                    if (rowChanged)
                    {
                        focusEdits ??= (PlayerHudFocusTarget[])previous.FocusTargets.Clone();
                        focusEdits[index] = old with { Hp = hp, HpMax = hpMax, Hits = hits };
                        changes |= PlayerHudGroups.Focus;
                        focusTouched = true;
                    }
                }
            }
            else
            {
                if (previous.Allies == null || !_groups.ContainsKey("allies")) throw new FormatException("hot_layout");
                bool overflow = kind == 'o';
                var source = overflow ? previous.Allies.Overflow : previous.Allies.Rows;
                if (index >= source.Length) throw new FormatException("hot_index");
                var old = source[index];
                if (old.Id != id || old.Generation != WireInteger(rec[fields[3]], 1, 1_000_000_000_000_000))
                    throw new FormatException("hot_identity");
                double shCur = WireDouble(rec[fields[6]]);
                double shMax = WireDouble(rec[fields[7]]);
                if (shMax < 0) throw new FormatException("hot_shield_max");
                bool down = WireInteger(rec[fields[8]], 0, 1) == 1;
                bool rowChanged = old.Hp != hp || old.HpMax != hpMax || old.Shield != shCur || old.ShieldMax != shMax || old.Down != down;
                if (rowChanged)
                {
                    var copy = overflow ? (overflowEdits ??= (PlayerHudAlly[])source.Clone()) : (visibleEdits ??= (PlayerHudAlly[])source.Clone());
                    copy[index] = old with { Hp = hp, HpMax = hpMax, Shield = shCur, ShieldMax = shMax, Down = down };
                    changes |= PlayerHudGroups.Allies;
                    alliesTouched = true;
                }
            }
        }

        var targets = focusEdits ?? previous.FocusTargets;
        var allies = visibleEdits == null && overflowEdits == null ? previous.Allies
            : new PlayerHudAllyRoster(visibleEdits ?? previous.Allies!.Rows, overflowEdits ?? previous.Allies!.Overflow);
        var next = new PlayerHudSnapshot(epoch, sequence, previous.Vitals, previous.Combat, previous.Loadout,
            previous.Cooldowns, previous.Buffs, previous.Resources, previous.ColdSkills,
            focusEdits == null ? previous.FocusTarget : focusEdits[0], targets, allies) { BuffCards = previous.BuffCards };
        if (focusTouched) _focusJsonDirty = true;
        if (alliesTouched) _alliesJsonDirty = true;
        Snapshot = next;
        _sequence = sequence;
        LastReceivedMilliseconds = now;
        AcceptedPackets++;
        ReceivedBytes += wire.Length;
        if (changes != PlayerHudGroups.None) NotifyChanged(changes);
        return true;
    }

    // Apply every numeric edit to privately staged JSON groups. The normal receiver
    // then validates cold and hot data through exactly the same atomic adoption path.
    private JObject? ExpandHotPacket(string wire)
    {
        SyncDirtyJsonShadow();
        if (!ReadHotHeader(wire, out var rows, out var epoch, out var sequence)) return null;

        var edits = new JObject();
        var seen = new HashSet<(string, int)>();
        for (int i = 1; i < rows.Length; i++)
        {
            var fields = rows[i].Split(',');
            string kind = fields[0];
            bool focus = kind == "f";
            if ((!focus && kind is not ("a" or "o")) || (focus ? fields.Length is not (6 or 11) : fields.Length != 9))
                throw new FormatException("hot_item");
            var key = focus ? "focusTarget" : "allies";
            if (edits[key] == null)
            {
                if (!_groups.TryGetValue(key, out var source)) throw new FormatException("hot_layout");
                edits[key] = source.DeepClone();
            }
            JArray? items = focus ? edits[key] as JArray : (edits[key] as JObject)?[kind == "a" ? "rows" : "overflow"] as JArray;
            int index = (int)WireInteger(fields[1],0,int.MaxValue);
            if (items == null || index >= items.Count || !seen.Add((kind,index))) throw new FormatException("hot_index");
            var item = Object(items[index]);
            if (item.Value<long>("id") != WireInteger(fields[2],1,1_000_000_000_000_000)) throw new FormatException("hot_identity");
            if (focus)
            {
                item["hp"] = new JArray(WireNumber(fields[3]), WireNumber(fields[4]));
                long hits = WireInteger(fields[5],0,999999);
                if (hits == 0) item.Remove("hits"); else item["hits"] = hits;
                if (fields.Length == 11)
                {
                    var shCurVal = WireNumber(fields[6]);
                    var shMaxVal = WireNumber(fields[7]);
                    if (shCurVal.Value<double>() < 0 || shMaxVal.Value<double>() < 0) throw new FormatException("hot_shield");
                    item["shield"] = new JArray(shCurVal, shMaxVal);
                    item["poise"] = WireSignedInteger(fields[8], -1, 255);
                    item["flags"] = WireInteger(fields[9], 0, 15);
                    long hitSeq = WireInteger(fields[10], 0, 9007199254740991);
                    if (hitSeq == 0) item.Remove("hitSeq"); else item["hitSeq"] = hitSeq;
                }
            }
            else
            {
                if (item.Value<long>("generation") != WireInteger(fields[3],1,1_000_000_000_000_000)) throw new FormatException("hot_generation");
                item["hp"] = new JArray(WireNumber(fields[4]), WireNumber(fields[5]));
                item["shield"] = new JArray(WireNumber(fields[6]), WireNumber(fields[7]));
                item["down"] = WireInteger(fields[8],0,1) == 1;
            }
        }
        return new JObject { ["v"]=1, ["epoch"]=epoch, ["seq"]=sequence, ["full"]=false, ["visible"]=true, ["groups"]=edits };
    }

    private bool ReadHotHeader(string wire, out string[] rows, out long epoch, out long sequence)
    {
        if (wire.Length > 16384) throw new FormatException("hot_length");
        rows = wire.Split(';');
        if (rows.Length is < 2 or > 65) throw new FormatException("hot_rows");
        var header = rows[0].Split(',');
        if (header.Length != 3 || header[0] != "~1") throw new FormatException("hot_header");
        epoch = WireInteger(header[1],1,1_000_000_000_000_000);
        sequence = WireInteger(header[2],1,1_000_000_000_000_000);
        if (epoch < _epoch || (epoch == _epoch && sequence <= _sequence)) return false;
        if (NeedsUnitSync || epoch != _epoch || sequence != _sequence + 1 || Snapshot == null) throw new FormatException("hot_base");
        return true;
    }
}
