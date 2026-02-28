import org.flashNight.arki.scene.*;
import org.flashNight.sara.util.*;
import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.item.ItemUtil.*;
import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeUtil;

_root.主动战技函数 = {空手: {}, 兵器: {}, 长枪: {}};



//空手
_root.主动战技函数.空手.旋风腿 = {初始化: null,
        释放许可判定: function(自机) {
            return 自机.攻击模式 === "空手" && !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "旋风腿");
        }}

_root.主动战技函数.空手.飞身踢 = {初始化: null,
        释放许可判定: function(自机) {
            return 自机.攻击模式 === "空手" && !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "飞身踢");
        }}

_root.主动战技函数.空手.毁天灭地 = {初始化: null,
        释放许可判定: function(自机) {
            return 自机.攻击模式 === "空手";
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "毁天灭地");
        }}
_root.主动战技函数.空手.刀剑乱舞 = {初始化: null,
    释放许可判定: function(自机) {
        return !自机.倒地;
    },
    释放: function(自机) {
        _root.战技路由.战技标签跳转_旧(自机, "刀剑乱舞");
    }}

_root.主动战技函数.空手.地狱穿心剑 = {初始化: null,
        释放许可判定: function(自机) {
            return 自机.攻击模式 === "空手" && !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "地狱穿心剑");
        }}

_root.主动战技函数.空手.掌炮 = {初始化: null,
        释放许可判定: function(自机) {
            return 自机.攻击模式 === "空手";
        },
        释放: function(自机) {
            _root.播放音效("火箭重拳蓄力开始.wav");
            _root.战技路由.战技标签跳转_旧(自机, "掌炮");
        }}

_root.主动战技函数.空手.震地 = {初始化: null,
        释放许可判定: function(自机) {
            return 自机.攻击模式 === "空手" && !自机.倒地;
        },
        释放: function(自机) {
            _root.技能路由.技能标签跳转_旧(自机, "震地");
        }}

_root.主动战技函数.空手.贯空天盖战技 = {初始化: null,
        释放许可判定: function(自机) {
            return 自机.攻击模式 === "空手";
        },
        释放: function(自机) {
            var 装备栏 = _root.物品栏.装备栏;
            var 头部装备 = 装备栏.getNameString("头部装备");
            var 上装装备 = 装备栏.getNameString("上装装备");
            var 战技列表 = ["咒针","伸手及月"];
            if(头部装备 == "登上明星"){
                战技列表.push("登上明星");
            }
            if(上装装备 == "贯空天盖上衣"){
                战技列表.push("回归枢机之光");
            }
            if(!装备栏.getItem("手部装备").value.当前战技){
                装备栏.getItem("手部装备").value.当前战技 = 0;
            }
            var 战技类型 = 战技列表[装备栏.getItem("手部装备").value.当前战技];
            if(!战技类型){
                装备栏.getItem("手部装备").value.当前战技 = 0;
                战技类型 = 战技列表[0];
                _root.发布消息("当前战技切换为"+ 战技列表[0]);
            }
            if(战技类型 == "回归枢机之光"){
                if(!自机.回归枢机之光发射数){
                    自机.回归枢机之光发射数 = 0;
                }
                if(自机.回归枢机之光发射数 >= 5){
                    _root.发布消息("本张地图[回归枢机之光]发射数已达到上限");  
                    自机.mp += 100;
                }else if(自机.mp >= 300){
                    自机.mp -= 200;
                    _root.战技路由.战技标签跳转_旧(自机, "回归枢机之光");
                }else{
                    _root.发布消息("当前mp不足以释放[回归枢机之光]");
                    自机.mp += 100;
                }
            }else if(战技类型 == "登上明星"){
                自机.登上明星消耗mp = Math.ceil(自机.mp * 0.01);
                _root.战技路由.战技标签跳转_旧(自机, "登上明星");
            }else{
                if(战技类型 == "伸手及月"){
                    自机.手部发射子弹属性 = {
                        子弹种类: "伸手及月",
                        声音: "伸手及月.wav",
                        子弹威力: 10 * 自机.内力,
                        子弹速度: 25,
                        Z轴攻击范围: 50,
                        击倒率:2,
                        伤害类型:"破击",
                        魔法伤害属性:"蚀",
                        击中时触发函数:function(){
                            var 暂存敌人 = this.命中对象;
                            var childBuffs:Array = [
                                new PodBuff("行走X速度", BuffCalculationType.MULT_POSITIVE, 0.1)
                            ];

                            // 时间限制
                            var timeLimitComp:TimeLimitComponent = new TimeLimitComponent(150);
                            var components:Array = [timeLimitComp];

                            var metaBuff:MetaBuff = new MetaBuff(childBuffs, components, 0);
                            暂存敌人.buffManager.addBuff(metaBuff, "伸手及月");
                            if (!this.已爆炸)
                            {
                                this.已爆炸 = true;
                                //this.伤害类型 = "真伤";
                                this.xmov = 0;
                                this.ymov = 0;
                                gotoAndPlay("爆炸");
                            }
                        }
                    };
                    if(自机.性别 == "女"){
                        自机.手部发射子弹属性.声音 = "伸手及月无人声.wav";
                    }
                }else{
                    自机.手部发射子弹属性 = {
                        子弹种类: "普通咒针",
                        声音: "speed07.wav",
                        子弹威力: 10 * 自机.内力,
                        子弹速度: 35,
                        Z轴攻击范围: 30,
                        击倒率:5,
                        伤害类型:"破击",
                        魔法伤害属性:"人类",
                        毒:2000,
                        霰弹值:3,
                        子弹散射度:5
                    };
                }
                _root.战技路由.战技标签跳转_旧(自机, "手部发射");
            }
        }}


