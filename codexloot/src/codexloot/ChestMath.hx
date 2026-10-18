package codexloot;

import codexloot.LootMath.Row;

/** `mine` = the hero is offered this item (false: an item of another class, listed for completeness). */
typedef ChestEntry = {item:Dynamic, chance:Float, mine:Bool}

typedef ChestLootResult = {
    var entries:Array<ChestEntry>;
    /** The level the items are rolled at. */
    var level:Int;
    /** How many items the game offers at most (null = all that were rolled). */
    var maxItems:Null<Int>;
    /** The top table picks one row by weight. */
    var weighted:Bool;
    /** Only items of the hero's class are rolled (table flag WithAffinity). */
    var affinity:Bool;
    /** Items the hero already owns go to the end of the offer (table flag BLP_AlreadyOwned). */
    var ownedLast:Bool;
    /** The lowest rarity of the items (item data gainItem.rarity.min), "" when not limited. */
    var minRarity:String;
    /** How many items the table rolls for this hero (before the offer is cut to `maxItems`). */
    var pool:Int;
    /** The hero's items were filtered by class, but no hero is known (items of every class are listed). */
    var anyClass:Bool;
    /** The list also holds items of other classes (not offered to this hero). */
    var hasOthers:Bool;
}

/** The rules of a chest's loot that need no game data (see ChestLoot). */
class ChestMath {
    /** The level the chest's table is rolled at (GainItem.getSourceItemLevel). `heroLevel` null = no hero. */
    public static function sourceLevel(iLevel:Null<Float>, rangeMin:Null<Int>, rangeMax:Null<Int>, heroLevel:Null<Int>):Int {
        var level = Math.round((iLevel == null ? 0.0 : iLevel) / 10.0);
        if (rangeMin != null && rangeMax != null) {
            var h = heroLevel == null ? rangeMin : heroLevel;
            level = h < rangeMin ? rangeMin : (rangeMax < h ? rangeMax : h);
        }
        return Std.int(level);
    }

    /** Does the row pass the level rules of HItem.generateLootTable? `itemLevel`: the level of the row's item. */
    public static function levelPasses(row:Row, itemLevel:Null<Int>, level:Int):Bool {
        var minL = row.minLvl;
        // the UseItemLevel row flag: the item's own level is the default minimum
        if (minL == null && row.item != "" && row.flags != null && (row.flags & 4) != 0) minL = itemLevel;
        if (minL != null && level < minL) return false;
        if (row.maxLvl != null && level > row.maxLvl) return false;
        return true;
    }

    /**
     * The chance of each item to be among the offered ones, from the chances to be rolled: with `maxItems` the offer is a random
     * cut of the rolled items, so when more than `maxItems` are expected every chance shrinks by maxItems / expected count.
     */
    public static function offered(rolled:Map<String, Float>, maxItems:Null<Int>, weighted:Bool):Map<String, Float> {
        if (weighted || maxItems == null || maxItems <= 0) return rolled;
        var expected = 0.0;
        for (p in rolled) expected += p;
        if (expected <= maxItems) return rolled;
        var out = new Map<String, Float>();
        for (id => p in rolled) out.set(id, p * maxItems / expected);
        return out;
    }
}
