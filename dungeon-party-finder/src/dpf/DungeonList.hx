package dpf;

typedef DungeonInfo = {id:String, name:String, desc:String, level:Int, image:String};

/** The list of dungeons the player can pick from, in the order it is shown. */
class DungeonList {
    /** Ids the portal does not offer (the same one the Dungeon Button mod leaves out). */
    public static var HIDDEN:Array<String> = ["Z1_POI_Dungeon_ManfishGeyser"];

    /** By level, then by name; the same dungeon found twice (placed on several maps) once; nameless ones dropped. */
    public static function arrange(all:Array<DungeonInfo>):Array<DungeonInfo> {
        var seen = new Map<String, Bool>();
        var out:Array<DungeonInfo> = [];
        for (d in all) {
            if (d == null || d.id == null || d.id == "" || seen.exists(d.id) || HIDDEN.indexOf(d.id) >= 0) continue;
            if (d.name == null || StringTools.trim(d.name) == "") continue;
            seen.set(d.id, true);
            out.push(d);
        }
        out.sort((a, b) -> a.level != b.level ? a.level - b.level : Reflect.compare(a.name.toLowerCase(), b.name.toLowerCase()));
        return out;
    }
}