//长枪
_root.主动战技函数.长枪.发射榴弹 = {初始化: function(自机) {
    自机.当前弹夹副武器已发射数 = 0;
    //再次读取物品属性取得传参
    var 长枪物品信息 = 自机.长枪数据;
    var skill = 长枪物品信息.skill;
    var basePower:Number = skill.power && skill.power > 0 ? Number(skill.power) : 2500;

    // 冲击连携对霰弹枪的伤害加成：15%→25% 线性插值（等级1-10）
    var passiveSkills:Object = 自机.被动技能;
    if (passiveSkills && passiveSkills.冲击连携 && passiveSkills.冲击连携.启用) {
        var weaponTypeTag:String = 长枪物品信息.weapontype;
        if (weaponTypeTag == "霰弹枪") {
            var lv:Number = passiveSkills.冲击连携.等级 || 1;
            var damageBonus:Number = 0.15 + (lv - 1) * (0.25 - 0.15) / 9;
            basePower *= (1 + damageBonus);
        }
    }

    自机.副武器子弹威力 = basePower;
    自机.副武器可发射数 = skill.bulletsize > 0 ? Number(skill.bulletsize) : 1;
    自机.副武器弹药类型 = skill.clipname ? skill.clipname : "榴弹弹药";
    自机.副武器子弹种类 = skill.bullet ? skill.bullet : "榴弹";
    自机.副武器子弹声音 = skill.sound ? skill.sound : "re_GL_under.wav";
    自机.副武器子弹霰弹值 = skill.split && skill.split > 0 ? Number(skill.split) : 1;
    自机.副武器子弹散射度 = skill.diffusion && skill.diffusion > 0 ? Number(skill.diffusion) : 0;
    自机.副武器子弹速度 = skill.velocity && skill.velocity > 0 ? Number(skill.velocity) : 25;
    自机.副武器子弹Z轴攻击范围 = skill.range && skill.range > 0 ? Number(skill.range) : 50;
    自机.副武器子弹击倒率 = skill.impact && skill.impact > 0 ? Number(skill.impact) : 0.01;
    自机.副武器即时消耗弹药 = skill.instantconsume === true;
    自机.副武器伤害类型 = skill.damagetype ? skill.damagetype : "物理"; // 写null会默认读取发射者的属性产生污染
    自机.副武器魔法伤害属性 = skill.magictype ? skill.magictype : null;
},
        释放许可判定: function(自机) {
            if (自机.当前弹夹副武器已发射数 >= 自机.副武器可发射数)
                return false;
            if (自机.浮空 || 自机.倒地)
                return false;
            if (!(自机.状态 === "长枪行走" || 自机.状态 === "长枪站立") || 自机.换弹中)
                return false;
            //检测物品栏弹药
            if (自机.副武器即时消耗弹药) {
                //即时消耗模式：每次发射前检测弹药
                if (ItemUtil.singleSubmit(自机.副武器弹药类型, 1)) {
                    return true;
                }
                return false;
            } else {
                //默认模式：换弹时消耗，发射时只检测已发射数
                if (自机.当前弹夹副武器已发射数 > 0) {
                    return true;
                } else if (ItemUtil.singleSubmit(自机.副武器弹药类型, 1)) {
                    // _root.发布消息(自机.副武器弹药类型 + "耗尽！");
                    return true;
                }
                return false;
            }
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
            子弹属性.伤害类型 = 自机.副武器伤害类型;
            子弹属性.魔法伤害属性 = 自机.副武器魔法伤害属性;
            _root.子弹区域shoot传递(子弹属性);
        }};

