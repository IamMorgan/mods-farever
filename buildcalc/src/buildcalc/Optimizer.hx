package buildcalc;

import buildcalc.Items.Candidate;
import buildcalc.Augments.Augment;
import buildcalc.Model.Build;
import buildcalc.Model.Eval;

typedef BuildResult = {
    var build:Build;
    var worn:Build;
    var axes:Array<Float>;      // damage, defense, health, healing of the chosen build
    var current:Array<Float>;   // the same for what the hero has now
    var best:Array<Float>;      // the best value each axis can reach alone
    var changed:Int;            // equipment slots that differ from what the hero wears
    var stats:Map<String, Float>;
    var pool:Int;
    var talentPoints:Int;
    var eval:Eval;              // the chosen build: dps, heals, weapon skills
    var now:Eval;               // the same for what the hero has now
    var infusions:Map<String, Int>;
    var fight:Float;            // seconds of the real fight the values are calibrated by (0: none)
    var reasons:Array<{slot:Int, item:Dynamic, dps:Float, heal:Float, infDps:Float, infHeal:Float, infusion:String, onlyInfusion:Bool}>;
    /** Items to show instead of the worn ones whose infusion the build changes: copies with the new infusion (the tooltip shows it). */
    var display:Map<Int, Dynamic>;
}

typedef TalentNode = {id:String, tier:Int, branch:Int, max:Int};

/** A piece of work done a little at a time: `step` does one small part and says when all is done. */
interface Task {
    function step():Bool;
}

/**
 * Picks the whole build from what the game data allows and what can be obtained now:
 *  - equipment: every obtainable item the hero can wear (weapons upgraded to their maximum: only weapons
 *    can be upgraded, ui.win.GearUpgrade) and what the hero wears (as it is), one per slot
 *    (st.Equipment.isEquippableOnSlot), main weapon melee or ranged as asked; for each item the best augment
 *    of each type (enchantments, gems, sigils);
 *  - infusions of the items that can take one (HInfusion.canBeInfused; pattern obtainable), ranks by the
 *    number of items (HInfusion.getRankFromStacks), the item's infusion bonus where the faction matches;
 *  - talents within the hero's points and the tree's rules (root first, Const.Hero.Talents_TierThresholds
 *    points in the branch below a tier — st.player.HeroSpecialization.implInlineSetTalentRank);
 *  - class skills for the hero's slots and their runes (Const.Hero.UnlockLevel_SecondMastery: two).
 * The search starts from what the hero has and only takes changes that raise the score, so the result is
 * never worse than the current build. First each axis alone (its maximum), then Σ weight × axis / maximum.
 * The work runs a few milliseconds per frame (`run`), so the game does not stop.
 */
class Optimizer {
    var hero:Dynamic;
    public var settings:State.Settings;
    public var model:Model;
    var slotNames = new Map<Int, String>();
    var factor = new Map<Int, Float>();
    public var pools = new Map<Int, Array<Candidate>>();
    var full = new Map<Int, Array<Candidate>>();
    public var worn:Build;
    var poolSize = 0;
    public var infusions:Array<String> = [];
    public var bonusStats:Array<String> = [];
    var infusionRaw = new Map<String, Dynamic>();
    public var tree:Array<TalentNode> = [];
    var thresholds:Array<Int> = [];
    public var points = 0;
    public var classSkills:Array<String> = [];
    public var skillSlots = 0;
    var runesPerSkill = 1;
    public var evals = 0;
    /** Builds valued after which a search starts nothing new. */
    public var evalLimit = 0;

    var tasks:Array<Task> = [];
    public var done = false;
    public var result:BuildResult = null;
    /** What is being done, for the window (0..1 and a word). */
    public var progress = 0.0;
    public var stage = "";
    var t0 = 0.0;
    var all:Array<Candidate> = [];
    var weights:Array<Float>;
    var now:Array<Float>;
    var best:Array<Float> = [0, 0, 0, 0];
    var finalBuild:Build;
    /** The weights of the score: the player's priorities (3 high … 1 low), "not important" = 0.02 (only breaks ties). */
    var used:Array<Float>;
    /**
     * Weight of each priority level: not important, low, medium, high — the agreed TZ (DESIGN.md): High 3, Medium 2,
     * Low 1; "not important" only breaks ties. (The tiers 100/10/1 made every lower priority worthless: all went to damage.)
     */
    static var TIER = [0.01, 1.0, 2.0, 3.0];
    /**
     * Unit of the score's thresholds: the sum of the weights (one axis moving its whole range at weight 1 = 1 / unit). A
     * gain is measured against it, not against the score itself: the score has the worn build in it, so a share of it
     * changed with what is worn (a rune changed made a +0.99% swap a +1.01% one and the whole build came out other).
     */
    public var unit = 1.0;
    /**
     * How far each axis can move: the range between the builds that are best on one axis alone (Prefilter's anchors)
     * and the worn build. An axis counts by the share of its own range a change covers, so a priority means the same
     * on every axis (damage moving +60% does not drown defense moving +8% when defense is the priority).
     */
    public var span:Array<Float> = null;

    /**
     * The score of a build's axis values against `base` (the worn build): Σ weight × (1 + (value − base) / span).
     * Before the spans are known: Σ weight × value / base.
     */
    public function norm(v:Array<Float>, base:Array<Float>, floors:Bool = true):Float {
        var sum = 0.0;
        for (a in 0...4) {
            var sp = span != null ? span[a] : Math.max(1e-9, Math.abs(base[a]));
            sum += used[a] * (1 + (v[a] - base[a]) / sp);
            // below its floor an axis costs FLOOR_COST times its weight: a medium (low) priority keeps 90% (75%) of its
            // value at the start of the search, it is not given up for a higher one
            if (floors && floor != null && floor[a] > 0 && v[a] < floor[a]) sum -= used[a] * FLOOR_COST * (floor[a] - v[a]) / sp;
        }
        return sum;
    }

    /** The least an axis must keep (0: none). */
    public var floor:Array<Float> = null;
    static inline var FLOOR_COST = 10.0;
    /** The TZ: a High priority keeps at least 80% of the most its axis can reach (the highest of the anchors). */
    static inline var HIGH_KEEPS = 0.8;

    /**
     * Floors from what each axis can reach (Prefilter's anchors), not from the build the search starts with: the same
     * for any worn build, so a change the player made does not move them.
     */
    public function setFloors():Void {
        floor = [for (a in 0...4) weights[a] >= 3 && hi != null ? hi[a] * HIGH_KEEPS : 0.0];
        DebugLog.line("priorities: floors (High keeps " + Math.round(HIGH_KEEPS * 100) + "% of the most its axis reaches): " + floor.map(r3).join("/"));
    }

    /**
     * Version of the way builds are valued: raised with every change of the model (shields 2026-10-18 = 2). A last result
     * valued by another version is not a start for the search (it would keep a build the model of now does not choose).
     */
    public static inline var MODEL_VERSION = 2;

    /** The last result for the same questionnaire (null: none). */
    var last:State.LastResult = null;

    /**
     * The last recommended build, rebuilt from the candidates of now (null when one of its items cannot be had now).
     * The search starts from the better of it and the worn build: a recommendation the player followed (a rune, an
     * item, a talent) does not send the search elsewhere, it ends where it ended before, without that change.
     */
    public function seedFromLast():Build {
        if (last == null || last.build == null) return null;
        var b = copy(worn);
        if (last.talents != null) {
            var t = new Map<String, Int>();
            for (e in last.talents) if (e.rank > 0) t.set(e.id, e.rank);
            if (validTalents(t)) b.talents = t;
        }
        if (last.skills != null && last.skills.length > 0 && last.skills.length <= Math.max(skillSlots, worn.skills.length)) {
            var ok = true;
            for (e in last.skills) if (classSkills.indexOf(e.id) < 0) ok = false;
            if (ok) {
                b.skills = [for (e in last.skills) e.id];
                b.runes = [for (e in last.skills) e.id => e.runes.copy()];
            }
        }
        var bySlot = new Map<Int, State.TemplateItem>();
        for (e in last.build) bySlot.set(e.slot, e);
        for (s in Items.SLOTS) {
            var e = bySlot.get(s);
            if (e == null) { if (b.items.get(s) != null) place(b, s, null); continue; }
            var found:Candidate = null;
            var pool = fullPool(s);
            if (pool != null) for (c in pool) if (c.id == e.id && c.real == (e.own == true) && (!c.real || e.upgrade == null || c.upgrade == e.upgrade)) {
                found = c;
                if (!c.real || c == worn.items.get(s)) break;
            }
            if (found == null) {
                DebugLog.line("search: the last result's " + e.id + " (slot " + s + ") cannot be had now: not a start");
                return null;
            }
            if (b.items.get(s) != found) place(b, s, found);
            if (found.infusable && e.infusion != null && (!found.real || e.infusion != found.infusion)) {
                b.infusion.set(s, e.infusion);
                if (e.bonus != null) b.bonus.set(s, e.bonus);
            } else if (found.real && e.infusion == found.infusion) { b.infusion.remove(s); b.bonus.remove(s); }
        }
        return b;
    }

    /** Builds already valued (same items, augments, infusion sets, talents, skills, arsenal): their axes. */
    var memo = new Map<String, Array<Float>>();
    var memoB = new Map<String, Array<Float>>();
    public var memoHits = 0;
    var uids = new haxe.ds.ObjectMap<Dynamic, Int>();
    var uidNext = 0;

    function uidOf(c:Candidate):Int {
        var u = uids.get(c);
        if (u == null) { u = ++uidNext; uids.set(c, u); }
        return u;
    }

    /** What the value of a build depends on, as a key. */
    public function sig(b:Build):String {
        var buf = new StringBuf();
        for (s in Items.SLOTS) {
            var c = b.items.get(s);
            if (c == null) continue;
            buf.add(s); buf.add("="); buf.add(uidOf(c));
            var augs = b.augs.get(s);
            if (augs != null) for (a in augs) { buf.add(","); buf.add(a.id); }
            buf.add(";");
        }
        buf.add("|"); buf.add(model.infusionSig(b));
        buf.add("|"); buf.add(talentKey(b.talents));
        buf.add("|");
        for (id in b.skills) { buf.add(id); if (b.runes.exists(id)) { buf.add("{"); buf.add(b.runes.get(id).join("+")); buf.add("}"); } buf.add(","); }
        buf.add("|"); if (b.arsenal != null) buf.add(b.arsenal.join(","));
        if (model.statsOnly) buf.add("|s");
        return buf.toString();
    }

    /** The axes of a build (valued once: a build met again is not fought again). */
    public function axesOf(b:Build):Array<Float> {
        var k = sig(b);
        var a = memo.get(k);
        if (a != null) { memoHits++; return a; }
        a = model.evaluate(b).axes;
        evals++;
        memo.set(k, a);
        return a;
    }

