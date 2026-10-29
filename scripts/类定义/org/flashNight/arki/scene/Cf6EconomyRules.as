/** CF6 per-run finite supply selection. Inventory and durable choice writes remain in existing services. */
class org.flashNight.arki.scene.Cf6EconomyRules {
    private static function whole(value, low:Number, high:Number):Boolean {
        return typeof value == "number" && isFinite(value) && !isNaN(value)
            && Math.floor(value) == value && !(value < low) && !(value > high);
    }
    private static function text(value):Boolean {
        return typeof value == "string" && value.length > 0 && value.length < 97;
    }
    private static function list(value, limit:Number):Boolean { return value instanceof Array && value.length <= limit; }
    private static function anchor(map:Object):Boolean {
        var x=map.stage.BasicInformation.PlayerX,y=map.stage.BasicInformation.PlayerY;
        return typeof x == "number" && typeof y == "number" && isFinite(x) && isFinite(y) && !isNaN(x) && !isNaN(y);
    }
    private static function names(row:Object, minimum:Number, reserved:Object, collect:Boolean):Boolean {
        if (!list(row.choices,16) || row.choices.length < minimum) return false;
        var seen:Object={};
        for (var i:Number=0;i<row.choices.length;i++) {
            var choice:Object=row.choices[i];
            if (!text(choice.weapon) || !text(choice.ammo) || !whole(choice.ammoCount,1,30)
                    || seen["w."+choice.weapon] === true || reserved["w."+choice.weapon] === true) return false;
            if (choice.weaponCount !== undefined && !whole(choice.weaponCount,1,collect ? 1 : 2)) return false;
            seen["w."+choice.weapon]=true;
        }
        if (collect) for (var name:String in seen) reserved[name]=true;
        return true;
    }
    private static function allEnemies(map:Object):Array {
        var result:Array=[];
        for (var w:Number=0;w<map.stage.Wave.SubWave.length;w++) {
            var enemies:Array=map.stage.Wave.SubWave[w].EnemyGroup.Enemy;
            for (var n:Number=0;n<enemies.length;n++) result.push(enemies[n]);
        }
        for (var g:Number=0;g<map.bossEncounter.groups.length;g++) {
            enemies=map.bossEncounter.groups[g].enemies;
            for (n=0;n<enemies.length;n++) result.push(enemies[n]);
        }
        for (g=0;g<map.bossEncounter.nextPhase.groups.length;g++) {
            enemies=map.bossEncounter.nextPhase.groups[g].enemies;
            for (n=0;n<enemies.length;n++) result.push(enemies[n]);
        }
        return result;
    }
    public static function valid(config:Object):Boolean {
        var economy:Object=config.economy;
        var type61:Boolean=config.routeId === "type61";
        if (economy == null) return true;
        if (!list(economy.randomWeapons,20) || !list(economy.eliteWeapons,5) || !list(economy.choices,20)) return false;
        var quotaMaps:Object={E1:"A09",E2:"A13",E3:"A14",E4:"A17",E5:"A19"};
        var maps:Object={}, markers:Object={}, reserved:Object={}, used:Object={};
        for (var m:Number=0;m<config.maps.length;m++) {
            var map:Object=config.maps[m]; maps["m."+map.id]=map;
            var enemies:Array=allEnemies(map);
            for (var e:Number=0;e<enemies.length;e++) {
                var enemy:Object=enemies[e], quota=enemy.Parameters.cf6EliteQuota;
                if (quota == undefined) continue;
                var soldier:Boolean=enemy.Type==="兵种466" || enemy.Type==="兵种467"
                    || type61 && (enemy.Type==="兵种478" || enemy.Type==="兵种479" || enemy.Type==="兵种480" || enemy.Type==="兵种481");
                if (quotaMaps[quota] !== map.id || markers[quota] != undefined
                        || enemy.Quantity !== 1 || !soldier) return false;
                markers[quota]=enemy;
            }
        }
        for (var q:Number=0;q<economy.eliteWeapons.length;q++) {
            var row:Object=economy.eliteWeapons[q];
            if (quotaMaps[row.quota] !== row.mapId || markers[row.quota] == undefined
                    || used[row.quota] === true || !anchor(maps["m."+row.mapId])
                    || !names(row,(row.quota === "E1" || row.quota === "E4") ? 1 : 2,reserved,true)) return false;
            used[row.quota]=true;
        }
        for (var marker:String in markers) if (used[marker] !== true) return false;
        var eliteReserved:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(reserved);
        used={};
        for (var r:Number=0;r<economy.randomWeapons.length;r++) {
            row=economy.randomWeapons[r];
            if (maps["m."+row.mapId] == undefined || used["m."+row.mapId] === true
                    || !anchor(maps["m."+row.mapId]) || !names(row,2,eliteReserved,false)) return false;
            used["m."+row.mapId]=true;
            for (var n:Number=0;n<row.choices.length;n++) reserved["w."+row.choices[n].weapon]=true;
        }
        used={};
        var pools:Array=org.flashNight.arki.item.ChoiceRewardDefinition.get();
        var maxed:Object={};
        for (var s:Number=0;s<config.actor.skills.length;s++) maxed["s."+config.actor.skills[s].name]=true;
        var choiceNames:Object={};
        for (var c:Number=0;c<economy.choices.length;c++) {
            row=economy.choices[c];
            if (maps["m."+row.mapId] == undefined || used["m."+row.mapId] === true || used["p."+row.poolId] === true
                    || !anchor(maps["m."+row.mapId]) || !text(row.itemName) || !text(row.poolId)) return false;
            var pool:Object=null;
            for (var p:Number=0;p<pools.length;p++) if (pools[p].id === row.poolId) pool=pools[p];
            if (pool == null || pool.itemName !== row.itemName || pool.scope.kind !== "book" || pool.scope.bookId !== "cf6-sting") return false;
            for (var g:Number=0;g<pool.groups.length;g++) {
                var group:Object=pool.groups[g];
                for (var b:Number=0;b<group.entries.length;b++) {
                    var bundle:Object=group.entries[b];
                    if (bundle.kCost !== 0) return false;
                    for (s=0;s<bundle.skills.length;s++) if (maxed["s."+bundle.skills[s].skillKey] === true) return false;
                    for (var d:Number=0;d<bundle.entries.length;d++) if (eliteReserved["w."+bundle.entries[d].itemName] === true) return false;
                }
            }
            used["m."+row.mapId]=true;used["p."+row.poolId]=true;choiceNames["p."+row.itemName]=true;
        }
        for (m=0;m<config.maps.length;m++) {
            map=config.maps[m];
            var pickups:Array=map.stage.Pickups.Pickup;
            for (p=0;p<pickups.length;p++) if (reserved["w."+pickups[p].Name] === true || choiceNames["p."+pickups[p].Name] === true) return false;
            enemies=allEnemies(map);
            for (e=0;e<enemies.length;e++) {
                enemy=enemies[e];
                var drops:Array=enemy.Parameters.掉落物;
                for (d=0;d<drops.length;d++) {
                    if (choiceNames["p."+drops[d].名字] === true) return false;
                    if (enemy.Parameters.cf6EliteQuota == undefined && reserved["w."+drops[d].名字] === true) return false;
                }
            }
        }
        return true;
    }
    private static function select(state:Object, choices:Array):Object {
        state.value=(state.value * 48271) % 2147483647;
        return choices[Math.floor(state.value / 2147483647 * choices.length)];
    }
    private static function drop(name:String, count:Number):Object {
        return {名字:name,概率:100,最小数量:count,最大数量:count,总数:count};
    }
    /** Always resolve the complete route before slicing startAt, keeping debug jumps reproducible. */
    public static function maps(config:Object, seed:Number):Array {
        var result:Array=[];
        for (var copied:Number=0;copied<config.maps.length;copied++)
            result.push(org.flashNight.gesh.object.PersistedSnapshot.clone(config.maps[copied]));
        if (config.economy == null) return result;
        var economy:Object=config.economy;
        var type61:Boolean=config.routeId === "type61";
        var state:Object={value:whole(seed,1,2147483646) ? seed : 1};
        for (var m:Number=0;m<result.length;m++) {
            var map:Object=result[m], stage:Object=map.stage;
            if (stage.Pickups == null) stage.Pickups={Pickup:[]};
            if (!(stage.Pickups.Pickup instanceof Array)) stage.Pickups.Pickup=[];
            var pickups:Array=stage.Pickups.Pickup;
            var x:Number=Number(stage.BasicInformation.PlayerX), y:Number=Number(stage.BasicInformation.PlayerY);
            if (!isFinite(x) || isNaN(x)) x=0;
            if (!isFinite(y) || isNaN(y)) y=0;
            for (var r:Number=0;r<economy.randomWeapons.length;r++) {
                var row:Object=economy.randomWeapons[r];
                if (row.mapId !== map.id) continue;
                var chosen:Object=select(state,row.choices);
                var count:Number=chosen.weaponCount === undefined ? 1 : chosen.weaponCount;
                var replacement=type61 && map.id === "A04" ? config.type61.a04ReplacementPacks[chosen.weapon] : undefined;
                if (typeof replacement == "string" && replacement != "") pickups.push({Name:replacement,Value:1,x:x,y:y});
                else for (var instance:Number=0;instance<count;instance++) pickups.push({Name:chosen.weapon,Value:1,x:x,y:y});
                if (!type61) pickups.push({Name:chosen.ammo,Value:chosen.ammoCount,x:x,y:y});
            }
            for (var q:Number=0;q<economy.eliteWeapons.length;q++) {
                row=economy.eliteWeapons[q];
                if (row.mapId !== map.id) continue;
                chosen=select(state,row.choices);
                var enemies:Array=allEnemies(map);
                for (var e:Number=0;e<enemies.length;e++) {
                    var enemy:Object=enemies[e];
                    if (enemy.Parameters.cf6EliteQuota !== row.quota) continue;
                    enemy.Parameters.长枪=chosen.weapon+"#1";
                    enemy.Parameters.不掉装备=true;
                    enemy.Parameters.掉落物=[drop(chosen.weapon,1)];
                    if (!type61) enemy.Parameters.掉落物.push(drop(chosen.ammo,chosen.ammoCount));
                }
            }
            for (var c:Number=0;c<economy.choices.length;c++) {
                row=economy.choices[c];
                if (row.mapId === map.id) pickups.push({Name:row.itemName,Value:1,x:x,y:y});
            }
            if (type61) {
                var carriers:Array=allEnemies(map);
                for (var t:Number=0;t<carriers.length;t++) if (carriers[t].Parameters.cf6Type61MidMod === true) {
                    if (!(carriers[t].Parameters.掉落物 instanceof Array)) carriers[t].Parameters.掉落物=[];
                    carriers[t].Parameters.掉落物.push(drop(String(select(state,config.type61.midMods)),1));
                }
            }
        }
        return result;
    }
}
