打印加载内容("加载基建数据……");

var infra_loader = org.flashNight.gesh.xml.LoadXml.InfrastructureLoader.getInstance();

infra_loader.loadInfrastructure(
    function(data:Object):Void {
		trace("主程序：基建项目数据加载成功！");
		var infrastructureDict = {};
		var infrastructureList = data.Infrastructure;
		for(var i=0; i<data.Infrastructure.length; i++){
			var project = infrastructureList[i];
			if(project.Level != null){
				project.Level = org.flashNight.gesh.object.ObjectUtil.toArray(project.Level);
				for(var j = 0; j < project.Level.length; j++){
					var lvl = project.Level[j];
					if(isNaN(lvl.Price)) lvl.Price = 0;
					if(lvl.Material != null){
						lvl.Material = org.flashNight.gesh.object.ObjectUtil.toArray(lvl.Material);
					}
					if(lvl.Skill != null){
						lvl.Skill = org.flashNight.gesh.object.ObjectUtil.toArray(lvl.Skill);
					}
				}
			}
			infrastructureDict[project.Name] = project;
		}
		if(_root.基建系统 == null) _root.基建系统 = new Object();
		_root.基建系统.dict = infrastructureDict;
		_root.基建系统.nameList = infrastructureList;
    },
    function():Void {
        trace("主程序：基建项目数据加载失败！");
    }
);