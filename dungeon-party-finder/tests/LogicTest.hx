import dpf.DungeonList.DungeonInfo;
import dpf.Difficulties;
import dpf.DungeonList;
import dpf.PartyLogic;

class LogicTest {
    static var failures = 0;
    static function check(name:String, ok:Bool, ?info:String):Void {
        if (!ok) failures++;
        Sys.println((ok ? "ok   " : "FAIL ") + name + (!ok && info != null ? ": " + info : ""));
    }

    static function d(id:String, name:String, level:Int):DungeonInfo return {id: id, name: name, desc: "", level: level, image: ""};

    static function main():Void {
        check("below the cap only the normal difficulty", Difficulties.available(24, 25, true, 0).join(",") == "true,false,false");
        check("at the cap the second one opens", Difficulties.available(25, 25, true, 0).join(",") == "true,true,false");
        check("heroic needs completion and release", Difficulties.available(25, 25, true, 1)[2] == true && Difficulties.available(25, 25, false, 1)[2] == false && Difficulties.available(25, 25, true, 0)[2] == false);
        check("clamp drops to the nearest open one", Difficulties.clamp(2, [true, true, false]) == 1 && Difficulties.clamp(2, [true, false, false]) == 0 && Difficulties.clamp(5, [true, true, true]) == 2 && Difficulties.clamp(-1, [true, true, true]) == 0);

        var list = DungeonList.arrange([d("b", "Beta", 10), d("a", "alpha", 10), d("c", "Core", 3), d("a", "alpha again", 10), d("", "x", 1), d("n", " ", 1), d("Z1_POI_Dungeon_ManfishGeyser", "Geyser", 5)]);
        check("sorted by level then name, no duplicates, no hidden or nameless", [for (x in list) x.id].join(",") == "c,a,b", [for (x in list) x.id].join(","));

        check("leader waits for everyone", Std.string(PartyLogic.button(true, Waiting, false, false)) == "Start(false)");
        check("leader can start when all are ready", Std.string(PartyLogic.button(true, AllReady, true, true)) == "Start(true)");
        check("member readies", Std.string(PartyLogic.button(false, Waiting, false, false)) == "Ready(false)" && Std.string(PartyLogic.button(false, Waiting, false, true)) == "Ready(true)");
        check("count-down: leader may cancel, member waits", Std.string(PartyLogic.button(true, Delay, true, true)) == "CancelStart" && Std.string(PartyLogic.button(false, Delay, true, true)) == "Loading");
        check("no lobby: nothing to press", Std.string(PartyLogic.button(true, Missing, false, false)) == "Wait" && Std.string(PartyLogic.button(false, Missing, false, false)) == "Wait");
        check("loading", Std.string(PartyLogic.button(true, Starting, true, true)) == "Loading");
        check("phases by state name", Type.enumEq(PartyLogic.phaseOf("WaitPlayers", true), Waiting) && Type.enumEq(PartyLogic.phaseOf("AllPlayersReady", true), AllReady)
            && Type.enumEq(PartyLogic.phaseOf("DelayStarting(3.5)", true), Delay) && Type.enumEq(PartyLogic.phaseOf("Starting", true), Starting) && Type.enumEq(PartyLogic.phaseOf("Starting", false), Missing));
        check("ok reason", PartyLogic.isOk("Ok") && PartyLogic.isOk(null) && !PartyLogic.isOk("RequireLevel(5)"));

        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
