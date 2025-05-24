_root.改装系统当前页数 = 1;
_root.改装系统向前翻页 = function(){
   if(_root.改装系统当前页数 > 1)
   {
      _root.改装系统当前页数 -= 1;
      _parent.删除奖励块();
      _parent.排列奖励块(_root.改装系统当前页数);
   }
   //_root.发布消息("1");
}
_root.改装系统向后翻页 = function(){
	if(_parent.改装清单.length >= _root.改装系统当前页数 * _parent.每页显示数)
   {
      _root.改装系统当前页数 += 1;
      _parent.删除奖励块();
      _parent.排列奖励块(_root.改装系统当前页数);
   }
   //_root.发布消息("1");
}


_root.挂载物品完整装扮 = function()
{
   var 显示图标 = this.attachMovie(_parent.图标,"图标",this.getNextHighestDepth());
   var mask_size = 17;
   var border_thickness = 1; // 边框的厚度

   switch(_root.getItemData(_parent._parent.改装信息[1]).use)
   {
      case '长枪':
      case '手枪':
      case '刀':
         var maskMC:MovieClip = this.createEmptyMovieClip("maskMC", this.getNextHighestDepth());
         显示图标.gotoAndStop(2);
         显示图标._rotation += 45;
         显示图标._xscale = 显示图标._yscale = 50;

         // 绘制遮罩层
         maskMC.beginFill(0xFFFFFF);
         maskMC.moveTo(-mask_size, -mask_size);
         maskMC.lineTo(mask_size, -mask_size);
         maskMC.lineTo(mask_size, mask_size);
         maskMC.lineTo(-mask_size, mask_size);
         maskMC.lineTo(-mask_size, -mask_size);
         maskMC.endFill();
         显示图标.setMask(maskMC); // 将遮罩层应用到显示图标上

         // 创建并绘制边框
         var borderMC:MovieClip = this.createEmptyMovieClip("borderMC", this.getNextHighestDepth());
         borderMC.lineStyle(border_thickness, 0xFFFFFF); // 设置线条样式
         borderMC.moveTo(-mask_size, -mask_size);
         borderMC.lineTo(mask_size, -mask_size);
         borderMC.lineTo(mask_size, mask_size);
         borderMC.lineTo(-mask_size, mask_size);
         borderMC.lineTo(-mask_size, -mask_size);

         显示图标._x = maskMC._x = borderMC._x -= 2;
         break;

      default:
         显示图标._xscale = 显示图标._yscale = 145;
         显示图标._x -= 1;
         break;
   }

   if(this.图标._x != undefined) 
   {
      this.基本款._visible = 0;
   } else 
   {
      this.基本款._visible = 1;
   }
}
