
_root.效果 = Delegate.create(EffectSystem, EffectSystem.Effect);
_root.画面效果 = Delegate.create(EffectSystem, EffectSystem.ScreenEffect);
_root.触发震屏阶段 = Delegate.create(org.flashNight.arki.render.CombatFxBridge, org.flashNight.arki.render.CombatFxBridge.tryShakePhase);

EventBus.getInstance().subscribe("SceneChanged", function() {
	EffectSystem.initializeEffectPool();
}, null); // 地图变动时，重新初始化子弹池
