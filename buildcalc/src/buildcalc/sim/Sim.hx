package buildcalc.sim;

import buildcalc.sim.Interp.IObj;
import buildcalc.sim.Interp.Host;
import buildcalc.sim.Interp.DynObj;
import buildcalc.sim.Interp.Closure;
import buildcalc.sim.SimData.SkillInfo;
import buildcalc.sim.SimData.SStep;
import buildcalc.sim.SimData.SEffect;
import buildcalc.sim.SimData.SAffix;
import buildcalc.sim.SimData.Affinity;
import buildcalc.sim.SimData.GameRules;
import buildcalc.sim.SimData.SAttr;

/** The hero's attributes for the simulation. */
interface StatsView {
    /** Displayed value (percentages as fractions). */
    function get(name:String):Float;
    /** Raw value (what skill scalings multiply). */
    function raw(name:String):Float;
}

/** What the simulation needs from outside: skills, attributes with buffs, the base value of effects, the target. */
interface SimEnv {
    function skill(id:String):SkillInfo;
    /** The hero's attributes with these status affixes on (each `share` times). */
    function stats(buffs:Array<{a:SAffix, share:Float}>):StatsView;
    /** An effect's value before multipliers (scalings, the item's own power, AllAttributes, WeaponPower). */
    function effectBase(inst:Inst, e:SEffect, stats:StatsView):Float;
    function armorReduction(armor:Float):Float;
    function targetArmor(physical:Bool):Float;
    /** What the target's other reductions (magic reduction, resilience, damage taken) leave of a hit after armour. */
    function targetTaken(physical:Bool):Float;
    /**
     * The target's defense with the affixes of its statuses on it (debuffs): [armour (or magic armour), what is
     * left of a hit after armour]. Without statuses: [targetArmor, targetTaken].
     */
    function targetDefense(physical:Bool, buffs:Array<{a:SAffix, share:Float}>):Array<Float>;
    /** The hero's level (Mage_Conduit_Levels…). */
    function heroLevel():Int;
    /** The skills a summoned unit (Data.unit) attacks with. */
    function unitSkills(unit:String):Array<String>;
}

/** A skill of the build as the simulation is told it: rank, runes, where it comes from. */
typedef SkillSpec = {id:String, rank:Int, runes:Array<String>, kind:String, slot:Int, item:Dynamic, ?weave:Int};

/** One damage or heal of a fight: what it was made of, to value it again with other attributes. */
typedef HitRec = {inst:Inst, e:SEffect, split:Int, add:Float, mult:Float, ccAdd:Float, cdAdd:Float, crit:Bool, ignore:Float, kind:Int,
    self:Bool, ally:Bool, buffs:Int, tbuffs:Int, dyn:Bool, amount:Float};

typedef SimResult = {dps:Float, selfHeal:Float, allyHeal:Float, damage:Map<String, Float>, heal:Map<String, Float>, casts:Map<String, Int>, missing:Map<String, Int>, time:Float, ?resources:String};

/** Names of the data a script refers to: Skill.X, Steps.X, Mastery.X, GameBeat.X… are their names. */
/**
 * A capitalised global of a script: a namespace (Skill.X, Steps.X, Reason.Ok: its field's name) or an enum value
 * used bare (return Ok; return Invalid;: its own name).
 */
class Names implements IObj {
    var name:String;
    public function new(name:String = "") this.name = name;
    public function toString():String return name;
    static var cache = new Map<String, Names>();
    public static function of(name:String):Names {
        var n = cache.get(name);
        if (n == null) { n = new Names(name); cache.set(name, n); }
        return n;
    }
    public function get(name:String):Dynamic return name;
    public function set(name:String, v:Dynamic):Void {}
    public function call(name:String, args:Array<Dynamic>):Dynamic return null;
}

/** A lasting area a step made (hit.area): a script may take it away (remove()), its remaining ticks are gone. */
class AreaObj extends DynObj {
    public var removed = false;
    override public function call(name:String, args:Array<Dynamic>):Dynamic {
        if (name == "remove") { removed = true; return null; }
        return super.call(name, args);
    }
}

class MathObj implements IObj {
    var sim:Sim;
    public function new(sim:Sim) this.sim = sim;
    public function get(name:String):Dynamic {
        return switch (name) {
            case "PI": Math.PI;
            case "POSITIVE_INFINITY": Math.POSITIVE_INFINITY;
            case "NEGATIVE_INFINITY": Math.NEGATIVE_INFINITY;
            default: null;
        }
    }
    public function set(name:String, v:Dynamic):Void {}
    public function call(name:String, a:Array<Dynamic>):Dynamic {
        inline function n(i:Int):Float return Sim.num(a[i]);
        return switch (name) {
            case "min": Math.min(n(0), n(1));
            case "max": Math.max(n(0), n(1));
            case "abs": Math.abs(n(0));
            case "floor": Math.floor(n(0));
            case "ceil": Math.ceil(n(0));
            case "round": Math.round(n(0));
            case "sqrt": Math.sqrt(n(0));
            case "pow": Math.pow(n(0), n(1));
            case "random": sim.rand();
            case "int": Std.int(n(0));
            case "isNaN": Math.isNaN(n(0));
            case "clamp": Math.max(n(1), Math.min(n(2), n(0)));
            default: sim.missing("Math." + name); null;
        }
    }
}

/** A unit of the fight: the hero or the training dummy. */
class Unit implements IObj {
    public var sim:Sim;
    public var hero:Bool;
    public var statuses:Array<Status> = [];
    public var skills:Array<Inst> = [];
    public var healthRatio:Float;
    /** What a summon is (Data.unit id); empty for the hero and the dummy. */
    public var kind = "";
    /** The skill that summoned it (empty for the hero and the dummy). */
    public var summonOf = "";
    /** When a summon goes (addLifetime puts it off). */
    public var lifeEnd = 0.0;
    /** Current values of resource attributes (Spark, Rage, ComboPoint…), see Sim.resGet. */
    public var res = new Map<String, Float>();
    /** 0: the hero's side (the hero, its summons), 1: the foes. */
    public var team:Int;

    public function new(sim:Sim, hero:Bool, team:Int = -1) {
        this.sim = sim;
        this.hero = hero;
        this.team = team >= 0 ? team : (hero ? 0 : 1);
        // the hero is hurt (its heals have something to heal), the dummy half way
        healthRatio = hero ? 0.7 : 0.5;
    }

    public function get(name:String):Dynamic {
        switch (name) {
            case "healthRatio": return healthRatio;
            case "health": return healthRatio * maxHealth();
            case "maxHealth": return maxHealth();
            case "isInCombat": return true;
            case "isDead": return false;
            case "isHero": return hero;
            case "kind": return kind;
            case "owner", "ownerUnit", "unit": return this;
            case "instigatedStatuses": return [for (u in sim.units) for (s in u.statuses) if (s.instigator == this) s];
            case "statuses": return statuses.copy();
            case "position", "pos2D": return new DynObj();
            case "skills": return skills.copy();
            case "priest", "mage", "rogue", "warrior": return sim.component(this, name);
            default:
                sim.missing("unit." + name);
                return null;
        }
    }

    function maxHealth():Float return hero ? sim.timingStat("MaxHealth") : 100000;

    public function set(name:String, v:Dynamic):Void sim.missing("unit.set " + name);

    public function call(name:String, a:Array<Dynamic>):Dynamic {
        switch (name) {
            case "addLifetime": lifeEnd += Sim.num(a[0]); return null;
            case "isAlly": return Std.isOfType(a[0], Unit) && (a[0] : Unit).team == team;
            case "isEnemy": return Std.isOfType(a[0], Unit) && (a[0] : Unit).team != team;
            case "addStatus": return sim.applyStatus(this, Sim.str(a[0]), Std.isOfType(a[2], Inst) ? a[2] : null, Std.int(Math.max(1, Sim.num(a[1]))), a.length > 4 ? Sim.num(a[4]) : null);
            case "removeStatus": var s = sim.findStatus(this, Sim.str(a[0]), null); if (s != null) sim.removeStatus(s); return null;
            case "hasStatus": return sim.findStatus(this, Sim.str(a[0]), null) != null;
            case "getStatus": return sim.findStatus(this, Sim.str(a[0]), Std.isOfType(a[1], Unit) ? a[1] : null);
            case "getStatusCount": var s = sim.findStatus(this, Sim.str(a[0]), null); return s == null ? 0 : s.stacks;
            case "tryConsumeStatus":
                var s = sim.findStatus(this, Sim.str(a[0]), Std.isOfType(a[1], Unit) ? a[1] : null);
                if (s != null) sim.removeStatus(s);
                return s != null;
            case "distanceBetween", "distance": return sim.distance(this, Std.isOfType(a[0], Unit) ? a[0] : null);
            case "isType", "isStatusType": return false;
            case "hasStatusType": var t = Sim.str(a[0]); return Lambda.exists(statuses, st -> !st.removed && GameRules.isType(st.info.statusTypes, t));
            case "getStatusTypeCount": var t = Sim.str(a[0]); return Lambda.count(statuses, st -> !st.removed && GameRules.isType(st.info.statusTypes, t));
            case "getStatuses":
                // the statuses a filter function accepts (optionally only those a unit inflicted)
                var f:Closure = Std.isOfType(a[0], Closure) ? a[0] : null;
                var by:Unit = Std.isOfType(a[1], Unit) ? a[1] : null;
                var out:Array<Dynamic> = [];
                for (st in statuses.copy()) if (!st.removed && (by == null || st.instigator == by) && (f == null || f.run([st]) == true)) out.push(st);
                return out;
            case "getStatusesCount":
                // a filter function, or a status id
                if (Std.isOfType(a[0], Closure)) { var f:Closure = a[0]; return Lambda.count(statuses, st -> !st.removed && f.run([st]) == true); }
                var id = Sim.str(a[0]);
                return Lambda.count(statuses, st -> !st.removed && st.info.id == id);
            case "getAtb", "atb", "atbVal": return sim.atbValue(this, Sim.str(a[0]));
            case "getSkill": return sim.instById(this, Sim.str(a[0]));
            case "isCCImmune", "isUnderAnyCC", "isCrowdControlled", "isStunned": return false;
            case "getTimeInCombat": return sim.time;
            case "getTarget": return team == 0 ? sim.dummy : sim.hero;
            case "getShield": return 0.0;
            case "getOffhandWeaponSkill":
                // ent.Hero.getOffhandWeaponSkill: the weapon skill of the item in Slot_OffhandWeapon (a shield), not the arsenal
                for (sk in skills) if (sk.slot == 2 && sk.isWeaponSkill()) return sk;
                return null;
            case "consumeStatus":
                var st = sim.findStatus(this, Sim.str(a[0]), null);
                if (st == null) return 0;
                var n = a.length > 1 && a[1] != null ? Std.int(Sim.num(a[1])) : st.stacks;
                var used = Std.int(Math.min(n, st.stacks));
                st.stacks -= used;
                if (st.stacks <= 0) sim.removeStatus(st);
                return used;
            default:
                sim.missing("unit." + name + "()");
                return null;
        }
    }
}

/** A skill instance of the hero (or a status, see Status): its cooldown, charges, dynamic values and script. */
class Inst implements IObj implements Host {
    public var sim:Sim;
    public var info:SkillInfo;
    public var rank:Int;
    public var runes:Array<String>;
    public var kind:String;
    public var slot:Int;
    public var item:Dynamic;
    public var owner:Unit;
    /** The summon whose attack this is (its damage is the owner's, heard as onProxyDamage); null for a skill of the hero. */
    public var proxy:Unit = null;
    public var cdEnd = 0.0;
    public var charges = 0;
    public var maxCharges = 0;
    public var dyn = [0.0, 0.0, 0.0, 0.0];
    public var interp:Interp = null;
    public var stepTick = new Map<String, Float>();
    /** End of its cast (isRunning). */
    public var runningUntil = -1.0;
    /** Where in the attack chain the skill is used: before the chain's attack of this index; -1 as soon as it is ready. */
    public var weave = -1;
    /** Raised by stopAreas / cancelWaits: lasting areas and waits started before end. */
    public var areaGen = 0;
    public var waitGen = 0;
    /** The lasting objects the skill's steps made (water spheres): what getSkillObjects gives. */
    public var objects:Array<SkillObj> = [];
    var vars:VarsObj;

    public function new(sim:Sim, info:SkillInfo, rank:Int, runes:Array<String>, kind:String, slot:Int, item:Dynamic, owner:Unit) {
        this.sim = sim;
        this.info = info;
        this.rank = rank;
        this.runes = runes;
        this.kind = kind;
        this.slot = slot;
        this.item = item;
        this.owner = owner;
        vars = new VarsObj(this);
        maxCharges = info.chargesWith(runes);
        if (info.script != null) interp = new Interp(info.script, this);
    }

    public function isStatus():Bool return false;

    public function has(fn:String):Bool return interp != null && interp.has(fn);

    public function fire(fn:String, args:Array<Dynamic>):Dynamic {
        if (interp == null || !interp.has(fn)) return null;
        if (sim.depth > 8) { sim.missing("recursion " + info.id + "." + fn); return null; }
        var prev = sim.current;
        sim.current = this;
        sim.depth++;
        var key = info.id + "." + fn;
        sim.calls.set(key, (sim.calls.exists(key) ? sim.calls.get(key) : 0) + 1);
        var r:Dynamic = null;
        try r = interp.callFn(fn, args) catch (e:Dynamic) {
            sim.missing("error " + info.id + "." + fn + ": " + Std.string(e).substr(0, 80));
        }
        sim.depth--;
        sim.current = prev;
        return r;
    }

