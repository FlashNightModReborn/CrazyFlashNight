import org.flashNight.arki.item.itemIcon.ItemIcon;
import org.flashNight.arki.item.itemIcon.CollectionIcon;
import org.flashNight.arki.item.itemIcon.IconFactory;
import org.flashNight.arki.item.ItemUtil;
/*
 * 在背包、仓库或战备箱中的物品图标，继承CollectionIcon
*/

class org.flashNight.arki.item.itemIcon.InventoryIcon extends CollectionIcon{

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
        // 检查是否为金钱或K点，是则点击直接获得
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
            // 高亮物品栏强化界面
            if(type == "武器" || type == "防具"){
                var 装备强化界面 = _root.物品栏界面.装备强化界面;
                if(装备强化界面 != null && 装备强化界面.当前物品 == null){
                    装备强化界面.进入强化界面标志.gotoAndStop(2);
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

        // 商店
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
        if(itemData.type == "武器" || itemData.type == "防具"){
            var 装备强化界面 = _root.物品栏界面.装备强化界面;
            if(装备强化界面 != null && 装备强化界面.进入强化界面标志.area.hitTest(xmouse, ymouse)){
                装备强化界面.刷新强化物品(this.item, this);
                return;
            }
        }
    }
}
