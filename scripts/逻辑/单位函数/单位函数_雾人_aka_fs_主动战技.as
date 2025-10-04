import org.flashNight.arki.scene.*;
import org.flashNight.sara.util.*;
import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

_root.主动战技函数 = {空手: {}, 兵器: {}, 长枪: {}};



//空手
_root.主动战技函数.空手.旋风腿 = {初始化: null,
        释放许可判定: function(自机) {
            return 自机.攻击模式 === "空手" && !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "旋风腿";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("旋风腿");
        }}

_root.主动战技函数.空手.飞身踢 = {初始化: null,
        释放许可判定: function(自机) {
            return 自机.攻击模式 === "空手" && !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "飞身踢";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("飞身踢");
        }}

_root.主动战技函数.空手.毁天灭地 = {初始化: null,
        释放许可判定: function(自机) {
            return 自机.攻击模式 === "空手";
        },
        释放: function(自机) {
            自机.技能名 = "毁天灭地";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("毁天灭地");
        }}

_root.主动战技函数.空手.震地 = {初始化: null,
        释放许可判定: function(自机) {
            return 自机.攻击模式 === "空手" && !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "震地";
            自机.状态改变("技能");
            自机.man.gotoAndPlay("震地");
        }}


//长枪
_root.主动战技函数.长枪.发射榴弹 = {初始化: function(自机) {
    自机.当前弹夹副武器已发射数 = 0;
    //再次读取物品属性取得传参
    var 长枪物品信息 = 自机.长枪数据;
    var skill = 长枪物品信息.skill;
    自机.副武器子弹威力 = skill.power && skill.power > 0 ? Number(skill.power) : 2500;
    自机.副武器可发射数 = skill.bulletsize > 0 ? Number(skill.bulletsize) : 1;
    自机.副武器弹药类型 = skill.clipname ? skill.clipname : "榴弹弹药";
    自机.副武器子弹种类 = skill.bullet ? skill.bullet : "榴弹";
    自机.副武器子弹声音 = skill.sound ? skill.sound : "re_GL_under.wav";
    自机.副武器子弹霰弹值 = skill.split && skill.split > 0 ? Number(skill.split) : 1;
    自机.副武器子弹散射度 = skill.diffusion && skill.diffusion > 0 ? Number(skill.diffusion) : 0;
    自机.副武器子弹速度 = skill.velocity && skill.velocity > 0 ? Number(skill.velocity) : 25;
    自机.副武器子弹Z轴攻击范围 = skill.range && skill.range > 0 ? Number(skill.range) : 50;
    自机.副武器子弹击倒率 = skill.range && skill.range > 0 ? Number(skill.range) : 0.01;
},
        释放许可判定: function(自机) {
            if (自机.当前弹夹副武器已发射数 >= 自机.副武器可发射数)
                return false;
            if (自机.浮空 || 自机.倒地)
                return false;
            if (!(自机.状态 === "长枪行走" || 自机.状态 === "长枪站立") || 自机.换弹中)
                return false;
            //检测物品栏弹药
            if (自机.当前弹夹副武器已发射数 > 0) {
                return true;
            } else if (org.flashNight.arki.item.ItemUtil.singleSubmit(自机.副武器弹药类型, 1)) {
                // _root.发布消息(自机.副武器弹药类型 + "耗尽！");
                return true;
            }
            return false;
        },
        释放: function(自机) {
            自机.当前弹夹副武器已发射数++;
            var myPoint = {x: 自机.man.枪.枪.装扮.枪口位置._x, y: 自机.man.枪.枪.装扮.枪口位置._y + 20};
            自机.man.枪.枪.装扮.localToGlobal(myPoint);
            _root.gameworld.globalToLocal(myPoint);
            var 子弹属性 = new Object();
            子弹属性.声音 = 自机.副武器子弹声音;
            子弹属性.霰弹值 = 自机.副武器子弹霰弹值;
            子弹属性.子弹散射度 = 自机.副武器子弹散射度;
            子弹属性.发射效果 = "";
            子弹属性.子弹种类 = 自机.副武器子弹种类;
            子弹属性.子弹威力 = 自机.副武器子弹威力;
            子弹属性.子弹速度 = 自机.副武器子弹速度;
            子弹属性.击中地图效果 = "";
            子弹属性.Z轴攻击范围 = 自机.副武器子弹Z轴攻击范围;
            子弹属性.击倒率 = 自机.副武器子弹击倒率;
            子弹属性.击中后子弹的效果 = "";
            子弹属性.发射者 = 自机._name;
            子弹属性.shootX = myPoint.x;
            子弹属性.shootY = myPoint.y;
            子弹属性.shootZ = 自机.Z轴坐标;
            _root.子弹区域shoot传递(子弹属性);
        }};

