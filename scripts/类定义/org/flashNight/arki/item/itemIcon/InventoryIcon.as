import org.flashNight.arki.item.itemIcon.ItemIcon;
import org.flashNight.arki.item.itemIcon.CollectionIcon;
import org.flashNight.arki.item.itemIcon.IconFactory;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.key.KeyManager;
/*
 * 在背包、仓库或战备箱中的物品图标，继承CollectionIcon
*/

class org.flashNight.arki.item.itemIcon.InventoryIcon extends CollectionIcon{

    // 仓库每页的物品数量 (5行 * 8列)
    public static var PAGE_SIZE:Number = 40;

    public function InventoryIcon(_icon:MovieClip, _collection, _index) {
        super(_icon, _collection, _index);
    }

    public function RollOver():Void{
        _root.物品图标注释(this.name, this.value, this.item);
        if (!this.locked) _root.鼠标.gotoAndStop("手型准备抓取");
    }

    public function Press():Void{
        _root.注释结束();
        if (this.locked) return;

        var type = itemData.type;
        var use = itemData.use;
        // 检查是否为金钱或K点，是则点击直接获得（优先级最高，不受交互键影响）
        if(this.name === "金钱"){
            _root.金钱 += this.value;
            _root.发布消息("获得金钱" + this.value + "。");
            collection.remove(index);
            return;
        }else if(this.name === "K点"){
            _root.虚拟币 += this.value;
            _root.发布消息("获得K点" + this.value + "。");
            collection.remove(index);
            return;
        }

        // 检测交互键 + 点击：快速移动物品
        if (KeyManager.isKeyDown("互动键")) {
            quickMoveToTarget();
            return;
        }

        // 检查是否为材料或情报，是则点击直接加入对应的收集品栏
        if (type == "收集品") {
            var 栏:Object = _root.收集品栏; // 缓存，少一次链式查找
            var 目标栏:Object = null;
            var 标签:String = "";

            switch (use) {
                case "材料":
                    目标栏 = 栏.材料;
                    标签 = "材料";
                    break;
                case "情报":
                    目标栏 = 栏.情报;
                    标签 = "情报";
                    break;
                default:
                    // 未知 use，必要时可记录日志
                    return;
            }

            // 统一落点
            if(!目标栏.add(this.name, this.value)) {
                目标栏.addValue(this.name, this.value);
            };
            _root.发布消息("获得[" + 标签 + "]" + this.name + "*" + this.value + "。");
            collection.remove(index);
            return;
        }


        var dragIcon = _root.鼠标.物品图标容器.attachMovie("图标-" + itemData.icon, "物品图标", 0);
        dragIcon.gotoAndStop(2);
        icon._alpha = 30;
        _root.鼠标.gotoAndStop("手型抓取");

        // 高亮对应装备栏
        if(type == "武器" || type == "防具" || use == "手雷"){
            if(use == "手枪"){
                icon.highlights = [_root.物品栏界面.手枪,_root.物品栏界面.手枪2];//对手枪2进行额外判定
            }else{
                icon.highlights = [_root.物品栏界面[use]];
            }
            // 如果来源是背包则高亮物品栏强化界面
            if(this.collection === _root.物品栏.背包 && (type == "武器" || type == "防具")){
                var 装备强化界面 = _root.物品栏界面.装备强化界面;
                if(装备强化界面 != null){
                    // 始终高亮进入强化界面标志（支持热切换装备）
                    装备强化界面.进入强化界面标志.gotoAndStop(2);

                    // 如果有当前物品且在强化度转换界面，检查是否可以高亮转换图标
                    if(装备强化界面.当前物品 != null && 装备强化界面.强化度转换物品图标 != null){
                        var 当前装备类型 = 装备强化界面.当前物品.getData().use;
                        // 类型匹配且不是同一件装备
                        if(当前装备类型 == use && this.item !== 装备强化界面.当前物品){
                            if(!icon.highlights) icon.highlights = [];
                            icon.highlights.push(装备强化界面.强化度转换物品图标);
                        }
                    }
                }
            }
        }else if(use == "药剂"){
            icon.highlights = _root.玩家信息界面.快捷药剂界面.药剂图标列表;
        }
        for(var i=0; i<icon.highlights.length; i++){
            icon.highlights[i].互动提示.gotoAndPlay("高亮");
        }
    }

