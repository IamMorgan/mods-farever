import codexloot.LootMath;

/** Checks LootMath against a direct simulation of HItem.generateLootTable. */
class LootMathTest {
    static var failures = 0;
    static function check(name:String, ok:Bool, ?info:String):Void {
        if (!ok) failures++;
        Sys.println((ok ? "ok   " : "FAIL ") + name + (!ok && info != null ? ": " + info : ""));
    }

    static function row(item:String, proba:Float, ?min:Int, ?max:Int, ?sub:String = "", ?flags:Int, ?minLvl:Int, ?maxLvl:Int):Row
        return {item: item, lootTable: sub, proba: proba, itemMin: min, itemMax: max, minLvl: minLvl, maxLvl: maxLvl, flags: flags};

    static var tables:Map<String, Table>;

    /** The game's algorithm, step by step (HItem.hx lines 711-741). */
    static function sim(t:Table, count:Int, inherited:Null<Int>, level:Int, out:Map<String, Bool>):Void {
        if (t == null) return;
        if ((t.flags & 1) != 0) {
            var total = 0.0;
            for (r in t.rows) total += r.proba;
            for (_ in 0...count) {
                var left = total;
                for (r in t.rows) {
                    if (Math.random() < r.proba / left) {
                        emit(t, r, inherited, level, 1, out);
                        break;
                    }
                    left -= r.proba;
                }
            }
        } else {
            for (r in t.rows) if (Math.random() < r.proba) emit(t, r, inherited, level, count, out);
        }
    }

    static function emit(t:Table, r:Row, inherited:Null<Int>, level:Int, mult:Int, out:Map<String, Bool>):Void {
        var flags:Null<Int> = inherited == null ? r.flags : (r.flags == null ? inherited : r.flags | inherited);
        var min = r.itemMin == null ? 1 : r.itemMin;
        var max = r.itemMax == null ? min : r.itemMax;
        if (flags != null && (flags & 1) != 0) {
            var a = r.minLvl == null ? 1 : r.minLvl, b = r.maxLvl == null ? 1 : r.maxLvl;
            if (a < b) {
                var k = Math.max(0.0, Math.min(1.0, (level - a) / (b - a)));
                min = Math.round(min + k * (max - min));
                max = min;
            }
        }
        var c = (min + Std.random(max - min + 1)) * mult;
        if (c <= 0) return;
        if (r.item != "") out.set(r.item, true);
        if (r.lootTable != "") sim(tables.get(r.lootTable), c, flags, level, out);
    }

    static function compare(name:String, top:Table, level:Int, runs:Int = 200000):Void {
        var math = new LootMath(id -> tables.get(id), level);
        var want = math.rollTop(top);
        var hits = new Map<String, Int>();
        for (_ in 0...runs) {
            var got = new Map<String, Bool>();
            sim(top, 1, null, level, got);
            for (id in got.keys()) hits.set(id, (hits.exists(id) ? hits.get(id) : 0) + 1);
        }
        var worst = 0.0, info = "";
        var ids = [for (k in want.keys()) k].concat([for (k in hits.keys()) k]);
        for (id in ids) {
            var a = want.exists(id) ? want.get(id) : 0.0;
            var b = (hits.exists(id) ? hits.get(id) : 0) / runs;
            var d = Math.abs(a - b);
            if (d > worst) { worst = d; info = id + " calc " + a + " sim " + b; }
        }
        check(name + " matches the game's rolls", worst < 0.006, info);
    }

    static function main():Void {
        tables = new Map();
        var m = new LootMath(id -> tables.get(id), 10);

        // plain cases, exact values
        var flat = {flags: 0, rows: [row("a", 0.4), row("b", 1.5), row("z", 0.5, 0, 1)]};
        var r = m.rollTop(flat);
        check("independent roll = proba", Math.abs(r.get("a") - 0.4) < 1e-9);
        check("proba above 1 always drops", r.get("b") == 1.0);
        check("count 0..1 halves the chance", Math.abs(r.get("z") - 0.25) < 1e-9);
        var weighted = {flags: 1, rows: [row("a", 3), row("b", 1)]};
        r = m.rollTop(weighted);
        check("weighted pick = weight share", Math.abs(r.get("a") - 0.75) < 1e-9 && Math.abs(r.get("b") - 0.25) < 1e-9);

        // a weighted sub-table picked 3 times
        tables.set("W", {flags: 1, rows: [row("x", 1), row("y", 3)]});
        r = m.rollTop({flags: 0, rows: [row("", 1, 3, 3, "W")]});
        check("weighted sub-table picked count times", Math.abs(r.get("x") - (1 - Math.pow(0.75, 3))) < 1e-9, Std.string(r.get("x")));

        // simulation of mixed tables
        tables.set("Sub", {flags: 0, rows: [row("s1", 0.3), row("s2", 0.6, 0, 2), row("", 0.5, 1, 2, "W")]});
        tables.set("Deep", {flags: 1, rows: [row("d1", 2, 0, 1), row("", 1, 2, 4, "Sub"), row("d2", 1)]});
        compare("mixed tables", {flags: 0, rows: [row("a", 0.2), row("", 0.7, 1, 3, "Deep"), row("", 0.4, 0, 2, "W"), row("a", 0.1, 0, 1)]}, 10);
        compare("weighted top", {flags: 1, rows: [row("", 2, 1, 2, "Sub"), row("t", 1, 0, 3), row("", 1, 2, 2, "Deep")]}, 10);

        // level-scaled counts (flag 1 on the row, inherited by sub-tables)
        tables.set("Lvl", {flags: 0, rows: [row("l1", 0.5, 0, 2, "", null, 1, 20), row("l2", 1, 0, 4, "", null, 1, 20)]});
        var scaled = {flags: 0, rows: [row("", 1, 1, 1, "Lvl", 1)]};
        compare("level scaled, level 3", scaled, 3);
        compare("level scaled, level 15", scaled, 15);
        var low = new LootMath(id -> tables.get(id), 1).rollTop(scaled);
        check("level scaled to 0 never drops", !low.exists("l1") && !low.exists("l2"));

        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
