import org.flashNight.sara.util.*;
import flash.display.BitmapData;
import flash.geom.Rectangle;
import flash.geom.Matrix;

class org.flashNight.sara.util.TileContainer {
    private var containerClip:MovieClip; // 用于显示瓦片的影片剪辑
    private var currentTile:BitmapData;  // 当前显示的瓦片
    public var currentTileID:String;     // 当前显示的瓦片 ID
    private var containerBitmapData:BitmapData; // 用于缓存显示瓦片的 BitmapData
    private var tileWidth:Number;        // 瓦片宽度
    private var tileHeight:Number;       // 瓦片高度

    // 构造函数，接受父级影片剪辑和瓦片容器的名称、位置、初始宽高
    public function TileContainer(parentClip:MovieClip, name:String, depth:Number, x:Number, y:Number, width:Number, height:Number) {
        // 在父级影片剪辑中创建一个空的影片剪辑作为容器
        this.containerClip = parentClip.createEmptyMovieClip(name, depth);
        this.containerClip._x = x;
        this.containerClip._y = y;
        this.tileWidth = width;
        this.tileHeight = height;

        // 创建一个 BitmapData 对象用于显示瓦片并重用
        this.containerBitmapData = new BitmapData(width, height, true, 0x00000000); // 透明背景

        // 将 BitmapData 附加到 MovieClip
        this.containerClip.attachBitmap(this.containerBitmapData, this.containerClip.getNextHighestDepth(), "auto", true);
    }

    // 更新容器中的瓦片显示
    public function setTile(tile:BitmapData):Void {
        if (tile == undefined || tile == this.currentTile) {
            return; // 如果 tile 无效或与当前瓦片相同，则不进行操作
        }

        // 清空之前的内容，防止堆积
        this.containerClip.clear();

        // 直接替换当前的瓦片
        this.containerClip.attachBitmap(tile, 0, "auto", true);  // 使用固定深度，避免不断增加深度

        // 更新当前瓦片引用
        this.currentTile = tile;

        // 绘制边界（启用或禁用边界绘制功能）
        var width:Number = this.getWidth();
        var height:Number = this.getHeight();
        this.containerClip.lineStyle(2, 0xFF0000, 100);  // 设置红色边框
        this.containerClip.moveTo(0, 0);
        this.containerClip.lineTo(width, 0);
        this.containerClip.lineTo(width, height);
        this.containerClip.lineTo(0, height);
        this.containerClip.lineTo(0, 0);

        this.setBlendMode("multiply"); // 或其他模式
    }


    // 清空当前的瓦片显示
    public function clear():Void {
        var rect:Rectangle = new Rectangle(0, 0, this.tileWidth, this.tileHeight);
        this.containerBitmapData.fillRect(rect, 0x00000000);  // 清空当前的 BitmapData 数据
        this.currentTile = null;
    }

    // 设置容器的位置
    public function setPosition(x:Number, y:Number):Void {
        this.containerClip._x = x;
        this.containerClip._y = y;
    }

    // 获取容器的位置
    public function getPosition():Object {
        return {x: this.containerClip._x, y: this.containerClip._y};
    }

    // 获取容器的宽度
    public function getWidth():Number {
        if (this.currentTile != undefined) {
            return this.currentTile.width;
        }
        return this.containerClip._width;
    }

    // 获取容器的高度
    public function getHeight():Number {
        if (this.currentTile != undefined) {
            return this.currentTile.height;
        }
        return this.containerClip._height;
    }

    // 设置容器的缩放比例
    public function setScale(xScale:Number, yScale:Number):Void {
        this.containerClip._xscale = xScale;
        this.containerClip._yscale = yScale;
    }

    // 获取缩放比例
    public function getScale():Object {
        return {xScale: this.containerClip._xscale, yScale: this.containerClip._yscale};
    }

    // 设置旋转角度
    public function setRotation(rotation:Number):Void {
        this.containerClip._rotation = rotation;
    }

    // 获取旋转角度
    public function getRotation():Number {
        return this.containerClip._rotation;
    }

    // 设置透明度
    public function setAlpha(alpha:Number):Void {
        this.containerClip._alpha = alpha;
    }

    // 获取透明度
    public function getAlpha():Number {
        return this.containerClip._alpha;
    }

    // 设置容器的可见性
    public function setVisibility(visible:Boolean):Void {
        this.containerClip._visible = visible;
    }

    // 获取可见性状态
    public function getVisibility():Boolean {
        return this.containerClip._visible;
    }

    // 设置容器的深度
    public function setDepth(depth:Number):Void {
        this.containerClip.swapDepths(depth);
    }

    // 设置混合模式
    public function setBlendMode(blendMode:String):Void {
        this.containerClip.blendMode = blendMode;
    }

    // 重置容器的所有状态
    public function reset():Void {
        this.setPosition(0, 0);
        this.setScale(100, 100);
        this.setRotation(0);
        this.setAlpha(100);
        this.setVisibility(true);
    }
}
