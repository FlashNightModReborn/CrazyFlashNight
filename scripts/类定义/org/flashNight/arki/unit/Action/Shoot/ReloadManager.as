import org.flashNight.arki.item.*;
import org.flashNight.arki.bullet.BulletComponent.Type.*;
/**
 * ReloadManager.as
 * 
 * 武器换弹管理器类，将原 _root.主角函数 中的换弹和弹药显示逻辑封装到此类中
 * 经过重构优化，集中管理换弹相关的所有功能
 * 主要负责：
 * 1. 开始换弹、换弹匣和结束换弹的流程控制
 * 2. 单武器和双武器系统的换弹逻辑
 * 3. UI界面中弹药数量的显示更新
 * 4. 弹匣消耗和库存管理的交互
 */
class org.flashNight.arki.unit.Action.Shoot.ReloadManager {
    
    /**
     * 开始武器换弹
     * @param target 目标MovieClip (原this引用)
     * @param parentRef 父级引用 (原_parent引用)
     * @param rootRef 根引用 (原_root引用)
     */
    public static function startReload(target:MovieClip, parentRef:Object, rootRef:Object):Void {
        var attackMode:String = parentRef.攻击模式;

        // 如果已在换弹或弹匣已满，则直接返回
        if (target.换弹标签 || parentRef[attackMode].value.shot == 0) {
            return;
        }

        // 检查是否为玩家控制的角色
        if (rootRef.控制目标 === parentRef._name) {
            // 获取武器属性，检查是否为逐发换弹类型
            var weaponAttr:Object = parentRef[attackMode + "属性"];
            var reloadType:String = weaponAttr.reloadType;

            // 逐发换弹（tube类型）：有残余换弹值时可以继续换弹，无需弹匣
            if (reloadType == "tube" && parentRef[attackMode].value.reloadCount > 0) {
                target.gotoAndPlay("换弹匣");
                return;
            }

            // 检查是否有可用弹匣
            if (ItemUtil.singleContain(target.使用弹匣名称, 1) != null) {
                target.gotoAndPlay("换弹匣");
            }
        } else {
            // AI角色直接进入换弹状态
            target.gotoAndPlay("换弹匣");
        }
    }
    
    /**
     * 执行换弹匣操作
     * @param target 目标MovieClip (原this引用)
     * @param parentRef 父级引用 (原_parent引用)
     * @param rootRef 根引用 (原_root引用)
     */
    public static function reloadMagazine(target:MovieClip, parentRef:Object, rootRef:Object):Void {
        // 逐发换弹路径中，弹匣消耗和shot重置已在门禁中处理，此处直接返回
        if (target.perRoundReload) {
            return;
        }

        var attackMode:String = parentRef.攻击模式;

        // 重置射击次数
        parentRef[attackMode].value.shot = 0;

        // 检查是否为玩家控制的角色
        if (rootRef.控制目标 === parentRef._name) {
            // 消耗一个弹匣
            ItemUtil.singleSubmit(target.使用弹匣名称, 1);

            // 更新剩余弹匣数
            target.剩余弹匣数 = ItemUtil.getTotal(target.使用弹匣名称);

            // 检查弹匣是否耗尽
            if (target.剩余弹匣数 === 0) {
                rootRef.发布消息("弹匣耗尽！");
            }

            // 重置副武器发射数据
            parentRef.当前弹夹副武器已发射数 = 0;

            // 刷新UI显示
            ReloadManager.updateAmmoDisplay(target, parentRef, rootRef);
        }
    }
    
    /**
     * 结束换弹过程
     * @param target 目标MovieClip (原this引用)
     */
    public static function finishReload(target:MovieClip):Void {
        target.gotoAndStop("空闲");
    }
    
