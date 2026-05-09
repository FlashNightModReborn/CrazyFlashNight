/**
 * SkinReadyClass - 装扮 deferred-ready 通道接收器
 *
 * 与 DressupReferenceManager.attach 的 register-attach-unregister 协议配对：
 * 仅当 unit.syncRefs[refName + ":ready"] === true 时，attach 会临时把 skinConfig
 * 绑到本类，attachMovie 注入 initObject {__unit, __publishKey}，由本类 onLoad
 * 在 load flush 阶段（子树含嵌套 attachMovie 全部就绪后）派发 deferred 事件。
 *
 * 时序契约见 agentsDoc/as2-load-timing.md 第 2.3 节、第 3 节方案 B-精准。
 */
dynamic class org.flashNight.arki.unit.UnitComponent.Dressup.SkinReadyClass extends MovieClip {

    public function SkinReadyClass() {
        // 空构造：initObject (__unit / __publishKey) 由 Flash 在 PlaceObject 后注入
    }

    public function onLoad():Void {
        var unit:MovieClip = this.__unit;
        var key:String = this.__publishKey;

        // 派发前活性校验：unit 可能在 load flush 之前就被卸载（死亡/切关/换装）
        if (!unit || !unit._parent || !unit.dispatcher || !key) {
            return;
        }

        unit.dispatcher.publish(key, unit);
    }
}
