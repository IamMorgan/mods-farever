package buildcalc;

typedef Scaling = {src:Int, scale:Float, op:Array<Float>};

/** Attribute bonuses of a build by kind: flat sums, additive ratios (TAttribute_ARatio), multipliers (TAttribute_MRatio). */
class Sums {
    public var flat:Array<Float>;
    public var add:Array<Float>;
    public var mul:Array<Float>;

    public function new(count:Int) {
        flat = [for (_ in 0...count) 0.0];
        add = [for (_ in 0...count) 0.0];
        mul = [for (_ in 0...count) 1.0];
    }

    public function copy():Sums {
        var s = new Sums(0);
        s.flat = flat.copy();
        s.add = add.copy();
        s.mul = mul.copy();
        return s;
    }

    /** Adds an affix of the data (`ref` = TAttribute_Flat / _ARatio / _MRatio), `share` of it (uptime, slot factor). */
    public function affix(index:Map<String, Int>, ref:String, attr:String, val:Float, share:Float = 1.0):Bool {
        var i = index.get(attr);
        if (i == null) return false;
        switch (ref) {
            case "TAttribute_Flat": flat[i] += val * share;
            case "TAttribute_ARatio": add[i] += val * share;
            case "TAttribute_MRatio": mul[i] *= 1 + (val - 1) * share;
            default: return false;
        }
        return true;
    }
}

/**
 * The hero's attributes computed the way the game does (ent.Unit.atb):
 *   value(i) = (stored(i) + Σ scaling(i) + flat(i)) × modAdd(i) × modMul(i)
 * with modAdd = 1 + Σ ARatio and modMul = Π MRatio (ent.Unit.atbValModAdd / atbValModMul) and the scalings
 * of Data.attribute ([0]: scale × source; [2, a, b, c]: source / HAttributes.getAtbLevelScaling(source, level, a, b) × c).
 * The hero's current values and multipliers are read from the game; the bonuses the calculator knows the
 * hero has now (`known`: worn items, talents, infusions, item skills) are taken out, so everything else
 * (class base values, other passives) stays as the game has it, and any build's bonuses are put in.
 */
class StatEngine {
    public var count = 0;
    public var names:Array<String> = [];
    public var flags:Array<Int> = [];
    public var scalings:Array<Array<Scaling>> = [];
    public var index = new Map<String, Int>();
    public var level = 1.0;
    /** Attributes averaged by the "AllAttributes" scaling of skills (Data.attribute flag 8192, HSkill.getStepEffectScaling). */
    public var mainAttributes:Array<Int> = [];
    var base:Array<Float> = [];
    var add0:Array<Float> = [];
    var mul0:Array<Float> = [];
    var known:Sums;
    var levelScaleCache = new Map<String, Float>();

    public static function attributes():{index:Map<String, Int>, count:Int} {
        var all = G.field(GameData.data("attribute"), "all");
        var index = new Map<String, Int>();
        for (i in 0...G.len(all)) index.set(G.str(G.field(G.at(all, i), "id")), i);
        return {index: index, count: G.len(all)};
    }

    public function new(hero:Dynamic) {
        var all = G.field(GameData.data("attribute"), "all");
        count = G.len(all);
        level = G.num(G.field(hero, "_level"));
        try level = G.num(G.call("ent.Unit", "getEffectiveLevel", [hero])) catch (_:Dynamic) {}
        for (i in 0...count) {
            var a = G.at(all, i);
            names.push(G.str(G.field(a, "id")));
            index.set(names[i], i);
            flags.push(Std.int(G.num(G.field(a, "flags"))));
            if ((flags[i] & 8192) != 0) mainAttributes.push(i);
        }
        for (i in 0...count) {
            var list:Array<Scaling> = [];
            var sc = G.field(G.at(all, i), "scaling");
            for (j in 0...G.len(sc)) {
                var s = G.at(sc, j);
                var src = index.get(G.str(G.field(s, "attribute")));
                if (src == null) continue;
                list.push({src: src, scale: G.num(G.field(s, "scale")), op: opOf(G.field(s, "scalingOperator"))});
            }
            scalings.push(list);
        }
        current = [for (i in 0...count) rawOnHero(hero, i)];
        for (i in 0...count) {
            var a = 1.0, m = 1.0;
            try a = G.num(G.call("ent.Unit", "atbValModAdd", [hero, i, null])) catch (_:Dynamic) {}
            try m = G.num(G.call("ent.Unit", "atbValModMul", [hero, i, null])) catch (_:Dynamic) {}
            add0.push(a);
            mul0.push(m);
        }
    }

    /** Raw values of the hero now (as the game shows them, before the ×0.01 of percentages). */
    public var current:Array<Float>;

