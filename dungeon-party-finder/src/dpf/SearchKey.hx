package dpf;

/**
 * What two searchers must have in common to be put in one group: the same dungeon, the same difficulty and the same level
 * bracket. It is the single filter value of the lobbies the mod creates, so the platform's lobby list only returns matches.
 */
class SearchKey {
    /** Name of the lobby data field the key is stored in (and filtered by). */
    public static inline var FIELD = "dpf";
    static inline var VERSION = "dpf1";

    public static function make(activityId:String, difficulty:Int, bracket:Int):String
        return VERSION + "|" + activityId + "|d" + difficulty + "|b" + bracket;

    /** Null if the text is not a key of this version. */
    public static function parse(key:String):Null<{activity:String, difficulty:Int, bracket:Int}> {
        if (key == null) return null;
        var parts = key.split("|");
        if (parts.length != 4 || parts[0] != VERSION || parts[1] == "") return null;
        if (parts[2].charAt(0) != "d" || parts[3].charAt(0) != "b") return null;
        var difficulty = Std.parseInt(parts[2].substr(1)), bracket = Std.parseInt(parts[3].substr(1));
        if (difficulty == null || bracket == null) return null;
        return {activity: parts[1], difficulty: difficulty, bracket: bracket};
    }
}