    /** BaseSkill.isBaseAttack: an attack of the chain, the combo attack too (types Attack..AttackCombo). */
    public function isAttack():Bool return Sim.ATTACKS.indexOf(info.type) >= 0;
    /** BaseSkill.isBasicAttack: Attack..Attack4, not the combo attack. */
    public function isBasicAttack():Bool return isAttack() && info.type != "AttackCombo";

    // the game's own tests of a skill's kind (st.skill.BaseSkill, HSkill.isSignature, st.skill.BaseSkillAccess.get_isSkill)
    public function isWeaponSkill():Bool return info.type == "WeaponSkill" || info.type == "WeaponSubSkill";
    public function isClassSkill():Bool return info.type == "ClassSkill";
    public function isSignature():Bool
        return ["SignatureSkill", "RoguePoison", "PriestPrayer", "MageConduit"].indexOf(info.type) >= 0
            || info.id == "Mage_SparkMaster" || info.id == "Rogue_MasterPoisoner";
    /** hit.isSkill / ctx.isSkill: a weapon, class or signature skill. */
    public function isSkillHit():Bool return isWeaponSkill() || isClassSkill() || isSignature();
    /** BaseSkill.isActiveSkill: WeaponSkill, ClassSkill, SignatureSkill. */
    public function isActiveSkill():Bool return info.type == "WeaponSkill" || info.type == "ClassSkill" || info.type == "SignatureSkill";

    // ---- the object scripts see as `skill`, `hit.skill`, `ctx.skill`
    public function get(name:String):Dynamic {
        switch (name) {
            case "kind", "id": return info.id;
            case "owner", "ownerUnit", "ownerHero", "instigator": return owner;
            case "rank": return rank;
            case "vars": return vars;
            case "inf": return null;
            case "charges": return charges;
            case "script": return new ScriptRef(this);
            default:
                sim.missing("skill." + name);
                return null;
        }
    }

    public function set(name:String, v:Dynamic):Void sim.missing("skill.set " + name);

    public function call(name:String, a:Array<Dynamic>):Dynamic {
        switch (name) {
            case "isFinalAttack", "isFinalCombo": return info.type == "AttackCombo";
            case "isBaseAttack", "isAttack": return isAttack();
            case "isBasicAttack": return isBasicAttack();
            case "isWeaponSkill": return isWeaponSkill();
            case "isClassSkill": return isClassSkill();
            case "isSignature": return isSignature();
            case "isFromArsenal": return slot == 1;
            case "isFromWeapon", "isWeaponBased": return slot == 0 || slot == 1;
            case "isPassive": return Sim.ACTIVE.indexOf(info.type) < 0 && !isAttack();
            case "isSkill": return isSkillHit();
            case "isActiveSkill": return isActiveSkill();
            case "isDoT": return info.dotHot;
            case "hasMastery": return runes.indexOf(Sim.str(a[0])) >= 0;
            case "getMaxStacks": return info.maxStacks;
            case "isInCooldown": return sim.time < cdEnd;
            case "getDynVal": return dyn[Std.int(Sim.num(a[0]))];
            case "setDynVal": dyn[Std.int(Sim.num(a[0]))] = Sim.num(a[1]); return null;
            case "isType", "isStatusType": return GameRules.isType(info.statusTypes, Sim.str(a[0]));
            case "getSparkCost": return sim.sparkCost(this);
            case "getCooldown": return info.cooldownWith(runes);
            case "getSourceSkill": return isStatus() && (cast this : Status).source != null ? (cast this : Status).source : this;
            case "getSourceObject": return owner;
            case "getCtx": return sim.ctx;
            case "setShield", "fireProjectiles", "hoverProjectile": return null;
            case "resetCooldown": cdEnd = sim.time; return null;
            case "reduceCooldown": cdEnd -= Sim.num(a[0]); return null;
            case "isRunning": return sim.time < runningUntil;
            case "isPeriodic": return info.dotHot || Lambda.exists(info.steps, st -> st.tick != null);
            case "getSkillObjects": objects = [for (o in objects) if (o.alive()) o]; return objects.copy();
            case "getProjectiles": return [];
            case "refresh":
                // a status lasts its whole duration again (its Refresh steps run)
                if (isStatus()) {
                    var st:Status = cast this;
                    var dur = info.durationWith(st.runes);
                    if (dur > 0 && !st.removed) st.endTime = sim.time + dur;
                    sim.refreshSteps(st);
                }
                return null;
            case "playStep", "playGlobalStep":
                // a status's own step played by a script that holds it (the poison's Blast), at the status's unit
                return sim.api(this, name, a.length > 1 ? a : [a[0], isStatus() ? (cast this : Status).unit : null]);
            case "remove": if (isStatus()) sim.removeStatus(cast this); return null;
            case "consume":
                // a status consumed: gone, its stacks returned
                if (isStatus()) { var n = (cast this : Status).stacks; sim.removeStatus(cast this); return n; }
                return 0;
            default:
                sim.missing("skill." + name + "()");
                return null;
        }
    }

    // ---- Host: what the script's own code sees
    public function global(name:String):Dynamic {
        switch (name) {
            case "vars": return vars;
            case "rank": return rank;
            case "kind": return info.id;
            case "stacks": return isStatus() ? (cast this : Status).stacks : 0;
            case "maxStacks": return info.maxStacks;
            case "elapsedTime": return isStatus() ? sim.time - (cast this : Status).start : 0.0;
            case "owner", "ownerUnit", "ownerHero": return owner;
            case "skill": return this;
            case "status": return isStatus() ? this : null;
            case "ctx": return sim.ctx;
            case "Math": return sim.mathObj;
            case "time": var t = new DynObj(); t.set("now", sim.time); return t;
            case "isServer": return true;
            case "isClient": return false;
            case "Std": return sim.stdObj;
            case "sourceSkill": return isStatus() && (cast this : Status).source != null ? (cast this : Status).source : this;
            default:
                // Skill.X, Steps.X, Mastery.X, GameBeat.X, Invalid / Ok…
                if (name.length > 0 && name.charAt(0) >= "A" && name.charAt(0) <= "Z") return Names.of(name);
                sim.missing("global " + name);
                return null;
        }
    }

    public function callGlobal(name:String, a:Array<Dynamic>):Dynamic return sim.api(this, name, a);

    public function missing(what:String):Void sim.missing(what);
}

/** A status on a unit: it is a skill too (its own steps and script), applied by someone. */
class Status extends Inst {
    public var unit:Unit;
    public var instigator:Unit;
    public var source:Inst;
    public var stacks = 1;
    /**
     * A status with no stack limit holds an amount of damage (Warrior_Hemorrhage_Status: "x% of the damage dealt over its duration"):
     * every application adds to the pool, every tick pays `payFrac` of it (-1: not a tick of a pool).
     */
    public var pool = 0.0;
    public var payFrac = -1.0;
    public var endTime = 0.0;
    public var start = 0.0;
    public var removed = false;

    public function new(sim:Sim, info:SkillInfo, source:Inst, unit:Unit, instigator:Unit) {
        super(sim, info, source != null ? source.rank : 1, source != null ? source.runes : [], "status", source != null ? source.slot : -1,
            source != null ? source.item : null, unit);
        this.source = source;
        this.unit = unit;
        this.instigator = instigator;
    }

    override public function isStatus():Bool return true;

    override public function get(name:String):Dynamic {
        switch (name) {
            case "stacks": return stacks;
            case "owner", "ownerUnit": return unit;
            case "instigator": return instigator;
            case "kind", "id": return info.id;
            case "target", "unit": return unit;
            case "duration": return endTime - start;
            case "elapsed": return sim.time - start;
            case "instigatorSkill": return source;
            default: return super.get(name);
        }
    }

    override public function call(name:String, a:Array<Dynamic>):Dynamic {
        switch (name) {
            case "isInfinite": return endTime == Math.POSITIVE_INFINITY;
            case "getMaxStacks": return info.maxStacks;
            case "extendDuration": endTime += Sim.num(a[0]); return null;
            case "setDynVal": dyn[Std.int(Sim.num(a[0]))] = Sim.num(a[1]); return null;
            case "getSourceObject": return instigator;
            case "getDurationLeft": return endTime - sim.time;
            case "getElapsedTime": return sim.time - start;
            default: return super.call(name, a);
        }
    }
}

/** `vars` of a script: the skill's variables by its rank and runes. */
class VarsObj implements IObj {
    var inst:Inst;
    public function new(inst:Inst) this.inst = inst;
    public function get(name:String):Dynamic {
        var v = inst.info.v(name, inst.rank, inst.runes);
        return v == null ? 0.0 : v;
    }
    public function set(name:String, v:Dynamic):Void {}
    public function call(name:String, a:Array<Dynamic>):Dynamic return null;
}

/** A hit (damage, heal) or a cast context as scripts see it. */
/** A lasting object of a skill (a water sphere): it can be pulled to the hero by a script, which takes it. */
class SkillObj implements IObj {
    public var until:Float;
    public var gone = false;
    var sim:Sim;
    public function new(sim:Sim, until:Float) { this.sim = sim; this.until = until; }
    public function alive():Bool return !gone && sim.time < until;
    public function get(name:String):Dynamic return null;
    public function set(name:String, v:Dynamic):Void {}
    public function call(name:String, args:Array<Dynamic>):Dynamic {
        switch (name) {
            case "magnetTo":
                // flies to the unit: its callback runs on arrival (the sphere is taken then)
                var f:Closure = Std.isOfType(args[1], Closure) ? args[1] : null;
                var src = sim.current;
                if (f != null && src != null) sim.at(sim.time + 0.3, () -> if (!gone) { sim.current = src; f.run([this]); });
                return null;
            case "consume": gone = true; return null;
            default: sim.missing("skillObject." + name + "()"); return null;
        }
    }
}

class HitObj extends DynObj {
    public function new() super();
    override public function get(name:String):Dynamic {
        var v = fields.get(name);
        if (v == null && !fields.exists(name)) {
            switch (name) {
                case "dmgMult", "healMult", "physicalDmgMult", "magicDmgMult": return 1.0;
                case "dmgAdd", "critChance", "magicArmorIgnore", "armorIgnore", "threatMultiplier", "amount", "totalHits", "block": return 0.0;
                default:
            }
        }
        return v;
    }
    override public function call(name:String, args:Array<Dynamic>):Dynamic {
        if (name == "isStatusType" || name == "isType") {
            // the hit of a status (a poison's tick): its types
            var st:Dynamic = fields.get("status");
            return Std.isOfType(st, Inst) && GameRules.isType((st : Inst).info.statusTypes, Sim.str(args[0]));
        }
        var f = fields.get(name);
        if (f != null && !Std.isOfType(f, Closure)) return f; // isSkill() written as a call
        return super.call(name, args);
    }
}

/**
 * A fight of the hero against a training dummy, run by the skills' own data and scripts: the attack chain
 * of the main weapon, the skills when ready (prayers when charged), steps with their delays and ticks,
 * statuses with their duration, stacks and ticks, and every script handler the game calls
 * (on…Eval before a hit, onInflictDamage after it, onSkillProc, onUseSkill, onRegUpdate…). Chances (crits,
 * checkProba) are not rolled: each one comes true exactly as often as its chance (`chance`), so a 40 s fight gives
 * every build its expected luck (rolled chances made the same build heal 27 or 44/s with an infusion proc).
 */
class Sim {
    public static var ATTACKS = ["Attack", "Attack2", "Attack3", "Attack4", "AttackCombo"];
    public static var ACTIVE = ["ClassSkill", "WeaponSkill", "SignatureSkill", "Skill", "Secondary", "PriestPrayer", "MageConduit", "RoguePoison", "GroupSkill"];
    static var PASSIVE_EVENTS_EVERY = 0.25;

    public var env:SimEnv;
    public var time = 0.0;
    public var units:Array<Unit> = [];
    public var hero:Unit;
    public var dummy:Unit;
    public var mathObj:MathObj;
    public var stdObj:DynObj;
    public var ctx:Dynamic = null;
    public var current:Inst = null;
    var queue:Array<{t:Float, f:Void->Void, seq:Int}> = [];
    var seq = 0;
    var seed:Int;
    var busyUntil = 0.0;
    var chain:Array<Inst> = [];
    var chainIndex = 0;
    /** End of the last attack of the chain (ent.Hero.getNextAttackSkill: past Const.ComboWindow the chain starts again). */
    var lastAttackEnd = -1e9;
    var actives:Array<Inst> = [];
    public var damage = new Map<String, Float>();
    public var depth = 0;
    /** How many times each script handler ran (diagnostics). */
    public var calls = new Map<String, Int>();
    public var heal = new Map<String, Float>();
    var allyHealed = 0.0;
    /**
     * Shields on the hero still holding something: a shield counts for healing only by the damage it takes in
     * (the player's choice) — its size alone is no heal, the dummy hardly hits. `rec`: its line in the log (replay),
     * `link`: the status it belongs to (it ends with it; a new shield of the same status replaces it), `ally`: an ally
     * next to the hero would have it too (same damage taken).
     */
    var shields:Array<{id:String, left:Float, rec:HitRec, link:Inst, ally:Bool}> = [];

    function addShieldPool(id:String, amount:Float, rec:HitRec, link:Inst, ally:Bool):Void {
        shields = [for (x in shields) if (!(link != null ? x.link == link : (x.link == null && x.id == id))) x];
        if (amount > 0) shields.push({id: id, left: amount, rec: rec, link: link, ally: ally});
    }

