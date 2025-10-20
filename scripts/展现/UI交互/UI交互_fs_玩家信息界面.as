import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.gesh.string.StringUtils;

_root.UI系统 = {};
_root.UI系统.血条刷新显示 = function() 
{
    var 控制对象 = TargetCacheManager.findHero();
    var 血槽数字当前HP = 控制对象.hp;
    var 血槽数字最大HP = 控制对象.hp满血值;

    if (isNaN(血槽数字当前HP) || isNaN(血槽数字最大HP)) return;

    var 血条格数 = 128;
    var 血量比 = 血槽数字当前HP / 血槽数字最大HP; // 计算HP百分比

    // this.gotoAndStop(Math.max(1, 血条格数 + 1 - Math.floor(血量比 * 血条格数))); // 控制血条动画

    this.frame = Math.max(1, 血条格数 + 1 - Math.floor(血量比 * 血条格数)); // 控制血条动画

    this.HP当前值.text = Math.floor(血槽数字当前HP); // 刷新血槽数字
    this.HP最大值.text = Math.floor(血槽数字最大HP);
    this.HP百分比.text = Math.floor(血量比 * 100);
}

_root.UI系统.蓝条刷新显示 = function() 
{
    var 控制对象 = TargetCacheManager.findHero();
    var 蓝条数字当前MP = 控制对象.mp;
    var 蓝条数字最大MP = 控制对象.mp满血值;

	if (isNaN(蓝条数字当前MP) || isNaN(蓝条数字最大MP)) return;

    // 格式化当前MP和最大MP为五位数，前面补零
    var 格式化当前MP = StringUtils.padStart(String(Math.floor(蓝条数字当前MP)), 5, "0");
    var 格式化最大MP = StringUtils.padStart(String(Math.floor(蓝条数字最大MP)), 5, "0");
    var 蓝量比 = 蓝条数字当前MP / 蓝条数字最大MP; // 计算MP百分比
	var 蓝条格数 = 100;

    this.MP数据显示.text = 格式化当前MP + "/" + 格式化最大MP;
    this.当前MP.text = Math.floor(蓝条数字当前MP);
    this.最大MP.text = Math.floor(蓝条数字最大MP);
    this.MP百分比.text = Math.floor(蓝量比 * 100) + "%"; 

    // this.gotoAndStop(Math.max(1, 蓝条格数 + 1 - Math.floor(蓝量比 * 蓝条格数))); // 控制蓝条动画
    this.frame = Math.max(1, 蓝条格数 + 1 - Math.floor(蓝量比 * 蓝条格数)); // 控制蓝条动画
}


_root.UI系统.韧性刷新显示 = function() 
{
    var target:MovieClip = TargetCacheManager.findHero();
    var poiseNumber:Number = target.nonlinearMappingResilience; // 获取韧性百分比

    // _root.发布消息("韧性百分比", poiseNumber); // 发布韧性百分比消息

	if (isNaN(poiseNumber)) return;

	var frameCount:Number = 30;

    this.poise = Math.floor(poiseNumber * 100) + "%"; 
    // this.gotoAndStop(Math.max(1, frameCount + 1 - Math.floor(poiseNumber * frameCount))); // 控制韧性动画
    this.frame = Math.max(1, frameCount + 1 - Math.floor(poiseNumber * frameCount)); // 控制韧性动画
}

_root.UI系统.经验刷新显示 = function()
{
    // 验证经验值数据
    if (isNaN(_root.经验值) || isNaN(_root.升级需要经验值) || isNaN(_root.上次升级需要经验值)) return;

    // _root.发布消息("经验值", _root.经验值, _root.升级需要经验值, _root.上次升级需要经验值); // 发布经验值消息

    // 计算经验值进度
    var a = Math.floor((_root.升级需要经验值 - _root.经验值) / (_root.升级需要经验值 - _root.上次升级需要经验值) * 100);

    // _root.发布消息("a", a); // 发布经验值消息
    if (a <= 100 && a > 0)
    {
        this.gotoAndStop(a); // 控制经验条动画
        this.frame = a; // 存储当前帧数
    }

    // 显示经验百分比
    this.经验百分比.text = Math.floor((_root.经验值 / _root.升级需要经验值) * 100) + "%";

    // _root.发布消息("经验百分比.text", 经验百分比.text); // 发布经验值消息

    // 格式化当前等级为三位数，前面补零
    var 格式化当前等级 = StringUtils.padStart(String(_root.等级), 3, "0");

    // _root.发布消息("格式化当前等级", 格式化当前等级); // 发布经验值消息
    this.玩家等级.text = 格式化当前等级;
}