    public function Release():Void{
        _root.鼠标.物品图标容器.物品图标.removeMovieClip();
        icon._alpha = 100;

        if(!this.name || itemData.type === "收集品") return;

        var xmouse = _root._xmouse;
        var ymouse = _root._ymouse;
        for(var i=0; i<icon.highlights.length;i++){
            icon.highlights[i].互动提示.gotoAndStop("空");
        }
        icon.highlights = null;
        _root.物品栏界面.装备强化界面.进入强化界面标志.gotoAndStop(1);

        // 装备栏
        if(_root.物品栏界面.窗体area.hitTest(xmouse, ymouse)){
            if(itemData.type == "武器" || itemData.type == "防具" || itemData.use == "手雷"){
                var 装备栏 = _root.物品栏.装备栏;
                var iconMovieClip = _root.物品栏界面[itemData.use];
                var targetIcon = iconMovieClip.itemIcon;
                if(iconMovieClip.area.hitTest(xmouse, ymouse)){
                    ItemUtil.moveItemToEquipment(this,targetIcon,itemData.use);
                    return;
                }
                //对手枪2进行额外硬代码判定
                iconMovieClip = _root.物品栏界面["手枪2"];
                targetIcon = iconMovieClip.itemIcon;
                if(itemData.use == "手枪" && iconMovieClip.area.hitTest(xmouse, ymouse)){
                    ItemUtil.moveItemToEquipment(this, targetIcon, "手枪2");
                    return;
                }
            }
        }

        // 药剂栏
        if (itemData.use == "药剂" && _root.玩家信息界面.快捷药剂界面.hitTest(xmouse, ymouse)){
            var 图标列表 = _root.玩家信息界面.快捷药剂界面.药剂图标列表;
            for (var i = 0; i < 4; i++){
                var iconMovieClip = 图标列表[i];
                if(iconMovieClip.area.hitTest(xmouse, ymouse)){
                    ItemUtil.moveItemToDrug(this,iconMovieClip.itemIcon);
                    return;
                }
            }
            return;
        }

        // 遍历在场所有数据结构为ArrayInventory的物品栏UI
        for(var uid in IconFactory.inventoryContainerDict){
            var info = IconFactory.inventoryContainerDict[uid];
            if(info.container._visible && info.container.hitTest(xmouse, ymouse)){
                for (var i = 0; i < info.list.length; i++){
                    var iconMovieClip = info.list[i];
                    if(iconMovieClip.area.hitTest(xmouse, ymouse)){
                        ItemUtil.moveItemToInventory(this,iconMovieClip.itemIcon);
                        return;
                    }
                }
            }
        }

        // 商店样品栏（批量售卖，优先于单件售卖检测）
        if (_root.购买物品界面._visible && _root.购买物品界面.样品栏容器 && _root.购买物品界面.样品栏容器.hitTest(xmouse, ymouse)){
            _root.物品UI函数.添加至样品栏(this.item, this.collection, this.index);
            return;
        }

        // 商店（单件售卖）
        if (_root.购买物品界面._visible && _root.购买物品界面.购买执行界面.idle && _root.购买物品界面.购买执行界面.hitTest(xmouse, ymouse)){
            _root.购买物品界面.购买执行界面.售卖确认(this.collection,this.index);
            return;
        }

        // 垃圾箱
        if(_root.物品栏界面.垃圾箱.area.hitTest(xmouse, ymouse) || _root.仓库界面.垃圾箱.area.hitTest(xmouse, ymouse)){
            _root.发布消息("丢弃物品" + itemData.displayname);
            collection.remove(index);
            _root.存档系统.dirtyMark = true;
            return;
        }

        // 强化界面
        if(this.collection === _root.物品栏.背包 && (itemData.type === "武器" || itemData.type === "防具")){
            var 装备强化界面 = _root.物品栏界面.装备强化界面;
            if(装备强化界面 != null){
                // 检测进入强化界面标志
                if(装备强化界面.进入强化界面标志.area.hitTest(xmouse, ymouse)){
                    装备强化界面.刷新强化物品(this.item, this.index, this, this.collection);
                    return;
                }
                // 检测强化度转换物品图标
                if(装备强化界面.强化度转换物品图标 != null && 装备强化界面.强化度转换物品图标.area.hitTest(xmouse, ymouse)){
                    装备强化界面.添加强化度转换物品(this.item, this.index, this, this.collection);
                    return;
                }
            }
        }
    }