    /** Damage taken by the hero goes into its shields first (oldest first); what they take counts as their healing. */
    function absorb(amount:Float):Void {
        var i = 0;
        while (amount > 1e-12 && i < shields.length) {
            var x = shields[i];
            var a = Math.min(x.left, amount);
            x.left -= a;
            amount -= a;
            heal.set(x.id, (heal.exists(x.id) ? heal.get(x.id) : 0) + a);
            if (x.ally) allyHealed += a;
            if (x.rec != null) x.rec.amount += a;
            if (x.left <= 1e-12) shields.splice(i, 1) else i++;
        }
    }
    public var casts = new Map<String, Int>();
    public var missingLog = new Map<String, Int>();
    var statsCache:StatsView = null;
    var statsDirty = true;
    var components = new Map<String, IObj>();
    var mageObj:MageObj = null;

    public static function num(v:Dynamic):Float {
        if (v == null) return 0;
        if (Std.isOfType(v, Bool)) return v ? 1 : 0;
        if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return v;
        return 0;
    }

    public static function str(v:Dynamic):String {
        if (v == null) return "";
        if (Std.isOfType(v, Inst)) return (v : Inst).info.id;
        return Std.string(v);
    }

    public function new(env:SimEnv, seed:Int = 12345) {
        this.env = env;
        this.seed = seed;
        mathObj = new MathObj(this);
        stdObj = new DynObj();
        hero = new Unit(this, true);
        dummy = new Unit(this, false);
        units = [hero, dummy];
    }

    /**
     * A chance without luck: per source (the skill whose script asks, or the hit's skill for a crit) the chances add up,
     * and it comes true each time the sum passes a whole number (starting at one half: the nearest count). A 15% proc
     * comes true 3 times in 20 tries, never 0 or 6 by chance; the same build is always valued the same.
     */
    var chances = new Map<String, Float>();

    public function chance(source:String, p:Float):Bool {
        if (p <= 0) return false;
        if (p >= 1) return true;
        var acc = (chances.exists(source) ? chances.get(source) : 0.5) + p;
        var yes = acc >= 1;
        chances.set(source, yes ? acc - 1 : acc);
        return yes;
    }

    public function rand():Float {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed / 0x7fffffff;
    }

    public function missing(what:String):Void missingLog.set(what, (missingLog.exists(what) ? missingLog.get(what) : 0) + 1);

    public function component(u:Unit, name:String):IObj {
        if (name == "priest") return new PriestObj(this);
        if (name == "mage") { if (mageObj == null) mageObj = new MageObj(this); return mageObj; }
        var c = components.get(name);
        if (c == null) { c = new UnknownComponent(this, name); components.set(name, c); }
        return c;
    }

    public function chargedPrayers():Array<Inst> return [for (s in hero.skills) if (s.info.type == "PriestPrayer" && s.charges > 0) s];

    /** ent.hero.PriestComponent.divineInterventionProc: each charged prayer starts, then onPrayerTrigger. */
    public function divineIntervention():Void {
        for (p in chargedPrayers()) {
            p.charges = 0;
            castSkill(p, 0);
            dispatchUnit(hero, "onPrayerTrigger", [p], null);
        }
    }

    var summons = 0;
    /** Switches of the parts added for the dummy logs of 2026-10-19 (the test mode and tests can turn each off to see what it changes). */
    public static var off = new Map<String, Bool>();

    function summon(inst:Inst, s:SStep, dur:Float, c:Dynamic):Void {
        var life = dur > 0 ? dur : 10;
        var attacks = s.summon != "" && !off.exists("summonAttacks") ? env.unitSkills(s.summon) : [];
        for (n in 0...s.summonCount) {
            var u = new Unit(this, false, inst.owner.team);
            u.healthRatio = 1;
            u.kind = s.summon;
            u.summonOf = inst.info.id;
            units.push(u);
            summons++;
            inst.fire("onSummon", [u]);
            var endAt = time + life;
            // the summon attacks the dummy with its own skills (Data.unit skills) for as long as it lives: one attack every
            // cycle of the skill (its longest step: delay + duration), the first one after most of a cycle
            for (id in attacks) {
                var si = env.skill(id);
                if (si == null) continue;
                var att = new Inst(this, si, inst.rank, [], "summon", -1, null, hero);
                att.proxy = u;
                var cycle = 0.0;
                for (st in si.steps) cycle = Math.max(cycle, si.value(st.delay, att.rank, att.runes, 0) + si.value(st.duration, att.rank, att.runes, 0));
                // the skill's own duration and cooldown count too (SummonBee_HoneyBolt: 2 s and a cooldown of 1 s)
                cycle = Math.max(cycle, si.duration) + si.cooldown;
                // a summon's lasting step with a tick (the totem's waves of healing): every tick
                if (cycle <= 0.1) for (st in si.steps) {
                    var tk = si.value(st.tick, att.rank, att.runes, 0);
                    if (tk > 0 && st.effects.length > 0) cycle = cycle <= 0.1 ? tk : Math.min(cycle, tk);
                }
                if (cycle <= 0.1) continue;
                var strike:Void->Void = null;
                strike = function() {
                    if (units.indexOf(u) < 0) return;
                    summonAttack(att, si);
                    at(time + cycle, strike);
                };
                at(time + cycle * 0.8, strike);
            }
            u.lifeEnd = endAt;
            var expire:Void->Void = null;
            expire = function() {
                if (u.lifeEnd > time + 1e-9) { at(u.lifeEnd, expire); return; }
                for (st in u.statuses.copy()) removeStatus(st);
                units.remove(u);
                inst.fire("onSummonElapsed", [u]);
            };
            at(endAt, expire);
        }
    }

    /** One attack of a summon: the effects of its skill's steps on the dummy. */
    function summonAttack(att:Inst, si:SkillInfo):Void {
        var hc = new HitObj();
        for (st in si.steps) if (st.effects.length > 0 && si.stepActive(st, att.rank, att.runes))
            for (e in st.effects) applyEffect(att, st, e, e.kind == "Heal" || e.kind == "Shield" ? hero : dummy, hc, 1);
    }

    public function later(dt:Float, f:Void->Void):Void at(time + Math.max(0, dt), f);

    /** A step whose props.stepGlobal.globalId is `id`, among the hero's skills. */
    function globalStep(id:String):{inst:Inst, step:SStep} {
        for (sk in hero.skills) for (st in sk.info.steps) if (st.globalId == id) return {inst: sk, step: st};
        return null;
    }

    /** A projectile step played by a script (getStepById(..).generateProjectile): as when the skill plays it. */
    public function fireProjectile(inst:Inst, s:SStep, target:Unit):Void runStepNow(inst, s, target, ctx, true);

    public function at(t:Float, f:Void->Void):Void {
        queue.push({t: t, f: f, seq: seq++});
    }

    function popNext():{t:Float, f:Void->Void, seq:Int} {
        var best = -1;
        for (i in 0...queue.length) if (best < 0 || queue[i].t < queue[best].t || (queue[i].t == queue[best].t && queue[i].seq < queue[best].seq)) best = i;
        if (best < 0) return null;
        var e = queue[best];
        queue[best] = queue[queue.length - 1];
        queue.pop();
        return e;
    }

    // ---------------------------------------------------------------- stats

    /** An affix whose value follows the status's dynamic value (mod.dynVal): with the value it has now. */
    function dynAffix(a:SAffix, s:Inst):SAffix {
        if (a.dyn <= 0) return a;
        var d = s.dyn[a.dyn];
        var v = switch (a.dynOp) { case 0: a.val * d; case 1: d; default: a.val + d; };
        return {ref: a.ref, attr: a.attr, val: v, minRank: a.minRank, maxRank: a.maxRank, equalRank: a.equalRank, mastery: a.mastery, dyn: a.dyn, dynOp: a.dynOp};
    }

    public function statsNow():StatsView {
        if (statsDirty || statsCache == null) {
            var buffs = [];
            for (s in hero.statuses) for (a in s.info.affixes) if (s.info.affixActive(a, s.rank, s.runes)) buffs.push({a: dynAffix(a, s), share: (s.stacks : Float)});
            var key = [for (b in buffs) b.a.attr + "|" + b.a.ref + "|" + b.a.val + "|" + b.share].join(",");
            var i = buffKeys.get(key);
            if (i == null) { i = buffSets.length; buffSets.push(buffs); buffKeys.set(key, i); }
            buffIndex = i;
            statsCache = env.stats(buffs);
            statsDirty = false;
        }
        return statsCache;
    }

    /** The hero's buff sets met in the fight (the statuses' affixes), and the one on now. */
    public var buffSets:Array<Array<{a:SAffix, share:Float}>> = [];
    var buffKeys = new Map<String, Int>();
    var buffIndex = 0;
    /** Attributes the fight's course depends on (cooldowns, cast times, scripts reading them), not only its numbers. */
    public var timing = new Map<String, Float>();

    /**
     * Keeps only what `replay` needs (the hit log, the buff sets, the casts) and lets the rest go: a fight kept whole for
     * every build valued (units, statuses, script interpreters, the event queue — each skill instance holding its owner,
     * its script and the fight) took 12 GB in two calculations, and the garbage collector then stopped the game for 12 s
     * (the server closed the connection).
     */
    public function compact():Void {
        for (r in log) {
            var i = r.inst;
            if (i == null) continue;
            i.interp = null;
            i.owner = null;
            // i.item (a candidate) stays: effectBase needs its power
            if (Std.isOfType(i, Status)) {
                var st:Status = cast i;
                st.unit = null;
                st.instigator = null;
                st.source = null;
            }
        }
        for (x in shields) x.link = null;
        shields = [];
        queue = [];
        units = [];
        hero = null;
        dummy = null;
        ctx = null;
        current = null;
        chain = [];
        actives = [];
        components = new Map();
        mageObj = null;
        statsCache = null;
        calls = new Map();
        chances = new Map();
    }
    /** Sets of the target's status affixes met in the fight (index 0: none). */
    public var targetBuffSets:Array<Array<{a:SAffix, share:Float}>> = [[]];
    var targetBuffKeys = ["" => 0];

    function targetBuffs(u:Unit):Int {
        if (u == null || u == hero) return 0;
        var buffs = [];
        for (s in u.statuses) if (!s.removed) for (a in s.info.affixes) if (s.info.affixActive(a, s.rank, s.runes)) buffs.push({a: dynAffix(a, s), share: (s.stacks : Float)});
        if (buffs.length == 0) return 0;
        var key = [for (b in buffs) b.a.attr + "|" + b.a.ref + "|" + b.a.val + "|" + b.share].join(",");
        var i = targetBuffKeys.get(key);
        if (i == null) { i = targetBuffSets.length; targetBuffSets.push(buffs); targetBuffKeys.set(key, i); }
        return i;
    }
    /** Every damage and heal of the fight, to value it again with other attributes (replay). */
    public var log:Array<HitRec> = [];

    public function timingStat(name:String):Float {
        var v = statsNow().get(name);
        if (!timing.exists(name)) timing.set(name, v);
        return v;
    }

    /**
     * A resource attribute as the game's resource code reads it (ent.UnitAttributes.get / getMax: the raw value, not the
     * displayed percentage): Rage's gain factor is 1 raw, 0.01 shown — taken shown, a warrior gained 0.85 Rage in 40 s
     * and never used Rage Strike.
     */
    public function timingRaw(name:String):Float {
        var v = statsNow().raw(name);
        if (!timing.exists(name)) timing.set(name, statsNow().get(name));
        return v;
    }

    /**
     * The same fight valued with other attributes (another `env` of the same skills): each logged hit again
     * with its buffs, script multipliers and expected critical hits; damage and heals made of other hits
     * (dynamic values) scale with them. Valid while the fight's course stays the same (see `timing`).
     */
    public function replay(env:SimEnv):SimResult {
        var statsBy = new Map<Int, StatsView>();
        var dmg = new Map<String, Float>(), hl = new Map<String, Float>();
        var dmgNow = 0.0, dmgThen = 0.0, healNow = 0.0, healThen = 0.0, ally = 0.0, self = 0.0, total = 0.0;
        function value(r:HitRec):Float {
            var st = statsBy.get(r.buffs);
            if (st == null) { st = env.stats(buffSets[r.buffs]); statsBy.set(r.buffs, st); }
            if (r.e == null) return r.add * st.get("HealGivenMultiplier");
            var base = env.effectBase(r.inst, r.e, st) / r.split + r.add;
            var cc = r.crit ? Math.min(1, Math.max(0, st.get("CritChance") + r.ccAdd)) : 0.0;
            var critF = 1 + cc * Math.max(0, st.get("CritDamage") + r.cdAdd - 1);
            if (r.kind == 0) {
                var ratio = (1 + st.get(r.e.physical ? "PhysicalMastery" : "MagicMastery") + st.get("Fervor")) * st.get("DamageModifier");
                var pen = Math.min(1, Math.max(0, st.get(r.e.physical ? "ArmorPenetration" : "SpellPenetration")));
                var def = env.targetDefense(r.e.physical, targetBuffSets[r.tbuffs]);
                var armor = def[0] * (1 - pen) * (1 - r.ignore);
                return Math.max(0, base * Math.max(0, ratio) * r.mult * critF * (1 - env.armorReduction(armor)) * def[1]);
            }
            if (r.kind == 1) return Math.max(0, base * st.get("HealGivenMultiplier") * r.mult * critF);
            // a shield: what it absorbed (the damage taken, not its size)
            return r.amount;
        }
        var vals = [];
        for (r in log) {
            var v = r.dyn ? 0.0 : value(r);
            vals.push(v);
            if (r.dyn) continue;
            if (r.kind == 0) { dmgNow += v; dmgThen += r.amount; } else { healNow += v; healThen += r.amount; }
        }
        var dmgScale = dmgThen > 0 ? dmgNow / dmgThen : 1, healScale = healThen > 0 ? healNow / healThen : 1;
        for (i in 0...log.length) {
            var r = log[i];
            var v = r.dyn ? r.amount * (r.kind == 0 ? dmgScale : healScale) : vals[i];
            var id = r.inst.info.id;
            if (r.kind == 0) { dmg.set(id, (dmg.exists(id) ? dmg.get(id) : 0) + v); total += v; }
            else if (r.self) {
                hl.set(id, (hl.exists(id) ? hl.get(id) : 0) + v);
                self += v;
                if (r.ally) ally += v;
            }
        }
        return {dps: total / length, selfHeal: self / length, allyHeal: ally / length, damage: dmg, heal: hl, casts: casts, missing: missingLog, time: length,
            resources: resourcesText};
    }

