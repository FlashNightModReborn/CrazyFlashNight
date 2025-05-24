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
        this.loadersMap["attributeData"] = new AttributeLoader();
        this.loadersMap["movementData"] = new MovementLoader();
        
        var server = ServerManager.getInstance();
        var self = this;

        BulletsCasesLoader.getInstance().loadBulletsCases(
            function(data:Object):Void {
                var resultData:Object = {}; // 存储解析后的总数据
                var bulletNodes:Array = data.bullet;

                for (var i:Number = 0; i < bulletNodes.length; i++) {
                    var bulletNode:Object = bulletNodes[i];
                    var bulletName = (bulletNode.name != undefined && bulletNode.name != "") ? bulletNode.name : "bullet_" + i;

                    // 遍历映射表，按键名执行加载器
                    for (var key:String in self.loadersMap) {
                        var loader:IComponentLoader = self.loadersMap[key];
                        var componentInfo:Object = loader.load(bulletNode);

                        // 如果加载器返回 null 或空对象，跳过挂载
                        if (componentInfo == null || typeof(componentInfo) != "object" || Object.prototype.toString.call(componentInfo) != "[object Object]") {
                            continue;
                        }

                        // 初始化存储键，确保为对象结构
                        if (resultData[key] == undefined) {
                            resultData[key] = {};
                        }

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
                // server.sendServerMessage(ObjectUtil.toString(self));

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
     * 通用化获取加载的数据，支持默认值
     * @param key:String - 数据的键名
     * @param defaultValue:Object - 数据不存在时返回的默认值（可选）
     * @return Object - 加载的数据对象或默认值
     */
    public function getData(key:String, defaultValue:Object):Object {
        return this.infoData[key] != undefined ? this.infoData[key] : defaultValue;
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