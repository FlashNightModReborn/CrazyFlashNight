#nullable enable

using System;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed class PlayerInfoAnimationModel : IPlayerInfoVisualStateSource
{
    internal const int LogicalFramesPerSecond = 30;
    internal const int LogicalFrameDenominator = 1_000;
    internal const int HpRatioSteps = 128;
    internal const int MpRatioSteps = 100;

    private readonly GaugeAnimation _hp =
        new(PlayerInfoGaugeIds.Hp, HpRatioSteps, appendPercentSign: false);
    private readonly GaugeAnimation _mp =
        new(PlayerInfoGaugeIds.Mp, MpRatioSteps, appendPercentSign: true);

    private int _logicalFrameRemainderNumerator;

    internal PlayerInfoAnimationModel()
    {
        VisualState = CreateVisualState();
    }

    public PlayerInfoVisualState VisualState { get; private set; }
    internal string? LastFixtureCaseId { get; private set; }
    internal int LogicalFrameRemainderNumerator =>
        _logicalFrameRemainderNumerator;
    internal bool WantsAnimationTick => VisualState.WantsAnimationTick;

    internal bool ApplyFixture(PlayerInfoFixtureInput fixture)
    {
        ArgumentNullException.ThrowIfNull(fixture);

        LastFixtureCaseId = fixture.CaseId;
        var visualChanged =
            _hp.Apply(fixture.Hp) |
            _mp.Apply(fixture.Mp);
        VisualState = CreateVisualState();
        return visualChanged;
    }

    /// <summary>
    /// Advances the 30 fps Flash-equivalent logical clock.
    /// The caller owns elapsed-time policy; this model deliberately does not
    /// repeat NativeHudOverlay's 50 ms cap. Multiple logical frames may be
    /// consumed in one call, while the return value reports one aggregated
    /// visual-change decision.
    /// </summary>
    internal bool Tick(int elapsedMilliseconds)
    {
        if (elapsedMilliseconds < 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(elapsedMilliseconds),
                "Elapsed milliseconds cannot be negative.");
        }
        if (elapsedMilliseconds == 0)
        {
            return false;
        }

        var scaledElapsed =
            _logicalFrameRemainderNumerator +
            ((long)elapsedMilliseconds * LogicalFramesPerSecond);
        var logicalFrameCount =
            scaledElapsed / LogicalFrameDenominator;
        _logicalFrameRemainderNumerator =
            (int)(scaledElapsed % LogicalFrameDenominator);

        var visualChanged = false;
        while (logicalFrameCount > 0 &&
               (_hp.WantsAnimationTick || _mp.WantsAnimationTick))
        {
            visualChanged |= _hp.AdvanceOneLogicalFrame();
            visualChanged |= _mp.AdvanceOneLogicalFrame();
            logicalFrameCount--;
        }

        if (visualChanged)
        {
            VisualState = CreateVisualState();
        }
        return visualChanged;
    }

    private PlayerInfoVisualState CreateVisualState() =>
        new(_hp.State, _mp.State);

    private sealed class GaugeAnimation
    {
        private readonly string _gaugeId;
        private readonly int _ratioSteps;
        private readonly bool _appendPercentSign;

        internal GaugeAnimation(
            string gaugeId,
            int ratioSteps,
            bool appendPercentSign)
        {
            _gaugeId = gaugeId;
            _ratioSteps = ratioSteps;
            _appendPercentSign = appendPercentSign;
            State = PlayerInfoGaugeVisualState.Unrenderable(gaugeId);
        }

        internal PlayerInfoGaugeVisualState State { get; private set; }
        internal bool WantsAnimationTick => State.WantsAnimationTick;

        internal bool Apply(PlayerInfoGaugeInput? input)
        {
            var before = State;
            PlayerInfoInputDiagnostic? invalid = Validate(input);
            if (invalid.HasValue)
            {
                State = State.WithInputStatus(
                    isInputValid: false,
                    invalid);
                return false;
            }

            PlayerInfoGaugeInput valid = input!.Value;
            var clampedCurrent = Math.Clamp(
                valid.Current,
                0d,
                valid.Maximum);
            var ratio = clampedCurrent / valid.Maximum;
            var targetFrame = MapVirtualFrame(ratio, _ratioSteps);
            var currentText =
                PlayerInfoGaugeVisualState.FormatFlooredValue(clampedCurrent);
            var maximumText =
                PlayerInfoGaugeVisualState.FormatFlooredValue(valid.Maximum);
            var percentValue = Math.Floor(ratio * 100d)
                .ToString("0", System.Globalization.CultureInfo.InvariantCulture);
            var percentText = _appendPercentSign
                ? percentValue + "%"
                : percentValue;
            string? combinedText = _appendPercentSign
                ? PadAtLeastFive(currentText) + "/" + PadAtLeastFive(maximumText)
                : null;
            var currentFrame = State.HasRenderableState
                ? State.CurrentVirtualFrame
                : targetFrame;

            State = new PlayerInfoGaugeVisualState(
                _gaugeId,
                hasRenderableState: true,
                isInputValid: true,
                clampedCurrent,
                valid.Maximum,
                ratio,
                currentFrame,
                targetFrame,
                currentText,
                maximumText,
                percentText,
                combinedText,
                diagnostic: null);
            return !before.HasSameVisual(State);
        }

        internal bool AdvanceOneLogicalFrame()
        {
            if (!WantsAnimationTick)
            {
                return false;
            }

            var current = State.CurrentVirtualFrame;
            var target = State.TargetVirtualFrame;
            var distance = Math.Abs(target - current);
            var proportionalStep = (int)Math.Ceiling(distance * 0.2d);
            var boundedTimeStep =
                (int)Math.Ceiling((distance / 30d) * 2d);
            var step = Math.Max(
                1,
                Math.Min(
                    distance,
                    Math.Min(proportionalStep, boundedTimeStep)));
            var next = target > current
                ? current + step
                : current - step;
            State = State.WithCurrentVirtualFrame(next);
            return true;
        }

        private PlayerInfoInputDiagnostic? Validate(
            PlayerInfoGaugeInput? input)
        {
            if (!input.HasValue)
            {
                return PlayerInfoInputDiagnostic.Invalid(
                    _gaugeId,
                    PlayerInfoInvalidInputReasons.Missing);
            }
            if (!double.IsFinite(input.Value.Current))
            {
                return PlayerInfoInputDiagnostic.Invalid(
                    _gaugeId,
                    PlayerInfoInvalidInputReasons.CurrentNonFinite);
            }
            if (!double.IsFinite(input.Value.Maximum))
            {
                return PlayerInfoInputDiagnostic.Invalid(
                    _gaugeId,
                    PlayerInfoInvalidInputReasons.MaximumNonFinite);
            }
            if (input.Value.Maximum <= 0)
            {
                return PlayerInfoInputDiagnostic.Invalid(
                    _gaugeId,
                    PlayerInfoInvalidInputReasons.MaximumNotPositive);
            }
            return null;
        }

        private static int MapVirtualFrame(
            double normalizedRatio,
            int ratioSteps)
        {
            var filledSteps =
                (int)Math.Floor(normalizedRatio * ratioSteps);
            return Math.Max(1, ratioSteps + 1 - filledSteps);
        }

        private static string PadAtLeastFive(string value) =>
            value.Length >= 5
                ? value
                : value.PadLeft(5, '0');
    }
}
