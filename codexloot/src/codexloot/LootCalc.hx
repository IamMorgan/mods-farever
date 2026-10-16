package codexloot;

/**
 * Works out which items a monster can drop and with what chance, the way the game does it
 * (see Unit.getLootFromUnit and LootTable.generateLootTable in the game's code):
 *  - tables: the unit's own loot table, its unit type's loot table, plus FoeUniqueDrops (Unique flag) / FoeEliteDrops (Elite flag);
 *    a spawn point's override table replaces all of them (SpawnerLoot);
 *  - faction loot (Unit.dropPlayerLoot -> Player.dropFactionLoot): with the chance Const.Items.Loot_FactionDropRate.Foes
 *    one rare item of the monster's faction, picked from the table HItem.getFactionLootTable builds;
 *  - the unit's gains (props.gains: lootTable, lootTables, items), given to every player of the kill;
 *  - an entry is skipped when its `conds` bits do not include the monster's (2 for unique/elite/boss
 *    monsters, otherwise 1), and, with the level filter on, when the monster's level is outside
 *    minLvl..maxLvl (minLvl defaults to the item's level, as in the game);
 *  - the chances themselves (weighted picks, counts, sub-tables) are worked out by LootMath.
 */
class LootCalc {
    static var tables:Map<String, Dynamic>;
    static var items:Map<String, Dynamic>;
    static var types:Map<String, Dynamic>;
    static var factions:Map<String, Dynamic>;

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

    static function passes(entry:Dynamic):Bool return skipReason(entry) == "";

    /** "" when the game would use the row for this monster, otherwise why not. */
    static function skipReason(entry:Dynamic):String {
        var c = optional(entry, "conds");
        // conds is a set of bits (1 normal, 2 elite/unique/boss, ...): the row is for this monster when it has the monster's bit
        if (!ignoreConds && c != null && (Std.int(c) & unitConds) == 0) return "conds " + Std.int(c) + " has no bit of monster " + unitConds;
        if (unitMin == null && unitMax == null) return "";
        var minL = optional(entry, "minLvl");
        var maxL = optional(entry, "maxLvl");
        if (minL == null && (Std.int(G.num(G.field(entry, "flags"))) & 4) == 0) {
            var it = items.get(G.str(G.field(entry, "item")));
            if (it != null) minL = optional(it, "level");
        }
        if (minL != null && unitMax != null && minL > unitMax) return "minLvl " + minL + " > monster " + unitMax;
        if (maxL != null && unitMin != null && maxL < unitMin) return "maxLvl " + maxL + " < monster " + unitMin;
        return "";
    }

    static function add(item:String, p:Float):Void {
        if (p <= 0) return;
        var old = result.exists(item) ? result.get(item) : 0.0;
        result.set(item, 1.0 - (1.0 - old) * (1.0 - Math.min(1.0, p)));
    }

    static function optInt(obj:Dynamic, name:String):Null<Int> {
        var v = optional(obj, name);
        return v == null ? null : Std.int(v);
    }

    /** A game loot table as LootMath rows, filtered for the current monster. Cached per monster. */
    static var converted:Map<String, LootMath.Table>;

    static function toTable(table:Dynamic):LootMath.Table {
        if (table == null) return null;
        var id = G.str(G.field(table, "id"));
        if (id != "" && converted.exists(id)) return converted.get(id);
        var rows:Array<LootMath.Row> = [];
        var loot = G.field(table, "loot");
        for (i in 0...G.len(loot)) {
            var e = G.at(loot, i);
            if (e == null || !passes(e)) continue;
            rows.push({item: G.str(G.field(e, "item")), lootTable: G.str(G.field(e, "lootTable")), proba: G.num(G.field(e, "proba")),
                itemMin: optInt(e, "itemMin"), itemMax: optInt(e, "itemMax"), minLvl: optInt(e, "minLvl"), maxLvl: optInt(e, "maxLvl"),
                flags: optInt(e, "flags")});
        }
        var out:LootMath.Table = {flags: Std.int(G.num(G.field(table, "flags"))), rows: rows};
        if (id != "") converted.set(id, out);
        return out;
    }

    static var math:LootMath;
    /** Chances of the world loot placeholder items in the last collect. */
    static var placeholders:Map<String, Float>;

    /** One roll of a table from the top, its chances times `mult`, added to the result. */
    static function walk(table:Dynamic, mult:Float):Void {
        if (table == null || mult <= 0) return;
        for (item => p in math.rollTop(toTable(table))) add(item, mult * p);
    }

    /** Const.Items.<group>.<name>, or `fallback` when it cannot be read. */
    static function constant(group:String, name:String, fallback:Float):Float {
        try {
            var items = HlxRuntime.resolveStaticField(HlxRuntime.resolveType("Const"), "Items");
            var v = G.field(G.field(items, group), name);
            if (v != null) return G.num(v);
        } catch (_:Dynamic) {}
        return fallback;
    }

