import buildcalc.sim.Script;
import buildcalc.sim.Interp;

/** Compiles every script into an interpreter with a host that records what it is asked for. */
class RunAll implements Host {
    var missingCount = new Map<String, Int>();
    public function new() {}
    public function global(name:String):Dynamic { return null; }
    public function callGlobal(name:String, args:Array<Dynamic>):Dynamic { return null; }
    public function missing(what:String):Void missingCount.set(what, (missingCount.exists(what) ? missingCount.get(what) : 0) + 1);

    static function main() {
        var all:Dynamic = haxe.Json.parse(sys.io.File.getContent("simtest/scripts.json"));
        var host = new RunAll();
        var ok = 0;
        for (id in Reflect.fields(all)) {
            var i = new Interp(Script.parse(Reflect.field(all, id)), host);
            ok++;
        }
        Sys.println("interpreters " + ok);
    }
}
