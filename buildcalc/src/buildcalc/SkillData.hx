package buildcalc;

typedef Scal = {atb:String, ratio:Float, minRank:Int, maxRank:Int, equalRank:Int};
typedef Effect = {uid:Int, kind:String, affinity:String, physical:Bool, base:Float, scaling:Array<Scal>, dynVal:Int, status:String, raw:Dynamic};
typedef Step = {id:String, on:String, type:String, mastery:String, masteryExclude:String, minRank:Int, maxRank:Int, equalRank:Int,
    duration:Dynamic, tick:Dynamic, targetCd:Float, spread:Bool, hitFilter:Int, ignoreMain:Bool, status:String, statusSelf:Bool, effects:Array<Effect>};
typedef AffixDef = {ref:String, attr:String, val:Float, minRank:Int, maxRank:Int, equalRank:Int, mastery:String};
typedef MasteryDef = {id:String, cooldown:Null<Float>, duration:Null<Float>, vars:Dynamic, inf:Dynamic};

/** A change a script makes to hits it sees (…Eval handlers): `stat` += value. */
typedef ScriptMod = {stat:String, value:String, sign:Float, filter:Filter, rankMin:Int, mastery:String, needSkill:String, own:Bool, heal:Bool};
/** Which hits a script reacts to. */
typedef Filter = {skill:String, attacks:Bool, combo:Bool, magic:Bool, crit:Bool, weaponSkill:Bool, classSkill:Bool, anySkill:Bool, status:Bool, ally:Bool,
    self:Bool, notArsenal:Bool, fromArsenal:Bool};
/** A script event that gives this skill a charge (chargePrayer, addCharges): the skill is cast that often. */
typedef ScriptCharge = {trigger:String, filter:Filter, rankMin:Int, mastery:String};
/** A script event that shortens cooldowns: `target` is a skill id, "self" or "weapons"; `time` and `chance` are var names. */
typedef ScriptCdr = {trigger:String, filter:Filter, target:String, time:String, chance:String, rankMin:Int, mastery:String, needSkill:String};

/** Something a script does when it fires: plays steps, adds statuses; `chance`, `chain` and `dyn` are var names. */
typedef ScriptProc = {trigger:String, filter:Filter, chance:String, steps:Array<String>, chain:String, statuses:Array<{id:String, self:Bool}>,
    dyn:String, every:String, rankMin:Int, mastery:String, needSkill:String};

/**
 * A skill of the game's data (Data.skill) read once into plain values: steps and their effects, rank and
 * rune (mastery) conditions, affixes, variables, statuses it applies, and what its script does as far as
 * the calculator understands it (see analyse). Everything comes from the data; nothing is per skill.
 */
class SkillDef {
    public var id:String;
    public var inf:Dynamic;
    public var type:String;
    public var cooldown:Float;
    public var duration:Float;
    public var steps:Array<Step> = [];
    public var affixes:Array<AffixDef> = [];
    public var masteries:Array<MasteryDef> = [];
    public var rankOverride:Array<{minRank:Int, vars:Dynamic}> = [];
    public var vars:Dynamic;
    public var maxPoints = 0;
    public var subskills:Array<String> = [];
    public var mods:Array<ScriptMod> = [];
    public var procs:Array<ScriptProc> = [];
    /** Script handlers the calculator cannot value (logged once). */
    public var unknown:Array<String> = [];
    public var charges:Array<ScriptCharge> = [];
    public var cdrs:Array<ScriptCdr> = [];
    /** A status that is a damage or heal over time (no critical hits: st.skill.SkillContext.initVars). */
    public var dotHot = false;
    /** Most stacks of a status (props.status.maxStacks). */
    public var maxStacks = 1;
    /** The status consumes itself (tryConsumeStatus / consumeStatus) unless the hero has this skill ("" = always). */
    public var consumes = false;
    public var consumeUnless = "";
    var varCache = new Map<String, Null<Float>>();

