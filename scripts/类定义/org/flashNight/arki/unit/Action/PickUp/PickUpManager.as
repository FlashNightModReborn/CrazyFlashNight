/**
 * 路径: org/flashNight/arki/unit/Action/PickUp/PickUpManager.as
 */

import org.flashNight.neur.Event.*;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.aven.Coordinator.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.ProgressValidator;
import org.flashNight.arki.unit.Action.PickUp.PickupEffectService;
import org.flashNight.naki.RandomNumberEngine.*;

class org.flashNight.arki.unit.Action.PickUp.PickUpManager {
    
    private var count:Number;
    private var pickupItemDict:Object;
    private var dispatcher:Object; // LifecycleEventDispatcher

    /**
     * 查询一次性拾取物是否已经被当前角色领取。
     */
    public static function isOneTimeClaimed(claimId):Boolean {
        if (claimId == undefined || claimId == null || String(claimId).length == 0) return false;
        if (_root._saveExt == undefined || _root._saveExt.一次性领取 == undefined) return false;
        return Number(_root._saveExt.一次性领取[String(claimId)]) > 0;
    }

    /**
     * 在物品成功进入背包后登记一次性领取标记。
     */
    public static function claimOneTimePickup(claimId):Void {
        if (claimId == undefined || claimId == null || String(claimId).length == 0) return;

        if (_root._saveExt == undefined) _root._saveExt = {};
        if (_root._saveExt.一次性领取 == undefined) _root._saveExt.一次性领取 = {};

        var key:String = String(claimId);
        if (Number(_root._saveExt.一次性领取[key]) > 0) return;

        _root._saveExt.一次性领取[key] = 1;
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
    }
    
    /**
     * 构造函数
     */
    public function PickUpManager() {
        this.count = 0;
        this.createPickupItemPool();
    }
    