    public function slotFits(c:Candidate, s:Int):Bool {
        var name = slotNames.get(s);
        if (name == null || name == "") return false;
        try return G.callStatic("st.Equipment", "isEquippableOnSlot", [c.inf, name]) == true catch (_:Dynamic) return false;
    }

    public static function copy(b:Build):Build {
        return {items: b.items.copy(), augs: [for (k => v in b.augs) k => v.copy()], infusion: b.infusion.copy(), bonus: b.bonus.copy(),
            talents: b.talents.copy(), skills: b.skills.copy(), runes: [for (k => v in b.runes) k => v.copy()],
            arsenal: b.arsenal == null ? null : b.arsenal.copy()};
    }

    public static function copyInto(from:Build, to:Build):Void {
        to.items = from.items; to.augs = from.augs; to.infusion = from.infusion; to.bonus = from.bonus;
        to.talents = from.talents; to.skills = from.skills; to.runes = from.runes; to.arsenal = from.arsenal;
    }

    var combat:Combat = null;
    /** Skills that can be chosen for the arsenal and how many (Weapon.isValidArsenalSkill, Hero.getNbArsenalSkillSlots). */
    public var arsenalSlots = 2;
    var arsenalCache = new Map<String, Array<String>>();

    public function arsenalChoices(c:Candidate):Array<String> {
        if (arsenalCache.exists(c.id)) return arsenalCache.get(c.id);
        var out = [];
        for (id in c.skills) {
            var ok = false;
            try ok = G.callStatic("st.item.Weapon", "isValidArsenalSkill", [c.inf, id]) == true catch (_:Dynamic) {}
            if (ok) out.push(id);
        }
        arsenalCache.set(c.id, out);
        return out;
    }

    /** The best set of arsenal skills for the arsenal weapon of `b` (all sets of arsenalSlots of the valid ones). */
    public function bestArsenal(b:Build):Void {
        var c = b.items.get(1);
        if (c == null) { b.arsenal = []; return; }
        var choices = arsenalChoices(c);
        var n = Std.int(Math.min(arsenalSlots, choices.length));
        var sets:Array<Array<String>> = [];
        function pick(from:Int, cur:Array<String>):Void {
            if (cur.length == n) { sets.push(cur.copy()); return; }
            for (i in from...choices.length) { cur.push(choices[i]); pick(i + 1, cur); cur.pop(); }
        }
        pick(0, []);
        if (sets.length <= 1) { b.arsenal = sets.length == 1 ? sets[0] : []; return; }
        var best = sets[0], bestV = -1e30;
        for (set in sets) {
            b.arsenal = set;
            var v = value(b);
            if (v > bestV) { bestV = v; best = set; }
        }
        b.arsenal = best;
    }

    public function settingsWeights():Array<Float> return weights;

    var caps:Array<Int> = null;

    /** Items needed for each set bonus of an infusion (Const.Items.Item_InfusionCaps). */
    public function infusionCaps():Array<Int> {
        if (caps != null) return caps;
        caps = [];
        try {
            var arr = G.field(HlxRuntime.resolveStaticField(G.type("Const"), "Items"), "Item_InfusionCaps");
            for (i in 0...G.len(arr)) caps.push(Std.int(G.num(G.at(arr, i))));
        } catch (e:Dynamic) DebugLog.error("infusion caps", e);
        return caps;
    }

    public function new(hero:Dynamic, settings:State.Settings) {
        this.hero = hero;
        // a copy: a click in the window during the calculation does not change it
        this.settings = State.copy(settings);
        t0 = haxe.Timer.stamp();
        weights = [for (p in settings.priorities) (p : Float)];
        if (weights[0] + weights[1] + weights[2] + weights[3] <= 0) weights = [1.0, 0, 0, 0];
        // the priorities weigh as the TZ says (High 3, Medium 2, Low 1, each on the range its axis can move): a lower
        // priority is worth a share of a higher one, it is not given away for any small gain; "not important" only
        // breaks ties (0.01)
        used = [for (w in weights) TIER[Std.int(Math.max(0, Math.min(3, w)))]];
        unit = 0.0;
        for (u in used) unit += u;
        // the last calculation with the same questionnaire: the search also starts from it (see seedFromLast)
        last = State.lastFor(settings);
        if (last != null && last.model != MODEL_VERSION) {
            DebugLog.line("search: the last result (" + last.savedAt + ") was valued by an older model (" + last.model + ", now " + MODEL_VERSION + "): not a start");
            last = null;
        }
        // the plan: data first (a part per frame), then the searches
        tasks.push(new Once(() -> { stage = "data"; prepare(); }));
        tasks.push(new ItemScan(this));
        tasks.push(new Once(() -> pools0()));
        // from here on only values are computed (no game objects are created): its own thread
        tasks.push(new ToWorker());
        tasks.push(new Prefilter(this));
        // the score: Σ weight × (1 + (value − value now) / range of the axis) — each axis counts by the share of
        // what it can reach that a change gives (norm)
        tasks.push(new Once(() -> {
            stage = "weighted";
            for (a in 0...4) best[a] = Math.max(1e-9, now[a]);
            evalLimit = evals + 6000;
        }));
        tasks.push(new Search(this, v -> norm(v, now), 3, b -> finalBuild = b));
        tasks.push(new Once(() -> finish()));
    }

    /**
     * The search runs in a thread of its own, so the game's frames never wait for it: WORK_MS of work, then
     * SLEEP_MS of rest (it takes at most about half of one processor core).
     */
    public static var WORK_MS = 15.0;
    public static var SLEEP_MS = 5.0;
    var threaded = false;
    var workerDone = false;
    var workerError:Dynamic = null;

    function startWorker():Void {
        try {
            sys.thread.Thread.create(() -> {
                try {
                    var slice = haxe.Timer.stamp();
                    while (tasks.length > 0) {
                        if (tasks[0].step()) tasks.shift();
                        if (haxe.Timer.stamp() - slice > WORK_MS / 1000) {
                            Sys.sleep(SLEEP_MS / 1000);
                            slice = haxe.Timer.stamp();
                        }
                    }
                } catch (e:Dynamic) {
                    var stack = "";
                    try stack = haxe.CallStack.toString(haxe.CallStack.exceptionStack()) catch (_:Dynamic) {}
                    workerError = Std.string(e) + " " + stack;
                }
                workerDone = true;
            });
            threaded = true;
            DebugLog.line("optimizer: the search runs in its own thread (" + WORK_MS + " ms work / " + SLEEP_MS + " ms rest)");
        } catch (e:Dynamic) {
            DebugLog.error("thread (the search runs a little each frame instead)", e);
        }
    }

    /** Works for about `ms` milliseconds; true when the whole calculation is done. */
    public function run(ms:Float):Bool {
        if (threaded) {
            if (!workerDone) return false;
            threaded = false;
            if (workerError != null) throw workerError;
            if (finalBuild != null) dress(finalBuild);
            done = true;
            return true;
        }
        var end = haxe.Timer.stamp() + ms / 1000;
        while (!done && haxe.Timer.stamp() < end) {
            if (tasks.length == 0) { done = true; break; }
            if (Std.isOfType(tasks[0], ToWorker)) {
                tasks.shift();
                startWorker();
                if (threaded) return false;
                continue;
            }
            if (tasks[0].step()) tasks.shift();
        }
        return done;
    }

    function prepare():Void {
        Sources.build(hero);
        var names = HlxRuntime.resolveStaticField(G.type("DataCache"), "EQUIPMENT_SLOTS");
        for (s in Items.SLOTS) {
            var name = G.str(G.at(names, s));
            slotNames.set(s, name);
            var f = 1.0;
            try {
                var v = G.field(G.field(Items.typeRecord(name), "slot"), "affixFactor");
                if (v != null) f = G.num(v);
            } catch (_:Dynamic) {}
            factor.set(s, f);
        }
        DebugLog.line("optimizer: slots " + [for (s in Items.SLOTS) s + "=" + slotNames.get(s) + (factor.get(s) != 1 ? " x" + factor.get(s) : "")].join(", "));
        try arsenalSlots = Std.int(G.num(G.call("ent.Hero", "getNbArsenalSkillSlots", [hero]))) catch (e:Dynamic) DebugLog.error("arsenal slots", e);
        worn = currentBuild();
        model = new Model(hero, worn, factor);
        model.idealRanks = settings.ideal;
        // choices inside a fight (rotation, weapon skill slots) follow the player's priorities too
        model.fightWeights = used;
        // the second rotation leaves out the class skills that give nothing to a prioritized fight axis (a heal skill is
        // not left out when healing has a priority)
        var kinds = [];
        if (weights[0] > 0) kinds.push("Damage");
        if (weights[3] > 0) { kinds.push("Heal"); kinds.push("Shield"); }
        model.valuedKinds = kinds.length > 0 ? kinds : ["Damage"];
        DebugLog.line("priorities: damage " + weights[0] + ", defense " + weights[1] + ", health " + weights[2] + ", heal " + weights[3]
            + " -> weights " + used.join("/") + " (score = sum of weight x (1 + (value - worn value) / range of the axis); high 3, medium 2, low 1, not important 0.01;"
            + " a change must gain a share of " + r3(unit) + ", the sum of the weights)" + (last != null ? "; the last result (" + last.savedAt + ") is a start too" : ""));

        readTree();
        readSkills();
        readInfusions();
        DebugLog.line("optimizer: data ready in " + ms(t0) + " ms");
    }

    /** One item of the game data: created and kept when it fits a slot and can be obtained (Items.consider). */
    public function scanItem(inf:Dynamic, level:Int, typeFits:Map<String, Bool>):Void {
        var c = Items.consider(hero, inf, level, typeFits, c -> {
            var ok = false;
            for (s in Items.SLOTS) if (slotFits(c, s)) ok = true;
            ok;
        }, Sources.available);
        if (c != null) all.push(c);
    }

    /** Rank of an item's rarity in the data's order (Data.rarity: Common, Uncommon, Rare, Epic, Legendary). */
    var rarityRanks:Map<String, Int> = null;

    function rarityRank(c:Candidate):Int {
        if (rarityRanks == null) {
            rarityRanks = new Map();
            var all = G.field(GameData.data("rarity"), "all");
            for (i in 0...G.len(all)) rarityRanks.set(G.str(G.field(G.at(all, i), "id")), i);
        }
        var r = G.str(G.field(c.inf, "rarity"));
        return rarityRanks.exists(r) ? rarityRanks.get(r) : 0;
    }

