
_root.主动战技函数 = {空手: {}, 兵器: {}, 长枪: {}, 手枪: {}, 手枪2: {}};

var 主动战技_读取技能路由等级 = function(自机, 攻击模式, 默认等级) {
    var 技能等级 = Number(默认等级);
    if (isNaN(技能等级) || 技能等级 <= 0 || 技能等级 > 10) {
        技能等级 = 1;
    }

    if (自机 && 自机.主动战技 && 自机.主动战技[攻击模式]) {
        var 战技等级 = Number(自机.主动战技[攻击模式].技能等级);
        if (!isNaN(战技等级) && 战技等级 > 0 && 战技等级 <= 10) {
            技能等级 = 战技等级;
        }
    }
    return 技能等级;
};

var 主动战技_创建技能路由战技 = function(技能名, 攻击模式, 默认等级) {
    return {初始化: function(自机) {
            自机.技能等级 = 主动战技_读取技能路由等级(自机, 攻击模式, 默认等级);
        },
        释放许可判定: function(自机) {
            return 自机.攻击模式 === 攻击模式 && !自机.倒地;
        },
        释放: function(自机) {
            自机.技能等级 = 主动战技_读取技能路由等级(自机, 攻击模式, 默认等级);
            _root.技能路由.技能标签跳转_旧(自机, 技能名);
        }}
};



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

_root.主动战技函数.空手.震地 = 主动战技_创建技能路由战技("震地", "空手", 1);

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


_root.主动战技函数.长枪.气锤地雷 = {初始化: null,
        释放许可判定: function(自机) {
            if (自机.倒地)
                return false;
            if (!(自机.状态 === "长枪行走" || 自机.状态 === "长枪站立") || 自机.换弹中)
                return false;
            return ItemUtil.singleSubmit("能量电池", 1,
                {source:"skill_cost", reason:"air_hammer_mine"});
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
            return ItemUtil.singleSubmit("强化石", 1,
                {source:"skill_cost", reason:"overload_strike"});
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
            return ItemUtil.singleSubmit("强化石", 1,
                {source:"skill_cost", reason:"macsiii_overload"});
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
            return ItemUtil.singleSubmit("强化石", 1,
                {source:"skill_cost", reason:"spear_edge"});
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
            if (ItemUtil.singleSubmit(自机.其他消耗物品, 1,
                    {source:"weapon_cost", reason:"alternate_ammo"})) {
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
                        if (_root.存档系统) _root.存档系统.dirtyMark = true;
                        org.flashNight.arki.item.PlayerAssetTransaction.recordEffect("loss", "item",
                            String(grenadeItem.name), 1,
                            {source:"weapon_cost", reason:"alternate_ammo"});
                        return true;
                    }
                    // 如果只有1个或是装备类型,直接移除并刷新装扮
                    else {
                        装备栏.remove("手雷");
                        if (_root.存档系统) _root.存档系统.dirtyMark = true;
                        org.flashNight.arki.item.PlayerAssetTransaction.recordEffect("loss",
                            ItemUtil.isEquipment(String(grenadeItem.name)) ? "equip" : "item",
                            String(grenadeItem.name), 1,
                            {source:"weapon_cost", reason:"alternate_ammo"});
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

_root.主动战技函数.空手.滑步 = _root.主动战技函数.兵器.滑步;
_root.主动战技函数.长枪.滑步 = _root.主动战技函数.兵器.滑步;
_root.主动战技函数.手枪.滑步 = _root.主动战技函数.兵器.滑步;
_root.主动战技函数.手枪2.滑步 = _root.主动战技函数.兵器.滑步;

_root.主动战技函数.长枪.震地 = 主动战技_创建技能路由战技("震地", "长枪", 1);
_root.主动战技函数.手枪.震地 = 主动战技_创建技能路由战技("震地", "手枪", 1);
_root.主动战技函数.手枪2.震地 = 主动战技_创建技能路由战技("震地", "手枪2", 1);

_root.主动战技函数.长枪.闪现 = 主动战技_创建技能路由战技("闪现", "长枪", 1);
_root.主动战技函数.手枪.闪现 = 主动战技_创建技能路由战技("闪现", "手枪", 1);
_root.主动战技函数.手枪2.闪现 = 主动战技_创建技能路由战技("闪现", "手枪2", 1);

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

_root.主动战技函数.兵器.神杀枪 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "神杀枪");
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

_root.主动战技函数.兵器.撼地烈狱 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "撼地烈狱");
        }}

_root.主动战技函数.兵器.猩红天秤 = {
    初始化:null,
    原子释放:true,
    播放方式:"container",
    释放许可判定:function(unit:MovieClip):Boolean {
        return unit.__titaniumType61 && unit.__titaniumType61.canBloodPact();
    },
    释放:function(unit:MovieClip):Boolean {
        if (!unit.__titaniumType61 || !unit.__titaniumType61.commitBloodPact()) return false;
        _root.战技路由.战技标签跳转_旧(unit, "猩红天秤", this.播放方式);
        return true;
    }
};

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

// ────────────────────────────────────────────────────────────────────────────
// 天启大封印（三蝶手稿插件授予，刀 / 拳(手部装备) / 长枪 通用）
//
// 数据配置：data/items/equipment_mods/特殊材料_通用.xml → <skill>
//              <skillname>天启大封印</skillname><cd>60000</cd><mp>500</mp><sp>10</sp>
// 封印逻辑本体：org.flashNight.arki.skill.SealDomain（范围收押 / 定住 / 无敌 / 按额度放逐 / 结束还原）
// 元件容器：战技容器-天启大封印；子弹元件：天启大封印
//
// 注意：本战技走"非原子释放"路径，MP 与 SP 由 释放主动战技 统一校验并扣除，
//       所以 释放许可判定 只做姿态判定，不要在这里扣资源。
// ────────────────────────────────────────────────────────────────────────────
_root.主动战技函数.兵器.天启大封印 = {初始化: null,
        释放许可判定: function(自机) {
            return !自机.倒地;
        },
        释放: function(自机) {
            _root.战技路由.战技标签跳转_旧(自机, "天启大封印");
        }}