    /** The faction drop: the game builds this table from the item sheet (rare items of the faction). */
    static function factionTable(unit:Dynamic):Dynamic {
        var id = G.str(G.field(unit, "faction"));
        if (id == "") return null;
        if (factions == null) factions = index("faction");
        var faction = factions.get(id);
        if (faction == null) return null;
        try return G.callStatic("HItem", "getFactionLootTable", [faction, false]) catch (_:Dynamic) return null;
    }

    /** An item id from an entry of gains.items, whatever its shape (a plain id or a record with an item reference). */
    static function gainItemId(e:Dynamic):String {
        if (e == null) return "";
        if (Std.isOfType(e, String)) return e;
        for (name in ["item", "itemId", "ref", "id"]) {
            var v = G.field(e, name);
            if (v == null) continue;
            if (Std.isOfType(v, String)) return v;
            var id = G.str(G.field(v, "id"));
            if (id != "") return id;
        }
        return "";
    }

    /** The unit's gains: loot tables rolled and items given on every kill. */
    static function walkGains(gains:Dynamic):Void {
        if (gains == null) return;
        var own = G.str(G.field(gains, "lootTable"));
        if (own != "") walk(tables.get(own), 1.0);
        var list = G.field(gains, "lootTables");
        for (i in 0...G.len(list)) {
            var ref = G.str(G.field(G.at(list, i), "ref"));
            if (ref != "") walk(tables.get(ref), 1.0);
        }
        var given = G.field(gains, "items");
        for (i in 0...G.len(given)) {
            var id = gainItemId(G.at(given, i));
            if (id != "") add(id, 1.0);
        }
    }

    public static function item(id:String):Dynamic {
        if (items == null) items = index("item");
        return items.get(id);
    }

    static function collect(roots:Array<String>, ignore:Bool, ?extra:Void->Void):Array<LootEntry> {
        result = new Map<String, Float>();
        ignoreConds = ignore;
        converted = new Map();
        for (r in roots) walk(tables.get(r), 1.0);
        if (extra != null) try extra() catch (_:Dynamic) {}
        ignoreConds = false;
        placeholders = new Map();
        for (id => p in result) if (WorldLoot.isPlaceholder(id)) placeholders.set(id, p);
        var out:Array<LootEntry> = [];
        for (id => chance in result) {
            var rec = items.get(id);
            if (rec != null && G.field(rec, "gfx") != null) out.push({item: rec, chance: chance});
        }
        out.sort((a, b) -> a.chance > b.chance ? -1 : (a.chance < b.chance ? 1 : 0));
        return out;
    }

    /** Each item once, with the higher of its two chances. */
    static function best(a:Array<LootEntry>, b:Array<LootEntry>):Array<LootEntry> {
        var m = new Map<String, LootEntry>();
        for (e in a.concat(b)) {
            var id = G.str(G.field(e.item, "id"));
            var old = m.get(id);
            if (old == null || old.chance < e.chance) m.set(id, e);
        }
        var out = [for (e in m) e];
        out.sort((x, y) -> x.chance > y.chance ? -1 : (x.chance < y.chance ? 1 : 0));
        return out;
    }

    /**
     * The world loot (equipment) of the monster: the pool for its level. Chance = the placeholder's chance
     * shared by the pool; -1 when no loot table of the monster asks for world loot (the server decides).
     */
    static function world(unit:Dynamic, hero:Dynamic, placeholders:Map<String, Float>):Array<LootEntry> {
        var lvl = optional(unit, "lvl"), maxLvl = optional(unit, "maxLvl");
        if (lvl == null && maxLvl == null) return [];
        var lo = lvl != null ? lvl : maxLvl, hi = maxLvl != null ? maxLvl : lvl;
        var plain = placeholders.exists(WorldLoot.PLAIN) ? placeholders.get(WorldLoot.PLAIN) : 0.0;
        var mine = placeholders.exists(WorldLoot.AFFINITY) ? placeholders.get(WorldLoot.AFFINITY) : 0.0;
        var classPool = WorldLoot.pool(items, lo, hi, hero);
        var allPool = plain > 0 || hero == null ? WorldLoot.pool(items, lo, hi, null) : [];
        var chance = new Map<String, Float>();
        var order:Array<Dynamic> = [];
        function share(pool:Array<Dynamic>, p:Float):Void {
            for (item in pool) {
                var id = G.str(G.field(item, "id"));
                if (!chance.exists(id)) { chance.set(id, 0.0); order.push(item); }
                if (p > 0) chance.set(id, 1.0 - (1.0 - chance.get(id)) * (1.0 - p / pool.length));
            }
        }
        if (plain <= 0 && mine <= 0) {
            share(hero != null ? classPool : allPool, 0.0);
            return [for (item in order) {item: item, chance: -1.0}];
        }
        if (mine > 0) share(classPool, mine);
        if (plain > 0) share(allPool, plain);
        var out = [for (item in order) {item: item, chance: chance.get(G.str(G.field(item, "id")))}];
        out.sort((a, b) -> a.chance > b.chance ? -1 : (a.chance < b.chance ? 1 : 0));
        return out;
    }