_root.主动战技函数.长枪.气锤地雷 = {初始化: null,
        释放许可判定: function(自机) {
            if (自机.倒地)
                return false;
            if (!(自机.状态 === "长枪行走" || 自机.状态 === "长枪站立") || 自机.换弹中)
                return false;
            return org.flashNight.arki.item.ItemUtil.singleSubmit("能量电池", 1);
        },
        释放: function(自机) {
            var 子弹属性 = new Object();

            子弹属性.声音 = "";
            子弹属性.霰弹值 = 1;
            子弹属性.子弹散射度 = 0;
            子弹属性.发射效果 = "";
            子弹属性.子弹种类 = "气锤地雷";
            var prop:Object = 自机.man.子弹属性;
            子弹属性.子弹威力 = prop.子弹威力 * 10 * prop.霰弹值;
            子弹属性.子弹速度 = 0;
            子弹属性.击中地图效果 = "";
            子弹属性.Z轴攻击范围 = 150;
            子弹属性.击倒率 = 1;
            子弹属性.击中后子弹的效果 = "";
            子弹属性.发射者 = 自机._name;
            子弹属性.shootX = 自机._x;
            子弹属性.shootY = 自机.Z轴坐标;
            子弹属性.shootZ = 自机.Z轴坐标;

            _root.子弹区域shoot传递(子弹属性);

            自机.拾取();
        }};


_root.主动战技函数.长枪.混凝土切割机超载打击 = {初始化: function(自机) {
    自机.混凝土切割机超载打击许可 = false;

    var skill:Object = 自机.长枪数据.skill;
    var duration:Number = skill.duration || 5;

    var upgradeLevel:Number = 自机.长枪.value.level;
    
    duration += upgradeLevel;
    var overRideCountMax:Number = duration * 30;
    自机.混凝土切割机超载打击持续时间 = overRideCountMax;
    自机.混凝土切割机超载打击剩余时间 = 0;
},

        释放许可判定: function(自机) {
            if (自机.倒地)
                return false;
            if (!(自机.状态 === "长枪行走" || 自机.状态 === "长枪站立") || 自机.换弹中)
                return false;
            return org.flashNight.arki.item.ItemUtil.singleSubmit("强化石", 1);
        },

        释放: function(自机)
        {
            自机.混凝土切割机超载打击许可 = true;
            自机.混凝土切割机超载打击剩余时间 = 自机.混凝土切割机超载打击持续时间;
        }};

_root.主动战技函数.长枪.MACSIII超载打击 = {初始化: function(自机) {
    自机.MACSIII超载打击许可 = false;

    var skill:Object = 自机.长枪数据.skill;
    var duration:Number = skill.duration || 5;

    var upgradeLevel:Number = 自机.长枪.value.level;
    duration += upgradeLevel;
    var overRideCountMax:Number = duration * 30;
    自机.MACSIII超载打击持续时间 = overRideCountMax;
    自机.MACSIII超载打击剩余时间 = 0;
},

        释放许可判定: function(自机) {
            if (自机.倒地)
                return false;
            if (!(自机.状态 === "长枪行走" || 自机.状态 === "长枪站立") || 自机.换弹中)
                return false;
            return org.flashNight.arki.item.ItemUtil.singleSubmit("强化石", 1);
        },

        释放: function(自机)
        {
            var prop:Object = 自机.man.子弹属性;

            自机.MACSIII超载打击许可 = true;
            自机.MACSIII超载打击剩余时间 = 自机.MACSIII超载打击持续时间;
            var gun:MovieClip = 自机.长枪_引用;
            var area:MovieClip = gun.枪口位置;
            var myPoint = new Vector(area._x, area._y);
            gun.localToGlobal(myPoint);
            _root.gameworld.globalToLocal(myPoint);

            var 子弹属性 = new Object();

            子弹属性.声音 = "";
            子弹属性.霰弹值 = 5;
            子弹属性.子弹散射度 = 0;
            子弹属性.发射效果 = "";
            子弹属性.子弹种类 = "近战子弹";

            子弹属性.子弹威力 = prop.子弹威力 * 10;
            子弹属性.子弹速度 = 0;
            子弹属性.击中地图效果 = "";
            子弹属性.Z轴攻击范围 = 150;
            子弹属性.击倒率 = 1;
            子弹属性.击中后子弹的效果 = "火花";
            子弹属性.发射者 = 自机._name;
            子弹属性.shootX = myPoint.x;
            子弹属性.shootY = myPoint.y;
            子弹属性.shootZ = 自机.Z轴坐标;
            子弹属性.区域定位area = area;
            子弹属性.伤害类型 = "魔法";
            子弹属性.魔法伤害属性 = "热";
            子弹属性.斩杀 = 13;
            子弹属性.吸血 = 20;

            _root.子弹区域shoot传递(子弹属性);

            自机.攻击模式切换("长枪");
        }};


