package codexloot;

/**
 * Unit flags by name, read from the game's data definition (_Data.Unit_flags: the value of a name is its
 * bit index), so a game update that moves or adds flags needs no change of the mod.
 */
class UnitFlags {
    static var bits = new Map<String, Int>();

    /** The bit of the flag `name`; `fallback` = the bit index known when the mod was written. */
    public static function bit(name:String, fallback:Int):Int return flagBit("Unit", name, fallback);

    /** The bit of flag `name` of a data sheet's flags type (_Data.<sheet>_flags). */
    public static function flagBit(sheet:String, name:String, fallback:Int):Int {
        var key = sheet + "." + name;
        var b = bits.get(key);
        if (b != null) return b;
        var index = fallback;
        try {
            var v = HlxRuntime.resolveStaticField(HlxRuntime.resolveType("_Data." + sheet + "_flags_Impl_"), name);
            if (v != null) {
                var i = Std.int(G.num(v));
                if (i >= 0 && i < 31) index = i; // a bit index; anything else keeps the known one
            }
        } catch (_:Dynamic) {}
        b = 1 << index;
        bits.set(key, b);
        return b;
    }

    public static function has(unit:Dynamic, name:String, fallback:Int):Bool
        return (Std.int(G.num(G.field(unit, "flags"))) & bit(name, fallback)) != 0;

    public static inline function elite():Int return bit("Elite", 3);
    public static inline function boss():Int return bit("Boss", 4);
    public static inline function unique():Int return bit("Unique", 6);
    public static inline function spark():Int return bit("Spark", 22);
    /** Item flag of the world loot pool (Hero.generateWorldLootItem). */
    public static inline function worldLootItem():Int return flagBit("Item", "WorldLoot", 1);
}
