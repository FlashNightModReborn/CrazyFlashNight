#nullable enable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>One adopted display card. Grouping never changes the underlying Buff instances.</summary>
internal sealed record PlayerHudBuffCard(string Id, bool Timed, double Total, double Remaining,
    string Name, string Description, string Polarity, int Stacks,
    PlayerHudBuffActivation? Activation, PlayerHudBuffMod[]? Mods)
{
    internal string PhaseLabel
    {
        get
        {
            if (Activation == null) return "";
            var label = Activation.Active ? Activation.ActiveLabel : Activation.InactiveLabel;
            return label.Length > 0 ? label : Activation.Active ? "已激活" : "未激活";
        }
    }
    internal bool DisplayTimed => Activation is { Active: true, Total: > 0 } || Timed;
    internal double DisplayTotal => Activation is { Active: true, Total: > 0 } ? Activation.Total : Total;
    internal double DisplayRemaining => Activation is { Active: true, Total: > 0 } ? Activation.Remaining : Remaining;

    internal static PlayerHudBuffCard[] Project(IReadOnlyList<PlayerHudBuff> rows)
    {
        var groups = rows.Where(row => row.Group != null).GroupBy(row => row.Group!.Id)
            .ToDictionary(group => group.Key, group => group.ToArray(), StringComparer.Ordinal);
        var valid = new HashSet<string>(groups.Where(pair =>
            pair.Value.Count(row => row.Group!.Primary) == 1 && pair.Value.Count(row => row.Activation != null) <= 1)
            .Select(pair => pair.Key), StringComparer.Ordinal);
        var merged = new HashSet<string>(StringComparer.Ordinal);
        var cards = new List<PlayerHudBuffCard>(rows.Count);
        foreach (var row in rows)
        {
            if (row.Group == null || !valid.Contains(row.Group.Id)) { cards.Add(Single(row)); continue; }
            if (!merged.Add(row.Group.Id)) continue;
            var members = groups[row.Group.Id];
            var primary = members.Single(member => member.Group!.Primary);
            var activation = members.SingleOrDefault(member => member.Activation != null)?.Activation;
            cards.Add(new PlayerHudBuffCard(primary.Id, primary.Timed, primary.Total, primary.Remaining,
                primary.Name, primary.Description, primary.Polarity, primary.Stacks, activation, CombineMods(members)));
        }
        return cards.OrderBy(card => card.Timed).ToArray();
    }

    private static PlayerHudBuffCard Single(PlayerHudBuff row) => new(row.Id, row.Timed, row.Total, row.Remaining,
        row.Name, row.Description, row.Polarity, row.Stacks, row.Activation, row.Mods);

    private static PlayerHudBuffMod[]? CombineMods(IEnumerable<PlayerHudBuff> members)
    {
        if (!members.Any(member => member.Mods != null)) return null;
        var rows = members.Where(member => member.Mods != null).SelectMany(member => member.Mods!).ToArray();
        return rows.Length <= 64 ? rows : null;
    }

    internal static bool SameDisplay(PlayerHudBuffCard? left, PlayerHudBuffCard? right)
    {
        if (ReferenceEquals(left, right)) return true;
        if (left == null || right == null) return false;
        return left.Id == right.Id && left.Name == right.Name && left.Description == right.Description &&
            left.Polarity == right.Polarity && left.Stacks == right.Stacks &&
            left.Timed == right.Timed && Seconds(left.Total) == Seconds(right.Total) &&
            Seconds(left.Remaining) == Seconds(right.Remaining) && SameActivation(left.Activation, right.Activation) &&
            SameMods(left.Mods, right.Mods);
    }

    private static bool SameActivation(PlayerHudBuffActivation? left, PlayerHudBuffActivation? right)
    {
        if (left == null || right == null) return left == null && right == null;
        return left.Active == right.Active && left.ActiveLabel == right.ActiveLabel &&
            left.InactiveLabel == right.InactiveLabel && Seconds(left.Total) == Seconds(right.Total) &&
            Seconds(left.Remaining) == Seconds(right.Remaining);
    }

    private static bool SameMods(PlayerHudBuffMod[]? left, PlayerHudBuffMod[]? right)
    {
        if (left == null || right == null) return left == null && right == null;
        if (left.Length != right.Length) return false;
        for (var i = 0; i < left.Length; i++)
            if (left[i].Property != right[i].Property || left[i].Calc != right[i].Calc || left[i].Value != right[i].Value) return false;
        return true;
    }

    internal static double Seconds(double frames) => Math.Ceiling(frames * PlayerHudCooldownText.StepMilliseconds / 1000);

    internal static string DescribeMod(PlayerHudBuffMod mod)
    {
        var value = mod.Value.ToString("0.##", CultureInfo.InvariantCulture);
        var signed = (mod.Value > 0 ? "+" : "") + value;
        return mod.Calc switch
        {
            "add" => signed,
            "percent" => (mod.Value > 0 ? "+" : "") + (mod.Value * 100).ToString("0.##", CultureInfo.InvariantCulture) + "%",
            "multiply" => "×" + value,
            "add_positive" => signed + "（正向取强）",
            "add_negative" => signed + "（负向取强）",
            "mult_positive" => "×" + value + "（正向取强）",
            "mult_negative" => "×" + value + "（负向取强）",
            "override" => "设为 " + value,
            "max" => "不低于 " + value,
            "min" => "不高于 " + value,
            _ => "按 " + mod.Calc + " 修正 " + value
        };
    }
}