    /**
     * 更新弹药显示界面
     * @param target 目标MovieClip (原this引用)
     * @param parentRef 父级引用 (原_parent引用)
     * @param rootRef 根引用 (原_root引用)
     */
    public static function updateAmmoDisplay(target:MovieClip, parentRef:Object, rootRef:Object):Void {
        // 如果控制目标不匹配，则直接返回
        if (rootRef.控制目标 != parentRef._name) {
            return;
        }
        
        // 缓存UI引用
        var ui:Object = rootRef.玩家信息界面.玩家必要信息界面;
        var mode:String = parentRef.攻击模式;
        var weapons:Array = [];
        
        // 构造武器配置
        if (mode === "双枪") {
            // 主手武器配置
            weapons.push({
                data: parentRef.手枪属性,
                capacity: parentRef.手枪弹匣容量,
                shot: parentRef.手枪.value.shot,
                uiBullet: "子弹数",
                uiMag: "弹夹数",
                magCount: target.主手剩余弹匣数
            });
            
            // 副手武器配置
            weapons.push({
                data: parentRef.手枪2属性,
                capacity: parentRef.手枪2弹匣容量,
                shot: parentRef.手枪2.value.shot,
                uiBullet: "子弹数_2",
                uiMag: "弹夹数_2",
                magCount: target.副手剩余弹匣数
            });
        } else {
            // 单武器配置
            var singleShot:Number = parentRef[mode].value.shot;
            weapons.push({
                data: parentRef[mode + "属性"],
                capacity: parentRef[mode + "弹匣容量"],
                shot: singleShot,
                uiBullet: "子弹数",
                uiMag: "弹夹数",
                magCount: target.剩余弹匣数
            });
        }
        
        // 遍历更新每个武器的UI显示
        for (var i:Number = 0; i < weapons.length; i++) {
            var w:Object = weapons[i];
            
            // 计算子弹消耗系数
            var cost:Number = BulletTypesetter.isVertical(w.data.bullet) ? w.data.split : 1;
            
            // 计算剩余子弹数
            var remaining:Number = w.capacity - w.shot;
            // 更新UI显示
            ui[w.uiBullet] = cost * remaining;
            ui[w.uiMag] = w.magCount;
        }
    }
    
    /**
     * 为双枪系统创建开始换弹函数
     * 封装了双枪模式下的换弹逻辑，使用武器状态管理器进行状态判断
     * 
     * @param target        目标 MovieClip
     * @param parentRef     父级引用
     * @param rootRef       根引用
     * @param stateManager  武器状态管理器
     * @return 返回开始换弹函数
     */
    public static function createDualGunReloadStartFunction(target:MovieClip, parentRef:Object, rootRef:Object, stateManager:Object):Function {
        var self:MovieClip = target;
        
        return function():Void {
            var that:MovieClip = self;
            
            // 检查换弹标签
            if (that.换弹标签) {
                return;
            }
            
            // 更新武器状态
            stateManager.updateState();
            
            // 使用状态管理器检查是否需要任何换弹
            if (!stateManager.needsAnyReload()) {
                return;
            }
            
            if (rootRef.控制目标 === parentRef._name) {
                // 使用状态管理器决定换弹策略
                var passiveSkills:Object = parentRef.被动技能;
                var hasImpactChain:Boolean = Boolean(passiveSkills && passiveSkills.冲击连携 && passiveSkills.冲击连携.启用);
                var reloadDecision:Number = stateManager.decideReloadHand(hasImpactChain, that);

                switch (reloadDecision) {
                    case 1: // 主手换弹
                        that.gotoAndPlay("主手换弹匣");
                        return;
                    case 2: // 副手换弹
                        that.gotoAndPlay("副手换弹匣");
                        return;
                    default: // 0: 不需要换弹
                        that.gotoAndPlay("换弹结束");
                }
            } else {
                that.gotoAndPlay("主手换弹匣");
            }
        };
    }
    
    /**
     * 为双枪系统创建手枪换弹函数
     * 封装了特定手枪的换弹逻辑，使用武器状态管理器进行状态判断
     * 
     * @param target        目标 MovieClip
     * @param parentRef     父级引用
     * @param rootRef       根引用
     * @param config        武器手配置对象
     * @param stateManager  武器状态管理器
     * @return 返回特定手的换弹匣函数
     */
    public static function createHandReloadFunction(target:MovieClip, parentRef:Object, rootRef:Object, config:Object, stateManager:Object):Function {
        var self:MovieClip = target;
        var handPrefix:String = config.handPrefix;
        var weaponType:String = config.weaponType;
        var magNameProp:String = handPrefix + "使用弹匣名称";
        
        return function():Void {
            var that:MovieClip = self;
            
            // 重置射击次数
            parentRef[weaponType].value.shot = 0;

            if (rootRef.控制目标 === parentRef._name) {
                // 使用弹匣
                ItemUtil.singleSubmit(that[magNameProp], 1);
                
                // 更新弹匣数量（两把枪都需要更新）
                that.主手剩余弹匣数 = ItemUtil.getTotal(that.主手使用弹匣名称);
                that.副手剩余弹匣数 = ItemUtil.getTotal(that.副手使用弹匣名称);
                
                // 检查弹匣耗尽
                if (that[handPrefix + "剩余弹匣数"] === 0) {
                    rootRef.发布消息("弹匣耗尽！");
                }
                
                // 更新物品与显示
                ReloadManager.updateAmmoDisplay(that, parentRef, rootRef);
                
                // 更新武器状态
                stateManager.updateState();

                var passiveSkills:Object = parentRef.被动技能;
                var hasImpactChain:Boolean = Boolean(passiveSkills && passiveSkills.冲击连携 && passiveSkills.冲击连携.启用);
                
                // 使用状态管理器检查是否可以结束换弹
                if (handPrefix == "主手") {
                    if (stateManager.canFinishMainHandReload(that.主手剩余弹匣数, that.副手剩余弹匣数, hasImpactChain)) {
                        that.gotoAndPlay("换弹结束");
                    }
                } else {
                    if (stateManager.canFinishSubHandReload(that.主手剩余弹匣数, that.副手剩余弹匣数, hasImpactChain)) {
                        that.gotoAndPlay("换弹结束");
                    }
                }
            }
        };
    }

