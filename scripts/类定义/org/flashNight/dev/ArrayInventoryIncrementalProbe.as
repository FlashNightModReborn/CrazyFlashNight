import org.flashNight.arki.item.itemCollection.Inventory;
import org.flashNight.naki.DataStructures.TreeSet;
import org.flashNight.gesh.iterator.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.gesh.object.ObjectUtil;

/*
 * 只以数字作为键的定长物品栏，继承物品栏基类
*/
class org.flashNight.dev.ArrayInventoryIncrementalProbe extends Inventory {

    public var capacity:Number; //总格数
    private var indexes:TreeSet; //仅供增量写维护的私有索引树
    private var indexArrayCache:Array; //内部升序快照；写入采用新数组，不能对外暴露
    private var indexArrayCapacity:Number; //公开 capacity 变化也使快照失效
    private var indexesDirty:Boolean; //索引树是否需要重建（索引树异常时标记，避免空位判断误判）
    private var occupiedCount:Number; //物理范围内的占用数量，与内部升序快照同步维护
    private var mutationRevision:Number; //每次成功写入后单调递增，供只读投影缓存做 O(1) 失效判断
    private var transactionWriteFaultHookForTests:Function; //仅供 focused TestLoader 注入同步提交异常
    private var indexRebuildCountForTests:Number; //仅供 focused TestLoader 钉住批量事务的确定性复杂度

    public function ArrayInventoryIncrementalProbe(_items:Object,_capacity:Number) {
        super(_items);
        mutationRevision = 1;
        if(_capacity < 1) _capacity = 8;
        this.capacity = _capacity;
        indexArrayCache = null;
        indexArrayCapacity = _capacity;
        // 保留现有 WAVL 增量写结构；查询使用同步维护的内部升序快照。
        indexes = new TreeSet(null, TreeSet.TYPE_WAVL);
        indexesDirty = true;
        occupiedCount = 0;
        indexRebuildCountForTests = 0;
        rebuildIndexesFromItems();
    }

    //重构isEmpty函数，非数字键也会返回false
    public function isEmpty(key:Number):Boolean{
        if(isNaN(key) || Math.floor(key) != key) return false;
        if(key < 0 || key >= capacity) return false;
        return items[key] == null;
    }

    //重构add函数，填写-1时自动寻找可用的索引
    public function add(key:Number, item:Object):Boolean {
        if(item == null || item.name == undefined || item.name == "" || item.value == undefined || item.value == null) return false;
        if(typeof item.value == "number" && (isNaN(item.value) || item.value <= 0)) return false;
        if (key == -1) key = getFirstVacancy();
        if (isNaN(key) || Math.floor(key) != key || key < 0 || key >= capacity) return false;
        if (!isEmpty(key) || !isAddable(String(key), item)) return false;

        var beforeIndexes:Array = getValidatedIndexes();
        var nextIndexes:Array = beforeIndexes.concat();
        nextIndexes.splice(indexPosition(beforeIndexes, key), 0, key);
        items[key] = item;
        indexArrayCache = nextIndexes;
        indexArrayCapacity = capacity;
        occupiedCount = nextIndexes.length;
        // 派生状态和版本必须先完成，再向同步监听器发布。
        // 监听器抛错仍向外传播；它不能把已经完成的真实写入变成未执行。
        try {
            if (indexes == null || indexesDirty || indexes.contains(key)) rebuildIndexesFromItems();
            else indexes.add(key);
        } catch (indexError) {
            rebuildIndexesFromItems();
        }
        bumpMutationRevision();
        publishTransactionChange(key, "added");
        return true;
    }


    public function remove(key:Number):Void {
        if(isNaN(key) || Math.floor(key) != key || key < 0 || key >= capacity) return;
        if(items[key] == null) return;
        var beforeIndexes:Array = getValidatedIndexes();
        var nextIndexes:Array = beforeIndexes.concat();
        nextIndexes.splice(indexPosition(beforeIndexes, key), 1);
        delete items[key];
        indexArrayCache = nextIndexes;
        indexArrayCapacity = capacity;
        occupiedCount = nextIndexes.length;
        try {
            if (indexes == null || indexesDirty || !indexes.remove(key)) rebuildIndexesFromItems();
        } catch (indexError) {
            rebuildIndexesFromItems();
        }
        bumpMutationRevision();
        publishTransactionChange(key, "removed");
    }

