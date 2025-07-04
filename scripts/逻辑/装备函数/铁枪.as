// =======================================================
//  铁枪 · 装备生命周期函数  （修复版本）
// =======================================================

/*--------------------------------------------------------
 * 1. 初始化
 *------------------------------------------------------*/
_root.装备生命周期函数.铁枪初始化 = function (ref, param) 
{
    var 自机 = ref.自机;

    // ——处理主角状态同步（参考炎魔斩的实现）
    if (ref.是否为主角) 
    {
        var 标签 = ref.标签名 + ref.初始化函数;
        var 标签对象 = _root.装备生命周期函数.全局参数[标签];
        if (标签对象) 
        {
            ref.unmaykr化 = 标签对象.unmaykr化;
        }
        else 
        {
            _root.装备生命周期函数.全局参数[标签] = {};
            var 标签对象 = _root.装备生命周期函数.全局参数[标签];
            ref.unmaykr化 = false; // 默认BFG形态
            标签对象.unmaykr化 = ref.unmaykr化;
        }
        ref.标签对象 = 标签对象;
    }
    else 
    {
        ref.unmaykr化 = false; // 佣兵默认BFG形态
    }

    // ——关键帧常量定义
    ref.bfg起始帧 = param.bfgStart || 1;
    ref.bfg结束帧 = param.bfgEnd || 15;
    ref.变形起始帧 = param.transStart || 16;
    ref.变形结束帧 = param.transEnd || 25;
    ref.unmaykr起始帧 = param.unmStart || 26;
    ref.unmaykr结束帧 = param.unmEnd || 41;

    // ——变形相关参数
    ref.变形切换间隔 = param.transformInterval || 1000;
    ref.变形切换标签 = param.transformLabel || "铁枪变形检测";

    // ——根据当前形态设置初始帧
    ref.当前帧 = ref.unmaykr化 ? ref.unmaykr起始帧 : ref.bfg起始帧;

    // ——形态切换执行函数
    ref.变形执行函数 = function(反射对象) 
    {
        反射对象.unmaykr化 = !反射对象.unmaykr化;
        
        // 同步到全局参数（仅主角）
        if (反射对象.是否为主角) 
        {
            反射对象.标签对象.unmaykr化 = 反射对象.unmaykr化;
        }
    };

    // ——友元函数引用
    ref.展开函数 = _root.装备生命周期函数.铁枪展开动画;
    ref.收纳函数 = _root.装备生命周期函数.铁枪收纳动画;
};

/*--------------------------------------------------------
 * 2. 周期函数
 *------------------------------------------------------*/
_root.装备生命周期函数.铁枪周期 = function (ref, param) 
{
    _root.装备生命周期函数.移除异常周期函数(ref);
    var 自机 = ref.自机;
    var 长枪 = 自机.长枪_引用;

    if (自机.攻击模式 === "长枪") 
    {
        // ——检测变形按键
        if (_root.按键输入检测(自机, _root.武器变形键)) 
        {
            _root.更新并执行时间间隔动作(ref, ref.变形切换标签, ref.变形执行函数, ref.变形切换间隔, false, ref);
        }

        // ——播放展开动画
        ref.展开函数(ref);
    }
    else 
    {
        // ——播放收纳动画
        ref.收纳函数(ref);
    }

    // ——更新武器动画帧
    长枪.动画.gotoAndStop(ref.当前帧);
};

/*--------------------------------------------------------
 * 3. 展开动画状态机
 *------------------------------------------------------*/
_root.装备生命周期函数.铁枪展开动画 = function (ref) 
{
    switch (ref.当前帧) 
    {
        // --------BFG 结束帧处理--------
        case ref.bfg结束帧:
            if (ref.unmaykr化) 
            {
                --ref.当前帧; // 开始向过渡区退回
            }
            else 
            {
                // 保持在BFG区间循环，可以选择回到起始帧或继续
                // 这里选择继续循环播放
            }
            break;

        // --------Unmaykr 结束帧处理--------
        case ref.unmaykr结束帧:
            if (!ref.unmaykr化) 
            {
                --ref.当前帧; // 开始向过渡区退回
            }
            else 
            {
                // 保持在Unmaykr区间循环
            }
            break;

        // --------BFG 起始帧处理--------
        case ref.bfg起始帧:
            if (ref.unmaykr化) 
            {
                ref.当前帧 = ref.变形起始帧 + 1; // 跳转到变形区间
            }
            else 
            {
                ++ref.当前帧; // 正常播放BFG动画
            }
            break;

        // --------Unmaykr 起始帧处理--------
        case ref.unmaykr起始帧:
            if (ref.unmaykr化) 
            {
                ++ref.当前帧; // 正常播放Unmaykr动画
            }
            else 
            {
                ref.当前帧 = ref.变形结束帧 - 1; // 跳转到变形区间末尾
            }
            break;

        // --------变形区间边界处理--------
        case ref.变形起始帧:
            if (ref.unmaykr化) 
            {
                ++ref.当前帧; // 向Unmaykr变形
            }
            else 
            {
                ref.当前帧 = ref.bfg起始帧 + 1; // 跳回BFG区间
            }
            break;

        case ref.变形结束帧:
            if (ref.unmaykr化) 
            {
                ref.当前帧 = ref.unmaykr起始帧 + 1; // 跳到Unmaykr区间
            }
            else 
            {
                --ref.当前帧; // 向BFG变形
            }
            break;

        // --------默认区间内移动--------
        default:
            // BFG 区间内
            if (ref.当前帧 < ref.bfg结束帧) 
            {
                ref.当前帧 += ref.unmaykr化 ? -1 : 1;
            }
            // 变形过渡区间内
            else if (ref.当前帧 < ref.变形结束帧) 
            {
                ref.当前帧 += ref.unmaykr化 ? 1 : -1;
            }
            // Unmaykr 区间内
            else 
            {
                ref.当前帧 += ref.unmaykr化 ? 1 : -1;
            }
            break;
    }
};

/*--------------------------------------------------------
 * 4. 收纳动画
 *------------------------------------------------------*/
_root.装备生命周期函数.铁枪收纳动画 = function (ref) 
{
    switch (ref.当前帧) 
    {
        // ——关键帧直接归位
        case ref.bfg起始帧:
        case ref.unmaykr起始帧:
        case ref.变形起始帧:
        case ref.变形结束帧:
            ref.当前帧 = ref.unmaykr化 ? ref.unmaykr起始帧 : ref.bfg起始帧;
            break;

        // ——区间内归位移动
        default:
            if (ref.当前帧 <= ref.bfg结束帧) 
            {
                --ref.当前帧; // BFG区间向起始帧收纳
            }
            else if (ref.当前帧 <= ref.变形结束帧) 
            {
                // 过渡区间根据目标形态决定收纳方向
                ref.当前帧 += ref.unmaykr化 ? 1 : -1;
            }
            else 
            {
                --ref.当前帧; // Unmaykr区间向起始帧收纳
            }
            break;
    }
};