    public function new(inf:Dynamic) {
        this.inf = inf;
        id = G.str(G.field(inf, "id"));
        type = SkillData.typeName(G.field(inf, "type"));
        cooldown = G.num(G.field(inf, "cooldown"));
        duration = G.num(G.field(inf, "duration"));
        vars = G.field(inf, "vars");
        var props = G.field(inf, "props");
        maxPoints = Std.int(G.num(G.field(G.field(props, "talent"), "maxPoints")));
        var ro = G.field(props, "rankOverride");
        for (i in 0...G.len(ro)) {
            var o = G.at(ro, i);
            rankOverride.push({minRank: Std.int(G.num(G.field(o, "minRank"))), vars: G.field(o, "vars")});
        }
        var ms0 = G.field(G.field(props, "status"), "maxStacks");
        if (ms0 != null && G.num(ms0) > 1) maxStacks = Std.int(G.num(ms0));
        try dotHot = G.callStatic("HSkill", "isDoT", [inf]) == true || G.callStatic("HSkill", "isHoT", [inf]) == true catch (_:Dynamic) {}
        var subs = G.field(props, "subskills");
        for (i in 0...G.len(subs)) {
            var s = GameData.idOf(G.field(G.at(subs, i), "skill"));
            if (s != "") subskills.push(s);
        }
        var ms = G.field(inf, "mastery");
        for (i in 0...G.len(ms)) {
            var m = G.at(ms, i);
            var p = G.field(m, "props");
            var cd = G.field(p, "cooldown"), du = G.field(p, "duration");
            masteries.push({id: G.str(G.field(m, "id")), cooldown: cd == null ? null : G.num(cd), duration: du == null ? null : G.num(du),
                vars: G.field(m, "vars"), inf: m});
        }
        var afx = G.field(inf, "affixes");
        for (i in 0...G.len(afx)) {
            var a = G.at(afx, i);
            var c = G.field(a, "conds");
            affixes.push({ref: G.str(G.field(a, "ref")), attr: G.str(G.field(G.field(a, "target"), "attribute")), val: G.num(G.field(a, "val")),
                minRank: intOr(G.field(c, "minRank"), 0), maxRank: intOr(G.field(c, "maxRank"), 999), equalRank: intOr(G.field(c, "equalRank"), -1),
                mastery: G.str(G.field(c, "mastery"))});
        }
        var st = G.field(inf, "steps");
        for (i in 0...G.len(st)) {
            var s = G.at(st, i);
            var c = G.field(s, "cond");
            var p = G.field(s, "props");
            var status = G.field(p, "status");
            var effects:Array<Effect> = [];
            var ef = G.field(s, "effects");
            for (k in 0...G.len(ef)) {
                var e = G.at(ef, k);
                var sc:Array<Scal> = [];
                var list = G.field(e, "scaling");
                for (j in 0...G.len(list)) {
                    var x = G.at(list, j);
                    var xc = G.field(x, "conds");
                    sc.push({atb: G.str(G.field(x, "atb")), ratio: G.num(G.field(x, "ratio")), minRank: intOr(G.field(xc, "minRank"), 0),
                        maxRank: intOr(G.field(xc, "maxRank"), 999), equalRank: intOr(G.field(xc, "equalRank"), -1)});
                }
                var affinity = G.str(G.field(e, "affinity"));
                var physical = false;
                if (affinity != "") try physical = G.callStatic("HSkill", "isPhysical", [affinity]) == true catch (_:Dynamic) {}
                effects.push({uid: SkillData.nextUid++, kind: SkillData.effectName(G.field(e, "effect")), affinity: affinity, physical: physical, base: G.num(G.field(e, "baseVal")),
                    scaling: sc, dynVal: Std.int(G.num(G.field(e, "dynVal"))), status: G.str(G.field(e, "status")), raw: e});
            }
            var area = G.field(p, "area");
            var target = G.field(status, "target");
            var loop = G.field(p, "loop");
            steps.push({id: G.str(G.field(s, "id")), on: SkillData.onName(G.field(s, "on")), type: SkillData.stepTypeName(G.field(s, "type")),
                mastery: G.str(G.field(c, "mastery")),
                masteryExclude: G.str(G.field(c, "masteryExclude")), minRank: intOr(G.field(c, "minRank"), 0), maxRank: intOr(G.field(c, "maxRank"), 999),
                equalRank: intOr(G.field(c, "equalRank"), -1), duration: G.field(s, "duration"), tick: G.field(loop, "tick"),
                targetCd: G.num(G.field(area, "targetCooldown")), spread: (Std.int(G.num(G.field(loop, "flags"))) & 1) != 0,
                hitFilter: Std.int(G.num(G.field(area, "hitFilter"))), ignoreMain: G.field(area, "ignoreMainTarget") == true,
                status: G.str(G.field(status, "ref")),
                statusSelf: target == null || G.num(target) == 0, effects: effects});
        }
        analyse(G.str(G.field(inf, "script")));
    }

