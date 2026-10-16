package codexloot;

/**
 * The Codex monster search also finds monsters by the names of their loot: a monster stays in the list
 * when the search text is part of the name of any item it can drop (loot tables, boss and heroic loot,
 * equipment). The names are worked out once per monster and kept until the settings change.
 */
class LootSearch {
    static var names = new Map<String, String>(); // unit id -> lower-case item names, one per line

    public static function clear():Void names = new Map();

    /** The item's name as the game shows it, in the client's language (HItem.getName). */
    static function displayName(item:Dynamic):String {
        try {
            var n = G.str(G.callStatic("HItem", "getName", [item]));
            if (n != "") return n;
        } catch (_:Dynamic) {}
        return G.str(G.field(G.field(item, "texts"), "name"));
    }

    static function itemNames(unit:Dynamic, filterByLevel:Bool, hero:Dynamic):String {
        var id = G.str(G.field(unit, "id"));
        var cached = names.get(id);
        if (cached != null) return cached;
        var buf = new StringBuf();
        try {
            var loot = LootCalc.compute(unit, filterByLevel, hero);
            for (list in [loot.normal, loot.heroic, loot.world])
                for (e in list) { buf.add(displayName(e.item).toLowerCase()); buf.add("\n"); }
        } catch (_:Dynamic) {}
        var text = buf.toString();
        names.set(id, text);
        return text;
    }

    /** True when the monster drops an item whose name contains `search` (any case). */
    public static function matches(unit:Dynamic, search:String, filterByLevel:Bool, hero:Dynamic):Bool {
        if (unit == null || search == null) return false;
        var s = StringTools.trim(search).toLowerCase();
        if (s == "") return false;
        return itemNames(unit, filterByLevel, hero).indexOf(s) >= 0;
    }
}