    var length = 60.0;

    // ---------------------------------------------------------------- resources (Spark, Rage, ComboPoint…)

    /** A unit's attribute as scripts read it: a resource's current value, health, else the hero's attribute. */
    public function atbValue(u:Unit, id:String):Float {
        if (u == null) return 0;
        if (id == "Health") return u.healthRatio * (u == hero ? timingStat("MaxHealth") : 100000);
        if (GameRules.attributes.exists(id)) return resGet(u, id);
        return u == hero ? timingStat(id) : 0;
    }

    function resMax(u:Unit, at:SAttr):Float return u == hero ? timingRaw(at.max) : 0;

    /**
     * A resource's value; the first time: full if the game refills it out of combat (a regeneration out of combat that
     * adds: Spark), else empty (one that drains out of combat, or none: Rage, ComboPoint).
     */
    public function resGet(u:Unit, id:String):Float {
        var v = u.res.get(id);
        if (v != null) return v;
        var at = GameRules.attributes.get(id);
        var start = 0.0;
        if (at != null && u == hero) for (r in at.regen) if (r.cond == "timeOutsideCombat" && timingRaw(r.atb) * r.factor > 0) start = resMax(u, at);
        u.res.set(id, start);
        return start;
    }

    /**
     * ent.Unit.addResource / UnitAttributes.add: the change times the gain factor (gainAtb), kept between 0 and the
     * maximum; a decrease is a consumption (ent.Hero.addResource: HeroComponent.onConsumeResource, onOwnerConsumeResource).
     */
    public function resAdd(u:Unit, id:String, amount:Float):Void {
        var at = GameRules.attributes.get(id);
        if (at == null || u == null) return;
        var before = resGet(u, id);
        var factor = 1.0;
        if (at.gain != "" && u == hero) { factor = timingRaw(at.gain); if (factor <= 0) factor = 1.0; }
        var after = Math.max(0, Math.min(resMax(u, at), before + amount * factor));
        if (u == hero && amount > 0) resGained.set(id, (resGained.exists(id) ? resGained.get(id) : 0) + amount * factor);
        u.res.set(id, after);
        if (after < before && u == hero) {
            dispatchUnit(hero, "onOwnerConsumeResource", [id, after - before], null);
            if (mageObj != null || hasConduits()) cast(component(hero, "mage"), MageObj).onConsumeResource(id, before);
        }
    }

    var resGained = new Map<String, Float>();
    /** The resources at the end of the fight (run), kept for the replays' reports. */
    public var resourcesText = "";

    public function resSet(u:Unit, id:String, v:Float):Void {
        var at = GameRules.attributes.get(id);
        if (at == null || u == null) return;
        u.res.set(id, Math.max(0, Math.min(resMax(u, at), v)));
    }

    /** Regenerations in combat (no condition, or timeInCombat) of the resources in use, every `dt`. */
    function regenResources(dt:Float):Void {
        for (id => v in hero.res) {
            var at = GameRules.attributes.get(id);
            if (at == null) continue;
            var add = 0.0;
            for (r in at.regen) if (r.cond == "" || r.cond == "timeInCombat") add += timingRaw(r.atb) * r.factor * dt;
            if (add != 0) hero.res.set(id, Math.max(0, Math.min(resMax(hero, at), v + add)));
        }
    }

    /** What a use of the skill costs now (props.costs, through the script's evalCost). */
    function costOf(a:Inst, c:{atb:String, amount:Float}):Float {
        if (a.has("evalCost")) { var r = a.fire("evalCost", [c.amount, c.atb]); if (r != null) return num(r); }
        return c.amount;
    }

    /** st.skill.Skill.ownerHaveAllCost. */
    function canPay(a:Inst):Bool {
        for (c in a.info.costs) if (resGet(hero, c.atb) < costOf(a, c) - 1e-9) return false;
        return true;
    }

    /** st.skill.Skill.consumeResources. */
    function pay(a:Inst):Void {
        for (c in a.info.costs) { var v = costOf(a, c); if (v > 0) resAdd(hero, c.atb, -v); }
    }

    /**
     * st.skill.Skill.getSparkCost: a final combo attack costs Mage_Spark_SpellCDCost_FinalCombo; a skill
     * max(Mage_Spark_SpellMinCost, its cooldown × Mage_Spark_SpellCDCostRatio), rounded.
     */
    public function sparkCost(a:Inst):Float {
        if (a.info.type == "AttackCombo") return Math.round(GameRules.constant("Mage_Spark_SpellCDCost_FinalCombo"));
        return Math.round(Math.max(GameRules.constant("Mage_Spark_SpellMinCost"), a.info.cooldownWith(a.runes) * GameRules.constant("Mage_Spark_SpellCDCostRatio")));
    }

    function hasConduits():Bool return Lambda.exists(hero.skills, s -> s.info.type == "MageConduit");

    // ---------------------------------------------------------------- distance

    /** Distance from the hero's side to the dummy: the reach of the main weapon's first attack (melee: a few metres). */
    public var targetDistance = 2.0;

    public function distance(a:Unit, b:Unit):Float {
        if (a == null || b == null || a == b) return 0;
        return a.team == b.team ? 0 : targetDistance;
    }

    // ---------------------------------------------------------------- the build

    /** Sets up the hero's skills; `weaponSkillSlots`: how many weapon skills of the main weapon are used. */
    public function setup(given:Array<SkillSpec>):Void {
        var plain = [], fin:Inst = null;
        // the passives a skill gives from a rank on (props.rankPassives: the dual axes' combo at rank 3…), each once
        var specs = given.copy();
        var have = [for (sp in given) sp.id => true];
        for (sp in given) {
            var gi = env.skill(sp.id);
            if (gi != null && !off.exists("rankPassives")) for (rp in gi.rankPassives) if (sp.rank >= rp.minRank) for (id in rp.ids) if (!have.exists(id)) {
                have.set(id, true);
                specs.push({id: id, rank: sp.rank, runes: [], kind: sp.kind, slot: sp.slot, item: sp.item});
            }
        }
        // the skills one replaces while it can be recast (getOverrideSkill) are the hero's too
        var ovr = ~/return\s+Skill\.(\w+)/;
        for (sp in specs.copy()) {
            var gi = env.skill(sp.id);
            if (gi == null) continue;
            var at = gi.scriptText.indexOf("function getOverrideSkill");
            if (at < 0) continue;
            var body = gi.scriptText.substr(at);
            while (ovr.match(body)) {
                var id = ovr.matched(1);
                body = ovr.matchedRight();
                if (!have.exists(id) && env.skill(id) != null) {
                    have.set(id, true);
                    specs.push({id: id, rank: sp.rank, runes: [], kind: sp.kind, slot: sp.slot, item: sp.item});
                }
            }
        }
        for (sp in specs) {
            var info = env.skill(sp.id);
            if (info == null) { missing("skill data " + sp.id); continue; }
            var inst = new Inst(this, info, sp.rank, sp.runes, sp.kind, sp.slot, sp.item, hero);
            if (sp.weave != null) inst.weave = sp.weave;
            hero.skills.push(inst);
            if (sp.slot == 0 && ATTACKS.indexOf(info.type) >= 0) {
                if (info.type == "AttackCombo") fin = inst else plain.push(inst);
            } else if ((ACTIVE.indexOf(info.type) >= 0 || (info.type == "WeaponSubSkill" && inst.has("checkEnabled") && !off.exists("subUltimate"))) && info.type != "PriestPrayer" && info.type != "MageConduit" && info.type != "RoguePoison"
                && (info.cooldown > 0 || inst.maxCharges > 0 || inst.has("checkEnabled") || info.costs.length > 0))
                // a skill with no cooldown that its script enables (checkEnabled: an infusion's ultimate when it is ready) is used as soon as it may be
                actives.push(inst);
        }
        // the attack chain as ent.Hero.getNextAttackSkill makes it: each attack of the main weapon once (hero.attackSkills),
        // then its combo attack (a weapon with one attack: attack, combo, attack, combo…)
        for (p in plain) chain.push(p);
        if (fin != null) chain.push(fin);
        if (chain.length > 0 && chain[0].info.reach > 0) targetDistance = chain[0].info.reach;
        // skills charged by events start empty (prayers)
        for (a in actives) if (usesCharges(a)) a.charges = 0;
    }

    function usesCharges(a:Inst):Bool {
        if (a.info.type == "PriestPrayer") return true;
        return a.maxCharges > 0 && a.info.cooldown <= 1;
    }

    // ---------------------------------------------------------------- running

    public function run(seconds:Float):SimResult {
        length = seconds;
        // passives start: their status steps (permanent buffs) and regular updates
        for (s in hero.skills) s.fire("onStart", []);
        var tick:Void->Void = null;
        tick = function() {
            if (time > seconds) return;
            regenResources(PASSIVE_EVENTS_EVERY);
            dispatchAll("onRegUpdate", [PASSIVE_EVENTS_EVERY]);
            dispatchAll("onUpdate", [PASSIVE_EVENTS_EVERY]);
            at(time + PASSIVE_EVENTS_EVERY, tick);
        };
        at(0, tick);
        at(0, act);
        // the dummy does not fight back: a hit of 1 damage every INCOMING_EVERY seconds wakes what reacts to hits taken
        var incoming:Void->Void = null;
        incoming = function() {
            if (time > seconds) return;
            receiveHit(hero, dummy, 1);
            at(time + INCOMING_EVERY, incoming);
        };
        at(INCOMING_EVERY, incoming);
        var guard = 0;
        var wall = haxe.Timer.stamp();
        while (guard++ < 200000) {
            if ((guard & 255) == 0 && haxe.Timer.stamp() - wall > 10) { missing("aborted at " + Math.round(time * 10) / 10 + " s"); break; }
            var e = popNext();
            if (e == null || e.t > seconds) break;
            time = e.t;
            e.f();
        }
        var total = 0.0, healed = 0.0;
        for (v in damage) total += v;
        for (v in heal) healed += v;
        // the hero's resources at the end, their maximum and gain factor (for the log: why a skill with a cost was not used)
        var res = [for (id => v in hero.res) {
            var at = GameRules.attributes.get(id);
            id + "=" + Math.round(v * 100) / 100 + (at == null ? "" : "/" + Math.round(resMax(hero, at) * 100) / 100 + " gain x" + (at.gain != "" ? Std.string(Math.round(timingRaw(at.gain) * 1000) / 1000) : "1")
                + " gained " + Math.round((resGained.exists(id) ? resGained.get(id) : 0) * 100) / 100);
        }].join(", ");
        resourcesText = res;
        return {dps: total / seconds, selfHeal: healed / seconds, allyHeal: allyHealed / seconds, damage: damage, heal: heal, casts: casts, missing: missingLog, time: seconds,
            resources: res};
    }

    /** The hero's next action: a ready skill (prayers when charged), else the next hit of the attack chain. */
    function act():Void {
        if (time < busyUntil) { at(busyUntil, act); return; }
        var cdMod = Math.max(0, 1 - timingStat("CooldownReduction"));
        var castMod = Math.max(0.1, 1 - timingStat("SpellCastTimeReduction"));
        var pick:Inst = null;
        // a skill that is replaced by another while it can be used again (getOverrideSkill: the recast of a dash, of a throw of fangs
        // or of spheres): the player recasts at once, whatever the first skill's cooldown
        for (a in actives) if (a.has("getOverrideSkill")) {
            var r = a.fire("getOverrideSkill", []);
            var o = r == null ? null : instById(hero, str(r));
            if (o != null && o != a && time >= o.cdEnd) { pick = o; break; }
        }
        if (pick == null) for (a in actives) {
            var ready = usesCharges(a) ? a.charges > 0 && time >= a.cdEnd : time >= a.cdEnd;
            if (ready && a.has("checkEnabled")) {
                var r = a.fire("checkEnabled", []);
                if (r != null && str(r) != "Ok") ready = false;
            }
            if (ready && a.info.costs.length > 0 && !canPay(a)) ready = false;
            // a skill woven into the chain waits for its place (but not past the combo window: it would break the chain anyway)
            if (ready && a.weave >= 0 && chain.length > 0 && chainIndex % chain.length != a.weave) ready = false;
            if (ready) { pick = a; break; }
        }
        var dur:Float;
        if (pick != null) {
            // a skill with no duration in its data is instant in the game (an infusion's ultimate: 0.014 s in the dps meter's log)
            var d = pick.info.durationWith(pick.runes);
            dur = d > 0 ? Math.max(0.2, d * castMod) : 0.02;
            // a skill its script plays at once (shouldPlayInstantly: the mace's skill after a critical combo)
            if (pick.has("shouldPlayInstantly") && pick.fire("shouldPlayInstantly", []) == true) dur = 0.02;
            var cd = pick.info.cooldownWith(pick.runes) * cdMod;
            // a script that sets its own cooldown (the finisher during Urge to Kill: 1 s)
            if (pick.has("onCooldownEval")) { var r = pick.fire("onCooldownEval", [ctx, cd]); if (r != null) cd = num(r); }
            pick.cdEnd = time + cd;
            if (usesCharges(pick)) pick.charges--;
            pay(pick);
            castSkill(pick, dur);
        } else if (chain.length > 0) {
            // ent.Hero.getNextAttackSkill: the last attack ended more than ComboWindow ago -> the first attack again
            var window = GameRules.constant("ComboWindow");
            if (window > 0 && time - lastAttackEnd > window && chainIndex % chain.length != 0) chainIndex = 0;
            var a = chain[chainIndex % chain.length];
            chainIndex++;
            dur = a.info.duration > 0 ? a.info.duration : 0.5;
            castSkill(a, dur);
            lastAttackEnd = time + dur;
        } else dur = 0.5;
        busyUntil = time + dur;
        at(busyUntil, act);
    }

