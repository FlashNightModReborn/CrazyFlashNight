import org.flashNight.gesh.xml.LoadXml.EnemyPropertiesLoader;
//import org.flashNight.gesh.object.ObjectUtil;

// 获取 EnemyPropertiesLoader 实例
var enemyPropertiesLoader:EnemyPropertiesLoader = EnemyPropertiesLoader.getInstance();

// 加载敌人属性数据
enemyPropertiesLoader.loadEnemyProperties(
    function(combinedData:Object):Void {
        trace("主程序：敌人属性数据加载成功！");
		_root.发布消息("敌人属性数据加载完毕");
        //trace("合并后的数据: " + ObjectUtil.toString(combinedData));
        // 在此处处理合并后的敌人属性数据
		_root.敌人属性表 = combinedData;
    },
    function():Void {
        trace("主程序：敌人属性数据加载失败！");
    }
);