    /**
     * 数量型物品写入也推进版本。版本必须先于基类的同步 ItemValueChanged/ItemRemoved
     * 事件可见；若本次归零又触发 remove()，版本可能再推进一次，调用方只依赖单调性。
     */
    public function addValue(key:String, value:Number):Void {
        if (isNaN(value)) return;
        var current:Object = getItem(key);
        if (current == null) {
            super.addValue(key, value);
            return;
        }
        bumpMutationRevision();
        super.addValue(key, value);
    }

    /** 返回容器级单调写版本；不使用帧号/毫秒 tick，避免同帧多写碰撞。 */
    public function getMutationRevision():Number {
        var current:Number = Number(mutationRevision);
        return isNaN(current) || current < 0 ? 0 : current;
    }

    /** focused TestLoader 只读计数；生产逻辑不依赖此值。 */
    public function _getIndexRebuildCountForTests():Number {
        var current:Number = Number(indexRebuildCountForTests);
        return isNaN(current) || current < 0 ? 0 : current;
    }

    /** focused TestLoader 故障注入；正式运行时默认永远为 null。 */
    public function _setTransactionWriteFaultHookForTests(hook:Function):Void {
        transactionWriteFaultHookForTests = hook;
    }

    private function invokeTransactionWriteFaultHookForTests(phase:String):Void {
        var hook:Function = transactionWriteFaultHookForTests;
        if (hook != null) hook(phase);
    }

    private function bumpMutationRevision():Void {
        var current:Number = Number(mutationRevision);
        if (isNaN(current) || current < 0) current = 0;
        mutationRevision = current + 1;
    }

    /**
     * inventory-domain 事务提交用的无事件单槽写入口。
     *
     * 该入口只负责一次不可重入的提交阶段：调用方必须先完整预检全部槽位，
     * 再用本方法写入，并在所有槽都成功后通过 publishTransactionChange 统一派发事件。
     * 不能用它替代普通 add/remove；普通业务仍应走原生命周期方法。
     */
    public function transactionWrite(key:Number, item:Object):Boolean {
        if (isNaN(key) || Math.floor(key) != key || key < 0 || key >= capacity) return false;
        if (item != null) {
            if (item.name == undefined || item.name == "" || item.value == undefined || item.value == null) return false;
            if (typeof item.value == "number" && (isNaN(item.value) || item.value <= 0)) return false;
        }

        // 保留进入态的真实对象引用：成功时继续原位更新 items，
        // 失败时则把槽位、TreeSet、索引标志与 raw revision 全部还原。
        // rebuildIndexesFromItems 只会构造并替换新 TreeSet，不会改写旧树，
        // 因此保留旧树引用即可精确回到提交前状态。
        var previousItems:Object = this.items;
        var slotKey:String = String(key);
        var hadOwnSlot:Boolean = previousItems.hasOwnProperty(slotKey);
        var previousItem:Object = previousItems[key];
        getValidatedIndexes();
        var previousIndexArray:Array = this.indexArrayCache;
        var previousIndexCapacity:Number = this.indexArrayCapacity;
        var previousIndexes:TreeSet = this.indexes;
        var previousIndexesDirty:Boolean = this.indexesDirty;
        var previousOccupiedCount:Number = this.occupiedCount;
        var previousRevision:Number = this.mutationRevision;

        try {
            if (item == null) delete previousItems[key];
            else previousItems[key] = item;
            invokeTransactionWriteFaultHookForTests("mutation");

            this.indexesDirty = true;
            rebuildIndexesFromItems();
            invokeTransactionWriteFaultHookForTests("rebuildIndexes");

            bumpMutationRevision();
            invokeTransactionWriteFaultHookForTests("bumpRevision");
            return true;
        } catch (writeError) {
            this.items = previousItems;
            if (hadOwnSlot) previousItems[key] = previousItem;
            else delete previousItems[key];
            this.indexes = previousIndexes;
            this.indexArrayCache = previousIndexArray;
            this.indexArrayCapacity = previousIndexCapacity;
            this.indexesDirty = previousIndexesDirty;
            this.occupiedCount = previousOccupiedCount;
            this.mutationRevision = previousRevision;
            return false;
        }
    }

