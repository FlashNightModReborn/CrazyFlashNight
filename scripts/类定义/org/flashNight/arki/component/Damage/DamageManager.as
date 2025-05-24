import org.flashNight.arki.component.Damage.*;

/**
 * DamageManager 类是伤害管理的核心类。
 * - 负责管理和执行伤害处理器。
 * - 只包含必要的处理器，由 DamageManagerFactory 注入。
 * - 专注于执行伤害处理逻辑，避免冗余存储。
 */
class org.flashNight.arki.component.Damage.DamageManager {

    // 适用的伤害处理器列表，由工厂注入
    private var _handles:Array;

    // 多段 / 霰弹计算的重叠比例
    public var overlapRatio:Number;

    // 目标的躲闪状态
    public var dodgeState:String;

    /**
     * 构造函数。
     * 初始化 DamageManager 实例。
     *
     * @param handles 适用的伤害处理器列表（已由工厂筛选）
     */
    public function DamageManager(handles:Array) {
        this._handles = handles;          // 直接接受工厂筛选好的处理器
        var len:Number = handles.length; // 记录处理器数量
        if(len > 32) {
            throw new Error("不支持数量超过32的处理器");
        }
        else
        {
            this.execute = this["execute" + len];
        }

        
        this.overlapRatio = 1;            // 默认重叠比例为 1
        this.dodgeState = "";             // 默认躲闪状态为空
    }

    /**
     * 重置函数。
     * 初始化 DamageManager 实例。
     *
     * @param handles 适用的伤害处理器列表（已由工厂筛选）
     */
    public function reset():Void
    {
        this.overlapRatio = 1;            // 默认重叠比例为 1
        this.dodgeState = "";             // 默认躲闪状态为空
    }

    /**
     * 更新函数。
     * 更新当前状态，为后续的execute做准备。
     *
     * @param handles 适用的伤害处理器列表（已由工厂筛选）
     */
    public function update(overlapRatio:Number, dodgeState:String):Void
    {
        this.overlapRatio = overlapRatio;
        this.dodgeState = dodgeState;
    }

    /**
     * 执行所有伤害处理器。
     * 遍历处理器列表，依次调用每个处理器的 handleBulletDamage 方法。
     * 该方法仅用于示例，创建伤害管理器后，会被动态替换成特化策略方法以消除循环开销
     *
     * @param bullet  子弹对象
     * @param shooter 发射者对象
     * @param target  被击中目标对象
     * @param result  伤害结果对象
     */
    public function execute(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        var index:Number = 0;
        var len = _handles.length;
        // 遍历所有处理器
        do {
            _handles[index].handleBulletDamage(bullet, shooter, target, this, result);
        } while (++index < len);  // 自增操作移入条件判断
    }


    public function execute1(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute2(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute3(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute4(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute5(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute6(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute7(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute8(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute9(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute10(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute11(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute12(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute13(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute14(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute15(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute16(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute17(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute18(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute19(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[18].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute20(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[18].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[19].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute21(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[18].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[19].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[20].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute22(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[18].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[19].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[20].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[21].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute23(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[18].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[19].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[20].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[21].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[22].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute24(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[18].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[19].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[20].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[21].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[22].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[23].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute25(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[18].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[19].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[20].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[21].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[22].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[23].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[24].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute26(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[18].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[19].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[20].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[21].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[22].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[23].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[24].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[25].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute27(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[18].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[19].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[20].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[21].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[22].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[23].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[24].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[25].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[26].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute28(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[18].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[19].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[20].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[21].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[22].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[23].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[24].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[25].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[26].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[27].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute29(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[18].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[19].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[20].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[21].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[22].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[23].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[24].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[25].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[26].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[27].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[28].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute30(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[18].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[19].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[20].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[21].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[22].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[23].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[24].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[25].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[26].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[27].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[28].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[29].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute31(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[18].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[19].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[20].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[21].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[22].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[23].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[24].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[25].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[26].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[27].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[28].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[29].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[30].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    public function execute32(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        _handles[0].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[1].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[2].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[3].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[4].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[5].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[6].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[7].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[8].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[9].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[10].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[11].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[12].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[13].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[14].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[15].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[16].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[17].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[18].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[19].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[20].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[21].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[22].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[23].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[24].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[25].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[26].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[27].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[28].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[29].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[30].handleBulletDamage(bullet, shooter, target, this, result);
        _handles[31].handleBulletDamage(bullet, shooter, target, this, result);
    }
    

    /**
     * 输出 DamageManager 的状态信息。
     * 返回包含所有处理器名称的字符串，用于调试和日志记录。
     *
     * @return String DamageManager 的状态信息
     */
    public function toString():String {
        var str:String = "DamageManager:\n";

        // 遍历所有处理器，将其名称添加到字符串中
        for (var i:Number = 0; i < _handles.length; ++i) {
            str += "  Handle: " + _handles[i].toString() + "\n";
        }

        return str;
    }
}