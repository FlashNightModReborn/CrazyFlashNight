//用新版jsonLoader加载任务数据
打印加载内容("加载任务数据……");

import org.flashNight.gesh.json.LoadJson.TaskDataLoader;

//暂停外置大脑以等待任务数据加载完毕
this.stop();
var asloader = this;

var taskloader = TaskDataLoader.getInstance();
taskloader.loadTaskData(
    function(data:Object):Void {
        trace("主程序：任务数据加载成功！");
		_root.发布消息("任务数据加载完毕");
		asloader.rawTaskData = data;
		asloader.play();
    },
    function():Void {
        trace("主程序：任务数据加载失败！");
    }
);