    /**
     * 快速移动物品到目标仓库/背包
     * 交互键 + 点击 触发
     *
     * 规则：
     * - 背包物品：移动到仓库/战备箱（优先当前打开的，未打开则默认战备箱）
     * - 仓库/战备箱物品：移动到背包
     * - 移动到当前页范围内，自动合并同名消耗品
     * - 当前页满则提示
     */
    private function quickMoveToTarget():Void {
        if (!this.item) return;

        var 背包 = _root.物品栏.背包;
        var 仓库 = _root.物品栏.仓库;
        var 战备箱 = _root.物品栏.战备箱;
        var 仓库界面 = _root.仓库界面;

        var isInBackpack:Boolean = (this.collection === 背包);
        var isInWarehouse:Boolean = (this.collection === 仓库);
        var isInChest:Boolean = (this.collection === 战备箱);

        if (isInBackpack) {
            // 背包 → 仓库/战备箱
            moveFromBackpack(仓库界面, 仓库, 战备箱);
        } else if (isInWarehouse || isInChest) {
            // 仓库/战备箱 → 背包
            moveToBackpack(背包);
        }
    }

    /**
     * 从背包移动物品到仓库/战备箱
     */
    private function moveFromBackpack(仓库界面:MovieClip, 仓库, 战备箱):Void {
        var targetInventory;
        var currentPage:Number = 0;
        var usePageRange:Boolean = false;

        // 判断目标仓库
        if (仓库界面._visible && 仓库界面.inventory != null) {
            // 仓库界面已打开，使用当前绑定的仓库和当前页
            targetInventory = 仓库界面.inventory;
            currentPage = 仓库界面.page || 0;
            usePageRange = true;
        } else {
            // 未打开仓库界面，默认发送到战备箱第一页
            targetInventory = 战备箱;
            currentPage = 0;
            usePageRange = true;
        }

        executeQuickMove(targetInventory, currentPage, usePageRange);
    }

    /**
     * 从仓库/战备箱移动物品到背包
     */
    private function moveToBackpack(背包):Void {
        // 背包不分页，直接全范围查找
        executeQuickMove(背包, 0, false);
    }

    /**
     * 执行快速移动
     * @param targetInventory 目标物品栏
     * @param page 当前页（仅在 usePageRange=true 时有效）
     * @param usePageRange 是否限制在当前页范围内
     */
    private function executeQuickMove(targetInventory, page:Number, usePageRange:Boolean):Void {
        var itemName:String = this.name;
        var itemValue = this.value;
        // 缓存显示名（移动后 itemData 会被重置为 null）
        var displayName:String = itemData.displayname;
        var isConsumable:Boolean = (itemData.type == "消耗品") && !isNaN(itemValue);

        var startIndex:Number = 0;
        var endIndex:Number = targetInventory.capacity;

        if (usePageRange) {
            startIndex = page * PAGE_SIZE;
            endIndex = Math.min(startIndex + PAGE_SIZE, targetInventory.capacity);
        }

        // 1. 如果是消耗品，先尝试在范围内找同名物品合并
        if (isConsumable) {
            for (var i:Number = startIndex; i < endIndex; i++) {
                var existingItem = targetInventory.getItem(String(i));
                if (existingItem && existingItem.name == itemName && !isNaN(existingItem.value)) {
                    // 找到同名消耗品，执行合并
                    this.collection.merge(targetInventory, String(this.index), String(i));
                    _root.发布消息(displayName + " 已合并");
                    _root.存档系统.dirtyMark = true;
                    return;
                }
            }
        }

        // 2. 没有可合并的，在范围内找空位
        for (var j:Number = startIndex; j < endIndex; j++) {
            if (targetInventory.isEmpty(j)) {
                // 找到空位，执行移动
                this.collection.move(targetInventory, String(this.index), String(j));
                _root.发布消息(displayName + " 已转移");
                _root.存档系统.dirtyMark = true;
                return;
            }
        }

        // 3. 当前页/范围已满
        if (usePageRange) {
            _root.发布消息("当前页已满，无法转移 " + displayName);
        } else {
            _root.发布消息("背包已满，无法转移 " + displayName);
        }
    }
}
