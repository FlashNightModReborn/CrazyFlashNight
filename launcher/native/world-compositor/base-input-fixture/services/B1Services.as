// Explicit capability-limited services installed BEFORE either RSL symbol attaches.
// This file owns candidate lifecycle, never installs production boot/communication.
_root.最大等级 = 60;
_root.等级 = 1; _root.经验值 = 0; _root.杀敌数 = 0;
_root.角色名 = "基地验收角色"; _root.性别 = "男"; _root.身高 = 175;
_root.脸型 = "男变装-基本脸型"; _root.发型 = "光头";
_root.控制目标 = "b1Hero"; _root.关卡标志 = "医务室";
_root.暂停 = false; _root.控制目标全自动 = false; _root.全鼠标控制 = false;
_root.主角被动技能 = {}; _root.宠物信息 = []; _root.同伴数据 = []; _root.佣兵是否出战信息 = [];
_root.佣兵个数限制 = 0; _root.难度等级 = 1; _root.主线任务进度 = 0;
_root.tasks_to_do = []; _root.tasks_finished = []; _root.task_chains_progress = [];
_root.全局健身HP加成 = 0; _root.全局健身MP加成 = 0;
_root.全局健身空攻加成 = 0; _root.全局健身内力加成 = 0; _root.全局健身防御加成 = 0;
_root.上键 = 87; _root.下键 = 83; _root.左键 = 65; _root.右键 = 68;
_root.物品栏 = {装备栏:new org.flashNight.arki.item.itemCollection.EquipmentInventory({})};
_root.敌人函数 = {魔法伤害种类:org.flashNight.arki.component.Damage.MagicDamageTypes.getMagicDamageTypesArray()};
_root.敌人函数.掉落物判定 = b1DenyBusiness;
_root.敌人函数.掉落物品 = b1DenyBusiness;
_root.帧计时器 = {帧率:30, 当前帧数:1,
    eventBus:org.flashNight.neur.Event.EventBus.getInstance(),
    unitUpdateWheel:org.flashNight.neur.ScheduleTimer.UnitUpdateWheel.I(),
    添加任务:b1DenyTask, 添加单次任务:b1DenyTask,
    添加或更新任务:b1DenyTask, 移除任务:b1DenyTask};
_root.玩家信息界面 = {};
_root.玩家信息界面.刷新攻击模式 = function(mode:String):Void { this.攻击模式 = mode; };
_root.UI系统 = {iconBar:{}};
_root.UI系统.iconBar.initialize = function(manager:Object):Void { this.manager = manager; };
_root.UI系统.iconBar.update = function():Void { this.lastProjectionFrame = _root.帧计时器.当前帧数; };
_root.服务器 = {发布服务器消息:b1Log};
_root.发布消息 = b1Log;
_root.server = {sendSocketMessage:b1DenyBusiness, isSocketConnected:false};
_root.soundEffectManager = {playSound:b1DenyBusiness, playBGMWithSource:b1DenyBusiness};
_root.奖励待领取系统 = {投送在线补给包:b1DenyBusiness};
_root.NPC功能菜单 = {刷新显示:b1DenyBusiness};
_root.gameCommands = {};
var b1ForbiddenCommands:Array = ["safeExit","openHelp","openTaskMap","openWebMap","openWebStageSelect","openShop","toggleTablet","toggleSettings","openHairdresser"];
for (var b1ci:Number=0; b1ci<b1ForbiddenCommands.length; b1ci++) _root.gameCommands[b1ForbiddenCommands[b1ci]] = b1DenyBusiness;
var b1ForbiddenRoots:Array = ["GetTask","AddTask","FinishTask","FinishStage","DeleteTask","提交任务完成状态","检测并添加初始任务","修复错位的任务存档","重新加载任务数据","点击npc后检测任务","打开整形手术","加载外部UI","从库中加载外部UI","加载引导界面","请求打开Web选关","切换场景","跳转地图","经验值计算","主角是否升级"];
for (var b1ri:Number=0; b1ri<b1ForbiddenRoots.length; b1ri++) _root[b1ForbiddenRoots[b1ri]] = b1DenyBusiness;
// Scene NPCs retain authored visuals only in this actor milestone. Every interaction
// entry returns an explicit refusal before their onRelease can reach task/shop logic.
_root.初始化NPC = function(npc:MovieClip):Void { npc.__b1InteractionDenied = true; };
_root.是否达成任务检测 = function():Boolean { return false; };
_root.NPCTaskCheck = function():String { return "B1_DENIED"; };
_root.场景转换函数 = {切换场景:b1DenyBusiness, 是否从门加载角色:b1DenyBusiness};
_root.配置场景环境信息 = function():Void { _root.__b1EnvironmentRequested = true; };
StaticInitializer.factory = new AABBColliderFactory(8);
Mover.init();

function b1Log(message):Void { b1LastDiagnostic = String(message); }
function b1DenyTask():Number { b1DeniedTasks++; return -1; }
function b1DenyBusiness():String { b1DeniedBusiness++; return "B1_DENIED"; }
function b1CreateSceneServices(world:MovieClip):Boolean {
    var env:Object = _root.__b1MedicalEnvironment;
    if (world == undefined || env == undefined) return false;
    _root.Xmin = env.Xmin; _root.Xmax = env.Xmax; _root.Ymin = env.Ymin; _root.Ymax = env.Ymax;
    world.背景长 = env.Width; world.背景高 = env.Height;
    world.dispatcher = new LifecycleEventDispatcher(world);
    world.createEmptyMovieClip("地图", -2);
    // Collision remains in source stage coordinates, exactly as real Mover expects.
    _root.createEmptyMovieClip("collisionLayer", 100);
    DepthManager.instance = new DepthManager(world,0,1048575,256);
    if (!DepthManager.instance.calibrate(env.Ymin,env.Ymax)) return false;
    org.flashNight.arki.scene.SceneCollisionManager.getInstance().init();
    org.flashNight.arki.collision.CollisionLayerRenderer.drawBoundary(_root.collisionLayer,
        env.Xmin,env.Xmax,env.Ymin,env.Ymax,300,false);
    org.flashNight.arki.collision.CollisionLayerRenderer.drawPolygons(_root.collisionLayer,env.collisions);
    org.flashNight.arki.scene.SceneCollisionManager.instance.addCollisions(env.collisions);
    world.地图.初始化完毕 = true;
    return true;
}