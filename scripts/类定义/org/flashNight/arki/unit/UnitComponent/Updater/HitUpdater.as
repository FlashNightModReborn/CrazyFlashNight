import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.sara.util.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Collider.*;

class org.flashNight.arki.unit.UnitComponent.Updater.HitUpdater {

    public static function getUpdater():Function
    {
        return function(shooter:MovieClip, 
                        bullet:MovieClip, 
                        collisionResult:CollisionResult,
                        damageResult:DamageResult):Void {
            if(_root.调试模式)
            {
                _root.绘制线框(this.area);
            }
            ImpactHandler.refreshImpactForce(this);
            var bar = this.新版人物文字信息 ? this.新版人物文字信息.头顶血槽 : this.人物文字信息.头顶血槽;
            bar._visible = true;
            bar.gotoAndPlay(2);
            this.攻击目标 = shooter._name;

            if (this._name === _root.控制目标) {
                _root.玩家信息界面.刷新hp显示();
            }

            if(!bullet.近战检测 && !bullet.爆炸检测 && this.hp <= 0)
            {
                this.状态改变("血腥死");
            }

            
            var hitDirection:String = (this._x < shooter._x) ? "左" : "右" ;
            var overlapCenter:Vector = collisionResult.overlapCenter;

            if(bullet.水平击退反向){
                hitDirection = hitDirection === "左" ? "右" : "左";
            }
            this.方向改变(hitDirection === "左" ? "右" : "左");

            if (_root.血腥开关)
            {
                var bulletEffectFragment:String = "";
                switch (this.击中效果)
                {
                    case "飙血":
                        bulletEffectFragment = "子弹碎片-飞血";
                        break;
                    case "异形飙血":
                        bulletEffectFragment = "子弹碎片-异形飞血";
                        break;
                    default:
                }

                if(bulletEffectFragment != "")
                {
                    
                    var effectInstance = _root.效果(bulletEffectFragment, overlapCenter.x, overlapCenter.y, shooter._xscale);
                    effectInstance.出血来源 = this._name;
                }
            }
            var hp:Number = this.hp;
            var isRigid:Boolean = this.刚体 || this.man.刚体标签;
            if (!this.浮空 && !this.倒地)
            {
                _root.冲击力结算(this.损伤值,bullet.击倒率,this);
                this.barColorState = "常态";

                if (hp <= 0)
                {
                    this.状态改变(_root.血腥开关 ? "血腥死" : "击倒");
                }
                else if (damageResult.dodgeStatus == "躲闪")
                {
                    this.被击移动(hitDirection,bullet.水平击退速度,3);
                }
                else
                {
                    if (this.remainingImpactForce > this.韧性上限)
                    {
                        if (!isRigid)
                        {
                            this.状态改变("击倒");
                            this.barColorState = "击倒";
                        }
                        this.remainingImpactForce = 0;
                        this.被击移动(hitDirection,bullet.水平击退速度,0.5);
                    }
                    else if (this.remainingImpactForce > this.韧性上限 / ImpactHandler.IMPACT_STAGGER_COEFFICIENT / this.躲闪率)
                    {
                        if (!isRigid)
                        {
                            this.状态改变("被击");
                            this.barColorState = "被击";
                        }

                        this.被击移动(hitDirection,bullet.水平击退速度,2);
                    }
                    else
                    {
                        this.被击移动(hitDirection,bullet.水平击退速度,3);
                    }
                }
            }
            else
            {
                this.remainingImpactForce = 0;
                if (!isRigid)
                {
                    this.状态改变("击倒");
                    this.barColorState = "击倒";
                    if (!(bullet.垂直击退速度 > 0))
                    {
                        var y速度 = 5;
                        this.man.垂直速度 = -y速度;
                    }
                }
                this.被击移动(hitDirection,bullet.水平击退速度,0.5);
            }


            if(hp <= 0) {
                if(!bullet.近战检测 && !bullet.爆炸检测) {
                    this.状态改变("血腥死");
                }
            }

            switch (this.barColorState)
            {
                case "常态": _root.重置色彩(bar);
                    break;
                default: _root.暗化色彩(bar);
            }

            _root.效果(this.击中效果, overlapCenter.x, overlapCenter.y, shooter._xscale);
            var shouldGeneratePostHitEffect:Boolean = true;
            if(this.击中效果 == bullet.击中后子弹的效果) {
                shouldGeneratePostHitEffect = false;
            }


            if (bullet.垂直击退速度 > 0)
            {
                this.man.play();
                clearInterval(this.pauseInterval);
                this.硬直中 = false;
                clearInterval(this.pauseInterval2);

                _root.fly(this,bullet.垂直击退速度,0);
            }
        };
    }
}
