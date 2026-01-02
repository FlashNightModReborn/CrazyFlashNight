//妥协写法，在其他文件fla化后进行重构
_root.兵器攻击检测 = function(target:MovieClip)
{
	return !!(target.man.兵器攻击标签);
};
	
_root.兵器使用检测 = function(target:MovieClip)
{
	return !!(target.man.兵器使用标签);
};

_root.是否兵器跳 = function(target:MovieClip)
{
	// 优先基于逻辑状态判断，避免依赖主角时间轴帧号（容器化/重排帧会导致区间失效）
	if (target.状态 != undefined)
	{
		return target.状态 == "兵器跳";
	}
	// 兼容：历史实现使用帧号区间判断（仅对主角-男时间轴有效）
	return target._currentframe >= 599 and target._currentframe <= 618;
};
