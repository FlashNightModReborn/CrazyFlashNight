import org.flashNight.arki.item.itemCollection.Inventory;

/*
 * 装备栏，继承物品栏基类
 * 装备栏的键直接代表能接受的装备类型
*/
class org.flashNight.arki.item.itemCollection.EquipmentInventory extends Inventory {

    private static var TRANSACTION_KEYS:Object = {
        头部装备:true,
        上装装备:true,
        手部装备:true,
        下装装备:true,
        脚部装备:true,
        颈部装备:true,
        长枪:true,
        手枪:true,
        手枪2:true,
        刀:true,
        手雷:true
    };

    private var mutationRevision:Number;

    public function EquipmentInventory(_items:Object) {
        super(_items);
        // super 构造期可能动态派发到 setItems；构造完成后统一从稳定基线 1 开始。
        mutationRevision = 1;
    }

    //重构isAddable函数，判定装备类型是否和对应的键相同
    public function isAddable(key:String,item:Object):Boolean{
        if(!super.isAddable(key,item)) return false;
        var use = _root.getItemData(item.name).use;
        //对手枪2进行额外检测
        return use == key || (use == "手枪" && key == "手枪2");
    }

    /**
     * 普通生命周期写在同步事件前推进版本，使监听器读到的版本已覆盖当前写入。
     * legacy add 仍保留原有 use 规则；11 槽白名单只约束新的事务入口。
     */
    public function add(key:String, item:Object):Boolean {
        if (!isEmpty(key) || !isAddable(key, item)) return false;
        bumpMutationRevision();
        if (!super.add(key, item)) {
            mutationRevision--;
            return false;
        }
        return true;
    }

    public function remove(key:String):Void {
        if (isEmpty(key)) return;
        bumpMutationRevision();
        super.remove(key);
    }

    /**
     * 装备栏中的手雷是数量型物品。零增量、空槽与非数值 value 都不是有效写入。
     * 归零时基类会再动态派发 remove，版本与 ArrayInventory 一样允许再次推进。
     */
    public function addValue(key:String, value:Number):Void {
        if (isNaN(value) || value == 0) return;
        var item:Object = getItem(key);
        if (item == null || typeof item.value != "number") return;
        bumpMutationRevision();
        super.addValue(key, value);
    }

    public function setItems(_items:Object):Void {
        super.setItems(_items);
        bumpMutationRevision();
    }

    /** 返回容器级单调写版本；不使用帧号或毫秒 tick。 */
    public function getMutationRevision():Number {
        var current:Number = Number(mutationRevision);
        return isNaN(current) || current < 0 ? 0 : current;
    }

    private function bumpMutationRevision():Void {
        var current:Number = Number(mutationRevision);
        if (isNaN(current) || current < 0) current = 0;
        mutationRevision = current + 1;
    }

    /**
     * character-build 事务提交使用的无事件单槽写入口。
     * 调用方必须先完成跨容器预检，全部写成功后再统一 publish。
     */
    public function transactionWrite(key:String, item:Object):Boolean {
        if (TRANSACTION_KEYS[key] !== true) return false;

        var current:Object = getItem(key);
        if (item != null && !isAddable(key, item)) return false;
        if (current === item) return true;
        if (current == null && item == null) return true;

        if (item == null) delete items[key];
        else items[key] = item;
        bumpMutationRevision();
        return true;
    }

    /**
     * transactionWrite 全部成功后统一派发兼容旧 UI 的生命周期事件。
     * changeKind: added / removed / replaced / value。
     */
    public function publishTransactionChange(key:String, changeKind:String):Void {
        if (TRANSACTION_KEYS[key] !== true) return;
        var eventDispatcher = getDispatcher();
        if (eventDispatcher == null) return;
        if (changeKind == "value") {
            eventDispatcher.publish("ItemValueChanged", this, key);
            return;
        }
        if (changeKind == "removed" || changeKind == "replaced") {
            eventDispatcher.publish("ItemRemoved", this, key);
        }
        if (changeKind == "added" || changeKind == "replaced") {
            eventDispatcher.publish("ItemAdded", this, key);
        }
    }

