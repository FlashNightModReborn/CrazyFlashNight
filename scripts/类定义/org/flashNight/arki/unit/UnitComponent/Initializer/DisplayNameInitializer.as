import org.flashNight.gesh.string.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.DisplayNameInitializer {
    // 表驱动映射，存储称号与对应的处理函数
    private static var _titleHandlers:Object = initializeHandlers();

    // 初始化处理函数映射表（只初始化一次）
    private static function initializeHandlers():Object {
        var obj:Object = {
            坛主: function(target:Object):Void {
                target.称号 = MansionRandomizer.getInstance().getRandomName() + target.称号;
            },
            散人: function(target:Object):Void {
                target.称号 = HexagramRandomizer.getInstance().getRandomName() + target.称号;
            },
            军阀: function(target:Object):Void {
                target.称号 = JuntaRandomizer.getInstance().getRandomName();
            }
            // 可在此继续添加新的称号处理逻辑
        };

        return obj;
    }

    // 新增：格式化显示名称的函数
    public static function formatDisplayName(color:String, level:Number, makeBold:String, name:String):String {
        return color + "Lv." + level + "   " + makeBold + name + "</B>" + "</FONT>";
    }

    public static function syncCf6SoldierPhase(target:Object, phase:Number):Void {
        if (target == null) {
            return;
        }
        var kind:String = String(target.兵种);
        var isPhaseOne:Boolean = (phase == 1);
        if (kind != "敌人-CF6特种兵" && kind != "敌人-CF6持盾特种兵"
                && kind != "敌人-CF6特种精英" && kind != "敌人-CF6持盾特种精英"
                && kind != "敌人-CF6特种教官" && kind != "敌人-CF6持盾特种教官") {
            return;
        }
        var courtTitle:String = Cf6NameRandomizer.getCourtDetachmentTitle();
        target.驻防番号 = courtTitle;
        if (_root != null && _root.gameworld != null) {
            _root.gameworld.cf6CourtDetachment = courtTitle;
        }
        if (kind == "敌人-CF6特种兵" || kind == "敌人-CF6持盾特种兵") {
            target.名字 = isPhaseOne ? "重盾突击兵" : "突击步兵";
            if (!target.称号) {
                target.称号 = courtTitle;
            }
        } else if (kind == "敌人-CF6特种精英" || kind == "敌人-CF6持盾特种精英") {
            target.名字 = isPhaseOne ? "攻坚盾卫" : "机动特勤";
            if (!target.称号) {
                target.称号 = Cf6NameRandomizer.getMinorArcanaTitle(target);
            }
        } else {
            target.名字 = isPhaseOne ? "重盾教官" : "战术教官";
            var isReversed:Boolean = !isPhaseOne;
            if (!target.称号) {
                target.称号 = Cf6NameRandomizer.getMajorArcanaTitle(target, isReversed);
            } else {
                target.称号 = Cf6NameRandomizer.formatInstructorTitle(String(target.称号), isReversed);
            }
        }
        refreshName(target, false);
    }

    private static function bindCf6SoldierHooks(target:Object):Void {
        var syncFn:Function = function(phase:Number):Void {
            var p:Number = (phase === 1 || phase === 2) ? phase : (Number(target.soldierPhase) == 1 ? 1 : 2);
            DisplayNameInitializer.syncCf6SoldierPhase(target, p);
        };
        target.unwatch("eliteUpdateName");
        target.eliteUpdateName = syncFn;
        target.watch("eliteUpdateName", function(prop:String, oldVal:Function, newVal:Function):Function {
            return syncFn;
        });
        target.watch("soldierPhase", function(prop:String, oldVal:Number, newVal:Number):Number {
            DisplayNameInitializer.syncCf6SoldierPhase(target, Number(newVal) == 1 ? 1 : 2);
            return newVal;
        });
    }

    private static function applyCf6Identity(target:Object):Void {
        if (target == null) {
            return;
        }
        var kind:String = String(target.兵种);
        if (kind == "敌人-CF6特种兵" || kind == "敌人-CF6持盾特种兵"
                || kind == "敌人-CF6特种精英" || kind == "敌人-CF6持盾特种精英"
                || kind == "敌人-CF6特种教官" || kind == "敌人-CF6持盾特种教官") {
            var defaultPhase:Number = (kind == "敌人-CF6持盾特种兵" || kind == "敌人-CF6持盾特种精英" || kind == "敌人-CF6持盾特种教官") ? 1 : 2;
            var phase:Number = (target.soldierPhase === 1 || target.soldierPhase === 2)
                ? Number(target.soldierPhase)
                : ((target.特种兵初始阶段 === 1 || target.特种兵初始阶段 === 2) ? Number(target.特种兵初始阶段) : defaultPhase);
            syncCf6SoldierPhase(target, phase);
            bindCf6SoldierHooks(target);
            return;
        }
        if (kind == "敌人-CF6光头保安" || kind == "敌人-CF6变身光头保安") {
            if (!target.名字 || String(target.名字).indexOf("CF6光头保安") == 0) {
                target.名字 = "安保干员";
            }
            var guardCourtTitle:String = Cf6NameRandomizer.getCourtDetachmentTitle();
            target.驻防番号 = guardCourtTitle;
            if (_root != null && _root.gameworld != null) {
                _root.gameworld.cf6CourtDetachment = guardCourtTitle;
            }
            if (!target.称号) {
                target.称号 = guardCourtTitle;
            }
        } else if (kind == "敌人-CF6普通男僵尸") {
            if (!target.名字 || target.名字 == "CF6黄衣僵尸") {
                target.名字 = "制服感染者";
            }
        } else if (kind == "敌人-CF6女僵尸") {
            if (!target.名字 || target.名字 == "CF6红衣僵尸") {
                target.名字 = "游荡感染者";
            }
        } else if (kind == "敌人-CF6蛮蛮") {
            if (target.称号 == "Boss") {
                target.称号 = "C.T重装处刑人";
            }
        } else if (kind == "敌人-CF6Wings") {
            if (!target.名字 || target.名字 == "Wings") {
                target.名字 = "「翼」型克隆特工";
            }
            if (target.称号 == "3XF-W00") {
                target.称号 = Cf6NameRandomizer.getWingsZeroTitle(target);
            } else if (!target.称号) {
                target.称号 = Cf6NameRandomizer.getWingsSerialTitle(target);
            }
        } else if (kind == "敌人-CF6大刀机器人") {
            var isOphiuchus:Boolean = (Number(target.单位编号) == 482
                || target.单位键 == "cf6.大刀机器人.蛇夫座"
                || target.蛇夫座变体 === true);
            if (isOphiuchus) {
                if (!target.名字 || target.名字 == "大刀机器人") {
                    target.名字 = "星轨特装机·蛇夫";
                }
                if (!target.称号) {
                    target.称号 = "第十三序列·蛇夫座";
                }
                if (target.__ophiuchusBoosted !== true) {
                    target.__ophiuchusBoosted = true;
                    if (!isNaN(target.hp满血值)) {
                        target.hp满血值 = Math.round(target.hp满血值 * 1.25);
                        target.hp = target.hp满血值;
                    }
                    if (!isNaN(target.空手攻击力)) {
                        target.空手攻击力 = Math.round(target.空手攻击力 * 1.15);
                        target.基本空手攻击力 = target.空手攻击力;
                    }
                    if (!isNaN(target.基本防御力)) {
                        target.基本防御力 = Math.round(target.基本防御力 * 1.25);
                        target.防御力 = target.基本防御力 + (isNaN(target.装备防御力) ? 0 : Number(target.装备防御力));
                    }
                    if (!isNaN(target.行走X速度)) {
                        target.行走X速度 = Math.round(target.行走X速度 * 1.15 * 10) / 10;
                        target.行走Y速度 = Math.round(target.行走X速度 * 0.5 * 10) / 10;
                        target.跑X速度 = Math.round(target.行走X速度 * 2 * 10) / 10;
                        target.跑Y速度 = target.行走X速度;
                    }
                }
            } else {
                if (!target.名字 || target.名字 == "大刀机器人") {
                    target.名字 = "星轨斩铁机兵";
                }
                if (!target.称号) {
                    target.称号 = Cf6NameRandomizer.getZodiacTitle(target);
                }
            }
        } else if (kind == "敌人-CF6大头机器人") {
            if (!target.名字 || target.名字 == "大头机器人") {
                target.名字 = "守卫机兵·WAR-I";
            }
            if (target.称号 == "Boss") {
                target.称号 = "M.O.D中枢防卫核心";
            }
        } else if (kind == "敌人-CF6老头人形") {
            if (!target.名字 || target.名字 == "老头") {
                target.名字 = "Bloody";
            }
            if (!target.称号 || target.称号 == "Boss") {
                target.称号 = "C.T组织首脑";
            }
        } else if (kind == "敌人-CF6老头机器人") {
            if (!target.名字 || target.名字 == "老头机器人") {
                target.名字 = "Roll Phantom";
            }
            if (!target.称号 || target.称号 == "Boss") {
                target.称号 = "M.O.D终式决战兵器";
            }
        }
    }

    public static function initialize(target:Object):Void {
        // 表驱动处理逻辑
        var currentTitle:String = target.称号;
        if (_titleHandlers[currentTitle] != undefined) {
            // 执行对应的处理函数
            _titleHandlers[currentTitle](target);
        }

        applyCf6Identity(target);

        if(!target.称号) {
            target.新版人物文字信息.称号文本框.removeMovieClip();
        }

        if(target.新版人物文字信息) {
            target.人物文字信息.unloadMovie();
        }


        refreshName(target, false);
    }

    /** 仅刷新姓名投影，整形不重新随机称号或卸载文字层。 */
    public static function refreshName(target:Object, plainName:Boolean):Void {
        var nameColor:String;
        var shouldBeBold:String;

        // 初始化颜色判断逻辑保持不变

        if(target._name == _root.控制目标)
        {
            nameColor = "#FFFF00";
            shouldBeBold = "";
        }
        else if(target.是否为敌人 == false)
        {
            nameColor = "#00FF00";
            shouldBeBold = "";
        }
        else if(target.是否为敌人 == true)
        {
            nameColor = "#FF2222";
            shouldBeBold = "";
        }
        else
        {
            nameColor = "#FFFFFF";
            shouldBeBold = "<B>";
        }

        var name:String = String(target.名字);
        if (plainName) name = name.split("&").join("&amp;").split("<").join("&lt;").split(">").join("&gt;");
        target.displayName = formatDisplayName("<FONT COLOR='" + nameColor + "'>", target.等级, shouldBeBold, name);
    }
}