    function newCtx(inst:Inst):HitObj {
        var c = new HitObj();
        c.set("skill", inst);
        c.set("skillId", inst.info.id);
        c.set("kind", inst.info.id);
        c.set("owner", inst.owner);
        c.set("ownerUnit", inst.owner);
        c.set("aimTarget", dummy);
        c.set("target", dummy);
        c.set("isSkill", inst.isSkillHit());
        c.set("isWeaponSkill", inst.isWeaponSkill());
        c.set("isClassSkill", inst.isClassSkill());
        c.set("isSignature", inst.isSignature());
        c.set("isBaseAttack", inst.isAttack());
        c.set("isAttack", inst.isAttack());
        c.set("isFinalCombo", inst.info.type == "AttackCombo");
        c.set("isFinalAttack", inst.info.type == "AttackCombo");
        c.set("totalHits", 0);
        c.set("hitCount", 0);
        c.set("activeSkill", inst);
        return c;
    }

    /** A cast: script hooks, steps on Start now (with their delays), on CastEnd / Finish at the end. */
    public function castSkill(inst:Inst, dur:Float):Void {
        casts.set(inst.info.id, (casts.exists(inst.info.id) ? casts.get(inst.info.id) : 0) + 1);
        inst.runningUntil = time + dur;
        var c = newCtx(inst);
        ctx = c;
        dispatchUnit(hero, "onUseSkill", [c], null);
        inst.fire("onStart", [c]);
        // st.skill.Skill.start: BaseSkill.start (onStart), then tryConsumeCharge: onPreSkillProc first (the mage's spark is paid
        // there), then onProc and onSkillProc. The steps hit in the frames after: what these scripts put on the cast's context
        // (ctx.dmgMult += …) is there when they do
        dispatchUnit(hero, "onPreSkillProc", [c], null);
        inst.fire("onProc", [c]);
        dispatchUnit(hero, "onSkillProc", [c], null);
        for (s in inst.info.steps) if (inst.info.stepActive(s, inst.rank, inst.runes)) {
            if (s.on == "Start") runStep(inst, s, null, c);
            if (s.on == "CastEnd" || s.on == "Finish" || s.on == "StepEnd") { var st = s; at(time + dur, () -> runStep(inst, st, null, c)); }
        }
        // st.skill.Skill.doStop at the end of the cast: the skill's own onStop (a free strike's status taken off…)
        var st = inst;
        at(time + Math.max(0.01, dur), () -> st.fire("onStop", [c]));
        ctx = c;
    }

    /** One step of a skill: its effects on its targets (loops: every tick), statuses, then the steps that follow its hits. */
    /** `free`: the step was played by the script and lives on after its status ends (an area, a blast). */
    public function runStep(inst:Inst, s:SStep, target:Unit, c:Dynamic, free = false):Void {
        var delay = inst.info.value(s.delay, inst.rank, inst.runes, 0);
        if (delay > 0) { at(time + delay, () -> runStepNow(inst, s, target, c, free)); return; }
        runStepNow(inst, s, target, c, free);
    }

    function stepTargets(inst:Inst, s:SStep, target:Unit):Array<Unit> {
        // an area played at a unit is centred on it: with area.ignoreMainTarget it skips that unit (no other foe at a dummy)
        if (s.ignoreMain && (s.type == "Area" || s.type == "Aura")) return [];
        if (target != null) return [target];
        var self = inst.isStatus() ? (cast inst : Status).unit : inst.owner;
        if (s.type == "SelfEffect") return [self];
        var side = inst.isStatus() ? (cast inst : Status).instigator : inst.owner;
        var healing = false, damaging = false;
        for (e in s.effects) {
            if (e.kind == "Heal" || e.kind == "Shield") healing = true;
            if (e.kind == "Damage") damaging = true;
        }
        if (inst.isStatus() && s.type != "Area" && s.type != "Aura") return [self];
        // an area's filter (bits: 1 foes, 2 allies, 4 self)
        if (s.hitFilter != 0 && (s.hitFilter & 1) == 0) return [side.team == 0 ? hero : dummy];
        if (healing && !damaging) return [side.team == 0 ? hero : dummy];
        if (s.ignoreMain) return []; // an area around the target that skips it: no other foe at a dummy
        return [side.team == 0 ? dummy : hero];
    }

    /** A status step's own duration (Scepter_Flamie_S2: the flamie for dur2 seconds), null: the status's. */
    function stepStatusTime(inst:Inst, s:SStep):Null<Float> {
        var d = inst.info.value(s.duration, inst.rank, inst.runes, 0);
        return d > 0 ? d : null;
    }

    function runStepNow(inst:Inst, s:SStep, target:Unit, c:Dynamic, free = false):Void {
        if (!free && inst.isStatus() && (cast inst : Status).removed) return;
        if (inst.has("onStep")) {
            var so = new HitObj();
            so.set("kind", s.id);
            so.set("id", s.id);
            so.set("target", target);
            inst.fire("onStep", [so]);
        }
        var targets = stepTargets(inst, s, target);
        var tick = inst.info.value(s.tick, inst.rank, inst.runes, 0);
        var tickOverride = inst.stepTick.get(s.id);
        if (tickOverride != null && tickOverride > 0) tick = tickOverride;
        var dur = inst.info.value(s.duration, inst.rank, inst.runes, 0);
        if (dur < 0 && inst.isStatus()) dur = (cast inst : Status).endTime - time;
        // a loop of an infinite status ticks until the fight ends (it stops when the status goes)
        if (!Math.isFinite(dur)) dur = Math.max(0, length - time);
        // a script that follows the steps (Staff_SummonDemon_Skill1: the channel's ticks shoot, a shot counts itself): every
        // tick of a looping step, or the one start of the others, is an onStepTick of the step
        if (inst.has("onStepTick") && !off.exists("stepTick")) {
            var so = new HitObj();
            so.set("kind", s.id);
            so.set("id", s.id);
            so.set("target", target);
            if (tick > 0 && dur > 0) {
                var gen = inst.areaGen;
                for (k in 0...Std.int(Math.max(1, Math.floor(dur / tick)))) at(time + k * tick, () -> if (inst.areaGen == gen) inst.fire("onStepTick", [so]));
            } else inst.fire("onStepTick", [so]);
        }
        if (s.type == "Projectile") {
            // the projectile flies: its hit steps when it lands
            // ent.Projectile.onHit -> BaseSkill.onHit: the projectile's own hit on its target, then its hit steps
            var aim = target != null ? target : (inst.owner.team == 0 ? dummy : hero);
            at(time + 0.2, () -> {
                stepHit(inst, s, aim, c);
                for (n in inst.info.steps) if (n.on == "ProjectileHit" && inst.info.stepActive(n, inst.rank, inst.runes)) runStepNow(inst, n, null, c);
            });
            return;
        }
        if (s.status != "" && s.effects.length == 0) {
            for (t in (s.statusSelf ? [inst.owner] : targets)) applyStatus(t, s.status, inst, s.statusStacks, stepStatusTime(inst, s));
        }
        if (s.type == "Summon") { summon(inst, s, dur, c); return; }
        if (s.type == "SkillObject" && Lambda.exists(hero.skills, k -> k.info.scriptText.indexOf("getSkillObjects") >= 0)) {
            // a script of the hero takes such objects (Expulse grabs the water spheres): the sphere lies where it fell until it ends
            // (one the hero does not grab is walked through before it ends: the skill's Pickup steps run then)
            var obj = new SkillObj(this, time + Math.max(0.1, dur)), src = inst;
            inst.objects.push(obj);
            at(obj.until, () -> {
                if (obj.gone) return;
                obj.gone = true;
                for (n in src.info.steps) if (n.on == "Pickup" && src.info.stepActive(n, src.rank, src.runes)) runStepNow(src, n, hero, c, true);
            });
            return;
        }
        if (s.type == "SkillObject") {
            // a pickup object (a water orb): it lands, the hero takes it, the skill's Pickup steps run on the hero
            var src = inst;
            at(time + Math.max(0.1, s.travel), () -> {
                for (n in src.info.steps) if (n.on == "Pickup" && src.info.stepActive(n, src.rank, src.runes)) runStepNow(src, n, hero, c, true);
            });
            return;
        }
        // a lasting zone that tracks who is inside (area.detectPresence) tells its script
        if (s.type == "Area" && s.presence && (inst.has("onAreaEntered") || inst.has("onAreaElapsed") || inst.has("onAreaTick") || inst.has("onAreaExited"))) {
            var area = new HitObj();
            area.set("position", new DynObj());
            area.set("ctx", c);
            area.set("stepId", s.id);
            var foes = stepTargets(inst, s, null);
            for (u in foes) inst.fire("onAreaEntered", [area, u]);
            var length = dur > 0 ? dur : 0;
            if (tick > 0 && length > 0 && inst.has("onAreaTick")) for (k in 0...Std.int(length / tick)) at(time + k * tick, () -> inst.fire("onAreaTick", [area]));
            at(time + length, () -> {
                inst.fire("onAreaElapsed", [area, c]);
                for (u in foes) inst.fire("onAreaExited", [area, u]);
            });
        }
        if (s.effects.length == 0 && s.type != "Area" && s.type != "EffectTarget" && s.type != "Mono") return;
        // the loop of a status that lasts as long as the status (step duration -1) ticks for as long as the status is there, also
        // after it was refreshed (st.skill.SkillStep.applyTicks runs while the step runs); a pool of damage pays out over it
        if (tick > 0 && inst.isStatus() && !s.spread && s.effects.length > 0 && inst.info.maxStacks >= 1000000 && inst.info.value(s.duration, inst.rank, inst.runes, 0) < 0) {
            var st:Status = cast inst;
            var every = Math.max(tick, s.targetCd);
            var t0 = time;
            var gen = inst.areaGen;
            var tickAt:Int->Void = null;
            tickAt = function(k:Int):Void {
                if (inst.areaGen != gen || st.removed) return;
                if (k > 0 && (k + 1) * every > st.endTime - t0 + 1e-9) return;
                st.payFrac = Math.min(1, every / Math.max(every, st.endTime - time));
                var share = st.pool * st.payFrac;
                hitStep(inst, s, targets, c, 1, free);
                st.pool -= share;
                st.payFrac = -1;
                at(t0 + (k + 1) * every, () -> tickAt(k + 1));
            };
            at(time, () -> tickAt(0));
            return;
        }
        if (tick > 0 && dur > 0) {
            var n = Std.int(Math.max(1, Math.floor(dur / Math.max(tick, s.targetCd))));
            var every = Math.max(tick, s.targetCd);
            var gen = inst.areaGen;
            var area:AreaObj = null;
            if (s.type == "Area" && Std.isOfType(c, HitObj)) { area = new AreaObj(); (c : HitObj).set("areaObj", area); }
            for (k in 0...n) at(time + k * every, () -> if (inst.areaGen == gen && (area == null || !area.removed)) hitStep(inst, s, targets, c, s.spread ? n : 1, free));
            return;
        }
        hitStep(inst, s, targets, c, 1, free);
    }

    /**
     * st.skill.BaseSkill.canStartEventStep / checkAlignment: a step on Hit starts for a hit of another step whose target
     * fits its alignment (its cond.alignment, else the hitting step's filter; none: foes only). Bits: 1 foes, 2 allies, 4 self.
     */
    function hitAligned(inst:Inst, align:Int, t:Unit):Bool {
        if (t == null) return true;
        var src = inst.isStatus() ? (cast inst : Status).instigator : inst.owner;
        if (src == null) return true;
        if (align < 0) return t.team != src.team;
        if ((align & 1) != 0 && t.team != src.team) return true;
        if ((align & 2) != 0 && t.team == src.team && t != src) return true;
        if ((align & 4) != 0 && t == src) return true;
        return false;
    }

    /** Step types whose application is a hit on its target (st.skill.SkillStep.doApply calls hitEntity; areas, auras). */
    static var HIT_STEPS = ["EffectTarget", "SelfEffect", "Channel", "Area", "Aura", "Mono"];