// 刀 / 拳 / 长枪三个攻击模式共用同一份战技定义
_root.主动战技函数.空手.天启大封印 = _root.主动战技函数.兵器.天启大封印;
_root.主动战技函数.长枪.天启大封印 = _root.主动战技函数.兵器.天启大封印;

// ════════════════════════════════════════════════════════════════════════════
// 天启大封印 · 元件侧调用接口
//
// 目的：元件里只写「一行调用」，实现全部收在这里 + SealDomain 类里。
//       以后要改落成时机、实例命名、视觉挂载，只改这一节，不用回 CS6 动元件。
//
//   推荐（容器「出招」帧一行搞定，宿主子弹可以做成纯空 MC，不需要帧脚本）
//       _root.主动战技函数.长枪.天启大封印.落成(this);
//
//   分两步（想让子弹元件自己的第 1 帧来落成时）
//       容器出招帧 : var 子弹 = _root.主动战技函数.长枪.天启大封印.落成子弹(this);
//       子弹第 1 帧 : _root.主动战技函数.长枪.天启大封印.封印(this);
//
//   提前收工（换场景 / 做成可中断）
//       _root.主动战技函数.长枪.天启大封印.解除(this);
//
// 刀 / 拳 / 长枪 共用同一份定义（上方已有三条别名指向同一对象），从哪个模式调都一样。
//
// ⚠ 这些函数挂在「路由条目对象」上，与 初始化 / 释放许可判定 / 释放 是同一棵树。
//    路由链路只按名字读那三个键（见 单位函数_fs_aka_玩家模板迁移.as 的 装载主动战技），
//    多挂键不冲突。
// ════════════════════════════════════════════════════════════════════════════

/** 封印宿主（子弹）的 linkageIdentifier —— 元件改名只改这里 */
_root.主动战技函数.长枪.天启大封印.子弹元件名 = "天启大封印";

/**
 * 地面效果元件的 linkageIdentifier：与宿主**同位置、同生死**。
 * 在 落成子弹 里先于宿主 attach（深度更低，光柱盖在它上面），
 * 宿主被移除（到点自毁 / 连放换新清旧 / 解除 / 据点卸载）时经卸载链一并清掉。
 * 元件拆分后宿主只剩光柱，地面部分（法阵盘/裂纹等）全在这个元件里。
 */
_root.主动战技函数.长枪.天启大封印.地面效果元件名 = "天启大封印地面效果";

/**
 * 地面效果 attach 时的**初始**深度：负值，压在所有单位桶位（≥0）之下。
 * 双保险 —— 元件第 2 帧自己的 this.swapDepths(0) 每轮循环还会再钉一次；
 * 这里压低只是为了消灭「attach 后 → 元件第 2 帧执行前」的一帧高深度窗口。
 *
 * 为什么取 -1000 而不是 0：0 属于单位桶位带（DepthManager 桶公式下，
 * 屏幕最上沿的单位桶位是 0~255），attachMovie 到**已被占用**的深度会
 * 静默失败；负深度不在单位桶位带里，且 -1000 > -16384（保留区下限），
 * removeMovieClip 依然有效。
 */
_root.主动战技函数.长枪.天启大封印.地面效果初始深度 = -1000;

/** 宿主实例名的后缀，用来在 gameworld 里按施术者反查宿主，也用于避免撞名 */
_root.主动战技函数.长枪.天启大封印.实例名后缀 = "天启大封印";

/**
 * 由「容器 / 施术者 / 宿主」任一引用解析出宿主子弹。
 * 元件里通常只能拿到 this（容器），所以统一按实例命名规则反查。
 */
_root.主动战技函数.长枪.天启大封印.取宿主 = function(引用:MovieClip):MovieClip {
    if (引用 == undefined || 引用 == null) {
        return null;
    }
    // 直接给的就是宿主
    if (引用.封印状态 != undefined) {
        return 引用;
    }
    var 世界:MovieClip = _root.gameworld;
    if (世界 == undefined) {
        return null;
    }
    var 后缀:String = _root.主动战技函数.长枪.天启大封印.实例名后缀;
    // 容器 → 施术者是它的 _parent；也可能直接把施术者传了进来，两个都试
    if (引用._name != undefined) {
        var 命中1:MovieClip = 世界[引用._name + 后缀];
        if (命中1 != undefined && 命中1 != null) {
            return 命中1;
        }
    }
    if (引用._parent != undefined && 引用._parent._name != undefined) {
        var 命中2:MovieClip = 世界[引用._parent._name + 后缀];
        if (命中2 != undefined && 命中2 != null) {
            return 命中2;
        }
    }
    return null;
};

/**
 * 落成宿主子弹元件：在 _root.gameworld 上新建一个封印宿主，并把施术者记在它身上。
 *
 * 挂在 gameworld 下（不是挂在单位下），所以它不跟着单位移动、也不会被单位的状态切换
 * 连带卸载。**落成后宿主静止不动** —— 跟随目标由「法阵」在落成前完成，
 * 封印领域本身不追人。
 *
 * @param 容器:MovieClip 战技容器实例（元件里的 this），施术者是它的 _parent
 * @return MovieClip 宿主子弹；失败返回 null
 */
