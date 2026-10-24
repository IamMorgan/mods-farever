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
}