    // ============================================================
    // 换弹负担系统 (Reload Burden System)
    // ============================================================

    /**
     * 计算每次逐发换弹循环应该填充的发数
     * 目的：大弹容机枪减少循环次数，提升换弹体验
     *
     * 设计哲学：
     * - 小容量（≤10发）：逐发换弹（1发/循环），灵活快速
     * - 中容量（11-30发）：每次2发，平衡手感
     * - 中大容量（31-60发）：每次3发
     * - 大容量（61-100发）：每次5发
     * - 超大容量（>100发）：动态缩放，控制循环次数在20-30次
     *
     * @param capacity 弹匣容量
     * @return 每次换弹循环填充的发数
     */
    public static function calculateRoundsPerCycle(capacity:Number):Number {
        // 使用早期返回优化分支预测（AS2性能优化）
        if (capacity <= 10) return 1;   // 小容量：逐发换弹
        if (capacity <= 30) return 2;   // 中容量：每次2发
        if (capacity <= 60) return 3;   // 每次3发
        if (capacity <= 100) return 5;  // 每次5发
        // 超大容量：控制循环次数在20-30次
        return Math.max(5, Math.ceil(capacity / 25));
    }

    /**
     * 初始化换弹负担系统
     * 在换弹动画起始帧调用，设置帧率控制
     *
     * 换弹惩罚机制：
     * - 不同武器类型有不同的换弹惩罚值（武器XML的data节点中的reloadPenalty字段）
     * - 正值增加负担（变慢），负值减少负担（加速）
     * - 配件可通过flat操作修改此值（如加长弹匣在NOAH结构下提供-10加速）
     * - 快速换弹（枪械师被动）按比例衰减总负担（包含惩罚值），而非完全抵消
     * - 计算公式：实际换弹帧数 ≈ 基础帧数 × (总负担值 / 100)
     *
     * 各武器类型默认惩罚值参考（额外帧数 × 3.33 ≈ 惩罚值）：
     * - 冲锋枪/突击步枪/霰弹枪/近战/压制近战/特殊: 0
     * - 战斗步枪: 17 (额外5帧)
     * - 狙击步枪: 33 (额外10帧)
     * - 反器材武器/机枪: 50 (额外15帧)
     * - 压制机枪: 67 (额外20帧)
     * - 发射器: 0 (预留，待后续调整)
     *
     * @param target 时间轴MovieClip（换弹动画容器）
     * @param startFrame 换弹起始帧号
     * @param gateFrame 逐发换弹门禁检查帧号
     * @param loopBackFrame 逐发换弹循环回跳帧号
     * @param endFrame 换弹结束帧号（用于帧率控制）
     * @param audioFrames 必经的音频触发帧数组
     */
    public static function initReloadBurden(
        target:MovieClip,
        startFrame:Number,
        gateFrame:Number,
        loopBackFrame:Number,
        endFrame:Number,
        audioFrames:Array
    ):Void {
        // 缓存parent引用和核心属性（AS2性能优化）
        var parent:Object = target._parent;
        var attackMode:String = parent.攻击模式;
        var weaponValue:Object = parent[attackMode].value;
        var capacity:Number = parent[attackMode + "弹匣容量"];
        var shot:Number = weaponValue.shot;

        // 检查快速换弹被动技能（枪械师）
        target.快速换弹 = (parent._name == _root.控制目标
                         && parent.被动技能.枪械师
                         && parent.被动技能.枪械师.启用);

        // 记录帧位置
        target.reloadStartFrame = startFrame;
        target.reloadGateFrame = gateFrame;
        target.reloadLoopBackFrame = loopBackFrame;
        target.reloadEndFrame = endFrame;

        // 检测tube换弹类型，决定换弹路径
        var weaponAttr:Object = parent[attackMode + "属性"];
        var isTubeReload:Boolean = (weaponAttr.reloadType == "tube");

        // 路径分流：完全打空→整弹匣换弹，部分打空→逐发换弹
        // shot == capacity 表示完全打空（已发射数等于弹匣容量）
        var usePerRoundReload:Boolean = isTubeReload && (shot < capacity);
        target.perRoundReload = usePerRoundReload;

        // 处理音频帧：排序+去重，避免跳过必经帧
        // 对于逐发换弹类型，门禁帧也是必经帧
        var processedAudioFrames:Array = [];
        if (audioFrames != null) {
            for (var i:Number = 0; i < audioFrames.length; i++) {
                var af:Number = Number(audioFrames[i]);
                if (!isNaN(af)) processedAudioFrames.push(af);
            }
        }
        // 逐发换弹：添加门禁帧为必经帧
        if (usePerRoundReload && gateFrame != undefined) {
            processedAudioFrames.push(gateFrame);
        }
        if (processedAudioFrames.length > 0) {
            processedAudioFrames.sort(function(a, b) { return a - b; });
            var uniqueFrames:Array = [];
            for (var j:Number = 0; j < processedAudioFrames.length; j++) {
                if (j == 0 || processedAudioFrames[j] != processedAudioFrames[j - 1]) {
                    uniqueFrames.push(processedAudioFrames[j]);
                }
            }
            target.reloadAudioFrames = uniqueFrames;
        } else {
            target.reloadAudioFrames = null;
        }

        // 初始化负担值 = 时间缩放比例（100正常，200慢放2倍，<100加速）
        var burden:Number = 100;

        // 根据武器类型获取换弹惩罚值（从武器数据的reloadPenalty字段读取）
        var reloadPenalty:Number = 0;
        if (attackMode == "长枪" && parent.长枪属性) {
            var penaltyValue:Number = Number(parent.长枪属性.reloadPenalty);
            if (!isNaN(penaltyValue)) {
                reloadPenalty = penaltyValue;
            }
        }
        // 将惩罚值加入基础负担
        burden += reloadPenalty;

        // 快速换弹：按节省帧数比例缩减总负担（包含惩罚值，按比例衰减而非完全抵消）
        // 节省帧数根据枪械师等级动态计算：1级=8帧，10级=11帧，线性插值
        if (target.快速换弹 && endFrame != undefined) {
            var totalFrames:Number = endFrame - startFrame;
            var gunslingerSkill:Object = parent.被动技能.枪械师;
            var gunslingerLevel:Number = gunslingerSkill.等级 || 1;
            var savedFrames:Number = 8 + (gunslingerLevel - 1) * 3 / 9;  // 1级=8, 10级=11
            if (totalFrames > savedFrames) {
                burden = Math.round(burden * (totalFrames - savedFrames) / totalFrames);
            }
        }

        // 逐发换弹负担值缩放
        // 设计目标：弹容2时40%，弹容8时100%，弹容50时175%，大容量收敛到200%
        // 小容量武器（≤10发）：逐发换弹，灵活快速
        // 中容量武器（11-100发）：每次换2-5发，平衡手感和效率
        // 大容量武器（>100发）：每次换N发，控制循环次数在20-30次，ratio收敛到2.0
        if (usePerRoundReload && endFrame != undefined && gateFrame != undefined && loopBackFrame != undefined) {
            var loopFrames:Number = gateFrame - loopBackFrame;  // 单次循环帧数 t
            var fullFrames:Number = endFrame - startFrame;      // 整弹匣换弹帧数 T

            // 计算时间比例系数 ratio（收敛设计）
            var ratio:Number;
            if (capacity <= 2) {
                ratio = 0.4;
            } else if (capacity <= 8) {
                ratio = 0.4 + (capacity - 2) * 0.1;  // 2-8发：线性增长
            } else if (capacity <= 50) {
                ratio = 1.0 + (capacity - 8) * 0.75 / 42;  // 8-50发：平滑过渡到1.75
            } else {
                ratio = 2.0 - 12.5 / capacity;  // 50发以上：渐近收敛到2.0
            }

            // 计算每次换弹发数和总循环次数
            var roundsPerCycle:Number = ReloadManager.calculateRoundsPerCycle(capacity);
            var totalCycles:Number = Math.ceil(capacity / roundsPerCycle);

            // 计算逐发换弹负担值（基于实际循环次数）
            // 目标：(loopFrames × totalCycles) / (100/新负担) = fullFrames × ratio
            // 即：逐发真实时间 = 整弹匣真实时间 × ratio
            // 新负担 = 100 × fullFrames × ratio / (loopFrames × totalCycles)
            var perRoundBurden:Number = Math.round(100 * fullFrames * ratio / (loopFrames * totalCycles));

            // 应用基础负担的惩罚/加速比例
            perRoundBurden = Math.round(perRoundBurden * burden / 100);

            burden = perRoundBurden;
        }

        target.reloadBurden = burden;

        // 帧率控制模式（仅当传入endFrame时启用）
        if (endFrame != undefined) {
            target.reloadFrameControlRequest = true;
            target.reloadFrameProgress = 0;
        }
    }

