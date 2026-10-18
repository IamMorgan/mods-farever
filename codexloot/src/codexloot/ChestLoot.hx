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

    public static function compute(chest:Dynamic, hero:Dynamic):ChestLootResult {
        var gain = gainOf(chest);
        var tables = Sheets.get("lootTable");
        var items = Sheets.get("item");
        var range = G.field(gain, "levelRange");
        var level = ChestMath.sourceLevel(G.field(chest, "iLevel") == null ? null : G.num(G.field(chest, "iLevel")),
            optInt(range, "min"), optInt(range, "max"), heroLevel(hero));
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
                if ((flags & 2) != 0 && item != null && !suits(item, hero)) continue;
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
        var chances = ChestMath.offered(rolled, maxItems, weighted);

        var entries:Array<ChestEntry> = [];
        for (id => chance in chances) {
            var rec = items.get(id);
            if (rec != null && G.field(rec, "gfx") != null && chance > 0) entries.push({item: rec, chance: chance});
        }
        entries.sort((a, b) -> {
            if (a.chance != b.chance) return a.chance > b.chance ? -1 : 1;
            return Reflect.compare(G.str(G.field(a.item, "id")), G.str(G.field(b.item, "id")));
        });
        return {entries: entries, level: level, maxItems: maxItems, weighted: weighted, affinity: (topFlags & 2) != 0, ownedLast: (topFlags & 8) != 0,
            minRarity: G.str(G.field(rarity, "min")), pool: Math.round(pool), anyClass: hero == null && (topFlags & 2) != 0};
    }
}
