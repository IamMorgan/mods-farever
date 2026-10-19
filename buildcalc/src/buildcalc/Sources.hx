package buildcalc;

/**
 * Where an item can be obtained right now, read from the game's own data:
 *  - drop: the items the Codex lists in its zones (data.CodexData.zones[].items), and the loot of every
 *    monster the Codex places in the world (zones[].units): its loot table, its unit type's, its boss and
 *    heroic tables, its gains and its faction's table (HItem.getFactionLootTable), followed through sub
 *    tables and loot containers (item props.gainItem); world loot (item flag WorldLoot);
 *  - craft: the item is made by a recipe (Data.craft: its item, or the items of its loot table);
 *  - the hero's own items (worn, in the bag, the mail, every bank tab: st.Loadout.getAllInventories).
 * Items with none of these sources cannot be obtained now and are left out of the calculation.
 */
class Sources {
    static var drop:Map<String, String> = null;   // item -> where (for the log)
    static var craft:Map<String, String> = null;
    static var own:Map<String, Bool> = null;
    /** The hero's real items that are not worn (bag, mail, bank), as they are. */
    public static var ownItems:Array<Dynamic> = [];
    static var tables:Dynamic;
    /**
     * The level an item's way of dropping asks for: the lowest, over the ways the item drops, of the highest of the
     * killed monster's level (a real monster, not an NPC) and the minimum level (minLvl) of the loot entries on the
     * way. Ways with no level (world loot, codex lists, recipes) ask for none.
     */
    static var dropReq:Map<String, Int> = new Map();
    /** The level the way being followed asks for (see dropReq). */
    static var ctxReq = 0;
    /** Monsters above this level are no monsters of the levelling world (NPCs are level 100). */
    static inline var MAX_MOB_LEVEL = 25;
    /** The hero's level (0: unknown, the level is not looked at). */
    static var heroLevel = 0;

    static function list(v:Dynamic):Dynamic {
        var a = G.field(v, "array");
        return a != null && G.len(a) > 0 ? a : v;
    }

    static function table(ref:Dynamic):Dynamic {
        if (ref == null) return null;
        if (Std.isOfType(ref, String)) return (ref : String) == "" ? null : G.call("haxe.ds.StringMap", "get", [G.field(tables, "byId"), ref]);
        return ref;
    }

    static var seenTables:Map<String, Int>;

    static function addTable(t:Dynamic, into:Map<String, String>, where:String):Void {
        if (t == null) return;
        var tid = G.str(G.field(t, "id"));
        var key = tid + "|" + (into == craft ? "c" : "d");
        // a table is followed again when it is reached by a way that asks for less
        var req = into == craft ? 0 : ctxReq;
        if (tid != "" && seenTables.exists(key) && seenTables.get(key) <= req) return;
        if (tid != "") seenTables.set(key, req);
        var loot = G.field(t, "loot");
        var outer = ctxReq;
        for (i in 0...G.len(loot)) {
            var e = G.at(loot, i);
            if (into != craft) ctxReq = Std.int(Math.max(outer, G.num(G.field(e, "minLvl"))));
            addItem(GameData.idOf(G.field(e, "item")), into, where + (tid != "" ? "/" + tid : ""));
            addTable(table(G.field(e, "lootTable")), into, where);
        }
        ctxReq = outer;
    }

    static var items:Dynamic;

    static function addItem(id:String, into:Map<String, String>, where:String):Void {
        if (id == "") return;
        var improved = false;
        if (into != craft) {
            var cur = dropReq.get(id);
            if (cur == null || ctxReq < cur) { dropReq.set(id, ctxReq); improved = true; }
        }
        if (into.exists(id) && !improved) return;
        if (!into.exists(id)) into.set(id, where);
        // a loot container (e.g. a gear cache): what it gives
        var inf = G.call("haxe.ds.StringMap", "get", [G.field(items, "byId"), id]);
        var gain = G.field(G.field(inf, "props"), "gainItem");
        if (gain != null) addTable(table(G.field(gain, "lootTable")), into, where + ">" + id);
    }

