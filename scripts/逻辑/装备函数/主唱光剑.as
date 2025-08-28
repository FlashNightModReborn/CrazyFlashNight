import org.flashNight.neur.Event.*;
import org.flashNight.gesh.object.*;


_root.装备生命周期函数.主唱光剑初始化 = function(ref:Object, param:Object) 
{
   var target:MovieClip = ref.自机;
   var saberLabel:String = "武器类型名" + target.刀;
   var animFrameName:String = target.刀 + "动画帧";
   
   ref.saberLabel = saberLabel;
   ref.animFrameName = animFrameName;
   ref.animDuration = 15;
   ref.transformInterval = 1000;
   ref.timestampName = target.刀 + "时间戳";
   
   // 初始化基础伤害数据
   if (isNaN(target.话筒支架基础伤害)) {
       target.话筒支架基础伤害 = target.刀属性.power;
       target[saberLabel] = "光剑";
       
       // 读取保存的武器类型
       if (_root.控制目标 == target._name && _root[saberLabel] == "话筒支架") {
           target[saberLabel] = "话筒支架";
           target.刀属性.power = target.话筒支架基础伤害 * 0.8;
       }
   }
   
   // 初始化动画帧
   if (target[animFrameName] == undefined) {
       target[animFrameName] = 1;
   }

   var saberBladeYOffset1:Array = [363, 164];
   var saberBladeYOffset3:Array = [216, 102];
   ref.saberBladeYOffset1 = saberBladeYOffset1;
   ref.saberBladeYOffset3 = saberBladeYOffset3;


   target.dispatcher.subscribe("StatusChange", function(unit) {
       _root.装备生命周期函数.主唱光剑动画更新(ref);
       // _root.发布消息("主唱光剑状态变更为[" + unit.状态 + "]");
   });
};

_root.装备生命周期函数.主唱光剑周期 = function(ref:Object, param:Object) {
   _root.装备生命周期函数.移除异常周期函数(ref);
   
   var target:MovieClip = ref.自机;
   var saber:MovieClip = target.刀_引用;
   
   // 武器形态切换检测
   if (Key.isDown(_root.武器变形键) && target.攻击模式 == "兵器") {
       if (!target[ref.timestampName] || getTimer() - target[ref.timestampName] > ref.transformInterval) {
           target[ref.timestampName] = getTimer();
           _root.装备生命周期函数.主唱光剑切换武器形态(ref);
       }
   }
   
   // 动画控制和更新
   _root.装备生命周期函数.主唱光剑动画控制(ref);
}


// 武器形态切换函数
_root.装备生命周期函数.主唱光剑切换武器形态 = function(ref:Object) {
   var target:MovieClip = ref.自机;
   
   if (target[ref.saberLabel] == "光剑") {
       // 切换为话筒支架
       target[ref.saberLabel] = "话筒支架";
       target.刀属性.power = target.话筒支架基础伤害 * 0.8;
   } else {
       // 切换为光剑
       target[ref.saberLabel] = "光剑";
       target.刀属性.power = target.话筒支架基础伤害;
   }
   
   _root.发布消息("话筒支架武器类型切换为[" + target[ref.saberLabel] + "]");
   
   // 保存武器类型到全局
   if (_root.控制目标 == target._name) {
       _root[ref.saberLabel] = target[ref.saberLabel];
   }
};

// 动画控制函数 - 负责决定动画状态
_root.装备生命周期函数.主唱光剑动画控制 = function(ref:Object) {
   var target:MovieClip = ref.自机;
   
   // 判断是否应该展开光剑
   var shouldExpand = function() {
       if (!_root.兵器使用检测(target) && target.攻击模式 != "兵器" || target[ref.saberLabel] == "话筒支架") {
           return false;
       }
       
       var currentFrame = target.man._currentframe;
       if (currentFrame >= 370 && currentFrame <= 413) {
           // 攻击动作中快速展开到2/3
           target[ref.animFrameName] = Math.max(target[ref.animFrameName], Math.floor(ref.animDuration * 2 / 3));
       }
       
       return true;
   };
   
   // 根据状态调整动画帧值
   if (shouldExpand()) {
       if (target[ref.animFrameName] < ref.animDuration) {
           target[ref.animFrameName]++;
       }
   } else {
       if (target[ref.animFrameName] > 1) {
           target[ref.animFrameName]--;
       }
   }
   
   // 调用动画更新函数
   _root.装备生命周期函数.主唱光剑动画更新(ref);
};

// 动画更新函数 - 负责实际更新动画显示（包括动画帧和刀口位置）
_root.装备生命周期函数.主唱光剑动画更新 = function(ref:Object) {
   var target:MovieClip = ref.自机;
   var saber:MovieClip = target.刀_引用;
   
   // 更新动画帧
   if (saber.动画) {
       saber.动画.gotoAndStop(target[ref.animFrameName]);
   }
   
   // 更新刀口位置
   var isLightsaber:Boolean = (target[ref.saberLabel] == "光剑");
   var yOffsetIndex:Number = Number(isLightsaber);

   if (saber.刀口位置1) {
       saber.刀口位置1._y = ref.saberBladeYOffset1[yOffsetIndex];
   }
   
   if (saber.刀口位置3) {
       saber.刀口位置3._y = ref.saberBladeYOffset3[yOffsetIndex];
   }
};