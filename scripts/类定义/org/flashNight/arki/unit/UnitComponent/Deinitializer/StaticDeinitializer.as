

import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.component.Shield.*;

class org.flashNight.arki.unit.UnitComponent.Deinitializer.StaticDeinitializer
{

    public function deInitialize(target:MovieClip):Void
    {
        throw new Error("工具类待实现");
    }

    public static function deInitializeUnit(target:MovieClip):Void 
    {
        if(!target._deInitialized)
        {
            if(target.aabbCollider)
            {
                target.aabbCollider.getFactory().releaseCollider(target.aabbCollider);
            }
            
            TargetCacheManager.removeUnit(target);
            // 卸载ai组件
            target.unitAI.destroy();

            // 清空护盾（释放内部护盾引用）
            if(target.shield) {
                // 优先回收自适应护盾容器到对象池，减少频繁 new/free 带来的 GC 压力
                if (target.shield instanceof AdaptiveShield) {
                    var container:AdaptiveShield = AdaptiveShield(target.shield);
                    if (AdaptiveShield.POOL_ENABLED) {
                        AdaptiveShield.recycleToPool(container);
                    } else {
                        // 兼容：对象池关闭时保持原行为
                        container.clear();
                    }
                } else if (target.shield.clear != undefined) {
                    // 兜底：非 AdaptiveShield 实现（如历史遗留 IShield/ShieldStack）
                    target.shield.clear();
                }
                target.shield = null;
            }

            if(!target.已加经验值) target.死亡检测();

            // 发布特殊单位移除事件
            if(target.publishStageEvent === true){
                _root.gameworld.dispatcher.publish("UnitRemoved", target._name);
            }

            // 检查并销毁dispatcher以解除所有事件订阅
            if(target.dispatcher)
            {
                target.dispatcher.destroy();
            }

            target._deInitialized = true;
        } 
    }
}
