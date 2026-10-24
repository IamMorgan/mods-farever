import dpf.DungeonList.DungeonInfo;
import dpf.DungeonList;

class LogicTest {
    static var failures = 0;
    static function check(name:String, ok:Bool, ?info:String):Void {
        if (!ok) failures++;
        Sys.println((ok ? "ok   " : "FAIL ") + name + (!ok && info != null ? ": " + info : ""));
    }

    static function d(id:String, name:String, level:Int):DungeonInfo return {id: id, name: name, desc: "", level: level, image: ""};

    static function main():Void {

        var list = DungeonList.arrange([d("b", "Beta", 10), d("a", "alpha", 10), d("c", "Core", 3), d("a", "alpha again", 10), d("", "x", 1), d("n", " ", 1), d("Z1_POI_Dungeon_ManfishGeyser", "Geyser", 5)]);
        check("sorted by level then name, no duplicates, no hidden or nameless", [for (x in list) x.id].join(",") == "c,a,b", [for (x in list) x.id].join(","));


        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
