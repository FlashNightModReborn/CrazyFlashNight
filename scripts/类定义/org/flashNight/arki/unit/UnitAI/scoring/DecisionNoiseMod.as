import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/**
 * DecisionNoiseMod — 决策噪声注入
 *
 * 来源：ActionArbiter._scoreCandidates L474
 * 噪声放在修正器管线末位，不干扰确定性贡献的可解释性
 */
class org.flashNight.arki.unit.UnitAI.scoring.DecisionNoiseMod extends ScoringModifier {

    private var _rng:LinearCongruentialEngine;

    public function DecisionNoiseMod(rng:LinearCongruentialEngine) {
        this._rng = rng;
    }

    public function getName():String { return "DecisionNoise"; }

    public function modify(c:Object, ctx, p:Object, scratch:Object):Number {
        var noise:Number = p.decisionNoise;
        return (_rng.nextFloat() - 0.5) * noise;
    }
}
