import org.flashNight.arki.bullet.BulletComponent.Loader.*;
import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.gesh.object.*;
import org.flashNight.neur.Server.*; 

class org.flashNight.arki.bullet.BulletComponent.Loader.InfoLoader {
    private static var instance:InfoLoader = null;
    private var infoData:Object = {};
    private var isLoaded:Boolean = false; // 标记是否已完成加载
    private var onLoadCallbacks:Array = []; // 加载完成后的回调函数列表
    private var loadersMap:Object = {}; // 组件加载器列表

    /**
     * 私有构造函数
     */
    private function InfoLoader() {
        this.loadersMap["shellData"] = new ShellLoader();
        var server = ServerManager.getInstance();
        var self = this;

        BulletsCasesLoader.getInstance().loadBulletsCases(
            function(data:Object):Void {
                var resultData:Object = {}; // 存储解析后的总数据
                var bulletNodes:Array = data.bullet;

                for (var i:Number = 0; i < bulletNodes.length; i++) {
                    var bulletNode:Object = bulletNodes[i];

                    // 遍历映射表，按键名执行加载器
                    for (var key:String in self.loadersMap) {
                        var loader:IComponentLoader = self.loadersMap[key];
                        var componentInfo:Object = loader.load(bulletNode);

                        // 初始化存储键，确保为数组结构
                        if (resultData[key] == undefined) {
                            resultData[key] = {};
                        }

                        // 使用 name 作为键，存储解析结果
                        var bulletName:String = bulletNode.shell.name != undefined ? bulletNode.shell.name : ("bullet_" + i);
                        resultData[key][bulletName] = componentInfo;
                    }
                }

                self.infoData = resultData; // 保存总数据到 infoData
                self.isLoaded = true;

                // 触发所有回调
                for (var k:Number = 0; k < self.onLoadCallbacks.length; k++) {
                    self.onLoadCallbacks[k](self.infoData);
                }

                server.sendServerMessage("BulletsCasesLoader：bullets_cases.xml 加载成功！");

                // 清空回调队列
                self.onLoadCallbacks = [];
            },
            function():Void {
                server.sendServerMessage("BulletsCasesLoader：bullets_cases.xml 加载失败！");
            }
        );
    }


    /**
     * 注册加载完成后的回调
     */
    public function onLoad(callback:Function):Void {
        if (this.isLoaded) {
            callback(this.infoData); // 如果已经加载完成，直接执行回调
        } else {
            this.onLoadCallbacks.push(callback); // 否则加入回调队列
        }
    }

    /**
     * 获取加载的数据
     */
    public function getShellData():Object {
        return this.infoData["shellData"];
    }

    /**
     * 获取单例实例
     */
    public static function getInstance():InfoLoader {
        if (instance == null) {
            instance = new InfoLoader();
        }
        return instance;
    }
}