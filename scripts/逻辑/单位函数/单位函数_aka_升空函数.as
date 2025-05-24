
//传入的值分别为作用的对象、初始上升速度、升空的类型，可用于击飞/已起跳时/已升空时额外一次性提升高度等（类型传入0），或者喷气背包等从原地开始的多次可控的上升（类型传入1）
//例如  fly(this,-垂直速度,0)
_root.fly = function(Obj,flySpeed,type,left,right,up,down){
	//_root.发布调试消息("测试测试/开始"+Obj.flySpeed+"/"+Obj._y+"/"+Obj.起始Y+"/"+Obj.Z轴坐标);
	flySpeed = flySpeed ? flySpeed : 10;
	type = type ? type : 0;
	left = left ? left : 0;
	right = right ? right : 0;
	//这里是水平上下，不是高度
	up = up ? up : 0;
	down = down ? down : 0;
	if(Obj.状态.indexOf("跑")>-1){
		runSpeed =  Obj.跑X速度;
	}else{
		runSpeed =0;
	}
	if(left>0){
		left+=runSpeed;
		if(Obj.leftFlySpeed<left||Obj.leftFlySpeed == undefined){
			Obj.leftFlySpeed = left;
		}
	}else if(right>0){
		right+=runSpeed;
		if(Obj.rightFlySpeed<right||Obj.rightFlySpeed == undefined){
			Obj.rightFlySpeed = right;
		}
	}
	if(up>0){
		Obj.upFlySpeed = up;
	}else if(down>0){
		Obj.downFlySpeed = down;
	}
	_root.fly_isFly2 = false;
	_root.fly_isFly2 = false;
	/*
	if(Obj.flySpeed!=undefined&&Obj.flySpeed!=0){
		Obj.flySpeed = flySpeed;
	_root.发布调试消息("测试测试/已有速度"+v+"/"+Obj._y+"/"+Obj.flySpeed);
	}
	*/
	if(!Obj.flySpeed||Obj.flySpeed<flySpeed){
		Obj.flySpeed = flySpeed;
	}
	/*
   if(_root.fly_isFly == true and Obj._name == _root.gameworld[_root.控制目标]._name)
   {
      Obj._y = _root.fly_y;
   }
   */
	if(type == 0){
		Obj.temp_fly_frame = 0;
		Obj.flyType = 0;
		Obj.flyInFlying =function(){
			//type为0时该单位已起飞，已受到重力加速度影响，有起始Y
			if(Obj.起始Y!=undefined){
				temp起始Y = Obj.起始Y;
			}else if(Obj.man.起始Y!=undefined){
				temp起始Y = Obj.man.起始Y;
			}else{
				temp起始Y = Obj.Z轴坐标;
			}
			if(Obj.temp_fly_frame<10){
				if(Obj._y <temp起始Y-3){
					Obj.temp_fly_frame+=10;
				}
				Obj.temp_fly_frame+=1;
				if(Obj.temp_fly_frame==9){
					//clearInterval(Obj.持续升空);
					_root.帧计时器.移除任务(Obj.持续升空);
				}
			}else if(Obj._y <temp起始Y-3){
				/*
				Obj._y -= Obj.flySpeed;
				*/
				if(!Obj.hasChangedFlyType0){
					if(Obj.垂直速度!=undefined){
						Obj.垂直速度 = -5-Obj.flySpeed;
						Obj.hasChangedFlyType0 = true;
					}else if(Obj.man.垂直速度!=undefined){
						Obj.man.垂直速度 = -5-Obj.flySpeed;
						Obj.hasChangedFlyType0 = true;
					}
					
				}
			}else{
				Obj.flySpeed = 0;
				Obj.flyType = -1;
				_root.fly_isFly1 = false;
				_root.fly_isFly2 = false;
				//clearInterval(Obj.持续升空);
				_root.帧计时器.移除任务(Obj.持续升空);
				return;
			}
			if(Obj._y==undefined){
				Obj.flySpeed = 0;
				Obj.flyType = -1;
				_root.fly_isFly1 = false;
				_root.fly_isFly2 = false;
				//clearInterval(Obj.持续升空);
				_root.帧计时器.移除任务(Obj.持续升空);
				return;
			}
			if(Obj.状态!="击倒"&&Obj.temp_fly_frame>=10){
				Obj.flySpeed = 0;
				Obj.flyType = -1;
				_root.fly_isFly1 = false;
				_root.fly_isFly2 = false;
				//clearInterval(Obj.持续升空);
				_root.帧计时器.移除任务(Obj.持续升空);
				return;
			}
			/*
			if(Obj.垂直速度!=undefined){
				当前垂直速度 = Obj.垂直速度;
			}else{
				当前垂直速度 = Obj.man.垂直速度;
			}
			if(Obj.状态 == "击倒" && (Obj.temp_垂直速度 * 当前垂直速度 < 0) && 当前垂直速度 < 0 && Obj.temp_fly_frame >= 10){
				Obj.temp_垂直速度 = 0;
				Obj.flySpeed = 0;
				Obj.flyType = -1;
				_root.fly_isFly1 = false;
				_root.fly_isFly2 = false;
				clearInterval(Obj.持续升空);
				return;
			}else{
				Obj.temp_垂直速度 = 当前垂直速度;
			}
			//_root.发布调试消息("测试测试/正在击飞"+flySpeed+"/"+Obj._y+"/"+Obj.起始Y+"/"+Obj.man.起始Y+"/"+temp起始Y+"/"+Obj.flySpeed+"/"+Obj.状态+"/"+Obj.temp_fly_frame);
			*/
		}
		//clearInterval(Obj.持续升空);
		_root.帧计时器.移除任务(Obj.持续升空);
		if(Obj.垂直速度>0 and Obj.垂直速度!=undefined){
			Obj.垂直速度 = Obj.起跳速度;
		}
		Obj.hasChangedFlyType0 = false;
		//Obj.持续升空 = setInterval(Obj.flyInFlying, 33);
		Obj.持续升空 = _root.帧计时器.添加循环任务(Obj.flyInFlying, 33);

			
	}else if(type ==1){
		
		/*
		if(Obj.状态.indexOf("击倒")>-1 ||Obj.状态.indexOf("倒地")>-1){
			return;
		}
		Obj.flySpeed = flySpeed;
		Obj.flyType = 1;
		//_root.发布调试消息("/"+Obj._y+"/"+Obj.起始Y+"/"+Obj.飞行浮空+"/"+Obj.浮空);
		if(Obj.状态.indexOf("跳")==-1){
			if(Obj.状态.indexOf("攻击")==-1){ // and (_root.fly_isFly1 == true ||  _root.fly_isFly2 == true)
				Obj.动画完毕();
			}
			if(!Obj.飞行浮空 and !Obj.浮空){
				Obj.起始Y = Obj._y;
				Obj._y -= Obj.flySpeed;
				//_root.发布调试消息("_y"+"/"+Obj._y+"/"+Obj.起始Y);
			}else{
				Obj.起始Y = Obj.Z轴坐标;
				Obj._y -= Obj.flySpeed;
				//_root.发布调试消息("Z"+"/"+Obj._y+"/"+Obj.起始Y);

			}
			Obj.垂直速度 = 0;
		}else if(Obj.垂直速度>-1){
			Obj.垂直速度 = -1;
		}
		Obj.飞行浮空 = true;
		Obj.flyOnGround =function(){
			if(Obj.状态.indexOf("跳")==-1 and Obj.状态!="技能"){
				if(Obj.额外重力加速度 == 0){
					if(Obj.状态.indexOf("枪")==-1){
						Obj.额外重力加速度 =  _root.重力加速度;
						Obj.flySpeed = 0;
						Obj.flySpeed = 0;
						Obj.飞行浮空 = false;
						Obj.浮空 = false;
						Obj.flyType = -1;
						Obj._rotation = 0;
						_root.fly_isFly1 = false;
						_root.fly_isFly2 = false;
						Obj._y =Obj.起始Y;
						Obj.shadow._x =-15.2;
						Obj.shadow._y =233.05;
						Obj.shadow._rotation =0;
						//_root.发布调试消息("测试测试/跳跃落地"+Obj.状态+"/"+Obj.额外重力加速度+"/"+Obj.upFlySpeed+"/"+Obj.飞行浮空+"/"+Obj._y+"/"+Obj.起始Y);
						clearInterval(Obj.持续升空);
						return;
					}else{
						//_root.发布调试消息("测试测试/跳跃落地"+Obj.状态+"/"+Obj.额外重力加速度+"/"+Obj.flySpeed+"/"+Obj.垂直速度暂存);
						Obj.flySpeed = Obj.flySpeed- Obj.垂直速度暂存;
					}
				}
				Obj.额外重力加速度 =  _root.重力加速度;
			}else{
				Obj.额外重力加速度 =  0;
				Obj.垂直速度暂存 =Obj.垂直速度;
				if(_root.技能浮空 == false and Obj.状态=="技能"){
					Obj.flySpeed = -1;
					Obj.skillShadow._x =-15.2;
					Obj.skillShadow._y =233.05;
					Obj.skillShadow._rotation =0;
					
					//_root.是否阴影 == true;
					//Obj.skillOriShadow._visible =1;
					//Obj.skillShadow._visible =0;
					
				}
			}
			//_root.发布调试消息(Obj.shadow._x+"/"+Obj.shadow._y+"/"+Obj.shadow._visible+"/"+Obj.状态+"/"+_root.是否阴影);
			//_root.发布调试消息("测试测试/跳跃垂直速度"+Obj.状态+"/"+Obj.额外重力加速度+"/"+Obj.flySpeed+"/"+Obj.垂直速度);
			//_root.发布调试消息(Obj._rotation+"/"+Obj.额外重力加速度+"/"+Obj.起始Y);
			//type为1时该单位未起飞，未受到重力加速度影响，无起始Y。需要额外计算重力加速度
			if(Obj._y <Obj.起始Y)
			{
				Obj._y -= Obj.flySpeed;
				Obj.flySpeed -= Obj.额外重力加速度;
				Obj.浮空 = true;
				Obj.飞行浮空 = true;
			}else{
				Obj._y =Obj.起始Y;
				Obj.flySpeed = 0;
				Obj.浮空 = false;
				Obj.飞行浮空 = false;
				Obj.flyType = -1;
				_root.效果("灰尘1",Obj._x,Obj._y,Obj._xscale);
				Obj._rotation = 0;
				_root.fly_isFly1 = false;
				_root.fly_isFly2 = false;
				Obj.shadow._x =-15.2;
				Obj.shadow._y =233.05;
				Obj.shadow._rotation =0;
				clearInterval(Obj.持续升空);
				for(i = 0;i<_root.主角的升空函数.length;i++){
					clearInterval(_root.主角的升空函数[i]);
				}
				_root.主角的升空函数 = [];
				//if(Obj = _root.gameworld[_root.控制目标]){
					//clearInterval(_root.gameworld[_root.控制目标].持续升空);
				//}
			}
			if(Obj.leftFlySpeed>0){
				Obj._x -= Obj.leftFlySpeed;
				Obj.leftFlySpeed-=1;
				Obj._rotation = -Obj.leftFlySpeed;
			}
			if(Obj.rightFlySpeed>0){
				Obj._x += Obj.rightFlySpeed;
				Obj.rightFlySpeed-=1;
				Obj._rotation = Obj.rightFlySpeed;
			}
			if(Obj.攻击模式.indexOf("枪")==-1 || Key.isDown(_root.奔跑键) ){
				if(Obj.upFlySpeed>0){
					Obj.跳跃上下移动("上",Obj.upFlySpeed/2);
					Obj.upFlySpeed-=1;
					//_root.发布调试消息("测试测试/正在飞上"+Obj.upFlySpeed+"/"+up+"/"+Obj.downFlySpeed+"/"+down);
				}
				if(Obj.downFlySpeed>0){
					Obj.跳跃上下移动("下",Obj.downFlySpeed/2);
					Obj.downFlySpeed-=1;
					//_root.发布调试消息("测试测试/正在飞下"+Obj.upFlySpeed+"/"+up+"/"+Obj.downFlySpeed+"/"+down);
				}
			}
			
			
			if( Obj.攻击模式.indexOf("枪")>-1 and !Key.isDown(_root.奔跑键)  and Obj.状态.indexOf("攻击")==-1 ){
				
				if(Obj._xscale>0){
        	 		if(Key.isDown(Obj.上键) and Obj._rotation>-50)
      		 		{
     		   		    Obj._rotation -=3;
   		     	 	}
    		  		else if(Key.isDown(Obj.下键)  and Obj._rotation< 50)
    		  		{
     		    	   Obj._rotation += 3;
   		     		}
				}else{
        	 		if(Key.isDown(Obj.上键) and Obj._rotation< 50)
      		 		{
     		   		    Obj._rotation -= -3;
   		     	 	}
    		  		else if(Key.isDown(Obj.下键)  and Obj._rotation>-50)
    		  		{
     		    	   Obj._rotation += -3;
   		     		}
				}
			}
			
			//尝试用函数来判断阴影位置
			
			//var flyShadow = Obj.man.getInstanceAtDepth(2);
			//var flyShadow = _root.findLowestDepth(Obj.man);
			//var radians = -flyShadow._rotation ;
			//var flyShadow = Obj.shadow;
			
			if(!Obj.shadow._visible and Obj.skillShadow._visible){
				var flyShadow = Obj.skillShadow;
				if(Obj._rotation==0){
					flyShadow._y = 233.05 + (Obj.起始Y - Obj._y -Obj.垂直速度+ Obj.flySpeed) * 3.5;
				}else{
    	  			flyShadowBaseY = 233.05 + (Obj.起始Y - Obj._y -Obj.垂直速度+ Obj.flySpeed) * 3.5;
					if(Obj._xscale>0){
						flyShadow._rotation=-Obj._rotation;
					}else{
						flyShadow._rotation=Obj._rotation;
					}
						var radians:Number = flyShadow._rotation * Math.PI / 180;
					flyShadow._y =  flyShadowBaseY*Math.cos(radians);
					flyShadow._x = -flyShadowBaseY*Math.sin(radians);
					//_root.发布消息("测试测试/"+flyShadowBaseY+"/"+flyShadow._y +"/"+Math.sin(radians));
				}
			}else{
				var flyShadow = Obj.shadow;
				if(Obj._rotation==0){
					flyShadow._y = 233.05 + (Obj.起始Y - Obj._y) * 3.5;
				}else{
      				flyShadowBaseY = 233.05 + (Obj.起始Y - Obj._y) * 3.5;
					if(Obj._xscale>0){
						flyShadow._rotation=-Obj._rotation;
					}else{
						flyShadow._rotation=Obj._rotation;
					}
						var radians:Number = flyShadow._rotation * Math.PI / 180;
					flyShadow._y =  flyShadowBaseY*Math.cos(radians);
					flyShadow._x = -flyShadowBaseY*Math.sin(radians);
				}
			}
			
			
			//flyShadow._x = -_root.calculateXOffset(flyShadow._y,flyShadow._rotation)
			//_root.发布调试消息("测试测试/正在飞"+flyShadow+"/"+_root.findLowestDepth(Obj.man)+"/"+Obj.man.getDepth()+"/"+flyShadow._y+"/"+Obj.起始Y+"/"+Obj._y);
			
			//_root.发布调试消息("测试测试/正在飞"+_root.findLowestDepth(Obj.man).getDepth()+"/"+Obj.man.getDepth());

			
			//if(left>0 || right > 0){
			//_root.发布调试消息("测试测试/正在飞行"+flySpeed+"/"+Obj._y+"/"+Obj.起始Y+"/"+Obj.flySpeed+"/"+Obj.状态+"/"+left+"/"+right+"/"+up+"/"+down);
			//}
			//_root.发布调试消息("测试测试/正在飞行"+flySpeed+"/"+Obj._y+"/"+Obj.起始Y+"/"+Obj.man.起始Y+"/"+temp起始Y+"/"+Obj.flySpeed+"/"+Obj.状态+"/"+Obj.temp_fly_frame);
			

		}
		clearInterval(Obj.持续升空);
		
		//if(Obj = _root.gameworld[_root.控制目标]){
			//clearInterval(_root.gameworld[_root.控制目标].持续升空);
		//}
		
		
		Obj.持续升空 = setInterval(Obj.flyOnGround, 33);
		_root.主角的升空函数.push(Obj.持续升空);
		
		if(!Obj.shadow._visible and Obj.skillShadow._visible){
				var flyShadow = Obj.skillShadow;
				if(Obj._rotation==0){
					flyShadow._y = 233.05 + (Obj.起始Y - Obj._y -Obj.垂直速度+ Obj.flySpeed) * 3.5;
				}
		}else{
				var flyShadow = Obj.shadow;
				if(Obj._rotation==0){
					flyShadow._y = 233.05 + (Obj.起始Y - Obj._y) * 3.5;
				}
		}
	*/
	}
}