    // ============================================================
    // 双枪换弹负担系统 (Dual-Gun Reload Burden System)
    // ============================================================

    /**
     * 从时间轴状态推断当前双枪换弹上下文，并缓存到 target 上。
     *
     * 设计目的：
     * - 双枪模式下 _parent.攻击模式 通常为 "双枪"，不能直接用于索引弹匣容量/武器value等字段
     * - 由动画标签（主手换弹匣/副手换弹匣）推断当前换弹手并映射到实际武器类型：
     *   主手 → "手枪"
     *   副手 → "手枪2"
     *
     * 缓存字段：
     * - target.dualReloadHandPrefix         : "主手"/"副手"
     * - target.dualReloadWeaponType         : "手枪"/"手枪2"
     * - target.dualReloadMagNameProp        : "主手使用弹匣名称"/"副手使用弹匣名称"
     * - target.dualReloadRemainingMagProp   : "主手剩余弹匣数"/"副手剩余弹匣数"
     *
     * @param target 时间轴MovieClip（this引用）
     */
    private static function _resolveDualGunReloadContext(target:MovieClip):Void {
        // 依赖动画标签进行手位推断（更稳定，不依赖帧号）
        var label:String = target._currentlabel;
        var handPrefix:String = (label == "副手换弹匣") ? "副手" : "主手";
        var weaponType:String = (handPrefix == "副手") ? "手枪2" : "手枪";

        target.dualReloadHandPrefix = handPrefix;
        target.dualReloadWeaponType = weaponType;
        target.dualReloadMagNameProp = handPrefix + "使用弹匣名称";
        target.dualReloadRemainingMagProp = handPrefix + "剩余弹匣数";
    }

