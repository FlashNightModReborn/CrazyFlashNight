import org.flashNight.arki.bullet.BulletComponent.Loader.*;
import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.gesh.object.*;

class org.flashNight.arki.bullet.BulletComponent.Loader.InfoLoader {
    private static var instance:InfoLoader = null;
    private var infoData:Object = {};

    /**
     * 私有构造函数，不允许外部直接实例化
     */
    private function InfoLoader() {
        // 使用数据加载回调，与原逻辑相同
        var self = this;
        
        BulletsCasesLoader.getInstance().loadBulletsCases(
            function(data:Object):Void {
                
                var shellData = {};

                var bulletNodes:Array = data.bullet;
                for (var i:Number = 0; i < bulletNodes.length; i++) {
                    var bulletInfo:Object = {};
                    var child_Nodes:Array = bulletNodes[i];

                    var shell_info = child_Nodes.shell;

                    bulletInfo.弹壳 = shell_info.casing != undefined ? shell_info.casing : "步枪弹壳";
                    bulletInfo.myX = shell_info.xOffset != undefined ? Number(shell_info.xOffset) : 0;
                    bulletInfo.myY = shell_info.yOffset != undefined ? Number(shell_info.yOffset) : 0;
                    bulletInfo.模拟方式 = shell_info.simulationMethod != undefined ? shell_info.simulationMethod : "标准";
                    
                    shellData[shell_info.name] = bulletInfo;
                }

                self.infoData["shellData"] = shellData;
            },
            function():Void {
                trace("BulletsCasesLoader：bullets_cases.xml 加载失败！");
            }
        );
    }
    
    public function getShellData():Object
    {
        return getInstance().infoData["shellData"];
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