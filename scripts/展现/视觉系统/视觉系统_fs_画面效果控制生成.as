import org.flashNight.neur.Event.*;
import org.flashNight.arki.component.Effect.*;

_root.当前效果总数 = 0;
_root.当前画面效果总数 = 0;
_root.画面效果存在时间 = 1 * 1000;

_root.效果 = Delegate.create(EffectSystem, EffectSystem.Effect);
_root.画面效果 = Delegate.create(EffectSystem, EffectSystem.ScreenEffect);

EventBus.getInstance().subscribe("SceneChanged", function() {
	EffectSystem.initializeEffectPool();
}, null); // 地图变动时，重新初始化子弹池