    /**
     * 双枪：初始化换弹负担系统（主手/副手分别计算负担）
     *
     * 用法：由双枪时间轴在对应换弹区间的起始帧调用：
     * - 主手换弹匣区间调用一次（映射 "手枪"）
     * - 副手换弹匣区间调用一次（映射 "手枪2"）
     *
     * 与单武器 initReloadBurden 的差异：
     * - 不使用 _parent.攻击模式（避免 "双枪" 索引错误）
     * - 使用当前动画标签推断手位，并按手位读取武器属性/弹匣容量/弹匣名称
     * - reloadPenalty 从当前手对应的武器属性读取（允许配件/NOAH结构动态写入）
     *
     * @param target 时间轴MovieClip（换弹动画容器）
     * @param startFrame 换弹起始帧号
     * @param gateFrame 逐发换弹门禁检查帧号
     * @param loopBackFrame 逐发换弹循环回跳帧号
     * @param endFrame 换弹结束帧号（用于帧率控制）
     * @param audioFrames 必经的音频触发帧数组
     */
    public static function initDualGunReloadBurden(
        target:MovieClip,
        startFrame:Number,
        gateFrame:Number,
        loopBackFrame:Number,
        endFrame:Number,
        audioFrames:Array
    ):Void {
        // 推断并缓存当前换弹手位上下文
        ReloadManager._resolveDualGunReloadContext(target);

        // 缓存parent引用和核心属性（AS2性能优化）
        var parent:Object = target._parent;
        var weaponType:String = target.dualReloadWeaponType;
        var weaponIndex:String = weaponType; // parentRef[weaponType] 结构与单武器一致
        var weaponValue:Object = parent[weaponIndex].value;
        var capacity:Number = parent[weaponType + "弹匣容量"];
        var shot:Number = weaponValue.shot;

        // 记录帧位置（与单武器共用同一套帧率控制字段）
        target.reloadStartFrame = startFrame;
        target.reloadGateFrame = gateFrame;
        target.reloadLoopBackFrame = loopBackFrame;
        target.reloadEndFrame = endFrame;

        // 检查快速换弹被动技能（枪械师）：仅通过负担值加速，不再依赖动画跳帧
        var passiveSkills:Object = parent.被动技能;
        target.快速换弹 = (parent._name == _root.控制目标
                         && passiveSkills
                         && passiveSkills.枪械师
                         && passiveSkills.枪械师.启用);

        // 检测tube换弹类型，决定换弹路径
        var weaponAttr:Object = parent[weaponType + "属性"];
        var isTubeReload:Boolean = (weaponAttr && weaponAttr.reloadType == "tube");

        // 路径分流：完全打空→整弹匣换弹，部分打空→逐发换弹
        var usePerRoundReload:Boolean = isTubeReload && (shot < capacity);
        target.perRoundReload = usePerRoundReload;

        // 处理音频帧：排序+去重，避免跳过必经帧
        // 对于逐发换弹类型，门禁帧也是必经帧
        var processedAudioFrames:Array = [];
        if (audioFrames != null) {
            for (var i:Number = 0; i < audioFrames.length; i++) {
                var af:Number = Number(audioFrames[i]);
                if (!isNaN(af)) processedAudioFrames.push(af);
            }
        }
        if (usePerRoundReload && gateFrame != undefined) {
            processedAudioFrames.push(gateFrame);
        }
        if (processedAudioFrames.length > 0) {
            processedAudioFrames.sort(function(a, b) { return a - b; });
            var uniqueFrames:Array = [];
            for (var j:Number = 0; j < processedAudioFrames.length; j++) {
                if (j == 0 || processedAudioFrames[j] != processedAudioFrames[j - 1]) {
                    uniqueFrames.push(processedAudioFrames[j]);
                }
            }
            target.reloadAudioFrames = uniqueFrames;
        } else {
            target.reloadAudioFrames = null;
        }

        // 初始化负担值 = 时间缩放比例（100正常，200慢放2倍，<100加速）
        var burden:Number = 100;

        // reloadPenalty：优先从当前手的武器属性读取（支持配件 flat 写入）
        var reloadPenalty:Number = 0;
        if (weaponAttr && weaponAttr.reloadPenalty != undefined) {
            var penaltyValue:Number = Number(weaponAttr.reloadPenalty);
            if (!isNaN(penaltyValue)) {
                reloadPenalty = penaltyValue;
            }
        }
        burden += reloadPenalty;

        // 快速换弹：按节省帧数比例缩减总负担（包含惩罚值，按比例衰减而非完全抵消）
        // 节省帧数根据枪械师等级动态计算：1级=5帧，10级=9帧，线性插值
        if (target.快速换弹 && endFrame != undefined) {
            var totalFrames:Number = endFrame - startFrame;
            var gunslingerSkill:Object = passiveSkills.枪械师;
            var gunslingerLevel:Number = gunslingerSkill.等级 || 1;
            var savedFrames:Number = 5 + (gunslingerLevel - 1) * 4 / 9;  // 1级=5, 10级=9
            if (totalFrames > savedFrames) {
                burden = Math.round(burden * (totalFrames - savedFrames) / totalFrames);
            }
        }

        // 逐发换弹负担值缩放（双枪同样支持 tube 类型）
        if (usePerRoundReload && endFrame != undefined && gateFrame != undefined && loopBackFrame != undefined) {
            var loopFrames:Number = gateFrame - loopBackFrame;  // 单次循环帧数 t
            var fullFrames:Number = endFrame - startFrame;      // 整段换弹帧数 T

            // 计算时间比例系数 ratio（收敛设计）
            var ratio:Number;
            if (capacity <= 2) {
                ratio = 0.4;
            } else if (capacity <= 8) {
                ratio = 0.4 + (capacity - 2) * 0.1;
            } else if (capacity <= 50) {
                ratio = 1.0 + (capacity - 8) * 0.75 / 42;
            } else {
                ratio = 2.0 - 12.5 / capacity;
            }

            var roundsPerCycle:Number = ReloadManager.calculateRoundsPerCycle(capacity);
            var totalCycles:Number = Math.ceil(capacity / roundsPerCycle);
            var perRoundBurden:Number = Math.round(100 * fullFrames * ratio / (loopFrames * totalCycles));
            perRoundBurden = Math.round(perRoundBurden * burden / 100);
            burden = perRoundBurden;
        }

        target.reloadBurden = burden;

        // 帧率控制模式（仅当传入endFrame时启用）
        if (endFrame != undefined) {
            target.reloadFrameControlRequest = true;
            target.reloadFrameProgress = 0;
        }
    }

