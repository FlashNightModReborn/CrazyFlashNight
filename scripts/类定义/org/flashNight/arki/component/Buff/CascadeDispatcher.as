// org/flashNight/arki/component/Buff/CascadeDispatcher.as

/**
 * CascadeDispatcher - 级联调度器
 *
 * 用于处理"属性变化 → 触发级联动作"的帧内合并。
 * 解决同一帧内多个属性变化导致重复初始化的问题。
 *
 * 设计原则：
 * - 属性到分组的多对多映射：一个属性可触发多个分组，一个分组可被多个属性触发
 * - 帧内合并：同一帧内同一分组只执行一次
 * - 防递归：flush 期间的新 dirty 等下一帧
 *
 * 使用示例：
 *   // 配置
 *   dispatcher.map("长枪属性.power", "longGunReinit");
 *   dispatcher.action("longGunReinit", function(){ target.man.初始化长枪射击函数(); });
 *
 *   // 回调（由 BuffManager.onPropertyChanged 调用）
 *   dispatcher.mark(propId);
 *
 *   // 帧末（在 BuffManager.update() 后调用）
 *   dispatcher.flush();
 *
 * 版本历史:
 * v1.0 (2026-01) - 初始版本
 *   [FEAT] 支持属性到分组的映射
 *   [FEAT] 帧内合并执行
 *   [FEAT] 防递归保护
 *
 * @version 1.0
 */
class org.flashNight.arki.component.Buff.CascadeDispatcher {

    // 配置映射
    private var _propToGroups:Object;    // { propId: [groupId, ...] }
    private var _groupActions:Object;     // { groupId: Function }

    // 运行时状态
    private var _dirtyGroups:Object;      // { groupId: true }
    private var _isFlushing:Boolean;      // 防递归标志

    /**
     * 构造函数
     */
    public function CascadeDispatcher() {
        this._propToGroups = {};
        this._groupActions = {};
        this._dirtyGroups = {};
        this._isFlushing = false;
    }

    // =========================================================================
    // 配置接口
    // =========================================================================

    /**
     * 映射属性到分组
     *
     * 一个属性变化时，会标记其所属的所有分组为 dirty。
     *
     * @param propId 属性标识（如 "长枪属性.power"）
     * @param groupId 分组标识（如 "longGunReinit"）
     */
    public function map(propId:String, groupId:String):Void {
        if (propId == null || groupId == null) return;

        var groups:Array = this._propToGroups[propId];
        if (groups == null) {
            groups = [];
            this._propToGroups[propId] = groups;
        }

        // 避免重复添加
        for (var i:Number = 0; i < groups.length; i++) {
            if (groups[i] == groupId) return;
        }
        groups.push(groupId);
    }

    /**
     * 批量映射多个属性到同一分组
     *
     * @param propIds 属性标识数组
     * @param groupId 分组标识
     */
    public function mapAll(propIds:Array, groupId:String):Void {
        if (propIds == null || groupId == null) return;

        for (var i:Number = 0; i < propIds.length; i++) {
            this.map(propIds[i], groupId);
        }
    }

    /**
     * 设置分组的执行动作
     *
     * @param groupId 分组标识
     * @param action 执行函数（无参数）
     */
    public function action(groupId:String, actionFunc:Function):Void {
        if (groupId == null || actionFunc == null) return;
        this._groupActions[groupId] = actionFunc;
    }

    /**
     * 移除属性到分组的映射
     *
     * @param propId 属性标识
     * @param groupId 分组标识（可选，为 null 则移除该属性的所有映射）
     */
    public function unmap(propId:String, groupId:String):Void {
        if (propId == null) return;

        if (groupId == null) {
            // 移除属性的所有映射
            delete this._propToGroups[propId];
        } else {
            // 移除特定映射
            var groups:Array = this._propToGroups[propId];
            if (groups == null) return;

            for (var i:Number = groups.length - 1; i >= 0; i--) {
                if (groups[i] == groupId) {
                    groups.splice(i, 1);
                    break;
                }
            }

            // 若数组为空，清理
            if (groups.length == 0) {
                delete this._propToGroups[propId];
            }
        }
    }

    /**
     * 移除分组的执行动作
     *
     * @param groupId 分组标识
     */
    public function removeAction(groupId:String):Void {
        if (groupId == null) return;
        delete this._groupActions[groupId];
    }

    // =========================================================================
    // 运行时接口
    // =========================================================================

    /**
     * 标记属性变化
     *
     * 将该属性所属的所有分组标记为 dirty。
     * 由 BuffManager.onPropertyChanged 回调调用。
     *
     * @param propId 发生变化的属性标识
     */
    public function mark(propId:String):Void {
        if (propId == null) return;

        var groups:Array = this._propToGroups[propId];
        if (groups == null) return;

        for (var i:Number = 0; i < groups.length; i++) {
            this._dirtyGroups[groups[i]] = true;
        }
    }

    /**
     * 执行所有 dirty 分组的动作
     *
     * 【防递归】若在 flush 期间被调用：
     * - 返回不执行
     * - 新标记的 dirty 会在下一帧处理
     *
     * 建议在 BuffManager.update() 结束后调用。
     */
    public function flush():Void {
        // 防递归
        if (this._isFlushing) {
            return;
        }
        this._isFlushing = true;

        // 快照当前 dirty，清空后再执行
        // 这样 flush 期间的新 mark 会写入新的 _dirtyGroups
        var toFlush:Object = this._dirtyGroups;
        this._dirtyGroups = {};

        // 执行每个 dirty 分组的动作
        for (var groupId:String in toFlush) {
            var actionFunc:Function = this._groupActions[groupId];
            if (actionFunc != null) {
                // 使用 try-catch 保护，避免一个动作失败影响其他
                try {
                    actionFunc();
                } catch (e) {
                    trace("[CascadeDispatcher] 动作执行失败: " + groupId + " - " + e);
                }
            }
        }

        this._isFlushing = false;
    }

    /**
     * 检查是否有 dirty 分组等待执行
     *
     * @return 若有 dirty 分组返回 true
     */
    public function hasDirty():Boolean {
        for (var k:String in this._dirtyGroups) {
            return true;
        }
        return false;
    }

    /**
     * 清除所有 dirty 标记（不执行动作）
     */
    public function clearDirty():Void {
        this._dirtyGroups = {};
    }

    /**
     * 销毁调度器
     */
    public function destroy():Void {
        this._propToGroups = null;
        this._groupActions = null;
        this._dirtyGroups = null;
    }

    /**
     * 调试信息
     */
    public function toString():String {
        var propCount:Number = 0;
        var groupCount:Number = 0;
        var dirtyCount:Number = 0;

        for (var p:String in this._propToGroups) propCount++;
        for (var g:String in this._groupActions) groupCount++;
        for (var d:String in this._dirtyGroups) dirtyCount++;

        return "[CascadeDispatcher props:" + propCount +
               " groups:" + groupCount +
               " dirty:" + dirtyCount + "]";
    }
}
