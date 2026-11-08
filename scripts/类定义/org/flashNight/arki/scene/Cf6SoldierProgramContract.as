/** Cold, closed runtime admission. Unknown behavior never falls back to AI. */
class org.flashNight.arki.scene.Cf6SoldierProgramContract {
    private static function whole(value,low:Number,high:Number):Boolean {
        return typeof value=="number" && isFinite(value) && Math.floor(value)==value && value>=low && value<=high;
    }
    private static function member(value,choices:String):Boolean {
        return typeof value=="string" && ("|"+choices+"|").indexOf("|"+value+"|")>=0 && value!="" && value.indexOf("|")<0;
    }
    private static function keys(value:Object,allowed:String):Boolean {
        if(value==null || typeof value!="object" || value instanceof Array)return false;
        for(var key:String in value)if(!member(key,allowed))return false;
        return true;
    }
    private static function mapId(value):Boolean {
        if(typeof value!="string" || value.length!=3 || value.charAt(0)!="A")return false;
        var n:Number=Number(value.substr(1));
        return whole(n,1,20) && value==="A"+(n<10?"0":"")+n;
    }
    public static function profile(profile:Object):Boolean {
        var p:Object=profile.program,b:Object=profile.budget,e:Object=profile.extensions;
        var suppression:Object=p.suppression, sustained:Boolean=suppression!==undefined;
        if(sustained && (!keys(suppression,"weaponName|weaponType|fireFrames|recoveryFrames")
            || typeof suppression.weaponName!="string" || length(suppression.weaponName)<1 || length(suppression.weaponName)>96
            || !member(suppression.weaponType,"机枪|压制机枪") || suppression.fireFrames!==60 || suppression.recoveryFrames!==30
            || b.primaryTriggerLimit!==60))return false;
        var triggerCap:Number=sustained?60:8,cycleCap:Number=sustained?900:20,grantCap:Number=sustained?900:14;
        if(!member(profile.role,"line|suppress|precision|breach|flush|mobile|dual|counter")
            || !member(profile.roleClass,"ordinary|elite|instructor") || !member(profile.strategy,"line|mobile|adaptive|switch")
            || !keys(p,"schema|trigger|waiting|stages|dual|phase2|fallback|shield|grenade|pressure|recovery|danger|maxDistance|fireDistance|minDistance|lane|stopDistance|tether|mixed|capabilities|suppression")
            || p.schema!==1 || typeof p.danger!="boolean" || typeof p.mixed!="boolean"
            || !whole(p.recovery,1,180) || !whole(p.maxDistance,95,680) || !whole(p.fireDistance,p.maxDistance,1200) || !whole(p.minDistance,0,p.maxDistance)
            || !whole(p.stopDistance,0,680) || !whole(p.lane,1,80) || !whole(p.tether,0,480)
            || !member(p.waiting,"acquire|hold|anchor|close|boss_guard|primary_fallback|reload|g1111_pair|pair"))return false;
        var tactics:String="shield_breach|reverse_rear_guard|fixed_bastion|pursuit_leash|segmented_lane|advance_flush|landing_watch|bright_burst|relocate_then_flush|range_rotation|shield_counter|judgment_line|disciplined_screen|feint_retreat|alternating_fire|punish_commit|paired_windows|weapon_handoff|reserve_gate|robot_observer|threshold_flush|final_phase_guard";
        if(profile.roleClass=="instructor"){
            if(!member(p.trigger,tactics) || p.trigger!==e.majorTactic || p.danger!==true)return false;
        }else if(p.trigger!=="ordinary" || e.majorTactic!=null || p.danger!==false)return false;
        if(!whole(b.primaryTriggerLimit,1,triggerCap) || !whole(b.primarySplit,1,14)
            || !whole(b.sidearmSynchronizedTriggerLimit,0,3) || !whole(b.sidearmProjectilesPerAction,0,6)
            || !whole(b.subweaponProjectilesPerAction,0,7) || !whole(b.subweaponFinalDamageUnitsPerAction,0,7)
            || !whole(b.scriptedCycleProjectiles,1,cycleCap) || !whole(b.scriptedCycleDamageUnits,1,cycleCap)
            || !whole(b.maxGrantedDamageUnits,1,grantCap)
            || !whole(b.maxPlannedActionProjectiles,1,grantCap) || b.activeFrameRate!==30
            || !whole(e.subweaponBurstLimit,0,1) || !whole(e.finiteThrowableCount,0,3)
            || b.primaryTriggerLimit*b.primarySplit!==b.primaryProjectilesPerAction
            || b.primaryProjectilesPerAction+b.subweaponProjectilesPerAction!==b.longgunWithSubProjectilesPerAction
            || b.maxPlannedActionProjectiles>b.scriptedCycleProjectiles)return false;
        var capabilityNames:String="fixed_action|weapon_commit|weapon_pose|subweapon|projectile_lifetime|charge_terminal|danger_lease|direct_attack|wings_recovery|reload_commit|shield_recovery|g1111_pair|player_commit|alternating_pair|vanguard_event|robot_recovery|birth_crossing|human_guard";
        if(!(p.capabilities instanceof Array) || p.capabilities.length<3 || p.capabilities.length>18)return false;
        var seen:Object={};
        for(var i:Number=0;i<p.capabilities.length;i++){
            var cap:String=p.capabilities[i];if(!member(cap,capabilityNames) || seen[cap])return false;seen[cap]=true;
        }
        if(!seen.fixed_action || !seen.weapon_commit || !seen.weapon_pose || p.danger && !seen.danger_lease)return false;
        var names:Array=["stages","dual","phase2","fallback","shield","grenade","pressure"];
        for(i=0;i<names.length;i++){
            var stages:Object=p[names[i]];
            if(stages===undefined && i>0)continue;
            if(!sequence(stages,p,b,e))return false;
        }
        return true;
    }
    private static function sequence(stages:Object,p:Object,b:Object,e:Object):Boolean {
        if(!(stages instanceof Array) || stages.length<2 || stages.length>16 || stages[stages.length-1].kind!=="recover")return false;
        var sustained:Boolean=p.suppression!==undefined;
        var counts:Object={primary:0,dual:0,sub:0},warned:Object={primary:false,dual:false,sub:false};
        counts["throw"]=0;warned["throw"]=false;
        for(var i:Number=0;i<stages.length;i++){
            var stage:Object=stages[i],kind:String=stage.kind,mode:String=stage.mode;
            if(!keys(stage,"kind|mode|frames|lock|events|gap|direction|distance|stopDistance|pose|optional|minDistance|maxDistance|approaching|visible")
                || !member(kind,"warning|fire|wait|move|recover|charge|projectile_wait|mode_hold|draw")
                || !member(mode,"none|primary|dual|sub|throw") || !whole(stage.frames,1,180))return false;
            var bools:Array=["optional","approaching","visible"];
            for(var j:Number=0;j<bools.length;j++)if(stage[bools[j]]!==undefined && typeof stage[bools[j]]!="boolean")return false;
            if(stage.minDistance!==undefined && !whole(stage.minDistance,0,680)
                || stage.maxDistance!==undefined && !whole(stage.maxDistance,0,680)
                || stage.minDistance!==undefined && stage.maxDistance!==undefined && stage.minDistance>stage.maxDistance)return false;
            if(kind=="warning"){
                if(mode=="none" || !whole(stage.lock,0,stage.frames))return false;warned[mode]=true;
            }else if(kind=="fire"){
                if(mode=="none" || !warned[mode] || !whole(stage.events,1,sustained && mode=="primary"?60:8) || !whole(stage.gap,1,90))return false;
                if(sustained && mode=="primary" && (stage.events!==stage.frames || stage.gap!==1))return false;
                counts[mode]+=stage.events;
            }else if(kind=="draw"){
                if(mode=="none")return false;
            }else{
                if(mode!="none")return false;
                if(kind=="move" && (!member(stage.direction,"toward|away|lane") || !whole(stage.distance,1,480)
                    || stage.stopDistance!==undefined && !whole(stage.stopDistance,0,680)
                    || stage.pose!==undefined && !member(stage.pose,"primary|dual")))return false;
                if(kind=="charge" && !whole(stage.distance,1,120))return false;
            }
        }
        if(sustained && counts.primary>0 && (counts.primary!==60 || stages[stages.length-1].frames!==30))return false;
        if(counts.primary>b.primaryTriggerLimit || counts.dual>b.sidearmSynchronizedTriggerLimit
            || counts.sub>e.subweaponBurstLimit || counts["throw"]>e.finiteThrowableCount
            || !p.mixed && counts.dual>0 && (counts.primary>0 || counts.sub>0))return false;
        if(b.primaryFinalDamageUnitsPerAction!==undefined && (!whole(b.primaryFinalDamageUnitsPerAction,1,sustained?840:14)
            || b.primaryFinalDamageUnitsPerAction<b.primaryProjectilesPerAction))return false;
        var primaryUnits:Number=b.primaryFinalDamageUnitsPerAction===undefined?b.primarySplit:
            b.primaryFinalDamageUnitsPerAction/b.primaryTriggerLimit;
        var units:Number=counts.primary*primaryUnits+counts.sub*b.subweaponFinalDamageUnitsPerAction+counts["throw"]*2;
        var sidearmUnits:Number=counts.dual>0?counts.dual*b.sidearmProjectilesPerAction/b.sidearmSynchronizedTriggerLimit:0;
        var granted:Number=p.mixed?Math.max(units,sidearmUnits):units+sidearmUnits;
        units+=sidearmUnits;
        return units>0 && units<=b.scriptedCycleDamageUnits && granted<=b.maxGrantedDamageUnits && granted<=(sustained?900:14);
    }
    public static function valid(config:Object):Boolean {
        if(config.schema!=="cf6-fixed-roster.runtime.v1" || typeof config.version!="string" || config.version==""
            || config.counts.personnel!==158 || config.profiles==null || config.profiles instanceof Array
            || config.identities==null || config.identities instanceof Array)return false;
        var count:Number=0;
        for(var key:String in config.profiles){if(!profile(config.profiles[key]))return false;count++;}
        if(count<1 || count>158)return false;
        var people:Number=0,ordinary:Number=0,elite:Number=0,instructor:Number=0;
        for(var id:String in config.identities){
            var row:Object=config.identities[id],p:Object=config.profiles[row.profileId];people++;
            if(id.indexOf("CF6-")!==0 || p==null || !mapId(row.mapId) || !whole(row.startingPhase,1,2)
                || row.roleClass!==p.roleClass || typeof row.sourceSeat!="string" || row.sourceSeat=="")return false;
            if(row.roleClass=="ordinary")ordinary++;else if(row.roleClass=="elite")elite++;else instructor++;
        }
        return people===158 && ordinary===96 && elite===40 && instructor===22;
    }
}
