//妥协写法，在其他文件fla化后进行重构
_root.兵器攻击检测 = function(人物)
{
	return !!(人物.man.兵器攻击标签);
};
	
_root.兵器使用检测 = function(人物)
{
	return !!(人物.man.兵器使用标签);
};