    function pools0():Void {
        // the hero's own items (bag, mail, bank), as they are, that the hero can wear
        var level = Std.int(G.num(G.field(hero, "_level")));
        var owned = [];
        for (item in Sources.ownItems) try {
            if (!Items.isGear(item)) continue;
            var inf = G.field(item, "inf");
            var ok = true;
            try ok = G.callStatic("HItem", "hasUnitAptitude", [inf, hero]) == true catch (_:Dynamic) {}
            if (!ok || G.num(G.field(inf, "level")) > level) continue;
            var c = Items.candidate(item, "owned");
            var fits = false;
            for (sl in Items.SLOTS) if (slotFits(c, sl)) fits = true;
            if (!fits) continue;
            c.realAugs = cast Augments.inItem(hero, item);
            all.push(c);
            owned.push(c.id + (c.upgrade > 0 ? "+" + c.upgrade : "") + (c.infusion != "" ? "[" + c.infusion + "]" : ""));
        } catch (e:Dynamic) DebugLog.error("owned item", e);
        DebugLog.line("optimizer: the hero's own items that fit (bag, mail, bank): " + (owned.length == 0 ? "none" : owned.join(", ")));
        poolSize = all.length;
        for (s in Items.SLOTS) {
            var list = [];
            var w = worn.items.get(s);
            if (w != null && (s != 0 || w.ranged == settings.ranged)) list.push(w);
            var minRarity = w != null ? rarityRank(w) : 0;
            for (c in all) {
                if (!slotFits(c, s)) continue;
                if (s == 0 && c.ranged != settings.ranged) continue; // main weapon: melee or ranged as asked

                list.push(c);
            }
            full.set(s, list);
        }
        // game objects are made here, on the game's thread: the search thread only reads and fills them. A copy of each
        // real item that may be infused again (Model.probe) and the slot list of each created item (Model.createdAffixes)
        var made = 0;
        for (sl in Items.SLOTS) for (c in full.get(sl)) {
            if (c.real) {
                if (c.infusable && c.probe == null) { try c.probe = G.call("st.Item", "clone", [c.item, null]) catch (e:Dynamic) DebugLog.error("probe " + c.id, e); made++; }
            } else if (G.field(c.item, "slots") == null) Items.setSlots(c.item, []);
        }
        for (sl => c in worn.items) if (c != null && c.infusable && c.probe == null) { try c.probe = G.call("st.Item", "clone", [c.item, null]) catch (e:Dynamic) DebugLog.error("probe " + c.id, e); made++; }
        DebugLog.line("optimizer: " + made + " copies of the hero's items made for trying infusions (on the game's thread)");
        now = model.evaluate(worn).axes;
        DebugLog.line("optimizer: " + all.length + " obtainable items; per slot " + [for (s in Items.SLOTS) s + ":" + full.get(s).length].join(" ") + " (" + ms(t0) + " ms)");
    }

    public function fullPool(s:Int):Array<Candidate> return full.get(s);

    static function ms(t0:Float):Int return Math.round((haxe.Timer.stamp() - t0) * 1000);

    /** What the hero has now: worn items with their augments, talents, class skills and runes. */
    function currentBuild():Build {
        var b:Build = {items: new Map(), augs: new Map(), infusion: new Map(), bonus: new Map(), talents: new Map(), skills: [], runes: new Map(), arsenal: []};
        var content = G.field(G.call("ent.Hero", "get_equipment", [hero]), "content");
        for (s in Items.SLOTS) {
            var entry = G.at(content, s);
            var item = entry == null ? null : G.field(entry, "item");
            if (item == null || !Items.isGear(item)) continue;
            var c = Items.candidate(item, "equipped");
            b.items.set(s, c);
            b.augs.set(s, Augments.inItem(hero, item));
            c.realAugs = b.augs.get(s);
            if (Items.slotsTemplate == null && G.field(item, "slots") != null) Items.slotsTemplate = G.field(item, "slots");
            var found = [for (a in b.augs.get(s)) a.id + ":" + G.len(G.call("st.item.Gear", "getSlotAffixes", [item, a.raw]))];
            DebugLog.line("  worn " + s + " " + c.id + ": slots " + G.str(G.field(G.field(item, "slots"), "array")) + " -> " + found.join(",")
                + "; infusion " + c.infusion + "; upgrade " + c.upgrade);
            if (s == 1) {
                // the arsenal skills the hero chose for this weapon (HeroSpecialization.getArsenalSkills)
                for (id in GameData.arsenalSkills(hero, G.field(c.inf, "id"))) b.arsenal.push(id);
                DebugLog.line("  arsenal skills of " + c.id + ": " + b.arsenal.join(",") + " (slots " + arsenalSlots + ")");
            }
        }
        var trees = G.field(G.field(hero, "inf"), "talentTrees");
        if (G.len(trees) > 0) {
            var talents = G.field(G.at(trees, 0), "talents");
            for (i in 0...G.len(talents)) {
                var id = GameData.idOf(G.field(G.at(talents, i), "skill"));
                var r = GameData.talentRank(hero, id);
                if (r > 0) b.talents.set(id, r);
            }
        }
        var active = GameData.activeMasteries(hero);
        var list = G.field(hero, "skills");
        for (i in 0...G.len(list)) {
            var def = SkillData.get(G.str(G.field(G.field(G.at(list, i), "inf"), "id")));
            if (def == null || def.type != "ClassSkill" || b.skills.indexOf(def.id) >= 0) continue;
            b.skills.push(def.id);
            b.runes.set(def.id, GameData.skillMasteries(def.inf, active));
        }
        DebugLog.line("worn build: " + describe(b));
        return b;
    }

    function readTree():Void {
        try {
            var arr = G.field(HlxRuntime.resolveStaticField(G.type("Const"), "Hero"), "Talents_TierThresholds");
            for (i in 0...G.len(arr)) thresholds.push(Std.int(G.num(G.at(arr, i))));
        } catch (e:Dynamic) DebugLog.error("tier thresholds", e);
        try points = Std.int(G.num(G.call("st.player.HeroSpecialization", "getTotalTalentPoints", [G.field(hero, "specialization")]))) catch (_:Dynamic) {}
        var trees = G.field(G.field(hero, "inf"), "talentTrees");
        if (G.len(trees) > 0) {
            var talents = G.field(G.at(trees, 0), "talents");
            for (i in 0...G.len(talents)) {
                var t = G.at(talents, i);
                var id = GameData.idOf(G.field(t, "skill"));
                var d = SkillData.get(id);
                if (d == null) continue;
                tree.push({id: id, tier: Std.int(G.num(G.field(t, "tier"))), branch: Std.int(G.num(G.field(t, "branch"))), max: d.maxPoints > 0 ? d.maxPoints : 1});
            }
        }
        DebugLog.line("talents: " + tree.length + " in the tree, " + points + " points, tier thresholds " + thresholds.join(","));
        for (t in tree) DebugLog.line("  talent " + t.id + " tier " + t.tier + " branch " + t.branch + " max " + t.max + ": " + describeSkill(SkillData.get(t.id)));
    }

    /** What the calculator read from a skill's data and script (for the log). */
    public static function describeSkill(d:buildcalc.SkillData.SkillDef):String {
        return "affixes " + [for (a in d.affixes) a.ref + " " + a.attr + " " + a.val + " r" + a.minRank + "-" + a.maxRank + (a.mastery != "" ? " " + a.mastery : "")].join("; ")
            + "; modifiers " + [for (m in d.mods) m.stat + (m.sign < 0 ? "-=" : "+=") + m.value + (m.filter.skill != "" ? "@" + m.filter.skill : "")
                + (m.filter.attacks ? "@attacks" : "") + (m.own ? "@own" : "") + (m.rankMin > 0 ? " r" + m.rankMin : "")].join("; ")
            + "; procs " + [for (p in d.procs) p.trigger + "(" + p.steps.join("+") + [for (s in p.statuses) "+" + s.id].join("") + (p.chance != "" ? " chance " + p.chance : "")
                + (p.rankMin > 0 ? " r" + p.rankMin : "") + (p.needSkill != "" ? " needs " + p.needSkill : "") + ")"].join("; ")
            + (d.charges.length > 0 ? "; charged by " + [for (c in d.charges) c.trigger].join(",") : "")
            + (d.cdrs.length > 0 ? "; cooldown cut " + [for (c in d.cdrs) c.trigger + ">" + c.target + " " + c.time].join(",") : "")
            + (d.unknown.length > 0 ? "; not valued " + d.unknown.join(",") : "");
    }

    function readSkills():Void {
        var level = G.num(G.field(hero, "_level"));
        var list = G.field(G.field(hero, "inf"), "skills");
        for (i in 0...G.len(list)) {
            var e = G.at(list, i);
            var d = SkillData.get(GameData.idOf(G.field(e, "skill")));
            if (d == null || d.type != "ClassSkill") continue;
            if (G.num(G.field(e, "level")) > level) continue;
            classSkills.push(d.id);
        }
        var slots = 0;
        try slots = G.len(G.field(G.field(G.field(hero, "specialization"), "skillSlots"), "array")) catch (_:Dynamic) {}
        skillSlots = worn.skills.length > 0 ? worn.skills.length : slots;
        try {
            var second = G.num(G.field(HlxRuntime.resolveStaticField(G.type("Const"), "Hero"), "UnlockLevel_SecondMastery"));
            if (second > 0 && level >= second) runesPerSkill = 2;
        } catch (e:Dynamic) DebugLog.error("UnlockLevel_SecondMastery", e);
        DebugLog.line("skills: class skills learnt " + classSkills.join(",") + "; slots " + skillSlots + " (skillSlots list " + slots + "); runes per skill " + runesPerSkill);
        for (id in classSkills) {
            var d = SkillData.get(id);
            DebugLog.line("  skill " + id + " cd " + d.cooldown + " cast " + d.duration + " runes " + [for (m in d.masteries) m.id].join(",")
                + " steps " + [for (s in d.steps) s.on + "/" + s.type + (s.mastery != "" ? "[" + s.mastery + "]" : "") + ":" + [for (e in s.effects) e.kind].join("+") + (s.status != "" ? ">" + s.status : "")].join(" ")
                + "; " + describeSkill(d));
        }
    }