/**
 * 防御性刷新：确保等级经验值阈值已设置并刷新UI
 * 用于防止加载顺序问题导致UI显示默认值（如999）
 *
 * @return Boolean 如果成功刷新返回true，否则返回false
 */
_root.UI系统.防御性刷新等级经验 = function():Boolean {
    // 验证等级数据有效性
    if(isNaN(_root.等级) || _root.等级 <= 0) {
        return false;
    }

    // 检查并设置缺失的阈值
    if(isNaN(_root.升级需要经验值) || isNaN(_root.上次升级需要经验值)) {
        _root.升级需要经验值 = _root.根据等级得升级所需经验(_root.等级);
        _root.上次升级需要经验值 = _root.等级 > 1 ? _root.根据等级得升级所需经验(_root.等级 - 1) : 0;
    }

    // 触发UI刷新
    if(_root.玩家信息界面 && _root.玩家信息界面.刷新经验值显示) {
        _root.玩家信息界面.刷新经验值显示();
        return true;
    }

    return false;
}

_root.UI系统.初始化玩家信息界面 = function() 
{
    this.刷新hp显示 = function() 
    {
        主角hp显示界面.刷新显示();
        主角韧性显示界面.刷新显示();
    };

    this.刷新mp显示 = function() 
    {
        主角mp显示界面.刷新显示();
    };

    this.刷新经验值显示 = function() 
    {
        主角经验值显示界面.刷新显示();
    };

    this.刷新技能等级显示 = function() 
    {
        快捷技能界面.刷新技能等级显示();
    };

    this.刷新攻击模式 = function(攻击模式) 
    {
        玩家必要信息界面.刷新(攻击模式);
    };

    this.刷新韧性显示 = function() 
    {
        主角韧性显示界面.刷新显示();
    };

    this.onEnterFrame = function() 
    {
        // 将所有需要做插帧动画的剪辑放到数组里
        var clips:Array = [
            主角hp显示界面, 
            主角mp显示界面, 
            主角韧性显示界面
            // 主角经验值显示界面
        ];
        
        // 控制动画参数
        var 最大过渡时间帧数:Number = 30;  // 确保动画不会太长
        var 最小帧变化量:Number = 1;      // 确保至少移动1帧
        var 最大帧变化比例:Number = 0.2;  // 每次最多移动距离的20%
        
        // 对每个剪辑分别按需移动
        for (var i:Number = 0; i < clips.length; i++) {
            var clip:MovieClip = clips[i];
            var targetFrame:Number = clip.frame;                // 目标帧
            var currentFrame:Number = clip._currentframe;       // 当前帧
            var frameDiff:Number = targetFrame - currentFrame;  // 帧差值
            
            if (frameDiff != 0) {
                // 计算这一帧应该移动的量
                var frameDistance:Number = Math.abs(frameDiff);
                
                // 根据距离计算变化量，距离越大变化越大，但有上限
                var changeAmount:Number = Math.max(
                    最小帧变化量,
                    Math.min(
                        Math.ceil(frameDistance * 最大帧变化比例),  // 按比例变化
                        Math.ceil(frameDistance / 最大过渡时间帧数 * 2), // 确保在指定时间内完成
                        frameDistance  // 不超过剩余距离
                    )
                );
                
                // 根据方向移动
                if (frameDiff > 0) {
                    clip.gotoAndStop(currentFrame + changeAmount);
                } else {
                    clip.gotoAndStop(currentFrame - changeAmount);
                }
            }
        }
    };
}