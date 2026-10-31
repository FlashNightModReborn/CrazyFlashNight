import org.flashNight.arki.unit.Action.Huofeng.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*;
import org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletCancelQueueProcessor;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.spatial.move.Mover;
import flash.display.BitmapData;
import flash.geom.Matrix;
import org.flashNight.arki.unit.Action.Skill.QuickSkillInputService;

/** Published art, real emitters, native bullet creation/collision/HP settlement.
 * The scene, input and set-transaction scheduler are controlled test fixtures.
 * No inventory, save, coin, host or human-combat acceptance is asserted here.
 */
class org.flashNight.arki.unit.Action.Huofeng.HuofengNativeTest {
    private static var passed:Number,failed:Number,index:Number,age:Number,total:Number;
    private static var world:MovieClip,driver:MovieClip,u:MovieClip;
    private static var runtime:HuofengSetRuntime,chest:Object,hair:HuofengHairRig;
    private static var factory:AABBColliderFactory,cache:Object,targets:Array,items:Array;
    private static var productionShoot:Function,weaponFinish:Function,held:Boolean,ended:Boolean,pausedAt:Number;
    private static var action:Object,pulses:Array,lastPulse:Object,shots:Number,rawTotal:Number,sounds:Array;
    private static var pulseHits:Object,hitCounts:Array,projectiles:Array,returnedAt:Number,pulseAges:Array;
    private static var inputName:String,inputCalls:Number,inputAccepted:Boolean;
    private static var quickBullet:Object;
    private static var nativeWaveCounts:Array;
    private static var kinds:Array=["normal","run","spin","spin","nirvana","nirvana"];
    private static var counts:Array=[30,12,24,48,3,6];
    private static var coldNames:Array=["迅斩","凶斩","瞬步斩","火舞旋风","拔刀术","剑气释放","贯穿突刺","月光斩","蓄力重劈"];
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("HuofengNativeTest FAIL: case="+index+" "+label);}
    }
    public static function runAllTests():Void {
        passed=failed=index=age=total=0;ended=false;items=[];
        _root.暂停=false;_root.是否阴影=false;_root.当前玩家总数=1;_root.控制目标="none";
        _root.帧计时器={当前帧数:0,毫秒每帧:.03,添加冷却任务:function():Void{}};
        _root.装备引用配置={配置装扮:DressupReferenceManager.attach};
        _root.播放音效=function(key:String):Void{if(key.indexOf("火凤_")==0)HuofengNativeTest.sounds.push(key);};
        _root.发布消息=function():Void{};
        _root.按键输入检测=function():Boolean{return false;};
        _root.对象浅拷贝=function(p:Object):Object{var o:Object={};for(var k:String in p)o[k]=p[k];return o;};
        _root.soundEffectManager={playSound:function():Void{}};
        HuofengInput.install();
        HuofengInput.weaponSkillHeld=function():Boolean{return HuofengNativeTest.held;};
        productionShoot=_root.子弹区域shoot传递;
        _root.子弹区域shoot传递=function(p:Object):Void{HuofengNativeTest.capture(p);};
        weaponFinish=_root.兵器攻击路由.动画完毕;
        _root.兵器攻击路由.动画完毕=function(man:MovieClip,unit:MovieClip):Void{
            // Baseline plays all 81 original frames at a fixed position. Input
            // continuation is controlled; the native emitters remain intact.
            if(HuofengNativeTest.index>=27 && man._currentframe<81)return;
            HuofengNativeTest.weaponFinish(man,unit);
        };
        org.flashNight.arki.component.Collider.ColliderFactoryRegistry.init();
        org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine.getInstance();
        var caches:Object=TargetCacheManager;
        caches.acquireEnemyCache=function():Object{return HuofengNativeTest.cache;};
        Mover.init();factory=new AABBColliderFactory(1);
        world=_root.createEmptyMovieClip("__huofengNativeScene",30000);_root.gameworld=world;
        world.createEmptyMovieClip("子弹区域",20000);
        _root.collisionLayer=_root.createEmptyMovieClip("__huofengNativeCollision",30001);
        driver=_root.createEmptyMovieClip("__huofengNativeDriver",30002);
        driver.onEnterFrame=function():Void{if(++HuofengNativeTest.total>5000){HuofengNativeTest.check(false,"watchdog");HuofengNativeTest.finish();}};
        var xml:XML=new XML();xml.ignoreWhite=true;
        xml.onLoad=function(ok:Boolean):Void{HuofengNativeTest.loaded(ok,this);};
        xml.load("../data/items/防具_20-39级.xml");
    }
    private static function loaded(ok:Boolean,xml:XML):Void {
        check(ok,"actual armor XML loaded");if(!ok){finish();return;}
        var rows:Array=XMLParser.configureDataAsArray(XMLParser.parseXMLNode(xml.firstChild).item);
        for(var i:Number=0;i<rows.length;i++)if(rows[i].setId=="huofeng")items.push(rows[i]);
        check(items.length==5,"actual five armor items");if(items.length!=5){finish();return;}
        startCase();
        driver.onEnterFrame=function():Void{
            try{HuofengNativeTest.advance();}
            catch(error){HuofengNativeTest.check(false,"exception "+error);HuofengNativeTest.finish();}
        };
    }
    private static function createUnit():Void {
        _root.是否阴影=(index%2==0);
        u=world.createEmptyMovieClip("actor",20);u.hp=u.hp满血值=1000;u.mp=u.mp满血值=500;
        u.是否为敌人=false;u.version=index+1;u.等级=28;u.攻击模式="空手";u.状态="空手站立";u.方向=(index>=6 && index<12) || index==28?"左":"右";
        u.兵种="主角-男";u.技能等级=10;u.兵器动作类型="刀剑";u.蓄力等级=0;u.方向改变=_root.主角函数.方向改变;
        u.刀口位置生成子弹=org.flashNight.arki.unit.Action.Melee.BladeShootCore.shoot;
        u.攻击时移动=_root.主角函数.攻击时移动;
        u.根据模式重新读取武器加成=function():Void{};
        u._xscale=u.方向=="左"?-100:100;u.myxscale=100;u.性别="女";u.身高=175;u.Z轴坐标=0;
        u.被动技能={刀剑攻击:{启用:true,等级:10}};u.主动战技={};u.syncRefs={};u.生命周期函数列表=[];
        u.装备刀锋利度加成=340;u.伤害加成=115;u.内力=120;u.mp攻击加成=0;u.空手攻击力=999999;
        u.基础伤害类型="物理";u.基础毒=u.基础吸血=u.基础击溃=u.基础斩杀=0;u.基础命中率=100000;u.基础命中加成=0;
        u.动作A=true;u.动作B=false;u.左行=u.右行=u.上行=u.下行=false;u.行走X速度=8;u.跑X速度=16;u.操控编号=-1;
        u.dispatcher=new EventDispatcher();u.enableShoot=true;FireEventComponent.initialize(u);
        u.动画完毕=function():Void{this.状态改变(this.攻击模式+"站立");};
        u.UpdateBigSmallState=u.UpdateSmallState=u.攻击呐喊=function():Void{};
        // Run the production state plan/executor, including retirement of
        // dynamic man paths before attaching a replacement. Only the outer
        // timeline's labelled container placement is supplied by this fixture.
        u.状态改变=_root.主角函数.状态改变;
        u.存储当前飞行状态=u.读取当前飞行状态=function():Void{};
        u.gotoAndStop=function(label:String):Void {
            this.container.removeMovieClip();
            this.createEmptyMovieClip("container",1);this.container._x=3.4;this.container._y=-62.35;
            this.container._xscale=27.7084350585938;this.container._yscale=27.6901245117188;
        };
        u.装载主动战技=_root.主角函数.装载主动战技;
        for(var i:Number=0;i<items.length;i++){
            var item:Object=items[i];u[item.use]={name:item.name,value:{level:1}};u[item.use+"数据"]=item;
            if(item.use=="上装装备")check(Number(item.data.force)==40,"chest force is approved 40");
        }
        u.脸型="女变装-基本脸型";u.发型=undefined;u.面具="HF8/Hair/Front";
        u.身体="女变装-火凤上装身体";u.上臂="女变装-火凤上装上臂";u.左下臂="女变装-火凤上装左下臂";u.右下臂="女变装-火凤上装右下臂";
        u.屁股="女变装-火凤下装屁股";u.左大腿="女变装-火凤下装左大腿";u.右大腿="女变装-火凤下装右大腿";u.小腿="女变装-火凤下装小腿";
        u.左手="女变装-火凤手甲左手";u.右手="女变装-火凤手甲右手";u.脚="女变装-火凤战靴";
        if(index!=16) {
            u.长枪_装扮="枪-长枪-m14";u.手枪_装扮="枪-手枪-MP7";
            u.手枪2_装扮="枪-手枪-UZI";u.刀_装扮="刀-破旧军刀";
        }
        u.createEmptyMovieClip("底层背景",-100);
        hair=new HuofengHairRig(u,HuofengHairProfile.hair(),"HF8/Hair/Front");
        u.buffManager=new BuffManager(u);
        var group:Object={status:"preparing",id:"native",rollbackPlan:{resourceStack:[]},teardownPlan:{resourceStack:[]}};
        var effect:Object={group:group};runtime=HuofengSetRuntime(HuofengSetRuntime.prepare(effect,u));
        check(runtime!=null,"actual item set qualification");
        for(i=0;i<HuofengRules.SLOTS.length;i++){
            var ref:Object={自机:u,装备类型:HuofengRules.SLOTS[i],套装效果记录:effect,套装事务:group,套装上下文:runtime,版本号:u.version};
            runtime.initializeComponent(ref,{});if(i==1)chest=ref;
        }
        group.status="committed";
        check(runtime.isActive(),"five components committed");
        check(HuofengRules.attackUnit(u)==1182.5,"no weapon slot or 999999 punch leakage");
        if(index==16){u.刀属性={power:999999};u.刀_刀口数=99;u.兵器动作类型="双刀";check(HuofengRules.attackUnit(u)==1182.5,"carried blade cannot change P or B");}
    }
    private static function createTargets():Void {
        targets=[];var direction:Number=u.方向=="左"?-1:1;
        for(var i:Number=0;i<6;i++){
            var t:MovieClip=world.createEmptyMovieClip("target"+i,50+i);
            t.probe=i;t._x=(i==3?1000:(i==5?130:(index==23?200:50)))*direction;t._y=0;t.Z轴坐标=i==4?250:0;
            t.hp=t.hp满血值=10000000;t.__hfObservedHp=t.hp;t.防御力=0;t.等级=28;t.躲闪率=0;t.魔法抗性={基础:0,热:0};
            t.dispatcher=new EventDispatcher();t.shield=org.flashNight.arki.component.Shield.AdaptiveShield.acquireDormantFromPool("hfTarget"+i);
            var w:Number=i==0?8:(i==1?16:32);var ar:MovieClip=t.createEmptyMovieClip("area",1);
            ar.beginFill(0);ar.moveTo(-w,-110);ar.lineTo(w,-110);ar.lineTo(w,0);ar.lineTo(-w,0);ar.lineTo(-w,-110);ar.endFill();
            t.aabbCollider=factory.createFromUnitArea(t);targets.push(t);
        }
        var sorted:Array=targets.concat();sorted.sort(function(a:Object,b:Object):Number{return a.aabbCollider.left-b.aabbCollider.left;});
        cache={data:sorted,leftValues:[],rightValues:[],rightMaxValues:[]};var maximum:Number=-100000;
        for(i=0;i<sorted.length;i++){var box:Object=sorted[i].aabbCollider;maximum=Math.max(maximum,box.right);cache.leftValues.push(box.left);cache.rightValues.push(box.right);cache.rightMaxValues.push(maximum);}
    }
    private static function startCase():Void {
        trace("HuofengNativeTest Case: "+index);age=0;pulses=[];pulseAges=[];HuofengPressureTest.beginCase(index);lastPulse=null;shots=rawTotal=0;sounds=[];hitCounts=[0,0,0,0,0,0];projectiles=[];returnedAt=-1;
        _root.暂停=index==0;_root.collisionLayer.clear();createUnit();
        if(index==0){visualContract();_root.暂停=false;createUnit();lifecycleContract();createUnit();reviveContract();}
        createTargets();
        if(index==0){inputContract();scopeSwitchContract();resourceContract();quickSkillContract();sounds=[];}
        if(index==31 || index==32){
            runtime.getState().tier=2;u.createEmptyMovieClip("man",0);
            u.man.__huofengColdSnapshot=HuofengNative.snapshot(u);
            action={frame:0,cancelled:false};
            var wave:Object={发射者:u._name,声音:"",霰弹值:1,子弹散射度:0,发射效果:"",
                子弹种类:"主角满蓄重劈",子弹速度:0,子弹威力:1000,shootX:0,shootY:0,shootZ:0,
                Z轴攻击范围:40,击倒率:10,击中地图效果:"",击中后子弹的效果:""};
            // Launch both versions at the same point in the real Flash frame cycle.
            // The reference owns the timing contract; do not infer a hit count
            // solely from the three authored area keyframes.
            if(index==32)HuofengNative.prepareBullet(u,wave);
            capture(wave);return;
        }
        if(index>=29){
            runtime.getState().tier=index==29?2:1;
            check(runtime.startAttack(false),"held-input cycle starts through production runtime");
            action=runtime.getAction();return;
        }
        if(index>=27){
            runtime.getState().tier=index-26;u.伤害类型="物理";u.兵器伤害类型="物理";
            u.攻击模式="兵器";u.空手攻击力=80;u.刀属性={power:610};u.刀_刀口数=3;u.刀_装扮="刀-破旧军刀";
            action={frame:0,cancelled:false};
            _root.兵器攻击路由.主角普攻连招开始(u);
            u.man.变招判定=function():Void{};
            check(u.man!=undefined && u.man._totalframes==81,"native sword module is the actual 81-frame baseline");
            return;
        }
        if(index>=18){
            runtime.getState().tier=2;
            u.动作A=false;u.刀属性={power:999999};u.刀_刀口数=99;
            action={frame:0,cancelled:false};
            if(index<23)_root.技能路由.技能标签跳转_旧(u,coldNames[index-18]);
            else _root.兵器攻击路由.兵器攻击标签跳转(u,coldNames[index-18]);
            check(u.man.__huofengColdSnapshot.power==610,"cold action uses owned P snapshot "+coldNames[index-18]);
            check(u.man.刀.刀.装扮!=undefined,"cold action has its own chain mount");
            runtime.getState().tier=2;
            return;
        }
        var slot:Number=index<12?index%6:(index==15?1:0);held=slot==3;
        if(index==15){var wall:MovieClip=_root.collisionLayer;wall.beginFill(0);wall.moveTo(60,-500);wall.lineTo(72,-500);wall.lineTo(72,500);wall.lineTo(60,500);wall.lineTo(60,-500);wall.endFill();}
        if(slot>=4){runtime.getState().tier=slot-3;runtime.beginNirvana(slot-3);}
        else if(slot>=2)check(runtime.startSpin(),"spin accepted");
        else check(runtime.startAttack(slot==1),"primary accepted");
        if(index==2 || index==6)runtime.getState().tier=1;
        if(index==3 || index==7)runtime.getState().tier=2;
        action=runtime.getAction();check(action!=null && u.man!=undefined,"real native container attached");
        if(!action || !u.man){finish();return;}
    }
    private static function capture(p:Object):Void {
        shots++;
        if(index>=18)trace("HuofengNativeTest Shot: case="+index+" age="+age+" frame="+u.man._currentframe+" kind="+p.子弹种类+" P="+p.子弹威力+" xy="+p.shootX+","+p.shootY);
        if(index>=18)check(isFinite(p.子弹威力) && p.子弹威力>0 && p.子弹威力<100000,"cold power finite and excludes carried 999999 punch/blade");
        var hasPulse:Boolean=p.__huofengPulse.seen!=undefined;
        if(!hasPulse || p.__huofengPulse!==lastPulse){
            lastPulse=p.__huofengPulse;pulses.push(action.frame);pulseAges.push(age);rawTotal+=p.子弹威力;pulseHits={};
            if(action.kind==="normal"){
                check(p.水平击退速度==(action.frame==70?8:2),"native pulse retains light push until final contact at frame 70");
                check(p.击倒率==(action.stage==4?1:10),"native normal/finisher impact matches the cold-weapon baseline");
            }
        }
        var before:Array=[];for(var i:Number=0;i<targets.length;i++)before.push(targets[i].hp);
        var bullet:Object=productionShoot(p);
        if((runtime.getTier()==2 && action.kind!=="nirvana" && index<27) || index==29) {
            check(bullet.伤害类型=="魔法" && bullet.魔法伤害属性=="热",
                "actual native projectile retains pure heat conversion without old extra heat");
        }
        if(runtime.getTier()==1 && action.kind!=="nirvana" && index<27) {
            check(bullet.伤害类型==="破击" && bullet.魔法伤害属性==="热","native first-tier hammer uses standard heat crush");
        }
        if(index==27 || index==28) check(bullet.伤害类型==="物理","native real sword stays physical after either Nirvana tier");
        var melee:Boolean=p.子弹种类.indexOf("近战")>=0;
        check(bullet!=undefined,"native bullet exists: "+p.子弹种类);
        if(melee)check(bullet.aabbCollider.right>bullet.aabbCollider.left,"native melee bullet has nonempty area");
        else if(bullet!=undefined)projectiles.push(bullet);
        BulletQueueProcessor.processQueue();
        for(i=0;i<targets.length;i++)if(targets[i].hp<before[i]){
            if(hasPulse)check(pulseHits[i]!==true,"a spatial sample cannot charge the same pulse twice for target "+i);
            pulseHits[i]=true;hitCounts[i]++;targets[i].__hfObservedHp=targets[i].hp;
            if(i==0) HuofengPressureTest.contact(action.kind,bullet,targets[i].损伤值,check);
        }
    }
    private static function resourceContract():Void {
        var skill:Object=u.主动战技.空手;
        check(skill.消耗mp==36 && skill.描述.indexOf("48MP")>=0,"real skill loader exposes first-loop and held-loop cost");
        var service:Object=org.flashNight.arki.skill.SkillResourceService;
        var selected=_root.控制目标;_root.控制目标=u._name;
        u.mp=35;
        check(service.weapon(u,skill,{}).state=="blocked","normal HUD resource projection detects insufficient spin MP");
        check(org.flashNight.arki.unit.Action.Skill.WeaponSkillInputService.canTriggerUnit(u,true),"insufficient MP reaches the ordinary release rejection");
        service.begin(u,"weapon",0);
        check(_root.主角函数.释放主动战技.apply(u)===false,"real spin release rejects 35 MP");
        service.finish(u);
        check(u.__skillResourceNotice.reason=="mp" && u.__skillResourceNotice.kind=="weapon","real rejection publishes standard weapon feedback");
        check(u.mp==35 && runtime.getState().spinReadyFrame==0 && runtime.getAction()==null,"denied spin spends no MP or cooldown");
        u.mp=36;check(service.weapon(u,skill,{}).state=="last" && runtime.canSpin(),"36 MP is the last affordable first loop");
        u.mp=72;check(service.weapon(u,skill,{}).state=="ready","72 MP is ready in the shared HUD");
        u.mp=500;delete u.__skillResourceNotice;_root.控制目标=selected;
    }
    private static function quickSkillContract():Void {
        var shoot:Function=_root.子弹区域shoot传递;
        _root.子弹区域shoot传递=function(b:Object):Void{HuofengNativeTest.quickBullet=b;};
        var man:MovieClip=u.createEmptyMovieClip("man",0);man.createEmptyMovieClip("攻击点",1);
        u.刀属性={power:100,skillmultipliers:{龙斩:2}};u.空手攻击力=80;
        u.兵器伤害类型="魔法";u.兵器魔法伤害属性="冰";
        var names:Array=["龙斩刀伤","六连攻击"];
        for(var tier:Number=1;tier<=2;tier++) {
            runtime.getState().tier=tier;
            for(var i:Number=0;i<names.length;i++) {
                quickBullet=null;var fn:Function=_root.技能函数[names[i]];fn.apply(man,[40]);
                check(quickBullet.子弹威力==(i==0?2628:1188),"quick skill keeps actual receiver and original weapon/punch formula "+names[i]+"/"+tier);
                check(quickBullet.伤害类型=="魔法" && quickBullet.魔法伤害属性=="冰" && quickBullet.__huofengPulse==undefined,
                    "ordinary quick skill never borrows meteor hammer conversion "+names[i]+"/"+tier);
            }
        }
        runtime.getState().tier=0;u.空手攻击力=999999;
        delete u.刀属性;delete u.兵器伤害类型;delete u.兵器魔法伤害属性;
        man.removeMovieClip();_root.子弹区域shoot传递=shoot;
    }
    private static function observeNativeContacts():Void {
        for(var i:Number=0;i<targets.length;i++) {
            if(targets[i].hp<targets[i].__hfObservedHp)hitCounts[i]++;
            targets[i].__hfObservedHp=targets[i].hp;
        }
    }
    private static function inputContract():Void {
        var selected=_root.控制目标;_root.控制目标=u._name;
        var release:Function=QuickSkillInputService.releaseBySkillName;
        QuickSkillInputService.releaseBySkillName=function(unit:Object,name:String,key:Number):Object{
            HuofengNativeTest.inputName=name;HuofengNativeTest.inputCalls++;
            return {released:HuofengNativeTest.inputAccepted};
        };
        inputAccepted=true;inputCalls=0;
        var names:Array=["迅斩","瞬步斩","凶斩","火舞旋风","拔刀术"];
        for(var direction:Number=0;direction<2;direction++)for(var i:Number=0;i<5;i++){
            u.方向=direction==0?"右":"左";u.动作B=true;u.动作A=false;
            u.上行=i==0;u.下行=i==2 || i==3;u.按住奔跑键=i==4;
            u.右行=direction==0 && (i==1 || i==3 || i==4);u.左行=direction==1 && (i==1 || i==3 || i==4);
            delete u.__黑猫技能B已消费;u.当前搓招名=i==4?"瞬步斩":"";u.搓招缓冲名="";u.搓招缓冲已消费=true;
            var result:Number=_root.技能函数.冷兵器主动技能搓招(u,6,30,false);
            check(result==2 && inputName==names[i],"cold directional input including Shift priority "+direction+"/"+names[i]);
            check(!u.动作B && !u.左行 && !u.右行,"successful cold command yields this frame's local inputs");
        }
        u.按住奔跑键=false;u.上行=u.下行=u.左行=u.右行=false;u.动作B=false;
        u.当前搓招名="";u.搓招缓冲名="迅斩";u.搓招缓冲帧=Number(_root.帧计时器.当前帧数)-30;u.搓招缓冲已消费=false;
        check(_root.技能函数.冷兵器主动技能搓招(u,6,30,false)==1 && inputName=="迅斩","released key retains thirty-frame preinput");
        u.搓招缓冲名="迅斩";u.搓招缓冲帧=Number(_root.帧计时器.当前帧数)-31;u.搓招缓冲已消费=false;
        check(_root.技能函数.冷兵器主动技能搓招(u,6,30,false)==0,"expired preinput does not release");
        u.动作B=true;u.上行=true;inputAccepted=false;inputCalls=0;
        check(_root.技能函数.冷兵器主动技能搓招(u,6,30,false)==-1,"rejected release consumes B without jumping");
        check(_root.技能函数.冷兵器主动技能搓招(u,6,30,false)==-1 && inputCalls==1,"held rejected input never retries release");
        u.动作B=false;u.上行=false;_root.技能函数.冷兵器主动技能搓招(u,6,30,false);
        check(u.__黑猫技能B已消费==undefined,"release of B rearms the consumer");
        QuickSkillInputService.releaseBySkillName=release;
        var route:Function=_root.兵器攻击路由.兵器攻击标签跳转;
        _root.兵器攻击路由.兵器攻击标签跳转=function(unit:Object,name:String):Void{HuofengNativeTest.inputName=name;};
        var man:MovieClip=u.createEmptyMovieClip("man",0);
        var passives:Array=["剑气释放","贯穿突刺","月光斩","蓄力重劈"];
        for(i=0;i<4;i++){
            var name:String=passives[i];u.被动技能[name]={启用:true,等级:1};u.当前搓招名=name;inputName="";
            var handler:Function=_root.技能函数["使用"+name];
            check(handler.apply(man)>0 && inputName==name,"learned passive resolves actual receiver "+name);
            u.被动技能[name].启用=false;inputName="";
            check(handler.apply(man)==0 && inputName=="","unlearned passive stays unavailable "+name);
            delete u.被动技能[name];
        }
        _root.兵器攻击路由.兵器攻击标签跳转=route;man.removeMovieClip();
        check(!HuofengInput.allowedPassive("双剑气") && !HuofengInput.allowedPassive("疾影剑气"),"dual-blade derivations remain outside the profile");
        _root.控制目标=selected;u.方向="右";u.动作A=true;u.动作B=false;u.当前搓招名="";u.搓招缓冲名="";
        delete u.__weaponSameFrameJump;delete u.__黑猫技能B已消费;
    }
    /** Real AVM1 clips and published skins; paused equip is separate from action playback. */
    private static function visualPlacement(label:String):Void {
        var skirt:MovieClip=u.底层背景.__huofengSkirt;
        check(skirt!=undefined && skirt._visible,label+" visible");
        var samples:Array=[{x:0,y:0},{x:100,y:0},{x:0,y:100}];
        for(var i:Number=0;i<samples.length;i++) {
            var a:Object={x:samples[i].x,y:samples[i].y};
            var b:Object={x:samples[i].x,y:samples[i].y};
            u.屁股_引用.localToGlobal(a);skirt.localToGlobal(b);
            check(Math.abs(a.x-b.x)<0.2 && Math.abs(a.y-b.y)<0.2,label+" native basis "+i);
        }
        var bounds:Object=skirt.getBounds(u);
        check(bounds.yMax-bounds.yMin<200,label+" player-sized skirt");
        trace("HuofengNativeTest Visual: "+label+" matrix="+skirt.transform.matrix+" bounds="+bounds.xMin+","+bounds.yMin+","+bounds.xMax+","+bounds.yMax);
    }
    /** Real actor/man replacement, with only the run authority and scene
     * scheduler controlled. No coin or save transaction is performed. */
    private static var reviveRun:Object;
    private static function reviveContract():Void {
        var api:Object=org.flashNight.arki.scene.StageRunSession;
        var authority:Function=api.getReviveAuthority;
        var selected:String=_root.控制目标;
        var transitioning=_root.场景转换中;
        reviveRun={runId:"native-map-scope"};
        api.getReviveAuthority=function():Object{return HuofengNativeTest.reviveRun;};
        _root.控制目标=u._name;_root.暂停=false;
        u.version++;
        _root.装备生命周期函数.火凤组件周期(chest);
        check(runtime.isActive() && chest.版本号==u.version,"production equipment callback survives weapon version update");
        HuofengRunState.notifyPaidRevive(reviveRun,u,true,1);
        var state:Object=reviveRun.huofeng;
        check(state.tier==1 && state.pendingNirvanaTier==1 && runtime.getAction()==null,"paid receipt queues instead of replacing respawn body inline");
        _root.场景转换中=true;runtime.tick(chest);
        check(runtime.getAction()==null,"scene transition retains pending presentation");
        runtime.dispose();hair.dispose();u.buffManager.destroy();u.removeMovieClip();
        createUnit();
        u.__resourceSpawn={resourcesReady:false};_root.场景转换中=false;
        runtime.tick(chest);check(runtime.getAction()==null && state.pendingNirvanaTier==1,"same-map replacement actor waits for resources");
        u.__resourceSpawn.resourcesReady=true;_root.暂停=true;
        runtime.tick(chest);check(runtime.getAction()==null,"paused respawn retains receipt");
        _root.暂停=false;runtime.tick(chest);
        var a:Object=runtime.getAction();
        check(a.kind==="nirvana" && a.tier==1 && u.man._totalframes==92,"new scene actor attaches ordinary native Nirvana");
        check(state.pendingNirvanaTier==1,"attachment alone does not consume presentation");
        u.状态改变("空手站立");runtime.tick(chest);
        check(runtime.getAction().kind==="nirvana","same-tick body replacement retries unshown presentation");
        _root.帧计时器.当前帧数++;HuofengAction.tick(u.man);
        check(state.presentedReviveSequence==1 && state.pendingNirvanaTier==0,"first live action frame consumes receipt once");
        runtime.cancelAction(true);
        for(var sequence:Number=2;sequence<=4;sequence++) {
            _root.帧计时器.当前帧数++;
            HuofengRunState.notifyPaidRevive(reviveRun,u,true,sequence);runtime.tick(chest);
            trace("HuofengNativeTest PaidState: seq="+sequence+" tier="+state.tier+" last="+state.lastPaidSequence+" pending="+state.pendingNirvanaTier+" receipt="+state.pendingReviveSequence+" shown="+state.presentedReviveSequence+" action="+runtime.getAction().tier+" frames="+u.man._totalframes+" hp="+u.hp+" max="+u.hp满血值);
            check(runtime.getAction().tier==2 && u.man._totalframes==113,"paid revive "+sequence+" uses full native animation");
            var oldUnload:Function=u.man.onUnload;
            _root.帧计时器.当前帧数++;HuofengAction.tick(u.man);runtime.cancelAction(true);
            trace("HuofengNativeTest PaidShown: seq="+sequence+" shown="+state.presentedReviveSequence+" pending="+state.pendingNirvanaTier+" hpMax="+u.hp满血值);
            check(state.tier==2 && state.presentedReviveSequence==sequence && u.hp满血值==500,"paid revive "+sequence+" preserves capped contract");
        }
        HuofengRunState.notifyPaidRevive(reviveRun,u,true,4);runtime.tick(chest);
        check(runtime.getAction()==null && state.pendingNirvanaTier==0,"duplicate transaction never replays full animation");
        runtime.beginNirvana(2);
        var current:Object=runtime.getAction();
        oldUnload.call(u.man);
        check(runtime.getAction()===current && !current.cancelled,"late old-man unload cannot cancel replacement action");
        runtime.cancelAction(true);
        HuofengPresentationTest.mapReset(u,runtime,chest,reviveRun,world,check);
        trace("HuofengNativeTest Revive: same-map replacements, map reset, old-map receipt rejection and new-map paid tier one checked");
        runtime.dispose();hair.dispose();u.buffManager.destroy();u.removeMovieClip();
        api.getReviveAuthority=authority;_root.控制目标=selected;_root.场景转换中=transitioning;reviveRun=null;
        createUnit();
    }
    private static function lifecycleContract():Void {
        check(u.底层背景.getDepth()<0 && u.container==undefined,"fixture models a fresh actor with no high dynamic attachments");
        var visual:MovieClip=u.__huofengVisual;
        var visualToken:Object=visual.__huofengVisualToken;
        var hip:MovieClip=u.createEmptyMovieClip("standingHip",-99);
        hip._xscale=hip._yscale=27.7;
        DressupReferenceManager.doConfig(hip,u.屁股,"装扮","屁股_引用",u);
        runtime.tick(chest);check(u.底层背景.__huofengSkirt._visible,"standing skirt is visible before attack");
        runtime.getState().tier=2;
        check(runtime.startAttack(false),"low-depth actor starts native action");
        check(!u.底层背景.__huofengSkirt._visible,"action start hides standing skirt before maintenance");
        _root.帧计时器.当前帧数++;HuofengAction.tick(u.man);runtime.tick(chest);
        check(u.__huofengVisual.__huofengVisualToken===visualToken,"dynamic man must not overwrite equipment presentation");
        var savedEmitter:Function=_root.子弹区域shoot传递;
        _root.子弹区域shoot传递=function():Void{};
        // Windup is intentionally quiet; run to the first real strike.
        for(var step:Number=2;step<=8;step++) {_root.帧计时器.当前帧数++;HuofengAction.tick(u.man);runtime.tick(chest);}
        _root.子弹区域shoot传递=savedEmitter;
        check(flameCount()>0,"real depth layout retains post-revive strike burst");
        check(!u.底层背景.__huofengSkirt._visible,"authored action hides external standing skirt");
        var visualDepth:Number=u.__huofengVisual.getDepth();u.__huofengVisual.removeMovieClip();
        var foreign:MovieClip=u.createEmptyMovieClip("foreignEffect",visualDepth);foreign.owner={};
        runtime.tick(chest);
        check(u.__huofengVisual.__huofengVisualToken===visualToken && flameCount()>0,
            "lost presentation rebuilds and restores flame on the same frame");
        check(foreign._parent===u && foreign.owner!=undefined,"presentation recovery preserves unrelated replacement");
        var dyingAction:Object=runtime.getAction();var delayedUnload:Function=u.man.onUnload;
        u.hp=0;runtime.tick(chest);
        check(dyingAction.cancelled && runtime.getAction()==null,"death cancels the action token");
        check(u.man.__huofengAction!==dyingAction || !u.man._visible,"death cannot leave a visible frozen action body");
        check(!u.底层背景.__huofengSkirt._visible && !u.__huofengVisual._visible,"same-frame death hides all presentation");
        u.hp=500;runtime.beginNirvana(2);var replacement:Object=runtime.getAction();
        delayedUnload();check(runtime.getAction()===replacement && !replacement.cancelled,"late death unload preserves revived body");
        _root.帧计时器.当前帧数++;HuofengAction.tick(u.man);runtime.tick(chest);
        check(!u.底层背景.__huofengSkirt._visible,"revival has no duplicate ground skirt");
        runtime.cancelAction(true);
        _root.技能路由.技能标签跳转_旧(u,"凶斩");
        var cold:Object=u.man.__huofengColdSnapshot;check(cold!=null,"death regression attaches real cold action");
        var corpse:MovieClip=u.createEmptyMovieClip("man",-98);corpse.corpseToken={};corpse._visible=true;
        u.hp=0;runtime.tick(chest);
        var leftover:MovieClip=u.getInstanceAtDepth(0);
        check(cold.token.cancelled && (leftover.__huofengColdSnapshot!==cold || !leftover._visible),"cold skill death retires its owned body under a same-name corpse");
        check(corpse._visible && corpse.corpseToken!=undefined,"death cleanup preserves the replacement corpse");
        runtime.dispose();hair.dispose();u.buffManager.destroy();u.removeMovieClip();
    }
    private static function hairCount():Number {
        var result:Number=0;
        for(var key:String in u.底层背景) if(u.底层背景[key].__hf8Token!=undefined)result++;
        return result;
    }
    private static function hairReferenceContract():Void {
        // Exercise the actual authored head after its native load scripts have
        // run, rather than assuming attachMovie executes every child instantly.
        var man:MovieClip=u.man;var owned:MovieClip=u.面具_引用;
        var savedHp:Number=u.hp;var savedName:String=man._name;
        hair.update(1000);
        check(owned.__hf8HairIdentity!=undefined && hairCount()==2,"real head binds rear hair");
        var foreign:MovieClip=world.createEmptyMovieClip("foreignHead",90);foreign.__hf8HairIdentity={};
        u.面具_引用=foreign;hair.update(1010);
        check(hairCount()==0,"foreign head cannot leave giant detached hair");
        u.面具_引用=owned;hair.update(1020);check(hairCount()==2,"returning owned head restores hair");
        u.hp=0;hair.update(1030);check(hairCount()==2,"valid corpse head retains its own hair");u.hp=savedHp;
        man._name="__retiredManHairFixture";hair.update(1040);
        check(hairCount()==0,"retired body references cannot drive rear hair");
        man._name=savedName;
        // Unit-level reference resolves again after restoring the native path.
        u.面具_引用=owned;foreign.removeMovieClip();hair.update(1050);
        check(hairCount()==2,"live action rebinds after retired reference is cleared");
    }
    private static function visualContract():Void {
        var skirt:MovieClip=u.底层背景.__huofengSkirt;
        check(skirt!=undefined,"published rear skirt attaches");
        check(!skirt._visible,"paused equip hides raw unpositioned skirt before first maintenance");
        check(!u.__huofengVisual._visible,"paused equip hides raw ember layer");
        runtime.tick(chest);
        check(!skirt._visible,"paused missing hip stays hidden");
        var man:MovieClip=u.createEmptyMovieClip("man",1);
        man._x=3.4;man._y=-62.35;man._xscale=27.7084350585938;man._yscale=27.6901245117188;
        var hip:MovieClip=man.createEmptyMovieClip("hip",1);
        hip.transform.matrix=new Matrix(0.95,0.08,-0.06,1.02,13,180);
        DressupReferenceManager.doConfig(hip,u.屁股,"装扮","屁股_引用",u);
        var anchor:MovieClip=u.屁股_引用;
        check(anchor!=undefined,"real lower-armor skin loads");
        runtime.tick(chest);visualPlacement("paused-first-pose");
        check(u.__huofengVisual.ember==undefined,"tier zero creates no ember timeline");
        var hp:Number=u.hp;var mp:Number=u.mp;var frame:Number=u.__huofengVisual.ember._currentframe;
        hip._x+=27;hip._rotation=-13;runtime.tick(chest);visualPlacement("paused-same-frame-pose-change");
        u._xscale=-100;u.底层背景._xscale=125;u.底层背景._yscale=73;u.底层背景._rotation=11;
        runtime.tick(chest);visualPlacement("paused-left-transformed-background");
        check(u.hp==hp && u.mp==mp && u.__huofengVisual.ember._currentframe==frame,"paused pose sync advances no resources or ember clock");
        world._x=173;world._y=-281;world._xscale=136;world._yscale=92;
        u._x=647;u._y=389;
        runtime.tick(chest);visualPlacement("translated-camera-and-actor");
        u.攻击模式="长枪";u.状态="长枪攻击";
        runtime.tick(chest);visualPlacement("translated-rifle-pose");
        var started:Number=getTimer();
        for(var batch:Number=0;batch<2000;batch++) runtime.tick(chest);
        trace("HuofengNativeTest Perf: idle-maintenance-2000 ms="+(getTimer()-started));
        started=getTimer();
        for(batch=0;batch<2000;batch++){hip._rotation=batch%21-10;runtime.tick(chest);}
        trace("HuofengNativeTest Perf: changing-pose-2000 ms="+(getTimer()-started));
        world._x=world._y=u._x=u._y=0;world._xscale=world._yscale=100;
        u.攻击模式="空手";u.状态="空手站立";

        var lower:MovieClip=u.createEmptyMovieClip("movingGunLegs",2);
        lower.transform.matrix=man.transform.matrix;
        var split:MovieClip=lower.createEmptyMovieClip("hip",1);split.transform.matrix=hip.transform.matrix;
        DressupReferenceManager.doConfig(split,u.屁股,"装扮","屁股_引用",u);
        runtime.tick(chest);visualPlacement("split-moving-gun-lower-body");
        lower.removeMovieClip();u.屁股_引用=anchor;
        u.version++;_root.装备生命周期函数.火凤组件周期(chest);
        check(runtime.isActive(),"weapon-only version update retains skirt maintenance");
        u.dressupRefreshing=true;runtime.tick(chest);check(!skirt._visible,"refresh hides old pose");
        u.dressupRefreshing=false;delete u.屁股_引用;runtime.tick(chest);check(!skirt._visible,"missing hip hides old pose");
        u.屁股_引用=world.createEmptyMovieClip("foreignHip",80);runtime.tick(chest);
        check(!skirt._visible,"foreign hip cannot position owned skirt");world.foreignHip.removeMovieClip();
        u.屁股_引用=anchor;man._xscale=0;runtime.tick(chest);check(!skirt._visible,"degenerate hip stays hidden");
        man._xscale=27.7084350585938;runtime.tick(chest);visualPlacement("paused-pose-recovered");
        u.底层背景.removeMovieClip();u.createEmptyMovieClip("底层背景",100);u.底层背景.swapDepths(-100);
        runtime.tick(chest);visualPlacement("paused-background-recreated");
        u.hp=0;runtime.tick(chest);check(!u.底层背景.__huofengSkirt._visible && !u.__huofengVisual._visible,"death hides owned presentation");
        u.hp=hp;runtime.tick(chest);visualPlacement("paused-alive-again");
        runtime.dispose();check(u.底层背景.__huofengSkirt==undefined && u.__huofengVisual==undefined,"unequip removes presentation");
        hair.dispose();u.buffManager.destroy();u.removeMovieClip();
    }
    private static function advance():Void {
        if(ended)return;if(++total>5000){check(false,"watchdog");finish();return;}
        age++;_root.帧计时器.当前帧数++;
        runtime.tick(chest);hair.update();
        if(index==0 && age==4)hairReferenceContract();
        if(index<12 && (age==4 || age==18 || age==46 || age==68 || age==80)) {HuofengPresentationTest.carry(u,index,check);captureImage();}
        if(index==16 && age==4) HuofengPresentationTest.carry(u,index,check);
        if(index==27 || index==28) {
            check(flameCount()==0,"real sword never emits the mace-only attack flames");
            if(age==18)captureImage();
        }
        if(index==31 || index==32) {
            action.frame=age;BulletQueueProcessor.processQueue();observeNativeContacts();
            if(age<20)return;
            if(index==31) {
                nativeWaveCounts=hitCounts.concat();
                check(nativeWaveCounts[0]>1 && nativeWaveCounts[1]>1 && nativeWaveCounts[2]>1,"unmodified full-charge reference makes multiple real contacts");
            } else {
                for(var waveIndex:Number=0;waveIndex<targets.length;waveIndex++)
                    check(hitCounts[waveIndex]==nativeWaveCounts[waveIndex],"adapted full-charge retains each native target's contact count "+waveIndex+": "+hitCounts[waveIndex]+"/"+nativeWaveCounts[waveIndex]);
            }
            trace("HuofengNativeTest MultiHit: full-charge="+hitCounts+" adapted="+(index==32));
            cleanup();if(++index==32)startCase();else finish();return;
        }
        if(index>=29) {
            if(index==30 && age==4) u.动作A=false;
            if(index==29) {
                if(age==60) u.__testFlameCapacity=u.__huofengVisual.getNextHighestDepth();
                if(age>=71 && age<=78) {HuofengPresentationTest.carry(u,index,check);captureImage();}
                if(pulses.length>=60) u.动作A=false;
                if(!action.cancelled) check(runtime.getAction()===action && u.man.__huofengAction===action,"held chain keeps one body and ownership token");
            }
            if(!action.cancelled && age<230) return;
            check(pulses.length==(index==29?60:5),"holding repeats sixty contacts; early release stops after five");
            check(age==(index==29?169:27),"two true chained cycles end at 169; early release ends at 27");
            check(runtime.getAction()==null,"completed cycle returns control");
            if(index==29) {
                check(pulseAges[30]-pulseAges[29]==12,"held fifth-to-first real contact gap is twelve frames");
                check(action.cycle==1,"second cycle starts internally with no idle restart");
                check(hitCounts[0]==60 && hitCounts[1]==60 && hitCounts[2]==60,"both cycles hit narrow/medium/wide targets exactly sixty times");
                check(sounds.length==24,"both cycles replay all six chain/swing sound pairs");
                check(u.__huofengVisual.getNextHighestDepth()==u.__testFlameCapacity && u.__testFlameCapacity<=17,"second full cycle reuses the bounded sixteen-clip flame pool");
                trace("HuofengNativeTest ChainGap: last="+pulseAges[29]+" next="+pulseAges[30]+" gap="+(pulseAges[30]-pulseAges[29]));
            }
            trace("HuofengNativeTest Hold: case="+index+" age="+age+" contacts="+pulses.length);
            cleanup();if(++index>=33)finish();else startCase();return;
        }
        if(index>=18){
            action.frame=age;
            if(index<27 && (age==4 || age==18 || age==32) && u.man.__huofengColdSnapshot!=undefined && u.man.刀.刀.装扮!=undefined) {
                verifyColdMount();captureImage();
            }
            BulletQueueProcessor.processQueue();observeNativeContacts();
            if(returnedAt<0 && (index>=27 ? u.man==undefined : u.man.__huofengColdSnapshot==undefined))returnedAt=age;
            // Let real moving projectiles advance after the actor recovers.
            if((returnedAt<0 || age<returnedAt+20) && age<320)return;
            var name:String=index>=27?"刀剑五段基准":coldNames[index-18];
            check(returnedAt>0 && age<320,"native action returns control "+name);
            check(shots>0,"native action invokes real bullet pipeline "+name);
            var damageList:Array=[];var totalDamage:Number=0;
            for(var j:Number=0;j<3;j++){damageList.push(10000000-targets[j].hp);totalDamage+=10000000-targets[j].hp;}
            check(totalDamage>0 && isFinite(totalDamage),"native action reaches actual targets "+name);
            if(index==21) {
                check(hitCounts[0]==4 && hitCounts[1]==4 && hitCounts[2]==4,"real whirlwind retains all four native collision windows: "+hitCounts);
                trace("HuofengNativeTest MultiHit: whirlwind="+hitCounts);
            }
            if(index>=27)check(shots>=30 && shots%3==0,"sword completes all native emission windows with three nodes");
            trace("HuofengNativeTest Cold: "+name+" frames="+returnedAt+" shots="+shots+" raw="+rawTotal+" HP="+damageList+" x="+u._x);
            cleanup();if(++index>=33)finish();else startCase();return;
        }
        if(age==4){
            check(u.面具_引用.__hf8HairIdentity!=undefined && hair.bindCount>0,"R9 front and back bound to actual head");
            var image:BitmapData=new BitmapData(500,600,true,0);image.draw(u,new Matrix(1,0,0,1,250,420));
            var bounds=image.getColorBoundsRect(0xFF000000,0,false);check(bounds.width>20 && bounds.height>50,"native dressed actor rasterizes");image.dispose();
        }
        if(age==18 && (index==2 || index==3 || index==6 || index==7)) {
            check(flameCount()>=4,"strike has overlapping native fire and ring bursts");
            var fb:Object=u.__huofengVisual.getBounds(u);
            trace("HuofengNativeTest Flame: case="+index+" active="+flameCount()+" bounds="+fb.xMin+","+fb.yMin+","+fb.xMax+","+fb.yMax);
            check(fb.xMax-fb.xMin>150 && fb.yMax-fb.yMin>100,"Boss-scale flame covers the strike area");
            if(index==2) cancellationContract();
        }
        if(age==4) {
            check(u.man.hfShadow!=undefined && u.shadow===u.man.hfShadow,"native action installs the standard ground shadow hook");
            check(u.man.hfShadow._visible===(_root.是否阴影==true),"ground shadow respects the global setting");
            var shadowBounds:Object=u.man.hfShadow.getBounds(u);
            check(shadowBounds.xMax-shadowBounds.xMin>50 && shadowBounds.xMax-shadowBounds.xMin<80
                && Math.abs((shadowBounds.yMax+shadowBounds.yMin)*0.5)<5,"shadow remains at the unit ground plane");
        }
        if((index==12 || index==15 || index==2 || index==4) && age==2) verifyControls();
        if(index==12 && age==10){_root.暂停=true;pausedAt=action.frame;}
        if(index==12 && age==18){check(action.frame==pausedAt,"pause freezes real action callback");_root.暂停=false;}
        if(index==13 && age==5)u.状态改变("空手被击");
        if(index==14 && age==5)runtime.dispose();
        if(index==17 && age==5)u.攻击模式="长枪";
        if(action.kind==="normal" && pulses.length>=30) u.动作A=false;
        if(!action.cancelled && age<180)return;
        check(action.cancelled,"action relinquishes control");
        var slot:Number=index<12?index%6:(index==15?1:0);
        var interrupted:Boolean=index==13 || index==14 || index==17;
        check(pulses.length==(interrupted?0:counts[slot]),"exact contact pulse count got="+pulses.length);
        if(slot==0 && !interrupted)check(hitCounts[0]==30 && hitCounts[1]==30 && hitCounts[2]==30,"all thirty contacts reach narrow, medium and wide forward targets");
        check(shots==pulses.length*(slot>=4?1:3),"three samples share each primary pulse");
        var damages:Array=[];
        for(var i:Number=0;i<targets.length;i++){
            var damage:Number=10000000-targets[i].hp;damages.push(damage);
            check(isFinite(damage) && damage>=0,"finite settled target HP");
            // Native damage has its own random fluctuation. Pulse deduplication
            // is proved above by observing each target before/after each sample.
            if(i<3 && !interrupted)check((damage>0 || index==15) && damage<=rawTotal*1.2*(runtime.getTier()==1 && slot<4 ? 1.1 : 1)+10,"bounded native damage "+i+"="+damage+" budget="+rawTotal);
            if(i==3 || i==4 || interrupted)check(damage==0,"out of range/depth or cancelled attack is inert "+i);
            if(slot>=4 && i==5)check(damage==0,"large body beyond blast radius is rejected");
            if(slot<4 && i==5 && !interrupted && index!=15)check(damage>0,"full chain reaches the target outside the former 110-pixel limit");
        }
        if(slot>=4)check(u._x==0 && u.Z轴坐标==0,"nirvana ascent preserves world X/Z");
        if(slot==2 || slot==3)check(u.mp==(slot==2?464:452),"native loop MP totals");
        if(slot==0 && !interrupted)check(sounds.length==12,"six swings invoke six chain and six swing cues");
        if(index==15)check(u._x<60.1,"run respects real wall collision x="+u._x);
        trace("HuofengNativeTest Damage: case="+index+" pulses="+pulses+" hits="+hitCounts+" HP="+damages+" raw="+rawTotal+" x="+u._x);
        cleanup();if(++index>=33)finish();else startCase();
    }
    private static function scopeSwitchContract():Void {
        HuofengPresentationTest.scopeSwitch(u,runtime,chest,check);
        runtime.dispose();hair.dispose();u.buffManager.destroy();u.removeMovieClip();createUnit();
    }
    private static function flameCount():Number {
        var count:Number=0;
        for(var i:Number=0;i<16;i++) if(u.__huofengVisual["burst"+i]._visible===true) count++;
        return count;
    }
    private static function cancellationContract():Void {
        var savedCache:Object=cache;
        cache={data:[],leftValues:[],rightValues:[],rightMaxValues:[]};
        var area:Object=u.man.hfHit2.getRect(world);
        for(var i:Number=0;i<7;i++) {
            // Each independent scene step needs its own native queue stamp.
            _root.帧计时器.当前帧数++;
            BulletCancelQueueProcessor.reset();
            var props:Object={发射者:u._name,声音:"",霰弹值:1,子弹散射度:0,发射效果:"",子弹种类:"透明子弹",
                子弹威力:1,子弹速度:1,击中地图效果:"",shootX:(area.xMin+area.xMax)*.5+(i==5?1000:0),
                shootY:(area.yMin+area.yMax)*.5,shootZ:i==3?100:0,Z轴攻击范围:1,lockShooterAttributes:true};
            var bullet:MovieClip=productionShoot(props);
            check(bullet!=undefined && bullet.aabbCollider!=undefined,"real cancellation projectile created "+i);
            var receipt:Object={vanished:false};bullet.__receipt=receipt;
            bullet.gotoAndPlay=function(label:String):Void{this.__receipt.vanished=label=="消失";};
            bullet.是否为敌人=i!=2;bullet.xmov=i==4?0:(i==1?-1:1);bullet.ymov=0;
            if(i==6) bullet.flags|=1; // Native FLAG_MELEE, excluded from cancellation.
            HuofengCombat.cancelBullets(u,action);
            check(BulletCancelQueueProcessor.soaLen==3 && !BulletCancelQueueProcessor.isPowerful[0]
                && !BulletCancelQueueProcessor.isBounce[0],"spin uses three ordinary damage-band cancellation areas");
            BulletQueueProcessor.processQueue();
            check(receipt.vanished===(i<2),"native cancellation respects direction/faction/Z/stationary/range/melee case "+i);
            if(bullet._parent) bullet.removeMovieClip();
        }
        cache=savedCache;
        trace("HuofengNativeTest Cancellation: seven real native projectiles checked");
    }
    private static function verifyColdMount():Void {
        var outer:MovieClip=u.man.刀;var blade:MovieClip=outer.刀.装扮;
        var points:Array=[[-8,33.95],[-9,135.95],[12,261.95]];
        check(Math.abs(outer.刀._x-1.8)<.1 && Math.abs(outer.刀._y-97.45)<.1,"cold mount preserves native grip wrapper");
        for(var i:Number=0;i<3;i++) {
            var actual:Object={x:0,y:0};blade["刀口位置"+(i+1)].localToGlobal(actual);
            var expected:Object={x:points[i][0]+1.8,y:points[i][1]+97.45};outer.localToGlobal(expected);
            check(Math.abs(actual.x-expected.x)<.3 && Math.abs(actual.y-expected.y)<.3,"cold contact follows original blade node "+i);
        }
        check(flameCount()>0,"revived cold skill keeps flame at its weapon tip");
    }
    private static function verifyControls():Void {
        var selected:String=_root.控制目标;_root.控制目标=u._name;
        var rootX:Number=_root._x;var rootY:Number=_root._y;
        var x:Number=u._x;var z:Number=u.Z轴坐标;var y:Number=u._y;
        var frame:Number=action.frame;var localFrame:Number=action.localFrame;
        u.左行=true;u.上行=true;
        _root.帧计时器.当前帧数++;HuofengAction.tick(u.man);
        if(action.kind==="nirvana") {
            check(u.方向==="右" && u._x==x && u.Z轴坐标==z,"nirvana still holds its world anchor and input lock");
            u.左行=u.上行=false;action.frame=frame;action.localFrame=localFrame;_root.控制目标=selected;return;
        }
        check(u.方向==="左" && u._xscale<0 && u._x<x && u.Z轴坐标<z,action.kind+" accepts movement and turn through native controls");
        check(_root._x==rootX && _root._y==rootY,"class input callback never moves the timeline definition scope");
        trace("HuofengNativeTest Control: "+action.kind+" direction="+u.方向+" x="+u._x+" z="+u.Z轴坐标);
        var movedX:Number=u._x;var movedZ:Number=u.Z轴坐标;
        u.左行=false;u.上行=false;u.右行=true;u.下行=true;
        _root.暂停=true;_root.帧计时器.当前帧数++;HuofengAction.tick(u.man);
        check(u._x==movedX && u.Z轴坐标==movedZ && u.方向==="左","pause freezes movement and facing");
        _root.暂停=false;_root.帧计时器.当前帧数++;HuofengAction.tick(u.man);
        check(u.方向==="右" && u._xscale>0 && u._x>movedX && u.Z轴坐标>movedZ,"reverse input turns and moves the active attack");
        u.右行=u.下行=false;u._x=x;u._y=y;u.Z轴坐标=z;u.方向改变("右");
        action.frame=frame;action.localFrame=localFrame;_root.控制目标=selected;
    }
    private static function cleanup():Void {
        HuofengPressureTest.endCase(check);
        for(var p:Number=0;p<projectiles.length;p++)if(projectiles[p]._parent)projectiles[p].removeMovieClip();
        if(runtime)runtime.dispose();if(hair)hair.dispose();if(u){u.buffManager.destroy();u.removeMovieClip();}
        for(var i:Number=0;i<targets.length;i++){factory.releaseCollider(targets[i].aabbCollider);targets[i].shield.dispose();targets[i].dispatcher.destroy();targets[i].removeMovieClip();}
        // This entire fixture-owned layer includes native descendants emitted
        // by a projectile's own timeline. None may leak into the next case.
        world.子弹区域.removeMovieClip();world.createEmptyMovieClip("子弹区域",20000);
        targets=[];_root.暂停=false;
    }
    private static function captureImage():Void {
        if(_root.huofengCaptureRun==undefined)return;
        var bitmap:BitmapData=new BitmapData(900,720,false,0x181824);
        bitmap.draw(u,new Matrix(1.5,0,0,1.5,450,620));
        var pixels:String="",previous:Number=-1,count:Number=0;
        for(var y:Number=0;y<720;y++)for(var x:Number=0;x<900;x++){
            var color:Number=bitmap.getPixel(x,y);
            if(color==previous)count++;
            else{if(count>0)pixels+=count.toString(16)+":"+previous.toString(16)+",";previous=color;count=1;}
        }
        if(count>0)pixels+=count.toString(16)+":"+previous.toString(16);
        bitmap.dispose();
        var request:LoadVars=new LoadVars();request.run=_root.huofengCaptureRun;
        request.key="case-"+index+"-frame-"+action.frame;request.value="900|720|"+pixels;
        request.sendAndLoad("http://127.0.0.1:8787/report",new LoadVars(),"POST");
        if(age==4){
            for(var key:String in u.底层背景){
                var clip:MovieClip=u.底层背景[key];if(clip.__hf8Token==undefined)continue;
                var b:Object=clip.getBounds(u);trace("HuofengNativeTest Hair: "+key+" visible="+clip._visible+" bounds="+b.xMin+","+b.yMin+","+b.xMax+","+b.yMax+" matrix="+clip.transform.matrix);
            }
        }
    }
    private static function finish():Void {
        if(ended)return;ended=true;delete driver.onEnterFrame;
        trace("HuofengNativeTest Tests Passed: "+passed);trace("HuofengNativeTest Tests Failed: "+failed);
        _root.huofengNativeTestComplete();
    }
}