    /**
     * 多槽事务的纯预检入口。changes 每项为：
     * {slot, expectedItem, item, hasFinalValue?, finalValue?}。
     * expectedItem 与 item 都是精确对象引用；空槽显式写 null。
     */
    public function canApplySlotTransaction(changes:Array):Boolean {
        if (!(changes instanceof Array) || changes.length < 1) return false;
        var seenSlots:Object = {};
        for (var i:Number = 0; i < changes.length; i++) {
            var change:Object = changes[i];
            if (change == null) return false;
            var slot:Number = Number(change.slot);
            if (isNaN(slot) || Math.floor(slot) != slot || slot < 0 || slot >= capacity) return false;
            var slotKey:String = String(slot);
            if (seenSlots[slotKey] === true) return false;
            seenSlots[slotKey] = true;
            if (getItem(slotKey) !== change.expectedItem) return false;
            if (!isValidTransactionItem(change.item)) return false;
            if (change.hasFinalValue === true) {
                var finalValue:Number = Number(change.finalValue);
                if (change.item == null || typeof change.item.value != "number"
                        || isNaN(finalValue) || finalValue <= 0) return false;
            }
        }
        return true;
    }

    private function isValidTransactionItem(item:Object):Boolean {
        if (item == null) return true;
        if (item.name == undefined || item.name == ""
                || item.value == undefined || item.value == null) return false;
        return typeof item.value != "number" || (!isNaN(Number(item.value)) && Number(item.value) > 0);
    }

    private function buildSlotTransactionReceipt(changes:Array):Object {
        getValidatedIndexes();
        var receiptChanges:Array = [];
        for (var i:Number = 0; i < changes.length; i++) {
            var change:Object = changes[i];
            var slot:Number = Number(change.slot);
            receiptChanges.push({
                slot:slot,
                beforeHad:items.hasOwnProperty(String(slot)),
                beforeItem:items[slot],
                afterItem:change.item,
                hasFinalValue:change.hasFinalValue === true,
                beforeValue:change.item == null ? undefined : change.item.value,
                afterValue:change.finalValue
            });
        }
        return {
            success:true,
            owner:this,
            beforeRevision:mutationRevision,
            previousIndexes:indexes,
            previousIndexArray:indexArrayCache,
            previousIndexCapacity:indexArrayCapacity,
            previousIndexesDirty:indexesDirty,
            previousOccupiedCount:occupiedCount,
            changes:receiptChanges
        };
    }

    private function applySlotTransactionReceipt(receipt:Object):Void {
        var changes:Array = receipt.changes;
        var i:Number;
        for (i = 0; i < changes.length; i++) {
            var change:Object = changes[i];
            if (change.afterItem == null) delete items[change.slot];
            else items[change.slot] = change.afterItem;
        }
        for (i = 0; i < changes.length; i++) {
            change = changes[i];
            if (change.hasFinalValue === true) change.afterItem.value = Number(change.afterValue);
        }
        indexesDirty = true;
        rebuildIndexesFromItems();
        bumpMutationRevision();
        receipt.revision = mutationRevision;
    }

    /**
     * 完整预检后一次提交多个槽位，只重建一次索引并只推进一次 revision。
     * 热路径不捕获异常；所有可预期失败都必须在任何写入前返回 false receipt。
     */
    public function transactionApplySlotChangesWithReceipt(changes:Array):Object {
        if (!canApplySlotTransaction(changes)) return {success:false, rollbackComplete:true};
        var receipt:Object = buildSlotTransactionReceipt(changes);
        applySlotTransactionReceipt(receipt);
        return receipt;
    }

