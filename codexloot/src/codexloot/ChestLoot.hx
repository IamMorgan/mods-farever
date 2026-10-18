package codexloot;

import codexloot.ChestMath.ChestEntry;
import codexloot.ChestMath.ChestLootResult;
import codexloot.LootMath.Row;
import codexloot.LootMath.Table;

/**
 * The contents of a chest item (an item with props.gainItem, e.g. Hero Weapon Cache), the way the game opens it
 * (st.skill.GainItem.onStartStep -> st.Player.generateLoot -> HItem.generateLootTable):
 *  - the level the table is rolled at: the hero's level inside gainItem.levelRange (or the item's iLevel / 10 without a range);
 *  - a row is used when its minLvl <= level <= maxLvl (minLvl defaults to the item's level for rows with the UseItemLevel flag),
 *    and, for a table with the WithAffinity flag, when the item suits the hero's class (HItem.hasUnitAptitude);
 *  - the rolled items are shuffled (the ones the hero already owns last), cut to gainItem.maxItems and offered; mode "Chose"
 *    lets the hero keep one of them. So an item is offered with the chance min(1, maxItems / items rolled).
 * A table with the Weights flag picks exactly one row by weight, so nothing is cut.
 */
class ChestLoot {
    static function optInt(obj:Dynamic, name:String):Null<Int> {
        var v = G.field(obj, name);
        return v == null ? null : Std.int(G.num(v));
    }

    static function suits(item:Dynamic, hero:Dynamic):Bool {
        if (hero == null || item == null) return true;
        try return G.callStatic("HItem", "hasUnitAptitude", [item, hero]) == true catch (_:Dynamic) return true;
    }

    /** The hero's level, or null. */
    static function heroLevel(hero:Dynamic):Null<Int> {
        if (hero == null) return null;
        try return Std.int(G.num(G.call("ent.Unit", "get_level", [hero]))) catch (_:Dynamic) return null;
    }

    /** The chest item's gainItem record, or null when the item is not a chest. */
    public static function gainOf(item:Dynamic):Dynamic return G.field(G.field(item, "props"), "gainItem");

    /** The classes of the game (aptitudes with the "exclusive" flag): Fighter, Assassin, Wizard, Cleric. */
    static function classes():Array<String> {
        var out:Array<String> = [];
        for (id => apt in Sheets.get("aptitude")) {
            var flags = G.field(G.field(apt, "props"), "flags");
            if (flags != null && (Std.int(G.num(flags)) & 1) != 0) out.push(id);
        }
        out.sort(Reflect.compare);
        return out;
    }

    /** Does the item suit a hero of the class `cls`? The rule of HItem.hasUnitAptitude: an item without a class suits everyone. */
    static function suitsClass(item:Dynamic, cls:String, exclusive:Array<String>):Bool {
        var result = true;
        var apts = G.field(item, "aptitudes");
        for (i in 0...G.len(apts)) {
            var ref = G.str(G.field(G.at(apts, i), "ref"));
            if (exclusive.indexOf(ref) < 0) continue;
            if (ref == cls) return true;
            result = false;
        }
        return result;
    }