    function readInfusions():Void {
        try {
            var list = G.callStatic("HInfusion", "getAllInfusions", []);
            var mine = model.infusionCounts(worn);
            for (i in 0...G.len(list)) {
                var id = G.str(G.at(list, i));
                var pattern = "";
                try pattern = G.str(G.field(G.callStatic("HInfusion", "getInfusionPattern", [id]), "id")) catch (_:Dynamic) {}
                var ok = mine.exists(id) || pattern == "" || Sources.available(pattern);
                var d = SkillData.get(id);
                DebugLog.line("  infusion " + id + " pattern " + pattern + " " + (ok ? "obtainable (" + Sources.where(pattern) + ")" : "not obtainable now")
                    + (d != null ? "; " + describeSkill(d) : ""));
                if (ok) { infusions.push(id); infusionRaw.set(id, G.at(list, i)); }
            }
            var apt = G.callStatic("HInfusion", "getInfusionBonusAptitude", []);
            var sc = G.field(apt, "atbScaling");
            for (i in 0...G.len(sc)) bonusStats.push(G.str(G.field(G.at(sc, i), "endAtb")));
        } catch (e:Dynamic) DebugLog.error("infusions", e);
        DebugLog.line("infusions: " + infusions.length + " usable; bonus attributes " + bonusStats.join(","));
        model.bonusStats = bonusStats;
    }

    // ---------------------------------------------------------------- search helpers

    public var score:Array<Float>->Float;

    /** What the hero's build has that the model cannot value: a change must keep it. */
    public var keep:Map<String, Bool> = null;

    public function keepsUnvalued(b:Build):Bool {
        if (keep == null) {
            keep = model.unvalued(worn);
            DebugLog.line("optimizer: kept because the model cannot value them: " + [for (id in keep.keys()) id].join(", "));
        }
        var has = new Map<String, Bool>();
        for (src in model.sources(b)) has.set(src.def.id, true);
        for (id in keep.keys()) if (!has.exists(id)) return false;
        return true;
    }

    /**
     * The worn main weapon is not of the kind asked (melee / ranged): the search starts with the best weapon of that
     * kind (swaps need a gain over the worn one, which a weapon of the other kind would otherwise keep).
     */
    public function startWeapon(b:Build):Void {
        var w = b.items.get(0);
        if (w == null || w.ranged == settings.ranged) return;
        var pool = pools.get(0);
        if (pool == null) return;
        var best:Candidate = null, bestV = -1e30;
        for (c in pool) {
            if (c.ranged != settings.ranged) continue;
            var trial = copy(b);
            place(trial, 0, c);
            var v = value(trial);
            if (v > bestV) { bestV = v; best = c; }
        }
        if (best != null) {
            place(b, 0, best);
            DebugLog.line("search: the worn main weapon " + w.id + " is " + (w.ranged ? "ranged" : "melee") + ", the search starts with " + best.id);
        } else DebugLog.line("search: no " + (settings.ranged ? "ranged" : "melee") + " main weapon among the candidates: the worn one is kept");
    }

    /**
     * The ranges of the axes, from the builds best on one axis each (`anchors`, made of the items best on that axis
     * alone in each slot) and the worn build: the range of an axis is its highest value minus its lowest over these
     * builds (at least 5% of its value now, so an axis that can hardly move does not weigh without end).
     */
    /** The most each axis reaches over the anchors (and the worn build). */
    public var hi:Array<Float> = null;

    public function setSpans(anchors:Array<Array<Float>>):Void {
        var lo = now.copy(), hi = now.copy();
        for (x in anchors) for (a in 0...4) {
            if (x[a] < lo[a]) lo[a] = x[a];
            if (x[a] > hi[a]) hi[a] = x[a];
        }
        span = [for (a in 0...4) Math.max(hi[a] - lo[a], 0.05 * Math.max(1e-9, Math.abs(now[a])))];
        this.hi = hi;
        model.fightSpans = [span[0], span[3]];
        var names = ["damage", "defense", "health", "heal"];
        DebugLog.line("priorities: range of each axis over the builds best on one axis (" + anchors.map(x -> x.map(r3).join("/")).join("; ")
            + "): " + [for (a in 0...4) names[a] + " " + r3(lo[a]) + ".." + r3(hi[a]) + " (range " + r3(span[a]) + ", weight " + used[a] + ")"].join(", "));
    }

    /** Base of the second rotation's score (the worn build without the utility class skills). */
    var nowB:Array<Float> = null;

    /** The build's score in the second rotation (no utility class skills), each axis against the worn build there. */
    public function valueB(b:Build):Float {
        if (nowB == null) nowB = model.evaluateWithoutUtility(worn).axes;
        var k = sig(b);
        var a = memoB.get(k);
        if (a == null) {
            a = model.evaluateWithoutUtility(b).axes;
            evals++;
            memoB.set(k, a);
        } else memoHits++;
        return norm(a, nowB, false);
    }

    /**
     * A change is taken only when it does not lose in the second rotation either (no utility class skills used):
     * talents that pay only while a utility skill keeps a buff up are not suggested.
     */
    public function robustOk(from:Build, to:Build):Bool {
        var a = valueB(from), b = valueB(to);
        var ok = b >= a - Math.abs(a) * 1e-6;
        if (!ok) {
            robustRejected++;
            var d = diffOf(from, to);
            if (!refusedLogged.exists(d)) {
                refusedLogged.set(d, true);
                DebugLog.line("refused (loses without the utility class skills " + r3(a) + " -> " + r3(b) + "): " + d);
            }
        }
        return ok;
    }
    public var robustRejected = 0;
    var refusedLogged = new Map<String, Bool>();
    /** Items refused by `place` because the slot does not take them (should stay 0). */
    public var badPlace = 0;

    /** The build as the game allows it: each item fits its slot; an off-hand item that does not work with the main weapon. */
    function checkBuild(b:Build):String {
        var bad = [];
        for (s => c in b.items) if (c != null && !slotFits(c, s)) bad.push("slot " + s + " " + c.id + " cannot be worn there");
        var off = b.items.get(Items.OFFHAND);
        if (off != null && !Items.offhandWorks(b.items.get(0), off))
            bad.push("off-hand " + off.id + " does not work with " + (b.items.get(0) == null ? "-" : b.items.get(0).id) + " (two-handed): not counted");
        return bad.length == 0 ? "OK" : bad.join("; ");
    }

    /** What differs between two builds: items, infusions, talents (for the log). */
    function diffOf(a:Build, b:Build):String {
        var out = [];
        for (s in Items.SLOTS) {
            var x = a.items.get(s), y = b.items.get(s);
            if (x != y) out.push("slot " + s + " " + (x == null ? "-" : x.id) + " -> " + (y == null ? "-" : y.id));
            var ix = a.infusion.exists(s) ? a.infusion.get(s) : "", iy = b.infusion.exists(s) ? b.infusion.get(s) : "";
            if (ix != iy) out.push("infusion " + s + " " + ix + " -> " + iy);
        }
        var ids = [for (id => n in a.talents) id];
        for (id => n in b.talents) if (ids.indexOf(id) < 0) ids.push(id);
        for (id in ids) {
            var p = a.talents.exists(id) ? a.talents.get(id) : 0, q = b.talents.exists(id) ? b.talents.get(id) : 0;
            if (p != q) out.push(id + " " + p + "->" + q);
        }
        if (a.skills.join(",") != b.skills.join(",")) out.push("skills " + b.skills.join(","));
        return out.length == 0 ? "runes" : out.join(", ");
    }

    /** An item valued by its attributes only (no skills of its own): see Model.statsOnly. */
    public static function statsOnlyItem(s:Int, c:Candidate):Bool return s > 1 && c != null && c.skills.length == 0;

    public function value(b:Build):Float return score(axesOf(b));

    public function overLimit():Bool return evals >= evalLimit;

    public var augCache = new Map<String, Array<Augment>>();

    /** The best augment of each type for a created item in slot `s` (worn items keep theirs). */
    public function bestAugs(b:Build, s:Int, c:Candidate):Array<Augment> {
        if (c.real) return cast c.realAugs;
        // the best augments depend on the talents (a sigil gives a talent the tree may already have)
        var key = s + ":" + c.id + ":" + talentKey(b.talents);
        if (augCache.exists(key)) return augCache.get(key);
        var chosen:Array<Augment> = [];
        var trial = copy(b);
        trial.items.set(s, c);
        trial.augs.set(s, chosen);
        var wornAugs = worn.augs.exists(s) ? worn.augs.get(s) : [];
        for (type => list in Augments.forItem(hero, c.inf)) {
            // sigils (augments that give a talent) are not changed: the item gets the sigil the hero has in this slot,
            // so the talents chosen work with the sigils the hero owns (a talent moved onto a sigil the hero does not
            // have would be lost)
            if (Lambda.exists(list, a -> isSigil(a))) {
                for (w in wornAugs) if (isSigil(w) && Lambda.exists(list, a -> a.id == w.id)) chosen.push(w);
                continue;
            }
            var best:Augment = null, bestV = -1e30, bestTie = -1.0;
            for (a in list) {
                chosen.push(a);
                // an augment without skills changes attributes only: the fight of the same skills is valued again
                model.statsOnly = a.skills.length == 0;
                var v = value(trial);
                model.statsOnly = false;
                chosen.remove(a);
                var tie = 0.0;
                for (w in wornAugs) if (w.id == a.id) tie += 2;
                for (id in a.skills) {
                    var d = SkillData.get(id);
                    if (d != null && d.maxPoints > 0 && !(b.talents.exists(id) && b.talents.get(id) > 0)) tie += 1;
                }
                if (v > bestV + Math.abs(bestV) * 1e-6 || (Math.abs(v - bestV) <= Math.abs(bestV) * 1e-6 && tie > bestTie)) { bestV = v; best = a; bestTie = tie; }
            }
            if (best != null) chosen.push(best);
        }
        augCache.set(key, chosen);
        return chosen;
    }

    /** Puts item `c` in slot `s`: its augments; a created item keeps the slot's infusion if it can take one. */
    public function place(b:Build, s:Int, c:Candidate):Void {
        // only where the game lets the item be worn (st.Equipment.isEquippableOnSlot): a two-handed weapon, fists or
        // halos never go to the off-hand
        if (c != null && !slotFits(c, s)) { badPlace++; return; }
        // the infusion the slot has now (a worn item carries its own): the new item takes it over, so a swap does not
        // break an infusion set (6 worn Manfish items: any new item without it dropped the set to 5, rank 3 -> 2, and
        // looked worse than it is)
        var old = b.items.get(s);
        var slotInf = b.infusion.exists(s) ? b.infusion.get(s) : (old != null && old.real ? old.infusion : "");
        var slotBonus = b.bonus.exists(s) ? b.bonus.get(s) : (old != null && old.real && old.bonusStat != "" ? old.bonusStat : null);
        b.items.set(s, c);
        if (c == null) { b.augs.remove(s); b.infusion.remove(s); b.bonus.remove(s); return; }
        b.augs.set(s, bestAugs(b, s, c));
        if (s == 1) {
            if (c == worn.items.get(1)) b.arsenal = worn.arsenal.copy() else bestArsenal(b);
        }
        if (!c.infusable || (c.real && (c.infusion != "" || slotInf == null || slotInf == ""))) {
            // an item that cannot be infused; a real item with an infusion of its own (or nothing to take over) keeps its own
            b.infusion.remove(s);
            b.bonus.remove(s);
        } else {
            if (slotInf != null && slotInf != "") b.infusion.set(s, slotInf);
            if (slotBonus != null) b.bonus.set(s, slotBonus);
            else if (!b.bonus.exists(s) && bonusStats.length > 0 && !c.real) b.bonus.set(s, bonusStats[0]);
        }
    }

