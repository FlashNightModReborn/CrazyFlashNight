import org.flashNight.gesh.json.JSONLoader;
import org.flashNight.naki.DataStructures.DAG;
import org.flashNight.gesh.path.PathManager;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.json.LoadJson.BaseDAGLoader {
    private var dag:DAG = null;       // 构建好的 DAG 对象
    private var _isLoading:Boolean = false; // 是否正在加载
    private var filePath:String;      // JSON 文件的完整路径
    private var parseType:String = "JSON"; // JSON, LiteJSON, FastJSON
    private var data:Object = null;   // 解析后的原始 JSON 数据

    /**
     * 构造函数：通过相对路径指定 JSON 文件位置，并设置解析类型。
     * @param relativePath 相对于资源目录的文件路径
     * @param _parseType JSON 解析类型：JSON, LiteJSON, FastJSON
     */
    public function BaseDAGLoader(relativePath:String, _parseType:String) {
        // 初始化 PathManager
        PathManager.initialize();
        if (!PathManager.isEnvironmentValid()) {
            trace("BaseDAGLoader: Resource directory not detected, cannot load file!");
            return;
        }
        // 解析完整文件路径
        this.filePath = PathManager.resolvePath(relativePath);
        if (this.filePath == null) {
            trace("BaseDAGLoader: Failed to resolve path, cannot load file!");
        }
        this.parseType = _parseType;
    }

    /**
     * 加载 JSON 文件并构建 DAG 对象
     * @param onLoadHandler 加载成功后的回调，参数为构建好的 DAG 对象
     * @param onErrorHandler 加载失败时的回调，参数为错误信息字符串
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        if (this._isLoading) {
            trace("BaseDAGLoader: Data is currently being loaded, please avoid duplicate loads!");
            return;
        }
        if (this.dag != null) {
            trace("BaseDAGLoader: DAG already loaded, directly invoking callback.");
            if (onLoadHandler != null) onLoadHandler(this.dag);
            return;
        }
        if (this.filePath == null) {
            trace("BaseDAGLoader: Invalid file path, cannot load!");
            if (onErrorHandler != null) onErrorHandler("Invalid file path");
            return;
        }
        
        this._isLoading = true;
        var self:BaseDAGLoader = this;
        trace("BaseDAGLoader: Starting file load: " + this.filePath);
        
        // 使用 JSONLoader 加载文件
        new JSONLoader(this.filePath, function(parsedData:Object):Void {
            self._isLoading = false;
            self.data = parsedData;
            // 将解析后的 JSON 数据转换为 DAG 对象
            self.dag = self.buildDAGFromData(parsedData);
            if (self.dag != null) {
                trace("BaseDAGLoader: DAG loaded and built successfully!");
                if (onLoadHandler != null) onLoadHandler(self.dag);
            } else {
                trace("BaseDAGLoader: Failed to build DAG from data.");
                if (onErrorHandler != null) onErrorHandler("Failed to build DAG");
            }
        }, function(errorMessage:String):Void {
            self._isLoading = false;
            trace("BaseDAGLoader: File load failed! Error: " + errorMessage);
            if (onErrorHandler != null) onErrorHandler(errorMessage);
        }, null, this.parseType);
    }
    
    /**
     * 根据解析后的 JSON 数据构建 DAG 对象
     * 支持两种格式：
     * 1. 字典格式：{ "A": ["B", "C"], "B": ["D"], ... }
     * 2. 数组格式：[{ "id": "A", "edges": ["B", "C"] }, { "id": "B", "edges": ["D"] }, ...]
     * @param data 解析后的 JSON 数据
     * @return 构建好的 DAG 对象，若格式不符合则返回 null
     */
    private function buildDAGFromData(data:Object):DAG {
        var dag:DAG = new DAG();
        // 如果数据是字典格式
        if (data instanceof Object && !(data instanceof Array)) {
            for (var key:String in data) {
                dag.addVertex(key);
            }
            for (var key:String in data) {
                var edges:Array = data[key];
                if (edges instanceof Array) {
                    for (var i:Number = 0; i < edges.length; i++) {
                        var target:String = String(edges[i]);
                        dag.addEdge(key, target);
                    }
                }
            }
        }
        // 如果数据是数组格式
        else if (data instanceof Array) {
            // 首先添加所有顶点
            for (var j:Number = 0; j < data.length; j++) {
                var node:Object = data[j];
                var id:String = String(node.id);
                dag.addVertex(id);
            }
            // 然后添加边
            for (var j:Number = 0; j < data.length; j++) {
                var node:Object = data[j];
                var id:String = String(node.id);
                var edges:Array = node.edges;
                if (edges instanceof Array) {
                    for (var k:Number = 0; k < edges.length; k++) {
                        var target:String = String(edges[k]);
                        dag.addEdge(id, target);
                    }
                }
            }
        } else {
            trace("BaseDAGLoader: Unrecognized JSON structure for DAG.");
            return null;
        }
        return dag;
    }
    
    /**
     * 重载：重新加载 JSON 文件并构建 DAG 对象（忽略已缓存数据）。
     * @param onLoadHandler 加载成功后的回调
     * @param onErrorHandler 加载失败后的回调
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.data = null;
        this.dag = null;
        this.load(onLoadHandler, onErrorHandler);
    }
    
    /**
     * 获取构建好的 DAG 对象
     * @return DAG 对象，若尚未加载则返回 null
     */
    public function getDAG():DAG {
        return this.dag;
    }
    
    /**
     * 检查数据是否已加载
     * @return Boolean 如果 DAG 已加载返回 true，否则 false
     */
    public function isLoaded():Boolean {
        return this.dag != null;
    }
    
    /**
     * 检查当前是否正在加载数据
     * @return Boolean 如果正在加载返回 true，否则 false
     */
    public function isLoadingStatus():Boolean {
        return this._isLoading;
    }
    
    /**
     * 将加载的原始数据转换为字符串，便于调试或日志记录
     * @return String 原始 JSON 数据的字符串表示
     */
    public function toString():String {
        return ObjectUtil.toString(this.data);
    }
}
