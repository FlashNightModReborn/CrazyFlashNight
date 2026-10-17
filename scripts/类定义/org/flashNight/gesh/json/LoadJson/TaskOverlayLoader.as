import org.flashNight.gesh.path.PathManager;

/**
 * 任务覆盖层读取器（G2-2）：按当前存档槽位读取 data/rag/agent_saves/<slot>/ 下的
 * Agent 增量文件（agent_tasks.json / agent_text.json / task_text_overrides.json）。覆盖层与基础 list.xml 目录
 * 完全分离：不进 entries、不走 ownedEntries，由领域 loader 显式持有路径并单独判断变化。
 *
 * fail-closed 口径（§2.0.8）：文件缺失＝该存档无增量，静默跳过（onReady(null)）；
 * 文件存在但解析不净＝报错（trace + Host 日志）并回退 null，调用方保留基础数据，
 * 不拿半份数据糊过去。
 */
class org.flashNight.gesh.json.LoadJson.TaskOverlayLoader {
    // 与后端写盘落点同名（cfn-rag-backend 的 agent_saves 根与两个文件名）。
    public static var DIRECTORY:String = "data/rag/agent_saves/";
    public static var TASK_FILE:String = "agent_tasks.json";
    public static var TEXT_FILE:String = "agent_text.json";
    public static var TEXT_OVERRIDE_FILE:String = "task_text_overrides.json";

    /**
     * 解析当前存档的覆盖层文件相对路径；无存档或槽位形态非法时返回 null。
     * 槽位合法形态与 SaveSlotKey/后端一致：不含路径分隔符与 ..，防越目录读取。
     */
    public static function resolvePath(fileName:String):String {
        var slot:String = (_root.savePath == undefined || _root.savePath == null) ? "" : String(_root.savePath);
        if (slot == "") return null;
        if (slot.indexOf("/") >= 0 || slot.indexOf("\\") >= 0 || slot.indexOf("..") >= 0) return null;
        return DIRECTORY + slot + "/" + fileName;
    }

    /** 变化清单里的文件是否位于某个存档覆盖层目录下（含别的槽位；调用方据此重新对齐当前槽位）。 */
    public static function isOverlayPath(relativePath:String):Boolean {
        return relativePath != null && String(relativePath).indexOf(DIRECTORY) == 0;
    }

    /**
     * 读取并解析一个覆盖层 JSON 文件。
     * @param relativePath resolvePath 给出的仓库相对路径。
     * @param onReady 解析成功时收到对象；缺失或解析不净时收到 null。
     */
    public static function load(relativePath:String, onReady:Function):Void {
        if (relativePath == null || onReady == null) return;
        PathManager.initialize(null);
        if (!PathManager.isEnvironmentValid()) {
            onReady(null);
            return;
        }
        var fullPath:String = PathManager.resolvePath(relativePath);
        if (fullPath == null) {
            onReady(null);
            return;
        }
        var lv:LoadVars = new LoadVars();
        lv.onData = function(raw:String):Void {
            if (raw == undefined || raw.length == 0) {
                onReady(null); // 缺失＝该存档无增量，静默跳过
                return;
            }
            // JSONLoader 默认宽容模式解析不净仍回调部分数据；覆盖层必须 fail-closed，
            // 所以用 JSON(true) 自解析并检查 errors，任何残留在错误里的解析都按失败处理。
            var parsed:Object = null;
            try {
                var parser:JSON = new JSON(true);
                parsed = parser.parse(raw);
                if (parsed == null || typeof parsed != "object" || parsed instanceof Array
                        || parser.errors.length > 0) {
                    parsed = null;
                }
            } catch (e:Object) {
                parsed = null;
            }
            if (parsed == null) {
                reportFailure("覆盖层文件解析不净，保留基础任务数据：" + relativePath);
                onReady(null);
                return;
            }
            onReady(parsed);
        };
        lv.load(fullPath);
    }

    private static function reportFailure(message:String):Void {
        trace("[TaskOverlayLoader] " + message);
        if (_root.server != undefined && typeof _root.server.sendServerMessage == "function") {
            _root.server.sendServerMessage("[TaskOverlayLoader] " + message);
        }
    }
}