_root.主动战技函数.长枪.投影召唤 = {

    /** 初始化：此技能无被动帧更新，可留空 **/初始化: function(自机) {
    },

        /** 是否允许释放 —— 这里留简单 true，后续可加冷却 / 条件判定 **/
        释放许可判定: function(自机) {
            return true;
        },

        /** 真正释放逻辑 **/
        释放: function(自机)
        {
            var name:String = 自机._name + "投影召唤";
            /* ---------- A. 生成投影召唤器本体 ---------- */
            var info:Object = {};
            info.Identifier = "投影召唤器"; // 关联库导出名

            var param:Object = {};
            param._x = 自机._x; // 水平位置与自机齐平
            param._y = 自机.Z轴坐标; // Z→Y 投影平面
            param.projector = 自机;
            info.Parameters = param;
            if (_root.gameworld[name])
                _root.gameworld[name].removeMovieClip();
            var target:MovieClip = SceneManager.getInstance().addInstance(info, name);
        }};

_root.主动战技函数.长枪.铁枪之锋 = {初始化: function(自机) {
            自机.铁枪之锋许可 = false;
            var upgradeLevel:Number = 自机.长枪.value.level;
            自机.铁枪之锋倍率 = 1 + upgradeLevel * 0.1;
        },

        释放许可判定: function(自机) {
            if (自机.倒地)
                return false;
            if (!(自机.状态 === "长枪行走" || 自机.状态 === "长枪站立") || 自机.换弹中)
                return false;
            return org.flashNight.arki.item.ItemUtil.singleSubmit("强化石", 1);
        },

        释放: function(自机) {
            // 1. 清理所有射击相关的状态和任务
            自机.强制奔跑 = false;
            自机.射击最大后摇中 = false;

            var instance:EnhancedCooldownWheel = EnhancedCooldownWheel.I();

            // 清理可能干扰的帧计时器任务
            instance.removeTask(自机.keepshooting);
            instance.removeTask(自机.keepshooting2);
            instance.removeTask(自机.taskLabel.结束射击后摇);

            // 2. 重置射击状态标志
            自机.主手射击中 = false;
            自机.副手射击中 = false;
            自机.长枪射击中 = false;

            // 3. 确保射击许可标签为true（关键修复）
            var man = 自机.man;
            var lable:MovieClip = man.射击许可标签;
            man.射击许可标签 = true;
            自机.动作A = true;

            // 4. 状态切换和攻击执行
            自机.状态改变("长枪站立");
            自机.铁枪之锋许可 = true;
            自机.上行 = !!自机.isRocketMode;

            // 5. 执行攻击
            自机.攻击();


            // 6. 清理临时状态
            自机.上行 = false;
            自机.铁枪之锋许可 = false;

            man.射击许可标签 = lable;
        }};

_root.主动战技函数.长枪.气锤光炮 = {初始化: function(自机) {
    var skill = 长枪物品信息.skill;
    自机.气锤光炮弹药类型 = skill.bullet ? skill.bullet : "铁枪磁轨弹";
    自机.气锤光炮音效 = skill.sound ? skill.sound : "re_GL_under.wav";


    自机.dispatcher.subscribe("长枪射击", function() {
        if (!自机.气锤光炮开启)
            return;
        var prop:Object = 自机.man.子弹属性;

        prop.子弹种类 = 自机.气锤光炮弹药类型;
        自机.气锤光炮原伤害 = prop.子弹威力;
        var magazineCapName:String = "长枪弹匣容量";
        var rate:Number = (自机[magazineCapName] - 自机.长枪.value.shot) * prop.霰弹值 / 2;
        // _root.发布消息(自机.气锤光炮原伤害, rate)
        prop.子弹威力 *= rate;
        prop.霰弹值 = 1;
        prop.站立子弹散射度 = 0;
        prop.发射效果 = "铁枪能量弹枪火";
        prop.sound = 自机.气锤光炮音效;

        自机.气锤光炮开启 = false;
    });
},
        释放许可判定: function(自机) {
            if (自机["主手射击中"])
                return false;
            if (!自机.chargeComplete)
                return false;
            if (!(自机.状态 === "长枪行走" || 自机.状态 === "长枪站立") || 自机.换弹中)
                return false;
            var magazineCapName:String = "长枪弹匣容量";

            if (自机.长枪.value.shot + 1 > 自机[magazineCapName])
                return false;
            if (自机.浮空 || 自机.倒地)
                return false;
            return true;
        },
        释放: function(自机) {

            自机.强制奔跑 = false;

            var currentA:Boolean = 自机.动作A;
            自机.气锤光炮开启 = true;
            自机.动作A = true;
            自机.攻击();

            自机.气锤光炮开启 = false;

            var data:Object = 自机.长枪属性;
            var prop:Object = 自机.man.子弹属性;

            prop.子弹种类 = data.bullet;
            prop.霰弹值 = data.split;
            prop.sound = data.sound;
            prop.发射效果 = data.muzzle;
            prop.站立子弹散射度 = data.diffusion;
            prop.子弹威力 = 自机.气锤光炮原伤害;

            // _root.发布消息("back", prop.子弹威力)

            // _root.发布消息(prop.子弹种类, prop.霰弹值, prop.子弹威力)

            // 自机.动作A = currentA;

            var magazineCapName:String = "长枪弹匣容量";
            自机.长枪.value.shot = 自机[magazineCapName];
            if (_root.控制目标 == 自机._name) {
                _root.玩家信息界面.玩家必要信息界面["子弹数"] = 0;
            }
        }}

