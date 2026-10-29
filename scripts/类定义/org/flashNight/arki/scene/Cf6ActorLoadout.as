import org.flashNight.arki.item.BaseItem;

/** Detached CF6 actor validation; no live player or save mutation. */
class org.flashNight.arki.scene.Cf6ActorLoadout {
    /** Build and validate detached initial state before clearing the origin character. */
    public static function prepare(routeId:String):Object {
        var config:Object=org.flashNight.arki.scene.BookDefinition.get("cf6-sting",routeId);
        if (!org.flashNight.arki.scene.BookDefinition.valid(config)) return null;
        var type61:Boolean=config.routeId === "type61";
        var quickSkills:Array=type61 ? config.actor.quickSkills : [];
        var equipment:Object={};
        var allowed:Object={头部装备:true,上装装备:true,下装装备:true,手部装备:true,脚部装备:true,颈部装备:true,刀:true,长枪:true,手枪:true,手枪2:true};
        for (var i:Number=0;i<config.actor.equipment.length;i++) {
            var source:Object=config.actor.equipment[i];
            if (allowed[source.slot] !== true) return null;
            var item:BaseItem=BaseItem.create(source.name,source.enhancement);
            var meta:Object=_root.getItemData(source.name);
            var itemLevel:Number=Number(meta.data.level);
            if (item == null || item.value.level !== (type61 ? 1 : 11) || isNaN(itemLevel) || !isFinite(itemLevel) || itemLevel>config.actor.level
                    || (meta.use !== source.slot && !(source.slot === "手枪2" && meta.use === "手枪"))) return null;
            equipment[source.slot]=item;
        }
        var skills:Array=new Array(80), passives:Object={};
        for (i=0;i<80;i++) skills[i]=["",0,false,"",true];
        for (i=0;i<config.actor.skills.length;i++) {
            var grant:Object=config.actor.skills[i];
            var skill:Object=_root.技能表对象[grant.name];
            if (skill == null || typeof skill.Type != "string" || !isFinite(grant.level) || isNaN(grant.level)
                    || !isFinite(Number(skill.MaxLevel)) || isNaN(Number(skill.MaxLevel)) || !(Number(skill.MaxLevel)>0)
                    || !isFinite(Number(skill.UnlockLevel)) || isNaN(Number(skill.UnlockLevel)) || !(Number(skill.UnlockLevel)>0)
                    || Math.floor(grant.level)!=grant.level || !(grant.level>0) || grant.level>Number(skill.MaxLevel)
                    || (!type61 && Number(skill.MaxLevel)!==grant.level) || Number(skill.UnlockLevel)>config.actor.level
                    || grant.name === "驾驶" || typeof skill.Equippable != "boolean" || typeof skill.Passive != "boolean") return null;
            var pure:Boolean=String(skill.Type) === "被动" || skill.Equippable === false;
            var equipped:Boolean=false;
            for (var q:Number=0;q<quickSkills.length;q++) if (quickSkills[q]===grant.name) {
                if (pure) return null;
                equipped=true;
            }
            skills[i]=[grant.name,grant.level,pure || equipped,skill.Type,pure || equipped];
            if (skill.Passive === true) passives[grant.name]={技能名:grant.name,等级:grant.level,启用:pure || equipped};
        }
        return {equipment:equipment,skills:skills,passives:passives,quickSkills:quickSkills};
    }

}
