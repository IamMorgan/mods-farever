package dpf;

import dpf.DungeonList.DungeonInfo;
import dpf.GameAccess as G;

/** The game's dungeons and what the local hero may do in them. */
class GameDungeons {
    /** Every dungeon the game offers, arranged for the list. */
    public static function read():Array<DungeonInfo> {
        var all:Array<DungeonInfo> = [];
        for (entry in G.array(G.staticCall("HActivity", "allFiltered", [null]))) {
            var inf = G.field(entry, "inf");
            if (inf == null) continue;
            try {
                if (G.staticCall("HActivity", "isDungeon", [inf]) != true || G.staticCall("HActivity", "isRift", [inf]) == true) continue;
                var texts = G.field(inf, "texts"), props = G.field(inf, "props");
                all.push({
                    id: text(G.field(inf, "id")),
                    name: text(G.field(texts, "name")),
                    desc: text(G.field(texts, "desc")),
                    level: G.integer(G.field(props, "level")),
                    image: text(G.field(props, "loadingScreen"))
                });
            } catch (_:Dynamic) {}
        }
        return DungeonList.arrange(all);
    }

    static function text(value:Dynamic):String {
        var s = G.str(value);
        return s == null ? "" : s;
    }

    /** Which difficulties of the dungeon the hero may pick (see Difficulties.available). */
    public static function difficulties(party:GameParty, activityId:String):Array<Bool> {
        var heroic = false, highest = 0;
        try {
            var inf = G.staticCall("HActivity", "getInf", [activityId]);
            heroic = G.staticCall("HData", "checkStatus", [G.field(G.field(inf, "props"), "heroicReleaseStatus")]) == true;
            var state = G.call("st.player.Progress", "getActivityState", G.field(party.me(), "progress"), [activityId, null]);
            highest = G.integer(G.field(state, "highestDifficultyCompleted"), 0);
        } catch (_:Dynamic) {}
        return Difficulties.available(party.level(), party.maxLevel(), heroic, highest);
    }

    /** The dungeon's picture (what the game's own dialog shows), or null. */
    public static function picture(path:String):Dynamic {
        if (path == null || path == "") return null;
        try return G.call("hxd.res.Any", "toTile", G.staticCall("hxd.Res", "load", [path])) catch (_:Dynamic) return null;
    }

    /** The game's icon by its id ("Dungeon_Default"), as a tile, or null. */
    public static function icon(id:String):Dynamic {
        try {
            var inf = G.call("haxe.ds.StringMap", "get", G.field(G.current("Data", "icon"), "byId"), [id]);
            return inf == null ? null : G.staticCall("lib.ExtensionsUI", "toTile", [G.field(inf, "gfx")]);
        } catch (_:Dynamic) return null;
    }
}
