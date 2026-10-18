import buildcalc.sim.Script;

class ParseAll {
    static function main() {
        var all:Dynamic = haxe.Json.parse(sys.io.File.getContent("simtest/scripts.json"));
        var ok = 0, bad = 0;
        for (id in Reflect.fields(all)) {
            var src:String = Reflect.field(all, id);
            try {
                Script.parse(src);
                ok++;
            } catch (e:Dynamic) {
                bad++;
                if (bad <= 25) Sys.println(id + ": " + e);
            }
        }
        Sys.println("parsed " + ok + ", failed " + bad);
    }
}
