// org/flashNight/arki/component/Buff/PropertyContainer.as
import org.flashNight.arki.component.Buff.*;
import org.flashNight.gesh.property.*;

/**
 * 属性容器 - 与PropertyAccessor完美集成
 *
 * 设计理念：
 * - PropertyContainer 负责buff逻辑和数值计算
 * - PropertyAccessor 负责属性访问接口和性能优化
 * - 两者协作提供完整的动态属性管理方案
 *
 * 版本历史:
 * v2.6 (2026-01) - 路径绑定支持
 *   [FEAT] 新增 _accessTarget/_accessKey/_bindingParts 字段，支持嵌套属性路径
 *   [FEAT] 构造函数扩展，支持可选的路径绑定参数
 *   [FEAT] getFinalValue() 区分已绑定/未绑定状态
 *   [FEAT] 新增 syncAccessTarget() rebind 接口
 *   [FEAT] 新增 getBindingParts()/getAccessTarget()/isPathProperty() 查询接口
 *   [FIX] _markDirtyAndInvalidate() 处理 _accessor 为 null 的情况
 *
 * v2.5 (2026-01) - 契约化优化
 *   [PERF] addBuff 移除冗余的 isPod() 和属性名匹配检查
 *   [CONTRACT] 调用方（BuffManager._redistributePodBuffs）保证传入正确的 PodBuff
 *
 * v2.4 (2026-01) - 代码质量优化
 *   [FIX] _cachedFinalValue不显式初始化，AS2中Number默认为NaN
 *
 * v2.3 (2026-01) - 热路径优化
 *   [PERF] _computeFinalValue 移除冗余 isPod() 检查，由 BuffManager 分发逻辑保证
 *
 * v2.2 (2026-01) - 契约文档化
 *   [DOC] 添加OVERRIDE遍历方向契约说明
 *
 * v2.1 (2026-01) - Bugfix Review
 *   [P1-3] changeCallback无值比较问题 - 仅在值变化时触发回调
 *
 * ==================== 设计契约 ====================
 *
 * 【契约】OVERRIDE 冲突决策（遍历方向）
 *   - _computeFinalValue 使用 while(i--) 逆序遍历 _buffs 数组
 *   - 即：后添加的buff先apply，先添加的buff后apply
 *   - BuffCalculator 的 OVERRIDE 采用"最后写入wins"语义
 *   - 结果：多个 OVERRIDE 并存时，**添加顺序最早的 OVERRIDE 生效**
 *
 *   示例：
 *   - addBuff(OVERRIDE=500, id="first")  // 先添加
 *   - addBuff(OVERRIDE=999, id="second") // 后添加
 *   - 最终值 = 500（因为first最后apply，覆盖了second）
 *
 *   若需"新覆盖旧"语义：
 *   - 使用同ID替换机制（BuffManager.addBuff同ID会先移除旧buff）
 *   - 或者只保持同时存在一个OVERRIDE
 *
 * ================================================
 *
 * @version 2.6
 */
class org.flashNight.arki.component.Buff.PropertyContainer {
    
    // 核心数据
    private var _propertyName:String;
    private var _baseValue:Number;
    private var _buffs:Array;
    private var _calculator:IBuffCalculator;

    // 集成组件
    private var _target:Object;           // root target（用于 BuffContext.target）
    private var _accessor:PropertyAccessor;

    // 路径绑定支持（v2.6）
    // 对于一级属性：_accessTarget == _target, _accessKey == _propertyName
    // 对于路径属性：_accessTarget == 叶子父对象, _accessKey == 叶子字段名
    private var _accessTarget:Object;     // 真正 addProperty 的对象
    private var _accessKey:String;        // 真正被接管的字段名
    private var _bindingParts:Array;      // 缓存路径分段，如 ["长枪属性", "power"]
    
    // 缓存和优化
    // [v2.4] 不显式初始化，AS2中Number默认为NaN，表示"未计算"状态
    // 用于_computeFinalValue中的值变化检测（首次计算时isNaN(oldValue)为true）
    private var _cachedFinalValue:Number;
    private var _isDirty:Boolean = true;
    private var _changeCallback:Function;
    private var _buffContext:BuffContext; // [优化] 缓存BuffContext实例，避免重复创建
    