    static function addUnit(unit:Dynamic):Void {
        if (unit == null) return;
        if (G.typeName(unit) == "String") unit = G.call("haxe.ds.StringMap", "get", [G.field(GameData.data("unit"), "byId"), Std.string(unit)]);
        var uid = G.str(G.field(unit, "id"));
        if (uid == "" || seenUnits.exists(uid)) return;
        seenUnits.set(uid, true);
        var props = G.field(unit, "props");
        var lvl = Std.int(G.num(G.field(unit, "lvl")));
        var outer = ctxReq;
        ctxReq = lvl > 0 && lvl <= MAX_MOB_LEVEL ? lvl : 0;
        for (name in ["lootTable", "bossLootTable", "heroicLootTable"]) addTable(table(G.field(props, name)), drop, uid);
        var type = G.call("haxe.ds.StringMap", "get", [G.field(GameData.data("unitType"), "byId"), G.str(G.field(unit, "type"))]);
        addTable(table(G.field(type, "lootTable")), drop, uid);
        var gains = G.field(props, "gains");
        if (gains != null) {
            addTable(table(G.field(gains, "lootTable")), drop, uid);
            var lts = G.field(gains, "lootTables");
            for (i in 0...G.len(lts)) addTable(table(G.field(G.at(lts, i), "ref")), drop, uid);
            var given = G.field(gains, "items");
            for (i in 0...G.len(given)) {
                var g = G.at(given, i);
                addItem(Std.isOfType(g, String) ? g : GameData.idOf(G.field(g, "item")), drop, uid);
            }
        }
        var faction = G.str(G.field(unit, "faction"));
        if (faction != "") try {
            var f = G.call("haxe.ds.StringMap", "get", [G.field(GameData.data("faction"), "byId"), faction]);
            if (f != null) addTable(G.callStatic("HItem", "getFactionLootTable", [f, false]), drop, uid + ":" + faction);
        } catch (_:Dynamic) {}
        ctxReq = outer;
    }

    static var seenUnits:Map<String, Bool>;

