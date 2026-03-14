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
            // _root.服务器.发布服务器消息("TrailStylesLoader: 文件加载成功！");
            var s:Object = data.style;
            var ts:Object = {};
            for (var Key:String in s) {
                var st:Object = s[Key];
                var entry:Object = {
                    color: st.color,
                    lineColor: st.lineColor,
                    lineWidth: st.lineWidth,
                    fillOpacity: st.fillOpacity,
                    lineOpacity: st.lineOpacity
                };
                // P1 几何增强字段（可选，XML 中未定义时不设置，由 getStyle 惰性 backfill）
                if (st.leadOffset != undefined) entry.leadOffset = Number(st.leadOffset);
                if (st.lagOffset != undefined)  entry.lagOffset  = Number(st.lagOffset);
                if (st.outerScale != undefined) entry.outerScale = Number(st.outerScale);
                if (st.innerScale != undefined) entry.innerScale = Number(st.innerScale);
                if (st.tailFade != undefined)   entry.tailFade   = Number(st.tailFade);
                ts[st.name] = entry;
            }
            this.styles = ts;
            // _root.服务器.发布服务器消息("Parsed Styles: " + ObjectUtil.stringify(ts)); // 调试输出
            if (onLoadHandler != null) onLoadHandler(this.styles);
        }, function():Void {
            _root.服务器.发布服务器消息("TrailStylesLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的样式数据。
     * @return Object 样式对象，如果尚未加载，则返回 null。
     */
    public function getStyles():Object {
        return this.styles;
    }
}