    private function slotTransactionMatchesAfter(receipt:Object):Boolean {
        var changes:Array = receipt.changes;
        for (var i:Number = 0; i < changes.length; i++) {
            var change:Object = changes[i];
            if (getItem(String(change.slot)) !== change.afterItem) return false;
            if (change.hasFinalValue === true
                    && change.afterItem.value !== Number(change.afterValue)) return false;
        }
        return true;
    }

    private function restoreSlotTransactionReceipt(receipt:Object):Void {
        var changes:Array = receipt.changes;
        var i:Number;
        for (i = 0; i < changes.length; i++) {
            var change:Object = changes[i];
            if (change.hasFinalValue === true) change.afterItem.value = change.beforeValue;
        }
        for (i = 0; i < changes.length; i++) {
            change = changes[i];
            if (change.beforeHad === true) items[change.slot] = change.beforeItem;
            else delete items[change.slot];
        }
        indexes = receipt.previousIndexes;
        indexArrayCache = receipt.previousIndexArray;
        indexArrayCapacity = Number(receipt.previousIndexCapacity);
        indexesDirty = receipt.previousIndexesDirty;
        occupiedCount = Number(receipt.previousOccupiedCount);
        mutationRevision = Number(receipt.beforeRevision);
    }

    /** 只回滚本容器刚签发且未被后续写覆盖的多槽 receipt。 */
    public function rollbackSlotTransaction(receipt:Object):Boolean {
        if (receipt == null || receipt.success !== true || receipt.owner !== this
                || !(receipt.changes instanceof Array)
                || getMutationRevision() != Number(receipt.revision)
                || !slotTransactionMatchesAfter(receipt)) return false;
        restoreSlotTransactionReceipt(receipt);
        return getMutationRevision() == Number(receipt.beforeRevision);
    }

    /**
     * 装备调制等显式领域事务使用的批量原位 value 写入口。
     *
     * changes 中每项必须携带 slot、expectedItem、expectedValue、expectedLastUpdate、
     * value 与 lastUpdate。方法先完整校验全部槽位，再原位写入，整个批次只推进一次
     * mutationRevision，且不在半提交状态派发任何生命周期事件。
     */
    public function canApplyValueTransaction(changes:Array):Boolean {
        if (!(changes instanceof Array)) return false;
        var seen:Object = {};
        for (var i:Number = 0; i < changes.length; i++) {
            var change:Object = changes[i];
            if (change == null) return false;
            var slot:Number = Number(change.slot);
            if (isNaN(slot) || Math.floor(slot) != slot || slot < 0 || slot >= capacity) return false;
            var slotKey:String = String(slot);
            if (seen[slotKey] == true) return false;
            seen[slotKey] = true;

            var item:Object = items[slot];
            if (item == null || item !== change.expectedItem || item.value !== change.expectedValue) return false;
            if (Number(item.lastUpdate) != Number(change.expectedLastUpdate)) return false;
            if (change.value == null || typeof change.value != "object") return false;
            var timestamp:Number = Number(change.lastUpdate);
            if (isNaN(timestamp) || timestamp < 0) return false;
        }
        return true;
    }

    public function transactionApplyValueChanges(changes:Array):Boolean {
        var receipt:Object = transactionApplyValueChangesWithReceipt(changes);
        return receipt != null && receipt.success === true;
    }