    public static function build(?hero:Dynamic):Void {
        if (drop == null) {
            drop = new Map();
            craft = new Map();
            seenTables = new Map();
            seenUnits = new Map();
            tables = GameData.data("lootTable");
            items = GameData.data("item");
            try {
                var codex = G.type("data.CodexData");
                var zones = list(HlxRuntime.resolveStaticField(codex, "zones"));
                var listed = 0;
                for (z in 0...G.len(zones)) {
                    var zone = G.at(zones, z);
                    var zi = G.field(zone, "items");
                    for (i in 0...G.len(zi)) {
                        var id = G.str(G.field(G.at(zi, i), "id"));
                        if (id != "" && !drop.exists(id)) { drop.set(id, "codex"); listed++; }
                    }
                    var units = G.field(zone, "units");
                    for (i in 0...G.len(units)) {
                        var u = G.at(units, i);
                        var unit = G.field(u, "unit");
                        addUnit(unit != null ? unit : u);
                    }
                }
                // the Codex's full monster list may hold monsters not in the world now: only logged
                var monsters = list(HlxRuntime.resolveStaticField(codex, "allMonsters"));
                var notPlaced = [];
                for (i in 0...G.len(monsters)) {
                    var u:Dynamic = G.at(monsters, i);
                    var unit:Dynamic = G.field(u, "unit");
                    if (unit == null) unit = u;
                    var uid = G.typeName(unit) == "String" ? Std.string(unit) : G.str(G.field(unit, "id"));
                    if (uid != "" && !seenUnits.exists(uid)) notPlaced.push(uid);
                }
                DebugLog.line("sources: Codex monsters not in a zone (their loot is not counted): " + notPlaced.join(","));
                DebugLog.line("sources: codex zones " + G.len(zones) + " list " + listed + " items; " + Lambda.count(seenUnits)
                    + " monsters of the world; " + Lambda.count(drop) + " items drop");
            } catch (e:Dynamic) DebugLog.error("sources: codex", e);
            // loot tables that no unit, table, recipe or item of the data refers to: the maps' own objects
            // (rift rewards, chests, activities) roll them, so their items can be obtained
            try {
                var used = new Map<String, Bool>();
                function mark(v:Dynamic):Void {
                    var id = G.typeName(v) == "String" ? Std.string(v) : G.str(G.field(v, "id"));
                    if (id != "") used.set(id, true);
                }
                var allTables = G.field(tables, "all");
                for (i in 0...G.len(allTables)) {
                    var loot = G.field(G.at(allTables, i), "loot");
                    for (k in 0...G.len(loot)) { var t = G.field(G.at(loot, k), "lootTable"); if (t != null) mark(t); }
                }
                var units = G.field(GameData.data("unit"), "all");
                for (i in 0...G.len(units)) {
                    var p = G.field(G.at(units, i), "props");
                    for (name in ["lootTable", "bossLootTable", "heroicLootTable"]) { var t = G.field(p, name); if (t != null) mark(t); }
                    var gains = G.field(p, "gains");
                    if (gains != null) {
                        var t = G.field(gains, "lootTable");
                        if (t != null) mark(t);
                        var lts = G.field(gains, "lootTables");
                        for (k in 0...G.len(lts)) { var r = G.field(G.at(lts, k), "ref"); if (r != null) mark(r); }
                    }
                }
                var types = G.field(GameData.data("unitType"), "all");
                for (i in 0...G.len(types)) { var t = G.field(G.at(types, i), "lootTable"); if (t != null) mark(t); }
                var crafts = G.field(GameData.data("craft"), "all");
                for (i in 0...G.len(crafts)) { var t = G.field(G.at(crafts, i), "loot"); if (t != null) mark(t); }
                var allItems = G.field(items, "all");
                for (i in 0...G.len(allItems)) {
                    var g = G.field(G.field(G.at(allItems, i), "props"), "gainItem");
                    if (g != null) { var t = G.field(g, "lootTable"); if (t != null) mark(t); }
                }
                // every loot table of the game is a way to obtain its items: the ones the data refers to (monsters,
                // recipes, containers), the maps' own objects (chests, rifts, activities) and the containers the game's
                // code gives (HM_Demon_Cache_25 -> HM_DemonGear: demon gear), which no data refers to
                var orphans = [];
                for (i in 0...G.len(allTables)) {
                    var t = G.at(allTables, i);
                    var id = G.str(G.field(t, "id"));
                    if (id == "") continue;
                    if (!used.exists(id)) orphans.push(id);
                    // a table something refers to (a monster of another place…) asks the highest level of a monster unless a way
                    // above gave it a lower one; a map object's table (chest, rift, activity) asks none
                    ctxReq = used.exists(id) ? MAX_MOB_LEVEL : 0;
                    addTable(t, drop, (used.exists(id) ? "table:" : "map:") + id);
                    ctxReq = 0;
                }
                // loot containers (items with props.gainItem: Hero Weapon Cache, Hero Gear Cache, rift caches…): their
                // table, whoever gives the container; their items are logged
                var caches = [];
                for (i in 0...G.len(allItems)) {
                    var it = G.at(allItems, i);
                    var g = G.field(G.field(it, "props"), "gainItem");
                    if (g == null) continue;
                    var cid = G.str(G.field(it, "id"));
                    var t = table(G.field(g, "lootTable"));
                    addTable(t, drop, "container:" + cid);
                    var given = [];
                    function walk(t:Dynamic, depth:Int):Void {
                        if (t == null || depth > 4) return;
                        var loot = G.field(t, "loot");
                        for (k in 0...G.len(loot)) {
                            var e = G.at(loot, k);
                            var id = GameData.idOf(G.field(e, "item"));
                            if (id != "") given.push(id);
                            walk(table(G.field(e, "lootTable")), depth + 1);
                        }
                    }
                    walk(t, 0);
                    caches.push(cid + " -> " + given.join(","));
                }
                DebugLog.line("sources: loot containers (all their items count): " + caches.join("; "));
                DebugLog.line("sources: every loot table counts (" + G.len(allTables) + "); not referred to by data (map objects, code): " + orphans.join(","));
            } catch (e:Dynamic) DebugLog.error("sources: map tables", e);
            // world loot: item flag "WorldLoot", its bit read from the game's flag definition
            var flag = 2;
            try {
                var v = HlxRuntime.resolveStaticField(G.type("_Data.Item_flags_Impl_"), "WorldLoot");
                if (v != null) flag = 1 << Std.int(G.num(v));
            } catch (_:Dynamic) {}
            var all = G.field(items, "all");
            var world = 0;
            for (i in 0...G.len(all)) {
                var it = G.at(all, i);
                if ((Std.int(G.num(G.field(it, "flags"))) & flag) != 0) { addItem(G.str(G.field(it, "id")), drop, "world loot"); world++; }
            }
            try {
                var crafts = G.field(GameData.data("craft"), "all");
                for (i in 0...G.len(crafts)) {
                    var c = G.at(crafts, i);
                    addItem(GameData.idOf(G.field(c, "item")), craft, "recipe");
                    addTable(table(G.field(c, "loot")), craft, "recipe");
                }
                DebugLog.line("sources: " + G.len(crafts) + " recipes give " + Lambda.count(craft) + " items; world loot items " + world);
                var asking = [for (id => r in dropReq) if (r > 0 && !craft.exists(id)) r];
                DebugLog.line("sources: " + asking.length + " items drop only from level " + (asking.length > 0 ? Std.string(Lambda.fold(asking, (r, m) -> Std.int(Math.min(r, m)), 1000)) : "-") + " up");
            } catch (e:Dynamic) DebugLog.error("sources: recipes", e);
        }
        if (hero != null) {
            heroLevel = Std.int(G.num(G.field(hero, "_level")));
            own = new Map();
            ownItems = [];
            // st.Loadout.getAllInventories: equipment, bag, mail, then every bank tab
            try {
                var invs = G.call("st.Loadout", "getAllInventories", [G.field(hero, "loadout")]);
                var counts = [];
                for (k in 0...G.len(invs)) {
                    var inv = G.at(invs, k);
                    if (inv == null) continue;
                    var content = G.field(inv, "content");
                    var n = 0;
                    for (i in 0...G.len(content)) {
                        var entry = G.at(content, i);
                        var item = entry == null ? null : G.field(entry, "item");
                        if (item == null) continue;
                        own.set(G.str(G.field(G.field(item, "inf"), "id")), true);
                        if (k > 0) ownItems.push(item); // 0 is the equipment (worn: its own candidates)
                        n++;
                    }
                    counts.push(n);
                }
                DebugLog.line("sources: the hero's items per inventory (equipment, bag, mail, bank tabs…): " + counts.join(", "));
            } catch (e:Dynamic) DebugLog.error("sources: inventories", e);
        }
    }

