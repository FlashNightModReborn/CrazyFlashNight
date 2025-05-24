import org.flashNight.sara.util.*;
import org.flashNight.neur.Server.ServerManager;  // 引入ServerManager类

class org.flashNight.sara.util.TileManager {
    private var tileSize:Number;               // 瓦片大小
    public var mapClip:MovieClip;             // 地图影片剪辑
    private var parentClip:MovieClip;          // 父级影片剪辑
    public var tileCache:Object;              // 瓦片缓存，键为"tileX_tileY"
    public var tileContainers:Array;          // 瓦片容器数组
    private var mapWidth:Number;               // 地图宽度
    private var mapHeight:Number;              // 地图高度
    private var lastCenterTileX:Number; // 上一次的中心瓦片 X 索引
    private var lastCenterTileY:Number; // 上一次的中心瓦片 Y 索引

    // 构造函数
    public function TileManager(tileSize:Number, mapClip:MovieClip, parentClip:MovieClip) {
        this.tileSize = tileSize;
        this.mapClip = mapClip;
        this.parentClip = parentClip;
        this.tileCache = {};
        this.tileContainers = [];
        this.mapWidth = mapClip._width;
        this.mapHeight = mapClip._height;

        // 创建9个瓦片容器
        for (var i:Number = 0; i < 9; i++) {
            var containerName:String = "tileContainer_" + i;
            var depth:Number = parentClip.getNextHighestDepth();
            var tileContainer:TileContainer = new TileContainer(parentClip, containerName, depth, 0, 0);
            this.tileContainers.push(tileContainer);
        }

        this.lastCenterTileX = null; // 初始值为 null，表示尚未更新过
        this.lastCenterTileY = null;

        // 初始化瓦片缓存
        this.initializeTileCache();
    }

private function initializeTileCache():Void {
    for (var tileY:Number = 0; tileY < Math.ceil(this.mapHeight / this.tileSize); tileY++) {
        for (var tileX:Number = 0; tileX < Math.ceil(this.mapWidth / this.tileSize); tileX++) {
            var tileID:String = tileX + "_" + tileY;
            var tileLeft:Number = tileX * this.tileSize;
            var tileTop:Number = tileY * this.tileSize;

            // 创建瓦片并缓存
            var bounds:AABB = new AABB(tileLeft, tileLeft + this.tileSize, tileTop, tileTop + this.tileSize);
            var tile:Tile = new Tile(this.mapClip, bounds);
            this.tileCache[tileID] = tile;

            // 日志
            ServerManager.getInstance().sendServerMessage("初始化瓦片: " + tileID + "，位置: (" + tileLeft + ", " + tileTop + ")");
        }
    }

    // 日志：缓存大小
    ServerManager.getInstance().sendServerMessage("瓦片缓存初始化完成，缓存大小: " + this.tileCache.length);
}



public function update(playerX:Number, playerY:Number):Void {
    // 确保使用传递的参数，并进行限制
    var clampedX:Number = Math.max(0, Math.min(playerX, this.mapWidth));
    var clampedY:Number = Math.max(0, Math.min(playerY, this.mapHeight));

    // 日志：传递和限制后的坐标
    ServerManager.getInstance().sendServerMessage("TileManager.update called with: (" + playerX + ", " + playerY + ")");
    ServerManager.getInstance().sendServerMessage("Clamped coordinates: (" + clampedX + ", " + clampedY + ")");

    // 计算玩家所在的瓦片索引
    var centerTileX:Number = Math.floor(clampedX / this.tileSize);
    var centerTileY:Number = Math.floor(clampedY / this.tileSize);

    // 日志：中心瓦片索引
    ServerManager.getInstance().sendServerMessage("Center Tile: (" + centerTileX + ", " + centerTileY + ")");

    // 如果玩家仍在同一瓦片内，且瓦片容器已经初始化，则不需要更新
    if (this.lastCenterTileX == centerTileX && this.lastCenterTileY == centerTileY) {
        ServerManager.getInstance().sendServerMessage("玩家仍在同一瓦片内，无需更新: (" + centerTileX + ", " + centerTileY + ")");
        return; // 直接返回，避免不必要的更新
    }

    // 更新 lastCenterTileX 和 lastCenterTileY
    this.lastCenterTileX = centerTileX;
    this.lastCenterTileY = centerTileY;
    ServerManager.getInstance().sendServerMessage("更新瓦片，玩家位置: (" + clampedX + ", " + clampedY + ")，中心瓦片: (" + centerTileX + ", " + centerTileY + ")");

    // 计算需要显示的瓦片范围（以玩家所在瓦片为中心的3x3区域）
    var index:Number = 0;
    for (var dy:Number = -1; dy <= 1; dy++) {
        for (var dx:Number = -1; dx <= 1; dx++) {
            var tileX:Number = centerTileX + dx;
            var tileY:Number = centerTileY + dy;

            // 获取对应的瓦片容器
            var tileContainer:TileContainer = this.tileContainers[index];

            // 边界检查，防止超出地图范围
            if (tileX >= 0 && tileX < Math.ceil(this.mapWidth / this.tileSize) && 
                tileY >= 0 && tileY < Math.ceil(this.mapHeight / this.tileSize)) {
                // 瓦片的像素位置
                var tileLeft:Number = tileX * this.tileSize;
                var tileTop:Number = tileY * this.tileSize;

                // 获取瓦片ID
                var tileID:String = tileX + "_" + tileY;

                // 从缓存中获取瓦片
                var tile:Tile = this.tileCache[tileID];

                // 设置瓦片容器的位置
                tileContainer.setPosition(tileLeft, tileTop);

                // **仅当瓦片内容发生变化时，才更新瓦片容器的内容**
                if (tileContainer.currentTileID != tileID) {
                    tileContainer.setTile(tile);
                    tileContainer.currentTileID = tileID; // 保存当前瓦片的 ID
                    ServerManager.getInstance().sendServerMessage("设置瓦片容器内容，容器索引: " + index + "，瓦片ID: " + tileID);
                }
            } else {
                // 如果超出地图范围，清空对应的瓦片容器
                tileContainer.clear(); // 清空容器内容
                tileContainer.currentTileID = null; // 重置当前瓦片 ID
                ServerManager.getInstance().sendServerMessage("超出地图范围，清空瓦片容器: 容器索引 " + index);
            }

            index++;
        }
    }
}

}


