// 文件路径：org/flashNight/arki/render/TrailStyleManager.as

import org.flashNight.gesh.xml.LoadXml.TrailStylesLoader;

/**
 * TrailStyleManager
 * =================
 * 轨迹样式管理器（单例）
 *
 * 责  任：
 *   - 负责加载、缓存并按名称提供拖影/残影样式配置；
 *   - 提供运行时样式更新与默认样式回退机制；
 *   - 对外暴露只读查询接口，避免渲染层直接依赖样式内部结构。
 *
 * 典型用法：
 *   var styleMgr:TrailStyleManager = TrailStyleManager.getInstance();
 *   styleMgr.loadStyles();                      // 游戏初始化阶段调用一次
 *   var style:Object = styleMgr.getStyle("刀光"); // 渲染阶段按需查询
 *
 * 样式结构示例：
 *   {
 *     color:      0xFFFFFF,  // 填充色
 *     lineColor:  0xFFFFFF,  // 描边色
 *     lineWidth:  2,         // 线宽
 *     fillOpacity: 100,      // 填充透明度 (0‑100)
 *     lineOpacity: 100       // 线条透明度 (0‑100)
 *   }
 *
 * 备注：
 *   - 为保证即使加载失败也能正常渲染，始终提供“预设”样式作为后备。
 *   - AS2 不支持严格私有属性，这里以前导下划线表示内部字段。
 *
 * @author flashNight
 */
class org.flashNight.arki.render.TrailStyleManager
{
    // --------------------------
    // 单例实现
    // --------------------------
    private static var _instance:TrailStyleManager;

    /**
     * 获取样式管理器单例。
     */
    public static function getInstance():TrailStyleManager
    {
        if (_instance == null) _instance = new TrailStyleManager();
        return _instance;
    }

    // --------------------------
    // 成员变量
    // --------------------------
    /** 样式缓存表：{ styleName:String -> styleConfig:Object } */
    private var _styles:Object;

    /** 默认后备样式 */
    private var _defaultStyle:Object = {
        color: 0xFFFFFF,
        lineColor: 0xFFFFFF,
        lineWidth: 2,
        fillOpacity: 100,
        lineOpacity: 100
    };

    // --------------------------
    // 构造函数
    // --------------------------
    /**
     * 私有构造函数 —— 请通过 getInstance() 访问。
     */
    private function TrailStyleManager()
    {
        _styles = { 预设: _defaultStyle };
    }

    // --------------------------
    // 对外接口
    // --------------------------
    /**
     * 异步加载外部样式配置。
     *
     * @param onComplete  (可选) 成功回调；function(styles:Object):Void
     * @param onError     (可选) 失败回调；function():Void
     */
    public function loadStyles(onComplete:Function, onError:Function):Void
    {
        var loader:TrailStylesLoader = TrailStylesLoader.getInstance();
        var self:TrailStyleManager   = this;

        loader.loadStyles(
            function(styles:Object):Void
            {
                // 合并到内部缓存，允许外部文件覆盖默认值
                for (var key:String in styles)
                {
                    self._styles[key] = styles[key];
                }
                if (onComplete != undefined) onComplete(self._styles);
            },
            function():Void
            {
                // 失败时保持默认样式可用
                if (_root.服务器) _root.服务器.发布服务器消息("TrailStyleManager: 样式加载失败，已回退到默认样式。");
                if (onError != undefined) onError();
            }
        );
    }

    /**
     * 读取指定名称的样式。若不存在则返回默认样式。
     *
     * @param styleName 样式名称
     * @return 样式配置对象（永不为 null）
     */
    public function getStyle(styleName:String):Object
    {
        return _styles[styleName] != undefined ? _styles[styleName] : _styles["预设"];
    }

    /**
     * 运行时动态更新或新增样式。
     *
     * @param styleName   样式名称
     * @param styleConfig 样式配置对象
     */
    public function updateStyle(styleName:String, styleConfig:Object):Void
    {
        _styles[styleName] = styleConfig;
    }

    /**
     * （可选）暴露全部样式表（只读），便于调试或列表显示。
     */
    public function getAllStyles():Object
    {
        return _styles;
    }
}
