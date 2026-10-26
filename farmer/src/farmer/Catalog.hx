package farmer;

import farmer.GameAccess as G;

/** A resource item the player can ask for: the game's item record and what it is. */
typedef Res = {id:String, item:Dynamic, rarity:String, level:Int};

/**
 * The resources of the game, read from its data sheets (nothing is listed by hand):
 *  - `gather`: crafting items that the ore and plant nodes (Data.gatherable) give;
 *  - `hunt`: crafting items that monsters (Data.unit) drop.
 * An item is a resource when its item type is a crafting component, an upgrade component or a prospecting item.
 * The loot tables are followed the way the game does it (nested tables, the `conds` bit of the monster and the level range of a
 * row, see codexloot's LootCalc), so `unitItems` tells which resources a given monster can drop.
 */
class Catalog {
    public static var gather:Array<Res> = [];
    public static var hunt:Array<Res> = [];
    public static var ready = false;

    static var items:Map<String, Dynamic> = new Map();
    static var tables:Map<String, Dynamic> = new Map();
    static var itemTypes:Map<String, Dynamic> = new Map();
    static var unitTypes:Map<String, Dynamic> = new Map();
    static var resourceCache:Map<String, Bool> = new Map();
    static var unitCache:Map<String, Map<String, Bool>> = new Map();
    static var gatherCache:Map<String, Map<String, Bool>> = new Map();

    static inline var FLAG_ELITE = 3;
    static inline var FLAG_BOSS = 4;
    static inline var FLAG_UNIQUE = 6;

    static function index(sheet:String):Map<String, Dynamic> {
        var m = new Map<String, Dynamic>();
        for (rec in G.sheet(sheet)) {
            var id = G.s(G.field(rec, "id"));
            if (id != "") m.set(id, rec);
        }
        return m;
    }

    public static function item(id:String):Dynamic return items.get(id);

    /** Reads the sheets once the game has loaded them (the item sheet is empty before that). */
    public static function build():Bool {
        if (ready) return true;
        items = index("item");
        if (!items.keys().hasNext()) return false;
        tables = index("lootTable");
        itemTypes = index("itemType");
        unitTypes = index("unitType");
        resourceCache = new Map();
        unitCache = new Map();
        gatherCache = new Map();

        var gathered = new Map<String, Bool>();
        for (rec in G.sheet("gatherable")) {
            var found = gatherItems(rec);
            for (id in found.keys()) gathered.set(id, true);
        }
        var hunted = new Map<String, Bool>();
        for (rec in G.sheet("unit")) {
            if (isBoss(rec)) continue;
            for (id in unitItems(rec).keys()) hunted.set(id, true);
        }
        gather = [];
        hunt = [];
        for (rec in G.sheet("item")) {
            var id = G.s(G.field(rec, "id"));
            var entry:Res = {id: id, item: rec, rarity: G.s(G.field(rec, "rarity")), level: G.integer(G.field(rec, "level"))};
            if (gathered.exists(id)) gather.push(entry);
            if (hunted.exists(id)) hunt.push(entry);
        }
        ready = true;
        return true;
    }

    /** Crafting component, upgrade component or prospecting item with an icon. */
    public static function isResource(id:String):Bool {
        var known = resourceCache.get(id);
        if (known != null) return known;
        var result = false;
        var rec = items.get(id);
        if (rec != null && G.field(rec, "gfx") != null) {
            var typeId = G.s(G.field(rec, "type"));
            var guard = 0;
            while (typeId != "" && guard++ < 12) {
                if (typeId == "CraftingComponent" || typeId == "UpgradeComponent" || typeId == "Prospecting") { result = true; break; }
                typeId = G.s(G.field(itemTypes.get(typeId), "inherit"));
            }
        }
        resourceCache.set(id, result);
        return result;
    }

    // ---- loot tables ----

    static function optional(obj:Dynamic, name:String):Null<Float> {
        var v = G.field(obj, name);
        return v == null ? null : G.number(v);
    }

