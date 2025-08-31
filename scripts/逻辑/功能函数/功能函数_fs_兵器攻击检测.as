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
	if (target._currentframe >= 599 and target._currentframe <= 618)
	{
		return true;
	}
	else
	{
		return false;
	}
};