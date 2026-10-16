package codexloot;

/**
 * Text tags on the monster list of the Codex: Boss, Elite, Spark. The class comes from the monster's own
 * flags (looked up by name in the game's data, see UnitFlags), so new monsters are tagged automatically.
 * A monster that is both Spark and Elite is tagged Spark.
 */
class UnitTags {
    /** "Boss", "Elite", "Spark" or null. */
    static function classify(unit:Dynamic):String {
        var flags = Std.int(G.num(G.field(unit, "flags")));
        if ((flags & UnitFlags.boss()) != 0) return "Boss";
        if ((flags & UnitFlags.spark()) != 0) return "Spark";
        if ((flags & (UnitFlags.elite() | UnitFlags.unique())) != 0) return "Elite";
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
                if (LootUi.prepare(sheet, child)) {
                    var text = SettingsText.tag(kind);
                    if (!LootUi.canDraw(text)) text = kind; // a font without Cyrillic would draw an empty plate
                    LootUi.tag(child, text, colorOf(kind), 17.0);
                }
            } catch (_:Dynamic) {}
        }
    }
}