    /** The resource items a loot table can give, for a monster with the given `conds` bit and level range (null: no level filter). */
    static function walk(table:Dynamic, conds:Int, lo:Null<Float>, hi:Null<Float>, out:Map<String, Bool>, seen:Map<String, Bool>, depth:Int):Void {
        if (table == null || depth > 8) return;
        var tableId = G.s(G.field(table, "id"));
        if (tableId != "") {
            if (seen.exists(tableId)) return;
            seen.set(tableId, true);
        }
        var loot = G.field(table, "loot");
        for (i in 0...G.len(loot)) {
            var row = G.at(loot, i);
            if (row == null) continue;
            var c = optional(row, "conds");
            if (conds > 0 && c != null && (Std.int(c) & conds) == 0) continue;
            if (lo != null || hi != null) {
                var minL = optional(row, "minLvl");
                var maxL = optional(row, "maxLvl");
                if (minL == null && (G.integer(G.field(row, "flags")) & 4) == 0) {
                    var it = items.get(G.s(G.field(row, "item")));
                    if (it != null) minL = optional(it, "level");
                }
                if (minL != null && hi != null && minL > hi) continue;
                if (maxL != null && lo != null && maxL < lo) continue;
            }
            var itemId = G.s(G.field(row, "item"));
            if (itemId != "" && isResource(itemId)) out.set(itemId, true);
            var sub = G.s(G.field(row, "lootTable"));
            if (sub != "") walk(tables.get(sub), conds, lo, hi, out, seen, depth + 1);
        }
    }

    // ---- ore and plant nodes ----

    /** The resources a gatherable (data record) gives, by its loot and hit-loot tables (inherited ones included). */
    public static function gatherItems(rec:Dynamic):Map<String, Bool> {
        var id = G.s(G.field(rec, "id"));
        var cached = gatherCache.get(id);
        if (cached != null) return cached;
        var out = new Map<String, Bool>();
        gatherCache.set(id, out);
        for (getter in ["get_loot", "get_hitLoot"]) {
            try {
                var table = G.staticCall("_Data.Gatherable_Impl_", getter, [rec]);
                if (table != null) walk(Std.isOfType(table, String) ? tables.get(G.s(table)) : table, 0, null, null, out, new Map(), 0);
            } catch (_:Dynamic) {}
        }
        return out;
    }

    static var gatherIndex:Map<String, Dynamic> = null;

    /** The data record of a gatherable by id (null: unknown). */
    public static function gatherable(id:String):Dynamic {
        if (gatherIndex == null || !gatherIndex.keys().hasNext()) gatherIndex = index("gatherable");
        return gatherIndex.get(id);
    }

    /** Ore (`GearPickaxe`) or plant (`GearSickle`): the tool a gatherable needs, "" when it is none of them. */
    public static function toolOf(rec:Dynamic):String {
        var current = rec;
        var guard = 0;
        var gatherables = index("gatherable");
        while (current != null && guard++ < 10) {
            var tool = G.s(G.field(current, "requiredTool"));
            if (tool != "") return tool;
            var parent = G.s(G.field(current, "inherit"));
            if (parent == "") break;
            current = gatherables.get(parent);
        }
        return "";
    }

    // ---- monsters ----

    public static function flagSet(unit:Dynamic, bit:Int):Bool return (G.integer(G.field(unit, "flags")) & (1 << bit)) != 0;

    public static function isBoss(unit:Dynamic):Bool return flagSet(unit, FLAG_BOSS);