/**
 * 建封印宿主（子弹元件）并落在指定位置。
 *
 * @param 容器:MovieClip 战技容器
 * @param 落点:Object     可选 {x, y}。**调用方应在撤法阵之前把它取好**
 *                        （法阵坐标在撤法阵后就查不到了）。
 *                        传 null / undefined 时退回 取落成位置 现算。
 * @return 宿主 MovieClip；失败返回 null
 */
_root.主动战技函数.长枪.天启大封印.落成子弹 = function(容器:MovieClip, 落点:Object):MovieClip {
    var 自机:MovieClip = (容器 == undefined || 容器 == null) ? undefined : 容器._parent;
    if (自机 == undefined) {
        return null;
    }
    var 世界:MovieClip = _root.gameworld;
    if (世界 == undefined) {
        return null;
    }
    var 接口 = _root.主动战技函数.长枪.天启大封印;
    var 实例名:String = 自机._name + 接口.实例名后缀;

    // 同名旧宿主先清掉：连放两次时避免撞名。旧宿主的 onUnload 会让 SealDomain 自动收工
    // 并还原它控制中的全部单位（终止是幂等的）。
    var 旧宿主:MovieClip = 世界[实例名];
    if (旧宿主 != undefined && 旧宿主 != null) {
        旧宿主.removeMovieClip();
    }

    if (落点 == undefined || 落点 == null) {
        落点 = 接口.取落成位置(自机);
    }

    // 地面效果**先挂**在负深度上（见 地面效果初始深度 的说明），宿主（光柱）
    // 后挂 —— 两者同落点。地面效果的最终层级由元件第 2 帧自己的 swapDepths(0) 管。
    var 地面效果:MovieClip = 世界.attachMovie(
        接口.地面效果元件名,
        实例名 + "地面效果",
        接口.地面效果初始深度,
        { _x: 落点.x,
          _y: 落点.y }
    );

    var 宿主:MovieClip = 世界.attachMovie(
        接口.子弹元件名,
        实例名,
        世界.getNextHighestDepth(),
        { _x: 落点.x,
          _y: 落点.y,
          施术者: 自机 }
    );

    if (宿主 == undefined || 宿主 == null) {
        // 宿主没建成（理论上极罕见）：地面效果不能留成孤儿
        if (地面效果 != undefined && 地面效果 != null && 地面效果._parent != undefined) {
            地面效果.removeMovieClip();
        }
        return null;
    }

    // 光柱参与 Z 排序：一次性喂给 DepthManager。它的桶公式对 Y 严格单调，
    // 而**静态物体喂一次即永久正确** —— 单位桶位随移动各自变化，但任何一个
    // 单位与「固定 Y 的宿主桶位」的相对大小只取决于双方 Y，不会漂移。
    // 不喂的话宿主就停在 getNextHighestDepth 的快照深度上：释放瞬间压住所有人，
    // 之后单位往下走桶位超过快照就跳到光柱前，光柱又盖住下方桶位没超的单位。
    // 失败（未标定 / 容量满）时什么都不做，维持修复前的快照深度行为。
    // ⚠ 宿主从此在单位深度带里占一个槽位（容量 256）；连放两次的同名重建
    //   走 DepthManager 的 同名异引用检测 自动回收旧槽位，不泄漏。
    var 深度管理 = org.flashNight.gesh.depth.DepthManager.instance;
    if (深度管理 != undefined && 深度管理 != null) {
        深度管理.updateDepth(宿主, 宿主._y);
    }

    // 地面效果与宿主同生死：宿主被移除（50 秒到点自毁 / 连放两次清旧 /
    // 提前解除 / 换场景清理）时经卸载链把它一并带走。
    // 走 SealDomain 的卸载链封装（EventCoordinator），与 法阵交给宿主 同一套 ——
    // 直接写 宿主.onUnload 会被 EventCoordinator 的 proxy 静默吞掉。
    org.flashNight.arki.skill.SealDomain.挂卸载回调(宿主, function():Void {
        if (地面效果 != undefined && 地面效果 != null && 地面效果._parent != undefined) {
            地面效果.removeMovieClip();
        }
    });

    return 宿主;
};

/**
 * 推算封印宿主的落成位置（**仅在没有已知法阵坐标时使用**）。
 *
 * 规则与脚下法阵的兜底规则逐字一致：
 *     施术者._x + 法阵兜底距离 × 朝向,  施术者._y + 法阵Y偏移
 *
 * 注意：正常情况下应该由 落成 在撤法阵之前把法阵的真实坐标取出并传进来，
 * 这样"光柱落点"与"法阵当时的位置"严格相等（哪怕法阵吸在敌人身上）。
 *
 * @return Object {x:Number, y:Number}
 */
_root.主动战技函数.长枪.天启大封印.取落成位置 = function(自机:MovieClip):Object {
    var 接口 = _root.主动战技函数.长枪.天启大封印;
    var 方向:Number = (自机.方向 == "左") ? -1 : 1;
    // 兜底位也要带上 Y 偏移，否则没有敌人时法阵会和施术者错开一截（详见 法阵Y偏移）
    return { x: 自机._x + 接口.法阵兜底距离 * 方向,
             y: 自机._y + 接口.法阵Y偏移 };
};

/**
 * 封印（落成领域）。子弹元件第 1 帧调，或由 落成 内部调。
 * 幂等：同一个宿主重复调用只会落成一次。
 *
 * @param 宿主:MovieClip 宿主子弹（子弹元件里的 this）
 * @return Object SealDomain 的封印状态对象；失败返回 null
 */