_root.主动战技函数.长枪.突击者之眼 = {初始化: function(自机) {
    var skill = 长枪物品信息.skill;
    自机.突击者之眼弹药类型 = skill.bullet ? skill.bullet : "横向联弹-无壳穿刺子弹";
    自机.突击者之眼数 = skill.split && skill.split > 0 ? Number(skill.split) : 3;
    自机.突击者之眼音效 = skill.sound ? skill.sound : "re_GL_under.wav";

    var upgradeLevel:Number = 自机.长枪.value.level;

    var k:Number = 22 / 1029; // ≈ 0.02138
    var level:Number = upgradeLevel; // 1–13

    var factor:Number = 1 / (1 + k * Math.pow(level, 3));
    自机.主动战技.长枪.冷却时间 *= factor;
    // _root.发布消息("突击者之眼冷却时间: " + 自机.主动战技.长枪.冷却时间 + "秒");

    自机.dispatcher.subscribe("长枪射击", function() {
        if (!自机.突击者之眼开启)
            return;
        var prop:Object = 自机.man.子弹属性;
        prop.子弹种类 = 自机.突击者之眼弹药类型;
        prop.霰弹值 = 自机.突击者之眼数;
        prop.sound = 自机.突击者之眼音效;
        自机.长枪.value.shot += 自机.突击者之眼数 - 1;
        自机.突击者之眼开启 = false;
    });
},
        释放许可判定: function(自机) {
            if (自机["主手射击中"])
                return false;
            var magazineCapName:String = "长枪弹匣容量";

            if (自机.长枪.value.shot + 自机.突击者之眼数 > 自机[magazineCapName])
                return false;
            if (自机.浮空 || 自机.倒地)
                return false;
            return true;
        },
        释放: function(自机) {

            自机.强制奔跑 = false;

            var currentA:Boolean = 自机.动作A;
            自机.动作A = true;
            自机.突击者之眼开启 = true;
            自机.攻击();

            var data:Object = 自机.长枪属性;
            var prop:Object = 自机.man.子弹属性;

            prop.子弹种类 = data.bullet;
            prop.霰弹值 = data.split;
            prop.sound = data.sound;

            // 自机.动作A = currentA;
        }}