    /** Sets the bonuses the hero has now (see the class comment) and checks the model against the game. */
    public function setKnown(k:Sums):Void {
        known = k;
        base = [];
        for (i in 0...count) {
            var mult = add0[i] * mul0[i];
            var stored = Math.abs(mult) > 1e-9 ? current[i] / mult : current[i];
            base.push(stored - scalingSum(i, current) - k.flat[i]);
        }
        var again = evaluate(k);
        var bad = [];
        for (i in 0...count) {
            var d = Math.abs(again[i] - current[i]);
            if (d > 0.01 && d > Math.abs(current[i]) * 0.002) bad.push(names[i] + " game=" + current[i] + " model=" + again[i]);
        }
        // what of the game's multipliers the calculator knows the source of
        var ratios = [];
        for (i in 0...count) {
            var otherAdd = add0[i] - 1 - k.add[i];
            var otherMul = k.mul[i] != 0 ? mul0[i] / k.mul[i] : 0;
            if (Math.abs(add0[i] - 1) > 1e-6 || Math.abs(mul0[i] - 1) > 1e-6 || Math.abs(k.add[i]) > 1e-6)
                ratios.push(names[i] + " add=" + r4(add0[i]) + " (known " + r4(k.add[i]) + ", other " + r4(otherAdd) + ") mul=" + r4(mul0[i])
                    + " (known " + r4(k.mul[i]) + ", other " + r4(otherMul) + ")");
        }
        DebugLog.line("stats: " + count + " attributes, level " + level + "; self-check " + (bad.length == 0 ? "OK" : "MISMATCH " + bad.join("; ")));
        DebugLog.line("stats: multipliers of the hero now: " + (ratios.length == 0 ? "none" : ratios.join("; ")));
    }

    static function r4(v:Float):String return Std.string(Math.round(v * 10000) / 10000);

    static function opOf(v:Dynamic):Array<Float> {
        var out:Array<Float> = [];
        try for (i in 0...G.len(v)) out.push(G.num(G.at(v, i))) catch (_:Dynamic) {}
        if (out.length == 0) {
            var text = Std.string(v);
            var re = ~/-?[0-9]+(\.[0-9]+)?/g;
            var pos = 0;
            while (re.matchSub(text, pos)) {
                out.push(Std.parseFloat(re.matched(0)));
                var p = re.matchedPos();
                pos = p.pos + p.len;
            }
        }
        if (out.length == 0) out.push(0);
        return out;
    }

    public function percent(i:Int):Float return (flags[i] & 4) != 0 ? 0.01 : 1.0;

    function rawOnHero(hero:Dynamic, i:Int):Float {
        try return G.num(G.call("ent.GameObject", "atbVal", [hero, i, null])) / percent(i) catch (_:Dynamic) return 0;
    }

    function levelScale(src:Int, a:Float, b:Float):Float {
        var key = src + "|" + a + "|" + b;
        var v = levelScaleCache.get(key);
        if (v != null) return v;
        var s = 0.0;
        try s = G.num(G.callStatic("HAttributes", "getAtbLevelScaling", [src, level, a, b, null, null])) catch (e:Dynamic) DebugLog.error("levelScale", e);
        levelScaleCache.set(key, s);
        return s;
    }

    function scalingSum(i:Int, vals:Array<Float>):Float {
        var sum = 0.0;
        for (s in scalings[i]) {
            var v = vals[s.src];
            switch (Std.int(s.op[0])) {
                case 0: sum += s.scale * v;
                case 2:
                    var k = levelScale(s.src, s.op[1], s.op[2]);
                    if (k > 0) sum += v / k * (s.op.length > 3 ? s.op[3] : 1);
                default:
            }
        }
        return sum;
    }

    /** Raw values of every attribute with these bonuses instead of the known ones (indexed like Data.attribute). */
    public function evaluate(s:Sums):Array<Float> {
        var mult = [for (i in 0...count) (add0[i] - known.add[i] + s.add[i]) * (known.mul[i] != 0 ? mul0[i] / known.mul[i] : mul0[i]) * s.mul[i]];
        var vals = [for (i in 0...count) (base[i] + s.flat[i]) * mult[i]];
        // attributes depend on others (MaxPoise on MaxHealth on Vitality): settle in a few passes
        for (_ in 0...4) for (i in 0...count) if (scalings[i].length > 0) vals[i] = (base[i] + scalingSum(i, vals) + s.flat[i]) * mult[i];
        for (i in 0...count) if ((flags[i] & 128) == 0 && vals[i] < 0) vals[i] = 0;
        return vals;
    }

    /** Displayed value of attribute `name`. */
    public function get(vals:Array<Float>, name:String):Float {
        var i = index.get(name);
        return i == null ? 0 : vals[i] * percent(i);
    }
}