    /**
     * 跨容器领域事务使用的可回滚 value receipt。旧 Boolean API 保持兼容，
     * 新调用方可在另一容器提交失败时恢复 value、lastUpdate 与 raw revision。
     */
    public function transactionApplyValueChangesWithReceipt(changes:Array):Object {
        if (!canApplyValueTransaction(changes)) {
            return {success:false, rollbackComplete:true};
        }
        var beforeRevision:Number = getMutationRevision();
        var receiptChanges:Array = [];
        var i:Number;
        for (i = 0; i < changes.length; i++) {
            var planned:Object = changes[i];
            var current:Object = items[Number(planned.slot)];
            receiptChanges.push({
                slot:Number(planned.slot),
                item:current,
                beforeValue:current.value,
                beforeLastUpdate:Number(current.lastUpdate),
                afterValue:planned.value,
                afterLastUpdate:Number(planned.lastUpdate)
            });
        }
        if (changes.length == 0) {
            return {
                success:true,
                beforeRevision:beforeRevision,
                revision:beforeRevision,
                changes:receiptChanges
            };
        }
        try {
            for (i = 0; i < receiptChanges.length; i++) {
                var applied:Object = receiptChanges[i];
                applied.item.value = applied.afterValue;
                applied.item.lastUpdate = applied.afterLastUpdate;
            }
            bumpMutationRevision();
        } catch (writeError) {
            var restored:Boolean = true;
            try {
                for (i = 0; i < receiptChanges.length; i++) {
                    var rollback:Object = receiptChanges[i];
                    rollback.item.value = rollback.beforeValue;
                    rollback.item.lastUpdate = rollback.beforeLastUpdate;
                }
                mutationRevision = beforeRevision;
            } catch (rollbackError) {
                restored = false;
            }
            return {success:false, rollbackComplete:restored};
        }
        return {
            success:true,
            beforeRevision:beforeRevision,
            revision:getMutationRevision(),
            changes:receiptChanges
        };
    }

    /** 只回滚本容器刚签发且未被后续写覆盖的 receipt。 */
    public function rollbackValueTransaction(receipt:Object):Boolean {
        if (receipt == null || receipt.success !== true
                || !(receipt.changes instanceof Array)
                || getMutationRevision() != Number(receipt.revision)) {
            return false;
        }
        var changes:Array = receipt.changes;
        var i:Number;
        for (i = 0; i < changes.length; i++) {
            var expected:Object = changes[i];
            var current:Object = items[Number(expected.slot)];
            if (current == null || current !== expected.item
                    || current.value !== expected.afterValue
                    || Number(current.lastUpdate)
                        != Number(expected.afterLastUpdate)) {
                return false;
            }
        }
        var restoredCount:Number = 0;
        try {
            for (i = 0; i < changes.length; i++) {
                var change:Object = changes[i];
                change.item.value = change.beforeValue;
                change.item.lastUpdate = Number(change.beforeLastUpdate);
                restoredCount++;
            }
            mutationRevision = Number(receipt.beforeRevision);
        } catch (rollbackError) {
            try {
                for (i = 0; i < restoredCount; i++) {
                    var compensate:Object = changes[i];
                    compensate.item.value = compensate.afterValue;
                    compensate.item.lastUpdate = Number(compensate.afterLastUpdate);
                }
                mutationRevision = Number(receipt.revision);
            } catch (compensationError) {
                // 调用方收到 false 后必须按 authority-unknown 对账。
            }
            return false;
        }
        return getMutationRevision() == Number(receipt.beforeRevision);
    }

    /** 跨容器 raw commit 全部成功后统一发布 value 生命周期事件。 */
    public function publishValueTransaction(receipt:Object):Void {
        if (receipt == null || receipt.success !== true
                || !(receipt.changes instanceof Array)) return;
        for (var i:Number = 0; i < receipt.changes.length; i++) {
            publishTransactionChange(Number(receipt.changes[i].slot), "value");
        }
    }

    /**
     * inventory-domain 整容器事务提交入口。
     *
     * 调用方先在隔离副本中完成排序/合并计划，本方法完整校验 orderedItems 后
     * 才一次替换底层 items，因而不会把半份 setItems 暴露给同步事件回调。
     */
    public function transactionReplaceAll(orderedItems:Array):Boolean {
        if (!(orderedItems instanceof Array) || orderedItems.length > capacity) return false;
        var replacement:Object = {};
        for (var i:Number = 0; i < orderedItems.length; i++) {
            var item:Object = orderedItems[i];
            if (item == null || item.name == undefined || item.name == "" || item.value == undefined || item.value == null) return false;
            if (typeof item.value == "number" && (isNaN(item.value) || item.value <= 0)) return false;
            replacement[String(i)] = item;
        }
        items = replacement;
        indexesDirty = true;
        rebuildIndexesFromItems();
        bumpMutationRevision();
        return true;
    }