_root.主动战技函数.长枪.气锤地雷 = {初始化: null,
        释放许可判定: function(自机) {
            if (自机.倒地)
                return false;
            if (!(自机.状态 === "长枪行走" || 自机.状态 === "长枪站立") || 自机.换弹中)
                return false;
            return ItemUtil.singleSubmit("能量电池", 1);
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
            return ItemUtil.singleSubmit("强化石", 1);
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
            return ItemUtil.singleSubmit("强化石", 1);
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
            return ItemUtil.singleSubmit("强化石", 1);
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
    var 长枪物品信息 = 自机.长枪数据;
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
        var rate:Number = (自机[magazineCapName] - 自机.长枪.value.shot) * prop.霰弹值 / 3;
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

_root.主动战技函数.长枪.调用射击发射其他弹药 = {初始化: function(自机) {
    var 长枪物品信息 = 自机.长枪数据;
    var skill = 长枪物品信息.skill;

    // 从配置读取战技参数
    自机.其他弹药类型 = skill.bullet ? skill.bullet : "核战斗部火箭弹";
    自机.其他霰弹值 = skill.split && skill.split > 0 ? Number(skill.split) : 1;
    自机.其他音效 = skill.sound ? skill.sound : "re_GL_m202.wav";
    自机.其他消耗物品 = skill.clipname ? skill.clipname : "战术核弹手雷";

    // 子弹速度: skill.velocity存在时使用配置值(包括0), 否则使用undefined标记(表示继承武器原速度)
    // 注意: velocity=0 是合法值(近战子弹), velocity>=0 都应该被应用
    自机.其他子弹速度 = skill.velocity !== undefined ? Number(skill.velocity) : undefined;

    // 威力支持三种模式:
    // 1. skill.power > 0: 使用配置的固定威力值
    // 2. skill.power = 0: 使用武器基础威力 (继承原有伤害)
    // 3. skill.power < 0: 使用武器基础威力的倍率 (如 -2 表示2倍伤害)
    自机.其他子弹威力模式 = skill.power !== undefined ? Number(skill.power) : 100000;

    // 订阅"长枪射击"事件,在实际射击时修改子弹属性
    自机.dispatcher.subscribe("长枪射击", function() {
        // 检查开关: 只有战技激活时才修改属性
        if (!自机.其他弹药开启)
            return;

        var prop:Object = 自机.man.子弹属性;

        // 替换子弹属性为配置的弹药
        prop.子弹种类 = 自机.其他弹药类型;
        prop.霰弹值 = 自机.其他霰弹值;
        prop.sound = 自机.其他音效;

        // 应用子弹速度 (如果配置了的话)
        // velocity>=0 都是合法值(0=近战子弹), 只有undefined时才继承武器原速度
        if (自机.其他子弹速度 !== undefined) {
            prop.子弹速度 = 自机.其他子弹速度;
        }

        // _root.发布消息("调用射击发射其他弹药 - 子弹速度:", prop.子弹速度, "配置值:", 自机.其他子弹速度);

        // 根据威力模式设置子弹威力
        if (自机.其他子弹威力模式 > 0) {
            // 模式1: 固定威力值 (应用被动技能增幅)
            // 使用 ShootInitCore.calculateWeaponPower 确保受到长枪被动技能加成
            prop.子弹威力 = ShootInitCore.calculateWeaponPower(
                自机,
                "长枪",
                自机.其他子弹威力模式,
                BulletTypeUtil.isRay(自机.其他弹药类型)
            );
        } else if (自机.其他子弹威力模式 < 0) {
            // 模式2: 倍率模式 (基于武器原始威力的倍率,已经包含被动增幅)
            // prop.子弹威力 已经在初始化时通过 calculateWeaponPower 计算过
            // 这里直接乘以倍率即可
            prop.子弹威力 *= Math.abs(自机.其他子弹威力模式);
        }

        // _root.发布消息("调用射击发射其他弹药 - 子弹威力:", prop.子弹威力);
        // 模式3: 等于0时不修改,继承武器原有威力(已包含被动增幅)

        // 修正弹药消耗计数 (因为攻击本身会扣1发)
        自机.长枪.value.shot += 自机.其他霰弹值 - 1;

        // 用完后立即关闭,避免影响后续正常射击
        自机.其他弹药开启 = false;
    });
},
        释放许可判定: function(自机) {
            // 正在射击时不允许释放
            if (自机["主手射击中"])
                return false;

            // 检查弹匣容量是否足够
            var magazineCapName:String = "长枪弹匣容量";
            if (自机.长枪.value.shot + 自机.其他霰弹值 > 自机[magazineCapName])
                return false;

            // 浮空或倒地时不允许释放
            if (自机.浮空 || 自机.倒地)
                return false;

            // 优先尝试从背包/药剂栏扣除消耗品
            if (ItemUtil.singleSubmit(自机.其他消耗物品, 1)) {
                return true;
            }

            // Fallback: 检查手雷装备栏是否有对应消耗品
            // 这样可以让装备在手雷栏的战术核弹也能用于战技
            if (_root.控制目标 === 自机._name) {
                var 装备栏 = _root.物品栏.装备栏;
                var grenadeItem = 装备栏.getItem("手雷");

                if (grenadeItem && grenadeItem.name == 自机.其他消耗物品) {
                    // 如果是可堆叠消耗品(有数量),就减1
                    if (!isNaN(grenadeItem.value) && grenadeItem.value > 1) {
                        grenadeItem.value -= 1;
                        return true;
                    }
                    // 如果只有1个或是装备类型,直接移除并刷新装扮
                    else {
                        装备栏.remove("手雷");
                        _root.刷新人物装扮(自机._name);
                        return true;
                    }
                }
            }

            return false;
        },
        释放: function(自机) {
            // 1. 取消强制奔跑状态
            自机.强制奔跑 = false;

            // 2. 强制启用动作A (允许射击)
            自机.动作A = true;

            // 3. 开启战技开关,触发事件订阅
            自机.其他弹药开启 = true;

            // 4. 执行攻击 → 触发"长枪射击"事件 → 执行订阅回调修改属性
            自机.攻击();

            // 5. 恢复原始子弹属性 (防御性编程,确保不影响后续射击)
            var data:Object = 自机.长枪属性;
            var prop:Object = 自机.man.子弹属性;

            prop.子弹种类 = data.bullet;
            prop.霰弹值 = data.split;
            prop.sound = data.sound;
            prop.子弹威力 = data.power;  // 恢复原始威力
            // _root.发布消息(prop.子弹速度, data.velocity);
            prop.子弹速度 = data.velocity;  // 恢复原始速度
        }}


_root.主动战技函数.长枪.突击者之眼 = {初始化: function(自机) {
    var 长枪物品信息 = 自机.长枪数据;
    var skill = 长枪物品信息.skill;
    自机.突击者之眼弹药类型 = skill.bullet ? skill.bullet : "横向联弹-无壳穿刺子弹";
    自机.突击者之眼数 = skill.split && skill.split > 0 ? Number(skill.split) : 3;
    自机.突击者之眼音效 = skill.sound ? skill.sound : "re_GL_under.wav";

    var upgradeLevel:Number = 自机.长枪.value.level;

    // ========== 冷却时间缩减公式 ==========
    // 数学模型: factor = 1 / (1 + k·level³)
    //
    // 公式特性:
    //   - 类型: 递减型有理函数 (三次方分母)
    //   - 值域: (0, 1], 永远不会达到0或负数
    //   - 单调性: 严格递减, 强化等级越高冷却越短
    //   - 边际收益: Lv3-4达到峰值 (~430ms/级), 后期递减但总收益持续增长
    //
    // 常数设计:
    //   k = 22/1029 = 22/(3×7³) ≈ 0.02138
    //   - 分母1029使用7³对应公式中的level³
    //   - 精确调校使Lv13达到97.9%缩减率 (2000ms→42ms)
    //
    // 典型收益 (基础冷却2000ms):
    //   Lv1:  1958ms ( 2.1%缩减) - 初步强化
    //   Lv3:  1268ms (36.6%缩减) - 边际收益峰值区间
    //   Lv5:   545ms (72.8%缩减) - 主流玩家目标
    //   Lv10:   89ms (95.5%缩减) - 高端配置
    //   Lv13:   42ms (97.9%缩减) - 极限强化 (47.9倍缩减!)
    //
    // 设计意图:
    //   前期: 小投入大回报 (鼓励尝试强化)
    //   中期: 持续递增收益 (保持强化动力)
    //   后期: 边际递减但总收益巨大 (避免数值失衡)
    // =====================================

    var k:Number = 22 / 1029; // ≈ 0.02138, 精确调校常数
    var level:Number = upgradeLevel; // 武器强化等级 (1-13)

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
    var 长枪物品信息 = 自机.长枪数据;
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
            _root.技能路由.技能标签跳转_旧(自机, "抡枪");
        }}



//兵器
_root.主动战技函数.兵器.滑步 = {初始化: null,
        释放许可判定: function(自机) {
            return true; //应该是无条件吧（）
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "战技小跳");
        }}

_root.主动战技函数.兵器.弧光斩 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "弧光斩");
        }}