/*

import flash.geom.Rectangle;
import flash.geom.Matrix;
import org.flashNight.sara.util.*;

_root.createComplexMap = function(parentClip:MovieClip):MovieClip {
    var mapClip:MovieClip = parentClip.createEmptyMovieClip("mapClip", parentClip.getNextHighestDepth());
    mapClip._x = 0;
    mapClip._y = 0;

    // 绘制大矩形作为地图背景
    mapClip.beginFill(0xCCCCCC, 100); // 灰色填充
    mapClip.moveTo(0, 0);
    mapClip.lineTo(1000, 0);
    mapClip.lineTo(1000, 1000);
    mapClip.lineTo(0, 1000);
    mapClip.lineTo(0, 0);
    mapClip.endFill();

    // 绘制网格线
    mapClip.lineStyle(1, 0x999999, 100);
    for (var i:Number = 0; i <= 1000; i += 100) {
        mapClip.moveTo(i, 0);
        mapClip.lineTo(i, 1000);
        mapClip.moveTo(0, i);
        mapClip.lineTo(1000, i);
    }

    // 添加随机树木
    for (var j:Number = 0; j < 10; j++) {
        var treeX:Number = Math.random() * 1000;
        var treeY:Number = Math.random() * 1000;
        mapClip.beginFill(0x228B22, 100); // 树的颜色
        mapClip.moveTo(treeX, treeY);
        mapClip.lineTo(treeX - 10, treeY + 20);
        mapClip.lineTo(treeX + 10, treeY + 20);
        mapClip.lineTo(treeX, treeY);
        mapClip.endFill();
    }

    // 添加随机建筑
    for (var k:Number = 0; k < 5; k++) {
        var buildingX:Number = Math.random() * 1000;
        var buildingY:Number = Math.random() * 1000;
        var buildingWidth:Number = 40 + Math.random() * 60;
        var buildingHeight:Number = 60 + Math.random() * 100;
        mapClip.beginFill(0x8B4513, 100); // 建筑颜色
        mapClip.moveTo(buildingX, buildingY);
        mapClip.lineTo(buildingX + buildingWidth, buildingY);
        mapClip.lineTo(buildingX + buildingWidth, buildingY + buildingHeight);
        mapClip.lineTo(buildingX, buildingY + buildingHeight);
        mapClip.lineTo(buildingX, buildingY);
        mapClip.endFill();
    }

    // 返回生成的地图影片剪辑
    return mapClip;
};

// 初始化测试
_root.initTest = function():Void {
    // 创建游戏世界的影片剪辑
    var gameWorld:MovieClip = _root.createEmptyMovieClip("gameWorld", _root.getNextHighestDepth());

    // 在 gameWorld 中创建复杂地图影片剪辑
    var mapClip:MovieClip = _root.createComplexMap(gameWorld);

    // 创建一个模拟的玩家对象
    var player:MovieClip = gameWorld.createEmptyMovieClip("player", gameWorld.getNextHighestDepth());
    player.beginFill(0xFF0000, 100); // 红色填充
    player.moveTo(-10, -10);
    player.lineTo(10, -10);
    player.lineTo(10, 10);
    player.lineTo(-10, 10);
    player.lineTo(-10, -10);
    player.endFill();
    player._x = 500; // 初始位置在地图中心
    player._y = 500;

    // 初始化 TileManager
    var tileSize:Number = 200; // 瓦片大小
    var tileManager:TileManager = new TileManager(tileSize, mapClip, gameWorld);

    // 将 TileManager 保存到全局变量，方便在其他地方访问
    _root.tileManager = tileManager;

    // 监听键盘事件，控制玩家移动
    var speed:Number = 5; // 玩家移动速度
    var keys:Object = {left: false, right: false, up: false, down: false};

    Key.addListener({
        onKeyDown: function() {
            var keyCode:Number = Key.getCode();
            if (keyCode == Key.LEFT) keys.left = true;
            if (keyCode == Key.RIGHT) keys.right = true;
            if (keyCode == Key.UP) keys.up = true;
            if (keyCode == Key.DOWN) keys.down = true;
        },
        onKeyUp: function() {
            var keyCode:Number = Key.getCode();
            if (keyCode == Key.LEFT) keys.left = false;
            if (keyCode == Key.RIGHT) keys.right = false;
            if (keyCode == Key.UP) keys.up = false;
            if (keyCode == Key.DOWN) keys.down = false;
        }
    });

    // 显示性能信息的文本字段
    // Increase the size of the TextField to 300x120 for better visibility
var infoText:TextField = _root.createTextField("infoText", _root.getNextHighestDepth(), 10, 10, 300, 120);

    infoText.border = true;
    infoText.background = true;
    infoText.backgroundColor = 0xFFFFFF;
    infoText.text = "性能信息";

    // FPS 相关变量
    var frameCount:Number = 0;
    var lastTime:Number = getTimer();
    var fps:Number = 0;

    // 主循环
    _root.onEnterFrame = function():Void {
        // 更新玩家位置
        if (keys.left) player._x -= speed;
        if (keys.right) player._x += speed;
        if (keys.up) player._y -= speed;
        if (keys.down) player._y += speed;

        // 限制玩家在地图范围内
        if (player._x < 0) player._x = 0;
        if (player._x > mapClip._width) player._x = mapClip._width;
        if (player._y < 0) player._y = 0;
        if (player._y > mapClip._height) player._y = mapClip._height;

        // 更新 TileManager
        tileManager.update(player._x, player._y);

        // 让游戏世界跟随玩家移动，实现滚屏效果
        var stageCenterX:Number = Stage.width / 2;
        var stageCenterY:Number = Stage.height / 2;
        gameWorld._x = stageCenterX - player._x;
        gameWorld._y = stageCenterY - player._y;

        // 计算 FPS
        frameCount++;
        var currentTime:Number = getTimer();
        var elapsed:Number = currentTime - lastTime;

        if (elapsed >= 1000) {  // 每秒更新一次 FPS
            fps = frameCount * 1000 / elapsed;
            frameCount = 0;
            lastTime = currentTime;
        }

        // 更新性能信息
        var cacheSize:Number = 0;
        for (var id:String in tileManager.tileCache) {
            cacheSize++;
        }
        infoText.text = "玩家位置：(" + Math.round(player._x) + ", " + Math.round(player._y) + ")\n";
        infoText.text += "加载的瓦片数量：" + cacheSize + "\n";
        infoText.text += "瓦片容器数量：" + tileManager.tileContainers.length + "\n";
        infoText.text += "当前帧率：" + Math.round(fps) + " FPS\n";
    };
};

// 启动测试
_root.initTest();

*/