    public static function isDrop(id:String):Bool { build(); return drop.exists(id); }
    public static function isCraft(id:String):Bool { build(); return craft.exists(id); }
    public static function isOwn(id:String):Bool return own != null && own.exists(id);
    /** The item drops somewhere the hero's level reaches (see dropReq). */
    static function dropsAtLevel(id:String):Bool {
        if (!isDrop(id)) return false;
        var req = dropReq.get(id);
        return heroLevel <= 0 || req == null || req <= heroLevel;
    }

    public static function available(id:String):Bool return dropsAtLevel(id) || isCraft(id) || (own != null && own.exists(id));

    /** Where the item comes from (for the log). */
    public static function where(id:String):String {
        build();
        if (craft.exists(id)) return "craft " + craft.get(id);
        if (drop.exists(id)) return "drop " + drop.get(id) + (dropReq.exists(id) && dropReq.get(id) > 0 ? " from level " + dropReq.get(id) : "");
        return own != null && own.exists(id) ? "hero's own" : "-";
    }

    /** Where the hero's real item is: shown on the cell of an owned item. */
    public static function ownLabel():String return Texts.ownLabel();

    /** "craft", "drop" or "" (shown on the item's cell). */
    public static function label(id:String):String return isCraft(id) ? Texts.craftLabel() : (dropsAtLevel(id) ? Texts.dropLabel() : "");
}