    /**
     * 构造函数
     *
     * v2.6 扩展：支持路径绑定（可选参数）
     * - 不传后三个参数：一级属性，accessTarget=target, accessKey=propertyName
     * - 传入后三个参数：路径属性，accessTarget=叶子父对象, accessKey=叶子字段名
     *
     * @param target 目标对象（root target，用于 BuffContext.target）
     * @param propertyName 属性名/路径（如 "atk" 或 "长枪属性.power"）
     * @param baseValue 基础值
     * @param changeCallback 值变化回调（可选）
     * @param accessTarget 可选：真正 addProperty 的对象
     * @param accessKey 可选：真正被接管的字段名
     * @param bindingParts 可选：路径分段数组
     */
    public function PropertyContainer(
        target:Object,
        propertyName:String,
        baseValue:Number,
        changeCallback:Function
        // 后三个为可选参数，通过 arguments 读取
    ) {
        this._target = target;
        this._propertyName = propertyName;
        this._baseValue = baseValue;
        this._changeCallback = changeCallback;
        this._buffs = [];
        this._calculator = new BuffCalculator();

        // [v2.6] 路径绑定参数处理
        // 注意：只用 arguments.length 判断，因为 AS2 中 null == undefined
        // 当路径解析失败时，BuffManager 会传入 null 作为 accessTarget
        if (arguments.length > 4) {
            // 路径属性：传入了 accessTarget/accessKey/bindingParts
            // accessTarget 可能为 null（路径解析失败的未绑定状态）
            this._accessTarget = arguments[4];
            this._accessKey = arguments[5];
            this._bindingParts = arguments[6];
        } else {
            // 一级属性：accessTarget 与 accessKey 等同于 target 与 propertyName
            this._accessTarget = target;
            this._accessKey = propertyName;
            this._bindingParts = null;
        }

        // [优化] 在构造时创建一次BuffContext，之后重复使用
        // 注意：propertyName 用完整路径（如 "长枪属性.power"），target 用 root target
        this._buffContext = new BuffContext(
            this._propertyName,
            this._target,
            null,
            {}
        );

        // [v2.6] 根据 _accessTarget 是否存在决定是否创建 accessor
        if (this._accessTarget != null) {
            // 创建 PropertyAccessor，安装到 accessTarget 上
            this._accessor = new PropertyAccessor(
                this._accessTarget,
                this._accessKey,
                baseValue,
                this._createComputeFunction(), // 计算函数
                this._createSetterFunction(),   // 设置回调
                null                          // 暂不使用验证函数
            );
        } else {
            // 未绑定状态（accessTarget 为 null，如路径解析失败）
            // 不创建 accessor，但容器仍可以持有 buff，等待 rebind
            this._accessor = null;
        }
    }
    
    // =========================================================================
    // 核心计算与集成
    // =========================================================================
    
    /**
     * 核心计算方法 - 只处理 PodBuff
     *
     * [v2.3] 热路径优化：移除 isPod() 检查
     * - addBuff() 入口已保证只有 PodBuff 能进入 _buffs 数组
     * - BuffManager 分发时也有前置检查
     * - 消除热路径上每个 buff 的冗余函数调用
     *
     * [P1-3 修复] 添加值比较，仅在值变化时触发回调
     */
    private function _computeFinalValue():Number {
        if (!this._isDirty) {
            return this._cachedFinalValue;
        }

        this._calculator.reset();

        // [v2.3] 直接遍历，不再检查 isPod()（由 addBuff 入口保证）
        var i:Number = this._buffs.length;
        var buff:IBuff;
        while (i--) {
            buff = this._buffs[i];
            if (buff && buff.isActive()) {
                buff.applyEffect(this._calculator, this._buffContext);
            }
        }

        // [P1-3 修复] 保存旧值用于比较
        var oldValue:Number = this._cachedFinalValue;
        var newValue:Number = this._calculator.calculate(this._baseValue);
        this._cachedFinalValue = newValue;
        this._isDirty = false;

        // [P1-3 修复] 仅在值变化时触发回调（注意处理NaN情况）
        if (this._changeCallback) {
            // 值变化的判断：旧值是NaN，或者新旧值不相等
            var valueChanged:Boolean = isNaN(oldValue) || (oldValue != newValue);
            if (valueChanged) {
                this._changeCallback(this._propertyName, newValue);
            }
        }

        return this._cachedFinalValue;
    }
    
    /**
     * 创建计算函数 - 给PropertyAccessor使用
     */
    private function _createComputeFunction():Function {
        var self:PropertyContainer = this;
        return function():Number {
            return self._computeFinalValue();
        };
    }
    
    /**
     * 创建一个合格的 setter 函数，用于外部直接设置属性值
     */
    private function _createSetterFunction():Function {
        var self:PropertyContainer = this;
        return function(newValue:Number):Void {
            if (!isNaN(newValue)) {
                self._baseValue = newValue;
                self._markDirtyAndInvalidate();
            }
        };
    }
    
    // =========================================================================
    // 公共接口 - Buff管理
    // =========================================================================
    
