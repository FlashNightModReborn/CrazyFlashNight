

// 资源箱根回调的唯一源码；asLoader frame39 与 Chest S0 TestLoader 共用此 include。
// S0 精确 fixture 必须在所有旧滚奖、container 与 UI 逻辑之前 fail-closed。

_root.地图元件.资源箱开启脚本 = function(target:MovieClip) {
    target._visible = true;

    var chestS0Result:Object = org.flashNight.arki.scene.ChestSessionService.handleOpenFrame(target);
    if (chestS0Result.handled) {
        org.flashNight.arki.scene.ChestS0SocketBridge.handleAuthorityTransition(chestS0Result);
        return;
    }

    // recovery 比当前箱优先；任何网格箱都只能重新呈现那份尚未取空的唯一 inventory。
    var lootGuard:Object = org.flashNight.arki.item.LootContainerService.guardAnyGridFixture(target);
    if (lootGuard.handled) {
        // LOOT_SUSPENDED 的 authored callback 若被重复触发只能停住；重开必须回到
        // InteractionHandler exact anchor，绝不把 suspend 误解释成 legacy recovery。
        if (lootGuard.recovery === true) {
            if (lootGuard.rendererConfirmed === true) {
                _root.地图元件.显示Web战利品旧界面(lootGuard);
            } else {
                _root.地图元件.回退Web战利品到旧界面(null);
            }
        }
        return;
    }
    if (_root.地图元件.具有Web战利品标记(target)) {
        var activated:Object = org.flashNight.arki.item.LootContainerService.activateReservedOpen(target);
        if (activated.success) {
            if (activated.duplicate !== true
                    && !org.flashNight.arki.item.LootContainerService.requestOpenPanel()) {
                _root.地图元件.回退Web战利品到旧界面(target);
            }
        } else {
            _root.地图元件.回退Web战利品到旧界面(target);
        }
        return;
    }

    // 如果有物品栏则弹出，否则爆出物品
    if (target.row > 0 && target.col > 0) {
        _root.地图元件.掉落物转换为物品栏(target);
    } else {
        target.掉落物判定 = _root.敌人函数.掉落物判定;
        target.掉落物品 = _root.敌人函数.掉落物品;
        target.掉落物判定();
    }
}

_root.地图元件.资源箱破碎脚本 = function(target:MovieClip) {
    target._visible = true;

    var chestS0Result:Object = org.flashNight.arki.scene.ChestSessionService.handleBreakFrame(target);
    if (chestS0Result.handled) {
        org.flashNight.arki.scene.ChestS0SocketBridge.handleAuthorityTransition(chestS0Result);
        return;
    }

    var lootGuard:Object = org.flashNight.arki.item.LootContainerService.guardAnyGridFixture(target);
    if (lootGuard.handled) {
        if (lootGuard.recovery === true) {
            if (lootGuard.rendererConfirmed === true) {
                _root.地图元件.显示Web战利品旧界面(lootGuard);
            } else {
                _root.地图元件.回退Web战利品到旧界面(null);
            }
        }
        return;
    }

    // rollout marker 即使因资产/linkage 漂移落到破碎回调，也不能绕回直接爆落旧链。
    if (_root.地图元件.具有Web战利品标记(target)) {
        var activated:Object = org.flashNight.arki.item.LootContainerService.activateReservedOpen(target);
        if (activated.success) {
            if (activated.duplicate !== true
                    && !org.flashNight.arki.item.LootContainerService.requestOpenPanel()) {
                _root.地图元件.回退Web战利品到旧界面(target);
            }
        } else {
            _root.地图元件.回退Web战利品到旧界面(target);
        }
        return;
    }

    // 不尝试弹出物品栏，直接爆出物品
    target.掉落物判定 = _root.敌人函数.掉落物判定;
    target.掉落物品 = _root.敌人函数.掉落物品;
    target.掉落物判定();
}
