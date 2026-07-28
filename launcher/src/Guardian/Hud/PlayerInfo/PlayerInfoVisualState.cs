#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal static class PlayerInfoGaugeIds
{
    internal const string Hp = "hp";
    internal const string Mp = "mp";
}

internal static class PlayerInfoInvalidInputReasons
{
    internal const string Missing = "missing";
    internal const string CurrentNonFinite = "current_non_finite";
    internal const string MaximumNonFinite = "maximum_non_finite";
    internal const string MaximumNotPositive = "maximum_not_positive";
}

internal readonly record struct PlayerInfoGaugeInput(
    double Current,
    double Maximum);

internal sealed class PlayerInfoFixtureInput
{
    internal const double HpMaximum = 12_800d;
    internal const double MpMaximum = 10_000d;

    private sealed record FixtureCase(
        string Id,
        double Hp,
        double Mp);

    private static readonly FixtureCase[] FrozenCases =
    [
        new("empty", 0, 0),
        new("min_step", 100, 100),
        new("p25", 3_200, 2_500),
        new("p50", 6_400, 5_000),
        new("p75", 9_600, 7_500),
        new("p99", 12_672, 9_900),
        new("full", 12_800, 10_000),
        new("mp_vf34", 8_576, 6_700),
        new("mp_vf35", 8_448, 6_600),
        new("mp_vf70", 3_968, 3_100),
        new("mp_vf91", 1_280, 1_000)
    ];

    private static readonly IReadOnlyDictionary<string, FixtureCase>
        FrozenCasesById = FrozenCases.ToDictionary(
            item => item.Id,
            StringComparer.Ordinal);

    private static readonly IReadOnlyList<string> FrozenCaseIds =
        Array.AsReadOnly(FrozenCases.Select(item => item.Id).ToArray());

    internal PlayerInfoFixtureInput(
        string caseId,
        PlayerInfoGaugeInput? hp,
        PlayerInfoGaugeInput? mp)
    {
        ArgumentNullException.ThrowIfNull(caseId);
        if (!IsAllowedCaseId(caseId))
        {
            throw new ArgumentException(
                $"Unknown PlayerInfo fixture case '{caseId}'.",
                nameof(caseId));
        }

        CaseId = caseId;
        Hp = hp;
        Mp = mp;
    }

    internal string CaseId { get; }
    internal PlayerInfoGaugeInput? Hp { get; }
    internal PlayerInfoGaugeInput? Mp { get; }
    internal static IReadOnlyList<string> AllowedCaseIds => FrozenCaseIds;

    internal static bool IsAllowedCaseId(string? caseId) =>
        caseId is not null &&
        FrozenCasesById.ContainsKey(caseId);

    internal static PlayerInfoFixtureInput FromCaseId(string caseId)
    {
        ArgumentNullException.ThrowIfNull(caseId);
        if (!FrozenCasesById.TryGetValue(caseId, out FixtureCase? fixtureCase))
        {
            throw new ArgumentException(
                $"Unknown PlayerInfo fixture case '{caseId}'.",
                nameof(caseId));
        }
        return Create(
            fixtureCase.Id,
            fixtureCase.Hp,
            fixtureCase.Mp);
    }

    private static PlayerInfoFixtureInput Create(
        string caseId,
        double hp,
        double mp) =>
        new(
            caseId,
            new PlayerInfoGaugeInput(hp, HpMaximum),
            new PlayerInfoGaugeInput(mp, MpMaximum));
}

internal readonly record struct PlayerInfoInputDiagnostic(
    string Code,
    string GaugeId,
    string Reason)
{
    internal const string InvalidInputCode = "invalid_input";

    internal static PlayerInfoInputDiagnostic Invalid(
        string gaugeId,
        string reason) =>
        new(InvalidInputCode, gaugeId, reason);
}

internal sealed class PlayerInfoGaugeVisualState
{
    internal PlayerInfoGaugeVisualState(
        string gaugeId,
        bool hasRenderableState,
        bool isInputValid,
        double clampedCurrent,
        double maximum,
        double normalizedRatio,
        int currentVirtualFrame,
        int targetVirtualFrame,
        string currentText,
        string maximumText,
        string percentText,
        string? combinedText,
        PlayerInfoInputDiagnostic? diagnostic)
    {
        GaugeId = gaugeId;
        HasRenderableState = hasRenderableState;
        IsInputValid = isInputValid;
        ClampedCurrent = clampedCurrent;
        Maximum = maximum;
        NormalizedRatio = normalizedRatio;
        CurrentVirtualFrame = currentVirtualFrame;
        TargetVirtualFrame = targetVirtualFrame;
        CurrentText = currentText;
        MaximumText = maximumText;
        PercentText = percentText;
        CombinedText = combinedText;
        Diagnostic = diagnostic;
    }

