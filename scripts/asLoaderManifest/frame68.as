import org.flashNight.gesh.xml.LoadXml.SceneEnvironmentLoader;
var scene_env_loader:SceneEnvironmentLoader = SceneEnvironmentLoader.getInstance();

scene_env_loader.loadSceneEnvironment(
    function(data:Object):Void {
        trace("主程序：场景环境数据加载成功！");
		_root.配置场景环境数据(data);
    },
    function():Void {
        trace("主程序：场景环境数据加载失败！");
    }
);
