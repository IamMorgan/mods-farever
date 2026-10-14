package codexloot;

/**
 * Text tags on the monster list of the Codex: Boss, Elite, Spark.
 * The class is read from the monster's own data, so monsters added by game updates are tagged automatically:
 *  - Boss:  unit flag 16 (the game's isBoss)
 *  - Spark: the unit id, type or a model name is a "Spark" variant (for example Crab_Spark)
 *  - Elite: unit flag 8 (isElite) or 64 (isUnique)
 * A monster that is both Spark and Elite is tagged Spark.
 */
class UnitTags {
    static function sparkName(name:String):Bool {
        return name.indexOf("Spark") >= 0 && name.indexOf("Sparkling") < 0;
    }

    /** Spark variants are marked by the id, the type or a model name of the unit (for example Crab_Spark, Rabbit_Spark). */
    static function isSpark(unit:Dynamic):Bool {
        try {
            if (sparkName(G.str(G.field(unit, "id"))) || sparkName(G.str(G.field(unit, "type")))) return true;
        } catch (_:Dynamic) {}
        try {
            var models = G.field(unit, "models");
            for (i in 0...G.len(models)) {
                var m = G.at(models, i);
                if (m == null) continue;
                try {
                    if (sparkName(Std.string(m))) return true; // a plain string model name
                } catch (_:Dynamic) {}
                try {
                    for (name in Reflect.fields(m)) {
                        var v = G.field(m, name);
                        if (v != null && sparkName(Std.string(v))) return true;
                    }
                } catch (_:Dynamic) {}
            }
        } catch (_:Dynamic) {}
        return false;
    }

    /** "Boss", "Elite", "Spark" or null. */
    static function classify(unit:Dynamic):String {
        var flags = Std.int(G.num(G.field(unit, "flags")));
        if ((flags & 16) != 0) return "Boss";
        if (isSpark(unit)) return "Spark";
        if ((flags & (8 | 64)) != 0) return "Elite";
        return null;
    }

    static function colorOf(kind:String):Int {
        return kind == "Boss" ? 0xFF6B5E : (kind == "Spark" ? 0x7FDBFF : 0xFFC247);
    }

    public static function apply(sheet:Dynamic):Void {
        var list = G.field(sheet, "unitList");
        if (list == null) return;
        for (child in G.children(list)) {
            // one monster must never stop the others from being tagged
            try {
                if (G.typeName(child) != "ui.win.codex.CodexButton") continue;
                var unit = G.field(G.field(child, "data"), "data");
                if (unit == null) continue;
                var kind = classify(unit);
                if (kind == null) continue;
                if (LootUi.prepare(sheet, child)) LootUi.tag(child, kind, colorOf(kind), 17.0);
            } catch (_:Dynamic) {}
        }
    }
}
