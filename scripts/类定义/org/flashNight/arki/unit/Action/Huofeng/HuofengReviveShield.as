import org.flashNight.arki.component.Shield.Shield;

/** 火凤恢复行动后获得的临时盾，沿用单位盾容器结算，暂停时冻结本层。 */
class org.flashNight.arki.unit.Action.Huofeng.HuofengReviveShield extends Shield {
    public function HuofengReviveShield(capacity:Number, frames:Number) {
        super(capacity, capacity, -capacity / frames, 0, "涅槃护盾", "decaying");
        setTemporary(true);
        setDuration(frames);
    }

    public function update(deltaTime:Number):Boolean {
        if (_root.暂停) return false;
        return super.update(deltaTime);
    }

    public static function grant(unit:Object, capacity:Number, frames:Number):Number {
        if (!unit.shield || !(capacity > 0) || !isFinite(capacity) || !(frames > 0) || !isFinite(frames)) return -1;
        var layer:HuofengReviveShield = new HuofengReviveShield(capacity, frames);
        return unit.shield.addShield(layer) ? layer.getId() : -1;
    }
}
