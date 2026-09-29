/**
 * 穿刺共有执行器的类型配置。预算仍由 AttributeLoader/BulletInitializer 和
 * BulletQueueProcessor 负责；这里不把预算改译为目标数，不加入命中去重。
 *
 * XFL 仍是 area 形状与 Flash 帧时钟的载体。原生只接管显示，不推进此时钟。
 * 普通/无壳停在飞行第1帧；只有次级的首次真实命中启动爆炸时间轴。
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.PierceBulletProfile {
    public var id:String;
    public var firstHitLabel:String;
    public var disableRepeatedHitHook:Boolean;
    public var removeOnMapHit:Boolean;

    private static var truePierce:PierceBulletProfile;
    private static var secondaryPierce:PierceBulletProfile;

    public function PierceBulletProfile(id:String, firstHitLabel:String,
                                        disableRepeatedHitHook:Boolean, removeOnMapHit:Boolean) {
        this.id = id;
        this.firstHitLabel = firstHitLabel;
        this.disableRepeatedHitHook = disableRepeatedHitHook;
        this.removeOnMapHit = removeOnMapHit;
    }

    public static function resolve(baseAsset:String):PierceBulletProfile {
        // 延迟创建，避免类注册期跨类调用。只接受本轮已对照的直接单弹资产。
        // 联弹单元嵌套的次级剪辑没有组命中回调，不能套用该单弹配置。
        if (baseAsset == "穿刺子弹" || baseAsset == "无壳穿刺子弹") {
            if (!truePierce) truePierce = new PierceBulletProfile("pierce", null, false, false);
            return truePierce;
        }
        if (baseAsset == "次级穿刺子弹") {
            if (!secondaryPierce) secondaryPierce = new PierceBulletProfile("secondary", "爆炸", true, true);
            return secondaryPierce;
        }
        return null;
    }
}
