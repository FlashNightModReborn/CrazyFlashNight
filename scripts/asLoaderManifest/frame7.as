//在任务数据和任务文本皆加载完成后配置数据
org.flashNight.arki.task.TaskUtil.ParseTaskData(this.rawTaskData, this.rawTextData);
this.rawTaskData = null;
this.rawTextData = null;

// 异步加载任务引导数据
import org.flashNight.gesh.json.LoadJson.ProgressGuideLoader;
var guideLoader = ProgressGuideLoader.getInstance();
guideLoader.loadGuideData(
    function(data:Object):Void {
        trace("主程序：任务引导数据加载成功！");
        org.flashNight.arki.task.TaskUtil.ParseGuideData(data);
    },
    function():Void {
        trace("主程序：任务引导数据加载失败！");
    }
);