    /**
     * 创建拾取物品池
     */
    public function createPickupItemPool():Void {
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
    public function pickup(target:MovieClip, 拾取者:Object, 播放拾取动画:Boolean):Void {
        if(target.__pickupClaimed===true) return;
        target.__pickupClaimed=true;
        // 实体级同步占用先于领域调用；异常可能已经取得物品，不能把未知结果改成可再次领取。
        // 明确的零写拒绝才释放占用。成功实体随后沿原动画卸载。
        if(pickupOwned(target,拾取者,播放拾取动画)!==true) target.__pickupClaimed=false;
    }
    private function pickupOwned(target:MovieClip, 拾取者:Object, 播放拾取动画:Boolean):Boolean {
        // 鼠标与快捷键共用此权威门；拒绝时保留实体，也不能触发升级或快捷换装。
        var actor:Object = 拾取者 == undefined ? TargetCacheManager.findHero() : 拾取者;
        if (actor == undefined || !(actor.hp > 0)) return false;
        // 同一领取 ID 即使因重复配置同时生成多个实体，也只允许首个成功进入背包。
        if (PickUpManager.isOneTimeClaimed(target.一次性领取ID)) {
            target.gotoAndPlay("消失");
            delete this.pickupItemDict[target.index];
            return true;
        }

        var str:String = "获得";
        var itemName:String = target.物品名;
        var value:Number = target.数量;
        // loot feed 卡片类型（money/kpoint/intel/equip/item），各成功分支赋值
        var lootKind:String = null;
        
        if (拾取者 && 拾取者.名字) {
            str = 拾取者.名字 + "为你收集了";
        }
        
        if (itemName == "金钱") {
            _root.金钱 += value;
            str += "金钱" + value;
            lootKind = "money";
            PlayerAssetTransaction.recordEffect("gain", "money", "金钱", value,
                {source:"pickup", reason:"world_pickup"});
        } else if (itemName == "K点") {
            _root.虚拟币 += value;
            str += "K点" + value;
            lootKind = "kpoint";
            PlayerAssetTransaction.recordEffect("gain", "kpoint", "K点", value,
                {source:"pickup", reason:"world_pickup"});
        } else if (ItemUtil.isInformation(itemName)) {
            // 生成后到实际拾取之间，其他奖励可能已占用剩余容量；这里再次按逐物品
            // maxvalue 结算，避免同屏多个拾取物越界或变成“捡了但没增加”。
            var settlement:Object = ItemUtil.acquireReward([
                {name:itemName, value:value}
            ], {source:"pickup", reason:"world_pickup"});
            if (!settlement.success) {
                _root.发布消息("情报结算失败，暂时无法拾取！");
                return false;
            }
            var conversion:Object = settlement.conversions[0];
            var accepted:Number = Number(conversion.accepted || 0);
            var overflow:Number = Number(conversion.overflow || 0);
            var overflowMoney:Number = Number(conversion.money || 0);
            if (accepted > 0) str += itemName + accepted + "个";
            else str += itemName + "已达持有上限";
            if (overflow > 0 && overflowMoney > 0) {
                str += "，超出的" + overflow + "个已折算为金币" + overflowMoney;
            } else if (overflow > 0) {
                str += "，超出部分不再重复计入";
            }
            str += "。";
            lootKind = "intel";
        } else if (PickupEffectService.isInstantSupply(itemName)) {
            // 战场即时补给：不入包，由 service 现场结算并自己播报收益/拒绝原因。
            // 仅 applied 复用下方实体收尾；通用获得播报与 loot feed 不适用（无资产变化）。
            var outcome:String = PickupEffectService.tryClaim(target);
            if (outcome != "applied") return false;
            lootKind = "supply";
        } else if (!拾取者 && Key.isDown(_root.组合键) && this.拾取并装备(itemName, value)) {
            str = "已拾取" + itemName;
            // 手雷虽然占用装备槽，领域上仍是可堆叠物品；按实际拾取数量播报。
            // 武器/防具才固定为一件，避免把一组手雷错误显示成 ×1 装备。
            lootKind = ItemUtil.isEquipment(itemName) ? "equip" : "item";
            var quickCount:Number = lootKind == "equip" ? 1 : value;
            PlayerAssetTransaction.recordEffect("gain", lootKind, itemName, quickCount,
                {source:"pickup", reason:"quick_equip"});
        } else if (_root.singleAcquire(itemName, value,
                {source:"pickup", reason:"world_pickup"})) {
            str += itemName + value + "个。";
            lootKind = "item";
        } else {
            _root.发布消息("物品栏空间不足，无法拾取！");
            return false;
        }

        // 金币/K 点与快捷装备分支不经过 ItemUtil.acquire()，成功拾取后也必须落脏。
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
        PickUpManager.claimOneTimePickup(target.一次性领取ID);

        // 成功变化由资产事务回执统一驱动 NativeHud；情报已达上限且零折算时
        // 没有实际资产变化，退回旧文本提示。
        // 注：accepted/overflow/overflowMoney 为情报分支 var（AS2 函数作用域），此处可直接判读。
        if (lootKind == "intel") {
            if (accepted <= 0 && !(overflow > 0 && overflowMoney > 0)) {
                _root.发布消息(str);
            }
        } else if (lootKind == null) {
            _root.发布消息(str);
        }
        var 控制对象:MovieClip = TargetCacheManager.findHero();
        target.gotoAndPlay("消失");
        delete this.pickupItemDict[target.index];
        _root.soundEffectManager.playSound("拾取音效.mp3");

        // 发布Pickup事件
        _root.gameworld.dispatcher.publish("Pickup", itemName);
        
        if (!拾取者 && 播放拾取动画 && 控制对象.__playerStatProjectionBlocked!==true
                && 控制对象.__playerStatInitializing!==true) {
            控制对象.拾取();
        }
        return true;
    }
    
    /**
     * 拾取并装备物品
     */
    public function 拾取并装备(itemName:String, value:Number):Boolean {
        var coordinator:org.flashNight.arki.unit.PlayerStatRefreshCoordinator=org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production();
        if(coordinator.equipmentTransition()!=null) return false;
        var admission:Object=coordinator.flush("pickup_equipment_admission");
        if(admission.status!="applied" && admission.status!="unchanged") return false;
        var itemData:Object = _root.getItemData(itemName);
        var type = itemData.type;
        var use = itemData.use;
        
        if (type == "武器" || type == "防具" || use == "手雷") {
            var 装备:Object = _root.物品栏.装备栏.getItem(use);
            
            if (itemData.data.level > _root.等级) {
                return false;
            }

            // 同名手雷交还 ItemUtil.acquire 统一合并；快捷拾取不再把旧堆
            // 强行挪入背包后创建一份新堆。
            if (use == "手雷" && 装备.name == itemName) {
                return false;
            }
            
            if (!装备 && use) {
                // 装备栏为空，直接装备
                var candidate:BaseItem=BaseItem.create(itemName,value);
                if(!_root.物品栏.装备栏.add(use,candidate)) return false;
            } else if (装备 && use) {
                // 装备栏有装备，需要替换
                var 背包:Object = _root.物品栏.背包;
                var targetIndex:Number = 背包.getFirstVacancy();
                
                if (targetIndex == -1) {
                    return false;
                }
                
                // 卸下装备
                var result:Boolean = _root.物品栏.装备栏.move(背包, use, targetIndex);
                if (!result) {
                    return false;
                }
                
                if(!_root.物品栏.装备栏.add(use, BaseItem.create(itemName, value))) {
                    // 卸下已完成，仍须投影这个真实变化；新物品交原调用方尝试入包。
                    projectCommittedEquipment(null);
                    return false;
                }
            } else {
                return false;
            }
        } else {
            return false;
        }
        
        // 容器已成功，异常不能被上层当成未拾取而再次 acquire。
        projectCommittedEquipment(type=="武器" || use=="手雷" ? String(use) : null);
        return true;
    }

    /** 只投影已经完成的装备变化；失败后的恢复绝不再移动物品。 */
    private static function projectCommittedEquipment(mode:String):Void {
        if(_root.存档系统!=undefined) _root.存档系统.dirtyMark=true;
        var c:org.flashNight.arki.unit.PlayerStatRefreshCoordinator=org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production();
        var target:Object=_root.gameworld[_root.控制目标];
        var receipt:Object={context:c.contextToken(),world:org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld),actor:target,mode:mode};
        var result:Object;
        try {result=_root.刷新人物装扮(_root.控制目标);}
        catch(error) {trace("[PickUpManager] committed equipment projection: "+error);}
        if(receipt.context!==c.contextToken() || receipt.world!==org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)
                || _root.gameworld[_root.控制目标]!==target) return;
        var ticket:Object=c.equipmentTransition();
        if(ticket!=null && ticket.context===receipt.context && ticket.actor===target
                && ticket.owner===target.__legacyStatEquipmentOwner) {receipt.body=ticket.targetBody;receipt.ticket=ticket;}
        else if(result.status=="applied" || result.status=="unchanged") receipt.body=target.__playerStatBody;
        if(receipt.body==null || mode==null) return;
        target.__pickupEquipmentModeReceipt=receipt;
        resumePendingEquipmentMode(target);
    }
    /** 原 legacy owner 的显式恢复完成后才恢复原定模式；迟到/新体回执不执行。 */
    public static function resumePendingEquipmentMode(target:Object):Void {
        var receipt:Object=target.__pickupEquipmentModeReceipt;
        if(receipt==null) return;
        var c:org.flashNight.arki.unit.PlayerStatRefreshCoordinator=org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production();
        if(receipt.context!==c.contextToken() || receipt.world!==org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)
                || receipt.actor!==target || target.__playerStatBody!==receipt.body
                || _root.gameworld[_root.控制目标]!==target) return;
        if(c.equipmentTransition()!=null || target.__playerStatFullReady!==receipt.body
                || target.__playerStatProjectionBlocked===true || target.__playerStatInitializing===true) return;
        var barrier:Object=c.flush("pickup_mode");
        if(barrier.status!="applied" && barrier.status!="unchanged") return;
        delete target.__pickupEquipmentModeReceipt;
        target.攻击模式切换(receipt.mode);
    }
    
    /**
     * 创建可拾取物
     */
    public function createCollectible(物品名:String, 数量:Number, X位置:Number, Y位置:Number, 是否飞出:Boolean, parameterObject:Object):Void {
        // Lee攻入篇禁用场内拾取物创建，覆盖受击掉武器、原生帧脚本及换形态等旁路。
        // 赠送复活币直接进入本局库存，不经过场内拾取物；其他书籍、普通关卡不受影响。
        if (org.flashNight.arki.scene.LeeAssaultService.suppressesEnemyDrops()) return;
        if (!parameterObject) parameterObject = new Object();
        if (!ProgressValidator.meetsRequirements(parameterObject)) return;
        if (PickUpManager.isOneTimeClaimed(parameterObject.一次性领取ID)) return;

        if (数量 <= 0) {
            数量 = 1;
        }

        // 61计划只恢复带死亡来源标记的随机转换；固定货币仍保持精确数量。
        var bookCurrency:Boolean = org.flashNight.arki.scene.BookRunService.isBookStageContext();
        var type61Death:Boolean = bookCurrency && parameterObject.敌人死亡货币 === true
            && org.flashNight.arki.scene.Cf6Type61Service.isActive();
        var exactCurrency:Boolean = parameterObject.精确货币数量 === true || bookCurrency && 物品名 === "K点";
        if (物品名 === "金币") 物品名 = "金钱";
        if (物品名 === "金钱" && !exactCurrency && (!bookCurrency || type61Death)
                && LinearCongruentialEngine.instance.randomCheck(_root.打怪掉钱机率)) {
            物品名 = "K点";
        }

        // 根据等级对金币和K点掉落进行数量补正
        if (!exactCurrency && 物品名 === "K点"){
            if (数量 < 10){
                数量 += 10;
            }
            if (!_root.isEasyMode()){
                var 数量上限 = 50 + _root.等级 * _root.等级 * 10;
                if (数量 > 数量上限){
                    数量 = 数量上限 + random((数量 - 数量上限) / 100);
                }
                if (_root.isChallengeMode()){
                    数量 = Math.floor(数量 * 0.5);
                }
            }
        }else if (!exactCurrency && 物品名 === "金钱"){
            if (数量 < 10){
                数量 += 10;
            }
            if (!_root.isEasyMode()){
                var 数量上限 = 50 + _root.等级 * 3000;
                if (数量 > 数量上限){
                    数量 = 数量上限 + random((数量 - 数量上限) / 5);
                }
                if (_root.isChallengeMode()){
                    数量 = Math.floor(数量 * 0.5);
                }
            }
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
        
        // 纳入深度管理器，正确参与 Y 排序
        DepthManager.instance.updateDepth(pickupItem, pickupItem._y);
        pickupItem.焦点高亮框.gotoAndPlay(
            LinearCongruentialEngine.instance.randomInteger(1, 59));
        
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

        var mousePickUpFunc:Function = function():Void {
            if (this.area == undefined) return;

            var hit:Boolean = false;
            if (_root.鼠标代理 != undefined && _root.鼠标代理.命中目标 != undefined) {
                hit = _root.鼠标代理.命中目标(this.area, false);
            } else {
                hit = this.area.hitTest(_root._xmouse, _root._ymouse, false);
            }

            if (hit) {
                self.pickup(this, null, false);
            }
        };
        
        var resetFunc:Function = function():Void {
            var mc:MovieClip = this.焦点高亮框;
            mc.stop();
            mc._visible = false;
        };
        
        this.dispatcher.subscribeGlobal("interactionKeyDown", pickUpFunc, pickupItem);
        this.dispatcher.subscribeGlobal("interactionKeyUp", resetFunc, pickupItem);
        this.dispatcher.subscribeGlobal("interactionMouseDown", mousePickUpFunc, pickupItem);

        // 可拾取物内部函数
        pickupItem.itemData = _root.getItemData(物品名 === "金钱" ? "金币" : 物品名);
        pickupItem.displayName = pickupItem.itemData.displayname;
        
        this.count++;
    }
    
    /**
     * 获取当前拾取物数量
     */
    public function getCount():Number {
        return this.count;
    }
    
    /**
     * 获取拾取物字典
     */
    public function getPickupItemDict():Object {
        return this.pickupItemDict;
    }
    
    /**
     * 清理资源
     */
    public function destroy():Void {
        if (this.dispatcher) {
            this.dispatcher.destroy();
            this.dispatcher = null;
        }
        this.pickupItemDict = null;
    }
}