    public function talentSpent(t:Map<String, Int>):Int {
        var n = 0;
        for (v in t) n += v;
        return n;
    }

    /** The tree's rules (st.player.HeroSpecialization.implInlineSetTalentRank). */
    public function validTalents(t:Map<String, Int>):Bool {
        if (talentSpent(t) > points) return false;
        var root:TalentNode = null;
        for (n in tree) if (n.branch == 0 && n.tier == 0) root = n;
        var any = false;
        for (n in tree) if (n != root && t.exists(n.id) && t.get(n.id) > 0) any = true;
        if (any && root != null && !(t.exists(root.id) && t.get(root.id) > 0)) return false;
        for (n in tree) {
            var r = t.exists(n.id) ? t.get(n.id) : 0;
            if (r <= 0 || n.tier == 0) continue;
            if (r > n.max) return false;
            var below = 0;
            for (m in tree) if (m.tier < n.tier && (m.branch == n.branch || m.branch == 0)) below += t.exists(m.id) ? t.get(m.id) : 0;
            var need = n.tier < thresholds.length ? thresholds[n.tier] : 0;
            if (below < need) return false;
        }
        return true;
    }

    /** Talents the build's sigils give (augments with a talent skill). */
    /** An augment that gives a talent of the tree (a demon sigil). */
    static function isSigil(a:Augment):Bool {
        for (id in a.skills) {
            var d = SkillData.get(id);
            if (d != null && d.maxPoints > 0) return true;
        }
        return false;
    }

    public static function talentKey(t:Map<String, Int>):String {
        var parts = [for (id => n in t) if (n > 0) id + n];
        parts.sort((x, y) -> x < y ? -1 : (x > y ? 1 : 0));
        return parts.join(",");
    }

    public function sigilTalents(b:Build):Map<String, Bool> {
        var out = new Map<String, Bool>();
        for (s => augs in b.augs) for (a in augs) for (id in a.skills) {
            var d = SkillData.get(id);
            if (d != null && d.maxPoints > 0) out.set(id, true);
        }
        return out;
    }

    /** Would `t` stay valid with one point in `n`? */
    public function validTalentWith(t:Map<String, Int>, n:TalentNode):Bool {
        var r = t.exists(n.id) ? t.get(n.id) : 0;
        t.set(n.id, r + 1);
        var ok = validTalents(t);
        if (r == 0) t.remove(n.id) else t.set(n.id, r);
        return ok;
    }

    public function bestRunes(b:Build, id:String):Array<String> {
        var d = SkillData.get(id);
        var chosen:Array<String> = [];
        b.runes.set(id, chosen);
        for (_ in 0...runesPerSkill) {
            var best = "", bestV = value(b);
            for (m in d.masteries) {
                if (chosen.indexOf(m.id) >= 0) continue;
                chosen.push(m.id);
                var v = value(b);
                chosen.remove(m.id);
                var tie = worn.runes.exists(id) && worn.runes.get(id).indexOf(m.id) >= 0 ? 1e-7 : 0;
                if (v + tie > bestV + 1e-12) { bestV = v + tie; best = m.id; }
            }
            if (best == "") break;
            chosen.push(best);
        }
        return chosen;
    }

    // ---------------------------------------------------------------- the end

    function finish():Void {
        var b = finalBuild;
        stage = "done";
        var rep = [];
        model.report = rep;
        // an item in a slot the game does not allow: taken out (it would be counted as worn)
        for (s => c in b.items) if (c != null && !slotFits(c, s)) { DebugLog.line("check: " + c.id + " removed from slot " + s); b.items.remove(s); b.augs.remove(s); b.infusion.remove(s); b.bonus.remove(s); }
        DebugLog.line("check: slots of the chosen build " + checkBuild(b) + "; refused placements " + badPlace);
        var ev = model.evaluate(b);
        model.report = null;
        for (a in 0...4) if (ev.axes[a] > best[a]) best[a] = ev.axes[a];
        try model.verify(worn) catch (e:Dynamic) DebugLog.error("self-check", e);
        var nowRep = [];
        model.report = nowRep;
        var nowEval = model.evaluate(worn);
        model.report = null;
        DebugLog.line("now: " + now.map(r3).join("/") + " dps " + r3(nowEval.dps) + " self heal " + r3(nowEval.selfHeal) + " ally heal " + r3(nowEval.allyHeal)
            + "\n    " + nowRep.join("\n    "));
        DebugLog.line("chosen: " + ev.axes.map(r3).join("/") + " dps " + r3(ev.dps) + " self heal " + r3(ev.selfHeal) + " ally heal " + r3(ev.allyHeal)
            + "; best per axis " + best.map(r3).join("/") + " weights " + weights.join(",") + "; " + evals + " builds valued in " + ms(t0) + " ms"
            + " (" + memoHits + " met again; " + model.fightsRun + " fights of " + Model.FIGHT + " s simulated, " + Math.round(model.fightMs / Math.max(1, model.fightsRun)) + " ms each; "
            + model.fightsReplayed + " valued again from a fight; fought again because of " + [for (k => n in model.refights) k + " x" + n].join(", ") + ")"
            + "\n    " + describe(b) + "\n    " + rep.join("\n    "));
        // why each change: the chosen build against the same build with the worn item (and its infusion) back in
        // that slot; and the share of the new infusion (the same item without it)
        var reasons = [];
        var heal0 = ev.selfHeal + ev.allyHeal;
        function pct(a:Float, b:Float):Float return b > 1e-9 ? (a / b - 1) * 100 : 0;
        for (s in Items.SLOTS) {
            var c = b.items.get(s), w = worn.items.get(s);
            if (c == null || w == null) continue;
            var inf = b.infusion.exists(s) ? b.infusion.get(s) : (c.real ? c.infusion : "");
            if (inf == null) inf = "";
            if (c == w && inf == w.infusion) continue;
            var back = copy(b);
            place(back, s, w);
            back.infusion.remove(s);
            var e2 = model.evaluate(back);
            var noInf = copy(b);
            noInf.infusion.set(s, "");
            var e3 = inf != "" ? model.evaluate(noInf) : e2;
            var diffs = [];
            for (i in 0...model.engine.count) {
                var p = model.engine.percent(i);
                var d = (ev.vals[i] - e2.vals[i]) * p;
                if (Math.abs(d) > (p < 1 ? 0.0005 : 0.05)) diffs.push(model.engine.names[i] + (d > 0 ? "+" : "") + r3(p < 1 ? d * 100 : d) + (p < 1 ? "%" : ""));
            }
            DebugLog.line("compare slot " + s + ": " + c.id + (inf != "" ? " [" + inf + "]" : "") + " -> dps " + r3(ev.dps) + ", heal " + r3(heal0) + ", armour "
                + r3(ev.axes[1]) + ", health " + r3(ev.axes[2]) + " | worn " + w.id + (w.infusion != "" ? " [" + w.infusion + "]" : "") + " -> dps " + r3(e2.dps)
                + ", heal " + r3(e2.selfHeal + e2.allyHeal) + ", armour " + r3(e2.axes[1]) + ", health " + r3(e2.axes[2])
                + (inf != "" ? " | without the infusion -> dps " + r3(e3.dps) + ", heal " + r3(e3.selfHeal + e3.allyHeal) : "")
                + "
    attributes (chosen - worn): " + (diffs.length == 0 ? "same" : diffs.join(", ")));
            reasons.push({slot: s, item: c.inf, dps: pct(ev.dps, e2.dps), heal: pct(heal0, e2.selfHeal + e2.allyHeal),
                infDps: inf != "" ? pct(ev.dps, e3.dps) : 0.0, infHeal: inf != "" ? pct(heal0, e3.selfHeal + e3.allyHeal) : 0.0, infusion: inf, onlyInfusion: c == w});
        }
        // every main weapon candidate in the chosen build (one swap): its score, dps and heal
        try {
            var lines = [];
            for (c in pools.get(0)) {
                var trial = copy(b);
                place(trial, 0, c);
                var e = model.evaluate(trial);
                lines.push({c: c, v: value(trial), dps: e.dps, heal: e.selfHeal + e.allyHeal});
            }
            lines.sort((x, y) -> x.v > y.v ? -1 : (x.v < y.v ? 1 : 0));
            DebugLog.line("main weapons (" + (settings.ranged ? "ranged" : "melee") + "), each in the chosen build: "
                + [for (l in lines) l.c.id + "[" + l.c.source + (l.c.upgrade > 0 ? " +" + l.c.upgrade : "") + "] score " + r3(l.v) + " dps " + r3(l.dps) + " heal " + r3(l.heal)].join("; "));
        } catch (e:Dynamic) DebugLog.error("main weapons", e);
        // per slot: the best other item (one swap from the chosen build) and why it was not taken
        var base = value(b);
        for (s in Items.SLOTS) {
            var pool = pools.get(s);
            if (pool == null) continue;
            var bestC:Candidate = null, bestV = -1e30;
            for (c in pool) {
                if (c == b.items.get(s)) continue;
                var trial = copy(b);
                place(trial, s, c);
                var v = value(trial);
                if (v > bestV) { bestV = v; bestC = c; }
            }
            if (bestC == null) continue;
            var gain = (bestV - base) / unit * 100;
            var need = (s <= 1 ? 1.0 : 0.5);
            var why = gain <= 0 ? "worse" : (gain < need ? "gain under the " + need + "% a swap needs" : "");
            if (why == "") {
                var trial = copy(b);
                place(trial, s, bestC);
                why = robustOk(b, trial) ? "better: not reached by the search" : "loses without the utility class skills";
            }
            DebugLog.line("alternative slot " + s + ": " + bestC.id + " [" + bestC.source + "] score " + (gain >= 0 ? "+" : "") + r3(gain) + "% -> " + why);
        }
        // the second rotation (no utility class skills): the chosen build must not lose there
        try {
            var wB = model.evaluateWithoutUtility(worn), cB = model.evaluateWithoutUtility(b);
            DebugLog.line("without the utility class skills: worn dps " + r3(wB.dps) + " heal " + r3(wB.selfHeal + wB.allyHeal) + " | chosen dps " + r3(cB.dps)
                + " heal " + r3(cB.selfHeal + cB.allyHeal) + "; changes refused because they lose there: " + robustRejected);
        } catch (e:Dynamic) DebugLog.error("second rotation", e);
        // why each talent change: the chosen build with only that talent back at its worn points
        var ids = [for (id => n in b.talents) id];
        for (id => n in worn.talents) if (ids.indexOf(id) < 0) ids.push(id);
        for (id in ids) {
            var to = b.talents.exists(id) ? b.talents.get(id) : 0, from = worn.talents.exists(id) ? worn.talents.get(id) : 0;
            if (to == from) continue;
            var back = copy(b);
            back.talents.set(id, from);
            var e2 = model.evaluate(back);
            DebugLog.line("why talent " + id + " " + from + "->" + to + ": dps " + r3(ev.dps - e2.dps) + ", defense " + r3(ev.axes[1] - e2.axes[1])
                + ", health " + r3(ev.axes[2] - e2.axes[2]) + ", self heal " + r3(ev.selfHeal - e2.selfHeal) + ", ally heal " + r3(ev.allyHeal - e2.allyHeal)
                + "; score " + r3(norm(ev.axes, now) - norm(e2.axes, now)));
        }
        // why the infusions: the chosen build with the worn infusions (new items without one)
        if ([for (s => i in b.infusion) s].length > 0) {
            var back = copy(b);
            for (s in [for (s => i in b.infusion) s]) back.infusion.remove(s);
            var e2 = model.evaluate(back);
            DebugLog.line("why infusions " + [for (k => n in model.infusionCounts(b)) k + " x" + n].join(", ") + ": dps " + r3(ev.dps - e2.dps)
                + ", defense " + r3(ev.axes[1] - e2.axes[1]) + ", health " + r3(ev.axes[2] - e2.axes[2])
                + ", self heal " + r3(ev.selfHeal - e2.selfHeal) + ", ally heal " + r3(ev.allyHeal - e2.allyHeal) + "; score " + r3(norm(ev.axes, now) - norm(e2.axes, now)));
        }
        var changed = 0;
        for (s in Items.SLOTS) {
            var c = b.items.get(s);
            if (c != worn.items.get(s)) changed++;
            if (c != null) DebugLog.line("  slot " + s + " " + slotNames.get(s) + ": " + c.id + " [" + c.source + ", " + Sources.where(c.id) + ", upgrade "
                + c.upgrade + "] " + [for (a in c.affixes) a.attr + "+" + r3(a.val)].join(" ")
                + (b.augs.exists(s) ? " augments " + [for (a in b.augs.get(s)) a.id].join(",") : "")
                + (b.infusion.exists(s) ? " infusion " + b.infusion.get(s) + " bonus " + b.bonus.get(s) : ""));
        }
        if (!threaded) dress(b);
        var stats = new Map<String, Float>();
        for (i in 0...model.engine.count) stats.set(model.engine.names[i], ev.vals[i] * model.engine.percent(i));
        result = {build: b, worn: worn, axes: ev.axes, current: now, best: best, changed: changed, stats: stats, pool: poolSize, talentPoints: points,
            eval: ev, now: nowEval, infusions: model.infusionCounts(b), fight: combat != null && combat.ok ? combat.duration : 0, reasons: reasons,
            display: new Map()};
    }

    /** Puts the chosen augments, infusion and bonus on the created items, so the game's tooltip shows them. */
    function dress(b:Build):Void {
        // a real item infused again: the bonus attribute it was valued with (Model.bonusOf) is the one shown and saved
        for (s => c in b.items) if (c != null && model.reinfused(b, s, c)) b.bonus.set(s, model.bonusOf(b, s, c));
        // worn items with another infusion: a copy of the item (st.Item.clone) carries it, the worn item is not touched
        for (s => c in b.items) if (c != null && c.real && b.infusion.exists(s) && b.infusion.get(s) != c.infusion) {
            try {
                var copy = G.call("st.Item", "clone", [c.item, null]);
                var inf = b.infusion.get(s);
                G.call("st.item.Gear", "set_infusion", [copy, inf == "" ? null : infusionRaw.get(inf)]);
                if (b.bonus.exists(s) && b.bonus.get(s) != null) G.call("st.item.Gear", "set_infusionBonusStat", [copy, b.bonus.get(s)]);
                if (result != null) result.display.set(s, copy);
                DebugLog.line("  shown " + c.id + " with infusion " + G.str(G.field(copy, "infusion")) + " (worn: " + c.infusion + ")");
            } catch (e:Dynamic) DebugLog.error("infusion copy " + c.id, e);
        }
        for (s => c in b.items) if (c != null && !c.real) {
            var ids = [for (a in (b.augs.exists(s) ? b.augs.get(s) : [])) a.raw];
            Items.setSlots(c.item, ids);
            try {
                var inf = b.infusion.exists(s) ? b.infusion.get(s) : "";
                G.call("st.item.Gear", "set_infusion", [c.item, inf == "" ? null : infusionRaw.get(inf)]);
                if (b.bonus.exists(s)) G.call("st.item.Gear", "set_infusionBonusStat", [c.item, b.bonus.get(s)]);
                // what the game's tooltip will find for the slots
                var found = [for (id in ids) id + ":" + G.len(G.call("st.item.Gear", "getSlotAffixes", [c.item, id]))];
                DebugLog.line("  dressed " + c.id + ": slots " + G.str(G.field(G.field(c.item, "slots"), "array")) + " affixes per slot " + found.join(",")
                    + "; infusion " + G.str(G.field(c.item, "infusion")) + " bonus " + G.str(G.field(c.item, "infusionBonusStat")));
            } catch (e:Dynamic) DebugLog.error("dress " + c.id, e);
        }
    }

    public function describe(b:Build):String {
        var counts = model == null ? new Map<String, Int>() : model.infusionCounts(b);
        return "items " + [for (s in Items.SLOTS) if (b.items.get(s) != null) s + "=" + b.items.get(s).id].join(",")
            + "; infusions " + [for (id => n in counts) id + "x" + n].join(",")
            + "; talents " + [for (id => r in b.talents) id + ":" + r].join(",")
            + "; skills " + [for (id in b.skills) id + (b.runes.exists(id) ? "{" + b.runes.get(id).join(",") + "}" : "")].join(",")
            + "; arsenal " + (b.arsenal == null ? "" : b.arsenal.join(","));
    }

    static function r3(v:Float):String return Std.string(Math.round(v * 1000) / 1000);
}

/** Marks where the search moves to its own thread (Optimizer.run). */
class ToWorker implements Task {
    public function new() {}
    public function step():Bool return true;
}

/** Runs a function once. */
class Once implements Task {
    var f:Void->Void;
    public function new(f:Void->Void) this.f = f;
    public function step():Bool {
        f();
        return true;
    }
}

/** Creates the items of the game a few at a time (st.Item.create for each). */
class ItemScan implements Task {
    var o:Optimizer;
    var i = 0;
    var all:Dynamic = null;
    var typeFits = new Map<String, Bool>();
    var level = 1;