_root.主动战技函数.兵器.地狱斩绝 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "地狱斩绝");
        }}

_root.主动战技函数.兵器.Overdrive = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "Overdrive");
        }}

_root.主动战技函数.兵器.EternalMaximumDrive = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "Eternal Maximum Drive");
        }}

_root.主动战技函数.兵器.Excalibur = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "Excalibur");
        }}

_root.主动战技函数.兵器.凶斩 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "凶斩");
        }}

_root.主动战技函数.兵器.狼跳 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "狼跳");
        }}

_root.主动战技函数.兵器.回旋斩击 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "回旋斩击");
        }}

_root.主动战技函数.兵器.回旋裂地 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "回旋裂地");
        }}

_root.主动战技函数.兵器.破坏殆尽 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "破坏殆尽");
        }}

_root.主动战技函数.兵器.雷鸣感召 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "雷鸣感召");
        }}

_root.主动战技函数.兵器.突刺 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "突刺");
        }}

_root.主动战技函数.兵器.重力操作 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "重力操作");
        }}

_root.主动战技函数.兵器.瞬步斩 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "瞬步斩");
        }}
_root.主动战技函数.兵器.一文字落雷 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "一文字落雷");
            
        }}

_root.主动战技函数.兵器.漆黑凶斩 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "漆黑凶斩");
        }}