_root.主动战技函数.长枪.天启大封印.封印 = function(宿主:MovieClip):Object {
    if (宿主 == undefined || 宿主 == null) {
        return null;
    }
    if (宿主.封印状态 != undefined && 宿主.封印状态 != null) {
        return 宿主.封印状态;                       // 已经落成过，直接返回
    }

    // ⚠ 这里**不能** stop() 宿主。
    // 宿主元件自己就是光柱美术，靠帧脚本做「爆发 1~15 → 循环 16~30」的播放头控制。
    // 一旦 stop()，元件会卡在第 1 帧，既不播爆发也永远进不了循环。
    // 封印逻辑与宿主的播放头无关（SealDomain 只读宿主坐标、给宿主挂卸载回调），
    // 所以让它自由播放即可。

    var 状态:Object = org.flashNight.arki.skill.SealDomain.封(宿主);
    宿主.封印状态 = 状态;

    // 宿主自己负责收工：SealDomain 只管封印逻辑，**不会销毁宿主**。
    // 没有这段的话，50 秒到点后 terminate 只是把引用置空，宿主元件会永远留在
    // _root.gameworld 里（光柱一直亮着）。所以这里给宿主挂一个每帧检查：
    // 状态.已结束 一旦为 true（到点 / 被 终止 / 宿主被换场景）就 removeMovieClip。
    _root.主动战技函数.长枪.天启大封印._挂宿主收尾(宿主, 状态);
    return 状态;
};

/**
 * 给封印宿主挂上「结束即自毁」的每帧检查。
 * 幂等：同一个宿主只挂一次。宿主已经被删 / 换场景时自动摘掉，不会泄漏。
 *
 * 为什么不用 onUnload：宿主是被主动 removeMovieClip 的一方，
 * onUnload 只在"别人删它"时触发；我们要的恰恰是"它自己发现该走了"。
 *
 * ⚠ 这个 onEnterFrame 同时兼任**播放头保活**：宿主是整条美术时间轴，
 *   靠帧脚本做「爆发 → gotoAndPlay 循环」。只要它身上有任何一个 onEnterFrame，
 *   AVM1 就认为它每帧被访问，stop() 冻不住它。所以这里必须自己挂，
 *   不能指望 SealDomain.确保播放 的空 handler —— 那个会被本函数覆盖。
 *   换句话说：本 handler 一旦挂上，SealDomain 每帧再调 确保播放 也是空操作。
 */
_root.主动战技函数.长枪.天启大封印._挂宿主收尾 = function(宿主:MovieClip, 状态:Object):Void {
    if (宿主 == undefined || 宿主 == null || 状态 == undefined || 状态 == null) {
        return;
    }
    if (宿主._收尾已挂 === true) {
        return;
    }
    宿主._收尾已挂 = true;
    宿主.onEnterFrame = function():Void {
        if (this._parent == undefined) {
            delete this.onEnterFrame;
            return;
        }
        if (this.封印状态 != undefined && this.封印状态.已结束 === true) {
            delete this.onEnterFrame;
            this.removeMovieClip();
        }
    };
};

/**
 * 落成 = 建宿主 + 立刻封印。推荐用法：容器「出招」帧一行调用。
 * 这样宿主子弹元件可以是个纯空 MC，不需要任何帧脚本。
 *
 * @param 容器:MovieClip 战技容器实例（元件里的 this）
 * @return Object SealDomain 的封印状态对象；失败返回 null
 */
_root.主动战技函数.长枪.天启大封印.落成 = function(容器:MovieClip):Object {
    var 接口 = _root.主动战技函数.长枪.天启大封印;
    var 施术者:MovieClip = (容器 == undefined || 容器 == null) ? undefined : 容器._parent;

    // 索敌上下文要在撤之前先摘出来：落成时撤法阵 = false 的话，
    // 要把法阵转交给封印宿主接管，而不是删掉。
    var 上下文:Object = (施术者 == undefined) ? null : 施术者["天启大封印索敌"];
    var 保留法阵:Boolean = (接口.落成时撤法阵 === false) &&
                           (上下文 != undefined && 上下文 != null);

    // ⚠ 关键：法阵坐标必须在**撤之前**记下来。
    // 撤法阵 会把 施术者.天启大封印索敌 置 null，之后再也读不到法阵。
    // 封印宿主必须落在「法阵消失前所在的位置」——它可能吸在敌人脚下、
    // 也可能是身前兜底位，不能事后重算。
    var 落点:Object = null;
    if (上下文 != undefined && 上下文 != null) {
        var 法阵:MovieClip = 上下文.法阵;
        if (法阵 != undefined && 法阵 != null && 法阵._parent != undefined) {
            落点 = { x: 法阵._x, y: 法阵._y };
        }
    }

    if (保留法阵) {
        // 只摘帧任务，留着法阵实例
        接口._摘索敌任务(施术者);
    } else {
        接口.撤法阵(容器);
    }

    var 状态:Object = 接口._落成核心(容器, 落点);
    if (保留法阵 && 状态 != undefined && 状态 != null) {
        接口.法阵交给宿主(状态, 上下文.法阵);
    }
    return 状态;
};

/**
 * 把法阵交给封印宿主接管：法阵从此**钉在宿主落成的位置**不动
 * （宿主本身落成后静止，所以法阵也不需要再跟谁走）。
 * 幂等：重复调用只接管一次。
 */
_root.主动战技函数.长枪.天启大封印.法阵交给宿主 = function(状态:Object, 法阵:MovieClip):Void {
    if (状态 == undefined || 状态 == null || 法阵 == undefined || 法阵 == null) {
        return;
    }
    if (状态.法阵已接管 === true) {
        return;
    }
    状态.法阵已接管 = true;
    状态.法阵 = 法阵;

    var 宿主:MovieClip = 状态.宿主;
    if (宿主 == undefined || 宿主 == null || 宿主._parent == undefined) {
        return;
    }
    // 位置对齐到宿主落点；之后双方都不移动，保持重合
    法阵._x = 宿主._x;
    法阵._y = 宿主._y;

    // ⚠ 不能写 `宿主.onUnload = …`：宿主若被 EventCoordinator 注册过生命周期任务，
    //    它的 onUnload 已被换成 proxy 并被 watch 住，直接赋值会被静默丢弃。
    //    统一走 SealDomain 的卸载链封装。
    org.flashNight.arki.skill.SealDomain.挂卸载回调(宿主, function():Void {
        _root.主动战技函数.长枪.天启大封印._清法阵引用(法阵);
    });
};

