/**
 * NightVisionManager.as
 * 位于：org.flashNight.arki.weather
 *
 * 夜视仪管理器 —— 负责夜视仪装备的注册/注销/校验。
 *
 * 设计要点：
 * - 区分"注册态"（_registered）和"激活态"（_active）
 *   注册态 = 装备已穿戴，仅 unregister() 可清除
 *   激活态 = 当前光照在有效范围内，随光照变化自动切换
 * - 解决旧代码的三个 Bug：
 *   Bug1: 嵌套 subscribeOnce 泄漏 → 装备侧不再管理事件链
 *   Bug2: 亮度越界永久清除 → validate() 只切换 _active，不清除 _registered
 *   Bug3: 双重卸载回调 → 装备侧只保留生命周期函数列表卸载
 *
 * @class NightVisionManager
 */
class org.flashNight.arki.weather.NightVisionManager {

    /** 注册配置，仅 unregister() 可清除 */
    private var _registered:Object;

    /** 当前帧是否处于激活状态 */
    private var _active:Boolean;

    /**
     * 构造函数
     */
    public function NightVisionManager() {
        this._registered = null;
        this._active = false;
    }

    /**
     * 注册夜视仪配置。
     * 如果已有注册配置，先清理旧状态再注册新配置。
     *
     * @param owner 夜视仪配置对象，需包含:
     *   - 视觉情况:String
     *   - 最小启动亮度:Number
     *   - 最大启动亮度:Number
     *   - 启用装备:String (可选)
     *   - 装备类型:String (可选)
     */
    public function register(owner:Object):Void {
        this._registered = owner || null;
        this._active = false;
    }

    /**
     * 注销夜视仪配置（幂等）。
     * 支持两种匹配方式：引用匹配 或 装备标识匹配。
     *
     * @param owner 要注销的配置对象
     * @return Boolean 是否成功注销
     */
    public function unregister(owner:Object):Boolean {
        var cur:Object = this._registered;
        if (cur == null) {
            return false;
        }

        // 引用匹配
        if (cur === owner) {
            this._registered = null;
            this._active = false;
            return true;
        }

        // 装备标识匹配（兼容：调用方没有拿到原对象引用时）
        if (cur.启用装备 != undefined && cur.装备类型 != undefined &&
            owner.启用装备 != undefined && owner.装备类型 != undefined &&
            cur.启用装备 === owner.启用装备 && cur.装备类型 === owner.装备类型) {
            this._registered = null;
            this._active = false;
            return true;
        }

        return false;
    }

    /**
     * 防御性校验 + 亮度范围判断。
     *
     * 如果夜视仪已注册且光照在有效范围内，返回视觉情况字符串；
     * 否则返回 null。
     *
     * 注意：即使光照越界，也只设 _active = false，不清除 _registered。
     *
     * @param lightLevel  当前光照等级
     * @param controlTarget  当前控制目标 MovieClip（用于防御性校验）
     * @return 视觉情况字符串，或 null
     */
    public function validate(lightLevel:Number, controlTarget:MovieClip):String {
        var cfg:Object = this._registered;
        if (cfg == null || cfg.视觉情况 == undefined) {
            this._active = false;
            return null;
        }

        // 防御性校验：确认装备仍然匹配
        if (cfg.装备类型 != undefined && cfg.启用装备 != undefined) {
            if (controlTarget == undefined) {
                // 控制对象不存在，清除注册
                this._registered = null;
                this._active = false;
                return null;
            }
            var equipSlot:Object = controlTarget[cfg.装备类型];
            if (equipSlot == undefined || equipSlot.name !== cfg.启用装备) {
                // 装备已变更，清除注册
                this._registered = null;
                this._active = false;
                return null;
            }
        }

        // 亮度范围判断
        if (lightLevel >= cfg.最小启动亮度 && lightLevel <= cfg.最大启动亮度) {
            this._active = true;
            return cfg.视觉情况;
        }

        // 亮度越界：只切换激活状态，不清除注册
        this._active = false;
        return null;
    }

    /**
     * 返回当前注册的夜视仪配置引用（只读用途）。
     * @return 注册配置对象，或 null
     */
    public function getRegistered():Object {
        return this._registered;
    }

    /**
     * 返回当前是否处于激活状态。
     * @return Boolean
     */
    public function isActive():Boolean {
        return this._active;
    }

    /**
     * 清除所有状态（用于强制重置）。
     */
    public function clear():Void {
        this._registered = null;
        this._active = false;
    }
}