    /** The resources a monster (data record) can drop. */
    public static function unitItems(unit:Dynamic):Map<String, Bool> {
        var id = G.s(G.field(unit, "id"));
        var cached = unitCache.get(id);
        if (cached != null) return cached;
        var out = new Map<String, Bool>();
        unitCache.set(id, out);
        var conds = flagSet(unit, FLAG_ELITE) || flagSet(unit, FLAG_UNIQUE) || flagSet(unit, FLAG_BOSS) ? 2 : 1;
        var lvl = optional(unit, "lvl"), maxLvl = optional(unit, "maxLvl");
        var lo = lvl != null ? lvl : maxLvl, hi = maxLvl != null ? maxLvl : lvl;
        var seen = new Map<String, Bool>();
        var props = G.field(unit, "props");
        var roots:Array<String> = [];
        var own = G.s(G.field(props, "lootTable"));
        if (own != "") roots.push(own);
        var type = unitTypes.get(G.s(G.field(unit, "type")));
        var typeTable = G.s(G.field(type, "lootTable"));
        if (typeTable != "") roots.push(typeTable);
        if (flagSet(unit, FLAG_UNIQUE)) roots.push("FoeUniqueDrops");
        if (flagSet(unit, FLAG_ELITE)) roots.push("FoeEliteDrops");
        for (r in roots) walk(tables.get(r), conds, lo, hi, out, seen, 0);
        var gains = G.field(props, "gains");
        if (gains != null) {
            var gainTable = G.s(G.field(gains, "lootTable"));
            if (gainTable != "") walk(tables.get(gainTable), conds, lo, hi, out, seen, 0);
            var list = G.field(gains, "lootTables");
            for (i in 0...G.len(list)) {
                var ref = G.s(G.field(G.at(list, i), "ref"));
                if (ref != "") walk(tables.get(ref), conds, lo, hi, out, seen, 0);
            }
            var given = G.field(gains, "items");
            for (i in 0...G.len(given)) {
                var e = G.at(given, i);
                var itemId = Std.isOfType(e, String) ? (e : String) : G.s(G.field(e, "item"));
                if (itemId != "" && isResource(itemId)) out.set(itemId, true);
            }
        }
        return out;
    }

    /** The levels of the (non-boss) monsters that can drop any of `wanted`, sorted. */
    public static function dropLevels(wanted:Array<String>):Array<Int> {
        var seen:Map<Int, Bool> = new Map();
        for (rec in G.sheet("unit")) {
            if (isBoss(rec)) continue;
            var items = unitItems(rec);
            var hit = false;
            for (id in wanted) if (items.exists(id)) { hit = true; break; }
            if (!hit) continue;
            var l = optional(rec, "lvl");
            if (l == null) l = optional(rec, "maxLvl");
            if (l != null) seen.set(Std.int(l), true);
        }
        var out = [for (l in seen.keys()) l];
        out.sort((a, b) -> a - b);
        return out;
    }

    /** The ids of the (non-boss) monsters that can drop any of the wanted items. */
    public static function dropUnits(wanted:Array<String>):Array<String> {
        var out = [];
        for (rec in G.sheet("unit")) {
            if (isBoss(rec)) continue;
            var items = unitItems(rec);
            for (id in wanted) if (items.exists(id)) { out.push(G.s(G.field(rec, "id"))); break; }
        }
        return out;
    }

    /** The ids of the (non-boss) fighting monsters whose level range reaches into lo..hi (a spawn's level is drawn from lvl..maxLvl). */
    public static function unitsOfLevels(lo:Int, hi:Int):Array<String> {
        var out = [];
        for (rec in G.sheet("unit")) {
            if (isBoss(rec)) continue;
            var type = G.s(G.field(rec, "type"));
            if (type == "Environment" || type == "Critter") continue;
            var l = optional(rec, "lvl"), m = optional(rec, "maxLvl");
            if (l == null && m == null) continue;
            var from = l != null ? l : m, to = m != null ? m : l;
            if (to >= lo && from <= hi) out.push(G.s(G.field(rec, "id")));
        }
        return out;
    }

    static var unitRecords:Map<String, Dynamic>;

    public static function unitRecord(id:String):Dynamic {
        if (unitRecords == null || !unitRecords.keys().hasNext()) unitRecords = index("unit");
        return unitRecords.get(id);
    }
}
