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
            
            var 被击方向:String = (this._x < shooter._x) ? "左" : "右" ;
            var overlapCenter:Vector = collisionResult.overlapCenter;

            if(bullet.水平击退反向){
                被击方向 = 被击方向 === "左" ? "右" : "左";
            }
            this.方向改变(被击方向 === "左" ? "右" : "左");

            if (_root.血腥开关)
            {
                var 子弹效果碎片 = "";
                switch (this.击中效果)
                {
                    case "飙血":
                        子弹效果碎片 = "子弹碎片-飞血";
                        break;
                    case "异形飙血":
                        子弹效果碎片 = "子弹碎片-异形飞血";
                        break;
                    default:
                }

                if(子弹效果碎片 != "")
                {
                    
                    var 效果对象 = _root.效果(子弹效果碎片, overlapCenter.x, overlapCenter.y, shooter._xscale);
                    效果对象.出血来源 = this._name;
                }
            }

            var 刚体检测 = this.刚体 || this.man.刚体标签;
            if (!this.浮空 && !this.倒地)
            {
                _root.冲击力结算(this.损伤值,bullet.击倒率,this);
                this.血条变色状态 = "常态";

                if (!isNaN(this.hp) && this.hp <= 0)
                {
                    this.状态改变(_root.血腥开关 ? "血腥死" : "击倒");
                }
                else if (damageResult.dodgeStatus == "躲闪")
                {
                    this.被击移动(被击方向,bullet.水平击退速度,3);
                }
                else
                {
                    if (this.remainingImpactForce > this.韧性上限)
                    {
                        if (!刚体检测)
                        {
                            this.状态改变("击倒");
                            this.血条变色状态 = "击倒";
                        }
                        this.remainingImpactForce = 0;
                        this.被击移动(被击方向,bullet.水平击退速度,0.5);
                    }
                    else if (this.remainingImpactForce > this.韧性上限 / _root.踉跄判定 / this.躲闪率)
                    {
                        if (!刚体检测)
                        {
                            this.状态改变("被击");
                            this.血条变色状态 = "被击";
                        }

                        this.被击移动(被击方向,bullet.水平击退速度,2);
                    }
                    else
                    {
                        this.被击移动(被击方向,bullet.水平击退速度,3);
                    }
                }
            }
            else
            {
                this.remainingImpactForce = 0;
                if (!刚体检测)
                {
                    this.状态改变("击倒");
                    this.血条变色状态 = "击倒";
                    if (!(bullet.垂直击退速度 > 0))
                    {
                        var y速度 = 5;
                        this.man.垂直速度 = -y速度;
                    }
                }
                this.被击移动(被击方向,bullet.水平击退速度,0.5);
            }

            if(!bullet.近战检测 && !bullet.爆炸检测 && this.hp <= 0)
            {
                this.状态改变("血腥死");
            }

            switch (this.血条变色状态)
            {
                case "常态": _root.重置色彩(bar);
                    break;
                default: _root.暗化色彩(bar);
            }

            _root.效果(this.击中效果, overlapCenter.x, overlapCenter.y, shooter._xscale);
            var 是否生成击中后效果:Boolean = true;
            if(this.击中效果 == bullet.击中后子弹的效果) {
                是否生成击中后效果 = false;
            }

            if (bullet.近战检测 && !bullet.不硬直)
            {
                shooter.硬直(shooter.man,_root.钝感硬直时间);
            }
            else if(!bullet.穿刺检测)
            {
                bullet.gotoAndPlay("消失");
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