    /**
     * 双枪：换弹门禁检查点（tube 逐发换弹）
     *
     * 说明：双枪版本复用单武器门禁逻辑，但将索引改为当前手对应的武器：
     * - 主手 → parent["手枪"]
     * - 副手 → parent["手枪2"]
     *
     * @param target 时间轴MovieClip（this引用）
     */
    public static function handleDualGunReloadGate(target:MovieClip):Void {
        // 非tube类型或未启用逐发换弹模式：直接返回，让动画继续播放到换弹匣()
        if (!target.perRoundReload) {
            return;
        }

        // 推断并缓存当前换弹手位上下文（确保字段存在）
        ReloadManager._resolveDualGunReloadContext(target);

        var parent:Object = target._parent;
        var weaponType:String = target.dualReloadWeaponType;
        var weaponValue:Object = parent[weaponType].value;
        var capacity:Number = parent[weaponType + "弹匣容量"];
        var shot:Number = weaponValue.shot;

        // 1. 弹匣已满，清空换弹值，跳到结束帧
        if (shot <= 0) {
            weaponValue.reloadCount = 0;
            target.reloadFrameControlActive = false;
            target.gotoAndPlay(target.reloadEndFrame);
            return;
        }

        // 2. 检查换弹值，没有则消耗弹匣获取
        if (weaponValue.reloadCount == undefined || weaponValue.reloadCount <= 0) {
            if (_root.控制目标 == parent._name) {
                // 预缓存弹匣名称（AS2性能优化）
                var magNameProp:String = target.dualReloadMagNameProp;
                var magName:String = target[magNameProp];

                if (ItemUtil.singleContain(magName, 1) != null) {
                    ItemUtil.singleSubmit(magName, 1);
                    weaponValue.reloadCount = capacity;

                    // 更新两手剩余弹匣数（考虑同弹匣共享库存）
                    var handPrefix:String = target.dualReloadHandPrefix;
                    var remainingProp:String = target.dualReloadRemainingMagProp;
                    target[remainingProp] = ItemUtil.getTotal(magName);

                    var otherHandPrefix:String = (handPrefix == "主手") ? "副手" : "主手";
                    var otherMagName:String = target[otherHandPrefix + "使用弹匣名称"];
                    if (otherMagName != undefined) {
                        target[otherHandPrefix + "剩余弹匣数"] = ItemUtil.getTotal(otherMagName);
                    }
                } else {
                    // 没有弹匣了，结束换弹（保留当前填充进度）
                    _root.发布消息("弹匣耗尽！");
                    target.reloadFrameControlActive = false;
                    target.gotoAndPlay(target.reloadEndFrame);
                    return;
                }
            } else {
                // AI直接获得换弹值
                weaponValue.reloadCount = capacity;
            }
        }

        // 3. 填充N发（大容量武器每次换多发）
        var roundsPerCycle:Number = ReloadManager.calculateRoundsPerCycle(capacity);
        roundsPerCycle = Math.min(roundsPerCycle, shot);
        roundsPerCycle = Math.min(roundsPerCycle, weaponValue.reloadCount);

        weaponValue.reloadCount -= roundsPerCycle;
        weaponValue.shot -= roundsPerCycle;

        // 更新UI显示
        ReloadManager.updateAmmoDisplay(target, parent, _root);
        _root.soundEffectManager.playSound("9mmclip2.wav");

        // 4. 检查是否继续
        if (weaponValue.shot <= 0) {
            target.reloadFrameControlActive = false;
            target.gotoAndPlay(target.reloadEndFrame);
        } else {
            target.gotoAndPlay(target.reloadLoopBackFrame);
        }
    }

