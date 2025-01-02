import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.neur.Event.*;

_root.踉跄判定 = ImpactHandler.IMPACT_STAGGER_COEFFICIENT;
_root.冲击残余时间 = ImpactHandler.IMPACT_DECAY_TIME;



_root.冲击力刷新 = Delegate.create(ImpactHandler, ImpactHandler.refreshImpactForce);
_root.冲击力结算 = Delegate.create(ImpactHandler, ImpactHandler.settleImpactForce);