/**
 * 落成的实际实现。与 落成 分开，是为了让「撤法阵 / 转交法阵」两个入口
 * 共用同一段而不用重复代码。一般不需要直接调它。
 *
 * @param 容器:MovieClip 战技容器
 * @param 落点:Object    可选的 {x, y}：宿主要落的位置（通常取「法阵消失前所在坐标」）。
 *                       传 null / undefined = 按 取落成位置 自行推算。
 */
_root.主动战技函数.长枪.天启大封印._落成核心 = function(容器:MovieClip, 落点:Object):Object {
    var 接口 = _root.主动战技函数.长枪.天启大封印;
    var 宿主:MovieClip = 接口.落成子弹(容器, 落点);
    if (宿主 == undefined || 宿主 == null) {
        return null;
    }
    return 接口.封印(宿主);
};

/**
 * 解除封印（提前收工）。SealDomain.终止 幂等，重复调用无副作用。
 * 传 容器 / 施术者 / 宿主 都认。
 */
_root.主动战技函数.长枪.天启大封印.解除 = function(引用:MovieClip):Void {
    var 接口 = _root.主动战技函数.长枪.天启大封印;
    var 宿主:MovieClip = 接口.取宿主(引用);
    if (宿主 == undefined || 宿主 == null) {
        return;
    }
    var 状态:Object = 宿主.封印状态;
    if (状态 == undefined || 状态 == null) {
        return;
    }
    org.flashNight.arki.skill.SealDomain.终止(状态);
};

// ════════════════════════════════════════════════════════════════════════════
// 天启大封印 · 索敌与法阵（元件侧调用接口 之二）
//
// 和「索敌」以及「脚下法阵」有关的实现全部收在这里。元件侧只需要两行：
//
//   容器「起手」帧（开始索敌，法阵同时出现并跟随）
//       _root.主动战技函数.长枪.天启大封印.开始索敌(this);
//
//   容器「发射」帧（除了落成，什么都不用写）
//       _root.主动战技函数.长枪.天启大封印.落成(this);
//
// 落成 会自己把索敌和法阵撤掉，所以发射帧不需要额外调 撤法阵。
//
// ── 法阵元件是什么 ──────────────────────────────────────────────
// 就一个东西：**复制 导弹自瞄准星、把美术换成圆阵**的那个元件
// （见 CS6 接入说明 §3.4）。它同时扮演两个角色：
//   • 脚下圆阵 / 范围指示器（外圈代表 SealDomain 的判定范围）
//   • 准星（自带 onClipEvent：跟随 + 顺次换目标 + 回写 发射者.攻击目标）
//
// **所以只挂这一个，不建第二个。** 之前"准星 + 法阵"两份坐标重合的写法已取消。
//
// ── 跟随规则（= 上帝之杖那套，原样保留在元件里）────────────────
//   ① 范围里有敌人 → 踩在锁定目标的脚下（= 目标脚下 + 法阵Y偏移，见该常量注释）；
//      目标死了会顺次换下一个
//      （换人时写 施术者.攻击目标，所以落成封印的就是法阵当前踩着的那个敌人）
//   ② 范围里没有敌人 → 摆在施术者身前「法阵兜底距离」处、**同一条水平线**上
//      （= 施术者._y + 法阵Y偏移），朝左朝右自动判断
//
// 跟随由**法阵元件自己的帧脚本**负责；脚本侧每帧只补 2.5D 层级。
// 两条路不会同时写 攻击目标 —— 脚本只在「没有法阵元件」时才自己算目标。
//
// 法阵元件自己正常播放动画（旋转 / 呼吸都行）；位置由它自己每帧覆盖，两者不冲突。
// ════════════════════════════════════════════════════════════════════════════

/** 法阵（脚下圆阵）元件的 linkageIdentifier */
_root.主动战技函数.长枪.天启大封印.法阵元件名 = "天启大封印法阵";

/** 落成时是否把法阵撤掉。false = 让法阵留到封印结束（由 SealDomain 接管追踪） */
_root.主动战技函数.长枪.天启大封印.落成时撤法阵 = true;

/** 没有敌人时，法阵落在施术者身前的距离（也用作法阵的初始摆放位置） */
_root.主动战技函数.长枪.天启大封印.法阵兜底距离 = 390;

/**
 * 法阵 / 宿主的 Y 轴下移量（像素）。
 *
 * 为了配合 Z 轴排序，光柱元件的**原点画在形状下端**（DepthManager 按 Y 排层级时
 * 用的是形状底部，层级才正确）。所以把原点摆到参考点（目标脚下 / 施术者脚下）
 * 再往下 80，形状的**视觉中心**才正好与参考点重合。凡是"摆在某某脚边"的地方，
 * 统一写成 `参考点._y + 法阵Y偏移` —— 包括**没有敌人时的身前兜底位**，
 * 否则法阵（和它落成的封印宿主）会跟施术者错开一截、不在一条线上。
 *
 * ⚠ 三处必须同步改：
 *   ① 法阵元件里贴着敌人脚下的跟随（现在是 `敌人._y + 80`）；
 *   ② 本常量；
 *   ③ `SealDomain.宿主Y偏移`（它按 `宿主._y - 宿主Y偏移` 反推判定圆心）。
 */