    /**
     * 换弹门禁检查点
     * 在门禁检查帧调用，扣除负担并决定放行或回跳
     *
     * 路径分流说明：
     * - 完全打空（shot == capacity）：走整弹匣换弹路径，门禁不做任何事，动画继续到换弹匣()
     * - 未完全打空（shot < capacity）且为tube类型：走逐发换弹路径
     *
     * 逐发换弹（tube类型）说明：
     * - 适用于霰弹枪、狙击步枪、机枪等管状弹仓武器或大容量弹链武器
     * - 每次门禁执行：检查换弹值 → 消耗弹匣获取换弹值 → 填充N发 → 回跳或结束
     * - 填充发数N根据弹容动态计算：小容量逐发（1发），大容量批量（2-40发）
     * - 中途打断时换弹值保留，下次换弹继续消耗
     * - 换弹值 = capacity（弹匣容量），每次填充 shot -= N
     *
     * @param target 时间轴MovieClip（this引用）
     */
    public static function handleReloadGate(target:MovieClip):Void {
        // 缓存parent引用和核心属性
        var parent:Object = target._parent;
        var attackMode:String = parent.攻击模式;

        // 非tube类型或未启用逐发换弹模式：直接返回，让动画继续播放到换弹匣()
        if (!target.perRoundReload) {
            return;
        }

        // ============ 逐发换弹（tube类型，shot < capacity） ============
        var capacity:Number = parent[attackMode + "弹匣容量"];
        var weaponValue:Object = parent[attackMode].value;
        var shot:Number = weaponValue.shot;

        // 1. 弹匣已满，清空换弹值，跳到结束帧
        if (shot <= 0) {
            weaponValue.reloadCount = 0;
            // 关闭帧率控制，防止继续推进到换弹匣()帧
            target.reloadFrameControlActive = false;
            target.gotoAndPlay(target.reloadEndFrame);
            return;
        }

        // 2. 检查换弹值，没有则消耗弹匣获取
        if (weaponValue.reloadCount == undefined || weaponValue.reloadCount <= 0) {
            // 玩家需要检查并消耗弹匣
            if (_root.控制目标 == parent._name) {
                // 预缓存弹匣名称（AS2性能优化：减少3次属性访问）
                var magName:String = target.使用弹匣名称;
                if (ItemUtil.singleContain(magName, 1) != null) {
                    ItemUtil.singleSubmit(magName, 1);
                    weaponValue.reloadCount = capacity;
                    target.剩余弹匣数 = ItemUtil.getTotal(magName);
                } else {
                    // 没有弹匣了，结束换弹（保留当前填充进度）
                    _root.发布消息("弹匣耗尽！");
                    target.reloadFrameControlActive = false;
                    target.gotoAndPlay(target.reloadEndFrame);
                    return;
                }
            } else {
                // AI直接获得换弹值
                weaponValue.reloadCount = capacity;
            }
        }

        // 3. 填充N发（大容量武器每次换多发）
        var roundsPerCycle:Number = ReloadManager.calculateRoundsPerCycle(capacity);
        // 不能超过剩余需要填充的发数
        roundsPerCycle = Math.min(roundsPerCycle, shot);
        // 也不能超过当前换弹值剩余
        roundsPerCycle = Math.min(roundsPerCycle, weaponValue.reloadCount);

        weaponValue.reloadCount -= roundsPerCycle;
        weaponValue.shot -= roundsPerCycle;

        // 更新UI显示
        ReloadManager.updateAmmoDisplay(target, parent, _root);
        _root.soundEffectManager.playSound("9mmclip2.wav");

        // 4. 检查是否继续
        if (weaponValue.shot <= 0) {
            // 弹匣满了，关闭帧率控制，跳到结束帧
            target.reloadFrameControlActive = false;
            target.gotoAndPlay(target.reloadEndFrame);
        } else {
            // 回跳继续循环
            target.gotoAndPlay(target.reloadLoopBackFrame);
        }
    }

