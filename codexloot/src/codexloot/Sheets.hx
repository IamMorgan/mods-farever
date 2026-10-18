package codexloot;

/** Records of the game's data sheets (Data.<sheet>.all), by id. Cached until `clear` (new game data or language). */
class Sheets {
    static var cache = new Map<String, Map<String, Dynamic>>();

    public static function clear():Void cache = new Map();

    public static function get(sheet:String):Map<String, Dynamic> {
        var m = cache.get(sheet);
        if (m != null) return m;
        m = new Map<String, Dynamic>();
        try {
            var all = G.field(HlxRuntime.resolveStaticField(HlxRuntime.resolveType("Data"), sheet), "all");
            for (i in 0...G.len(all)) {
                var rec = G.at(all, i);
                var id = G.str(G.field(rec, "id"));
                if (id != "") m.set(id, rec);
            }
        } catch (_:Dynamic) {}
        if (m.keys().hasNext()) cache.set(sheet, m); // an empty result (data not loaded yet) is not kept
        return m;
    }

    /** The localized name of a record (`texts.name`, or `name` for sheets like rarity), or its id when it has none. */
    public static function name(sheet:String, id:String):String {
        var rec = get(sheet).get(id);
        if (rec == null) return id;
        var n = G.str(G.field(G.field(rec, "texts"), "name"));
        if (n == "") n = G.str(G.field(rec, "name"));
        return n == "" ? id : n;
    }
}