    /** The chance of each item to be among the offered ones, for a hero accepted by `accept` (null = no class limit). */
    static function offeredFor(chest:Dynamic, heroLvl:Null<Int>, accept:Dynamic->Bool):{chances:Map<String, Float>, pool:Int, level:Int, maxItems:Null<Int>, weighted:Bool, topFlags:Int, minRarity:String} {
        var gain = gainOf(chest);
        var tables = Sheets.get("lootTable");
        var items = Sheets.get("item");
        var range = G.field(gain, "levelRange");
        var level = ChestMath.sourceLevel(G.field(chest, "iLevel") == null ? null : G.num(G.field(chest, "iLevel")),
            optInt(range, "min"), optInt(range, "max"), heroLvl);
        var maxItems = optInt(gain, "maxItems");
        var rarity = G.field(gain, "rarity");
        var top = tables.get(G.str(G.field(gain, "lootTable")));
        var topFlags = top == null ? 0 : Std.int(G.num(G.field(top, "flags")));
        var weighted = (topFlags & 1) != 0;
        var converted = new Map<String, Table>();

        function convert(id:String):Table {
            var cached = converted.get(id);
            if (cached != null) return cached;
            var table = tables.get(id);
            if (table == null) return null;
            var flags = Std.int(G.num(G.field(table, "flags")));
            var rows:Array<Row> = [];
            var loot = G.field(table, "loot");
            for (i in 0...G.len(loot)) {
                var e = G.at(loot, i);
                if (e == null) continue;
                var row:Row = {item: G.str(G.field(e, "item")), lootTable: G.str(G.field(e, "lootTable")), proba: G.num(G.field(e, "proba")),
                    itemMin: optInt(e, "itemMin"), itemMax: optInt(e, "itemMax"), minLvl: optInt(e, "minLvl"), maxLvl: optInt(e, "maxLvl"), flags: optInt(e, "flags")};
                var item = row.item == "" ? null : items.get(row.item);
                if (row.item != "" && (item == null || G.field(item, "gfx") == null)) continue;
                if (!ChestMath.levelPasses(row, item == null ? null : optInt(item, "level"), level)) continue;
                if ((flags & 2) != 0 && item != null && accept != null && !accept(item)) continue;
                rows.push(row);
            }
            var out:Table = {flags: flags, rows: rows};
            converted.set(id, out);
            return out;
        }

        var math = new LootMath(convert, level);
        var topTable = top == null ? null : convert(G.str(G.field(top, "id")));
        var rolled = topTable == null ? new Map<String, Float>() : math.rollTop(topTable);
        var pool = 0.0;
        for (p in rolled) pool += p;
        return {chances: ChestMath.offered(rolled, maxItems, weighted), pool: Math.round(pool), level: level, maxItems: maxItems, weighted: weighted,
            topFlags: topFlags, minRarity: G.str(G.field(rarity, "min"))};
    }

    /**
     * The complete contents of the chest. A chest whose table is limited to the hero's class (WithAffinity) offers only the items of
     * the hero's class, but the list shows the items of every class: the ones the hero is offered (`mine`) with their chance, the
     * others (not `mine`) with the chance they have for a hero of the class that can use them.
     */
    public static function compute(chest:Dynamic, hero:Dynamic):ChestLootResult {
        var items = Sheets.get("item");
        var level = heroLevel(hero);
        var main = offeredFor(chest, level, hero == null ? null : (item) -> suits(item, hero));
        var affinity = (main.topFlags & 2) != 0;
        var chances = main.chances;
        var other = new Map<String, Float>();
        if (affinity) {
            var exclusive = classes();
            if (hero == null) chances = new Map(); // no hero: every item is listed with the chance it has for its own class
            for (cls in exclusive) {
                var r = offeredFor(chest, level, (item) -> suitsClass(item, cls, exclusive));
                for (id => c in r.chances) if (!chances.exists(id) && (!other.exists(id) || other.get(id) < c)) other.set(id, c);
            }
        }

        var entries:Array<ChestEntry> = [];
        function add(map:Map<String, Float>, mine:Bool):Void {
            for (id => chance in map) {
                var rec = items.get(id);
                if (rec != null && G.field(rec, "gfx") != null && chance > 0) entries.push({item: rec, chance: chance, mine: mine});
            }
        }
        add(chances, true);
        add(other, hero == null);
        entries.sort((a, b) -> {
            if (a.mine != b.mine) return a.mine ? -1 : 1;
            if (a.chance != b.chance) return a.chance > b.chance ? -1 : 1;
            return Reflect.compare(G.str(G.field(a.item, "id")), G.str(G.field(b.item, "id")));
        });
        return {entries: entries, level: main.level, maxItems: main.maxItems, weighted: main.weighted, affinity: affinity, ownedLast: (main.topFlags & 8) != 0,
            minRarity: main.minRarity, pool: main.pool, anyClass: hero == null && affinity,
            hasOthers: hero != null && affinity && Lambda.exists(entries, (e) -> !e.mine)};
    }
}
