import org.flashNight.arki.hud.PlayerHudAllyRoster;
import org.flashNight.arki.hud.FocusTargetHudService;
class org.flashNight.arki.hud.PlayerHudAllyRosterTest {
    private static var cases:Number;
    private static var failures:Number;
    private static function check(ok:Boolean, label:String):Void {
        cases++;
        if (!ok) failures++;
        trace("ALLYTEST " + (ok ? "PASS " : "FAIL ") + label);
    }
    private static function born(w:MovieClip, key:String, role:String):MovieClip {
        var u:MovieClip = w.createEmptyMovieClip(key, w.getNextHighestDepth());
        u.__hudAllyRole=role; u.是否为敌人=false; u.hp=79; u.hp满血值=100; u.名字=key;
        u.version=1; u.__unitInitializedVersion=1;
        PlayerHudAllyRoster.onUnitInitialized(u);
        return u;
    }
    private static function snap(f):Object { return PlayerHudAllyRoster.snapshot(null,f); }
    private static function batch():Void {
        var w:MovieClip=_root.createEmptyMovieClip("allyBatch",_root.getNextHighestDepth());
        var before=_root.gameworld; _root.gameworld=w; PlayerHudAllyRoster.clear(); PlayerHudAllyRoster.configure("four");
        var u:MovieClip=born(w,"oldscript","merc");
        var sample:Function=function(frame:Number, ms:Number, pause:Boolean):Object {
            return PlayerHudAllyRoster.snapshotAt(null,null,frame,ms,pause,false);
        };
        sample(0,0,false); u.hp=72;
        check(sample(1,17,false).rows[0].hp[0]==79 && PlayerHudAllyRoster.observeHp()[0][3]==72,"direct write ordinary HP held; raw observer sees 72");
        u.hp=29;check(sample(2,32,false).rows[0].hp[0]==29,"direct write danger supplied on non-poll beat");
        u.hp=40;check(sample(3,40,false).rows[0].hp[0]==40,"danger exit immediately clears indicator");u.hp=28;
        check(sample(5,55,false).rows[0].hp[0]==28,"danger reentry on a non-poll beat");
        u.hp=0;check(sample(6,70,false).rows[0].down,"death on non-poll beat");
        u.hp=81;check(!sample(7,85,false).rows[0].down,"revive on non-poll beat");
        u.hp=74;check(sample(7,93,true).rows[0].hp[0]==74,"pause edge immediate");
        u.hp=70;check(sample(7,100,true).rows[0].hp[0]==70,"direct write while a paused frame repeats");
        u.hp=66;check(sample(9,112,false).rows[0].hp[0]==66,"resume edge immediate");
        u.hp=NaN;check(sample(10,125,false).rows.length==0,"invalid HP clears current row");
        u.hp=55;check(sample(11,140,false).rows[0].hp[0]==55,"valid HP is immediately restored");
        PlayerHudAllyRoster.configure("deadline");sample(13,155,false);u.hp=49;
        check(sample(14,204,false).rows[0].hp[0]==55,"deadline does not fire at 49ms");
        check(sample(15,205,false).rows[0].hp[0]==49,"deadline bypasses 4-beat phase at 50ms");
        u.hp=47;check(sample(17,20,false).rows[0].hp[0]==47,"wall clock wrap resynchronizes");
        u.removeMovieClip();check(sample(18,25,false).rows.length==0,"departure on non-poll beat");
        u=born(w,"oldscript","merc");var newRow:Object=sample(19,30,false).rows[0];
        check(newRow.hp[0]==79,"admission on non-poll beat");
        var guard:Object=FocusTargetHudService.bindInitialized(u,"protect","guard");
        var protectedRow:Object=sample(21,34,false).rows[0];
        check(protectedRow.slot>=20 && protectedRow["protected"],"protect acquires reserve on non-poll beat");
        var focus:Array=FocusTargetHudService.snapshotList(null,4);
        check(PlayerHudAllyRoster.snapshotAt(null,focus,22,37,false,false).rows.length==0,"visible focus masks redundant ally on non-poll beat");
        FocusTargetHudService.clear(guard);
        check(sample(23,39,false).rows[0].slot<20,"protect release and focus unmask on non-poll beat");
        u.removeMovieClip();u=born(w,"oldscript","merc");
        check(sample(25,43,false).rows[0].id!=newRow.id,"reused display-list name has new identity off-phase");
        u.__hudAllyRole="pet";
        check(sample(26,45,false).rows[0].role=="pet","existing script changes role on non-poll beat");
        PlayerHudAllyRoster.configure("deadline");PlayerHudAllyRoster.clear();_root.gameworld=before;w.removeMovieClip();
        trace("ALLYBATCH FINISH "+(failures==0?"PASS":"FAIL"));
    }
    public static function runAllTests():Void { run(); }
    public static function run():Void {
        cases=failures=0;
        PlayerHudAllyRoster.configure(undefined);
        check(PlayerHudAllyRoster.currentMode()=="deadline","unspecified sampling uses deadline");
        PlayerHudAllyRoster.configure("every");
        check(PlayerHudAllyRoster.currentMode()=="every","explicit every remains available");
        var before = _root.gameworld;
        var w:MovieClip=_root.createEmptyMovieClip("allySuite",_root.getNextHighestDepth());
        _root.gameworld=w; PlayerHudAllyRoster.clear();
        var i:Number;
        for(i=0;i<20;i++) born(w,"map"+i,"map");
        born(w,"spare","map");
        var a:Object=snap(null);
        check(a.rows.length==20 && a.overflow[0].name=="spare","same priority waits at capacity");
        var pet:MovieClip=born(w,"pet","pet"); var b:Object=snap(null);
        var fixed:Boolean=true;
        for(i=0;i<19;i++) if(a.rows[i]!==b.rows[i]) fixed=false;
        check(fixed && b.rows[19].name=="pet" && b.overflow[0].name=="map19","pet replaces last map only");
        var merc:MovieClip=born(w,"merc","merc"); var c:Object=snap(null);
        check(c.rows[18].name=="merc" && c.rows[19].name=="pet" && c.overflow.length==3,"merc takes lowest tier last seat");
        var id:Number=c.rows[18].id;
        merc.hp=0; c=snap(null); check(c.rows[18].id==id && c.rows[18].down,"down retains seat");
        merc.hp=45; c=snap(null); check(c.rows[18].id==id && !c.rows[18].down,"revive retains seat");
        var guard:MovieClip=born(w,"guard","map");
        var lease:Object=FocusTargetHudService.bindInitialized(guard,"protect","guard");
        var f:Array=FocusTargetHudService.snapshotList(null,4);
        c=snap(f); check(f.length==1 && c.rows.length==20 && c.overflow.length==3,"visible focus appears once");
        c=snap([]);check(c.rows.length==21 && c.rows[20].name=="guard" && c.rows[20]["protected"],"protected unit gets independent seat");
        check(c===snap([]),"static member and roster snapshots reused");
        FocusTargetHudService.clear(lease);
        merc.removeMovieClip();c=snap(null);
        check(c.rows[18].name=="map18" && c.rows[19].name=="pet","departed seat takes oldest waiting map");
        var recycled:MovieClip=born(w,"merc","merc");c=snap(null);
        var fresh:Boolean=false;for(i=0;i<c.rows.length;i++) if(c.rows[i].name=="merc" && c.rows[i].id!=id)fresh=true;
        check(fresh,"same display-list name has fresh identity");
        var other:MovieClip=_root.createEmptyMovieClip("allyNext",_root.getNextHighestDepth());
        _root.gameworld=other;var generation:Number=c.rows[0].generation;
        check(snap(null).rows.length==0,"new scene clears all old members");
        born(other,"map0","map");check(snap(null).rows[0].generation!=generation,"new scene generation");
        _root.gameworld=before;other.removeMovieClip();w.removeMovieClip();PlayerHudAllyRoster.clear();
        batch();
        trace("ALLYTEST FINISH "+(failures==0?"PASS":"FAIL")+" cases="+cases+" failures="+failures);
    }
}