_root.findLowestDepth =  function(obj:MovieClip):MovieClip {
  var lowestDepth:Number = obj.getNextHighestDepth();
  var lowestDepthObj:MovieClip = obj;

  for (var i:Number = obj.getNextHighestDepth() - 1; i >= obj.getDepth(); i--) {
    var childObj:MovieClip = obj.getInstanceAtDepth(i);
    if (childObj && childObj._visible) {
      lowestDepth = i;
      lowestDepthObj = childObj;
    }
  }
  //_root.发布调试消息("测试测试/正在飞"+lowestDepth+"/"+lowestDepthObj);

  return lowestDepthObj;
}

_root.updateChildPosition = function(child:MovieClip, obj:MovieClip, initialY:Number):Void {
  // 获取子元件在旋转之前的位置和旋转角度
  var initialPos:Object = {x: child._x, y: child._y};
  var initialRotation:Number = child._rotation;
  
  // 将子元件的坐标系移动到 obj 的初始位置，并通过相反的角度将子元件旋转回原始方向
  child._x -= obj._x;
  child._y -= obj._y;
  child._rotation -= obj._rotation - initialRotation;
  
  // 计算子元件在 obj 旋转之后的位置
  var radians:Number = obj._rotation * Math.PI / 180; // 将角度转换为弧度
  var yOffset:Number = initialY - obj._y; // 计算子元件在 obj 旋转之后的 y 偏移量
  var xOffset:Number = yOffset * Math.tan(radians); // 计算子元件在 obj 旋转之后的 x 偏移量
  
  var newPos:Object = {x: initialPos.x + xOffset, y: initialPos.y + yOffset};
  
  // 将子元件坐标系移回到全局坐标系，并将子元件设置为计算得到的位置和旋转角度
  child._x = newPos.x;
  child._y = newPos.y;
  child._rotation = initialRotation + obj._rotation;
}

