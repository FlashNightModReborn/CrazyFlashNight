import org.flashNight.gesh.xml.LoadXml.StageInfoLoader;
import org.flashNight.gesh.object.ObjectUtil;

// 获取 StageInfoLoader 实例
var StageInfoLoader:StageInfoLoader = StageInfoLoader.getInstance();

// 加载关卡信息
StageInfoLoader.loadStageInfo(
    function(combinedData:Object):Void {
        trace("主程序：关卡信息加载成功！");
		_root.发布消息("关卡信息加载完毕");
        _root.StageInfoDict = combinedData;
    },
    function():Void {
        trace("主程序：关卡信息加载失败！");
    }
);