    public function new(o:Optimizer) this.o = o;

    public function step():Bool {
        if (all == null) {
            all = G.field(GameData.data("item"), "all");
            level = Std.int(G.num(G.field(o.model.hero, "_level")));
            o.stage = "items";
        }
        var n = G.len(all);
        var end = Std.int(Math.min(n, i + 40));
        while (i < end) o.scanItem(G.at(all, i++), level, typeFits);
        o.progress = 0.1 * i / Math.max(1, n);
        return i >= n;
    }
}

/**
 * Per slot: every item alone in the worn build (its axes). From these, the builds best on one axis each (the anchors:
 * in each slot the item best on that axis) give the ranges of the axes (Optimizer.setSpans); then each slot keeps the
 * worn item, the hero's own items, the best ones by the score and the best ones on each axis that has a weight.
 */
class Prefilter implements Task {
    var o:Optimizer;
    var si = 0;
    var ci = 0;
    var scored = new Map<Int, Array<{c:Candidate, a:Array<Float>}>>();
    var weights:Array<Float>;
    var now:Array<Float>;
    var anchored = false;
    var base:Build = null;
    var baseAxes:Array<Float> = null;

    public function new(o:Optimizer) this.o = o;

    public function step():Bool {
        if (weights == null) {
            weights = o.settingsWeights();
            now = o.model.evaluate(o.worn).axes;
            o.stage = "prefilter";
        }
        if (si < Items.SLOTS.length) {
            var s = Items.SLOTS[si];
            var list = o.fullPool(s);
            if (!scored.exists(s)) scored.set(s, []);
            if (s != 0 && base == null) {
                // the items of the other slots are valued with a main weapon of the kind asked (a shield needs a
                // one-handed one): the worn one, or the best of slot 0 by the score without ranges
                base = Optimizer.copy(o.worn);
                var w = o.worn.items.get(0);
                if (w == null || w.ranged != o.settings.ranged) {
                    var bestX = null;
                    for (x in scored.get(0)) if (bestX == null || o.norm(x.a, now) > o.norm(bestX.a, now)) bestX = x;
                    if (bestX != null) { base.items.set(0, bestX.c); base.augs.set(0, bestX.c.real ? cast bestX.c.realAugs : []); }
                }
                baseAxes = o.model.evaluate(base).axes;
                DebugLog.line("prefilter: items valued with main weapon " + (base.items.get(0) == null ? "-" : base.items.get(0).id));
            }
            if (ci < list.length) {
                var c = list[ci++];
                var trial = Optimizer.copy(s == 0 ? o.worn : base);
                // a created item takes over the infusion of the worn item it replaces (the set is not broken: see place)
                var was = trial.items.get(s);
                trial.items.set(s, c);
                trial.augs.set(s, c.real ? cast c.realAugs : []);
                if (!c.real && c.infusable && was != null && was.real && was.infusion != "") {
                    trial.infusion.set(s, was.infusion);
                    if (was.bonusStat != "") trial.bonus.set(s, was.bonusStat);
                }
                o.model.statsOnly = Optimizer.statsOnlyItem(s, c);
                var a = o.model.evaluate(trial).axes;
                o.model.statsOnly = false;
                o.evals++;
                scored.get(s).push({c: c, a: a});
                return false;
            }
            si++;
            ci = 0;
            o.progress = 0.1 + 0.1 * si / Items.SLOTS.length;
            return false;
        }
        if (!anchored) {
            anchored = true;
            var anchors = [];
            var wornMain = o.worn.items.get(0);
            var wrongMain = wornMain != null && wornMain.ranged != o.settings.ranged;
            for (axis in 0...4) {
                var b = Optimizer.copy(base != null ? base : o.worn);
                for (s in Items.SLOTS) {
                    var bestX = null;
                    for (x in scored.get(s)) if (bestX == null || x.a[axis] > bestX.a[axis]) bestX = x;
                    if (bestX == null) continue;
                    var ref = s == 0 || baseAxes == null ? now : baseAxes;
                    if (bestX.a[axis] > ref[axis] + 1e-9 || (s == 0 && wrongMain)) {
                        b.items.set(s, bestX.c);
                        b.augs.set(s, bestX.c.real ? cast bestX.c.realAugs : []);
                    }
                }
                anchors.push(o.model.evaluate(b).axes);
                o.evals++;
            }
            o.setSpans(anchors);
            return false;
        }
        for (s in Items.SLOTS) {
            var list = o.fullPool(s);
            var sc = scored.get(s);
            var keep = new Map<Candidate, Bool>();
            var worn = o.worn.items.get(s);
            if (worn != null) keep.set(worn, true);
            for (x in sc) if (x.c.source == "owned") keep.set(x.c, true); // the hero's own items are always looked at
            sc.sort((x, y) -> { var p = o.norm(x.a, now), q = o.norm(y.a, now); p > q ? -1 : (p < q ? 1 : 0); });
            for (i in 0...Std.int(Math.min(10, sc.length))) keep.set(sc[i].c, true);
            for (axis in 0...4) if (weights[axis] > 0) {
                sc.sort((x, y) -> x.a[axis] > y.a[axis] ? -1 : (x.a[axis] < y.a[axis] ? 1 : 0));
                for (i in 0...Std.int(Math.min(4, sc.length))) keep.set(sc[i].c, true);
            }
            o.pools.set(s, [for (c in list) if (keep.exists(c)) c]);
        }
        DebugLog.line("prefilter: " + [for (s in Items.SLOTS) s + ":" + o.pools.get(s).length + "/" + o.fullPool(s).length].join(" "));
        return true;
    }
}

/** A search: passes over items, infusions, talents and skills until none raises the score (or the limit). */
class Search implements Task {
    var o:Optimizer;
    var fn:Array<Float>->Float;
    var rounds:Int;
    var onDone:Build->Void;
    var b:Build;
    var current = 0.0;
    var start = 0.0;
    var round = 0;
    var before = 0.0;
    var passIndex = 0;
    var pass:Pass = null;
    var started = false;
    var t0 = 0.0;
    var e0 = 0;
    var passT0 = -1.0;
    var passE0 = 0;
    var passF0 = 0;

