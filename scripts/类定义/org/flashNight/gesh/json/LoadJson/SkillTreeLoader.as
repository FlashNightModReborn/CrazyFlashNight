import org.flashNight.gesh.json.JSONLoader;
import org.flashNight.naki.DataStructures.DAG;
import org.flashNight.gesh.json.LoadJson.BaseDAGLoader;
import org.flashNight.gesh.path.PathManager;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * SkillTreeLoader
 * 用于同时加载两类 JSON 文件：
 *   1. 技能元数据（skills_metadata.json）
 *   2. 技能树配置（skills_tree_config.json, 描述DAG的边）
 *
 * 并且将两部分数据组装起来：
 *   - this.skillMetadata: 技能元数据（已解析）
 *   - this.skillDAG:      技能之间的依赖关系图（DAG）
 */
class org.flashNight.gesh.json.LoadJson.SkillTreeLoader extends BaseDAGLoader
{
    private var skillMetadata:Object = null; // 存放从 skills_metadata.json 解析出来的原始数据
    private var skillDAG:DAG = null;         // 存放构建好的技能依赖图(DAG)

    // 我们需要保存两份路径
    private var metadataFilePath:String;
    private var treeFilePath:String;

    // 是否正在加载
    private var isLoadingNow:Boolean = false;

    /**
     * 构造函数
     * @param metadataRelativePath  技能元数据的相对路径
     * @param treeRelativePath      技能树配置(DAG)的相对路径
     * @param _parseType            解析模式 (JSON, LiteJSON, FastJSON)
     */
    public function SkillTreeLoader(metadataRelativePath:String, treeRelativePath:String, _parseType:String)
    {
        // 父类BaseDAGLoader需要一个路径，但这里我们不直接用父类的路径了（会被浪费）
        // 可以传一个空字符串给父类，只是为了满足其构造函数的签名。
        super("", _parseType);

        // 初始化 PathManager
        PathManager.initialize();
        if (!PathManager.isEnvironmentValid()) {
            trace("SkillTreeLoader: 资源目录未检测到，无法加载文件！");
            return;
        }

        // 解析完整路径
        this.metadataFilePath = PathManager.resolvePath(metadataRelativePath);
        this.treeFilePath     = PathManager.resolvePath(treeRelativePath);

        if (this.metadataFilePath == null || this.treeFilePath == null) {
            trace("SkillTreeLoader: 路径解析失败，无法正常加载！");
        }
    }

    /**
     * 对外提供的加载接口，一次性加载技能元数据与技能树配置
     * @param onLoadHandler   加载成功后的回调，回调参数为 { skillMetadata: Object, skillDAG: DAG }
     * @param onErrorHandler  加载失败时的回调，回调参数为错误信息字符串
     */
    public function loadAll(onLoadHandler:Function, onErrorHandler:Function):Void
    {
        if (this.isLoadingNow) {
            trace("SkillTreeLoader: 正在加载中，请勿重复调用 loadAll！");
            return;
        }

        if (this.skillDAG != null && this.skillMetadata != null) {
            // 已经加载过了，直接回调
            if (onLoadHandler != null) {
                onLoadHandler({skillMetadata: this.skillMetadata, skillDAG: this.skillDAG});
            }
            return;
        }

        if (this.metadataFilePath == null || this.treeFilePath == null) {
            trace("SkillTreeLoader: 文件路径无效，无法加载！");
            if (onErrorHandler != null) onErrorHandler("Invalid file path");
            return;
        }

        this.isLoadingNow = true;
        var self:SkillTreeLoader = this;

        // 第一步：加载技能元数据
        trace("SkillTreeLoader: 开始加载技能元数据 -> " + this.metadataFilePath);
        new JSONLoader(this.metadataFilePath,
            // onSuccess
            function(parsedData:Object):Void {
                // 存储技能元数据
                self.skillMetadata = parsedData;

                // 第二步：加载技能树配置（DAG）
                self.loadDAGConfig(onLoadHandler, onErrorHandler);
            },
            // onError
            function(errorMessage:String):Void {
                self.isLoadingNow = false;
                trace("SkillTreeLoader: 技能元数据加载失败: " + errorMessage);
                if (onErrorHandler != null) onErrorHandler(errorMessage);
            },
            null, // onProgress
            self.parseType // parseType
        );
    }

    /**
     * 内部方法：加载技能树配置，并构建DAG
     */
    private function loadDAGConfig(onLoadHandler:Function, onErrorHandler:Function):Void
    {
        var self:SkillTreeLoader = this;
        trace("SkillTreeLoader: 开始加载技能树配置 -> " + this.treeFilePath);

        new JSONLoader(this.treeFilePath,
            function(parsedData:Object):Void {
                // 通过父类中的 buildDAGFromData 来构造一个 DAG
                // BaseDAGLoader 里有个 private 方法 buildDAGFromData(...)，无法直接访问
                // 如果你想直接利用父类功能，需要改成 public 或者我们自己手写简单的逻辑
                // 这里演示手写构建 DAG（可以模仿 BaseDAGLoader.buildDAGFromData 的做法）
                var newDAG:DAG = new DAG(); // 强制有向图

                // data 期望是 dictionary 格式： { "A": ["B", "C"], ... }
                for (var key:String in parsedData) {
                    newDAG.addVertex(key);
                }

                for (var src:String in parsedData) {
                    var neighbors:Array = parsedData[src];
                    if (neighbors instanceof Array) {
                        for (var i:Number = 0; i < neighbors.length; i++) {
                            newDAG.addEdge(src, neighbors[i]);
                        }
                    }
                }

                // 构建完成
                self.skillDAG = newDAG;
                self.isLoadingNow = false;

                trace("SkillTreeLoader: 成功构建技能依赖DAG！");

                // 回调返回组合结果
                if (onLoadHandler != null) {
                    onLoadHandler({
                        skillMetadata: self.skillMetadata,
                        skillDAG:      self.skillDAG
                    });
                }
            },
            function(errorMessage:String):Void {
                self.isLoadingNow = false;
                trace("SkillTreeLoader: 技能树配置加载失败: " + errorMessage);
                if (onErrorHandler != null) onErrorHandler(errorMessage);
            },
            null,
            this.parseType
        );
    }

    /**
     * 重载：重新加载（忽略已缓存的数据）
     */
    public function reloadAll(onLoadHandler:Function, onErrorHandler:Function):Void
    {
        this.skillMetadata = null;
        this.skillDAG = null;
        this.loadAll(onLoadHandler, onErrorHandler);
    }

    /**
     * 获取技能元数据
     */
    public function getSkillMetadata():Object {
        return this.skillMetadata;
    }

    /**
     * 获取技能DAG
     */
    public function getSkillDAG():DAG {
        return this.skillDAG;
    }

    /**
     * 是否已完成加载
     */
    public function isLoaded():Boolean {
        return (this.skillMetadata != null && this.skillDAG != null);
    }

    /**
     * 是否正在加载中
     */
    public function isLoadingStatus():Boolean {
        return this.isLoadingNow;
    }

    /**
     * 便于调试或日志
     */
    public function toString():String {
        var info:String = "SkillTreeLoader current status:\n";
        info += "isLoaded=" + this.isLoaded() + "\n";
        info += "skillMetadata=" + ((this.skillMetadata != null) ? "[Object]" : "null") + "\n";
        info += "skillDAG=" + ((this.skillDAG != null) ? "[DAG]" : "null") + "\n";
        return info;
    }
}
