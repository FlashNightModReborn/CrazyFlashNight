import flash.filters.ColorMatrixFilter;
import flash.filters.GlowFilter;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.weather.NightVisionManager;
import org.flashNight.arki.weather.WeatherSystem;
/** Unit-owned visual layer. Never uses RGB keying, saves, Buff reset or health writes. */
class org.flashNight.arki.weather.NightVisionUnitTint {
    private static var _entries:Array = [];
    private static var _profile:Object = null;
    private static var _matrix:Array = null;
    private static var _filter:ColorMatrixFilter = null;
    private static var _glow:GlowFilter = null;
    private static var _glowSignature:Array = null;
    private static var _frame:Number = 0;

    public static function makeMatrix(p:Object):Array {
        var s:Number = Number(p.UnitStrength);
        if (isNaN(s) || !isFinite(s) || s <= 0 || s > 1) return null;
        var colors:Array = [Number(p.UnitRed),Number(p.UnitGreen),Number(p.UnitBlue)];
        var out:Array = [];
        var whiteHot:Boolean=p.UnitStyle=="whitehot";
        for (var c:Number=0; c<3; c++) {
            var tint:Number = colors[c];
            if (isNaN(tint) || !isFinite(tint) || tint < 0 || tint > 1) return null;
            if(whiteHot) {
                // White-hot is a neutral luminance shape, with a bright floor
                // even for black clothing. Material detail remains above it.
                var detail:Number=1-s*.90;
                out.push(detail*.2126);out.push(detail*.7152);out.push(detail*.0722);
                out.push(0);out.push(s*.90*255);
            } else {
                out.push(s*tint*.35*.2126+(c==0?1-s:0));
                out.push(s*tint*.35*.7152+(c==1?1-s:0));
                out.push(s*tint*.35*.0722+(c==2?1-s:0));
                out.push(0);out.push(s*tint*.65*255);
            }
        }
        out.push(0);out.push(0);out.push(0);out.push(1);out.push(0);
        return out;
    }
    /** Semantic silhouette, formed from character alpha before world grading.
     * This is an outer rim only: it does not replace material or hit colors. */
    public static function makeGlow(p:Object):GlowFilter {
        var strength:Number=Number(p.UnitOutlineStrength!=undefined?p.UnitOutlineStrength:p.EdgeStrength);
        var width:Number=Number(p.UnitOutlineWidth!=undefined?p.UnitOutlineWidth:p.EdgeWidth);
        var red:Number=Number(p.EdgeRed),green:Number=Number(p.EdgeGreen),blue:Number=Number(p.EdgeBlue);
        if(isNaN(strength) || !isFinite(strength) || !(strength>0) || strength>2
            || isNaN(width) || !isFinite(width) || width<.5 || width>3
            || isNaN(red) || red<0 || red>1 || isNaN(green) || green<0 || green>1
            || isNaN(blue) || blue<0 || blue>1) return null;
        var color:Number=(Math.round(red*255)<<16)|(Math.round(green*255)<<8)|Math.round(blue*255);
        // An explicit unit width is independent of the environment detector.
        // Strength above .8 concentrates the alpha rim so a dark costume still
        // has a visible boundary after denoising and the camera LUT. No fill.
        var concentration:Number=2+Math.max(0,strength-.8)*5;
        return new GlowFilter(color,Math.min(1,strength),width*1.8,width*1.8,concentration,1,false,false);
    }
    private static function matchesGlow(value:Object, signature:Array):Boolean {
        return signature!=null && value instanceof GlowFilter && value.color===signature[0]
            && value.alpha===signature[1] && value.blurX===signature[2] && value.blurY===signature[3]
            && value.strength===signature[4] && value.quality===1 && !value.inner && !value.knockout;
    }
    private static function matches(value:Object, matrix:Array):Boolean {
        if(matrix==null) return false;
        var values:Array = value.matrix;
        if (!(values instanceof Array) || values.length != 20) return false;
        for (var n:Number=0; n<20; n++) {
            var difference:Number = Number(values[n])-matrix[n];
            if (isNaN(difference) || difference > .0001 || difference < -.0001) return false;
        }
        return true;
    }
    private static function remove(entry:Object):Void {
        var body:MovieClip = entry.body;
        // AVM1 can redirect an unloaded MovieClip reference to a new same-path clip.
        if (body.__nightTintToken !== entry.token) return;
        var current:Array = body.filters;
        var kept:Array = [];
        var own:Number=entry.token.slot;
        if (!matches(current[own],entry.matrix)) {
            own=-1;
            for (var index:Number=current.length-1; index>=0; index--) {
                if (matches(current[index],entry.matrix)) {own=index;break;}
            }
        }
        var glowSlot:Number=entry.token.glowSlot;
        if(!matchesGlow(current[glowSlot],entry.glowSignature)) {
            glowSlot=-1;
            for(var indexGlow:Number=current.length-1; indexGlow>=0; indexGlow--) {
                if(matchesGlow(current[indexGlow],entry.glowSignature)){glowSlot=indexGlow;break;}
            }
        }
        for (var n:Number=0; n<current.length; n++) {
            if (n != own && n != glowSlot) kept.push(current[n]);
        }
        if (kept.length != current.length) body.filters = kept;
        delete body.__nightTintToken;
    }
    public static function clear():Void {
        var entries:Array = _entries;
        for (var n:Number=0; n<entries.length; n++) remove(entries[n]);
        entries.length=0; _profile=null; _matrix=null; _filter=null; _glow=null; _glowSignature=null;
    }
    private static function apply(unit:MovieClip):Void {
        var body:MovieClip = unit.man;
        if (!body || !unit._visible || unit.hp <= 0) return;
        // Tint the character art, never its ground shadow, health bars or world objects.
        var token:Object = body.__nightTintToken;
        if (token != null && token.profile === _profile) {
            token.seen=_frame;
            // Other effects may replace the filter list. Repair at a bounded cadence.
            if ((_frame & 7) != 0) return;
            var existing:Array=body.filters;
            var matrixFound:Boolean=_filter==null,glowFound:Boolean=_glow==null;
            for (var i:Number=existing.length-1; i>=0; i--) {
                if(!matrixFound && matches(existing[i],_matrix)){token.slot=i;matrixFound=true;}
                if(!glowFound && matchesGlow(existing[i],_glowSignature)){token.glowSlot=i;glowFound=true;}
            }
            if(matrixFound && glowFound) return;
            if(!matrixFound){token.slot=existing.length;existing.push(_filter);}
            if(!glowFound){token.glowSlot=existing.length;existing.push(_glow);}
            body.filters=existing;
            return;
        }
        var current:Array = body.filters;
        var slot:Number=-1,glowSlot:Number=-1;
        if(_filter!=null){slot=current.length;current.push(_filter);}
        if(_glow!=null){glowSlot=current.length;current.push(_glow);}
        body.filters=current;
        token={profile:_profile,seen:_frame,slot:slot,glowSlot:glowSlot};
        body.__nightTintToken=token;
        _global.ASSetPropFlags(body,["__nightTintToken"],1,false);
        _entries.push({body:body,token:token,matrix:_matrix,glowSignature:_glowSignature,unit:unit});
    }
    public static function syncUnits(profile:Object, units:Array, hero:MovieClip):Void {
        if (profile !== _profile) {
            clear(); _profile=profile;
            _matrix=profile != null ? makeMatrix(profile) : null;
            if (_matrix != null) _filter=new ColorMatrixFilter(_matrix);
            _glow=profile!=null?makeGlow(profile):null;
            if(_glow!=null)_glowSignature=[_glow.color,_glow.alpha,_glow.blurX,_glow.blurY,_glow.strength];
        }
        if (_filter == null && _glow == null) return;
        _frame++;
        apply(hero);
        for (var n:Number=0; n<units.length; n++) apply(units[n]);
        // Compact in place: corpses, unloaded art and removed units lose only our layer.
        var write:Number=0;
        for (n=0; n<_entries.length; n++) {
            var entry:Object=_entries[n];
            if (entry.token.seen === _frame && entry.body.__nightTintToken === entry.token)
                _entries[write++]=entry;
            else remove(entry);
        }
        _entries.length=write;
    }
    public static function tick():Void {
        var world:MovieClip=_root.gameworld;
        var hero:MovieClip=world[_root.控制目标];
        if (!hero || !_root.server.isSocketConnected || !_root.色彩引擎.视觉增强映射表
            || !org.flashNight.arki.render.WeatherParticleRenderer.hasNativeHost()) {
            if (_profile != null) clear();
            return;
        }
        var manager:NightVisionManager=WeatherSystem.getInstance().getNightVisionManager();
        var p:Object=null;
        if (_root.server.isSocketConnected && hero && manager.isActive()) {
            var cfg:Object=manager.getRegistered();
            p=_root.色彩引擎.视觉增强映射表[cfg.视觉情况];
            if (Number(p.Version) !== 1) p=null;
        }
        if (p == null || !(Number(p.UnitStrength) > 0 || Number(p.EdgeStrength) > 0 || Number(p.UnitOutlineStrength) > 0)) { if (_profile != null) clear(); return; }
        // Existing indexed roster, no full-world for-in scan or per-frame filter allocation.
        syncUnits(p,TargetCacheManager.getCachedAll(hero,4),hero);
    }
}