_root.主动战技函数.兵器.黑刀斩术 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "黑刀斩术");
        }}

_root.主动战技函数.兵器.猩红居合 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "猩红凶斩");
        }}

_root.主动战技函数.兵器.居合次元斩 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "居合次元斩");
        }}

_root.主动战技函数.兵器.天蓝斩术 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "蓝瞬步斩");
        }}

_root.主动战技函数.兵器.辉光剑气 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "辉光剑气");
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
                _root.战技路由.战技标签跳转_旧(自机, "追踪五连");
            }
        }}

_root.主动战技函数.兵器.深冲利刺 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "深冲利刺");
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
                var 狮王防御加成倍率 = 1 + 我方角色数量 * 0.10;

                // 使用新BuffManager系统：MULT_POSITIVE保守语义，多个乘算buff只取最大值
                var childBuffs:Array = [
                    new PodBuff("空手攻击力", BuffCalculationType.MULT_POSITIVE, 狮王攻击加成倍率),
                    new PodBuff("防御力", BuffCalculationType.MULT_POSITIVE, 狮王防御加成倍率)
                ];
                var metaBuff:MetaBuff = new MetaBuff(childBuffs, [], 0);
                // 使用 addBuffImmediate 立即应用，以便后续播报正确的数值
                自机.buffManager.addBuffImmediate(metaBuff, "狮子之力");

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
            _root.战技路由.战技标签跳转_旧(自机, "暴走");
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
                _root.战技路由.战技标签跳转_旧(自机, "狂瀑扎");
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
                _root.战技路由.战技标签跳转_旧(自机, "狂瀑扎");
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
                _root.战技路由.战技标签跳转_旧(自机, "狂瀑顶");
            }
        }}