    internal string GaugeId { get; }
    internal bool HasRenderableState { get; }
    internal bool IsInputValid { get; }
    internal double ClampedCurrent { get; }
    internal double Maximum { get; }
    internal double NormalizedRatio { get; }
    internal int CurrentVirtualFrame { get; }
    internal int TargetVirtualFrame { get; }
    internal string CurrentText { get; }
    internal string MaximumText { get; }
    internal string PercentText { get; }
    internal string? CombinedText { get; }
    internal PlayerInfoInputDiagnostic? Diagnostic { get; }

    internal bool WantsAnimationTick =>
        HasRenderableState &&
        IsInputValid &&
        CurrentVirtualFrame != TargetVirtualFrame;

    internal static PlayerInfoGaugeVisualState Unrenderable(string gaugeId) =>
        new(
            gaugeId,
            hasRenderableState: false,
            isInputValid: false,
            clampedCurrent: 0,
            maximum: 0,
            normalizedRatio: 0,
            currentVirtualFrame: 0,
            targetVirtualFrame: 0,
            currentText: string.Empty,
            maximumText: string.Empty,
            percentText: string.Empty,
            combinedText: null,
            diagnostic: null);

    internal PlayerInfoGaugeVisualState WithInputStatus(
        bool isInputValid,
        PlayerInfoInputDiagnostic? diagnostic) =>
        new(
            GaugeId,
            HasRenderableState,
            isInputValid,
            ClampedCurrent,
            Maximum,
            NormalizedRatio,
            CurrentVirtualFrame,
            TargetVirtualFrame,
            CurrentText,
            MaximumText,
            PercentText,
            CombinedText,
            diagnostic);

    internal PlayerInfoGaugeVisualState WithCurrentVirtualFrame(
        int currentVirtualFrame) =>
        new(
            GaugeId,
            HasRenderableState,
            IsInputValid,
            ClampedCurrent,
            Maximum,
            NormalizedRatio,
            currentVirtualFrame,
            TargetVirtualFrame,
            CurrentText,
            MaximumText,
            PercentText,
            CombinedText,
            Diagnostic);

    internal bool HasSameVisual(PlayerInfoGaugeVisualState other)
    {
        ArgumentNullException.ThrowIfNull(other);
        return string.Equals(GaugeId, other.GaugeId, StringComparison.Ordinal) &&
            HasRenderableState == other.HasRenderableState &&
            ClampedCurrent.Equals(other.ClampedCurrent) &&
            Maximum.Equals(other.Maximum) &&
            NormalizedRatio.Equals(other.NormalizedRatio) &&
            CurrentVirtualFrame == other.CurrentVirtualFrame &&
            TargetVirtualFrame == other.TargetVirtualFrame &&
            string.Equals(CurrentText, other.CurrentText, StringComparison.Ordinal) &&
            string.Equals(MaximumText, other.MaximumText, StringComparison.Ordinal) &&
            string.Equals(PercentText, other.PercentText, StringComparison.Ordinal) &&
            string.Equals(CombinedText, other.CombinedText, StringComparison.Ordinal);
    }

    internal static string FormatFlooredValue(double value) =>
        Math.Floor(value).ToString("0", CultureInfo.InvariantCulture);
}

internal sealed class PlayerInfoVisualState
{
    internal PlayerInfoVisualState(
        PlayerInfoGaugeVisualState hp,
        PlayerInfoGaugeVisualState mp)
    {
        Hp = hp;
        Mp = mp;
    }

    internal PlayerInfoGaugeVisualState Hp { get; }
    internal PlayerInfoGaugeVisualState Mp { get; }

    // A complete fixture snapshot is renderable only after both gauges have
    // independently acquired a last-known-good value.
    internal bool HasRenderableState =>
        Hp.HasRenderableState && Mp.HasRenderableState;

    internal bool HasAnyRenderableGauge =>
        Hp.HasRenderableState || Mp.HasRenderableState;

    internal bool WantsAnimationTick =>
        Hp.WantsAnimationTick || Mp.WantsAnimationTick;
}

internal interface IPlayerInfoVisualStateSource
{
    PlayerInfoVisualState VisualState { get; }
}
