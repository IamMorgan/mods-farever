package macromod;

/** A skill as the macro steps know it: `kind` is what the game's own skill request takes, `id`
    the data id (older configs stored this), `name` the display name in the client's language. */
typedef SkillRef = {kind:String, id:String, name:String};

/** Pure matching logic (no game access), kept separate so it can be tested on its own. */
class SkillMatch {
    /** A display name as shown in the settings field: markup tags removed, spaces collapsed. */
    public static function cleanName(raw:Null<String>):String {
        if (raw == null) return "";
        var out = new StringBuf();
        var inTag = false;
        for (i in 0...raw.length) {
            var ch = raw.charAt(i);
            if (ch == "<") { inTag = true; continue; }
            if (inTag) { if (ch == ">") inTag = false; continue; }
            out.add(ch);
        }
        var parts = [for (p in ~/\s+/g.split(out.toString())) if (p != "") p];
        return parts.join(" ");
    }

    /**
     * The skill kind a step's text stands for. The text is normally a display name picked from
     * the panel; `picks` remembers which kind each picked name meant, so the step still works
     * after the client language changes. Hand-typed names, and ids from older configs, are
     * matched against the known skills. Unknown text is returned as is: the game ignores a
     * request for a kind the hero doesn't have.
     */
    public static function kindFor(value:Null<String>, picks:Map<String, String>, known:Array<SkillRef>):Null<String> {
        var text = value == null ? "" : StringTools.trim(value);
        if (text == "") return null;
        for (s in known) if (s.name == text) return s.kind;
        if (picks.exists(text)) return picks.get(text);
        for (s in known) if (s.kind == text || s.id == text) return s.kind;
        var lower = text.toLowerCase();
        for (s in known) if (s.name.toLowerCase() == lower) return s.kind;
        return text;
    }

    /** For a step that holds an id or kind instead of a name (older configs): the name to show
        instead, or null if the text is already a name or isn't a known skill. */
    public static function nameForId(value:Null<String>, known:Array<SkillRef>):Null<String> {
        var text = value == null ? "" : StringTools.trim(value);
        if (text == "") return null;
        for (s in known) if (s.name == text) return null;
        for (s in known) if ((s.kind == text || s.id == text) && s.name != "" && s.name != text) return s.name;
        return null;
    }
}
