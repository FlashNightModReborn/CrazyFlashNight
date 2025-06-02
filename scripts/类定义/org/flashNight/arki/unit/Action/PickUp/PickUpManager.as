/**
 * 路径: org/flashNight/arki/unit/Action/PickUp/PickUpManager.as
 */

import org.flashNight.neur.Event.*;
import org.flashNight.aven.Coordinator.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

class org.flashNight.arki.unit.Action.PickUp.PickUpManager {
    
    private var count:Number;
    private var pickupItemDict:Object;
    private var dispatcher:Object; // LifecycleEventDispatcher
    
    /**
     * 构造函数
     */
    function PickUpManager() {
        this.count = 0;
        this.createPickupItemPool();
    }
    
    /**
     * 创建拾取物品池
     */
    function createPickupItemPool():Void {
        this.pickupItemDict = {};
        this.dispatcher = new LifecycleEventDispatcher(_root.gameworld);
        
        var self:PickUpManager = this;
        EventCoordinator.addUnloadCallback(
            _root.gameworld, 
            function():Void {
                self.pickupItemDict = null;
                self.dispatcher.destroy();
            }
        );
    }
    
    /**
     * 拾取物品
     */
    function pickup(target:MovieClip, 拾取者:Object, 播放拾取动画:Boolean):Void {
        var str:String = "获得";
        var itemName:String = target.物品名;
        var value:Number = target.数量;
        
        if (拾取者 && 拾取者.名字) {
            str = 拾取者.名字 + "为你收集了";
        }
        
        if (itemName == "金钱") {
            _root.金钱 += value;
            str += "金钱" + value;
        } else if (itemName == "K点") {
            _root.虚拟币 += value;
            str += "K点" + value;
        } else if (!拾取者 && Key.isDown(_root.组合键) && this.拾取并装备(itemName, value)) {
            str = "已拾取" + itemName;
        } else if (_root.singleAcquire(itemName, value)) {
            str += itemName + value + "个。";
        } else {
            _root.发布消息("物品栏空间不足，无法拾取！");
            return;
        }
        
        // 销毁对象
        _root.发布消息(str);
        var 控制对象:MovieClip = TargetCacheManager.findHero();
        target.gotoAndPlay("消失");
        delete this.pickupItemDict[target.index];
        _root.播放音效("拾取音效");
        
        if (!拾取者 && 播放拾取动画) {
            控制对象.拾取();
        }
    }
    
    /**
     * 拾取并装备物品
     */
    function 拾取并装备(itemName:String, value:Number):Boolean {
        var itemData:Object = _root.getItemData(itemName);
        
        if (itemData.type == "武器" || itemData.type == "防具" || itemData.use == "手雷") {
            var 装备:Object = _root.物品栏.装备栏.getNameString(itemData.use);
            
            if (itemData.level && itemData.level > _root.等级) {
                return false;
            }
            
            if (!装备 && itemData.use) {
                // 装备栏为空，直接装备
                if (itemData.use == "手雷") {
                    _root.物品栏.装备栏.add(itemData.use, {name: itemName, value: value});
                } else {
                    _root.物品栏.装备栏.add(itemData.use, {name: itemName, value: {level: value}});
                }
                _root.刷新人物装扮(_root.控制目标);
                
                if (itemData.type == "武器" || itemData.use == "手雷") {
                    TargetCacheManager.findHero().攻击模式切换(itemData.use);
                }
            } else if (装备 && itemData.use) {
                // 装备栏有装备，需要替换
                var 背包:Object = _root.物品栏.背包;
                var targetIndex:Number = 背包.getFirstVacancy();
                
                if (targetIndex == -1) {
                    return false;
                }
                
                // 卸下装备
                var result:Boolean = _root.物品栏.装备栏.move(背包, itemData.use, targetIndex);
                if (!result) {
                    return false;
                }
                
                if (itemData.use == "手雷") {
                    _root.物品栏.装备栏.add(itemData.use, {name: itemName, value: value});
                } else {
                    _root.物品栏.装备栏.add(itemData.use, {name: itemName, value: {level: value}});
                }
                _root.刷新人物装扮(_root.控制目标);
                
                if (itemData.type == "武器" || itemData.use == "手雷") {
                    TargetCacheManager.findHero().攻击模式切换(itemData.use);
                }
            } else {
                return false;
            }
        } else {
            return false;
        }
        
        return true;
    }
    
    /**
     * 创建可拾取物
     */
    function 创建可拾取物(物品名:String, 数量:Number, X位置:Number, Y位置:Number, 是否飞出:Boolean, parameterObject:Object):Void {
        if (数量 <= 0) {
            数量 = 1;
        }
        
        if (物品名 === "金钱" && random(_root.打怪掉钱机率) == 0) {
            物品名 = "K点";
        }
        
        if (!parameterObject) {
            parameterObject = new Object();
        }
        
        parameterObject.index = this.count;
        parameterObject._x = X位置;
        parameterObject._y = Y位置;
        parameterObject.物品名 = 物品名;
        parameterObject.数量 = Number(数量);
        parameterObject.在飞 = Boolean(是否飞出);
        
        var pickupItem:MovieClip = _root.gameworld.attachMovie(
            "可拾取物2", 
            "可拾取物" + this.count, 
            _root.gameworld.getNextHighestDepth(), 
            parameterObject
        );
        
        pickupItem.焦点高亮框.gotoAndPlay(_root.随机整数(1, 59));
        
        // 创建可拾取物池
        if (this.dispatcher.isDestroyed() || this.dispatcher == null) {
            this.createPickupItemPool();
        }
        
        this.pickupItemDict[this.count] = pickupItem;
        pickupItem.焦点高亮框._visible = false;
        
        var self:PickUpManager = this;
        
        var pickUpFunc:Function = function():Void {
            var focusedObject:MovieClip = TargetCacheManager.findHero();
            var mc:MovieClip = this.焦点高亮框;
            mc.play();
            this.焦点高亮框._visible = true;
            
            if (Math.abs(this.Z轴坐标 - focusedObject.Z轴坐标) < 50 && 
                focusedObject.area.hitTest(this.area)) {
                self.pickup(this, null, true);
            }
        };
        
        var resetFunc:Function = function():Void {
            var mc:MovieClip = this.焦点高亮框;
            mc.stop();
            mc._visible = false;
        };
        
        this.dispatcher.subscribeGlobal("interactionKeyDown", pickUpFunc, pickupItem);
        this.dispatcher.subscribeGlobal("interactionKeyUp", resetFunc, pickupItem);
        
        this.count++;
    }
    
    /**
     * 获取当前拾取物数量
     */
    function getCount():Number {
        return this.count;
    }
    
    /**
     * 获取拾取物字典
     */
    function getPickupItemDict():Object {
        return this.pickupItemDict;
    }
    
    /**
     * 清理资源
     */
    function destroy():Void {
        if (this.dispatcher) {
            this.dispatcher.destroy();
            this.dispatcher = null;
        }
        this.pickupItemDict = null;
    }
}