_root.主动战技函数.长枪.天启大封印.法阵Y偏移 = 80;

/** 索敌起始距离 = 索敌距离 × 该倍率 */
_root.主动战技函数.长枪.天启大封印.索敌距离倍率 = 1;

/** 索敌距离从「起始」涨到「满值」用多少帧 */
_root.主动战技函数.长枪.天启大封印.索敌距离帧数 = 8;

/** 索敌距离上限 */
_root.主动战技函数.长枪.天启大封印.索敌距离上限 = 1200;

/**
 * 法阵的显示缩放（百分数，同时作用于 _xscale / _yscale）。
 *
 * 法阵元件本身**就是范围指示器** —— 它的外圈代表
 * SealDomain 的判定范围（以视觉中心为圆心，X 半径 300、Z 半径 80 的椭圆）。
 *
 * ⚠ 这里默认 100，含义是「元件里的图形已经是最终尺寸了」。
 *   推荐做法：把圆阵 SVG 拖进法阵元件后，**在元件内部**把图形缩到 940→600
 *   （即设为 63.83%，取 64），这样每个实例天然就是正确大小。
 *   若你不想在元件里缩，就把这里改成 64 让代码统一缩 —— 两种都行，**别同时缩**。
 *
 * 换算：圆阵素材外圈椭圆实测 940 × 470（宽高比 2.00）。
 *   缩放 = 范围半径X × 2 / 940 × 100 = 63.83 → 取 64（边界误差 +0.3%，肉眼不可辨）。
 *   想要视觉余量取 65（+2%）或 68（+7%）。
 *
 * ⚠ 判定现在是 600 × 160（宽高比 3.75），素材是 2.00 —— Z 方向视觉比判定**偏胖很多**
 *   （罩住的范围看起来比实际能封到的厚）。要让 Z 也贴合，得在元件里把椭圆
 *   压到 300 : 80 的高度，不要反过来把判定改不对称。
 *
 * ⚠ 改判定范围时要同比重算。这是 SealDomain.as 与本文件之间唯一的耦合点。
 */
_root.主动战技函数.长枪.天启大封印.法阵缩放 = 100;

/** 缩放作用在哪一轴（true = X 与 Y 同比，保持椭圆宽高比 2:1 不失真） */
_root.主动战技函数.长枪.天启大封印.法阵同比缩放 = true;

/**
 * 按「序号」在施术者身上存取索敌上下文。
 * 不用「技能名」当键是因为它含中文，变量名只能走 this[字符串] 形式，可读性差。
 */
_root.主动战技函数.长枪.天启大封印.取上下文 = function(施术者:MovieClip):Object {
    if (施术者 == undefined || 施术者 == null) {
        return null;
    }
    return 施术者["天启大封印索敌"];
};

/** 递归停掉一个元件自身及其可见子级的播放头（降开销用） */
_root.主动战技函数.长枪.天启大封印._停播 = function(元件, 深度:Number):Void {
    if (元件 == undefined || 元件 == null || 深度 <= 0) {
        return;
    }
    if (元件.stop != undefined) {
        元件.stop();
    }
    var 子级 = 元件._subMovies;
    if (子级 == undefined) {
        return;
    }
    for (var i:Number = 0; i < 子级.length; i++) {
        var 子 = 子级[i];
        if (子 != undefined && 子 != 元件) {
            _root.主动战技函数.长枪.天启大封印._停播(子, 深度 - 1);
        }
    }
};

/**
 * 取（必要时新建）索敌上下文，并在首次调用时创建「法阵」图形元件。
 *
 * 只建**一个**实例：这个元件既是脚下的圆阵（范围指示器），又自带索敌
 * （复制自 导弹自瞄准星，跟随 + 换目标 + 回写 攻击目标）。
 * 所以不需要"准星 + 法阵"两份 —— 一份就够。
 *
 * @param 施术者:MovieClip 施术者单位
 * @param 图形名:String    法阵元件 linkage；传 "" = 不建图形，只跑逻辑索敌
 */
_root.主动战技函数.长枪.天启大封印.建上下文 = function(施术者:MovieClip, 图形名:String):Object {
    if (施术者 == undefined || 施术者 == null) {
        return null;
    }
    var 接口 = _root.主动战技函数.长枪.天启大封印;
    var 世界:MovieClip = _root.gameworld;
    if (世界 == undefined) {
        return null;
    }
    var 上下文:Object = 施术者["天启大封印索敌"];
    if (上下文 != undefined && 上下文 != null) {
        return 上下文;                                  // 已经在索敌中，复用
    }

    上下文 = {};
    上下文.施术者 = 施术者;
    上下文.存活帧 = 0;
    上下文.追踪目标 = undefined;
    上下文.索敌目标列表 = null;
    上下文.敌人顺序 = 0;

    // 法阵实例名挂施术者名，一个施术者同时只有一个
    if (图形名 != undefined && 图形名 != null && 图形名 != "") {
        上下文.法阵实例名 = String(施术者._name) + "天启大封印法阵";
        var 旧法阵:MovieClip = 世界[上下文.法阵实例名];
        if (旧法阵 != undefined && 旧法阵 != null) {
            旧法阵.removeMovieClip();
        }
        // 缩放写在 initObject 里，法阵元件自身不需要事先在 CS6 里调好大小。
        // 法阵就是范围指示器：这个比例让它外圈压住 SealDomain 的椭圆判定边界。
        var 缩放:Number = 接口.法阵缩放;
        var 缩Y:Number = (接口.法阵同比缩放 === false) ? 100 : 缩放;
        上下文.法阵 = 世界.attachMovie(
            图形名,
            上下文.法阵实例名,
            世界.getNextHighestDepth(),
            { _x: 施术者._x + 接口.法阵兜底距离 * ((施术者.方向 == "左") ? -1 : 1),
              _y: 施术者._y + 接口.法阵Y偏移,
              _xscale: 缩放,
              _yscale: 缩Y,
              发射者: 施术者,
              循环最大次数: 0,
              索敌距离: 接口.索敌距离上限 }
        );
        // 法阵元件自己正常播放动画（旋转 / 呼吸等）；位置由帧任务每帧覆盖，两者不冲突。
        // 只有想用静止贴图换性能时才调 接口._停播(上下文.法阵, 3);
    }

    施术者["天启大封印索敌"] = 上下文;
    return 上下文;
};

