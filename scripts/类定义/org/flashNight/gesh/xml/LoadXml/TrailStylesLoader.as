import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.xml.LoadXml.TrailStylesLoader extends BaseXMLLoader {
    private static var instance:TrailStylesLoader = null;
    private var styles:Object = null;

    /**
     * 获取单例实例。
     * @return TrailStylesLoader 实例。
     */
    public static function getInstance():TrailStylesLoader {
        if (instance == null) {
            instance = new TrailStylesLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 trailStyles.xml 的相对路径。
     */
    private function TrailStylesLoader() {
        super("data/render/trailStyles.xml");
    }

    /**
     * 加载 trailStyles.xml 文件。
     * @param onLoadHandler 加载成功后的回调函数，接收解析后的样式对象。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadStyles(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.load(function(data:Object):Void {
            trace("TrailStylesLoader: 文件加载成功！");
            this.styles = parseStyles(data);
            trace("Parsed Styles: " + ObjectUtil.toString(this.styles)); // 调试输出
            if (onLoadHandler != null) onLoadHandler(this.styles);
        }, function():Void {
            trace("TrailStylesLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 解析 XML 数据为样式对象。
     * @param data 解析后的 XML 数据。
     * @return 样式对象。
     */
    private function parseStyles(data:Object):Object {
        var styles:Object = {};
        var styleNodes:Array = data.trailStyles.style;
        for (var i:Number = 0; i < styleNodes.length; i++) {
            var styleNode:Object = styleNodes[i];
            var styleName:String = styleNode.attributes.name;
            styles[styleName] = {
                color: parseInt(styleNode.color, 16),
                lineColor: parseInt(styleNode.lineColor, 16),
                lineWidth: Number(styleNode.lineWidth),
                fillOpacity: Number(styleNode.fillOpacity),
                lineOpacity: Number(styleNode.lineOpacity)
            };
        }
        return styles;
    }

    /**
     * 获取已加载的样式数据。
     * @return Object 样式对象，如果尚未加载，则返回 null。
     */
    public function getStyles():Object {
        return this.styles;
    }
}