package codexloot;

/**
 * Works out which items a monster can drop and with what chance, the way the game does it
 * (see Unit.getLootFromUnit and LootTable.generateLootTable in the game's code):
 *  - tables: the unit's own loot table, its unit type's loot table, plus FoeUniqueDrops (flag 64) / FoeEliteDrops (flag 8);
 *  - an entry is skipped when the monster's level is outside minLvl..maxLvl, or when its `conds`
 *    differs from the monster's (2 for unique/elite/flagged monsters, otherwise 1);
 *  - a table with flag 1 picks one entry by weight (chance = proba / sum of proba), any other table
 *    rolls every entry on its own (chance = proba); sub-tables multiply the chances.
 */
class LootCalc {
    static var tables:Map<String, Dynamic>;
    static var items:Map<String, Dynamic>;
    static var types:Map<String, Dynamic>;

    static function index(sheet:String):Map<String, Dynamic> {
        var m = new Map<String, Dynamic>();
        var idx:Dynamic = HlxRuntime.resolveStaticField(HlxRuntime.resolveType("Data"), sheet);
        var all = G.field(idx, "all");
        for (i in 0...G.len(all)) {
            var rec = G.at(all, i);
            var id = G.str(G.field(rec, "id"));
            if (id != "") m.set(id, rec);
        }
        return m;
    }

    static var result:Map<String, Float>;
    static var unitMin:Null<Float>;
    static var unitMax:Null<Float>;
    static var unitConds:Int;
    static var ignoreConds:Bool;

    static function optional(obj:Dynamic, name:String):Null<Float> {
        var v = G.field(obj, name);
        return v == null ? null : G.num(v);
    }

    static function passes(entry:Dynamic):Bool {
        var minL = optional(entry, "minLvl");
        var maxL = optional(entry, "maxLvl");
        if (minL != null && unitMax != null && minL > unitMax) return false;
        if (maxL != null && unitMin != null && maxL < unitMin) return false;
        var c = optional(entry, "conds");
        if (!ignoreConds && c != null && c != 0 && Std.int(c) != unitConds) return false;
        return true;
    }

    static function add(item:String, p:Float):Void {
        var old = result.exists(item) ? result.get(item) : 0.0;
        result.set(item, 1.0 - (1.0 - old) * (1.0 - p));
    }

    static function walk(table:Dynamic, mult:Float, depth:Int):Void {
        if (table == null || depth > 6) return;
        var loot = G.field(table, "loot");
        var rows:Array<Dynamic> = [];
        for (i in 0...G.len(loot)) {
            var e = G.at(loot, i);
            if (e != null && passes(e)) rows.push(e);
        }
        var weighted = (Std.int(G.num(G.field(table, "flags"))) & 1) != 0;
        var total = 0.0;
        for (e in rows) total += G.num(G.field(e, "proba"));
        for (e in rows) {
            var proba = G.num(G.field(e, "proba"));
            var p = weighted ? (total > 0 ? proba / total : 0.0) : Math.min(1.0, proba);
            var chance = mult * p;
            if (chance <= 0) continue;
            var item = G.str(G.field(e, "item"));
            if (item != "") add(item, chance);
            var sub = G.str(G.field(e, "lootTable"));
            if (sub != "") walk(tables.get(sub), chance, depth + 1);
        }
    }

    public static function item(id:String):Dynamic {
        if (items == null) items = index("item");
        return items.get(id);
    }

    static function collect(roots:Array<String>, ignore:Bool):Array<LootEntry> {
        result = new Map<String, Float>();
        ignoreConds = ignore;
        for (r in roots) walk(tables.get(r), 1.0, 0);
        ignoreConds = false;
        var out:Array<LootEntry> = [];
        for (id => chance in result) {
            var rec = items.get(id);
            if (rec != null && G.field(rec, "gfx") != null) out.push({item: rec, chance: chance});
        }
        out.sort((a, b) -> a.chance > b.chance ? -1 : (a.chance < b.chance ? 1 : 0));
        return out;
    }

    /**
     * The monster's drops, most likely first: `normal` (open world / normal dungeon) and `heroic`
     * (the table the game uses for heroic mode). Only items that have an icon are returned.
     */
    public static function compute(unit:Dynamic, filterByLevel:Bool):{normal:Array<LootEntry>, heroic:Array<LootEntry>} {
        if (tables == null) tables = index("lootTable");
        if (items == null) items = index("item");
        if (types == null) types = index("unitType");

        var flags = Std.int(G.num(G.field(unit, "flags")));
        unitConds = (flags & (64 | 8 | 16)) != 0 ? 2 : 1;
        unitMin = null;
        unitMax = null;
        if (filterByLevel) {
            var lvl = optional(unit, "lvl");
            var maxLvl = optional(unit, "maxLvl");
            unitMin = lvl != null ? lvl : maxLvl;
            unitMax = maxLvl != null ? maxLvl : lvl;
        }

        var props = G.field(unit, "props");
        var roots:Array<String> = [];
        var own = G.str(G.field(props, "lootTable"));
        if (own != "") roots.push(own);
        var type = types.get(G.str(G.field(unit, "type")));
        var typeTable = G.str(G.field(type, "lootTable"));
        if (typeTable != "") roots.push(typeTable);
        if ((flags & 64) != 0) roots.push("FoeUniqueDrops");
        if ((flags & 8) != 0) roots.push("FoeEliteDrops");
        // the Codex itself adds the boss table for units with flag 16 (see CodexData.buildZoneData)
        var bossRoots:Array<String> = [];
        var bossTable = G.str(G.field(props, "bossLootTable"));
        if (bossTable != "" && (flags & 16) != 0) bossRoots.push(bossTable);
        var heroicTable = G.str(G.field(props, "heroicLootTable"));

        var normal = collect(roots, false);
        if (bossRoots.length > 0) {
            // boss tables: their entries may carry other `conds` values, so those are not used to filter here
            var boss = collect(bossRoots, true);
            for (b in boss) {
                var known = false;
                for (n in normal) if (G.str(G.field(n.item, "id")) == G.str(G.field(b.item, "id"))) { known = true; break; }
                if (!known) normal.push(b);
            }
        }
        var heroic = heroicTable == "" ? [] : collect([heroicTable], true);
        return {normal: normal, heroic: heroic};
    }
}

typedef LootEntry = {item:Dynamic, chance:Float}