/**
 * 开始索敌：建法阵（一个元件，兼任准星）+ 挂帧任务。
 * 法阵随之出现并按「敌人脚下 → 身前兜底」跟随。
 *
 * 法阵元件就是复制自 导弹自瞄准星 的那份（见 CS6 接入说明 §3.4）：
 * 自带跟随 / 顺次换目标 / 回写 发射者.攻击目标，同时圆阵美术充当范围指示器。
 * **只需要挂这一个**，不要再额外建准星 —— 它会自己跟。
 *
 * 容器里通常传 this；想换目标来源就调用 按目标索敌(施术者, 目标) 代替本函数。
 * 重复调用只会重建法阵，不会堆积帧任务。
 *
 * @param 引用:MovieClip 战技容器实例（元件里的 this）
 * @param 图形名:String   可选。覆盖 法阵元件名；传 "" = 不建图形（纯逻辑索敌，无可视化）
 * @return Object 索敌上下文；失败返回 null
 */
_root.主动战技函数.长枪.天启大封印.开始索敌 = function(引用:MovieClip, 图形名:String):Object {
    if (引用 == undefined || 引用 == null) {
        return null;
    }
    var 接口 = _root.主动战技函数.长枪.天启大封印;
    var 施术者:MovieClip = 引用._parent;
    if (施术者 == undefined || 施术者 == null) {
        return null;
    }
    if (图形名 == undefined) {
        图形名 = 接口.法阵元件名;
    }
    var 上下文:Object = 接口.建上下文(施术者, 图形名);
    if (上下文 == undefined || 上下文 == null) {
        return null;
    }
    接口._挂索敌任务(施术者);
    return 上下文;
};

/**
 * 换一个索敌来源：不按距离自己扫，而是跟着外部指定的目标走。
 * 给「用你自己的索敌实现 / 手动指定目标」留的入口。
 *
 * @param 施术者:MovieClip 施术者单位
 * @param 目标:MovieClip   要跟随的目标；传 null / undefined = 走「身前兜底」位置
 * @return Object 索敌上下文；失败返回 null
 */
_root.主动战技函数.长枪.天启大封印.按目标索敌 = function(施术者:MovieClip, 目标:MovieClip):Object {
    if (施术者 == undefined || 施术者 == null) {
        return null;
    }
    var 接口 = _root.主动战技函数.长枪.天启大封印;
    var 上下文:Object = 接口.建上下文(施术者, 接口.法阵元件名);
    if (上下文 == undefined || 上下文 == null) {
        return null;
    }
    上下文.锁定目标 = 目标;
    上下文.外部锁定 = true;
    接口._挂索敌任务(施术者);
    return 上下文;
};

/** 挂上索敌的每帧任务（幂等：已有任务号就直接返回） */
_root.主动战技函数.长枪.天启大封印._挂索敌任务 = function(施术者:MovieClip):Void {
    var 上下文:Object = 施术者["天启大封印索敌"];
    if (上下文 == undefined || 上下文 == null) {
        return;
    }
    if (上下文.任务号 != undefined && 上下文.任务号 != null) {
        return;                                          // 已经在跑
    }
    var 帧计时器 = _root.帧计时器;
    if (帧计时器 == undefined || 帧计时器.添加循环任务 == undefined) {
        return;
    }
    上下文.任务号 = 帧计时器.添加循环任务(function():Void {
        _root.主动战技函数.长枪.天启大封印.索敌每帧(施术者);
    }, 1);
};

/**
 * 索敌期间每帧。分两条路：
 *
 *   • **有法阵元件**（正常情况）：法阵复制自 导弹自瞄准星，它自己的
 *     `onClipEvent(enterFrame)` 每帧做完全部工作 —— 贴锁定目标脚下、
 *     从 索敌目标列表 顺次换人、回写 发射者.攻击目标。
 *     本函数这时只补 2.5D 层级，不碰坐标、不选目标（否则两边抢写入权）。
 *
 *   • **没有法阵元件**（开始索敌 第二参数传空串）：纯逻辑索敌，
 *     自己按距离扫目标、写 攻击目标，但没有可视化。
 *
 * 由帧任务驱动，一般不需要手动调。
 */
