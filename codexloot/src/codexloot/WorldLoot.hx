package codexloot;

/**
 * World loot: the equipment the game rolls for a kill outside the monster's loot tables
 * (ent.Hero.generateWorldLootItem). The pool for a monster level is every item with the world loot
 * flag (item flag WorldLoot) that is not a recipe and whose level lies in
 * level + Const.Items.WorldLootLevel[0] .. level + WorldLootLevel[1] (the level is capped at 20 and the
 * top at Const.Hero.MaxLevel); with affinity only items of the hero's class (HItem.hasUnitAptitude).
 * One item of the pool is picked at random. Loot tables ask for it with the placeholder items
 * WorldLoot / WorldLootWithAffinity; for other kills the server decides, so that chance is unknown.
 */
class WorldLoot {
    public static inline var PLAIN = "WorldLoot";
    public static inline var AFFINITY = "WorldLootWithAffinity";

    public static function isPlaceholder(id:String):Bool return StringTools.startsWith(id, PLAIN);

    static var itemTypes:Map<String, Dynamic>;

    static function itemsConst(name:String, i:Int, fallback:Float):Float {
        try {
            var arr = G.field(HlxRuntime.resolveStaticField(HlxRuntime.resolveType("Const"), "Items"), name);
            if (G.len(arr) > i) return G.num(G.at(arr, i));
        } catch (_:Dynamic) {}
        return fallback;
    }

    static function heroMaxLevel():Float {
        try {
            var v = G.field(HlxRuntime.resolveStaticField(HlxRuntime.resolveType("Const"), "Hero"), "MaxLevel");
            if (v != null) return G.num(v);
        } catch (_:Dynamic) {}
        return 25;
    }

    static function isRecipe(item:Dynamic):Bool {
        if (itemTypes == null) {
            itemTypes = new Map();
            var all = G.field(HlxRuntime.resolveStaticField(HlxRuntime.resolveType("Data"), "itemType"), "all");
            for (i in 0...G.len(all)) {
                var t = G.at(all, i);
                itemTypes.set(G.str(G.field(t, "id")), t);
            }
        }
        var type = itemTypes.get(G.str(G.field(item, "type")));
        if (type == null) return false;
        try return G.callStatic("HItem", "isSameType", [type, "Recipe"]) == true catch (_:Dynamic) return false;
    }

    /** The level window of the pool for one monster level, as the game computes it. */
    public static function window(level:Float, offLo:Float, offHi:Float, maxLevel:Float):{lo:Float, hi:Float} {
        var lvl:Float = Math.round(Math.max(0, Math.min(maxLevel, level)));
        if (lvl > 20) lvl = 20;
        return {lo: lvl + offLo, hi: Math.round(Math.max(0, Math.min(maxLevel, lvl + offHi)))};
    }

    /** The pool for a monster of level minLvl..maxLvl (every level of the range); `hero` set: only items of the hero's class. */
    static var pools = new Map<String, Array<Dynamic>>();

    /** Another hero (class) or new game data: build the pools again. */
    public static function clearPools():Void pools = new Map();

    public static function pool(items:Iterable<Dynamic>, minLvl:Float, maxLvl:Float, hero:Dynamic):Array<Dynamic> {
        var key = minLvl + "|" + maxLvl + "|" + (hero != null);
        var cached = pools.get(key);
        if (cached != null) return cached;
        var out = build(items, minLvl, maxLvl, hero);
        pools.set(key, out);
        return out;
    }

    static function build(items:Iterable<Dynamic>, minLvl:Float, maxLvl:Float, hero:Dynamic):Array<Dynamic> {
        var offLo = itemsConst("WorldLootLevel", 0, 0), offHi = itemsConst("WorldLootLevel", 1, 0);
        var top = heroMaxLevel();
        var lo = window(minLvl, offLo, offHi, top).lo, hi = window(maxLvl, offLo, offHi, top).hi;
        var out = [];
        for (item in items) {
            if ((Std.int(G.num(G.field(item, "flags"))) & UnitFlags.worldLootItem()) == 0) continue;
            if (G.field(item, "gfx") == null || isRecipe(item)) continue;
            var l = G.field(item, "level");
            if (l != null && (G.num(l) < lo || G.num(l) > hi)) continue;
            if (hero != null) {
                var ok = true;
                try ok = G.callStatic("HItem", "hasUnitAptitude", [item, hero]) == true catch (_:Dynamic) {}
                if (!ok) continue;
            }
            out.push(item);
        }
        out.sort((a, b) -> Reflect.compare(G.num(G.field(a, "level")), G.num(G.field(b, "level"))));
        return out;
    }
}