    /**
     * 换弹帧率控制
     * 由挂载在换弹区间内的子MC的onClipEvent(enterFrame)每帧调用
     * 通过stop()+nextFrame()手动推进时间轴，负担值控制推进速率，音乐帧保证必经
     *
     * 性能优化：缓存频繁访问的属性，减少AS2属性查找开销
     *
     * @param target 要控制的时间轴MovieClip
     */
    public static function controlReloadFrameRate(target:MovieClip):Void {
        // 首次请求：接管时间轴控制
        if (target.reloadFrameControlRequest) {
            target.reloadFrameControlRequest = false;
            target.reloadFrameControlActive = true;
            target.stop();
            return;
        }
        if (!target.reloadFrameControlActive) return;

        // 缓存负担和进度，减少属性访问（AS2性能优化）
        var burden:Number = target.reloadBurden;
        var progress:Number = target.reloadFrameProgress;

        // 保护：避免除零/负值
        if (burden == undefined || burden <= 0) {
            burden = 100;
            target.reloadBurden = burden;
        }

        // 累积帧进度：每真实帧推进 100/负担 个动画帧
        progress += 100 / burden;
        var framesToAdvance:Number = Math.floor(progress);
        if (framesToAdvance < 1) {
            target.reloadFrameProgress = progress;
            return;
        }
        progress -= framesToAdvance;

        // 缓存当前帧和结束帧
        var currentFrame:Number = target._currentframe;
        var endFrame:Number = target.reloadEndFrame;

        // 本帧计划到达的目标帧（先按结束帧夹住，避免越界导致跳过帧脚本/音乐帧）
        var targetFrame:Number = currentFrame + framesToAdvance;
        if (endFrame != undefined && targetFrame > endFrame) {
            targetFrame = endFrame;
        }

        // 音乐帧约束：多帧推进时，遇到音乐帧必须停住，剩余进度存回下帧继续
        if (targetFrame - currentFrame > 1) {
            var audioFrames:Array = target.reloadAudioFrames;
            if (audioFrames != null) {
                var stopFrame:Number = undefined;
                for (var i:Number = 0; i < audioFrames.length; i++) {
                    var af:Number = audioFrames[i];
                    if (af > currentFrame && af < targetFrame && (stopFrame == undefined || af < stopFrame)) {
                        stopFrame = af;
                    }
                }
                if (stopFrame != undefined) {
                    progress += (targetFrame - stopFrame);
                    targetFrame = stopFrame;
                }
            }
        }

        var advanceFrames:Number = targetFrame - currentFrame;
        if (advanceFrames < 1) {
            target.reloadFrameProgress = progress;
            return;
        }

        // 到达结束帧：逐帧推进到结束帧前一帧，再gotoAndPlay(结束帧)交还时间轴控制
        // 这样既不跳过中间帧脚本，也避免在已到达结束帧时重复执行结束帧脚本。
        if (endFrame != undefined && targetFrame == endFrame) {
            for (var f:Number = 1; f < advanceFrames; f++) {
                target.nextFrame();
            }
            target.reloadFrameControlActive = false;
            target.gotoAndPlay(endFrame);
            return;
        }

        // 逐帧推进（确保每帧脚本正常执行）
        for (var f:Number = 0; f < advanceFrames; f++) {
            var beforeFrame:Number = target._currentframe;
            target.nextFrame();
            // 如果帧脚本执行了跳转（如门禁回跳/结束），中断循环
            if (target._currentframe != beforeFrame + 1) {
                progress = 0;
                break;
            }
        }

        // 写回缓存的进度
        target.reloadFrameProgress = progress;
    }
}