_root.主动战技函数.长枪.天启大封印.索敌每帧 = function(施术者:MovieClip):Void {
    if (施术者 == undefined || 施术者 == null || 施术者._parent == undefined) {
        _root.主动战技函数.长枪.天启大封印.撤法阵(施术者);
        return;
    }
    var 接口 = _root.主动战技函数.长枪.天启大封印;
    var 上下文:Object = 施术者["天启大封印索敌"];
    if (上下文 == undefined || 上下文 == null) {
        return;
    }
    上下文.存活帧++;

    // ① 有法阵 → 跟随全权交给它的 onClipEvent，这里只压层级
    var 法阵:MovieClip = 上下文.法阵;
    if (法阵 != undefined && 法阵 != null) {
        if (法阵._parent == undefined) {
            上下文.法阵 = null;                          // 被别处删了，下次 开始索敌 会重建
            return;
        }
        法阵.swapDepths(法阵._y);
        return;
    }

    // ② 没有法阵 → 纯逻辑索敌（无可视化）：选目标 + 回写 攻击目标 + 推进距离
    var 锁定:MovieClip = undefined;
    if (上下文.外部锁定 === true) {
        锁定 = 上下文.锁定目标;
        if (锁定 == undefined || 锁定 == null || !(锁定.hp > 0)) {
            锁定 = undefined;
        }
    } else {
        锁定 = 接口.取锁定目标(施术者, 上下文);
    }
    上下文.追踪目标 = 锁定;

    var 满距离:Number = 接口.索敌距离上限;
    var 起始:Number = 满距离 * 接口.索敌距离倍率;
    var 已走:Number = 接口.索敌距离帧数;
    if (已走 <= 0 || 上下文.存活帧 >= 已走) {
        上下文.当前距离 = 满距离;
    } else {
        上下文.当前距离 = 起始 + (满距离 - 起始) * (上下文.存活帧 / 已走);
    }

    if (锁定 != undefined && 锁定 != null) {
        施术者.攻击目标 = 锁定._name;
    }
};

/**
 * 自己按距离选锁定目标（不依赖准星元件）。
 * 优先吃准星留下的 索敌目标列表，没有就自己调 按距离索敌 扫一遍。
 */
_root.主动战技函数.长枪.天启大封印.取锁定目标 = function(施术者:MovieClip, 上下文:Object):MovieClip {
    var 接口 = _root.主动战技函数.长枪.天启大封印;

    // ① 重新索敌（准星那边也有这套流程，重复调用只是白算一次）
    if (上下文.是否需刷新 === true || 上下文.索敌目标列表 == undefined || 上下文.索敌目标列表 == null) {
        上下文.是否需刷新 = false;
        var 距离:Number = 上下文.当前距离;
        if (距离 == undefined || 距离 == null) {
            距离 = 接口.索敌距离上限;
        }
        上下文.追踪目标 = 施术者.按距离索敌(距离, true, "距离", "顺序");
        上下文.索敌目标列表 = 施术者.索敌目标列表;
        上下文.敌人顺序 = 0;
        if (上下文.追踪目标 == undefined || 上下文.追踪目标 == null || !(上下文.追踪目标.hp > 0)) {
            上下文.是否需刷新 = true;
        }
    }
    上下文.是否需刷新 = false;

    // ② 目标还活着就直接用
    if (上下文.追踪目标 != undefined && 上下文.追踪目标 != null && 上下文.追踪目标.hp > 0) {
        return 上下文.追踪目标;
    }

    // ③ 目标没了 → 顺次换列表里下一个还活着的
    var 列表:Array = 上下文.索敌目标列表;
    if (列表 != undefined && 列表 != null && 列表.length > 0) {
        if (上下文.敌人顺序 >= 列表.length - 1) {
            上下文.敌人顺序 = -1;
        }
        for (var i:Number = 上下文.敌人顺序 + 1; i < 列表.length; i++) {
            var 敌人 = 列表[i].敌人;
            if (敌人 != undefined && 敌人 != null && 敌人.hp > 0) {
                上下文.追踪目标 = 敌人;
                上下文.敌人顺序 = i;
                return 敌人;
            }
        }
    }

    // ④ 列表空了 → 下帧重新扫
    上下文.是否需刷新 = true;
    上下文.追踪目标 = undefined;
    return undefined;
};

/**
 * 只摘掉索敌的每帧任务，不动法阵实例（落成时把法阵转交宿主接管用）。
 * 幂等，没挂过任务时是空操作。
 */
_root.主动战技函数.长枪.天启大封印._摘索敌任务 = function(施术者:MovieClip):Void {
    if (施术者 == undefined || 施术者 == null) {
        return;
    }
    var 上下文:Object = 施术者["天启大封印索敌"];
    if (上下文 == undefined || 上下文 == null) {
        return;
    }
    if (上下文.任务号 != undefined && 上下文.任务号 != null) {
        var 帧计时器 = _root.帧计时器;
        if (帧计时器 != undefined && 帧计时器.移除任务 != undefined) {
            帧计时器.移除任务(上下文.任务号);
        }
        上下文.任务号 = null;
    }
    上下文.是否需刷新 = false;
};

/** 清掉一个法阵实例（按引用，不做名字反查），幂等 */
_root.主动战技函数.长枪.天启大封印._清法阵引用 = function(法阵:MovieClip):Void {
    if (法阵 != undefined && 法阵 != null) {
        法阵.removeMovieClip();
    }
};

/**
 * 撤掉索敌与法阵：removeMovieClip 法阵 + 移除帧任务 + 清掉施术者身上的上下文。
 * 幂等，重复调用安全；落成 会选择性地调它（见 落成时撤法阵）。
 */
_root.主动战技函数.长枪.天启大封印.撤法阵 = function(引用:MovieClip):Void {
    if (引用 == undefined || 引用 == null) {
        return;
    }
    var 接口 = _root.主动战技函数.长枪.天启大封印;
    // 传容器时施术者是它的 _parent；直接传施术者时就用它自己
    var 施术者:MovieClip = 引用;
    if (引用["天启大封印索敌"] == undefined) {
        施术者 = 引用._parent;
    }
    if (施术者 == undefined || 施术者 == null) {
        return;
    }
    var 上下文:Object = 施术者["天启大封印索敌"];
    if (上下文 == undefined || 上下文 == null) {
        return;
    }

    接口._摘索敌任务(施术者);

    // 清掉法阵实例（按引用，不做名字反查，避免和别的技能撞名）
    接口._清法阵引用(上下文.法阵);
    上下文.法阵 = null;

    施术者["天启大封印索敌"] = null;
};
