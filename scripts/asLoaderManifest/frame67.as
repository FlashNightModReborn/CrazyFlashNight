import org.flashNight.gesh.xml.LoadXml.StageEnvironmentLoader;
var stage_env_loader:StageEnvironmentLoader = StageEnvironmentLoader.getInstance();

stage_env_loader.loadStageEnvironment(
    function(data:Object):Void {
        trace("主程序：关卡环境数据加载成功！");
		_root.配置关卡环境数据(data);
    },
    function():Void {
        trace("主程序：关卡环境数据加载失败！");
    }
);