    static function intOr(v:Dynamic, d:Int):Int return v == null ? d : Std.int(G.num(v));

    /** The skill's variable `name` at this rank with these runes (rune vars, then rank overrides, then the skill's own). */
    public function v(name:String, rank:Int, runes:Array<String>):Null<Float> {
        if (name == null || name == "") return null;
        var key = name + "|" + rank + "|" + runes.join(",");
        if (varCache.exists(key)) return varCache.get(key);
        var out:Null<Float> = null;
        for (m in masteries) if (runes.indexOf(m.id) >= 0) {
            var x = G.field(m.vars, name);
            if (x != null) { out = G.num(x); break; }
        }
        if (out == null) {
            var bestMin = -1;
            for (o in rankOverride) if (o.minRank <= rank && o.minRank > bestMin) {
                var x = G.field(o.vars, name);
                if (x != null) { out = G.num(x); bestMin = o.minRank; }
            }
        }
        if (out == null) {
            var x = G.field(vars, name);
            if (x != null) out = G.num(x);
        }
        varCache.set(key, out);
        return out;
    }

    /** A number of the data that may also be a variable name ("dur1"). */
    public function num(raw:Dynamic, rank:Int, runes:Array<String>, d:Float):Float {
        if (raw == null) return d;
        if (Std.isOfType(raw, String)) {
            var s:String = raw;
            if (s == "") return d;
            var f = Std.parseFloat(s);
            if (!Math.isNaN(f)) return f;
            var x = v(s, rank, runes);
            return x == null ? d : x;
        }
        return G.num(raw);
    }

    public function cooldownWith(runes:Array<String>):Float {
        for (m in masteries) if (runes.indexOf(m.id) >= 0 && m.cooldown != null) return m.cooldown;
        return cooldown;
    }

    public function durationWith(runes:Array<String>):Float {
        for (m in masteries) if (runes.indexOf(m.id) >= 0 && m.duration != null) return m.duration;
        return duration;
    }

    public static function rankOk(min:Int, max:Int, equal:Int, rank:Int):Bool
        return rank >= min && rank <= max && (equal < 0 || rank == equal);

    public function stepActive(s:Step, rank:Int, runes:Array<String>):Bool {
        if (s.mastery != "" && runes.indexOf(s.mastery) < 0) return false;
        if (s.masteryExclude != "" && runes.indexOf(s.masteryExclude) >= 0) return false;
        return rankOk(s.minRank, s.maxRank, s.equalRank, rank);
    }

    public function affixActive(a:AffixDef, rank:Int, runes:Array<String>):Bool {
        if (a.mastery != "" && runes.indexOf(a.mastery) < 0) return false;
        return rankOk(a.minRank, a.maxRank, a.equalRank, rank);
    }

    public function step(id:String):Step {
        for (s in steps) if (s.id == id) return s;
        return null;
    }

    // ---------------------------------------------------------------- scripts