_root.主动战技函数.兵器.追踪五连 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "追踪五连");
        }}

/**
 * 天秤之力 - 光剑天秤主动技能（空壳）
 *
 * 实际释放逻辑在装备生命周期函数中实现：
 * scripts/逻辑/装备函数/光剑天秤.as -> WeaponSkill 事件订阅
 *
 * 这样设计是因为主动技需要访问装备的 ref 对象（天秤切换次数等状态），
 * 而 ref 只能通过装备初始化时的闘包持久化访问，无法从战技函数中直接获取。
 *
 * 数据配置: data/items/武器_刀.xml -> <skill> 节点
 */
_root.主动战技函数.兵器.天秤之力 = {
    初始化: null,
    释放许可判定: function(自机) {
        return 自机.攻击模式 === "兵器";
    },
    释放: function(自机) {
        // 实际逻辑由 光剑天秤.as 中的 WeaponSkill 事件处理
        // 此处为空壳，仅触发事件流程
    }
}

/**
 * 镰刀追踪充能 - 键盘镰刀空中战技（空壳）
 *
 * 实际释放逻辑在装备生命周期函数中实现：
 * scripts/逻辑/装备函数/键盘镰刀.as -> WeaponSkill 事件订阅
 *
 * 空中按战技键时为镰刀补充追踪强度，消耗MP换取追踪能量。
 * 追踪强度用于空中跳砍时自动追踪敌人位置。
 *
 * 数据配置: data/items/武器_刀_镰刀.xml -> <skill_1> 节点
 */
_root.主动战技函数.兵器.镰刀追踪充能 = {
    初始化: null,
    释放许可判定: function(自机) {
        return 自机.攻击模式 === "兵器";
    },
    释放: function(自机) {
        // 实际逻辑由 键盘镰刀.as 中的 WeaponSkill 事件处理
        // 此处为空壳，仅触发事件流程
        自机.temp_y = 0;
    }
}