_root.主动战技函数.长枪.突击者之怒 = {初始化: function(自机) {
    var skill = 长枪物品信息.skill;
    自机.突击者之怒弹药类型 = skill.bullet ? skill.bullet : "铁枪磁轨弹";
    自机.突击者之怒倍率 = skill.power && skill.power > 0 ? Number(skill.power) : 9;
    自机.突击者之怒音效 = skill.sound ? skill.sound : "re_GL_under.wav";

    var upgradeLevel:Number = 自机.长枪.value.level;
    自机.突击者之怒倍率 += upgradeLevel;

    自机.dispatcher.subscribe("长枪射击", function() {
        var prop:Object = 自机.man.子弹属性;

        if (自机.突击者之怒开启) {
            prop.子弹种类 = 自机.突击者之怒弹药类型;
            自机.突击者之怒原伤害 = prop.子弹威力;
            prop.子弹威力 *= 自机.突击者之怒倍率;
            prop.霰弹值 = 1;
            prop.发射效果 = "铁枪能量弹枪火";
            prop.sound = 自机.突击者之怒音效;
        } else {
            prop.霰弹值 = 自机.chargeComplete ? 6 : 3;
            
        }

        // _root.发布消息(自机.突击者之怒原伤害, prop.子弹威力, prop.霰弹值)
    });
},
        释放许可判定: function(自机) {
            if (自机["主手射击中"])
                return false;
            if (!自机.chargeComplete)
                return false;
            var magazineCapName:String = "长枪弹匣容量";

            if (自机.长枪.value.shot + 1 > 自机[magazineCapName])
                return false;
            if (自机.浮空 || 自机.倒地)
                return false;
            return true;
        },
        释放: function(自机) {

            自机.强制奔跑 = false;

            var currentA:Boolean = 自机.动作A;
            自机.突击者之怒开启 = true;
            自机.动作A = true;
            自机.攻击();

            自机.突击者之怒开启 = false;

            var data:Object = 自机.长枪属性;
            var prop:Object = 自机.man.子弹属性;

            prop.子弹种类 = data.bullet;
            prop.霰弹值 = data.split;
            prop.sound = data.sound;
            prop.发射效果 = data.muzzle;
            prop.子弹威力 = 自机.突击者之怒原伤害;

            // _root.发布消息(prop.子弹种类, prop.霰弹值, prop.子弹威力)

            // 自机.动作A = currentA;
        }}

_root.主动战技函数.长枪.旋转抡枪 = {初始化: null,
        释放许可判定: function(自机) {
            return 自机.攻击模式 === "长枪" && (!自机.倒地 && 自机.状态 != "击倒" && 自机.状态 != "技能");
        },
        释放: function(自机) {
            自机.技能名 = "抡枪";
            自机.状态改变("技能");
            自机.man.gotoAndPlay("抡枪");
        }}



//兵器
_root.主动战技函数.兵器.滑步 = {初始化: null,
        释放许可判定: function(自机) {
            return true; //应该是无条件吧（）
        },
        释放: function(自机) {
            自机.技能名 = "战技小跳";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("战技小跳");
        }}

_root.主动战技函数.兵器.弧光斩 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "弧光斩";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("弧光斩");
        }}

_root.主动战技函数.兵器.EternalMaximumDrive = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "Eternal Maximum Drive";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("Eternal Maximum Drive");
        }}

_root.主动战技函数.兵器.凶斩 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "凶斩";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("凶斩");
        }}

_root.主动战技函数.兵器.狼跳 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "狼跳";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("狼跳");
        }}

_root.主动战技函数.兵器.回旋斩击 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "回旋斩击";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("回旋斩击");
        }}

_root.主动战技函数.兵器.回旋裂地 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "回旋裂地";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("回旋裂地");
        }}

_root.主动战技函数.兵器.破坏殆尽 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "破坏殆尽";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("破坏殆尽");
        }}

_root.主动战技函数.兵器.雷鸣感召 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "雷鸣感召";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("雷鸣感召");
        }}

_root.主动战技函数.兵器.突刺 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "突刺";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("突刺");
        }}

_root.主动战技函数.兵器.重力操作 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "重力操作";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("重力操作");
        }}

_root.主动战技函数.兵器.瞬步斩 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "瞬步斩";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("瞬步斩");
        }}

_root.主动战技函数.兵器.漆黑凶斩 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "漆黑凶斩";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("漆黑凶斩");
        }}

_root.主动战技函数.兵器.黑刀斩术 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "黑刀斩术";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("黑刀斩术");
        }}

_root.主动战技函数.兵器.猩红居合 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "猩红凶斩";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("猩红凶斩");
        }}

_root.主动战技函数.兵器.居合次元斩 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "居合次元斩";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("居合次元斩");
        }}

_root.主动战技函数.兵器.天蓝斩术 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "蓝瞬步斩";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("蓝瞬步斩");
        }}

_root.主动战技函数.兵器.苍紫爆炸 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.浮空 && !自机.倒地;
        },
        释放: function(自机) {
            var 当前战技 = 自机.主动战技.兵器;
            var 子弹属性 = new Object();
            子弹属性.声音 = "";
            子弹属性.霰弹值 = 1;
            子弹属性.子弹散射度 = 0;
            子弹属性.发射效果 = "";
            子弹属性.子弹种类 = "苍紫爆炸";
            子弹属性.子弹威力 = 当前战技.消耗mp * 15;
            子弹属性.子弹速度 = 0;
            子弹属性.击中地图效果 = "";
            子弹属性.Z轴攻击范围 = 120;
            子弹属性.击倒率 = 1;
            子弹属性.击中后子弹的效果 = "";
            子弹属性.水平击退速度 = 20;
            子弹属性.发射者 = 自机._name;
            var 偏移距离 = 20;
            var 偏移x = (Math.random() - 0.5) * 2 * 偏移距离;
            var 偏移y = (Math.random() - 0.5) * 2 * 偏移距离;
            子弹属性.shootX = 自机._x + 偏移x;
            子弹属性.shootY = 自机.Z轴坐标 + 偏移y;
            子弹属性.shootZ = 子弹属性.shootY;
            _root.子弹区域shoot传递(子弹属性);
        }}