    static var reHandler = ~/function\s+([A-Za-z0-9_]+)\s*\(/g;
    static var reMod = ~/\.(dmgMult|critChance|critDmgMult|magicArmorIgnore|armorIgnore)\s*(\+=|-=|=)\s*(vars\.([A-Za-z0-9_]+)|[0-9.]+)/g;
    static var reBlockComment = ~/\/\*[\s\S]*?\*\//g;
    static var reLineComment = ~/\/\/[^\n]*/g;
    static var reSkill = ~/(skillId|kind)\s*==\s*Skill\.([A-Za-z0-9_]+)/;
    static var reRank = ~/rank\s*>=\s*([0-9]+)/;
    static var reMastery = ~/hasMastery\(\s*Mastery\.([A-Za-z0-9_]+)\s*\)/;
    static var reHasSkill = ~/hasSkill\(\s*Skill\.([A-Za-z0-9_]+)\s*\)/;
    static var reChance = ~/checkProba\(\s*vars\.([A-Za-z0-9_]+)\s*\)/;
    static var rePlay = ~/(playStep|chainStep)\(\s*Steps\.([A-Za-z0-9_]+)/g;
    static var reChain = ~/chainStep\(\s*Steps\.[A-Za-z0-9_]+[^;]*?vars\.[A-Za-z0-9_]+\s*,\s*vars\.([A-Za-z0-9_]+)/;
    static var reStatus = ~/addStatus\(\s*([A-Za-z0-9_.]+)\s*,\s*Skill\.([A-Za-z0-9_]+)\s*\)/g;
    static var reDyn = ~/setDynVal\(\s*[0-9]\s*,\s*[A-Za-z0-9_]+\.amount\s*\*\s*vars\.([A-Za-z0-9_]+)\s*\)/;
    static var reTimer = ~/>\s*vars\.([A-Za-z0-9_]+)/;
    static var reCall = ~/([A-Za-z0-9_]+)\s*\(/g;
    static var reCharge = ~/(chargePrayer|addCharges)\s*\(/g;
    static var reCdr = ~/reduceCooldown\(\s*(Skill\.([A-Za-z0-9_]+)|skill\.kind)\s*,\s*vars\.([A-Za-z0-9_]+)/g;
    static var reCdrWeapons = ~/reduceWeaponsCooldown\(\s*vars\.([A-Za-z0-9_]+)/g;
    static var reConsume = ~/[cC]onsumeStatus\s*\(/g;
    static var reNotHasSkill = ~/!\s*hasSkill\(\s*Skill\.([A-Za-z0-9_]+)\s*\)/;

    /** The body of every function of the script, by name (braces matched). */
    static function functions(script:String):Map<String, String> {
        var out = new Map<String, String>();
        var pos = 0;
        while (reHandler.matchSub(script, pos)) {
            var name = reHandler.matched(1);
            var p = reHandler.matchedPos();
            var open = script.indexOf("{", p.pos + p.len);
            if (open < 0) break;
            var close = matching(script, open, "{", "}");
            out.set(name, script.substring(open + 1, close));
            pos = close;
        }
        return out;
    }

    /** Index of the bracket closing the one at `open`. */
    static function matching(s:String, open:Int, a:String, b:String):Int {
        var depth = 0, i = open;
        while (i < s.length) {
            var ch = s.charAt(i);
            if (ch == a) depth++;
            else if (ch == b) { depth--; if (depth == 0) return i; }
            i++;
        }
        return s.length;
    }

    /**
     * The `if` blocks of a body with the conditions the calculator follows: `rank >= N`, `hasMastery(…)`,
     * `hasSkill(…)` (negated ones are not followed). A block is the braces after the condition, or the
     * single statement up to its `;`.
     */
    static function conditionsRaw(body:String):Array<{start:Int, end:Int, cond:String}> {
        var out = [];
        var pos = 0;
        while (true) {
            var i = body.indexOf("if", pos);
            if (i < 0) break;
            pos = i + 2;
            if (i > 0 && ~/[A-Za-z0-9_]/.match(body.charAt(i - 1))) continue;
            var j = i + 2;
            while (j < body.length && body.charAt(j) == " ") j++;
            if (j >= body.length || body.charAt(j) != "(") continue;
            var close = matching(body, j, "(", ")");
            var k = close + 1;
            while (k < body.length && StringTools.isSpace(body, k)) k++;
            var end = k < body.length && body.charAt(k) == "{" ? matching(body, k, "{", "}") : body.indexOf(";", k);
            if (end < 0) end = body.length;
            out.push({start: k, end: end, cond: body.substring(j + 1, close)});
        }
        return out;
    }

    static function conditions(body:String):Array<{start:Int, end:Int, rank:Int, mastery:String, skill:String}> {
        var out = [];
        var pos = 0;
        while (true) {
            var i = body.indexOf("if", pos);
            if (i < 0) break;
            pos = i + 2;
            if (i > 0 && ~/[A-Za-z0-9_]/.match(body.charAt(i - 1))) continue;
            var j = i + 2;
            while (j < body.length && body.charAt(j) == " ") j++;
            if (j >= body.length || body.charAt(j) != "(") continue;
            var close = matching(body, j, "(", ")");
            var cond = body.substring(j + 1, close);
            var k = close + 1;
            while (k < body.length && StringTools.isSpace(body, k)) k++;
            var end = k < body.length && body.charAt(k) == "{" ? matching(body, k, "{", "}") : body.indexOf(";", k);
            if (end < 0) end = body.length;
            var rank = reRank.match(cond) ? Std.parseInt(reRank.matched(1)) : 0;
            var mastery = reMastery.match(cond) && cond.indexOf("!hasMastery") < 0 ? reMastery.matched(1) : "";
            var skill = reHasSkill.match(cond) && cond.indexOf("!hasSkill") < 0 ? reHasSkill.matched(1) : "";
            if (rank > 0 || mastery != "" || skill != "") out.push({start: k, end: end, rank: rank, mastery: mastery, skill: skill});
        }
        return out;
    }

    static function filterOf(body:String):Filter {
        var skill = reSkill.match(body) ? reSkill.matched(2) : "";
        return {skill: skill, attacks: body.indexOf("isBaseAttack") >= 0 || body.indexOf("isFinalAttack") >= 0,
            combo: body.indexOf("isFinalCombo") >= 0 || body.indexOf("isFinalAttack") >= 0, magic: body.indexOf("isMagic") >= 0,
            crit: body.indexOf(".critical") >= 0, weaponSkill: body.indexOf("isWeaponSkill") >= 0, classSkill: body.indexOf("isClassSkill") >= 0,
            anySkill: body.indexOf("isSkill") >= 0, status: skill == "" && (body.indexOf(".status != null") >= 0 || body.indexOf("status.owner") >= 0),
            ally: body.indexOf("isAlly(") >= 0, self: ~/skillId\s*==\s*skill\.kind/.match(body),
            notArsenal: ~/!\s*[A-Za-z0-9_.]*isFromArsenal\(/.match(body),
            fromArsenal: body.indexOf("isFromArsenal(") >= 0 && !~/!\s*[A-Za-z0-9_.]*isFromArsenal\(/.match(body)};
    }

    /**
     * What the script does, read from its text: modifiers set in …Eval handlers (dmgMult, critChance,
     * critDmgMult, armour ignore), and procs (steps played, statuses added) with their trigger, chance and
     * the conditions of the block they are in (rank, rune, another skill of the hero). Helper functions the
     * handlers call are read with them, and steps played from `onStep` follow the step that starts them.
     * What is not one of these patterns is listed in `unknown` and not valued.
     */
    function analyse(script:String):Void {
        if (script == null || script == "") return;
        // commented-out code does nothing
        script = reLineComment.replace(reBlockComment.replace(script, ""), "");
        // variables that name a skill (`var Buff = Skill.X;`): read as the skill
        var reAlias = ~/var\s+([A-Za-z0-9_]+)\s*=\s*(Skill\.[A-Za-z0-9_]+)\s*;/;
        var guard = 0;
        while (reAlias.match(script) && guard++ < 20) {
            var name = reAlias.matched(1), value = reAlias.matched(2);
            script = reAlias.replace(script, "");
            script = new EReg("\\b" + name + "\\b", "g").replace(script, value);
        }
        // a status that consumes itself, unless the hero has some skill (`if (… || !hasSkill(X)) …consumeStatus`)
        var cp = 0;
        while (reConsume.matchSub(script, cp)) {
            var p = reConsume.matchedPos();
            cp = p.pos + p.len;
            consumes = true;
            for (b in conditionsRaw(script)) if (p.pos >= b.start && p.pos <= b.end && reNotHasSkill.match(b.cond)) consumeUnless = reNotHasSkill.matched(1);
        }
        var fns = functions(script);
        for (name => body0 in fns) {
            if (!StringTools.startsWith(name, "on") || name == "onStep") continue;
            var body = body0;
            var pos = 0;
            while (reCall.matchSub(body0, pos)) {
                var callee = reCall.matched(1);
                var p = reCall.matchedPos();
                pos = p.pos + p.len;
                if (callee != name && fns.exists(callee) && !StringTools.startsWith(callee, "on")) body += "\n" + fns.get(callee);
            }
            var trigger = triggerOf(name, body);
            var n = read(name, body, trigger, filterOf(body), 0, "", "", fns);
            if (n == 0 && name != "checkEnabled" && name != "shouldHighlightSkill") unknown.push(name);
        }
    }

    /** Reads the modifiers and procs of one handler body; returns how many were found. */
    function read(name:String, body:String, trigger:String, filter:Filter, rank0:Int, mastery0:String, skill0:String, fns:Map<String, String>):Int {
        var blocks = conditions(body);
        function condAt(p:Int):{rank:Int, mastery:String, skill:String} {
            var r = {rank: rank0, mastery: mastery0, skill: skill0};
            for (b in blocks) if (p >= b.start && p <= b.end) {
                if (b.rank > r.rank) r.rank = b.rank;
                if (b.mastery != "") r.mastery = b.mastery;
                if (b.skill != "") r.skill = b.skill;
            }
            return r;
        }
        var found = 0;
        var own = name == "onDamageEval" || name == "onHealEval" || name == "onDamage" || name == "onHit" || name == "onProc";
        var heal = name.indexOf("Heal") >= 0;
        var mp = 0;
        // modifiers of hits the skill deals (not of hits it receives); those of single steps are not followed
        var dealt = name == "onInflictDamageEval" || name == "onDamageEval" || name == "onHealEval" || name == "onInflictHealEval";
        if (!dealt || body.indexOf("stepId") >= 0) mp = body.length;
        while (reMod.matchSub(body, mp)) {
            var p = reMod.matchedPos();
            mp = p.pos + p.len;
            var c = condAt(p.pos);
            var value = reMod.matched(4) != null ? reMod.matched(4) : reMod.matched(3);
            var op = reMod.matched(2);
            // a value set outright, or for the skill's own steps (stepId), concerns the skill's own hits only
            var ownOnly = own || (op == "=" && filter.skill == "");
            mods.push({stat: reMod.matched(1), value: value, sign: op == "-=" ? -1.0 : 1.0, filter: filter, rankMin: c.rank, mastery: c.mastery,
                needSkill: c.skill, own: ownOnly, heal: heal});
            found++;
        }
        if (trigger == "") return found;
        var chp = 0;
        while (reCharge.matchSub(body, chp)) {
            var p = reCharge.matchedPos();
            chp = p.pos + p.len;
            var c = condAt(p.pos);
            charges.push({trigger: trigger, filter: filter, rankMin: c.rank, mastery: c.mastery});
            found++;
        }
        for (re in [reCdr, reCdrWeapons]) {
            var rp = 0;
            while (re.matchSub(body, rp)) {
                var p = re.matchedPos();
                rp = p.pos + p.len;
                var c = condAt(p.pos);
                var target = re == reCdrWeapons ? "weapons" : (re.matched(2) != null ? re.matched(2) : "self");
                var time = re == reCdrWeapons ? re.matched(1) : re.matched(3);
                cdrs.push({trigger: trigger, filter: filter, target: target, time: time, chance: reChance.match(body) ? reChance.matched(1) : "",
                    rankMin: c.rank, mastery: c.mastery, needSkill: c.skill});
                found++;
            }
        }
        // plays and statuses, grouped by the conditions of their block
        var groups = new Map<String, ScriptProc>();
        var order = [];
        function group(p:Int):ScriptProc {
            var c = condAt(p);
            var key = c.rank + "|" + c.mastery + "|" + c.skill;
            var g = groups.get(key);
            if (g == null) {
                g = {trigger: trigger, filter: filter, chance: reChance.match(body) ? reChance.matched(1) : "", steps: [],
                    chain: reChain.match(body) ? reChain.matched(1) : "", statuses: [], dyn: reDyn.match(body) ? reDyn.matched(1) : "",
                    every: trigger == "timer" && reTimer.match(body) ? reTimer.matched(1) : "", rankMin: c.rank, mastery: c.mastery, needSkill: c.skill};
                groups.set(key, g);
                order.push(g);
            }
            return g;
        }
        var sp = 0;
        while (rePlay.matchSub(body, sp)) {
            var p = rePlay.matchedPos();
            sp = p.pos + p.len;
            var step = rePlay.matched(2);
            group(p.pos).steps.push(step);
            // steps started from onStep when this one plays
            var onStep = fns.get("onStep");
            if (onStep != null && onStep.indexOf("Steps." + step) >= 0) {
                var c = condAt(p.pos);
                found += read("onStep", onStep, trigger, filter, c.rank, c.mastery, c.skill, new Map());
            }
        }
        var ap = 0;
        while (reStatus.matchSub(body, ap)) {
            var p = reStatus.matchedPos();
            ap = p.pos + p.len;
            group(p.pos).statuses.push({id: reStatus.matched(2), self: reStatus.matched(1) == "owner"});
        }
        for (g in order) procs.push(g);
        return found + order.length;
    }

    /** What makes a handler run, in the calculator's terms ("" = not valued). */
    static function triggerOf(name:String, body:String):String {
        return switch (name) {
            case "onInflictDamage", "onInflictDamageEval", "onInflictHit": "damageHit";
            case "onDamage", "onHit", "onDamageEval", "onProc": "ownHit";
            case "onInflictHeal", "onInflictHealEval", "onHealEval": "healHit";
            case "onSkillProc", "onUseSkill": "cast";
            case "onRegUpdate", "onUpdate":
                if (reTimer.match(body)) "timer" else if (body.indexOf("hasStatus") >= 0) "always" else "";
            case "onInflictStatusEval", "onTryAddStatus", "onApplyKnockback": "statusInflict";
            case "onKill": "kill";
            case "onPrayerCharged", "onPrayerTrigger": "prayer";
            case "onGameBeat":
                if (body.indexOf("AttackBlock") >= 0 || body.indexOf("BlockWellTimed") >= 0) "block" else "";
            case "onReceiveDamage", "onReceiveDamageEval": "received";
            default: "";
        }
    }
}

/** Skill records read once per game session, and the game's enum names. */
class SkillData {
    public static var nextUid = 0;
    static var cache = new Map<String, SkillDef>();

    public static function get(id:String):SkillDef {
        if (id == null || id == "") return null;
        if (cache.exists(id)) return cache.get(id);
        var inf = GameData.skill(id);
        var d:SkillDef = null;
        if (inf != null) try d = new SkillDef(inf) catch (e:Dynamic) DebugLog.error("skill data " + id, e);
        cache.set(id, d);
        return d;
    }

    static var names = new Map<String, Map<Int, String>>();

    /** Name of a value of an enum of the data (`_Data.<Abstract>_Impl_.getName`). */
    static function enumName(abs:String, v:Dynamic):String {
        if (v == null) return "";
        var i = Std.int(G.num(v));
        var m = names.get(abs);
        if (m == null) { m = new Map(); names.set(abs, m); }
        if (m.exists(i)) return m.get(i);
        var n = Std.string(i);
        try n = G.str(G.callStatic(abs, "getName", [i])) catch (_:Dynamic) {}
        m.set(i, n);
        return n;
    }

    public static function effectName(v:Dynamic):String return enumName("_Data.Skill_steps_effects_effect_Impl_", v);
    public static function onName(v:Dynamic):String return enumName("_Data.Skill_steps_on_Impl_", v);
    public static function typeName(v:Dynamic):String return enumName("_Data.Skill_type_Impl_", v);
    public static function stepTypeName(v:Dynamic):String return enumName("_Data.Skill_steps_type_Impl_", v);
}
