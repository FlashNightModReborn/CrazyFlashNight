/*
1.作为狂野/长柄/镰刀/步枪四种形态切换的武器使用
2.收纳时处于收纳形态，拔出时切换到对应的武器形态，冷兵器状态下按武器变形键在三种形态间循环切换
3.装备死者之手且长枪槽为空时，将死者之手同时视作长枪槽武器，可以切换到长枪形态进行射击
4.释放主动技能（下称“一阶段技能”）时进入强化状态（制御板展开），获得强化效果，一定时间或攻击次数后强制进入冷却；强化状态下切换武器将强制结束技能与强化
5.切换形态时改变武器补正、伤害类型、动作模组与刀口位置，适应对应的攻击距离（钝器近距离、镰刀中距离、长矛远距离）
6.强化状态下可以释放二阶段技能，二阶段技能释放后强制结束强化状态并进入冷却
 */

// 仅登记 class 方法；避免将状态机及持久闭包展开进启动帧。
_root.装备生命周期函数.死者之手推进组件帧 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手推进组件帧;
_root.装备生命周期函数.死者之手判定武器模式 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手判定武器模式;
_root.装备生命周期函数.死者之手是否持有模式 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手是否持有模式;
_root.装备生命周期函数.死者之手配置借用长枪 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手配置借用长枪;
_root.装备生命周期函数.死者之手更新形态属性 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手更新形态属性;
_root.装备生命周期函数.死者之手同步视觉 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手同步视觉;
_root.装备生命周期函数.死者之手触发超载雷电 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手触发超载雷电;
_root.装备生命周期函数.死者之手装载阶段战技 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手装载阶段战技;
_root.装备生命周期函数.死者之手开启超载 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手开启超载;
_root.装备生命周期函数.死者之手结束超载 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手结束超载;
_root.装备生命周期函数.死者之手切换冷兵器形态 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手切换冷兵器形态;
_root.装备生命周期函数.死者之手处理武器切换 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手处理武器切换;
_root.装备生命周期函数.死者之手卸载 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手卸载;
_root.装备生命周期函数.死者之手初始化 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手初始化;
_root.装备生命周期函数.死者之手周期 = org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController.死者之手周期;