_root.主动战技函数.兵器.黑铁剑意 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.浮空 && !自机.倒地;
        },
        释放: function(自机) {
            if (自机.状态 === "兵器攻击" || 自机.状态 === "兵器冲击") {
                var 当前战技 = 自机.主动战技.兵器;
                var 子弹属性 = new Object();
                子弹属性.声音 = "";
                子弹属性.霰弹值 = 1;
                子弹属性.子弹散射度 = 0;
                子弹属性.发射效果 = "";
                子弹属性.子弹种类 = "剑光特效";
                子弹属性.子弹威力 = 当前战技.消耗mp * 12;
                子弹属性.子弹速度 = 0;
                子弹属性.击中地图效果 = "";
                子弹属性.Z轴攻击范围 = 100;
                子弹属性.击倒率 = 1;
                子弹属性.击中后子弹的效果 = "";
                子弹属性.水平击退速度 = 18;
                子弹属性.发射者 = 自机._name;
                var 偏移距离 = 50;
                var 偏移x = (Math.random() - 0.5) * 2 * 偏移距离;
                // var 偏移y = (Math.random() - 0.5) * 2 * 偏移距离;
                子弹属性.shootX = 自机._x + 偏移x;
                子弹属性.shootY = 自机.Z轴坐标;
                子弹属性.shootZ = 子弹属性.shootY;
                _root.子弹区域shoot传递(子弹属性);
            } else {
                自机.技能名 = "追踪五连";
                自机.状态改变("战技");
                自机.man.gotoAndPlay("追踪五连");
            }
        }}


//星座武器特辑
_root.主动战技函数.兵器.摩羯之力 = {初始化: null,
        释放许可判定: function(自机) {
            return _root.控制目标 === 自机._name;
        },
        释放: function(自机) {
            _root.发布消息("摩羯之力发动，敌人被引力拉扯至周围！");
            var 当前战技 = 自机.主动战技.兵器;
            var 子弹属性 = new Object();
            子弹属性.声音 = "";
            子弹属性.霰弹值 = 1;
            子弹属性.子弹散射度 = 0;
            子弹属性.发射效果 = "";
            子弹属性.子弹种类 = "摩羯之力";
            子弹属性.子弹威力 = 当前战技.消耗mp * 10;
            子弹属性.子弹速度 = 0;
            子弹属性.击中地图效果 = "";
            子弹属性.Z轴攻击范围 = 72;
            子弹属性.击倒率 = 1;
            子弹属性.击中后子弹的效果 = "";
            子弹属性.水平击退速度 = 18;
            子弹属性.发射者 = 自机._name;
            子弹属性.shootX = 自机._x;
            子弹属性.shootY = 自机.Z轴坐标;
            子弹属性.shootZ = 子弹属性.shootY;
            _root.子弹区域shoot传递(子弹属性);
        }}

_root.主动战技函数.兵器.金牛之力 = {初始化: null,
        释放许可判定: function(自机) {
            return _root.控制目标 === 自机._name;
        },
        释放: function(自机) {
            _root.发布消息("金牛之力发动，金币与K点爆率提升至50%，持续30秒！");
            _root.打怪掉钱机率 = 2;
            var timer = setTimeout(function() {
                _root.打怪掉钱机率 = 6;
                clearTimeout(timer);
            }, 30000);
            _root.发布调试消息("_root.打怪掉钱机率: " + _root.打怪掉钱机率);
            var 当前战技 = 自机.主动战技.兵器;
            var 子弹属性 = new Object();
            子弹属性.声音 = "";
            子弹属性.霰弹值 = 1;
            子弹属性.子弹散射度 = 0;
            子弹属性.发射效果 = "";
            子弹属性.子弹种类 = "金牛之力";
            子弹属性.子弹威力 = 当前战技.消耗mp * 12;
            子弹属性.子弹速度 = 0;
            子弹属性.击中地图效果 = "";
            子弹属性.Z轴攻击范围 = 72;
            子弹属性.击倒率 = 1;
            子弹属性.击中后子弹的效果 = "";
            子弹属性.水平击退速度 = 18;
            子弹属性.发射者 = 自机._name;
            子弹属性.shootX = 自机._x;
            子弹属性.shootY = 自机.Z轴坐标;
            子弹属性.shootZ = 子弹属性.shootY;
            _root.子弹区域shoot传递(子弹属性);
        }}