    /** BaseSkill.onHit: the skill's own onHit, then onInflictHit of every skill and status of the attacker. */
    function stepHit(inst:Inst, s:SStep, t:Unit, c:Dynamic):Void {
        var attacker = inst.isStatus() ? (cast inst : Status).instigator : inst.owner;
        // BaseSkill.onHit: ctx.hitCount + 1; the first hit of the cast is onFirstHit
        if (Std.isOfType(c, HitObj)) {
            var n = num((c : HitObj).get("hitCount")) + 1;
            (c : HitObj).set("hitCount", n);
            (c : HitObj).set("totalHits", n);
        }
        var hit = newHit(inst, s, t, c, attacker);
        if (hit.get("isFirstHit") == true) inst.fire("onFirstHit", [hit]);
        inst.fire("onHit", [hit]);
        dispatchUnit(attacker, "onInflictHit", [hit], null); // the skill hears its own hits too (scripts check skillId == kind)
        // the first hit of a cast on a unit: onHitNewTarget (the skill) and onInflictHitNewTarget (the attacker's scripts)
        var isNew = true;
        if (Std.isOfType(c, HitObj)) {
            var ctx:HitObj = c;
            var seen:Array<Unit> = ctx.get("hitUnits");
            if (seen == null) { seen = []; ctx.set("hitUnits", seen); }
            if (seen.indexOf(t) >= 0) isNew = false else seen.push(t);
        }
        if (isNew && !off.exists("newTarget")) {
            inst.fire("onHitNewTarget", [hit]);
            dispatchUnit(attacker, "onInflictHitNewTarget", [hit], null);
        }
    }

    function hitStep(inst:Inst, s:SStep, targets:Array<Unit>, c:Dynamic, split:Int, free = false):Void {
        if (!free && inst.isStatus() && (cast inst : Status).removed) return;
        for (t in targets) {
            // st.skill.SkillStep.doApply / AreaStep.areaHit -> hitEntity -> BaseSkill.onHit: one hit per unit a step reaches
            // (before its effects), heard by the skill (onHit) and every script of the attacker (onInflictHit)
            if (t != null && HIT_STEPS.indexOf(s.type) >= 0) stepHit(inst, s, t, c);
            for (e in s.effects) applyEffect(inst, s, e, t, c, split);
            if (s.status != "" && s.effects.length > 0) applyStatus(s.statusSelf ? inst.owner : t, s.status, inst, s.statusStacks, stepStatusTime(inst, s));
            // steps that follow a hit of this one
            for (n in inst.info.steps) if (n.on == "Hit" && n != s && (n.condStep == "" || n.condStep == s.id) && inst.info.stepActive(n, inst.rank, inst.runes)
                && hitAligned(inst, n.alignment >= 0 ? n.alignment : (s.hitFilter != 0 ? s.hitFilter : -1), t))
                runStep(inst, n, t, c);
        }
    }

    // ---------------------------------------------------------------- effects

    /** The hit object scripts see (hit.skill, hit.target, hit.isSkill…) for one target of a step. */
    function newHit(inst:Inst, s:SStep, target:Unit, c:Dynamic, attacker:Unit):HitObj {
        var hit = new HitObj();
        hit.set("skill", inst);
        hit.set("skillId", inst.info.id);
        hit.set("kind", inst.info.id);
        hit.set("stepId", s.id);
        if (s.type == "Area" && Std.isOfType(c, HitObj) && (c : HitObj).get("areaObj") != null) hit.set("area", (c : HitObj).get("areaObj"));
        hit.set("step", s.id);
        hit.set("target", target);
        hit.set("targetUnit", target);
        hit.set("source", attacker);
        hit.set("sourceUnit", attacker);
        hit.set("instigator", attacker);
        hit.set("sourceObject", attacker);
        hit.set("ctx", c);
        hit.set("status", inst.isStatus() ? inst : null);
        hit.set("isSkill", inst.isSkillHit());
        hit.set("isWeaponSkill", inst.isWeaponSkill());
        hit.set("isClassSkill", inst.isClassSkill());
        hit.set("isSignature", inst.isSignature());
        hit.set("isBaseAttack", inst.isAttack());
        // BaseSkillAccess.get_isAttack: a base attack or the final combo attack
        hit.set("isAttack", inst.isAttack());
        hit.set("isFinalCombo", inst.info.type == "AttackCombo");
        hit.set("isFinalAttack", inst.info.type == "AttackCombo");
        // ScriptHitData.get_isFirstHit / get_hitCount: the cast's hits so far (BaseSkill.onHit counts them)
        var hc = Std.isOfType(c, HitObj) ? num((c : HitObj).get("hitCount")) : 1.0;
        hit.set("hitCount", hc);
        hit.set("isFirstHit", hc <= 1);
        return hit;
    }

    /** Damage, heal, shield or status of one effect on one target, through every script that changes or reacts to it. */
    public function applyEffect(inst:Inst, s:SStep, e:SEffect, target:Unit, c:Dynamic, split:Int):Bool {
        if (e.kind == "Status") {
            if (e.status != "") applyStatus(target, e.status, inst, 1);
            return true;
        }
        if (e.status != "" && target != null) applyStatus(target, e.status, inst, 1);
        if (e.kind != "Damage" && e.kind != "Heal" && e.kind != "Shield") return false;
        var attacker = inst.isStatus() ? (cast inst : Status).instigator : inst.owner;
        var stats = statsNow();
        var base = env.effectBase(inst, e, stats);
        if (e.dynVal > 0 && e.scaling.length == 0 && base == 0) base = inst.dyn[e.dynVal];
        // a status with no stack limit holds an amount (Warrior_Hemorrhage_Status): a tick pays its share of the pool
        var pooled = false;
        if (inst.isStatus() && inst.info.maxStacks >= 1000000) {
            var ps:Status = cast inst;
            if (ps.payFrac >= 0) { base *= ps.pool * ps.payFrac; pooled = true; }
            else base *= ps.stacks;
        }
        base /= split;
        var hit = newHit(inst, s, target, c, attacker);
        if (inst.proxy != null) hit.set("instigatorUnit", inst.proxy);
        hit.set("isMagic", Affinity.isMagic(e.affinity));
        hit.set("isPhysical", e.physical);
        hit.set("isDoT", inst.isStatus() && inst.info.dotHot);
        var dot = inst.isStatus() && inst.info.dotHot;
        hit.set("critChance", dot ? 0.0 : stats.get("CritChance"));
        hit.set("critDmgMult", stats.get("CritDamage"));
        // what the scripts put on the context of the cast (ctx.dmgMult += … in onUseSkill, onStart, onProc, onSkillProc) or of a step the
        // script played (playStep returns it: ctx.dmgMult = …): the multipliers of the damage, its kind, the heal, the crit chance. Only
        // for the skill's own hits: a status started during the cast has its own context in the game
        var stepMult = 1.0, ctxCrit = 0.0;
        if (Std.isOfType(c, HitObj) && (c : HitObj).get("skill") == inst) {
            var co:HitObj = c;
            stepMult = num(co.get("dmgMult"));
            if (e.kind == "Damage") {
                if (e.physical) stepMult *= num(co.get("physicalDmgMult"));
                else if (Affinity.isMagic(e.affinity)) stepMult *= num(co.get("magicDmgMult"));
            } else if (e.kind == "Heal") stepMult *= num(co.get("healMult"));
            ctxCrit = num(co.get("critChance"));
        }
        hit.set("dmgMult", stepMult);
        if (ctxCrit != 0 && !dot) hit.set("critChance", num(hit.get("critChance")) + ctxCrit);
        var heal = e.kind != "Damage";
        if (!heal && inst.proxy != null) {
            // a summon's hit: its own skill hears it, the owner's skills hear it as a proxy damage
            inst.fire("onDamageEval", [hit]);
            dispatchUnit(attacker, "onProxyDamageEval", [hit], null);
        } else if (!heal) {
            inst.fire("onDamageEval", [hit]);
            dispatchUnit(attacker, "onInflictDamageEval", [hit], null); // the skill hears its own hits too (scripts check skillId == kind)
            dispatchUnit(target, "onReceiveDamageEval", [hit], null);
        } else {
            inst.fire("onHealEval", [hit]);
            dispatchUnit(attacker, "onInflictHealEval", [hit], null); // the skill hears its own hits too (scripts check skillId == kind)
            dispatchUnit(target, "onReceiveHealEval", [hit], null);
        }
        var ccHit = num(hit.get("critChance")), cdHit = num(hit.get("critDmgMult"));
        var critical = chance("crit|" + inst.info.id, ccHit);
        hit.set("critical", critical);
        var amount = base + num(hit.get("dmgAdd"));
        if (!heal) {
            var ratio = (1 + stats.get(e.physical ? "PhysicalMastery" : "MagicMastery") + stats.get("Fervor")) * stats.get("DamageModifier");
            var pen = Math.min(1, Math.max(0, stats.get(e.physical ? "ArmorPenetration" : "SpellPenetration")));
            var ignore = Math.min(1, num(hit.get(e.physical ? "armorIgnore" : "magicArmorIgnore")));
            var def = env.targetDefense(e.physical, targetBuffSets[targetBuffs(target)]);
            var armor = def[0] * (1 - pen) * (1 - ignore);
            amount *= Math.max(0, ratio) * Math.max(0, num(hit.get("dmgMult"))) * (critical ? num(hit.get("critDmgMult")) : 1) * (1 - env.armorReduction(armor))
                * def[1];
        } else if (e.kind == "Heal") {
            amount *= stats.get("HealGivenMultiplier") * Math.max(0, num(hit.get("dmgMult"))) * (critical ? num(hit.get("critDmgMult")) : 1);
        } else amount *= stats.get("ShieldPowerMultiplier");
        amount = Math.max(0, amount);
        hit.set("amount", amount);
        // the log keeps the expected value (critical hits by their chance), as the replay counts it
        var critOk = !dot && e.kind != "Shield";
        var expected = critical ? amount / Math.max(1e-9, cdHit) : amount;
        if (critOk) expected *= 1 + Math.min(1, Math.max(0, ccHit)) * Math.max(0, cdHit - 1);
        if (!heal || target == hero)
            log.push({inst: inst, e: e, split: split, add: num(hit.get("dmgAdd")), mult: Math.max(0, num(hit.get("dmgMult"))),
                ccAdd: ccHit - stats.get("CritChance"), cdAdd: cdHit - stats.get("CritDamage"), crit: critOk,
                ignore: Math.min(1, num(hit.get(e.physical ? "armorIgnore" : "magicArmorIgnore"))), kind: e.kind == "Damage" ? 0 : (e.kind == "Heal" ? 1 : 2),
                self: target == hero, ally: s.type != "SelfEffect" && (s.hitFilter == 0 || (s.hitFilter & 2) != 0),
                buffs: buffIndex, tbuffs: heal ? 0 : targetBuffs(target), dyn: pooled || (e.dynVal > 0 && e.scaling.length == 0), amount: expected});
        var id = inst.info.id;
        if (!heal) damage.set(id, (damage.exists(id) ? damage.get(id) : 0) + amount);
        else if (target == hero && e.kind == "Shield") {
            // a shield: held until damage comes (absorb); its log line starts at 0 and grows with what it takes
            var rec = log.length > 0 ? log[log.length - 1] : null;
            if (rec != null && rec.inst == inst && rec.e == e) rec.amount = 0 else rec = null;
            var link:Inst = e.status != "" ? findStatus(target, e.status, null) : (inst.isStatus() ? inst : null);
            addShieldPool(id, amount, rec, link, s.type != "SelfEffect" && (s.hitFilter == 0 || (s.hitFilter & 2) != 0));
        } else if (target == hero) {
            this.heal.set(id, (this.heal.exists(id) ? this.heal.get(id) : 0) + amount);
            // a heal that is not only for the hero reaches an ally next to the hero as well (area filter bit 2, or no filter)
            if (s.type != "SelfEffect" && (s.hitFilter == 0 || (s.hitFilter & 2) != 0)) allyHealed += amount;
        }
        if (!heal && inst.proxy != null) {
            inst.fire("onDamage", [hit]);
            dispatchUnit(attacker, "onProxyDamage", [hit], null);
        } else if (!heal) {
            inst.fire("onDamage", [hit]);
            dispatchUnit(attacker, "onInflictDamage", [hit], null); // the skill hears its own hits too (scripts check skillId == kind)
            dispatchUnit(target, "onReceiveDamage", [hit], null);
        } else {
            dispatchUnit(attacker, "onInflictHeal", [hit], null); // the skill hears its own hits too (scripts check skillId == kind)
        }
        return true;
    }

    // ---------------------------------------------------------------- statuses

    public function findStatus(u:Unit, id:String, instigator:Unit):Status {
        for (s in u.statuses) if (!s.removed && s.info.id == id && (instigator == null || s.instigator == instigator)) return s;
        return null;
    }