    /**
     * inventory-domain 前缀事务提交入口。
     *
     * 只把 [0, prefixCapacity) 重建为紧凑 orderedItems；prefixCapacity 之后的
     * 物理槽位按原 key / 原对象引用完整保留。战备箱用它整理剧情已解锁前缀，
     * 避免 400 槽存档保留区被排序或压缩。
     */
    public function transactionReplacePrefix(orderedItems:Array, prefixCapacity:Number):Boolean {
        if (!(orderedItems instanceof Array)
            || isNaN(prefixCapacity)
            || Math.floor(prefixCapacity) != prefixCapacity
            || prefixCapacity < 0
            || prefixCapacity > capacity
            || orderedItems.length > prefixCapacity) return false;

        var replacement:Object = {};
        var i:Number;
        for (i = 0; i < orderedItems.length; i++) {
            var item:Object = orderedItems[i];
            if (item == null || item.name == undefined || item.name == "" || item.value == undefined || item.value == null) return false;
            if (typeof item.value == "number" && (isNaN(item.value) || item.value <= 0)) return false;
            replacement[String(i)] = item;
        }
        for (i = prefixCapacity; i < capacity; i++) {
            var preserved:Object = items[i];
            if (preserved != null) replacement[String(i)] = preserved;
        }

        items = replacement;
        indexesDirty = true;
        rebuildIndexesFromItems();
        bumpMutationRevision();
        return true;
    }

    /**
     * transactionWrite 全部提交成功后统一派发兼容既有 UI 的生命周期事件。
     * changeKind: added / removed / replaced / value。
     */
    public function publishTransactionChange(key:Number, changeKind:String):Void {
        var eventDispatcher = getDispatcher();
        if (eventDispatcher == null) return;
        if (changeKind == "value") {
            eventDispatcher.publish("ItemValueChanged", this, String(key));
            return;
        }
        if (changeKind == "removed" || changeKind == "replaced") {
            eventDispatcher.publish("ItemRemoved", this, String(key));
        }
        if (changeKind == "added" || changeKind == "replaced") {
            eventDispatcher.publish("ItemAdded", this, String(key));
        }
    }

    //返回独立的升序槽位索引快照
    public function getIndexes():Array {
        return getValidatedIndexes().concat();
    }

    //返回兼容旧调用的独立 TreeSet 视图
    public function getTreeSet():TreeSet {
        // 兼容旧调试/排序调用；外部修改视图不能修改容器的私有树或数组。
        return TreeSet.buildFromArray(getValidatedIndexes().concat(), null, TreeSet.TYPE_WAVL);
    }

    //覆写setItems，批量替换items后索引需要重建
    public function setItems(_items:Object):Void{
        super.setItems(_items);
        indexesDirty = true;
        rebuildIndexesFromItems();
        bumpMutationRevision();
    }



    // 外部直接设置TreeSet
    public function setIndexes(legacyIndexes:TreeSet):Void {
        // items 是槽位权威。旧 setter 仅保留为无事件重建的兼容适配器，
        // 不从外部树导入成员或比较器。
        rebuildIndexes();
    }

    public function rebuildIndexes():Void {
        indexesDirty = true;
        rebuildIndexesFromItems();
    }

    // 槽位映射是只读快照；物品引用仍保持原身份，业务修改走现有写入口。
    public function getItems():Object {
        var snapshot:Object = {};
        for (var key:String in items) snapshot[key] = items[key];
        return snapshot;
    }

    private function indexPosition(indexArray:Array, key:Number):Number {
        var left:Number = 0;
        var right:Number = indexArray.length;
        while (left < right) {
            var middle:Number = (left + right) >> 1;
            if (indexArray[middle] < key) left = middle + 1;
            else right = middle;
        }
        return left;
    }

    //以数字索引顺序返回物品数组
    public function getItemArray():Array {
        var indexArr:Array = getValidatedIndexes();
        var count:Number = indexArr.length;
        var slotItems:Object = items;
        var list:Array = [];
        for (var i:Number = 0; i < count; i++) list.push(slotItems[indexArr[i]]);
        return list;
    }