_root.主动战技函数.兵器.狮子之力 = {初始化: function(自机) {
    if (isNaN(自机.狮王增幅次数))
        自机.狮王增幅次数 = 0;
},
        释放许可判定: function(自机) {
            return _root.控制目标 === 自机._name;
        },
        释放: function(自机) {
            var 我方角色数量 = TargetCacheManager.getAllyCount(自机, 150);
            if (我方角色数量 >= 10)
                我方角色数量 = 10;
            if (自机.狮王增幅次数 < 1)
            {
                /*
                   狮王攻击加成 = 我方角色数量 * 自机.空手攻击力 * 0.10;
                   狮王防御加成 = 我方角色数量 * 自机.防御力 * 0.10;
                   if(狮王攻击加成 >= 1000)
                   {
                   狮王攻击加成 = 1000;
                   }
                   if(狮王防御加成 >= 2000)
                   {
                   狮王防御加成 = 2000;
                   }
                   自机.空手攻击力 += 狮王攻击加成;
                   自机.防御力 += 狮王防御加成;

                   //换算为加算写法，但不建议在乘算倍率中使用
                   狮王攻击加成 = Math.min(1000, 自机.buff.基础值.空手攻击力 * 我方角色数量 * 0.10);
                   狮王防御加成 = Math.min(2000, 自机.buff.基础值.防御力 * 我方角色数量 * 0.10);
                   自机.buff.赋值("空手攻击力", "加算", 狮王攻击加成, "增益");
                   自机.buff.赋值("防御力", "加算", 狮王防御加成, "增益");
                 */
                var 狮王攻击加成倍率 = 1 + 我方角色数量 * 0.10;
                var 攻击buff换算上限值 = 1000;
                var 攻击buff换算下限值 = -10;
                var 狮王防御加成倍率 = 1 + 我方角色数量 * 0.10;
                var 防御buff换算上限值 = 2000;
                var 防御buff换算下限值 = -10;

                自机.buff.赋值("空手攻击力", "倍率", 狮王攻击加成倍率, "增益", 攻击buff换算上限值, 攻击buff换算下限值);
                自机.buff.赋值("防御力", "倍率", 狮王防御加成倍率, "增益", 防御buff换算上限值, 防御buff换算下限值);

                自机.狮王增幅次数 = 1;
                _root.发布消息("狮王之力发动！目前力量提升至" + 自机.空手攻击力 + "点！");
                _root.发布消息("狮王之力发动！目前防御提升至" + 自机.防御力 + "点！");
            }
            var 当前战技 = 自机.主动战技.兵器;
            var 子弹属性 = new Object();
            子弹属性.声音 = "";
            子弹属性.霰弹值 = 1;
            子弹属性.子弹散射度 = 0;
            子弹属性.发射效果 = "";
            子弹属性.子弹种类 = "狮子之力";
            子弹属性.子弹威力 = 当前战技.消耗mp * (10 + 我方角色数量);
            子弹属性.子弹速度 = 0;
            子弹属性.击中地图效果 = "";
            子弹属性.Z轴攻击范围 = 72;
            子弹属性.击倒率 = 1;
            子弹属性.击中后子弹的效果 = "";
            子弹属性.水平击退速度 = 18;
            子弹属性.发射者 = 自机._name;
            子弹属性.shootX = 自机._x;
            子弹属性.shootY = 自机.Z轴坐标;
            子弹属性.shootZ = 子弹属性.shootY;
            _root.子弹区域shoot传递(子弹属性);
        }}
_root.主动战技函数.兵器.暴走 = {初始化: null,
        释放许可判定: function(自机) {
            return true;
        },
        释放: function(自机) {
            自机.技能名 = "暴走";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("暴走");
        }}