_root.主角的升空函数 = [];


_root.jetpack = function(flySpeed, type, left, right, up, down)
{
         自机 = this;
		 flySpeed = flySpeed ? flySpeed : 10;
		 type = type ? type : 0;
		 left = left ? left : 0;
		 right = right ? right : 0;
		 up = up ? up : 0;
		 down = down ? down : 0;
		 runSpeed = 自机.状态.indexOf("跑") > -1 ? 自机.跑X速度 : 0;
         if(left > 0)
         {
            left += runSpeed;
            if(自机.leftFlySpeed < left || 自机.leftFlySpeed == undefined)
            {
               自机.leftFlySpeed = left;
            }
			if(!自机.按键检测(_root.奔跑键,0)){
               	自机._rotation = - 自机.leftFlySpeed;
			}
         }
         else if(right > 0)
         {
            right += runSpeed;
            if(自机.rightFlySpeed < right || 自机.rightFlySpeed == undefined)
            {
               自机.rightFlySpeed = right;
            }
			if(!自机.按键检测(_root.奔跑键,0)){
               自机._rotation = 自机.rightFlySpeed;
			}
         }
         if(up > 0)
         {
            自机.upFlySpeed = up;
         }
         else if(down > 0)
         {
            自机.downFlySpeed = down;
         }
         _root.fly_isFly2 = false;
         if(!自机.flySpeed || 自机.flySpeed < flySpeed)
         {
            自机.flySpeed = flySpeed;
         }
         if(自机.状态.indexOf("击倒") > -1 || 自机.状态.indexOf("倒地") > -1)
         {
            return undefined;
         }
         自机.flyType = 1;
         if(自机.状态.indexOf("跳") == -1)
         {
            if(自机.状态.indexOf("攻击") == -1 )
            {
               自机.动画完毕();
            }
            if(!自机.飞行浮空 && !自机.浮空)
            {
               自机.起始Y = 自机._y;
            }
            else
            {
               自机.起始Y = 自机.Z轴坐标;
            }
            自机._y -= 自机.flySpeed;
            自机.垂直速度 = 0;
         }
         else if(自机.垂直速度 > -1)
         {
            自机.垂直速度 = -1;
         }
         自机.飞行浮空 = true;
         自机.喷气背包开始飞行 = 1;
         if(!自机.shadow._visible && 自机.skillShadow._visible)
         {
            var _loc9_ = 自机.skillShadow;
            if(自机._rotation == 0)
            {
               _loc9_._y = 233.05 + (自机.起始Y - 自机._y - 自机.垂直速度 + 自机.flySpeed) * 3.5;
            }
         }
         else
         {
            _loc9_ = 自机.shadow;
            if(自机._rotation == 0)
            {
               _loc9_._y = 233.05 + (自机.起始Y - 自机._y) * 3.5;
            }
         }
};