    public function new(o:Optimizer, fn:Array<Float>->Float, rounds:Int, onDone:Build->Void) {
        this.o = o;
        this.fn = fn;
        this.rounds = rounds;
        this.onDone = onDone;
    }

    public function step():Bool {
        if (!started) {
            started = true;
            o.score = fn;
            o.augCache = new Map();
            b = Optimizer.copy(o.worn);
            o.startWeapon(b);
            if (o.floor == null) o.setFloors();
            current = o.value(b);
            var seed = o.seedFromLast();
            if (seed != null) {
                var v = o.value(seed);
                var take = v >= current && o.robustOk(b, seed);
                DebugLog.line("search: the last result scores " + v + " against " + current + " for the worn build -> "
                    + (take ? "the search starts from the last result" : "the search starts from the worn build"));
                if (take) { b = seed; current = v; }
            }
            start = current;
            before = current - 1;
            t0 = haxe.Timer.stamp();
            e0 = o.evals;
        }
        if (pass == null) {
            // a round that gained less than 0.2% ends the search (the next would find about nothing)
            if (passIndex == 0 && (round >= rounds || current <= before + o.unit * 0.002 || o.overLimit())) {
                DebugLog.line("search " + o.stage + ": score " + start + " -> " + current + ", " + (o.evals - e0) + " builds in "
                    + Math.round((haxe.Timer.stamp() - t0) * 1000) + " ms, " + round + " rounds" + (o.overLimit() ? " (limit)" : ""));
                onDone(b);
                return true;
            }
            if (passIndex == 0) before = current;
            pass = switch (passIndex) {
                case 0: new ItemPass(o, b, current);
                case 1: new InfusionPass(o, b, current, round == 0);
                case 2: new TalentPass(o, b, current, round == 0);
                default: new SkillPass(o, b, current);
            };
        }
        if (passT0 < 0) { passT0 = haxe.Timer.stamp(); passE0 = o.evals; passF0 = o.model.fightsRun; }
        if (pass.step()) {
            DebugLog.line("search pass " + ["items", "infusions", "talents", "skills"][passIndex] + " round " + (round + 1) + ": score " + current + " -> " + pass.current
                + ", " + (o.evals - passE0) + " builds, " + (o.model.fightsRun - passF0) + " fights, " + Math.round((haxe.Timer.stamp() - passT0) * 1000) + " ms");
            passT0 = -1;
            current = pass.current;
            pass = null;
            passIndex++;
            if (passIndex > 3) { passIndex = 0; round++; }
        }
        o.progress = Math.min(0.99, 0.2 + 0.8 * o.evals / Math.max(1, o.evalLimit));
        return false;
    }
}

class Pass implements Task {
    var o:Optimizer;
    var b:Build;
    public var current:Float;

    public function new(o:Optimizer, b:Build, current:Float) {
        this.o = o;
        this.b = b;
        this.current = current;
    }

    public function step():Bool return true;

    /** Share of the score a change must add to be taken (no swaps for nothing). */
    var threshold = 0.001;

    /** Takes `trial` if it raises the score. */
    function take(trial:Build, v:Float):Bool {
        if (v > current + Math.max(1e-9, o.unit * threshold) && o.keepsUnvalued(trial) && o.robustOk(b, trial)) {
            current = v;
            Optimizer.copyInto(trial, b);
            return true;
        }
        return false;
    }
}

/** Each slot: the item (with its augments) that raises the score most; swaps between slots of the same kind. */
class ItemPass extends Pass {
    var si = 0;
    var ci = 0;

    public function new(o:Optimizer, b:Build, current:Float) {
        super(o, b, current);
        threshold = 0.01;
    }

    override public function step():Bool {
        while (si < Items.SLOTS.length) {
            var s = Items.SLOTS[si];
            var pool = o.pools.get(s);
            if (pool == null || ci >= pool.length || o.overLimit()) { si++; ci = 0; continue; }
            var c = pool[ci++];
            if (b.items.get(s) == c) {
                // the same item: its augments again, for the talents the build has now (a sigil of the old talents)
                if (c.real) continue;
                var augs = o.bestAugs(b, s, c);
                var now = b.augs.exists(s) ? b.augs.get(s) : [];
                if ([for (a in augs) a.id].join(",") == [for (a in now) a.id].join(",")) continue;
                var again = Optimizer.copy(b);
                again.augs.set(s, augs);
                threshold = 0.001;
                o.model.statsOnly = Optimizer.statsOnlyItem(s, c) && !Lambda.exists(augs, a -> a.skills.length > 0);
                take(again, o.value(again));
                o.model.statsOnly = false;
                return false;
            }
            var other = -1;
            for (t => d in b.items) if (d == c && t != s) other = t;
            var trial = Optimizer.copy(b);
            var old = b.items.get(s);
            o.place(trial, s, c);
            // the item came from another slot: the old item goes there if it fits that slot (rings, the weapons); a real
            // item is only once in the build, a created one can be had twice
            if (other >= 0) {
                if (old != null && o.slotFits(old, other)) o.place(trial, other, old);
                else if (c.real) o.place(trial, other, null);
            }
            threshold = s <= 1 ? 0.01 : 0.005;
            o.model.statsOnly = Optimizer.statsOnlyItem(s, c) && (other < 0 || Optimizer.statsOnlyItem(other, old));
            take(trial, o.value(trial));
            o.model.statsOnly = false;
            return false;
        }
        return true;
    }
}

/** Infusions of the created items that can take one: one slot or two slots at a time, then the bonus attribute. */
class InfusionPass extends Pass {
    var slots:Array<Int> = null;
    var moves:Array<Array<Int>> = [];  // [infusion or bonus index, slot1, slot2 or -1]
    var mi = 0;
    var round = 0;
    var improved = false;
    var bonusPhase = false;
    var full:Bool;

    public function new(o:Optimizer, b:Build, current:Float, full:Bool) {
        super(o, b, current);
        this.full = full;
    }

    override public function step():Bool {
        if (slots == null) {
            slots = [for (s => c in b.items) if (c != null && c.infusable) s];
            if (slots.length == 0 || o.infusions.length == 0) return true;
            plan();
        }
        while (mi < moves.length) {
            if (o.overLimit()) return true;
            var m = moves[mi++];
            var trial = Optimizer.copy(b);
            if (bonusPhase) {
                var stat = o.bonusStats[m[0]];
                if (b.bonus.get(m[1]) == stat) continue;
                trial.bonus.set(m[1], stat);
            } else {
                var inf = o.infusions[m[0]];
                var same = true;
                for (i in 1...m.length) if (m[i] >= 0 && b.infusion.get(m[i]) != inf) same = false;
                if (same) continue;
                for (i in 1...m.length) if (m[i] >= 0) trial.infusion.set(m[i], inf);
            }
            if (take(trial, o.value(trial))) improved = true;
            return false;
        }
        if (!bonusPhase && improved && round < (full ? 2 : 0)) { round++; improved = false; plan(); return false; }
        if (!bonusPhase) {
            fill();
            bonusPhase = true;
            moves = [for (s in slots) for (k in 0...o.bonusStats.length) [k, s, -1]];
            mi = 0;
            return false;
        }
        return true;
    }

