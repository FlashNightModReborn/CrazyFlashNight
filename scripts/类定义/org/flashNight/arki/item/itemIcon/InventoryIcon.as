import org.flashNight.arki.item.itemIcon.CollectionIcon;
import org.flashNight.arki.item.ItemUtil;
/*
 * 在背包、仓库或战备箱中的物品图标，继承CollectionIcon
*/

class org.flashNight.arki.item.itemIcon.InventoryIcon extends CollectionIcon{

    public function InventoryIcon(_icon:MovieClip, _collection, _index) {
        super(_icon, _collection, _index);
    }

    public function RollOver():Void{
        _root.物品图标注释(name,value);
        if (!this.locked) _root.鼠标.gotoAndStop("手型准备抓取");
    }

    public function Press():Void{
        _root.注释结束();
        if (this.locked) return;

        icon.图标壳.图标.gotoAndStop(2);
        icon.startDrag(true);
        _root.鼠标.gotoAndStop("手型抓取");

        //硬代码控制一下层级
        var container = icon._parent;
        if (container !== _root.仓库界面 && container.getDepth() < _root.仓库界面.getDepth()){
            container.swapDepths(_root.仓库界面);
        }else if(container !== _root.物品栏界面 && container.getDepth() < _root.物品栏界面.getDepth()){
            container.swapDepths(_root.物品栏界面);
        }
        icon.swapDepths(127);

        //高亮对应装备栏
        if(itemData.type == "武器" || itemData.type == "防具"){
            if(itemData.use == "手枪"){//对手枪2进行额外判定
                icon.highlights = [_root.物品栏界面.手枪,_root.物品栏界面.手枪2];
            }else{
                icon.highlights = [_root.物品栏界面[itemData.use]];
            }
        }else if(itemData.use == "药剂"){
            icon.highlights = _root.玩家信息界面.快捷药剂界面.药剂图标列表;
        }
        for(var i=0; i<icon.highlights.length; i++){
            icon.highlights[i].互动提示.gotoAndPlay("高亮");
        }
    }

    public function Release():Void{
        icon.图标壳.图标.gotoAndStop(1);
        icon.stopDrag();
        icon._x = x;
        icon._y = y;
        //硬代码还原层级
        _root.物品栏界面.swapDepth(_root.物品栏界面.originalDepth);
        _root.仓库界面.swapDepth(_root.仓库界面.originalDepth);
        icon.swapDepths(index);

        var xmouse = _root._xmouse;
        var ymouse = _root._ymouse;
        for(var i=0; i<icon.highlights.length;i++){
            icon.highlights[i].互动提示.gotoAndStop("空");
        }
        icon.highlights = null;

        if(_root.物品栏界面.窗体area.hitTest(xmouse, ymouse)){
            if(_root.物品栏界面.垃圾箱.area.hitTest(xmouse, ymouse)){
                _root.发布消息("丢弃物品" + itemData.displayname);
                collection.remove(index);
                return;
            }

            if(itemData.type == "武器" || itemData.type == "防具"){
                var 装备栏 = _root.物品栏.装备栏;
                var targetIcon = 装备栏.icons[itemData.use];
                var iconMovieClip = targetIcon.icon;
                if(targetIcon.icon.area.hitTest(xmouse, ymouse)){
                    ItemUtil.moveItemToEquipment(this,targetIcon,itemData.use);
                    return;
                }
                //对手枪2进行额外硬代码判定
                var targetIcon = 装备栏.icons["手枪2"];
                if(itemData.use == "手枪" && targetIcon.icon.area.hitTest(xmouse, ymouse)){
                    ItemUtil.moveItemToEquipment(this,targetIcon,"手枪2");
                    return;
                }
            }
            
            var icons = _root.物品栏.背包.icons;
            for (var i in icons){
                var iconMovieClip = icons[i].icon;
                if(iconMovieClip.area.hitTest(xmouse, ymouse)){
                    ItemUtil.moveItemToInventory(this,icons[i]);
                    return;
                }
            }
            return;
        }

        if(_root.仓库界面._visible && _root.仓库界面.窗体area.hitTest(xmouse, ymouse)){
            if(_root.仓库界面.垃圾箱.area.hitTest(xmouse, ymouse)){
                _root.发布消息("丢弃物品" + itemData.displayname);
                collection.remove(index);
                return;
            }

            var 图标列表 = _root.仓库界面.图标列表;
            for(var i=0; i<图标列表.length;i++){
                var iconMovieClip = 图标列表[i];
                if(iconMovieClip.area.hitTest(xmouse, ymouse)){
                    var icon = iconMovieClip.itemIcon;
                    ItemUtil.moveItemToInventory(this,icon);
                    return;
                }
            }
            return;
        }

        if (itemData.use == "药剂" && _root.玩家信息界面.快捷药剂界面.hitTest(xmouse, ymouse)){
            var icons = _root.物品栏.药剂栏.icons;
            for (var i in icons){
                var iconMovieClip = icons[i].icon;
                if(iconMovieClip.area.hitTest(xmouse, ymouse)){
                    ItemUtil.moveItemToDrug(this,icons[i]);
                    return;
                }
            }
            return;
        }

        if (_root.购买物品界面._visible && _root.购买物品界面.hitTest(xmouse, ymouse)){
            _root.物品UI函数.出售物品(name,value);
            collection.remove(index);
            return;
        }
    }
}
