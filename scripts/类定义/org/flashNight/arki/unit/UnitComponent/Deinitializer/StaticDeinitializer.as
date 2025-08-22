

import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

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
            
            TargetCacheUpdater.removeUnit(target);
            // 卸载ai组件
            target.unitAI.destroy();
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