    /**
     * An item that can be infused gets an infusion where it completes a set: an infusion on fewer items than
     * its first set threshold gives nothing, so such items are moved to another set or left free.
     */
    function fill():Void {
        var caps = o.infusionCaps();
        var first = caps.length > 0 ? caps[0] : 2;
        // items of an infusion below its first threshold: free them
        var counts = o.model.infusionCounts(b);
        for (s in slots) {
            var inf = b.infusion.exists(s) ? b.infusion.get(s) : (b.items.get(s).real ? b.items.get(s).infusion : "");
            if (inf != "" && counts.exists(inf) && counts.get(inf) < first) b.infusion.set(s, "");
        }
        current = o.value(b);
        // a free item joins the set it brings to a threshold (best value first)
        for (s in slots) {
            if (b.infusion.exists(s) && b.infusion.get(s) != "") continue;
            if (!b.infusion.exists(s) && b.items.get(s).real && b.items.get(s).infusion != "") continue;
            var best = "", bestV = -1e30;
            var counts = o.model.infusionCounts(b);
            for (inf in o.infusions) {
                var n = (counts.exists(inf) ? counts.get(inf) : 0) + 1;
                if (caps.indexOf(n) < 0) continue;
                var trial = Optimizer.copy(b);
                trial.infusion.set(s, inf);
                var v = o.value(trial);
                if (v > bestV) { bestV = v; best = inf; }
            }
            if (best != "" && bestV >= current - Math.abs(current) * 1e-6) {
                var trial = Optimizer.copy(b);
                trial.infusion.set(s, best);
                if (o.robustOk(b, trial)) {
                    b.infusion.set(s, best);
                    current = Math.max(current, bestV);
                }
            }
        }
        // two free items together start a new set
        var free = [for (s in slots) if ((!b.infusion.exists(s) || b.infusion.get(s) == "") && !(b.items.get(s).real && !b.infusion.exists(s) && b.items.get(s).infusion != "")) s];
        while (free.length >= first) {
            var group = free.splice(0, first);
            var best = "", bestV = -1e30;
            for (inf in o.infusions) {
                var trial = Optimizer.copy(b);
                for (s in group) trial.infusion.set(s, inf);
                var v = o.value(trial);
                if (v > bestV) { bestV = v; best = inf; }
            }
            if (best != "" && bestV >= current - Math.abs(current) * 1e-6) {
                var trial = Optimizer.copy(b);
                for (s in group) trial.infusion.set(s, best);
                if (o.robustOk(b, trial)) {
                    for (s in group) b.infusion.set(s, best);
                    current = Math.max(current, bestV);
                }
            }
        }
    }

    function plan():Void {
        moves = [];
        // whole sets: an infusion brought to each count of its ranks (Const.Items.Item_InfusionCaps) at once — a rank
        // whose bonus starts at 4 items gives nothing at 2, so moves of one or two items would never reach it; the
        // items taken: free ones first, then those of another infusion (each other infusion in turn)
        var caps = o.infusionCaps();
        var counts = o.model.infusionCounts(b);
        function infOf(s:Int):String {
            var c = b.items.get(s);
            var v = b.infusion.exists(s) ? b.infusion.get(s) : (c.real ? c.infusion : "");
            return v == null ? "" : v;
        }
        var present = [for (id => n in counts) id];
        for (k in 0...o.infusions.length) {
            var inf = o.infusions[k];
            var have = counts.exists(inf) ? counts.get(inf) : 0;
            for (cap in caps) {
                if (cap <= have || cap > slots.length) continue;
                for (first in [""].concat(present)) {
                    if (first == inf) continue;
                    var free = [for (s in slots) if (infOf(s) == "") s];
                    var mine = [for (s in slots) if (infOf(s) == first && first != "") s];
                    var rest = [for (s in slots) if (infOf(s) != "" && infOf(s) != inf && infOf(s) != first) s];
                    var order = free.concat(mine).concat(rest);
                    var need = cap - have;
                    if (order.length < need) continue;
                    moves.push([k].concat(order.slice(0, need)));
                }
            }
        }
        for (k in 0...o.infusions.length) for (i in 0...slots.length) {
            moves.push([k, slots[i], -1]);
            for (j in i + 1...slots.length) moves.push([k, slots[i], slots[j]]); // a rank needs two items more
        }
        mi = 0;
    }
}

/**
 * Talents: for each branch whose last tier can be reached with the points, a build that takes it — root,
 * the branch's lower talents (best gain first) up to the tier threshold, the final talent, then the rest of
 * the points where they gain most. Talents a sigil of the build already gives get no points. The best of
 * these builds replaces the hero's talents only when it is clearly better (threshold).
 */
class TalentPass extends Pass {
    var full:Bool;

    public function new(o:Optimizer, b:Build, current:Float, full:Bool) {
        super(o, b, current);
        threshold = 0.03;
        this.full = full;
    }

    var options:Array<TalentNode> = null;   // the final talents to build towards
    var oi = 0;
    var t:Map<String, Int>;
    var trial:Build;
    var stage = 0;                           // 0: start an option, 1: lower tiers of the branch, 2: the rest
    var ni = 0;
    var bestId = "";
    var bestV = -1e30;
    var bestTie = -1.0;
    var bestBuild:Build = null;
    var bestScore = -1e30;
    var given:Map<String, Bool>;
    var root:TalentNode;
    var cap:TalentNode;

    override public function step():Bool {
        if (o.tree.length == 0 || o.points <= 0) return true;
        if (options == null && !full) options = []; // later rounds: the talents found are moved a point at a time
        if (options == null) {
            given = o.sigilTalents(b);
            var maxTier = 0;
            for (n in o.tree) if (n.tier > maxTier) maxTier = n.tier;
            for (n in o.tree) if (n.branch == 0 && n.tier == 0) root = n;
            options = [for (n in o.tree) if (n.tier == maxTier && !given.exists(n.id)) n];
            if (options.length == 0) options = [null];
        }
        if (options.length == 0 && !local) {
            local = true;
            threshold = 0.005;
            planMoves();
        }
        if (oi >= options.length) {
            if (!local) {
                if (bestBuild != null) take(bestBuild, bestScore);
                local = true;
                threshold = 0.005;
                planMoves();
            }
            return localStep();
        }
        if (o.overLimit()) { oi = options.length; return false; }
        if (stage == 0) {
            cap = options[oi];
            t = new Map();
            if (root != null) t.set(root.id, 1);
            trial = Optimizer.copy(b);
            trial.talents = t;
            stage = cap == null ? 2 : 1;
            ni = 0; bestId = ""; bestV = -1e30; bestTie = -1;
            return false;
        }
        if (stage == 1 && o.validTalentWith(t, cap)) {
            t.set(cap.id, 1);
            stage = 2;
            ni = 0; bestId = ""; bestV = -1e30; bestTie = -1;
            return false;
        }
        if (stage == 2 && o.talentSpent(t) >= o.points) { finishOption(); return false; }
        // one point more: the talent that gains most (stage 1: in the branch, below the final tier)
        if (ni < o.tree.length) {
            var n = o.tree[ni++];
            if (given.exists(n.id)) return false;
            if (stage == 1 && (n.branch != cap.branch || n.tier >= cap.tier)) return false;
            var r = t.exists(n.id) ? t.get(n.id) : 0;
            if (r >= n.max) return false;
            t.set(n.id, r + 1);
            if (o.validTalents(t)) {
                var val = o.value(trial);
                var have = o.worn.talents;
                var tie = n.tier * 0.01 + (have.exists(n.id) && have.get(n.id) > r ? 0.001 : 0.0);
                if (val > bestV + 1e-9 || (Math.abs(val - bestV) <= 1e-9 && tie > bestTie)) { bestV = val; bestId = n.id; bestTie = tie; }
            }
            if (r == 0) t.remove(n.id) else t.set(n.id, r);
            return false;
        }
        if (bestId == "") { finishOption(); return false; }
        t.set(bestId, (t.exists(bestId) ? t.get(bestId) : 0) + 1);
        ni = 0; bestId = ""; bestV = -1e30; bestTie = -1;
        return false;
    }

    // ---- then from the best talents found: one point moved (or a free point put) at a time, while it gains
    var local = false;
    var moves:Array<{from:String, to:String}> = [];
    var mi = 0;
    var localRounds = 0;

    function planMoves():Void {
        moves = [];
        mi = 0;
        var given = o.sigilTalents(b);
        var free = o.points - o.talentSpent(b.talents);
        var froms:Array<String> = [for (id => r in b.talents) if (r > 0 && !given.exists(id)) id];
        if (free > 0) froms.push("");
        for (f in froms) for (n in o.tree) {
            if (n.id == f || given.exists(n.id)) continue;
            var r = b.talents.exists(n.id) ? b.talents.get(n.id) : 0;
            if (r >= n.max) continue;
            moves.push({from: f, to: n.id});
        }
    }

    function localStep():Bool {
        if (o.overLimit() || localRounds > 12) return true;
        while (mi < moves.length) {
            var m = moves[mi++];
            var t = b.talents.copy();
            if (m.from != "") {
                var r = t.get(m.from) - 1;
                if (r <= 0) t.remove(m.from) else t.set(m.from, r);
            }
            t.set(m.to, (t.exists(m.to) ? t.get(m.to) : 0) + 1);
            if (!o.validTalents(t)) continue;
            var trial = Optimizer.copy(b);
            trial.talents = t;
            if (take(trial, o.value(trial))) {
                DebugLog.line("talents: moved a point " + (m.from == "" ? "(free)" : m.from) + " -> " + m.to + ", score " + current);
                localRounds++;
                planMoves();
            }
            return false;
        }
        return true;
    }

    function finishOption():Void {
        var v = o.value(trial);
        DebugLog.line("talents: option " + (cap == null ? "-" : cap.id) + " score " + v + ": " + [for (id => r in t) id + ":" + r].join(","));
        if (v > bestScore) { bestScore = v; bestBuild = trial; }
        oi++;
        stage = 0;
    }
}

/** Class skills for the hero's slots (best gain first) with their best runes; or only better runes. */
class SkillPass extends Pass {
    public function new(o:Optimizer, b:Build, current:Float) {
        super(o, b, current);
        threshold = 0.02;
    }

    var trial:Build = null;
    var ci = 0;
    var bestId = "";
    var bestV = -1e30;
    var phase = 0;

    override public function step():Bool {
        if (o.classSkills.length == 0 || o.skillSlots <= 0) return true;
        if (trial == null) {
            trial = Optimizer.copy(b);
            trial.skills = [];
            trial.runes = new Map();
        }
        if (phase == 0) {
            if (trial.skills.length >= o.skillSlots || o.overLimit()) { phase = 1; return false; }
            if (ci < o.classSkills.length) {
                var id = o.classSkills[ci++];
                if (trial.skills.indexOf(id) >= 0) return false;
                trial.skills.push(id);
                trial.runes.set(id, o.bestRunes(trial, id));
                var val = o.value(trial);
                var tie = o.worn.skills.indexOf(id) >= 0 ? 1e-7 : 0;
                if (val + tie > bestV) { bestV = val + tie; bestId = id; }
                trial.skills.remove(id);
                trial.runes.remove(id);
                return false;
            }
            if (bestId == "") { phase = 1; return false; }
            trial.skills.push(bestId);
            trial.runes.set(bestId, o.bestRunes(trial, bestId));
            ci = 0; bestId = ""; bestV = -1e30;
            return false;
        }
        if (!(trial.skills.length >= o.skillSlots && take(trial, o.value(trial)))) {
            var runesOnly = Optimizer.copy(b);
            for (id in runesOnly.skills) runesOnly.runes.set(id, o.bestRunes(runesOnly, id));
            take(runesOnly, o.value(runesOnly));
        }
        var arsenal = Optimizer.copy(b);
        o.bestArsenal(arsenal);
        take(arsenal, o.value(arsenal));
        return true;
    }
}
