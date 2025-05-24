import org.flashNight.arki.bullet.BulletComponent.Loader.*;

class org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer {
    private static var maxHor:Number = 33;
    private static var maxVer:Number = 15;
    
    // 新增：保存 AttributeLoader 返回的子弹属性数据
    private static var attributeMap:Object = {};
    
    // 构造函数（私有或空实现，避免被实例化）
    private function BulletInitializer() {
        // 不需要实例化
    }
    
    /**
     * 注册 InfoLoader 回调，获取子弹属性数据
     * 建议在游戏初始化阶段调用一次
     */
    public static function initializeAttributes():Void {
        InfoLoader.getInstance().onLoad(function(data:Object):Void {
            attributeMap = data.attributeData;
            trace("子弹属性数据已加载到 BulletInitializer.attributeMap");
        });
    }
    
    /**
     * 设置默认值
     * @param Obj {Object} 子弹对象
     * @param shooter {Object} 发射者对象
     */
    public static function setDefaults(Obj:Object, shooter:Object):Void {
        // 原有逻辑
        Obj.固伤 = Obj.固伤 | 0;
        Obj.命中率 = (isNaN(Obj.命中率)) ? shooter.命中率 : Obj.命中率;
        Obj.最小霰弹值 = (isNaN(Obj.最小霰弹值)) ? 1 : Obj.最小霰弹值;
        Obj.远距离不消失 = Obj.手雷检测 || Obj.爆炸检测;
        Obj.shooter = shooter;
        Obj.zAttackRangeSq = Obj.Z轴攻击范围 * Obj.Z轴攻击范围;
    }
    
    /**
     * 初始化子弹属性
     * @param Obj {Object} 子弹对象
     */
    public static function initializeBulletProperties(Obj:Object):Void {
        // 原有初始化逻辑
        Obj.发射者名 = Obj.发射者;
        Obj.子弹敌我属性值 = Obj.子弹敌我属性;
        Obj._x = Obj.shootX;
        Obj._y = Obj.shootY;
        Obj.Z轴坐标 = Obj.shootZ;
        Obj.子弹区域area = Obj.区域定位area;
        Obj.hitCount = 0;
        
        // 新增：挂载 AttributeLoader 解析的属性到子弹对象
        if(attributeMap[Obj.子弹种类]) initializeBulletAttributes(Obj);
    }
    
    /**
     */
    public static function initializeBulletAttributes(Obj:Object):Void {
        // 获取当前子弹类型对应的属性对象
        var attr:Object = attributeMap[Obj.子弹种类];
        // 遍历属性并拷贝到 Obj 上
        for(var key:String in attr) {
            Obj[key] = attr[key];
        }
    }
    
    /**
     * 继承发射者属性
     * @param Obj {Object} 子弹对象
     * @param shooter {Object} 发射者对象
     */
    public static function inheritShooterAttributes(Obj:Object, shooter:Object):Void {
        var objDmgType:Object = Obj.伤害类型;
        var shooterDmgType:Object = shooter.伤害类型;
        Obj.伤害类型 = (!objDmgType && shooterDmgType) ? shooterDmgType : objDmgType;
        var objMagicDmg:Object = Obj.魔法伤害属性;
        var shooterMagicDmg:Object = shooter.魔法伤害属性;
        Obj.魔法伤害属性 = (!objMagicDmg && shooterMagicDmg) ? shooterMagicDmg : objMagicDmg;
        if (Obj.吸血 || shooter.吸血) {
            Obj.吸血 = Math.max(Obj.吸血 > 0 ? Obj.吸血 : 0, shooter.吸血 > 0 ? shooter.吸血 : 0);
        }
        if (Obj.血量上限击溃 || shooter.击溃) {
            Obj.击溃 = Math.max(Obj.血量上限击溃 > 0 ? Obj.血量上限击溃 : 0, shooter.击溃 > 0 ? shooter.击溃 : 0);
        }
    }
    
    /**
     * 计算击退速度
     * @param Obj {Object} 子弹对象
     */
    public static function calculateKnockback(Obj:Object):Void {
        if (!(Obj.水平击退速度 >= 0)) {
            Obj.水平击退速度 = 10;
        } else {
            Obj.水平击退速度 = Math.min(Obj.水平击退速度, BulletInitializer.maxHor);
        }
        Obj.垂直击退速度 = Obj.垂直击退速度 | 0;
        Obj.垂直击退速度 = Math.min(Obj.垂直击退速度, BulletInitializer.maxVer);
    }
    
    /**
     * 初始化子弹毒属性
     * @param Obj {Object} 子弹对象
     * @param bullet {Object} 子弹对象
     * @param shooter {Object} 发射者对象
     */
    public static function initializeNanoToxicfunction(Obj:Object, bullet:Object, shooter:Object):Void {
        if (Obj.毒 || shooter.淬毒 || shooter.毒) {
            var shooterToxic:Number = shooter.淬毒 | 0;
            Obj.毒 = Math.max(Obj.毒 | 0, shooter.毒 | 0);
            if (shooterToxic && shooterToxic > Obj.毒) {
                bullet.nanoToxic = shooterToxic;
                bullet.nanoToxicDecay = 1;
                if (!bullet.近战检测 && shooter.淬毒 > 10) {
                    if(bullet.子弹种类.indexOf("纵向") != -1 && bullet.霰弹值 > 1){
                        shooter.淬毒 -= bullet.霰弹值;
                    }else{
                        shooter.淬毒 -= 1;
                    }
                }
            } else {
                bullet.nanoToxic = Obj.毒;
            }
        }
    }
}
