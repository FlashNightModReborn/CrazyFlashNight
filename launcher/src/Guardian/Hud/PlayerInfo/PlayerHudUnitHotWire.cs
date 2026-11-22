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

    private static long WireInteger(string text, long min, long max)
    {
        if (!long.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out long number) ||
            number < min || number > max) throw new FormatException("hot_integer");
        return number;
    }

    private static JValue WireNumber(string text)
    {
        if (text.Length == 0 || text.Length > 32) throw new FormatException("hot_number");
        if (long.TryParse(text, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out long integer) &&
            integer >= -1_000_000_000_000_000 && integer <= 1_000_000_000_000_000) return new JValue(integer);
        const NumberStyles style = NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint | NumberStyles.AllowExponent;
        if (!double.TryParse(text,style,CultureInfo.InvariantCulture,out double n) || !double.IsFinite(n) || Math.Abs(n) > 1e15)
            throw new FormatException("hot_number");
        return new JValue(n);
    }

    // A row's numeric JSON leaves are prepared before commit. Both the typed snapshot
    // and the retained JSON comparison base must see the same accepted sequence.
    private readonly record struct HotEdit(JObject Row, JArray Hp, JArray? Shield, JValue? Flag, bool Focus)
    {
        internal bool Changed => !JToken.DeepEquals(Row["hp"], Hp) || (Focus
            ? !JToken.DeepEquals(Row["hits"], Flag)
            : !JToken.DeepEquals(Row["shield"], Shield) || !JToken.DeepEquals(Row["down"], Flag));

        internal void Commit()
        {
            Row["hp"] = Hp;
            if (Focus)
            {
                if (Flag == null) Row.Remove("hits");
                else Row["hits"] = Flag;
            }
            else
            {
                Row["shield"] = Shield;
                Row["down"] = Flag;
            }
        }
    }

    private bool ReceiveTypedHotPacket(string wire, long now)
    {
        if (!ReadHotHeader(wire, out var records, out var epoch, out var sequence)) return false;
        var previous = Snapshot!;
        PlayerHudFocusTarget[]? focusEdits = null;
        PlayerHudAlly[]? visibleEdits = null, overflowEdits = null;
        var edits = new HotEdit[records.Length - 1];
        var seen = new HashSet<(string, int)>();
        var changes = PlayerHudGroups.None;
        for (int i = 0; i < edits.Length; i++)
        {
            var fields = records[i + 1].Split(',');
            var kind = fields[0];
            bool focus = kind == "f";
            if ((!focus && kind is not ("a" or "o")) || fields.Length != (focus ? 6 : 9)) throw new FormatException("hot_item");
            if (!_groups.TryGetValue(focus ? "focusTarget" : "allies", out var group)) throw new FormatException("hot_layout");
            var rows = focus ? group as JArray : (group as JObject)?[kind == "a" ? "rows" : "overflow"] as JArray;
            int index = (int)WireInteger(fields[1], 0, int.MaxValue);
            if (rows == null || index >= rows.Count || !seen.Add((kind, index))) throw new FormatException("hot_index");
            var row = Object(rows[index]);
            long id = WireInteger(fields[2], 1, 1_000_000_000_000_000);
            int h = focus ? 3 : 4;
            var current = WireNumber(fields[h]);
            var maximum = WireNumber(fields[h + 1]);
            double hp = current.Value<double>(), hpMax = maximum.Value<double>();
            if (hpMax <= 0) throw new FormatException("hot_hp_max");
            var hpJson = new JArray(current, maximum);
            if (focus)
            {
                var old = previous.FocusTargets![index];
                if (old.Id != id) throw new FormatException("hot_identity");
                int hits = (int)WireInteger(fields[5], 0, 999999);
                focusEdits ??= (PlayerHudFocusTarget[])previous.FocusTargets.Clone();
                focusEdits[index] = old with { Hp = hp, HpMax = hpMax, Hits = hits };
                edits[i] = new(row, hpJson, null, hits == 0 ? null : new JValue((long)hits), true);
            }
            else
            {
                bool overflow = kind == "o";
                var source = overflow ? previous.Allies!.Overflow : previous.Allies!.Rows;
                var old = source[index];
                if (old.Id != id || old.Generation != WireInteger(fields[3], 1, 1_000_000_000_000_000)) throw new FormatException("hot_identity");
                var shield = WireNumber(fields[6]);
                var shieldMax = WireNumber(fields[7]);
                if (shieldMax.Value<double>() < 0) throw new FormatException("hot_shield_max");
                bool down = WireInteger(fields[8], 0, 1) == 1;
                var copy = overflow ? (overflowEdits ??= (PlayerHudAlly[])source.Clone()) : (visibleEdits ??= (PlayerHudAlly[])source.Clone());
                copy[index] = old with { Hp = hp, HpMax = hpMax, Shield = shield.Value<double>(), ShieldMax = shieldMax.Value<double>(), Down = down };
                edits[i] = new(row, hpJson, new JArray(shield, shieldMax), new JValue(down), false);
            }
            if (edits[i].Changed) changes |= focus ? PlayerHudGroups.Focus : PlayerHudGroups.Allies;
        }
        var targets = focusEdits ?? previous.FocusTargets;
        var allies = visibleEdits == null && overflowEdits == null ? previous.Allies
            : new PlayerHudAllyRoster(visibleEdits ?? previous.Allies!.Rows, overflowEdits ?? previous.Allies!.Overflow);
        var next = new PlayerHudSnapshot(epoch, sequence, previous.Vitals, previous.Combat, previous.Loadout,
            previous.Cooldowns, previous.Buffs, previous.Resources, previous.ColdSkills,
            focusEdits == null ? previous.FocusTarget : focusEdits[0], targets, allies) { BuffCards = previous.BuffCards };
        foreach (var edit in edits) edit.Commit();
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
        if (!ReadHotHeader(wire, out var rows, out var epoch, out var sequence)) return null;

        var edits = new JObject();
        var seen = new HashSet<(string, int)>();
        for (int i = 1; i < rows.Length; i++)
        {
            var fields = rows[i].Split(',');
            string kind = fields[0];
            bool focus = kind == "f";
            if ((!focus && kind is not ("a" or "o")) || fields.Length != (focus ? 6 : 9)) throw new FormatException("hot_item");
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
