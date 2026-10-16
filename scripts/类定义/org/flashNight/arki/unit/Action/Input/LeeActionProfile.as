/** Lee 的同源动作、固定技能栏与能力条件；时间轴继续拥有伤害时点。 */
class org.flashNight.arki.unit.Action.Input.LeeActionProfile {
    public static function create(player:Boolean):Object {
        var profile:Object = {
            id:"lee.v2",
            // 原素材没有击倒标签；取消攻击后必须进入真实存在且能收尾的受击时间轴。
            stateFallbacks:{击倒:"被击", 倒地:"被击"},
            actions:{
                basic:{name:"寸拳", icon:"寸拳", state:"空手攻击", label:"", animationFrames:47,
                    description:"沿朝向追身出拳。保留原 Lee 的四处独立出伤与位移上限。",
                    targetKeepDistance:80, maxTravel:300, fallbackTravel:80},
                a1:{name:"截击", icon:"拳脚攻击", state:"近战", label:"a1", animationFrames:48,
                    description:"原 Lee 招式一；按下副攻击键发动。"},
                a2:{name:"连击", icon:"日字冲拳", state:"近战", label:"a2", animationFrames:35,
                    description:"原 Lee 招式二；主攻击键可按住连续使用。"},
                rush:{name:"冲腿·龙息", icon:"兽王崩拳", state:"近战", label:"冲腿", animationFrames:59,
                    promotion:"冲腿龙息", description:"进阶冲腿，保留原冲属性出伤。龙息进阶同时提高空手攻击力。"},
                strongRush:{name:"强力冲腿", icon:"升龙拳", state:"近战", label:"强力冲腿", animationFrames:93,
                    promotion:"冲腿龙息", description:"龙息进阶招式，向前方目标追击；无目标时沿朝向施展。",
                    fallbackTravel:180, minimumSpeedMultiplier:1, maximumSpeedMultiplier:7, trackingFrames:13},
                hop:{name:"小跳", icon:"小跳", state:"小跳", label:"", animationFrames:16, cooldownFrames:30,
                    canInterrupt:true, description:"借用 Lee 原生脱离动作向输入方向移动；没有方向输入时后撤，可打断自身攻击或受击。"}
            },
            quickSlots:["hop", "basic", "rush", "strongRush", "a1", "a2"],
            inputs:[
                {bit:16, actionId:"a2", held:true},
                {bit:32, actionId:"a1", held:false},
                {bit:64, actionId:"rush", held:false},
                {bit:256, actionId:"hop", held:false},
                {bit:512, actionId:"basic", held:false},
                {bit:1024, actionId:"rush", held:false},
                {bit:2048, actionId:"strongRush", held:false},
                {bit:4096, actionId:"a1", held:false},
                {bit:8192, actionId:"a2", held:false}
            ]
        };
        if (player === true) {
            profile.id = "lee.player-cd.v1";
            // 首轮手感试验：普攻约1倍动画，输出技约3倍；小跳按脱离收益单独给下限。
            profile.actions.a1.cooldownFrames = 48;
            profile.actions.a2.cooldownFrames = 105;
            profile.actions.basic.cooldownFrames = 141;
            profile.actions.rush.cooldownFrames = 180;
            profile.actions.strongRush.cooldownFrames = 270;
            profile.actions.hop.cooldownFrames = 75;
            // 玩家技能沿用主角的主动取消能力；AI 的动作准入与锁向仍由原生时间轴决定。
            for (var id:String in profile.actions) {
                profile.actions[id].canInterrupt = true;
                if (id != "hop") profile.actions[id].allowFacingInput = true;
            }
            profile.actions.a1.description = "普通攻击键发动截击，可按住重复并在攻击中转向；冷却1.6秒，取消衔接后仍保留冷却。";
            profile.actions.a2.description = "技能键可直接发动连击；跑动中按普通攻击键也可发动，与技能栏共用3.5秒冷却。";
            profile.actions.basic.description = "追身寸拳，保留原生四处出伤；冷却4.7秒。";
            profile.actions.rush.description = "副攻击键或技能栏发动冲腿·龙息，各段可转向并衔接其他技能；冷却6秒，需要龙息进阶。";
            profile.actions.strongRush.description = "龙息进阶追击，各段可转向，追身沿新朝向移动，可衔接其他技能；冷却9秒，需要龙息进阶。";
            profile.actions.hop.description = "向输入方向小跳，无方向时后撤；可取消攻击或受击，冷却2.5秒。普通形态须手动脱离；龙息进阶后恢复受击自动小跳，不占主动冷却。";
            profile.inputs[0] = {bit:16, actionId:"a1", runningActionId:"a2", held:true};
            profile.inputs[1].actionId = "rush";
        }
        return profile;
    }
}
