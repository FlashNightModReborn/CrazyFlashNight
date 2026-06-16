import org.flashNight.gesh.json.LoadJson.TaskTextLoader;

//暂停外置大脑以等待任务数据加载完毕
this.stop();
var asloader = this;

var textloader = TaskTextLoader.getInstance();
textloader.loadTaskText(
    function(data:Object):Void {
        trace("主程序：任务文本加载成功！");
		_root.发布消息("任务文本加载完毕");
		asloader.rawTextData = data;
		asloader.play();
    },
    function():Void {
        trace("主程序：任务文本加载失败！");
    }
);