    public function applyStatus(target:Unit, id:String, source:Inst, stacks:Int, ?duration:Float):Status {
        if (target == null || id == "") return null;
        var info = env.skill(id);
        if (Sys.getEnv("TRACE") != null && id.indexOf(Sys.getEnv("TRACE")) >= 0) Sys.println("TRACE status " + id + " t=" + Math.round(time * 10) / 10);
        if (info == null) { missing("status data " + id); return null; }
        var instigator = source != null ? (source.isStatus() ? (cast source : Status).instigator : source.owner) : hero;
        // the instigator's scripts see the status about to be added (the rogue's poison: added again, it blasts)
        var tryObj = new HitObj();
        tryObj.set("id", id);
        tryObj.set("kind", id);
        dispatchUnit(instigator, "onTryAddStatus", [tryObj, target], null);
        var dur = duration != null && duration > 0 ? duration : info.durationWith(source != null ? source.runes : []);
        // st.skill.Status.stacksWith: the same status stacks on one that is just as lasting (infinite or not), of the same
        // instigator unless its flags share it (2048); a lasting and an infinite one live side by side
        var s:Status = null;
        for (o in target.statuses) if (!o.removed && o.info.id == id && ((info.flags & 2048) != 0
            || ((dur > 0) == (o.endTime != Math.POSITIVE_INFINITY) && o.instigator == instigator))) { s = o; break; }
        var fresh = s == null;
        if (fresh) {
            s = new Status(this, info, source, target, instigator);
            s.stacks = Std.int(Math.max(1, Math.min(info.maxStacks, stacks)));
            s.start = time;
            target.statuses.push(s);
        } else s.stacks = Std.int(Math.min(info.maxStacks, s.stacks + Math.max(1, stacks)));
        if (info.maxStacks >= 1000000) s.pool += Math.max(1, stacks);
        s.endTime = dur > 0 ? time + dur : Math.POSITIVE_INFINITY;
        if (target == hero) statsDirty = true;
        var st = s;
        if (fresh) {
            s.fire("onStart", []);
            for (step in info.steps) if (info.stepActive(step, s.rank, s.runes) && (step.on == "Start" || step.on == "Refresh")) runStep(s, step, target, ctx);
            if (dur > 0) {
                var end = s.endTime;
                at(end, () -> if (!st.removed && st.endTime <= time + 1e-9) removeStatus(st) else if (!st.removed) at(st.endTime, () -> if (!st.removed && st.endTime <= time + 1e-9) removeStatus(st)));
            }
        } else {
            for (step in info.steps) if (info.stepActive(step, s.rank, s.runes) && step.on == "Refresh") runStep(s, step, target, ctx);
            s.fire("onStacksChange", [s.stacks]);
        }
        dispatchUnit(instigator, "onInflictStatus", [s], null);
        dispatchUnit(instigator, "onInflictStatusEval", [statusEval(s, target)], null);
        if (target != instigator) dispatchUnit(target, "onReceiveStatus", [s], null);
        return s;
    }

    public function refreshSteps(s:Status):Void {
        if (s.removed) return;
        for (step in s.info.steps) if (s.info.stepActive(step, s.rank, s.runes) && step.on == "Refresh") runStep(s, step, s.unit, ctx);
    }

    function statusEval(s:Status, target:Unit):HitObj {
        var o = new HitObj();
        o.set("status", s);
        o.set("target", target);
        o.set("kind", s.info.id);
        return o;
    }

    public function removeStatus(s:Status):Void {
        if (s.removed) return;
        s.removed = true;
        s.unit.statuses.remove(s);
        if (s.unit == hero && shields.length > 0) shields = [for (x in shields) if (x.link != s) x];
        if (s.unit == hero) statsDirty = true;
        s.fire("onStop", []);
        dispatchUnit(s.instigator, "onStatusEnd", [s, time - s.start], null);
        if (s.unit != s.instigator) dispatchUnit(s.unit, "onStatusEnd", [s, time - s.start], null);
    }

    // ---------------------------------------------------------------- script events

    /** Calls `fn` on every skill of the unit and every status on it (except `skip`). */
    /** Seconds between the 1-damage hits the hero takes (see run). */
    public static var INCOMING_EVERY = 1.0;

    /** A plain hit `target` takes from `source` (not a skill of the build: it adds no damage or heal of its own). */
    function receiveHit(target:Unit, source:Unit, amount:Float):Void {
        if (target == hero) absorb(amount);
        var hit = new HitObj();
        hit.set("target", target);
        hit.set("targetUnit", target);
        hit.set("source", source);
        hit.set("sourceUnit", source);
        hit.set("instigator", source);
        hit.set("amount", amount);
        hit.set("dmgMult", 1.0);
        hit.set("isPhysical", true);
        hit.set("isMagic", false);
        hit.set("isFirstHit", true);
        hit.set("critical", false);
        hit.set("skillId", "");
        hit.set("kind", "");
        dispatchUnit(target, "onReceiveDamageEval", [hit], null);
        dispatchUnit(source, "onInflictDamage", [hit], null);
        dispatchUnit(target, "onReceiveDamage", [hit], null);
    }

    public function dispatchUnit(u:Unit, fn:String, args:Array<Dynamic>, skip:Inst):Void {
        if (u == null) return;
        for (s in u.skills) if (s != skip && s.has(fn)) s.fire(fn, args);
        for (s in u.statuses.copy()) if (s != skip && !s.removed && s.has(fn)) s.fire(fn, args);
    }

    function dispatchAll(fn:String, args:Array<Dynamic>):Void {
        for (u in units) dispatchUnit(u, fn, args, null);
    }

    public function instById(u:Unit, id:String):Inst {
        for (s in u.skills) if (s.info.id == id) return s;
        return null;
    }

    // ---------------------------------------------------------------- the game functions scripts call

    public function api(inst:Inst, name:String, a:Array<Dynamic>):Dynamic {
        inline function unitArg(i:Int):Unit return Std.isOfType(a[i], Unit) ? a[i] : (Std.isOfType(a[i], Status) ? (a[i] : Status).unit : null);
        switch (name) {
            case "checkProba": return chance("proba|" + inst.info.id, num(a[0]));
            // a random value: its mean (no luck either)
            case "random": return a.length >= 2 ? (num(a[0]) + num(a[1])) / 2 : num(a[0]) / 2;
            case "pickRandom": var arr:Array<Dynamic> = a[0]; return arr == null || arr.length == 0 ? null : arr[Std.int(rand() * arr.length)];
            case "round": return Math.round(num(a[0]));
            case "addStatus", "tryAddStatus":
                // script.SkillScript.addStatus(unit, status, ?stacks, ?skill): the third argument is the stacks (rounded)
                var n = a.length > 2 && a[2] != null ? Std.int(Math.max(1, Math.round(num(a[2])))) : 1;
                return applyStatus(unitArg(0), str(a[1]), inst, n);
            case "removeStatuses":
                var u = unitArg(0);
                var f:Closure = Std.isOfType(a[1], Closure) ? a[1] : null;
                if (u != null && f != null) for (st in u.statuses.copy()) if (!st.removed && f.run([st]) == true) removeStatus(st);
                return null;
            case "removeStatus":
                var u = unitArg(0);
                if (u != null) { var s = findStatus(u, str(a[1]), null); if (s != null) removeStatus(s); }
                return null;
            case "hasStatus": var u = unitArg(0); return u != null && findStatus(u, str(a[1]), null) != null;
            case "getStatusCount": var u = unitArg(0); var s = u == null ? null : findStatus(u, str(a[1]), null); return s == null ? 0 : s.stacks;
            case "hasStatusMaxStacked": var u = unitArg(0); var s = u == null ? null : findStatus(u, str(a[1]), null); return s != null && s.stacks >= s.info.maxStacks;
            case "consumeStatus":
                var u = unitArg(0);
                var s = u == null ? null : findStatus(u, str(a[1]), null);
                if (s == null) return 0;
                var n = a.length > 2 && a[2] != null ? Std.int(num(a[2])) : s.stacks;
                var used = Std.int(Math.min(n, s.stacks));
                s.stacks -= used;
                if (s.stacks <= 0) removeStatus(s);
                dispatchUnit(s.instigator, "onStatusConsumed", [s, used], null);
                return used;
            case "addStatusDuration", "extendStatusDuration":
                var u = unitArg(0);
                var s = u == null ? null : findStatus(u, str(a[1]), null);
                if (s != null) s.endTime += num(a[2]);
                return null;
            case "enforceStatus":
                var u = unitArg(0);
                var s = u == null ? null : findStatus(u, str(a[1]), null);
                if (a[2] == true && s == null) applyStatus(u, str(a[1]), inst, 1);
                if (a[2] != true && s != null) removeStatus(s);
                return null;
            case "getInflictedStatuses":
                return [for (u in units) for (s in u.statuses) if (s.instigator == inst.owner && s.info.id == str(a[0])) s];
            case "playStep", "playGlobalStep":
                var s = inst.info.step(str(a[0]));
                if (s == null) {
                    // a global step (props.stepGlobal.globalId) of one of the hero's skills
                    var g = globalStep(str(a[0]));
                    if (g == null) { missing("step " + inst.info.id + "." + str(a[0])); return null; }
                    var gsc = new HitObj();
                    gsc.set("skill", g.inst);
                    gsc.set("aimTarget", dummy);
                    gsc.set("target", dummy);
                    var gi = g.inst, gs = g.step, gt = unitArg(1);
                    at(time, () -> runStep(gi, gs, gt, gsc, true));
                    return gsc;
                }
                // the step runs right after the script (which may still set its context)
                var sc = new HitObj();
                sc.set("stepMult", true);
                sc.set("dmgMult", 1.0);
                sc.set("skill", inst);
                sc.set("aimTarget", dummy);
                sc.set("target", dummy);
                var target = unitArg(1);
                var src = inst;
                at(time, () -> runStep(src, s, target, sc, true));
                return sc;
            case "playAreaStepFromPt":
                // script.SkillScript.playAreaStepFromPt(step, from, ctx, to): the area flies from `from` and lands at `to`
                // (area.travelTime later); the points scripts pass are units' positions, at a dummy: the target's
                var s = inst.info.step(str(a[0]));
                if (s == null) { missing("step " + inst.info.id + "." + str(a[0])); return null; }
                var sc = new HitObj();
                sc.set("stepMult", true);
                sc.set("dmgMult", 1.0);
                sc.set("skill", inst);
                sc.set("aimTarget", dummy);
                sc.set("target", dummy);
                var src = inst;
                at(time + Math.max(0, s.travel), () -> runStep(src, s, null, sc, true));
                return sc;
            case "setStatus":
                var u = unitArg(0);
                if (u == null) return null;
                // script.SkillScript.setStatus(unit, status, ?stacks): without the count it is one (the Chaincast talent, Heartsteel)
                var n = a.length > 2 && a[2] != null ? Std.int(num(a[2])) : 1;
                var s = findStatus(u, str(a[1]), null);
                if (n <= 0) { if (s != null) removeStatus(s); return null; }
                if (s == null) s = applyStatus(u, str(a[1]), inst, 1);
                if (s != null) s.stacks = Std.int(Math.min(n, s.info.maxStacks > 1 ? s.info.maxStacks : n));
                if (u == hero) statsDirty = true;
                return s;
            case "chainStep":
                var s = inst.info.step(str(a[0]));
                if (s == null) return null;
                // script.SkillScript.chainStep(step, units, mainTarget, pos, range, count, delay, filter): the main target
                // at once, then up to round(count) of the units other than the skill's owner, lowest health first, `delay` apart
                var list:Array<Dynamic> = Std.isOfType(a[1], Array) ? a[1] : [];
                var count = a.length > 5 ? Math.round(num(a[5])) : 1;
                var delay = a.length > 6 ? num(a[6]) : 0;
                var main = unitArg(2);
                if (main != null) runStep(inst, s, main, ctx);
                var others:Array<Unit> = [for (u in list) if (Std.isOfType(u, Unit) && (u : Unit) != inst.owner) (u : Unit)];
                others.sort((x, y) -> x.healthRatio < y.healthRatio ? -1 : (x.healthRatio > y.healthRatio ? 1 : 0));
                var src = inst, c0 = ctx;
                for (k in 0...Std.int(Math.min(count, others.length))) {
                    var u = others[k];
                    at(time + k * delay, () -> runStep(src, s, u, c0));
                }
                return null;
            case "localPlayStep", "trace", "setChallenge", "p3DAdd", "p3DDist": return null;
            case "wait", "delay":
                var f:Closure = Std.isOfType(a[1], Closure) ? a[1] : null;
                if (f != null) { var src = inst, gen = inst.waitGen; at(time + num(a[0]), () -> if (src.waitGen == gen) { current = src; f.run([]); }); }
                return null;
            case "stopAreas":
                // script.SkillScript.stopAreas(unit, skill): the lasting areas of that skill end
                var t = a.length > 1 && a[1] != null ? instById(hero, str(a[1])) : inst;
                if (t != null) t.areaGen++;
                return null;
            case "cancelWaits": inst.waitGen++; return null;
            case "reduceCooldown":
                var target = a[0] == null ? inst : instById(hero, str(a[0]));
                if (target != null) target.cdEnd -= num(a[1]);
                return null;
            case "reduceWeaponsCooldown":
                for (s in hero.skills) if (s.info.type == "WeaponSkill") s.cdEnd -= num(a[0]);
                return null;
            case "resetCooldown":
                var target = a.length > 0 && a[0] != null ? instById(hero, str(a[0])) : inst;
                if (target != null) target.cdEnd = time;
                return null;
            case "consumeCooldown": inst.cdEnd = time + inst.info.cooldownWith(inst.runes); return null;
            case "isInCooldown": return time < inst.cdEnd;
            case "isSkillInCooldown": var t = instById(hero, str(a[0])); return t != null && time < t.cdEnd;
            case "setDynVal": inst.dyn[Std.int(num(a[0]))] = num(a[1]); if (inst.isStatus()) statsDirty = true; return null;
            case "addDynVal": inst.dyn[Std.int(num(a[0]))] += num(a[1]); if (inst.isStatus()) statsDirty = true; return null;
            case "getDynVal": return inst.dyn[Std.int(num(a[0]))];
            case "stop": if (inst.isStatus()) removeStatus(cast inst); return null;
            case "startSkill", "startSkillAtPosition":
                var info = env.skill(str(a[0]));
                if (info == null) return null;
                var free = new Inst(this, info, inst.rank, inst.runes, "triggered", inst.slot, inst.item, hero);
                castSkill(free, 0);
                return ctx;
            case "chargePrayer", "addCharges":
                var cap = inst.info.type == "PriestPrayer" ? Std.int(Math.max(1, inst.maxCharges)) : 99;
                inst.charges = Std.int(Math.min(cap, inst.charges + (name == "addCharges" ? Math.max(1, num(a[0])) : 1)));
                dispatchUnit(hero, "onPrayerCharged", [inst], null);
                return null;
            case "getAllyUnitsWithinRange", "getAllies": return [hero];
            case "getEnemiesInRange", "getEnemies": return [dummy];
            case "isHittable": return true;
            case "isAlly": var u = unitArg(0); return u != null && u.team == inst.owner.team;
            case "isEnemy": var u = unitArg(0); return u != null && u.team != inst.owner.team;
            case "applyHeal":
                var amount = num(a[1]) * statsNow().get("HealGivenMultiplier");
                if (unitArg(0) == hero) {
                    heal.set(inst.info.id, (heal.exists(inst.info.id) ? heal.get(inst.info.id) : 0) + amount);
                    log.push({inst: inst, e: null, split: 1, add: num(a[1]), mult: 1, ccAdd: 0, cdAdd: 0, crit: false, ignore: 0, kind: 1, self: true,
                        ally: false, buffs: buffIndex, tbuffs: 0, dyn: false, amount: amount});
                }
                return null;
            case "getSummons", "getTotems": var of = a.length > 0 && a[0] != null ? str(a[0]) : null; return [for (u in units) if (u.summonOf != "" && (of == null || u.summonOf == of)) u];
            case "getAreas", "getProjectiles": return [];
            case "getStepById":
                var o = new StepObj(inst, str(a[0]));
                return o;
            case "isInCombat": return true;
            case "hasSkill": return instById(hero, str(a[0])) != null;
            case "hasMastery": return inst.runes.indexOf(str(a[0])) >= 0;
            case "onPlayerAllies":
                var f:Closure = Std.isOfType(a[0], Closure) ? a[0] : null;
                if (f != null) f.run([hero]);
                return null;
            case "isSkillFromPrayer": return Std.isOfType(a[0], Inst) && (a[0] : Inst).info.type == "PriestPrayer";
            case "isCrowdControl":
                // a status about to be added (onTryAddStatus) or a status: one of its types is a crowd control (Data.statusType flags)
                var ci:SkillInfo = Std.isOfType(a[0], HitObj) ? env.skill(str((a[0] : HitObj).get("id"))) : (Std.isOfType(a[0], Inst) ? (a[0] : Inst).info : null);
                return ci != null && GameRules.typesFlag(ci.statusTypes, 2);
            case "getAtb": return a.length > 1 ? atbValue(unitArg(0), str(a[1])) : atbValue(hero, str(a[0]));
            // ---- resources (ent.Unit.addResource; Attribute.X are names)
            case "addAtb": resAdd(unitArg(0), str(a[1]), num(a[2])); return null;
            case "setAtb":
                var u = unitArg(0), id = str(a[1]);
                if (id == "Health" && u != null) u.healthRatio = Math.max(0, Math.min(1, num(a[2]) / Math.max(1, atbValue(u, "MaxHealth"))));
                else resSet(u, id, num(a[2]));
                return null;
            case "addResource": resAdd(inst.owner, str(a[0]), num(a[1])); return null;
            case "getResource": return atbValue(inst.owner, str(a[0]));
            case "payLife":
                var mh = Math.max(1, timingStat("MaxHealth"));
                hero.healthRatio = Math.max(0.01, hero.healthRatio - num(a[0]) / mh);
                return null;
            // ---- a cast's own values (setCustom(ctx, v) keeps v under the calling skill; getCustom(ctx, skill) reads it)
            case "setCustom":
                if (Std.isOfType(a[0], DynObj)) (a[0] : DynObj).set("custom:" + inst.info.id, a[1]);
                return null;
            case "getCustom":
                return Std.isOfType(a[0], DynObj) ? (a[0] : DynObj).get("custom:" + str(a[1])) : null;
            // ---- statuses
            case "hasStatusApplied": var u = unitArg(0); return u != null && findStatus(u, str(a[1]), null) != null;
            case "enforceStatusCount":
                var u = unitArg(0);
                if (u == null) return null;
                var n = Std.int(num(a[2]));
                var s = findStatus(u, str(a[1]), null);
                if (n <= 0) { if (s != null) removeStatus(s); return null; }
                if (s == null) s = applyStatus(u, str(a[1]), inst, n);
                if (s != null) s.stacks = n;
                if (u == hero) statsDirty = true;
                return null;
            case "extendDuration":
                if (inst.isStatus()) (cast inst : Status).endTime += num(a[0]);
                return null;
            case "addShield":
                // a shield status with an amount: counted as a shield on the hero
                var u = unitArg(0);
                if (u == null) return null;
                var st = applyStatus(u, str(a[1]), inst, 1);
                if (u == hero) addShieldPool(inst.info.id, num(a[2]) * statsNow().get("ShieldPowerMultiplier"), null, st, false);
                return null;
            case "haveShield": var u = unitArg(0); return u != null && findStatus(u, str(a[1]), null) != null;
            case "getStatus": var u = unitArg(0); return u == null ? null : findStatus(u, str(a[1]), Std.isOfType(a[2], Unit) ? a[2] : null);
            // ---- skills of the hero
            case "hasStatusType":
                var u = unitArg(0), t = str(a[1]);
                return u != null && Lambda.exists(u.statuses, st -> !st.removed && GameRules.isType(st.info.statusTypes, t));
            case "canDoMagicDamage":
                // the skill has a magic damage effect
                var sk:Inst = Std.isOfType(a[0], Inst) ? a[0] : null;
                return sk != null && Lambda.exists(sk.info.steps, st -> Lambda.exists(st.effects, e -> e.kind == "Damage" && Affinity.isMagic(e.affinity)));
            case "hasGlobalMastery":
                var id = str(a[0]);
                return Lambda.exists(hero.skills, s -> s.runes.indexOf(id) >= 0);
            case "getSkill": return instById(hero, str(a[0]));
            case "getSkillRank": var t = instById(hero, str(a[0])); return t == null ? 0 : t.rank;
            case "forAllWeaponSkills", "forAllClassSkills":
                var f:Closure = Std.isOfType(a[1], Closure) ? a[1] : (Std.isOfType(a[0], Closure) ? a[0] : null);
                if (f != null) for (s in hero.skills.copy()) if (name == "forAllWeaponSkills" ? s.isWeaponSkill() : s.isClassSkill()) f.run([s]);
                return null;
            case "getSkillInstanceIndex":
                var i = 0;
                for (s in hero.skills) { if (s == inst) return i; if (s.info.id == inst.info.id) i++; }
                return 0;
            case "getSkillInstanceCount": return Lambda.count(hero.skills, s -> s.info.id == inst.info.id);
            case "getActiveSkill":
                var o = new DynObj();
                o.set("aimTarget", dummy);
                return o;
            // ---- units around (one dummy; the hero's side at one place)
            case "getPartyHeroesWithinRange": return [hero];
            case "countEnemiesInRange": return targetDistance <= num(a[a.length - 1]) ? 1 : 0;
            case "isInRange": return true;
            case "sortByDistance": return a[0];
            case "destroyProjectiles", "extendSummonDuration", "setCooldownProgress": return null;
            case "isCrowdControlled", "isCCImmune": return false;
            // ---- maths and time
            case "clamp": return Math.max(num(a[1]), Math.min(num(a[2]), num(a[0])));
            case "ceil": return Math.ceil(num(a[0]));
            case "floor": return Math.floor(num(a[0]));
            case "abs": return Math.abs(num(a[0]));
            case "min": return Math.min(num(a[0]), num(a[1]));
            case "max": return Math.max(num(a[0]), num(a[1]));
            case "nextFrame":
                var f:Closure = Std.isOfType(a[0], Closure) ? a[0] : null;
                if (f != null) { var src = inst; at(time + 1 / 60, () -> { current = src; f.run([]); }); }
                return null;
            case "getPointsAround": return [];
            case "getFanFacingPos", "p2DTo3D", "p2DSub", "p2DAdd": return new DynObj();
            default:
                missing("api " + name);
                return null;
        }
    }
}