_root.主动战技函数.兵器.狂瀑扎 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.浮空 && !自机.倒地;
        },
        释放: function(自机) {
            if (_root.控制目标 == 自机._name)
            {
                var 装备栏 = _root.物品栏.装备栏;
                头部装备 = 装备栏.getNameString("头部装备");
                上装装备 = 装备栏.getNameString("上装装备");
                手部装备 = 装备栏.getNameString("手部装备");
                下装装备 = 装备栏.getNameString("下装装备");
                脚部装备 = 装备栏.getNameString("脚部装备");
            } else {
                头部装备 = 自机.头部装备;
                上装装备 = 自机.上装装备;
                手部装备 = 自机.手部装备;
                下装装备 = 自机.下装装备;
                脚部装备 = 自机.脚部装备;
            }
            if (!自机.转换的冷兵器加成 && 自机.空手攻击力 > 100 && 头部装备 == "黑犀头甲" && 上装装备 == "黑犀胸甲" && 手部装备 == "黑犀手甲" && 下装装备 == "黑犀腿甲" && 脚部装备 == "黑犀鞋") {
                自机.转换的冷兵器加成 = 自机.空手攻击力 - 100;
                自机.空手攻击力 -= 自机.转换的冷兵器加成;
                自机.刀属性.power += 自机.转换的冷兵器加成;
                EffectSystem.Effect("紫金增幅", 自机._x, 自机._y + 30, 100);
                EffectSystem.Effect("刀虚影特效", 自机._x, 自机._y + 30, 100);
                _root.发布消息("空手攻击力转换为冷兵器加成");
            } else {
                自机.技能名 = "狂瀑扎";
                自机.状态改变("战技");
                自机.man.gotoAndPlay("狂瀑扎");
            }
        }}
_root.主动战技函数.兵器.狂瀑扎 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.浮空 && !自机.倒地;
        },
        释放: function(自机) {
            if (_root.控制目标 == 自机._name)
            {
                var 装备栏 = _root.物品栏.装备栏;
                头部装备 = 装备栏.getNameString("头部装备");
                上装装备 = 装备栏.getNameString("上装装备");
                手部装备 = 装备栏.getNameString("手部装备");
                下装装备 = 装备栏.getNameString("下装装备");
                脚部装备 = 装备栏.getNameString("脚部装备");
            } else {
                头部装备 = 自机.头部装备;
                上装装备 = 自机.上装装备;
                手部装备 = 自机.手部装备;
                下装装备 = 自机.下装装备;
                脚部装备 = 自机.脚部装备;
            }
            if (!自机.转换的冷兵器加成 && 自机.空手攻击力 > 100 && 头部装备 == "黑犀头甲" && 上装装备 == "黑犀胸甲" && 手部装备 == "黑犀手甲" && 下装装备 == "黑犀腿甲" && 脚部装备 == "黑犀鞋") {
                自机.转换的冷兵器加成 = 自机.空手攻击力 - 100;
                自机.空手攻击力 -= 自机.转换的冷兵器加成;
                自机.刀属性.power += 自机.转换的冷兵器加成;
                EffectSystem.Effect("紫金增幅", 自机._x, 自机._y + 30, 100);
                EffectSystem.Effect("刀虚影特效", 自机._x, 自机._y + 30, 100);
                _root.发布消息("空手攻击力转换为冷兵器加成");
            } else {
                自机.技能名 = "狂瀑扎";
                自机.状态改变("战技");
                自机.man.gotoAndPlay("狂瀑扎");
            }
        }}
_root.主动战技函数.空手.狂瀑顶 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.浮空 && !自机.倒地;
        },
        释放: function(自机) {
            if (_root.控制目标 == 自机._name)
            {
                var 装备栏 = _root.物品栏.装备栏;
                头部装备 = 装备栏.getNameString("头部装备");
                上装装备 = 装备栏.getNameString("上装装备");
                手部装备 = 装备栏.getNameString("手部装备");
                下装装备 = 装备栏.getNameString("下装装备");
                脚部装备 = 装备栏.getNameString("脚部装备");
            } else {
                头部装备 = 自机.头部装备;
                上装装备 = 自机.上装装备;
                手部装备 = 自机.手部装备;
                下装装备 = 自机.下装装备;
                脚部装备 = 自机.脚部装备;
            }
            if (自机.转换的冷兵器加成 && 头部装备 == "黑犀头甲" && 上装装备 == "黑犀胸甲" && 手部装备 == "黑犀手甲" && 下装装备 == "黑犀腿甲" && 脚部装备 == "黑犀鞋") {
                自机.空手攻击力 += 自机.转换的冷兵器加成;
                自机.刀属性.power -= 自机.转换的冷兵器加成;
                自机.转换的冷兵器加成 = 0;
                EffectSystem.Effect("紫金增幅", 自机._x, 自机._y + 30, 100);
                EffectSystem.Effect("拳虚影特效", 自机._x, 自机._y + 30, 100);
                _root.发布消息("已转换的冷兵器加成转换回空手攻击力");
            } else {
                自机.技能名 = "狂瀑顶";
                自机.状态改变("战技");
                自机.man.gotoAndPlay("狂瀑顶");
            }
        }}

_root.主动战技函数.兵器.追踪五连 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            自机.技能名 = "追踪五连";
            自机.状态改变("战技");
            自机.man.gotoAndPlay("追踪五连");
        }}