    // 覆写修改 searchFirstKey 方法以获得顺序支持
    public function searchFirstKey(name:String):String {
        if(name == null || name == "") return undefined;
        var indexArr:Array = getValidatedIndexes();
        var count:Number = indexArr.length;
        var slotItems:Object = items;
        for(var i:Number = 0; i < count; i++) {
            var index:Number = indexArr[i];
            var item:Object = slotItems[index];
            if(item != null && item.name == name) return String(index);
        }
        return undefined;
    }


    //寻找空格
    //寻找第一个空格的数字索引，若栏位全满则返回-1
    public function getFirstVacancy():Number {
        var indexArr:Array = getValidatedIndexes();
        var currentVacancy:Number = 0;  // 当前要检查的索引

        for(var i:Number = 0; i < indexArr.length; i++){
            var occupiedIndex:Number = indexArr[i];
            if (occupiedIndex > currentVacancy) {
                return currentVacancy < this.capacity ? currentVacancy : -1;
            }
            currentVacancy = occupiedIndex + 1;
            if(currentVacancy >= this.capacity) return -1;
        }

        return currentVacancy < this.capacity ? currentVacancy : -1;
    }

    //返回前n个空格的数字索引，若未填写数量则返回至多16个空索引
    public function getVacancies(amount:Number):Array {
        if (isNaN(amount)) amount = 16;
        var vacancies:Array = [];
        var currentVacancy:Number = 0;  // 当前要检查的索引
        var indexArr:Array = getValidatedIndexes();

        // 遍历已占用的位置并寻找空位
        for (var i:Number = 0; i < indexArr.length && vacancies.length < amount; i++) {
            var occupiedIndex:Number = indexArr[i];

            // 如果当前占用位置大于当前检查的位置，则计算空位区间
            if (occupiedIndex > currentVacancy) {
                // 批量添加从 currentVacancy 到 occupiedIndex - 1 的空位
                var spacesToAdd:Number = Math.min(occupiedIndex - currentVacancy, amount - vacancies.length);
                for (var j:Number = 0; j < spacesToAdd; j++) {
                    if(currentVacancy >= this.capacity) return vacancies;
                    vacancies.push(currentVacancy++);
                }
            }

            // 跳过已占用的当前索引
            currentVacancy = occupiedIndex + 1;
            if(currentVacancy >= this.capacity) return vacancies;
        }

        // 如果没有填满数量，继续添加剩余的空位直到容量为止
        while (vacancies.length < amount && currentVacancy < this.capacity) {
            vacancies.push(currentVacancy++);
        }

        return vacancies;
    }


    //返回物品栏占用格子数
    public function size():Number {
        getValidatedIndexes();
        return occupiedCount;
    }


    //寻找物品格
    //返回第一个满足条件的物品
    public function find(callback:Function) {
        if(typeof callback !== "function") return null;
        var indexArr:Array = getValidatedIndexes();
        var count:Number = indexArr.length;
        for(var i:Number = 0; i < count; i++) {
            // 回调可能写入或替换 items，保持旧实现每次读取当前槽位的语义；
            // 进入时的索引数组则因写时复制而保持不变。
            var item:Object = this.items[indexArr[i]];
            if(callback(item)) return item;
        }
        return null;
    }

    //返回第一个满足条件的物品索引
    public function findIndex(callback:Function):Number {
        if(typeof callback !== "function") return -1;
        var indexArr:Array = getValidatedIndexes();
        var count:Number = indexArr.length;
        for(var i:Number = 0; i < count; i++) {
            var index:Number = indexArr[i];
            var item:Object = this.items[index];
            if(callback(item)) return index;
        }
        return -1;
    }


    //返回物品栏中目标物品的总数
    public function getTotal(targetName:String):Number {
        var total = 0;
        for(var key in this.items){
            var currentItem = this.items[key];
            if(currentItem != null && currentItem.name === targetName){
                total += isNaN(currentItem.value) ? 1 : currentItem.value;
            }
        }
        return total;
    }