    /**
     * 添加buff
     *
     * 【契约8】调用方保证传入正确的 PodBuff（v2.5）
     *   - BuffManager._redistributePodBuffs 已按 targetProperty 分发
     *   - 此处不再重复验证 isPod() 和属性名匹配
     *   - 若绕过 BuffManager 直接调用，调用方自行负责正确性
     *
     * @param buff 要添加的 PodBuff（由调用方保证类型和属性正确）
     */
    public function addBuff(buff:IBuff):Void {
        if (!buff) return;
        this._buffs.push(buff);
        this._markDirtyAndInvalidate();
    }
    
    /**
     * 移除buff
     *
     * [Phase D / P2-1] 默认shouldDestroy=false，避免外部代码意外销毁BuffManager拥有的buff
     * BuffManager负责buff的生命周期管理，外部不应销毁buff
     *
     * @param buffId 要移除的buff ID
     * @param shouldDestroy 是否销毁buff（默认false，由BuffManager管理生命周期）
     * @return Boolean 是否成功移除
     */
    public function removeBuff(buffId:String, shouldDestroy:Boolean):Boolean {
        // [Phase D / P2-1] 默认不销毁
        if (shouldDestroy == undefined) shouldDestroy = false;

        // [优化] 使用反向循环遍历，便于安全地使用splice
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            if (this._buffs[i].getId() == buffId) {
                var removedBuff:IBuff = this._buffs.splice(i, 1)[0];
                if (shouldDestroy) {
                    removedBuff.destroy();
                }
                this._markDirtyAndInvalidate();
                return true;
            }
        }
        return false;
    }
    
    /**
     * 移除所有buff
     *
     * [Phase C / P1-5] 默认shouldDestroy=false，避免外部代码意外销毁BuffManager拥有的buff
     * BuffManager负责buff的生命周期管理，外部不应调用带destroy的版本
     */
    public function clearBuffs(shouldDestroy:Boolean):Void {
        // [Phase C / P1-5] 默认不销毁，由BuffManager管理生命周期
        if (shouldDestroy == undefined) shouldDestroy = false;

        if (shouldDestroy) {
            while (_buffs.length > 0) _buffs.pop().destroy();
        } else {
            _buffs.length = 0;              // 只清列表，保留对象生命周期
        }
        _markDirtyAndInvalidate();
    }

    
    // =========================================================================
    // 公共接口 - 值管理
    // =========================================================================
    
    /**
     * 设置基础值
     *
     * [Phase A / P1-6] 添加NaN防守
     */
    public function setBaseValue(value:Number):Void {
        // [Phase A / P1-6] NaN防守
        var v:Number = Number(value);
        if (isNaN(v)) {
            trace("[PropertyContainer] 警告：setBaseValue收到NaN，已忽略");
            return;
        }

        if (this._baseValue != v) {
            this._baseValue = v;
            this._markDirtyAndInvalidate();
        }
    }
    
    /**
     * 获取基础值
     */
    public function getBaseValue():Number {
        return this._baseValue;
    }
    
    /**
     * 获取最终计算值
     *
     * [v2.6] 路径绑定支持：
     * - 已绑定：通过 _accessTarget[_accessKey] 读取（走 accessor 热路径）
     * - 未绑定：返回 _baseValue（不触发回调，避免错误级联）
     *
     * 【设计说明】未绑定时不能调用 _computeFinalValue()，因为：
     * 1. _computeFinalValue() 会触发 _changeCallback
     * 2. 未绑定时不应该通知级联调度器
     */
    public function getFinalValue():Number {
        if (this._accessTarget != null) {
            // 已绑定：走 accessor（热路径）
            return Number(this._accessTarget[this._accessKey]);
        } else {
            // 未绑定：直接返回 base，不触发回调
            // 因为没有 accessor，buff 效果本来就无法体现在任何对象上
            return this._baseValue;
        }
    }
    
    /**
     * 强制重新计算
     */
    public function forceRecalculate():Number {
        this._markDirtyAndInvalidate();
        return this.getFinalValue();
    }
    
    // =========================================================================
    // 公共接口 - 查询与调试
    // =========================================================================
    
    /**
     * 获取buff数量
     */
    public function getBuffCount():Number {
        return this._buffs.length;
    }
    
    /**
     * 获取激活的buff数量
     */
    public function getActiveBuffCount():Number {
        var count:Number = 0;
        // [优化] 使用反向while循环
        var i:Number = this._buffs.length;
        while (i--) {
            if (this._buffs[i] && this._buffs[i].isActive()) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * 检查是否有特定ID的buff
     */
    public function hasBuff(buffId:String):Boolean {
        // [优化] 使用反向while循环
        var i:Number = this._buffs.length;
        while (i--) {
            if (this._buffs[i].getId() == buffId) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * 获取所有buff的副本（调试用）
     */
    public function getBuffs():Array {
        return this._buffs.slice();
    }
    
    /**
     * 获取属性名
     */
    public function getPropertyName():String {
        return this._propertyName;
    }
    
    // =========================================================================
    // 内部方法和生命周期
    // =========================================================================
    
    /**
     * 标记为脏数据并使PropertyAccessor缓存失效
     *
     * [v2.6] 处理未绑定状态：若 _accessor 为 null 只置脏标记
     */
    private function _markDirtyAndInvalidate():Void {
        this._isDirty = true;
        if (this._accessor != null) {
            this._accessor.invalidate(); // 通知PropertyAccessor重新计算
        }
    }
    
    // 建议：容器持有底层 accessor 的引用，例如 this._accessor
    public function finalizeToPlainProperty():Void {
        if (this._accessor != null) {
            this._accessor.detach();  // 固化"当前可见值"为普通数据属性，并与 target 解耦
        }
    }

    // =========================================================================
    // 路径绑定支持（v2.6）
    // =========================================================================

    /**
     * 同步 accessor 的安装目标（用于 rebind）
     *
     * 当路径根对象被替换（如换装 target.长枪属性 = newData）时调用此方法。
     * 由 BuffManager._syncPathBindings() 内部调用。
     *
     * 【关键】rebind 顺序：
     * 1. 解绑旧 accessor（避免内存泄漏和旧对象读错值）
     * 2. 恢复旧对象的原始值（写回 base，不是 final）
     * 3. 切换到新对象
     * 4. 用新对象的 raw 值作为新 base
     * 5. 重建 accessor
     *
     * @param newAccessTarget 新的 accessor 安装点（可为 null 表示解绑）
     * @param newRawBase 新对象上的原始值（必须从新对象读取）
     * @return 是否发生了绑定变化
     */
    public function syncAccessTarget(newAccessTarget:Object, newRawBase:Number):Boolean {
        // 检测是否真的需要变化
        if (this._accessTarget === newAccessTarget) {
            return false; // 同一个对象引用，无需 rebind
        }

        // 记录旧绑定信息
        var oldOwner:Object = this._accessTarget;
        var oldKey:String = this._accessKey;
        var oldBase:Number = this._baseValue;

        // 步骤 1 & 2：解绑旧 accessor 并恢复 base
        if (this._accessor != null) {
            // 销毁 accessor（会 delete oldOwner[oldKey]）
            this._accessor.destroy();
            this._accessor = null;

            // 恢复旧对象的 base 值（不是 final，避免污染旧对象）
            if (oldOwner != null) {
                oldOwner[oldKey] = oldBase;
            }
        }

        // 步骤 3 & 4：切换到新绑定
        this._accessTarget = newAccessTarget;
        // NaN 防守：使用新 raw 值，若无效则保留原 base
        if (!isNaN(newRawBase)) {
            this._baseValue = newRawBase;
        }

        // 步骤 5：重建 accessor（若新目标有效）
        if (this._accessTarget != null) {
            this._accessor = new PropertyAccessor(
                this._accessTarget,
                this._accessKey,
                this._baseValue,
                this._createComputeFunction(),
                this._createSetterFunction(),
                null
            );
        }

        // 标脏（调用方通常会 forceRecalculate）
        this._markDirtyAndInvalidate();

        return true;
    }

    /**
     * 获取路径分段数组（用于 BuffManager 的 rebind 检测）
     * @return 路径分段数组，一级属性返回 null
     */
    public function getBindingParts():Array {
        return this._bindingParts;
    }

    /**
     * 获取当前 accessor 安装目标（用于 BuffManager 的 rebind 检测）
     * @return 当前安装点对象
     */
    public function getAccessTarget():Object {
        return this._accessTarget;
    }

    /**
     * 检查是否为路径属性
     * @return 若为路径属性返回 true
     */
    public function isPathProperty():Boolean {
        return this._bindingParts != null && this._bindingParts.length > 1;
    }

    /**
     * 销毁容器
     */
    public function destroy():Void {
        this.clearBuffs();
        
        if (this._accessor) {
            this._accessor.destroy();
            this._accessor = null;
        }
        
        this._target = null;
        this._calculator = null;
        this._changeCallback = null;
        this._buffs = null;
        this._buffContext = null; // 清理缓存的Context
    }
    
    /**
     * 调试信息
     */
    public function toString():String {
        return "[PropertyContainer property: " + this._propertyName + 
               ", base: " + this._baseValue + 
               ", final: " + this.getFinalValue() + 
               ", buffs: " + this.getBuffCount() + "]";
    }
}