import flash.filters.GlowFilter;
import flash.filters.ColorMatrixFilter;
import flash.display.BitmapData;
import flash.geom.ColorTransform;
import org.flashNight.arki.weather.NightVisionUnitTint;
class org.flashNight.arki.weather.NightVisionUnitTintTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean,name:String):Void {
        if(value)passed++;else{failed++;trace("FAIL NightVisionUnitTintTest: "+name);}
    }
    private static function unit(parent:MovieClip,name:String,depth:Number):MovieClip {
        var u:MovieClip=parent.createEmptyMovieClip(name,depth);u.hp=100;
        var b:MovieClip=u.createEmptyMovieClip("man",1);
        b.beginFill(0,100);b.moveTo(0,0);b.lineTo(20,0);b.lineTo(20,20);b.lineTo(0,20);b.lineTo(0,0);b.endFill();
        u.createEmptyMovieClip("shadow",2);
        return u;
    }
    // Real AVM1 filter raster, exported for the native full-camera regression.
    // This is a synthetic actor fixture, never an inferred mask over gameplay.
    private static function exportOutlineFixture(profile:Object,label:String):Void {
        var parent:MovieClip=_root.createEmptyMovieClip("nightRimRaster",76549);
        var u:MovieClip=parent.createEmptyMovieClip("actor",1);u.hp=100;
        var b:MovieClip=u.createEmptyMovieClip("man",1);
        var points:Array=[26,9,38,9,43,15,43,25,39,30,43,34,46,40,59,39,61,42,45,45,43,57,39,61,43,86,36,88,32,67,28,86,21,86,23,62,21,49,15,58,10,55,16,39,21,33,26,29,22,25,22,15];
        b.beginFill(0x0C1015,100);b.moveTo(points[0],points[1]);
        for(var n:Number=2;n<points.length;n+=2)b.lineTo(points[n],points[n+1]);
        b.lineTo(points[0],points[1]);b.endFill();
        if(profile.UnitStyle=="whitehot" || profile.UnitStyle=="natural") {
            // Synthetic face and vest panels: verify that fusion retains
            // internal material contrast as well as the outer silhouette.
            b.beginFill(0xA77955,100);b.moveTo(28,14);b.lineTo(37,14);b.lineTo(37,23);b.lineTo(28,23);b.lineTo(28,14);b.endFill();
            b.beginFill(0x345783,100);b.moveTo(27,36);b.lineTo(36,36);b.lineTo(36,49);b.lineTo(27,49);b.lineTo(27,36);b.endFill();
            b.beginFill(0x404040,100);b.moveTo(24,52);b.lineTo(38,52);b.lineTo(38,56);b.lineTo(24,56);b.lineTo(24,52);b.endFill();
        }
        NightVisionUnitTint.syncUnits(profile,[u],u);
        var image:BitmapData=new BitmapData(64,96,true,0);image.draw(b);
        for(var y:Number=0;y<96;y++) {
            var line:String="";
            for(var x:Number=0;x<64;x++) {
                if(x>0)line+=",";
                line+=String(image.getPixel32(x,y));
            }
            trace("NV_RIM_RASTER "+label+" "+y+" "+line);
        }
        image.dispose();NightVisionUnitTint.clear();parent.removeMovieClip();
    }
    public static function runAllTests():Void {
        passed=0;failed=0;NightVisionUnitTint.clear();
        var p:Object={UnitStrength:.52,UnitRed:.4,UnitGreen:1,UnitBlue:.4};
        check(NightVisionUnitTint.makeMatrix({UnitStrength:0})==null,"zero strength disabled");
        check(NightVisionUnitTint.makeMatrix({UnitStrength:.5,UnitRed:-1,UnitGreen:1,UnitBlue:1})==null,"bad tint rejected");
        var m:Array=NightVisionUnitTint.makeMatrix(p);
        check(m.length==20 && m[18]===1 && m[19]===0,"alpha stays identity");
        var world:MovieClip=_root.createEmptyMovieClip("nightTintTestWorld",76548);
        var a:MovieClip=unit(world,"a",1);
        a.man.filters=[new GlowFilter(0x3366FF,.5,2,2,1)];
        var ct:ColorTransform=new ColorTransform();ct.redMultiplier=.7;ct.redOffset=31;
        a.man.transform.colorTransform=ct;a.man._alpha=63;
        var alphaBefore:Number=a.man._alpha;
        NightVisionUnitTint.syncUnits(p,[a],a);
        check(a.man.filters.length==2 && a.man.filters[0] instanceof GlowFilter,"append preserves existing glow");
        check(a.man._alpha===alphaBefore,"unit alpha preserved");
        check(a.man.transform.colorTransform.redOffset===31,"existing color transform preserved");
        check(a.shadow.filters.length==0,"ground shadow excluded");
        NightVisionUnitTint.syncUnits(p,[a],a);
        check(a.man.filters.length==2,"hero in roster cannot double tint");
        ct.redOffset=89;a.man.transform.colorTransform=ct;
        NightVisionUnitTint.syncUnits(p,[a],a);
        check(a.man.transform.colorTransform.redOffset===89,"later hit tint remains authoritative");
        var b:MovieClip=unit(world,"b",2);
        NightVisionUnitTint.syncUnits(p,[a,b],a);
        check(b.man.filters.length==1,"new actor receives fill");
        var pixels:BitmapData=new BitmapData(64,64,true,0);
        pixels.draw(b.man);
        check(((pixels.getPixel(10,10)>>8)&255)>20,"black art becomes visible inside its shape");
        check(pixels.getPixel32(63,63)==0,"transparent canvas receives no fill");pixels.dispose();
        b._visible=false;NightVisionUnitTint.syncUnits(p,[a,b],a);
        check(b.man.filters.length==0,"invisible actor removed");
        b._visible=true;b.hp=0;NightVisionUnitTint.syncUnits(p,[a,b],a);
        check(b.man.filters.length==0,"dead actor excluded");
        b.hp=100;NightVisionUnitTint.syncUnits(p,[a,b],a);NightVisionUnitTint.syncUnits(p,[a],a);
        check(b.man.filters.length==0,"removed roster member cleaned");
        var q:Object={UnitStrength:.2,UnitRed:1,UnitGreen:.4,UnitBlue:.3};
        NightVisionUnitTint.syncUnits(q,[a],a);
        check(a.man.filters.length==2,"profile switch replaces only owned layer");
        check(a.man.filters[1].matrix[4]!==m[4],"new profile replaces old tint values");
        a.man.filters=[new GlowFilter(0xFF0000,1,3,3,1)];
        for(var n:Number=0;n<8;n++)NightVisionUnitTint.syncUnits(q,[a],a);
        check(a.man.filters.length==2,"external filter replacement repaired");
        NightVisionUnitTint.clear();
        check(a.man.filters.length==1 && a.man.filters[0] instanceof GlowFilter,"cleanup retains other effects");
        check(a.man.transform.colorTransform.redOffset===89,"cleanup retains current injury tint");
        b.man.filters=[new ColorMatrixFilter(m)];
        NightVisionUnitTint.syncUnits(p,[b],null);NightVisionUnitTint.clear();
        check(b.man.filters.length==1,"identical existing matrix is not deleted");
        b.man.filters=[];NightVisionUnitTint.syncUnits(p,[b],null);
        b.man.removeMovieClip();b.createEmptyMovieClip("man",1).filters=[new GlowFilter()];
        NightVisionUnitTint.clear();
        check(b.man.filters.length==1 && b.man.filters[0] instanceof GlowFilter,"same-path replacement not touched by stale owner");
        NightVisionUnitTint.syncUnits(p,[a],a);
        org.flashNight.arki.weather.WorldLightingBridge.sceneChanged();
        check(a.man.filters.length==1,"scene change immediately releases tint");
        NightVisionUnitTint.syncUnits(p,[a],a);
        var oldServer:Object=_root.server;_root.server={isSocketConnected:false};
        NightVisionUnitTint.tick();_root.server=oldServer;
        check(a.man.filters.length==1,"connection loss releases tint");
        NightVisionUnitTint.syncUnits(p,[a],a);
        NightVisionUnitTint.syncUnits({UnitStrength:0},[a],a);
        check(a.man.filters.length==1,"true vision or unequip removes fill");
        // Environment texture suppression must not erase the semantic actor rim.
        var c:MovieClip=unit(world,"c",3);
        var outline:Object={UnitStrength:0,EdgeStrength:.62,EdgeWidth:1.1,EdgeRed:.46,EdgeGreen:1,EdgeBlue:.49};
        check(NightVisionUnitTint.makeGlow({EdgeStrength:0})==null,"zero outline disabled");
        check(NightVisionUnitTint.makeGlow({EdgeStrength:.5,EdgeWidth:1,EdgeRed:-1,EdgeGreen:1,EdgeBlue:1})==null,"bad outline color rejected");
        c.man.filters=[new GlowFilter(0x123456,.4,3,3,1)];
        NightVisionUnitTint.syncUnits(outline,[c],c);
        check(c.man.filters.length==2 && c.man.filters[1] instanceof GlowFilter,"edge-only profile owns semantic outline");
        check(c.shadow.filters.length==0,"semantic outline excludes ground shadow");
        NightVisionUnitTint.syncUnits(outline,[c],c);
        check(c.man.filters.length==2,"hero roster cannot double outline");
        pixels=new BitmapData(64,64,true,0);pixels.draw(c.man);
        check(((pixels.getPixel(21,10)>>8)&255)>0,"semantic rim follows alpha outside black actor");
        check(pixels.getPixel(10,10)==0,"outline does not fill opaque black interior");
        check(pixels.getPixel32(63,63)==0,"semantic outline does not fill transparent canvas");pixels.dispose();
        ct.redOffset=67;c.man.transform.colorTransform=ct;
        NightVisionUnitTint.syncUnits(outline,[c],c);
        check(c.man.transform.colorTransform.redOffset==67,"semantic outline preserves live hit transform");
        var fusion:Object={UnitStrength:.26,UnitRed:.78,UnitGreen:1,UnitBlue:.73,EdgeStrength:.16,EdgeWidth:.85,EdgeRed:.62,EdgeGreen:1,EdgeBlue:.74};
        NightVisionUnitTint.syncUnits(fusion,[c],c);
        check(c.man.filters.length==3 && c.man.filters[1] instanceof ColorMatrixFilter && c.man.filters[2] instanceof GlowFilter,"fusion owns fill then outline");
        NightVisionUnitTint.clear();
        check(c.man.filters.length==1 && c.man.filters[0].color==0x123456,"cleanup removes both layers and retains external glow");
        c.man.filters=[NightVisionUnitTint.makeGlow(outline)];
        NightVisionUnitTint.syncUnits(outline,[c],c);NightVisionUnitTint.clear();
        check(c.man.filters.length==1,"identical external glow survives cleanup");
        c.man.filters=[];NightVisionUnitTint.syncUnits(outline,[c],c);
        c.man.filters=[new GlowFilter(0xFF0000,1,3,3,1)];
        for(n=0;n<8;n++)NightVisionUnitTint.syncUnits(outline,[c],c);
        check(c.man.filters.length==2,"external list replacement repairs semantic rim");
        c.hp=0;NightVisionUnitTint.syncUnits(outline,[c],null);
        check(c.man.filters.length==1,"corpse loses semantic rim only");
        c.hp=100;NightVisionUnitTint.syncUnits(outline,[c],c);
        org.flashNight.arki.weather.WorldLightingBridge.sceneChanged();
        check(c.man.filters.length==1,"scene change releases semantic rim");
        NightVisionUnitTint.syncUnits(outline,[c],c);
        NightVisionUnitTint.syncUnits({UnitStrength:0,EdgeStrength:0},[c],c);
        check(c.man.filters.length==1,"true vision removes semantic rim");
        NightVisionUnitTint.clear();
        // Exercise the production tick, including the capability gate that a
        // direct syncUnits fixture cannot cover. Roster input alone is stubbed.
        var oldWorld:MovieClip=_root.gameworld,oldTarget:String=_root.控制目标;
        var oldColor:Object=_root.色彩引擎;
        oldServer=_root.server;
        var weather=org.flashNight.arki.render.WeatherParticleRenderer;
        var oldNative:Boolean=weather.hasNativeHost();
        var oldWeather:String=weather.getWeatherType(),oldIntensity:Number=weather.getWeatherIntensity();
        var rosterClass=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        var oldRoster:Function=rosterClass.getCachedAll;
        _root.__nightTintTestRoster=[b,c];_root.__nightTintRosterCalls=0;
        rosterClass.getCachedAll=function(t:Object,i:Number):Array {
            _root.__nightTintRosterCalls++;return _root.__nightTintTestRoster;
        };
        _root.gameworld=world;_root.控制目标="c";_root.server={isSocketConnected:true};
        var red:Object={Version:1,UnitStyle:"whitehot",UnitStrength:1,UnitRed:1,UnitGreen:1,UnitBlue:1,EdgeStrength:0};
        fusion.Version=1;
        _root.色彩引擎={视觉增强映射表:{target:red,fusion:fusion}};
        var manager=org.flashNight.arki.weather.WeatherSystem.getInstance().getNightVisionManager();
        var priorCfg:Object=manager.getRegistered();
        manager.register({视觉情况:"target",最小启动亮度:0,最大启动亮度:4});manager.validate(0,c);
        c.man.filters=[];b.man.filters=[];c.man.transform.colorTransform=new ColorTransform();
        weather.setNativeEnabled(true);weather.setWeather("none",0);
        check(weather.hasNativeHost() && !weather.isNativeEnabled(),"clear weather keeps paired Host capability");
        NightVisionUnitTint.tick();
        check(c.man.filters.length==1 && c.man.filters[0] instanceof ColorMatrixFilter,"production tick fills hero in clear indoor scene");
        check(b.man.filters.length==1 && b.man.filters[0] instanceof ColorMatrixFilter,"production tick fills live roster member");
        pixels=new BitmapData(64,64,true,0);pixels.draw(c.man);
        check(((pixels.getPixel(10,10)>>16)&255)>220,"white-hot production fill makes black clothing bright");pixels.dispose();
        check(weather.getWeatherType()=="none" && weather.getWeatherIntensity()==0,"night assist leaves weather selection unchanged");
        manager.register({视觉情况:"fusion",最小启动亮度:0,最大启动亮度:4});manager.validate(0,c);
        NightVisionUnitTint.tick();
        check(c.man.filters.length==2 && c.man.filters[0] instanceof ColorMatrixFilter && c.man.filters[1] instanceof GlowFilter,"production fusion tick owns fill and silhouette");
        weather.setNativeEnabled(false);NightVisionUnitTint.tick();
        check(c.man.filters.length==0 && b.man.filters.length==0,"capability revocation releases both actor layers");
        weather.setNativeEnabled(true);NightVisionUnitTint.tick();
        check(c.man.filters.length==2,"clear-weather reconnection restores active assist");
        manager.validate(7,c);var rosterCalls:Number=_root.__nightTintRosterCalls;NightVisionUnitTint.tick();
        check(c.man.filters.length==0 && b.man.filters.length==0,"brightness outside activation range clears assist");
        check(_root.__nightTintRosterCalls==rosterCalls,"inactive assist does not query actor roster");
        manager.validate(0,c);NightVisionUnitTint.tick();
        check(c.man.filters.length==2,"brightness return reactivates fusion");
        _root.server.isSocketConnected=false;NightVisionUnitTint.tick();
        check(c.man.filters.length==0 && b.man.filters.length==0,"production disconnect cleans hero and roster");
        manager.register(priorCfg);rosterClass.getCachedAll=oldRoster;
        weather.setWeather(oldWeather,oldIntensity);weather.setNativeEnabled(oldNative);
        _root.gameworld=oldWorld;_root.控制目标=oldTarget;_root.server=oldServer;_root.色彩引擎=oldColor;
        delete _root.__nightTintTestRoster;delete _root.__nightTintRosterCalls;
        NightVisionUnitTint.clear();
        var hot:Object={UnitStyle:"whitehot",UnitStrength:1,UnitRed:1,UnitGreen:1,UnitBlue:1,EdgeStrength:0};
        var hm:Array=NightVisionUnitTint.makeMatrix(hot);
        check(hm[18]===1 && hm[19]===0,"white-hot matrix keeps alpha identity");
        check(hm[0]===hm[5] && hm[5]===hm[10] && hm[4]===hm[9] && hm[9]===hm[14],"white-hot matrix has neutral RGB rows");
        c.man.filters=[];c.man.transform.colorTransform=new ColorTransform();
        c.man.beginFill(0xFF3300,100);c.man.moveTo(4,4);c.man.lineTo(12,4);c.man.lineTo(12,12);c.man.lineTo(4,12);c.man.lineTo(4,4);c.man.endFill();
        NightVisionUnitTint.syncUnits(hot,[c],c);
        pixels=new BitmapData(64,64,true,0);pixels.draw(c.man);
        var blackHot:Number=pixels.getPixel(2,2),coloredHot:Number=pixels.getPixel(8,8);
        check((blackHot&255)>220,"black material receives a bright white-hot floor");
        check((blackHot&255)==((blackHot>>8)&255) && ((blackHot>>8)&255)==((blackHot>>16)&255),"black clothing is white rather than amber");
        check((coloredHot&255)==((coloredHot>>8)&255) && ((coloredHot>>8)&255)==((coloredHot>>16)&255),"colored art becomes neutral heat detail");
        check(pixels.getPixel32(63,63)==0,"white-hot does not heat transparent canvas");pixels.dispose();
        check(c.man._alpha==100 && c.man.transform.colorTransform.redOffset==0,"white-hot leaves alpha and hit transform ownership intact");
        var unitRim:Object={UnitStrength:0,EdgeStrength:.1,UnitOutlineStrength:.65,EdgeWidth:1,EdgeRed:1,EdgeGreen:1,EdgeBlue:1};
        var rimAlpha:Number=NightVisionUnitTint.makeGlow(unitRim).alpha;
        check(rimAlpha>.60 && rimAlpha<.70,"unit rim strength is independent of quiet environment edges alpha="+rimAlpha);
        unitRim.UnitOutlineStrength=0;
        check(NightVisionUnitTint.makeGlow(unitRim)==null,"explicit zero unit rim disables the rim");
        NightVisionUnitTint.syncUnits(p,[c],c);
        check(c.man.filters.length==1 && c.man.filters[0].matrix[4]!==hm[4],"switching away from white-hot replaces its owned layer");
        NightVisionUnitTint.clear();
        var strongRim:Object={UnitStrength:0,EdgeStrength:.22,EdgeWidth:.8,UnitOutlineStrength:1.15,UnitOutlineWidth:1.8,EdgeRed:.46,EdgeGreen:1,EdgeBlue:.49};
        var strongGlow:GlowFilter=NightVisionUnitTint.makeGlow(strongRim);
        check(strongGlow.blurX>3 && strongGlow.alpha>.99 && strongGlow.strength>3,"actor rim retains concentrated coverage at independent width");
        strongRim.UnitOutlineWidth=0;
        check(NightVisionUnitTint.makeGlow(strongRim)==null,"invalid unit width rejected instead of silently using environment width");
        strongRim.UnitOutlineWidth=1.8;
        c.man.filters=[new GlowFilter(0x123456,.4,3,3,1)];
        NightVisionUnitTint.syncUnits(strongRim,[c],c);NightVisionUnitTint.clear();
        check(c.man.filters.length==1 && c.man.filters[0].color==0x123456,"strong actor rim releases only its own concentrated glow");
        exportOutlineFixture({UnitStrength:0,EdgeStrength:.22,EdgeWidth:.8,UnitOutlineStrength:.68,EdgeRed:.46,EdgeGreen:1,EdgeBlue:.49},"before");
        exportOutlineFixture(strongRim,"after");
        NightVisionUnitTint.clear();
        var phantomBefore:Object={UnitStyle:"whitehot",UnitStrength:.9,UnitRed:1,UnitGreen:1,UnitBlue:1,EdgeStrength:.1,EdgeWidth:.8,UnitOutlineStrength:.35,EdgeRed:1,EdgeGreen:1,EdgeBlue:1};
        var phantomAfter:Object={UnitStyle:"whitehot",UnitStrength:.5,UnitRed:1,UnitGreen:1,UnitBlue:1,EdgeStrength:.05,EdgeWidth:.8,UnitOutlineStrength:1.15,UnitOutlineWidth:1.6,EdgeRed:1,EdgeGreen:1,EdgeBlue:1};
        // The previous c fixture has a colored patch inside a black body.
        // The actual filter should keep dark clothes gray and restore detail.
        c.man.filters=[];c.man.transform.colorTransform=new ColorTransform();
        NightVisionUnitTint.syncUnits(phantomBefore,[c],c);
        pixels=new BitmapData(64,64,true,0);pixels.draw(c.man);
        var priorDetail:Number=(pixels.getPixel(8,8)&255)-(pixels.getPixel(10,16)&255);pixels.dispose();
        NightVisionUnitTint.syncUnits(phantomAfter,[c],c);
        pixels=new BitmapData(64,64,true,0);pixels.draw(c.man);
        var grayBody:Number=pixels.getPixel(10,16)&255;
        var newDetail:Number=(pixels.getPixel(8,8)&255)-grayBody;
        check(grayBody>=100 && grayBody<145,"phantom fusion keeps black clothes gray rather than white or invisible");
        check(newDetail>=priorDetail*2.5 && newDetail>30,"phantom fusion restores internal material contrast");
        check(pixels.getPixel32(63,63)==0 && c.man.filters.length==2,"phantom fill and rim share actor alpha without heating the canvas");pixels.dispose();
        exportOutlineFixture(phantomBefore,"fusion-before");
        exportOutlineFixture(phantomAfter,"fusion-after");
        NightVisionUnitTint.clear();
        var natural:Object={UnitStyle:"natural",UnitStrength:0,UnitRed:1,UnitGreen:1,UnitBlue:1,EdgeStrength:0,EdgeWidth:.8,UnitOutlineStrength:.18,UnitOutlineWidth:1,EdgeRed:.72,EdgeGreen:.82,EdgeBlue:.94};
        c.man.filters=[];c.man.transform.colorTransform=new ColorTransform();
        NightVisionUnitTint.syncUnits(natural,[c],c);
        pixels=new BitmapData(64,64,true,0);pixels.draw(c.man);
        var naturalPatch:Number=pixels.getPixel(8,8);
        check(c.man.filters.length==1 && c.man.filters[0] instanceof GlowFilter,"natural vision uses only a faint actor rim without repainting material");
        check((naturalPatch>>16&255)>(naturalPatch&255)+100 && pixels.getPixel32(63,63)==0,"natural vision preserves actor color and transparent canvas");pixels.dispose();
        exportOutlineFixture(phantomAfter,"natural-before");
        exportOutlineFixture(natural,"natural-after");
        exportOutlineFixture({UnitStyle:"natural",UnitStrength:0,UnitOutlineStrength:0,EdgeStrength:0},"natural-source");
        NightVisionUnitTint.clear();world.removeMovieClip();
        trace("NightVisionUnitTintTest Tests Passed: "+passed);
        trace("NightVisionUnitTintTest Tests Failed: "+failed);
    }
}
