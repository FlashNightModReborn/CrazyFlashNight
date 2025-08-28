import org.flashNight.neur.Event.*;
import org.flashNight.gesh.object.*;

_root.装备生命周期函数.主唱光剑初始化 = function(ref:Object, param:Object) 
{
   var saberLabel:String = "武器类型名" + ref.装备名称;
   ref.saberLabel = saberLabel;


   var saberBladeYOffset1:Array = [363, 164];
   var saberBladeYOffset3:Array = [216, 102];
   ref.saberBladeYOffset1 = saberBladeYOffset1;
   ref.saberBladeYOffset3 = saberBladeYOffset3;
};

_root.装备生命周期函数.主唱光剑周期 = function(ref:Object, param:Object) {
   _root.装备生命周期函数.主唱光剑动态调整光剑刀口(ref);
}


_root.装备生命周期函数.主唱光剑动态调整光剑刀口 = function(ref:Object) {
   var target:MovieClip = ref.自机;
   var saber:MovieClip = target.刀_引用;

   var isLightsaber:Boolean = (target[ref.saberLabel] == "光剑");

   var yOffsetIndex:Number = Number(isLightsaber);

   saber.刀口位置1._y = ref.saberBladeYOffset1[yOffsetIndex];
   saber.刀口位置3._y = ref.saberBladeYOffset3[yOffsetIndex];

   // _root.服务器.发布服务器消息(ObjectUtil.toString(target.刀))
   _root.发布消息(ref.saberLabel, target[ref.saberLabel] ,isLightsaber,yOffsetIndex,saber.刀口位置1._y,saber.刀口位置3._y);

}