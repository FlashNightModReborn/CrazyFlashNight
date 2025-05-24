import org.flashNight.gesh.json.LoadJson.BaseJSONLoader;

class org.flashNight.gesh.json.LoadJson.NPCSkillLoader extends BaseJSONLoader {
    private static var instance:NPCSkillLoader = null;

    /**
     * 获取单例实例。
     * @return NPCSkillLoader 实例。
     */
    public static function getInstance():NPCSkillLoader {
        if (instance == null) {
            instance = new NPCSkillLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 npc_skills.json 的相对路径，并以LiteJSON模式解析。
     */
    private function NPCSkillLoader() {
        super("data/skills/npc_skills.json", "LiteJSON");
    }

    /**
     * 覆盖基类的 load 方法，实现 npc_skills.json 的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadNPCSkills(onLoadHandler, onErrorHandler);
    }

    /**
     * 加载 npc_skills.json 文件。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadNPCSkills(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 调用基类的 load 方法
        super.load(function(data:Object):Void {
            trace("NPCSkillLoader: 文件加载成功！");

            if (onLoadHandler != null) onLoadHandler(data);
        }, function():Void {
            trace("NPCSkillLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的 NPC技能 数据。
     * @return Object 解析后的数据对象，如果尚未加载，则返回 null。
     */
    public function getBGMListData():Object {
        return this.getData();
    }

    /**
     * 覆盖基类的 reload 方法，实现 npc_skills.json 的重新加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 清空缓存并重新加载
        super.reload(onLoadHandler, onErrorHandler);
    }

    /**
     * 覆盖基类的 getData 方法，确保返回正确的数据。
     * @return Object 解析后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return super.getData();
    }
}
