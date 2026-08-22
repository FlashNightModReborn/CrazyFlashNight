/**
 * 已提交玩家资产回执到 loot v1 wire payload 的纯投影器。
 *
 * catalog/tier 展示解析仍由根时间轴边界完成；本类只冻结跨层字段形状，并让
 * receipt 的逐 effect 故障隔离可由 TestLoader 直接验证。
 */
class org.flashNight.arki.item.PlayerAssetWireProjector {

    public static function buildMessage(fact:Object):Object {
        if (fact == null) return null;
        var msg:Object = {
            direction:String(fact.direction),
            kind:String(fact.kind),
            itemKey:String(fact.itemKey),
            name:String(fact.name),
            count:Number(fact.count),
            source:String(fact.source),
            icon:fact.icon == undefined ? null : fact.icon
        };

        var version:Number = Number(fact.version);
        if (!isNaN(version) && version == Math.floor(version)) msg.v = version;
        addOptionalString(msg, "tier", fact.tier);
        addOptionalString(msg, "operationId", fact.operationId);
        addOptionalString(msg, "mergeScope", fact.mergeScope);
        addOptionalString(msg, "reason", fact.reason);
        if (fact.doll != undefined && fact.doll != null) msg.doll = fact.doll;

        var eliteLevel:Number = Number(fact.eliteLevel);
        if (msg.kind == "kill" && !isNaN(eliteLevel)
                && eliteLevel >= 0 && eliteLevel <= 2) {
            msg.eliteLevel = eliteLevel;
        }
        return msg;
    }

    /**
     * 每个 effect 都有独立故障边界。消费者失败只报告该下标，后续已提交事实
     * 必须继续投影；消费者不得反向改变 receipt。
     */
    public static function forEachEffect(receipt:Object, consumer:Function,
                                         errorSink:Function):Void {
        if (receipt == null || !(receipt.effects instanceof Array)
                || typeof consumer != "function") return;
        for (var i:Number = 0; i < receipt.effects.length; i++) {
            var effect:Object = receipt.effects[i];
            if (effect == null) continue;
            try {
                consumer(effect, i);
            } catch (projectionError) {
                if (typeof errorSink == "function") {
                    try {
                        errorSink(projectionError, i);
                    } catch (ignoredError) {
                    }
                }
            }
        }
    }

    private static function addOptionalString(target:Object, key:String,
                                              value):Void {
        if (value == undefined || value == null || String(value).length == 0) return;
        target[key] = String(value);
    }
}