    /**
     * 高性能排序重建方法
     * 1. 使用批量数组操作代替逐个插入
     * 2. 直接操作底层数据结构避免继承链开销
     * 3. 利用TreeSet.buildFromArray创建平衡树结构
     *
     * @param sortFunction 排序函数(null则保持原序)
     */
    public function rebuildOrder(sortFunction:Function):Void {
        // 阶段1：准备数据
        var oldItems:Array = this.getItemArray(); // 获取当前有序物品数组
        var maxItems:Number = Math.min(oldItems.length, this.capacity);

        if(_root.服务器 && typeof _root.服务器.发布服务器消息 == "function"){
            _root.服务器.发布服务器消息(ObjectUtil.stringify(oldItems));
        }

        // 阶段2：排序处理（时间复杂度：O(n log n)）
        if (sortFunction != null) {
            // 使用原地排序避免内存分配
            TimSort.sort(oldItems, sortFunction);
        }

        // 阶段3：生成新索引（时间复杂度：O(n)）
        var newIndexes:Array = [];
        for (var i:Number = 0; i < maxItems; i++) {
            newIndexes.push(i); // 生成0到capacity-1的连续索引
        }

        // 阶段4：批量重建数据结构（时间复杂度：O(n)）
        // timsort 对有序数组效率极高，因此额外排序的成本可以忽略
        // 4.1 直接替换索引树
        this.indexes = TreeSet.buildFromArray(
            newIndexes,
            null, // 槽位索引始终保持数字升序
            TreeSet.TYPE_WAVL // 强制使用 WAVL：性能更优
        );

        // 4.2 直接替换物品存储
        var newItems:Object = {};
        for (i = 0; i < maxItems; i++) {
            newItems[String(i)] = oldItems[i]; // 直接写入无需检查
        }
        this.items = newItems;
        this.indexArrayCache = newIndexes;
        this.indexArrayCapacity = capacity;
        this.occupiedCount = maxItems;
        this.indexesDirty = false;
        bumpMutationRevision();

        /*
        // 阶段5：处理溢出物品（如果有?）
        if (oldItems.length > this.capacity) {
            // 发布消息？...
        }
        */
    }

    /**
     * 从当前 items 重建索引树，并返回最新索引数组（升序、去重、范围内）。
     */
    private function rebuildIndexesFromItems():Array {
        var rebuildCount:Number = Number(indexRebuildCountForTests);
        if (isNaN(rebuildCount) || rebuildCount < 0) rebuildCount = 0;
        indexRebuildCountForTests = rebuildCount + 1;
        var indexArr:Array = [];
        var seen:Object = {};
        for (var key:String in this.items) {
            if (ObjectUtil.isInternalKey(key)) continue;
            var idx:Number = Number(key);
            if (isNaN(idx) || Math.floor(idx) != idx) continue;
            if (idx < 0 || idx >= this.capacity) continue;
            if (String(idx) != key) continue; // 排除 "01" / "1.0" 等非规范键，避免幽灵格
            if (this.items[key] == null) continue;
            if (seen[key]) continue;
            seen[key] = true;
            indexArr.push(idx);
        }
        indexArr.sort(Array.NUMERIC);

        var cmpFn:Function = null; // 数字槽位只使用升序比较
        this.indexes = TreeSet.buildFromArray(indexArr, cmpFn, TreeSet.TYPE_WAVL);
        this.indexArrayCache = indexArr;
        this.indexArrayCapacity = capacity;
        this.occupiedCount = indexArr.length;
        this.indexesDirty = false;
        return indexArr;
    }

    /**
     * 获取内部只读索引快照：纯读复用，脏标记或容量变化时从 items 重建。
     */
    private function getValidatedIndexes():Array {
        // 所有结构写入口同步维护快照，外部拿到的映射/树/数组均不能改成员。
        // 因而纯读无需重复物化树或全量校验；公开 capacity 的改变仍需重建。
        if (indexArrayCache == null || indexArrayCapacity != capacity || indexes == null || indexesDirty) {
            return rebuildIndexesFromItems();
        }
        return indexArrayCache;
    }

}