_root.jetpackCheck = function()
{
         自机 = this;
         if(!自机.喷气背包气槽 && 自机.喷气背包气槽 != 0)
         {
            自机.喷气背包气槽 = 80;
         }
         if(自机.喷气背包气槽 < 80 && 自机.正在充气 == 2)
         {
            自机.喷气背包气槽 += 2;
         }
         else if(自机.喷气背包气槽 >= -25 && 自机.正在充气 == 0)
         {
            自机.喷气背包气槽 -= 10;
            if(自机.喷气背包气槽 <= 0)
            {
               自机.喷气背包气槽 = -30;
            }
         }
         else if(自机.喷气背包气槽 >= -25 && 自机.正在充气 == 1)
         {
            自机.喷气背包气槽 -= 8;
            if(自机.喷气背包气槽 <= 0)
            {
               自机.喷气背包气槽 = -25;
            }
         }
         自机.正在充气 = 2;
         if(自机.按键检测(_root.飞行键,0) == true && 自机.喷气背包气槽 > 0)
         {
            自机.正在充气 = 0;
            if(自机.喷气背包气槽 <= 5)
            {
               飞行速度 = 5;
            }
            else
            {
               飞行速度 = 10;
            }
            if(自机.按键检测(自机.左键,0))
            {
               自机.jetpack(飞行速度,1,15,0,0,0);
            }
            else if(自机.按键检测(自机.右键,0))
            {
               自机.jetpack(飞行速度,1,0,15,0,0);
            }
            if(自机.按键检测(自机.上键,0))
            {
               自机.jetpack(飞行速度,1,0,0,15,0);
            }
            else if(自机.按键检测(自机.下键,0))
            {
               自机.jetpack(飞行速度,1,0,0,0,15);
            }
            else
            {
               自机.jetpack(飞行速度,1);
            }
         }
         else if(自机.飞行浮空 && 自机.喷气背包气槽 > 0)
         {
            if(自机.按键检测(自机.左键,0))
            {
               自机.jetpack(5,1,10,0);
               自机.正在充气 = 1;
            }
            else if(自机.按键检测(自机.右键,0))
            {
               自机.jetpack(5,1,0,10);
               自机.正在充气 = 1;
            }
            //if(自机.按键检测(自机.上键,0) && ((自机.状态.indexOf("攻击") == -1 || 自机.状态.indexOf("枪") == -1) || 自机.按键检测(_root.奔跑键,0)))
            if(自机.按键检测(自机.上键,0) && (自机.状态.indexOf("枪") == -1 || 自机.按键检测(_root.奔跑键,0)))
            {
               自机.jetpack(5,1,0,0,10,0);
               自机.正在充气 = 1;
            }
            else if(自机.按键检测(自机.下键,0) && (自机.状态.indexOf("枪") == -1 || 自机.按键检测(_root.奔跑键,0)))
            {
               自机.jetpack(5,1,0,0,0,10);
               自机.正在充气 = 1;
            }
         }
         if(自机.喷气背包开始飞行 == 1)
         {
            if(自机.状态.indexOf("跳") == -1 && 自机.状态 != "技能")
            {
               if(自机.额外重力加速度 == 0)
               {
                  if(自机.状态.indexOf("枪") == -1)
                  {
                     自机.额外重力加速度 = _root.重力加速度;
                     自机.flySpeed = 0;
                     自机.flySpeed = 0;
                     自机.飞行浮空 = false;
                     自机.浮空 = false;
                     自机.flyType = -1;
                     自机._rotation = 0;
                     _root.fly_isFly1 = false;
                     _root.fly_isFly2 = false;
                     自机._y = 自机.起始Y;
                     自机.shadow._x = -15.2;
                     自机.shadow._y = 233.05;
                     自机.shadow._rotation = 0;
                     自机.喷气背包开始飞行 = 0;
                  }
                  自机.flySpeed -= 自机.垂直速度暂存;
               }
               自机.额外重力加速度 = _root.重力加速度;
            }
            else
            {
               自机.额外重力加速度 = 0;
               自机.垂直速度暂存 = 自机.垂直速度;
               if(_root.技能浮空 == false && 自机.状态 == "技能")
               {
                  自机.flySpeed = -1;
                  自机.skillShadow._x = -15.2;
                  自机.skillShadow._y = 233.05;
                  自机.skillShadow._rotation = 0;
               }
            }
            if(自机._y < 自机.起始Y)
            {
               自机._y -= 自机.flySpeed;
               自机.flySpeed -= 自机.额外重力加速度;
               自机.浮空 = true;
               自机.飞行浮空 = true;
            }
            else
            {
               自机._y = 自机.起始Y;
               自机.flySpeed = 0;
               自机.浮空 = false;
               自机.飞行浮空 = false;
               自机.flyType = -1;
               _root.效果("灰尘1",自机._x,自机._y,自机._xscale);
               自机._rotation = 0;
               _root.fly_isFly1 = false;
               _root.fly_isFly2 = false;
               自机.shadow._x = -15.2;
               自机.shadow._y = 233.05;
               自机.shadow._rotation = 0;
               自机.喷气背包开始飞行 = 0;
            }
            if(自机.leftFlySpeed > 0)
            {
               自机._x -= 自机.leftFlySpeed;
               自机.leftFlySpeed -= 1;
			   if(!自机.按键检测(_root.奔跑键,0) && 自机._rotation + 自机.leftFlySpeed < 11 &&  自机._rotation + 自机.leftFlySpeed > -11){
               		自机._rotation = - 自机.leftFlySpeed;
			   }
            }
            if(自机.rightFlySpeed > 0)
            {
               自机._x += 自机.rightFlySpeed;
               自机.rightFlySpeed -= 1;
			   if(!自机.按键检测(_root.奔跑键,0) && 自机._rotation - 自机.rightFlySpeed < 11 && 自机._rotation - 自机.rightFlySpeed > -11){
               		自机._rotation = 自机.rightFlySpeed;
			   }
            }
            if(自机.攻击模式.indexOf("枪") == -1 || 自机.按键检测(_root.奔跑键,0))
            {
               if(自机.upFlySpeed > 0)
               {
                  自机.跳跃上下移动("上",自机.upFlySpeed / 2);
                  自机.upFlySpeed -= 1;
               }
               if(自机.downFlySpeed > 0)
               {
                  自机.跳跃上下移动("下",自机.downFlySpeed / 2);
                  自机.downFlySpeed -= 1;
               }
            }
            //if(自机.攻击模式.indexOf("枪") > -1 && !自机.按键检测(_root.奔跑键,0) && 自机.状态.indexOf("攻击") == -1)
            if(自机.攻击模式.indexOf("枪") > -1 && !自机.按键检测(_root.奔跑键,0) && !自机.主手射击中 && !自机.副手射击中)
            {
               if(自机._xscale > 0)
               {
                  if(自机.按键检测(自机.上键,0) && 自机._rotation > -60)
                  {
                     自机._rotation -= 3;
                  }
                  else if(自机.按键检测(自机.下键,0) && 自机._rotation < 60)
                  {
                     自机._rotation += 3;
                  }
               }
               else if(自机.按键检测(自机.上键,0) && 自机._rotation < 60)
               {
                  自机._rotation -= -3;
               }
               else if(自机.按键检测(自机.下键,0) && 自机._rotation > -60)
               {
                  自机._rotation += -3;
               }
            }
            if(!自机.shadow._visible && 自机.skillShadow._visible)
            {
               var _loc3_ = 自机.skillShadow;
               if(自机._rotation == 0)
               {
                  _loc3_._y = 233.05 + (自机.起始Y - 自机._y - 自机.垂直速度 + 自机.flySpeed) * 3.5;
               }
               else
               {
                  flyShadowBaseY = 233.05 + (自机.起始Y - 自机._y - 自机.垂直速度 + 自机.flySpeed) * 3.5;
                  if(自机._xscale > 0)
                  {
                     _loc3_._rotation = - 自机._rotation;
                  }
                  else
                  {
                     _loc3_._rotation = 自机._rotation;
                  }
                  var _loc4_ = _loc3_._rotation * Math.PI / 180;
                  _loc3_._y = flyShadowBaseY * Math.cos(_loc4_);
                  _loc3_._x = (- flyShadowBaseY) * Math.sin(_loc4_);
               }
            }
            else
            {
               _loc3_ = 自机.shadow;
               if(自机._rotation == 0)
               {
                  _loc3_._y = 233.05 + (自机.起始Y - 自机._y) * 3.5;
               }
               else
               {
                  flyShadowBaseY = 233.05 + (自机.起始Y - 自机._y) * 3.5;
                  if(自机._xscale > 0)
                  {
                     _loc3_._rotation = - 自机._rotation;
                  }
                  else
                  {
                     _loc3_._rotation = 自机._rotation;
                  }
                  _loc4_ = _loc3_._rotation * Math.PI / 180;
                  _loc3_._y = flyShadowBaseY * Math.cos(_loc4_);
                  _loc3_._x = (- flyShadowBaseY) * Math.sin(_loc4_);
               }
            }
         }
};

