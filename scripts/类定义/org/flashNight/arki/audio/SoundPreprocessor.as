/* 
 * 文件：org/flashNight/arki/audio/SoundPreprocessor.as
 * 说明：预处理类，负责创建音频预载容器、加载各分类 SWF 与 XML 数据，
 *       并构建 soundDict、soundLastTime、soundSourceDict 三个数据结构。
 */
 
import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.path.*;

class org.flashNight.arki.audio.SoundPreprocessor {
    // 音频管理容器（创建在指定容器上，默认 _root）
    public var soundManager:MovieClip;
    // 用于存放 Sound 对象
    public var soundDict:Object;
    // 记录每个音效上次播放的时间（单位 ms）
    public var soundLastTime:Object;
    // 映射音效标识到所属分类（如 "武器", "特效", "人物"）
    public var soundSourceDict:Object;
    // 同一声音播放的最小间隔（单位 ms）
    public var minInterval:Number;
    
    /**
     * 构造函数
     * @param container		指定创建音频容器的 MovieClip（若传 null 则为 _root）
     */
    public function SoundPreprocessor(container:MovieClip) {
        PathManager.initialize();

        // 创建 soundManager 空的 MovieClip，若为_root则深度设置为预留值65534，否则取当前最高深度
        if (container == null) container = _root;
        var depth = container === _root ? 65534 : container.getNextHighestDepth();
        this.soundManager = container.createEmptyMovieClip("soundManager", depth);
        
        // 初始化数据结构
        this.soundDict = new Object();
        this.soundLastTime = new Object();
        this.soundSourceDict = new Object();
        this.minInterval = 90;
        
        // 在 soundManager 中创建三个子轨道
        this.soundManager.createEmptyMovieClip("武器", 0);
        this.soundManager.createEmptyMovieClip("特效", 1);
        this.soundManager.createEmptyMovieClip("人物", 2);
        
        // 加载对应的 SWF 文件
        this.soundManager.武器.loadMovie(PathManager.resolvePath("sounds/音效-武器.swf"));
        this.soundManager.特效.loadMovie(PathManager.resolvePath("sounds/音效-特效.swf"));
        this.soundManager.人物.loadMovie(PathManager.resolvePath("sounds/音效-人物.swf"));

        loadAllCategories();
    }
    
    /**
     * 加载某个分类的 XML 数据，填充 soundSourceDict
     * @param category		音效所属分类，如 "武器", "特效", "人物"
     * @param xmlPath		XML 文件路径
     */
    public function loadCategoryXML(category:String, xmlPath:String):Void {
        var loader:BaseXMLLoader = new org.flashNight.gesh.xml.LoadXml.BaseXMLLoader(xmlPath);
        // 为回调捕获 this
        var self:SoundPreprocessor = this;
        loader.load(
            function(domdata:Object):Void {
                var soundItems:Object = domdata.media.DOMSoundItem;
                for (var i in soundItems) {
                    var soundIdentifier:String = soundItems[i].linkageIdentifier;
                    if (soundIdentifier != null) {
                        self.soundSourceDict[soundIdentifier] = category;
                    }
                }
                trace("[SoundPreprocessor] Loaded XML for category: " + category);
            },
            function():Void {
                trace("[SoundPreprocessor] Error loading XML for category: " + category);
            }
        );
    }
    
    /**
     * 便捷加载全部三个分类的 XML 数据
     */
    public function loadAllCategories():Void {
        this.loadCategoryXML("武器", "sounds/音效-武器/DOMDocument.xml");
        this.loadCategoryXML("特效", "sounds/音效-特效/DOMDocument.xml");
        this.loadCategoryXML("人物", "sounds/音效-人物/DOMDocument.xml");
    }
}