/** A step as scripts see it (getStepById): its tick interval can be changed. */
class StepObj implements IObj {
    var inst:Inst;
    var id:String;
    public function new(inst:Inst, id:String) {
        this.inst = inst;
        this.id = id;
    }
    public function get(name:String):Dynamic {
        if (name == "tickInterval") { var v = inst.stepTick.get(id); return v == null ? 0.0 : v; }
        return null;
    }
    public function set(name:String, v:Dynamic):Void {
        if (name == "tickInterval") inst.stepTick.set(id, Sim.num(v));
    }
    public function call(name:String, a:Array<Dynamic>):Dynamic {
        switch (name) {
            case "generateProjectile":
                // the step's projectile, flying at the target: its hit and its ProjectileHit steps
                var s = inst.info.step(id);
                if (s != null) inst.sim.fireProjectile(inst, s, Std.isOfType(a[0], Unit) ? a[0] : null);
                return null;
            case "getProjectileStart": return new DynObj();
            case "isRunning": return false;
            default: return null;
        }
    }
}

/** A skill's script as another script calls it (`s.script.onInflictDamage(dmg)`). */
class ScriptRef implements IObj {
    var inst:Inst;
    public function new(inst:Inst) this.inst = inst;
    public function get(name:String):Dynamic return null;
    public function set(name:String, v:Dynamic):Void {}
    public function call(name:String, a:Array<Dynamic>):Dynamic return inst.fire(name, a);
}

/** A class component the simulation does not model: what scripts ask of it is reported as missing. */
class UnknownComponent implements IObj {
    var sim:Sim;
    var name:String;
    public function new(sim:Sim, name:String) { this.sim = sim; this.name = name; }
    public function get(f:String):Dynamic { sim.missing(name + "." + f); return null; }
    public function set(f:String, v:Dynamic):Void sim.missing(name + ".set " + f);
    public function call(f:String, a:Array<Dynamic>):Dynamic { sim.missing(name + "." + f + "()"); return null; }
}

/**
 * The mage's class component (ent.hero.MageComponent): its conduits (the hero's MageConduit skills, as many as its
 * level unlocks: Mage_Conduit_Levels) trigger when spark is spent while the spark was above the bound of their
 * place (Mage_Conduit_SparkBounds, a share of MaxSpark); a chain cast is told to every script.
 */
class MageObj implements IObj {
    var sim:Sim;
    public function new(sim:Sim) this.sim = sim;
    public function get(name:String):Dynamic return null;
    public function set(name:String, v:Dynamic):Void {}

    function conduits():Array<Inst> {
        var level = sim.env.heroLevel(), n = 0;
        for (l in GameRules.constantList("Mage_Conduit_Levels")) if (l <= level) n++;
        var all = [for (s in sim.hero.skills) if (s.info.type == "MageConduit") s];
        return all.slice(0, n);
    }

    /** MageComponent.getConduitIndex: the last place whose bound the spark (share of the maximum) is above, -1 none. */
    function conduitIndex(spark:Float, count:Int):Int {
        var max = sim.timingStat("MaxSpark");
        var ratio = max > 0 ? spark / max : 0;
        var bounds = GameRules.constantList("Mage_Conduit_SparkBounds");
        var idx = -1;
        for (i in 0...count) if (i < bounds.length && bounds[i] < ratio) idx = i;
        return idx;
    }

    /** MageComponent.onConsumeResource: spending spark triggers the conduits the spark before allowed. */
    public function onConsumeResource(atb:String, before:Float):Void {
        if (atb == "Spark") trigger(false, before);
    }

    /** MageComponent.triggerAllConduits: onStartConduit of each, then onConduitTriggers(list) of every script of the hero. */
    public function trigger(force:Bool, spark:Float):Void {
        var all = conduits();
        var idx = force ? all.length - 1 : conduitIndex(spark, all.length);
        var list = [for (i in 0...all.length) if (i <= idx) all[i]];
        if (list.length == 0) return;
        for (c in list) {
            sim.casts.set(c.info.id, (sim.casts.exists(c.info.id) ? sim.casts.get(c.info.id) : 0) + 1);
            c.fire("onStartConduit", []);
        }
        sim.dispatchUnit(sim.hero, "onConduitTriggers", [list], null);
    }

    public function call(name:String, a:Array<Dynamic>):Dynamic {
        switch (name) {
            case "forceTriggerAllConduits", "triggerAllConduits":
                sim.later(Sim.num(a[0]), () -> trigger(true, 0));
                return null;
            case "propagateMageChainCast":
                sim.dispatchUnit(sim.hero, "onMageChainCast", [a[0]], null);
                return null;
            case "getConduitCount": return conduits().length;
            default: sim.missing("mage." + name); return null;
        }
    }
}

/** The priest's class component as scripts use it (ownerHero.priest). */
class PriestObj implements IObj {
    var sim:Sim;
    public function new(sim:Sim) this.sim = sim;
    public function get(name:String):Dynamic return null;
    public function set(name:String, v:Dynamic):Void {}
    public function call(name:String, a:Array<Dynamic>):Dynamic {
        switch (name) {
            case "divineInterventionProc": sim.divineIntervention(); return null;
            case "getChargedPrayerCount": return sim.chargedPrayers().length;
            default: sim.missing("priest." + name); return null;
        }
    }
}