    /**
     * 已穿戴单件调制专用预检。
     *
     * 这不是通用容器 writer：只接受 11 槽白名单中的一个现有装备，只允许原位替换
     * value/lastUpdate，并要求 item/value 引用和时间戳都与计划阶段完全一致。
     */
    public function canApplyWornValueTransaction(changes:Array):Boolean {
        if (!(changes instanceof Array) || changes.length != 1) return false;
        var change:Object = changes[0];
        if (change == null || typeof change.slot != "string") return false;
        var slot:String = String(change.slot);
        if (TRANSACTION_KEYS[slot] !== true) return false;

        var item:Object = getItem(slot);
        if (item == null || item !== change.expectedItem
                || item.value !== change.expectedValue
                || Number(item.lastUpdate)
                    != Number(change.expectedLastUpdate)) {
            return false;
        }
        if (change.value == null || typeof change.value != "object"
                || change.value === change.expectedValue) {
            return false;
        }
        var timestamp:Number = Number(change.lastUpdate);
        return !isNaN(timestamp) && timestamp >= 0
            && timestamp > Number(change.expectedLastUpdate);
    }

    /**
     * 已穿戴单件 value 的无事件原子应用。成功批次只推进一次 raw revision；
     * 任一赋值异常会在返回前恢复 value、lastUpdate 与 revision。
     */
    public function transactionApplyWornValueChanges(changes:Array):Object {
        if (!canApplyWornValueTransaction(changes)) {
            return {success:false, rollbackComplete:true};
        }
        var change:Object = changes[0];
        var slot:String = String(change.slot);
        var item:Object = getItem(slot);
        var beforeValue:Object = item.value;
        var beforeLastUpdate:Number = Number(item.lastUpdate);
        var beforeRevision:Number = getMutationRevision();
        try {
            item.value = change.value;
            item.lastUpdate = Number(change.lastUpdate);
            bumpMutationRevision();
        } catch (writeError) {
            var restored:Boolean = false;
            try {
                item.value = beforeValue;
                item.lastUpdate = beforeLastUpdate;
                mutationRevision = beforeRevision;
                restored = item.value === beforeValue
                    && Number(item.lastUpdate) == beforeLastUpdate
                    && getMutationRevision() == beforeRevision;
            } catch (rollbackError) {
                restored = false;
            }
            return {success:false, rollbackComplete:restored};
        }
        return {
            success:true,
            beforeRevision:beforeRevision,
            revision:getMutationRevision(),
            changes:[{
                slot:slot,
                item:item,
                beforeValue:beforeValue,
                beforeLastUpdate:beforeLastUpdate,
                afterValue:change.value,
                afterLastUpdate:Number(change.lastUpdate)
            }]
        };
    }

    /**
     * 只回滚本类刚签发、且尚未被任何后续写覆盖的 worn receipt。
     * 先完整验证 post-state，再恢复全部 authority；失败时绝不做部分回滚。
     */
    public function rollbackWornValueTransaction(receipt:Object):Boolean {
        if (receipt == null || receipt.success !== true
                || !(receipt.changes instanceof Array)
                || receipt.changes.length != 1
                || getMutationRevision() != Number(receipt.revision)) {
            return false;
        }
        var change:Object = receipt.changes[0];
        var slot:String = String(change.slot);
        var item:Object = getItem(slot);
        if (TRANSACTION_KEYS[slot] !== true || item == null
                || item !== change.item
                || item.value !== change.afterValue
                || Number(item.lastUpdate)
                    != Number(change.afterLastUpdate)) {
            return false;
        }
        try {
            item.value = change.beforeValue;
            item.lastUpdate = Number(change.beforeLastUpdate);
            mutationRevision = Number(receipt.beforeRevision);
        } catch (rollbackError) {
            return false;
        }
        return item.value === change.beforeValue
            && Number(item.lastUpdate) == Number(change.beforeLastUpdate)
            && getMutationRevision() == Number(receipt.beforeRevision);
    }

    /** 跨资源提交全部完成后，统一发布唯一的 worn value 生命周期事件。 */
    public function publishWornValueTransaction(receipt:Object):Void {
        if (receipt == null || receipt.success !== true
                || !(receipt.changes instanceof Array)
                || receipt.changes.length != 1) {
            return;
        }
        publishTransactionChange(
            String(receipt.changes[0].slot), "value");
    }

    //返回装备名称字符串，若未装备则返回空字符串
    public function getNameString(key:String):String{
        if(isEmpty(key)) return "";
        return items[key].name;
    }

    //返回装备强化度
    public function getLevel(key:String):Number{
        if(isEmpty(key)) return 0;
        return items[key].value.level;
    }
}