    /**
     * The monster's drops, most likely first: `normal` (open world / normal dungeon), `heroic` (the table the
     * game uses for heroic mode) and `world` (equipment). Only items that have an icon are returned.
     */
    public static function compute(unit:Dynamic, filterByLevel:Bool, ?hero:Dynamic):{normal:Array<LootEntry>, heroic:Array<LootEntry>, world:Array<LootEntry>} {
        if (tables == null) tables = index("lootTable");
        if (items == null) items = index("item");
        if (types == null) types = index("unitType");

        var flags = Std.int(G.num(G.field(unit, "flags")));
        unitConds = (flags & (UnitFlags.unique() | UnitFlags.elite() | UnitFlags.boss())) != 0 ? 2 : 1;
        unitMin = null;
        unitMax = null;
        if (filterByLevel) {
            var lvl = optional(unit, "lvl");
            var maxLvl = optional(unit, "maxLvl");
            unitMin = lvl != null ? lvl : maxLvl;
            unitMax = maxLvl != null ? maxLvl : lvl;
        }

        // level-scaled counts: a monster of one fixed level uses it, otherwise the counts' maximum
        var fixedLvl = optional(unit, "lvl"), topLvl = optional(unit, "maxLvl");
        math = new LootMath(id -> toTable(tables.get(id)), fixedLvl != null && (topLvl == null || topLvl == fixedLvl) ? fixedLvl : null);

        var props = G.field(unit, "props");
        var roots:Array<String> = [];
        var own = G.str(G.field(props, "lootTable"));
        if (own != "") roots.push(own);
        var type = types.get(G.str(G.field(unit, "type")));
        var typeTable = G.str(G.field(type, "lootTable"));
        if (typeTable != "") roots.push(typeTable);
        // the game adds these two tables by name for unique / elite monsters (Unit.getLootFromUnit)
        if ((flags & UnitFlags.unique()) != 0) roots.push("FoeUniqueDrops");
        if ((flags & UnitFlags.elite()) != 0) roots.push("FoeEliteDrops");
        // the Codex itself adds the boss table for bosses (see CodexData.buildZoneData)
        var bossRoots:Array<String> = [];
        var bossTable = G.str(G.field(props, "bossLootTable"));
        if (bossTable != "" && (flags & UnitFlags.boss()) != 0) bossRoots.push(bossTable);
        var heroicTable = G.str(G.field(props, "heroicLootTable"));

        // a spawner's override table replaces all tables of the monster; monsters met at several spawners
        // show each item with its best chance
        var spawnTables = SpawnerLoot.tablesFor(G.str(G.field(unit, "id")));
        var overrides = [for (t in spawnTables) if (t != "") t];
        var variants:Array<Array<String>> = [];
        if (overrides.length == 0 || spawnTables.indexOf("") >= 0) variants.push(roots);
        for (t in overrides) variants.push([t]);
        var normal:Array<LootEntry> = null;
        var worldAsks = new Map<String, Float>(); // the normal tables' world loot requests (boss/heroic rolls replace `placeholders`)
        for (v in variants) {
            // faction loot and gains come on top of the loot tables (Unit.dropPlayerLoot), with or without a spawner table
            var part = collect(v, false, () -> {
                var faction = factionTable(unit);
                if (faction != null) walk(faction, constant("Loot_FactionDropRate", "Foes", 0.0));
                walkGains(G.field(props, "gains"));
            });
            normal = normal == null ? part : best(normal, part);
            for (k => p in placeholders) if (!worldAsks.exists(k) || worldAsks.get(k) < p) worldAsks.set(k, p);
        }
        if (bossRoots.length > 0) {
            // boss tables: their entries may carry other `conds` values, so those are not used to filter here
            var boss = collect(bossRoots, true);
            for (b in boss) {
                var known = false;
                for (n in normal) if (G.str(G.field(n.item, "id")) == G.str(G.field(b.item, "id"))) { known = true; break; }
                if (!known) normal.push(b);
            }
        }
        var worldLoot = try world(unit, hero, worldAsks) catch (_:Dynamic) [];
        var heroic = heroicTable == "" ? [] : collect([heroicTable], true);
        return {normal: normal, heroic: heroic, world: worldLoot};
    }
}

typedef LootEntry = {item:Dynamic, chance:Float}
