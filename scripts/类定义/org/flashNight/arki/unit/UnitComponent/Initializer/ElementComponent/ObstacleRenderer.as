import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;

/**
 * 障碍物渲染组件 - 负责将地图元件的碰撞区域渲染到地图上
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.ObstacleRenderer {
    
    // 障碍物填充颜色
    private static var OBSTACLE_FILL_COLOR:Number = 0x000000;
    
    /**
     * 渲染目标的障碍物到地图
     * @param target 要渲染的目标MovieClip
     */
    public static function renderObstacle(target:MovieClip):Void {
        if (!ObstacleRenderer.canRenderObstacle(target)) {
            return;
        }
        
        var gameworld:MovieClip = _root.gameworld;
        var rect:Object = target.area.getRect(gameworld);
        var mapGraphics:MovieClip = ObstacleRenderer.getMapGraphics(gameworld);
        
        if (mapGraphics) {
            ObstacleRenderer.drawObstacleRect(mapGraphics, rect);
        }
    }
    
    /**
     * 检查目标是否可以渲染障碍物
     * @param target 要检查的目标MovieClip
     * @return Boolean 如果可以渲染返回true
     */
    public static function canRenderObstacle(target:MovieClip):Boolean {
        return target.obstacle && target.area && _root.gameworld;
    }
    
    /**
     * 获取或创建地图绘图对象
     * @param gameworld 游戏世界MovieClip
     * @return MovieClip 地图绘图对象
     */
    private static function getMapGraphics(gameworld:MovieClip):MovieClip {
        var mapGraphics:MovieClip = gameworld.地图;
        
        if (!mapGraphics) {
            mapGraphics = gameworld.createEmptyMovieClip("地图", gameworld.getNextHighestDepth());
        }
        
        // 设置地图为不可枚举
        ObstacleRenderer.setMapNonEnumerable(gameworld);
        
        return mapGraphics;
    }
    
    /**
     * 设置地图属性为不可枚举
     * @param gameworld 游戏世界MovieClip
     */
    private static function setMapNonEnumerable(gameworld:MovieClip):Void {
        if (_global.ASSetPropFlags) {
            _global.ASSetPropFlags(gameworld, ["地图"], 1, false);
        }
    }
    
    /**
     * 在地图上绘制障碍物矩形
     * @param mapGraphics 地图绘图对象
     * @param rect 要绘制的矩形区域
     */
    private static function drawObstacleRect(mapGraphics:MovieClip, rect:Object):Void {
        mapGraphics.beginFill(OBSTACLE_FILL_COLOR);
        mapGraphics.moveTo(rect.xMin, rect.yMin);
        mapGraphics.lineTo(rect.xMax, rect.yMin);
        mapGraphics.lineTo(rect.xMax, rect.yMax);
        mapGraphics.lineTo(rect.xMin, rect.yMax);
        mapGraphics.lineTo(rect.xMin, rect.yMin);
        mapGraphics.endFill();
    }
    
    /**
     * 清除地图上的所有障碍物
     * @param gameworld 游戏世界MovieClip，如果不提供则使用_root.gameworld
     */
    public static function clearAllObstacles(gameworld:MovieClip):Void {
        if (!gameworld) {
            gameworld = _root.gameworld;
        }
        
        if (!gameworld) return;
        
        var mapGraphics:MovieClip = gameworld.地图;
        if (mapGraphics) {
            mapGraphics.clear();
        }
    }
    
    /**
     * 获取障碍物的边界矩形
     * @param target 目标MovieClip
     * @param referenceClip 参考坐标系MovieClip，默认为gameworld
     * @return Object 包含xMin, yMin, xMax, yMax的矩形对象，如果无效则返回null
     */
    public static function getObstacleBounds(target:MovieClip, referenceClip:MovieClip):Object {
        if (!target || !target.area) {
            return null;
        }
        
        if (!referenceClip) {
            referenceClip = _root.gameworld;
        }
        
        return target.area.getRect(referenceClip);
    }
    
    /**
     * 设置障碍物填充颜色
     * @param color 新的填充颜色值
     */
    public static function setObstacleFillColor(color:Number):Void {
        OBSTACLE_FILL_COLOR = color;
    }
    
    /**
     * 批量渲染多个障碍物
     * @param targets 要渲染的目标数组
     */
    public static function renderMultipleObstacles(targets:Array):Void {
        if (!targets || targets.length == 0) return;
        
        for (var i:Number = 0; i < targets.length; i++) {
            ObstacleRenderer.renderObstacle(targets[i]);
        }
    }
}