package buildcalc;

import buildcalc.Items.Candidate;
import buildcalc.Items.Affix;
import buildcalc.Augments.Augment;
import buildcalc.SkillData.SkillDef;
import buildcalc.SkillData.Step;
import buildcalc.SkillData.Effect;
import buildcalc.SkillData.ScriptMod;
import buildcalc.SkillData.ScriptProc;
import buildcalc.SkillData.Filter;
import buildcalc.StatEngine.Sums;

/** A whole build: equipment with augments and infusions, talents, class skills and their runes. */
typedef Build = {
    var items:Map<Int, Candidate>;
    var augs:Map<Int, Array<Augment>>;      // per slot (worn items: what they have)
    var infusion:Map<Int, String>;          // per slot, items created for the calculation: infusion skill id
    var bonus:Map<Int, String>;             // per slot, items created for the calculation: infusion bonus attribute
    var talents:Map<String, Int>;
    var skills:Array<String>;               // class skills
    var runes:Map<String, Array<String>>;   // class skill -> runes
    var arsenal:Array<String>;              // skills chosen for the arsenal weapon (Weapon.isValidArsenalSkill)
}

typedef SkillOut = {dmg:Float, selfHeal:Float, allyHeal:Float};

/** A skill that is part of a build, with the rank and runes it has there; `slot`: the equipment slot it comes from (-1 none). */
typedef Src = {def:SkillDef, rank:Int, runes:Array<String>, kind:String, item:Candidate, slot:Int};

/**
 * `steps` of `src` run `rate` times a second on `chain` targets. `dyn`: dynamic effects take this share
 * of the triggering hits of `dynFrom`. `heal`: who its heals reach ("self", "ally", "both").
 */
typedef Event = {src:Src, steps:Array<Step>, rate:Float, chain:Float, dyn:Float, dynFrom:String, what:String, heal:String, ticks:Bool};

typedef Eval = {axes:Array<Float>, vals:Array<Float>, buffed:Array<Float>, dps:Float, selfHeal:Float, allyHeal:Float,
    weaponSkills:Map<Int, Array<String>>, perSkill:Map<String, SkillOut>, modelDps:Float, modelSelfHeal:Float, modelAllyHeal:Float, calibrated:Bool};

/**
 * Values a build the way the game computes it, from the data only (no class or skill is named here):
 *  - attributes: StatEngine with every bonus of the build (item affixes × slot factor, augments, infusion
 *    bonus, skill affixes of talents / infusion ranks / item skills by their rank and rune conditions);
 *  - the attack chain of the main weapon: each of its attacks once (hero.attackSkills), then its combo
 *    attack; class skills, the hero's weapon skill slots of each weapon, the hero's other active
 *    skills every cooldown × (1 − CooldownReduction) (ent.GameObject.getCooldownModifier), cast time
 *    × (1 − SpellCastTimeReduction); skills charged by script events (chargePrayer, addCharges) as often as
 *    the event; cooldowns shortened by script events (reduceCooldown) by the event's rate × time;
 *  - statuses the skills apply: their affixes × uptime (stacks up to props.status.maxStacks), their
 *    effects per application (at most maxStacks per duration);
 *  - procs read from the scripts (SkillDef.analyse): trigger rate × chance × the steps they play;
 *  - damage (st.skill.SkillContext / BaseSkill.calcDamageAmount): value × (1 + Mastery + Fervor) ×
 *    DamageModifier (GameObject.getDamageRatio) × script modifiers × crit (CritChance, CritDamage; none for
 *    damage / heal over time) × armour of the target after penetration (A / (A + F0 + F1 × level));
 *    heals × HealGivenMultiplier × crit; shields × ShieldPowerMultiplier. Steps spread over ticks
 *    (loop flag SpreadEffects, HSkill.getStepEffectVal) give their value once, others per tick.
 * The targets (armour, magic armour, health for kills) are the foes around the hero now, or the game's
 * expected armour (Const.Attributes.Armor_ExpectedReduction) when there are none.
 * Axes: damage per second, defense (effective health factor), MaxHealth, healing per second (self + one ally).
 */
class Model {
    public static var ATTACKS = ["Attack", "Attack2", "Attack3", "Attack4", "AttackCombo"];
    static var ACTIVE = ["ClassSkill", "WeaponSkill", "SignatureSkill", "Skill", "Secondary", "PriestPrayer", "MageConduit", "RoguePoison", "GroupSkill"];
    static var IGNORED = ["Block", "Dash", "Swap", "Mount", "Jump", "Exit", "Action", "ItemUse", "WeaponSubSkill"];
    /** Step triggers that do not run as part of a cast (scripts, reactions). */
    static var NOT_CAST = ["Code", "Trigger", "GetHit", "DeathDoor", "ShieldEnd", "Pickup", "Prepare", "TouchGround"];

    public var engine:StatEngine;
    public var hero:Dynamic;
    public var factor = new Map<Int, Float>();
    var index:Map<String, Int>;
    var progress:Dynamic;
    var armorF0 = 0.0;
    var armorF1 = 0.0;
    var targetArmor = 0.0;
    var targetMagicArmor = 0.0;
    /** Health of a typical foe around the hero (0: unknown, kills are not valued). */
    var foeHealth = 0.0;
    var fixed:Array<Src> = [];
    var flag512 = new Map<String, Bool>();
    var rankCache = new Map<String, Int>();
    var itemPartCache = new Map<String, Float>();
    var stackRanks = new Map<Int, Int>();
    var bonusCache = new Map<String, Affix>();
    var activeCache = new Map<String, Bool>();
    public var report:Array<String> = null;
    var weaponSlots = 2;

    public function new(hero:Dynamic, current:Build, slots:Map<Int, Float>) {
        this.hero = hero;
        factor = slots;
        engine = new StatEngine(hero);
        index = engine.index;
        try progress = G.field(G.call("st.player.HeroSpecialization", "get_player", [G.field(hero, "specialization")]), "progress") catch (_:Dynamic) {}
        var all = G.field(GameData.data("attribute"), "all");
        for (i in 0...G.len(all)) if ((Std.int(G.num(G.field(G.at(all, i), "flags"))) & 512) != 0) flag512.set(G.str(G.field(G.at(all, i), "id")), true);
        try {
            var attrs = G.field(HlxRuntime.resolveStaticField(G.type("Const"), "Attributes"), "ResistanceScalableReductionFormula");
            armorF0 = G.num(G.at(attrs, 0));
            armorF1 = G.num(G.at(attrs, 1));
            var r = G.num(G.field(HlxRuntime.resolveStaticField(G.type("Const"), "Attributes"), "Armor_ExpectedReduction"));
            var k = armorF0 + armorF1 * engine.level;
            if (r > 0 && r < 1) targetArmor = targetMagicArmor = r * k / (1 - r);
        } catch (e:Dynamic) DebugLog.error("armour formula", e);
        readFoes();
        try {
            var levels = G.field(HlxRuntime.resolveStaticField(G.type("Const"), "Hero"), "UnlockLevel_WeaponSkillSlots");
            var n = 0;
            for (i in 0...G.len(levels)) if (G.num(G.at(levels, i)) <= engine.level) n++;
            if (G.len(levels) > 0) weaponSlots = n;
        } catch (e:Dynamic) DebugLog.error("weapon skill slots", e);
        DebugLog.line("model: armour formula F0=" + armorF0 + " F1=" + armorF1 + "; target armour " + Math.round(targetArmor) + ", magic armour "
            + Math.round(targetMagicArmor) + ", foe health " + Math.round(foeHealth) + "; " + weaponSlots + " weapon skill slots");

        // the hero's other skills: what the hero has that does not come from what the build chooses
        var chosen = new Map<String, Bool>();
        for (s in sources(current)) chosen.set(s.def.id, true);
        var list = G.field(hero, "skills");
        var kept = [];
        // the mage's conduits: only those in its conduit slots work (ent.hero.MageComponent.conduits)
        var conduitSlots:Map<String, Bool> = null;
        try {
            var mage = G.field(hero, "mage");
            var cs = mage != null ? G.field(mage, "conduits") : null;
            if (cs != null) {
                conduitSlots = new Map();
                for (i in 0...G.len(cs)) { var c = G.at(cs, i); if (c != null) conduitSlots.set(G.str(G.field(G.field(c, "inf"), "id")), true); }
                DebugLog.line("model: mage conduits in slots: " + [for (k in conduitSlots.keys()) k].join(", "));
            }
        } catch (e:Dynamic) DebugLog.error("mage conduits", e);
        for (i in 0...G.len(list)) {
            var inst = G.at(list, i);
            var id = G.str(G.field(G.field(inst, "inf"), "id"));
            var def = SkillData.get(id);
            if (def == null || chosen.exists(id) || IGNORED.indexOf(def.type) >= 0) continue;
            if (def.type == "ClassSkill" || def.type == "Talent" || def.type == "InfusionPassive") continue;
            if (isItemSkill(id)) continue;
            if (def.type == "MageConduit" && conduitSlots != null && !conduitSlots.exists(id)) continue;
            fixed.push({def: def, rank: heroSkillRank(def), runes: GameData.skillMasteries(def.inf, GameData.activeMasteries(hero)), kind: "hero", item: null, slot: -1});
            kept.push(id + "(" + def.type + ")");
        }
        DebugLog.line("model: hero's own skills kept as they are: " + kept.join(", "));
        // the attack chain the game uses now (ent.Hero.getNextAttackSkill goes through hero.attackSkills)
        try {
            var atk = G.field(hero, "attackSkills");
            DebugLog.line("model: hero.attackSkills = " + [for (i in 0...G.len(atk)) G.str(G.field(G.field(G.at(atk, i), "inf"), "id"))].join(" > "));
        } catch (e:Dynamic) DebugLog.error("attackSkills", e);
        engine.setKnown(sums(current));
    }

    /** Foes of about the hero's level around the hero now: their armour, magic armour and health. */
    /** Damage taken multipliers of the target after armour (magic reduction, resilience, damage taken modifier). */
    var targetPhysTaken = 1.0;
    var targetMagicTaken = 1.0;

    function readFoes():Void {
        try {
            var app = HlxRuntime.resolveStaticField(G.type("GameApp"), "inst");
            var units = G.field(app, "units");
            for (i in 0...G.len(units)) {
                var u = G.at(units, i);
                if (G.str(G.field(G.field(u, "inf"), "id")) != "Dummy") continue;
                function atb(name:String):Float {
                    var k = index.get(name);
                    if (k == null) return 0;
                    return G.num(G.call("ent.GameObject", "atbVal", [u, k, null])) * engine.percent(k);
                }
                var d = {armor: atb("Armor"), magicArmor: atb("MagicArmor"), magicReduction: atb("MagicReduction"), resilience: atb("Resilience"),
                    taken: index.exists("DamageTakenModifier") ? atb("DamageTakenModifier") : 1, level: G.num(G.call("ent.Unit", "getEffectiveLevel", [u]))};
                DebugLog.line("model: training dummy in the world (saved): level " + d.level + ", armour " + d.armor + ", magic armour " + d.magicArmor
                    + ", magic reduction " + d.magicReduction + ", resilience " + d.resilience + ", damage taken x" + d.taken);
                State.dummy = d;
                State.save();
                break;
            }
        } catch (e:Dynamic) DebugLog.error("dummy", e);
        try {
            var app = HlxRuntime.resolveStaticField(G.type("GameApp"), "inst");
            var units = G.field(app, "units");
            var n = 0, armor = 0.0, magic = 0.0, health = 0.0;
            var iArmor = index.get("Armor"), iMagic = index.get("MagicArmor"), iHealth = index.get("MaxHealth");
            for (i in 0...G.len(units)) {
                var u = G.at(units, i);
                var t = G.typeName(u);
                if (t.indexOf("Foe") < 0 || t.indexOf("boss") >= 0) continue;
                var level = G.num(G.field(u, "_level"));
                if (Math.abs(level - engine.level) > 5) continue;
                var hp = G.num(G.call("ent.GameObject", "atbVal", [u, iHealth, null]));
                if (hp <= 0) continue;
                n++;
                health += hp;
                armor += G.num(G.call("ent.GameObject", "atbVal", [u, iArmor, null]));
                magic += G.num(G.call("ent.GameObject", "atbVal", [u, iMagic, null]));
            }
            if (n > 0) {
                foeHealth = health / n;
                targetArmor = armor / n;
                targetMagicArmor = magic / n;
            }
            DebugLog.line("model: " + n + " foes of level " + engine.level + "±5 around the hero");
        } catch (e:Dynamic) DebugLog.error("foes", e);
        // the fight is valued against the training dummy, else against the foes' expected armour
        var dummy:Dynamic = State.dummy;
        if (dummy != null) {
            targetArmor = G.num(dummy.armor);
            targetMagicArmor = G.num(dummy.magicArmor);
            var common = Math.max(0, 1 - G.num(dummy.resilience)) * Math.max(0, dummy.taken == null ? 1 : G.num(dummy.taken));
            targetPhysTaken = common;
            targetMagicTaken = common * Math.max(0, 1 - G.num(dummy.magicReduction));
            DebugLog.line("model: target = the training dummy as read in the game (level " + dummy.level + "): armour " + Math.round(targetArmor)
                + ", magic armour " + Math.round(targetMagicArmor) + "; physical x" + targetPhysTaken + ", magic x" + targetMagicTaken + " after armour");
        } else DebugLog.line("model: the training dummy was never in the loaded world: target = the game's expected armour " + Math.round(targetArmor)
            + " (Const.Attributes.Armor_ExpectedReduction)");
    }

    static var itemSkills:Map<String, Bool> = null;

    /** Is this skill given by some item of the game (weapons, trinkets, enchantments)? */
    static function isItemSkill(id:String):Bool {
        if (itemSkills == null) {
            itemSkills = new Map();
            var all = G.field(GameData.data("item"), "all");
            for (i in 0...G.len(all)) {
                var sk = G.field(G.at(all, i), "skills");
                for (k in 0...G.len(sk)) itemSkills.set(GameData.idOf(G.field(G.at(sk, k), "skill")), true);
            }
            var types = G.field(GameData.data("itemType"), "all");
            for (i in 0...G.len(types)) {
                var sk = G.field(G.at(types, i), "skills");
                for (k in 0...G.len(sk)) itemSkills.set(GameData.idOf(G.field(G.at(sk, k), "skill")), true);
            }
        }
        return itemSkills.exists(id);
    }

    /** Rank of a skill for this player (st.player.Progress.getSkillRank: weapon skills by the player's progress). */
    /**
     * The ideal build values every weapon with its skills at the highest rank (Const.Hero.WeaponSkill_MaxRank): a
     * weapon's skill ranks grow by using it (kills with it), so a weapon the hero has not used yet is not held back
     * by its rank now; otherwise the hero's rank now (st.player.Progress.getSkillRank).
     */
    public var idealRanks = false;
    var maxWeaponRank = -1;

    public function itemSkillRank(def:SkillDef):Int {
        var now = heroSkillRank(def);
        if (!idealRanks) return now;
        if (maxWeaponRank < 0) {
            maxWeaponRank = 1;
            try maxWeaponRank = Std.int(G.num(G.field(HlxRuntime.resolveStaticField(G.type("Const"), "Hero"), "WeaponSkill_MaxRank"))) catch (_:Dynamic) {}
            if (maxWeaponRank < 1) maxWeaponRank = 1;
            DebugLog.line("model: weapon skills valued at rank " + maxWeaponRank + " (Const.Hero.WeaponSkill_MaxRank)");
        }
        return Std.int(Math.max(now, maxWeaponRank));
    }

    public function heroSkillRank(def:SkillDef):Int {
        if (rankCache.exists(def.id)) return rankCache.get(def.id);
        var r = 1;
        try r = Std.int(G.num(G.call("st.player.Progress", "getSkillRank", [progress, def.inf]))) catch (_:Dynamic) {}
        if (r < 1) r = 1;
        rankCache.set(def.id, r);
        return r;
    }

    public function rankFromStacks(n:Int):Int {
        if (stackRanks.exists(n)) return stackRanks.get(n);
        var r = 0;
        try r = Std.int(G.num(G.callStatic("HInfusion", "getRankFromStacks", [n]))) catch (_:Dynamic) {}
        stackRanks.set(n, r);
        return r;
    }

    /** Infusions of the build: infusion id -> number of items with it. */
    public function infusionCounts(b:Build):Map<String, Int> {
        var out = new Map<String, Int>();
        for (s => c in b.items) if (c != null) {
            var inf = b.infusion.exists(s) ? (c.infusable ? b.infusion.get(s) : "") : (c.real ? c.infusion : "");
            if (inf != null && inf != "") out.set(inf, (out.exists(inf) ? out.get(inf) : 0) + 1);
        }
        return out;
    }

    /**
     * What the infusions of a build change, as a key: the number of items of each infusion (its rank) and the infusion
     * bonus affixes of the created items (sums). Two builds with the same key are valued the same.
     */
    public function infusionSig(b:Build):String {
        var parts = [for (id => n in infusionCounts(b)) id + "x" + n];
        for (slot => c in b.items) if (c != null) {
            var a = addedBonus(b, slot, c);
            if (a != null) parts.push("+" + a.kind + ":" + a.attr + ":" + a.val * (factor.exists(slot) ? factor.get(slot) : 1.0));
            if (reinfused(b, slot, c) && c.ownBonus != null) parts.push("-" + c.key);
        }
        parts.sort((x, y) -> x < y ? -1 : (x > y ? 1 : 0));
        return parts.join(",");
    }

    /** Every skill of the build with its rank and runes, each skill once (the game gives a skill once). */
    public function sources(b:Build):Array<Src> {
        var out:Array<Src> = [];
        var seen = new Map<String, Src>();
        function add(s:Src):Void {
            var o = seen.get(s.def.id);
            if (o == null) { seen.set(s.def.id, s); out.push(s); }
            else if (s.rank > o.rank) o.rank = s.rank;
        }
        var talents = new Map<String, Int>();
        for (id => r in b.talents) if (r > 0) talents.set(id, r);
        for (s in Items.SLOTS) {
            var c = b.items.get(s);
            if (c == null) continue;
            if (s == Items.OFFHAND && !Items.offhandWorks(b.items.get(0), c)) continue;
            for (id in c.skills) {
                var d = SkillData.get(id);
                if (d == null || IGNORED.indexOf(d.type) >= 0) continue;
                // the arsenal weapon gives only the skills chosen for the arsenal (ent.Hero.getNbArsenalSkillSlots of them)
                if (s == 1 && (b.arsenal == null || b.arsenal.indexOf(id) < 0)) continue;
                add({def: d, rank: itemSkillRank(d), runes: [], kind: s == 1 ? "arsenal" : "item", item: c, slot: s});
            }
            var augs = b.augs.get(s);
            if (augs != null) for (a in augs) for (id in a.skills) {
                var d = SkillData.get(id);
                if (d == null) continue;
                // a sigil gives a talent of the tree without points
                if (d.maxPoints > 0) { if (!talents.exists(id) || talents.get(id) < d.maxPoints) talents.set(id, d.maxPoints); }
                else add({def: d, rank: 1, runes: [], kind: "enchant", item: c, slot: s});
            }
        }
        // in a fixed order (sorted ids): a map's order depends on how it was filled, and the order of the skills is the
        // order the fight tries them in — the same build filled another way was valued otherwise
        var tids = [for (id in talents.keys()) id];
        tids.sort((x, y) -> x < y ? -1 : (x > y ? 1 : 0));
        for (id in tids) {
            var d = SkillData.get(id);
            if (d != null) add({def: d, rank: talents.get(id), runes: [], kind: "talent", item: null, slot: -1});
        }
        var counts = infusionCounts(b);
        var iids = [for (id in counts.keys()) id];
        iids.sort((x, y) -> x < y ? -1 : (x > y ? 1 : 0));
        for (id in iids) {
            var n = counts.get(id);
            var r = rankFromStacks(n);
            var d = SkillData.get(id);
            if (r > 0 && d != null) {
                add({def: d, rank: r, runes: [], kind: "infusion", item: null, slot: -1});
                for (sub in d.subskills) {
                    var sd = SkillData.get(sub);
                    if (sd != null) add({def: sd, rank: r, runes: [], kind: "infusion", item: null, slot: -1});
                }
            }
        }
        for (id in b.skills) {
            var d = SkillData.get(id);
            if (d != null) add({def: d, rank: heroSkillRank(d), runes: b.runes.exists(id) ? b.runes.get(id) : [], kind: "class", item: null, slot: -1});
        }
        for (f in fixed) add(f);
        return out;
    }

    /**
     * Skills of the build whose effect the model cannot value: script handlers it does not read, or procs
     * that need events it cannot count (blocks, hits received, kills without foes around).
     */
    public function unvalued(b:Build):Map<String, Bool> {
        var out = new Map<String, Bool>();
        if (useSim) return out; // the fight runs every script: nothing is left unvalued
        for (src in sources(b)) {
            var d = src.def;
            var unknown = d.unknown.length > 0;
            for (p in d.procs) if (p.trigger == "block" || p.trigger == "received" || (p.trigger == "kill" && foeHealth <= 0)) unknown = true;
            for (c in d.cdrs) if (c.trigger == "block" || c.trigger == "received" || (c.trigger == "kill" && foeHealth <= 0)) unknown = true;
            if (unknown) out.set(d.id, true);
        }
        return out;
    }

    /** Bonus attributes an infusion can give (HInfusion.getInfusionBonusAptitude); set by the optimizer. */
    public var bonusStats:Array<String> = [];

    /** A real item that the build gives another infusion (the player infuses it again). */
    public function reinfused(b:Build, slot:Int, c:Candidate):Bool {
        return c.real && c.infusable && b.infusion.exists(slot) && b.infusion.get(slot) != c.infusion;
    }

    /**
     * The infusion bonus attribute of the item in this slot: the one chosen for it; a real item infused again keeps its
     * own attribute, or takes the first one if it had none (the player picks it when infusing).
     */
    public static inline var COUNT_BONUS = false;

    public function bonusOf(b:Build, slot:Int, c:Candidate):String {
        if (b.bonus.exists(slot) && b.bonus.get(slot) != null) return b.bonus.get(slot);
        if (!c.real) return null;
        return c.bonusStat != "" ? c.bonusStat : (bonusStats.length > 0 ? bonusStats[0] : null);
    }

    /**
     * The infusion bonus the build adds to the item in this slot (null: none): a created item's with its infusion; a real
     * item's only when the build infuses it again (its own bonus is already in its affixes, `sums` leaves it out then).
     */
    function addedBonus(b:Build, slot:Int, c:Candidate):Affix {
        // the infusion bonus attribute works only on items of the infusion's faction: the choice of infusions must rest on
        // the effects of the sets, not on factions (the player's rule), so the attribute adds nothing to the value
        if (!COUNT_BONUS) return null;
        if (!c.infusable) return null;
        if (c.real && !reinfused(b, slot, c)) return null;
        var inf = b.infusion.get(slot);
        var stat = bonusOf(b, slot, c);
        if (inf == null || inf == "" || stat == null || !bonusActive(c, inf)) return null;
        return bonusAffix(c, inf, stat, c.real ? null : b.augs.get(slot));
    }

    /** The item the infusion is tried on: a created item itself; for a real item a copy (st.Item.clone), never the item. */
    function probe(c:Candidate):Dynamic {
        if (!c.real) return c.item;
        // made on the game's thread before the search (Optimizer.pools0); never here, in the search thread
        return c.probe;
    }

    /** The infusion bonus affix the item would have with this attribute (st.item.Gear.getInfusionBonusAffix). */
    public function bonusAffix(c:Candidate, infusion:String, stat:String, ?augs:Array<Augment>):Affix {
        var key = c.key + "|" + stat + "|" + augKey(augs);
        if (bonusCache.exists(key)) return bonusCache.get(key);
        var a:Affix = null;
        try {
            // the bonus scales with the item level (st.item.Gear.getInfusionBonusAffix): a created item with its augments
            if (!c.real) slotItem(c, augs);
            var item = probe(c);
            if (item == null) { bonusCache.set(key, null); return null; }
            G.call("st.item.Gear", "set_infusion", [item, infusion]);
            G.call("st.item.Gear", "set_infusionBonusStat", [item, stat]);
            a = Items.affixOf(G.call("st.item.Gear", "getInfusionBonusAffix", [item]));
        } catch (e:Dynamic) DebugLog.error("bonusAffix " + c.id, e);
        bonusCache.set(key, a);
        return a;
    }

    /** Is the infusion bonus of the item active with this infusion (st.item.Gear.isInfusionBonusActive)? */
    public function bonusActive(c:Candidate, infusion:String):Bool {
        var key = c.key + "|" + infusion;
        if (activeCache.exists(key)) return activeCache.get(key);
        var on = false;
        try {
            var item = probe(c);
            if (item == null) { activeCache.set(key, false); return false; }
            G.call("st.item.Gear", "set_infusion", [item, infusion]);
            // the copy needs an attribute for the game to call the bonus active (isInfusionBonusActive)
            if (c.real && G.field(item, "infusionBonusStat") == null && bonusStats.length > 0)
                G.call("st.item.Gear", "set_infusionBonusStat", [item, bonusStats[0]]);
            on = G.call("st.item.Gear", "isInfusionBonusActive", [item]) == true;
        } catch (e:Dynamic) DebugLog.error("bonusActive " + c.id, e);
        activeCache.set(key, on);
        return on;
    }

    var createdCache = new Map<String, Array<Affix>>();

    static function augKey(augs:Array<Augment>):String return augs == null ? "" : [for (a in augs) a.id].join(",");

    /** Puts these augments in a created item's slots (its item level depends on them). */
    function slotItem(c:Candidate, augs:Array<Augment>):Bool {
        var ids:Array<Dynamic> = augs == null ? [] : [for (a in augs) a.raw];
        Items.setSlots(c.item, ids);
        return ids.length == 0 || G.field(c.item, "slots") != null;
    }

    /**
     * A created item's affixes with these augments in its slots, as the game counts them (st.item.Gear.getAffixes): the
     * base affixes grow with the item level, and every augment adds its own iLevel to it (st.item.Gear.getILevel). With
     * the slots left empty a created item came out weaker than the same item worn (a censer 70 vitality instead of 75).
     * Without the infusion (its bonus is counted apart: addedBonus).
     */
    public function createdAffixes(c:Candidate, augs:Array<Augment>):Array<Affix> {
        var key = c.key + "|" + augKey(augs);
        var out = createdCache.get(key);
        if (out != null) return out;
        out = null;
        try {
            if (slotItem(c, augs)) {
                G.call("st.item.Gear", "set_infusion", [c.item, null]);
                out = Items.affixes(c.item);
            }
        } catch (e:Dynamic) DebugLog.error("createdAffixes " + c.id, e);
        if (out == null) { // no slot list to fill: the old way (base affixes + the augments' own)
            out = c.affixes.copy();
            if (augs != null) for (aug in augs) for (a in aug.affixes) out.push(a);
        }
        createdCache.set(key, out);
        return out;
    }

    /** Permanent attribute bonuses of the build. */
    public function sums(b:Build):Sums {
        var s = new Sums(engine.count);
        for (slot => c in b.items) if (c != null) {
            if (slot == Items.OFFHAND && !Items.offhandWorks(b.items.get(0), c)) continue;
            var f = factor.exists(slot) ? factor.get(slot) : 1.0;
            // a real item infused again loses its own infusion bonus (the last of its affixes)
            var own = reinfused(b, slot, c) ? c.ownBonus : null;
            // a real item's affixes hold its augments; a created one is valued with the build's augments in its slots
            var list = c.real ? c.affixes : createdAffixes(c, b.augs.get(slot));
            for (a in list) if (a != own) s.affix(index, a.kind, a.attr, a.val, f);
            var a = addedBonus(b, slot, c);
            if (a != null) s.affix(index, a.kind, a.attr, a.val, f);
        }
        for (src in sources(b)) for (a in src.def.affixes) if (src.def.affixActive(a, src.rank, src.runes)) s.affix(index, a.ref, a.attr, a.val, 1.0);
        return s;
    }

    // ---------------------------------------------------------------- values

    var vals:Array<Float>;
    var buffed:Array<Float>;

    function get(v:Array<Float>, name:String):Float return engine.get(v, name);

    function raw(v:Array<Float>, name:String):Float {
        var i = index.get(name);
        return i == null ? 0 : v[i];
    }

    /** Hits of one run of a step: its loop's ticks over its duration (a status's own duration when the step lasts as long). */
    function stepTicks(def:SkillDef, s:Step, rank:Int, runes:Array<String>, statusDuration:Float):Float {
        var tick = def.num(s.tick, rank, runes, 0);
        if (tick <= 0) return 1;
        var dur = def.num(s.duration, rank, runes, 0);
        if (dur < 0) dur = statusDuration;
        if (dur <= 0) return 1;
        return Math.max(1, Math.floor(dur / Math.max(tick, s.targetCd)));
    }

    /** How many times a step's effect value counts in one run: once if spread over its ticks, else per tick. */
    function stepValueTimes(def:SkillDef, s:Step, rank:Int, runes:Array<String>, statusDuration:Float):Float
        return s.spread ? 1 : stepTicks(def, s, rank, runes, statusDuration);

    function itemPart(src:Src, e:Effect, ratio:Float):Float {
        var key = src.item.key + "|" + src.rank + "|" + e.uid; // by the candidate: same id, other item data (rarity, level)
        if (itemPartCache.exists(key)) return itemPartCache.get(key);
        var v = 0.0;
        try {
            var info = {inf: src.def.inf, rank: src.rank, maxRank: null, masteries: src.runes, heroic: false};
            v = G.num(G.callStatic("HSkill", "getStepEffectItemScaling", [info, e.raw, src.item.inf, ratio]));
        } catch (err:Dynamic) DebugLog.error("item part " + src.def.id, err);
        itemPartCache.set(key, v);
        return v;
    }

    /** The value of one effect before multipliers (HSkill.getStepEffectScaling, with these attributes). */
    function effectBase(e:Effect, src:Src, v:Array<Float>):Float {
        var out = e.base;
        var r = src.item != null ? src.item.powerRatio : 0.0;
        if (r > 0) out += itemPart(src, e, r);
        for (sc in e.scaling) {
            if (!SkillDef.rankOk(sc.minRank, sc.maxRank, sc.equalRank, src.rank)) continue;
            var ratio = sc.ratio;
            if (r > 0 && flag512.exists(sc.atb)) ratio *= (1 - r);
            if (sc.atb == "AllAttributes") {
                var n = engine.mainAttributes.length;
                if (n > 0) for (i in engine.mainAttributes) out += v[i] * ratio / n;
            } else if (sc.atb == "WeaponPower" && src.item != null && src.item.aptAtbs.length > 0) {
                for (a in src.item.aptAtbs) out += raw(v, a) * ratio / src.item.aptAtbs.length;
            } else out += raw(v, sc.atb) * ratio;
        }
        return out;
    }

    var mods:Array<{mod:ScriptMod, value:Float, owner:SkillDef}> = [];
    var isStatus = false;

    function modMatches(m:ScriptMod, owner:SkillDef, def:SkillDef, physical:Bool, heal:Bool):Bool {
        if (m.heal != heal) return false;
        if (m.filter.status && !isStatus) return false;
        if (m.own && owner != def) return false;
        var f = m.filter;
        if (f.skill != "" && f.skill != def.id) return false;
        var attack = ATTACKS.indexOf(def.type) >= 0;
        if ((f.attacks || f.combo) && !attack) return false;
        if (f.combo && !f.attacks && def.type != "AttackCombo") return false;
        if (f.magic && physical) return false;
        if (f.weaponSkill && def.type != "WeaponSkill") return false;
        if (f.classSkill && def.type != "ClassSkill") return false;
        if (f.anySkill && attack) return false;
        return true;
    }

    function modSum(stat:String, def:SkillDef, physical:Bool, heal:Bool):Float {
        var s = 0.0;
        for (m in mods) if (m.mod.stat == stat && modMatches(m.mod, m.owner, def, physical, heal)) s += m.value;
        return s;
    }

    function critFactor(def:SkillDef, physical:Bool, heal:Bool):Float {
        if (isStatus && def.dotHot) return 1; // damage and heal over time do not crit
        var chance = Math.min(1, Math.max(0, get(buffed, "CritChance") + modSum("critChance", def, physical, heal)));
        return 1 + chance * Math.max(0, get(buffed, "CritDamage") + modSum("critDmgMult", def, physical, heal) - 1);
    }

    /** Is this attribute's skill scaling partly replaced by the item's own power (Data.attribute flag 512)? */
    public function itemScaled(atb:String):Bool return flag512.exists(atb);

    /** Armour (or magic armour) of the target the build is valued against. */
    public function foeArmor(physical:Bool):Float return physical ? targetArmor : targetMagicArmor;

    /** What the target's other reductions leave of a hit after armour. */
    public function foeTaken(physical:Bool):Float return physical ? targetPhysTaken : targetMagicTaken;

    /**
     * Defense axis: 1 / share of damage taken from foes of the hero's level, half physical (Armor) and half
     * magic (MagicArmor, MagicReduction), then Resilience, DamageTakenModifier and DodgeChance.
     */
    function defense(v:Array<Float>):Float {
        var magicTaken = (1 - reduction(get(v, "MagicArmor"))) * Math.max(0, 1 - get(v, "MagicReduction"));
        var taken = 0.5 * (1 - reduction(get(v, "Armor"))) + 0.5 * magicTaken;
        taken *= Math.max(0, 1 - get(v, "Resilience")) * Math.max(0.05, get(v, "DamageTakenModifier"))
            * Math.max(0.05, 1 - Math.min(0.95, get(v, "DodgeChance")));
        return 1 / Math.max(0.01, taken);
    }

    /** The chance of a critical strike the build has (the attribute as the stats panel shows it), at most 100%. */
    function critValue(v:Array<Float>):Float return Math.min(1, Math.max(0, get(v, "CritChance")));

    public function reduction(armor:Float):Float {
        var k = armorF0 + armorF1 * engine.level;
        return armor > 0 && armor + k > 0 ? armor / (armor + k) : 0;
    }

    /** Damage and heal of one effect with all multipliers. */
    function effectValue(e:Effect, src:Src, base:Float):{dmg:Float, heal:Float} {
        var def = src.def;
        isStatus = src.kind == "status";
        if (e.kind == "Damage") {
            var ratio = (1 + get(buffed, e.physical ? "PhysicalMastery" : "MagicMastery") + get(buffed, "Fervor")) * get(buffed, "DamageModifier");
            var pen = Math.min(1, Math.max(0, get(buffed, e.physical ? "ArmorPenetration" : "SpellPenetration")));
            var ignore = Math.min(1, modSum(e.physical ? "armorIgnore" : "magicArmorIgnore", def, e.physical, false));
            var a = (e.physical ? targetArmor : targetMagicArmor) * (1 - pen) * (1 - ignore);
            var d = base * Math.max(0, ratio) * Math.max(0, 1 + modSum("dmgMult", def, e.physical, false)) * critFactor(def, e.physical, false) * (1 - reduction(a));
            return {dmg: Math.max(0, d), heal: 0};
        }
        if (e.kind == "Heal")
            return {dmg: 0, heal: Math.max(0, base * get(buffed, "HealGivenMultiplier") * Math.max(0, 1 + modSum("dmgMult", def, false, true)) * critFactor(def, false, true))};
        if (e.kind == "Shield") return {dmg: 0, heal: Math.max(0, base * get(buffed, "ShieldPowerMultiplier"))};
        return {dmg: 0, heal: 0};
    }

    function isActive(d:SkillDef):Bool return ACTIVE.indexOf(d.type) >= 0 && (d.cooldown > 0 || d.charges.length > 0);

    /** Per-cast effect sum of the steps a cast runs (quick estimate with the permanent attributes, to rank weapon skills). */
    function quickCast(src:Src):Float {
        var sum = 0.0;
        for (s in castSteps(src)) for (e in s.effects) if (e.kind == "Damage" || e.kind == "Heal" || e.kind == "Shield")
            sum += effectBase(e, src, vals) * stepValueTimes(src.def, s, src.rank, src.runes, 0);
        return sum;
    }

    function castSteps(src:Src):Array<Step>
        return [for (s in src.def.steps) if (NOT_CAST.indexOf(s.on) < 0 && src.def.stepActive(s, src.rank, src.runes)) s];

    function hitsOf(src:Src, steps:Array<Step>, kind:String, statusDuration:Float):Float {
        var n = 0.0;
        for (s in steps) if (!(s.ignoreMain && kind == "Damage")) for (e in s.effects) if (e.kind == kind) n += stepTicks(src.def, s, src.rank, src.runes, statusDuration);
        return n;
    }

    /** Who a heal of this event reaches: the hero alone, one ally (× chain), or both. */
    static function healTarget(s:Step, chained:Bool, statusSelf:Bool):String {
        if (chained) return "ally";
        if (s.type == "SelfEffect" || statusSelf) return "self";
        return "both";
    }

    /**
     * The second rotation: the class skills that deal no damage (by their steps or the statuses they apply, with their
     * runes: Faithful Winds without its damage rune…) are not used. A build must not lose there either (Optimizer.robustOk).
     */
    public var noUtility = false;

    /**
     * Stats-only valuation (an item with no skills of its own: armour, rings, neck, back): the fight of the same skills
     * is valued again with the new attributes (replay, ~1 ms) even when a timing attribute (crit, cooldowns…) changed;
     * no new fight. The final build is valued with full fights.
     */
    public var statsOnly = false;

    public function evaluateWithoutUtility(b:Build):Eval {
        noUtility = true;
        var e = try evaluate(b) catch (err:Dynamic) { noUtility = false; throw err; }
        noUtility = false;
        return e;
    }

    /**
     * Effects that make a class skill count in the second rotation: the ones of the fight axes the player gave a priority
     * (damage: Damage; healing: Heal, Shield). Set by the optimizer; damage when none.
     */
    public var valuedKinds:Array<String> = ["Damage"];

    /** A class skill with no effect of the prioritized fight axes (valuedKinds) in its active steps or the statuses they apply (one level). */
    function isUtility(env:GameEnv, s:Src):Bool {
        if (s.kind != "class") return false;
        var info = env.skill(s.def.id);
        if (info == null) return false;
        function damages(i:buildcalc.sim.SimData.SkillInfo, rank:Int, runes:Array<String>, depth:Int):Bool {
            for (st in i.steps) {
                if (!i.stepActive(st, rank, runes)) continue;
                for (e in st.effects) {
                    if (valuedKinds.indexOf(e.kind) >= 0) return true;
                    if (depth == 0 && e.status != "") { var si = env.skill(e.status); if (si != null && damages(si, rank, runes, 1)) return true; }
                }
                if (depth == 0 && st.status != "") { var si = env.skill(st.status); if (si != null && damages(si, rank, runes, 1)) return true; }
            }
            return false;
        }
        return !damages(info, s.rank, s.runes, 0);
    }

    public function evaluate(b:Build):Eval {
        if (useSim) {
            var vals = engine.evaluate(sums(b));
            var e:Eval = {axes: [0, defense(vals), get(vals, "MaxHealth"), 0, critValue(vals)], vals: vals, buffed: vals, dps: 0, selfHeal: 0, allyHeal: 0,
                weaponSkills: new Map(), perSkill: new Map(), modelDps: 0, modelSelfHeal: 0, modelAllyHeal: 0, calibrated: false};
            if (b.arsenal != null) e.weaponSkills.set(1, b.arsenal.copy());
            simulateInto(b, e);
            return e;
        }
        var first = pass(b, new Map(), 0);
        var e = first.eval;
        if (first.needsSecond) {
            // cooldowns shortened by script events, and kills, need the rates and the damage of a first pass
            var killRate = foeHealth > 0 ? first.eval.dps / foeHealth : 0;
            e = pass(b, first.cdr, killRate).eval;
        }
        if (combat != null) calibrate(e);
        return e;
    }

    // ---------------------------------------------------------------- the fight simulation

    /** Damage and heals come from a simulated fight (buildcalc.sim.Sim running the skills' scripts). */
    public var useSim = true;
    /** Seconds of the model fight (two minutes): every skill with a cooldown up to two minutes is used in it, a slow stack (Nova's ultimate) is full. */
    public static var FIGHT = 120.0;
    public var lastSim:buildcalc.sim.Sim.SimResult = null;

    /**
     * Fights the training dummy with the build and puts its damage and heals per second into `e`.
     * The main weapon's skills beyond the hero's weapon skill slots: every choice is fought, the best kept.
     */
    /**
     * Self-check against the game (the build the hero wears): each effect's attribute part as the simulation
     * counts it and as the game does (HSkill.getStepEffectScaling on the hero), and the statuses the hero has
     * now against those the fight starts with (a permanent status counted twice would show here).
     */
    public function verify(b:Build):Void {
        var lines = [];
        try {
            var list = G.field(G.field(hero, "statuses"), "array");
            var n = G.len(list);
            var ids = [];
            for (i in 0...n) {
                var st = G.at(list, i);
                if (st != null) ids.push(G.str(G.field(G.field(st, "inf"), "id")) + "x" + G.str(G.field(st, "stacks")));
            }
            lines.push("statuses on the hero now: " + (ids.length == 0 ? "none" : ids.join(", ")));
        } catch (e:Dynamic) lines.push("statuses on the hero now: not read (" + Std.string(e) + ")");
        var env = new GameEnv(this, sums(b), itemPartCache);
        var sim = new buildcalc.sim.Sim(env);
        var specs:Array<buildcalc.sim.Sim.SkillSpec> = [for (s in sources(b)) {id: s.def.id, rank: s.rank, runes: s.runes, kind: s.kind, slot: s.slot, item: s.item}];
        sim.setup(specs);
        sim.run(0.01);
        lines.push("statuses the fight starts with: " + [for (s in sim.hero.statuses) s.info.id + "x" + s.stacks].join(", "));
        var stats = env.stats([]);
        var bad = 0, checked = 0;
        for (inst in sim.hero.skills) {
            var item:Items.Candidate = inst.item;
            for (st in inst.info.steps) for (e in st.effects) {
                if (e.kind != "Damage" && e.kind != "Heal" && e.kind != "Shield") continue;
                if (e.scaling.length == 0) continue;
                var ours = env.effectBase(inst, e, stats) - e.base;
                var game = 0.0;
                try {
                    var info = {inf: inst.info.inf, rank: inst.rank, maxRank: null, masteries: inst.runes, heroic: false};
                    game = G.num(G.callStatic("HSkill", "getStepEffectScaling", [info, e.raw, hero, null, null, item != null ? item.inf : null, null]));
                } catch (err:Dynamic) { lines.push("  " + inst.info.id + "." + st.id + ": game value not read (" + Std.string(err) + ")"); continue; }
                checked++;
                var off = Math.abs(ours - game) > Math.max(0.5, Math.abs(game) * 0.01);
                if (off) bad++;
                lines.push("  " + (off ? "MISMATCH " : "") + inst.info.id + "." + (st.id != "" ? st.id : "step" + st.index) + " " + e.kind + ": sim " + r2(ours) + ", game " + r2(game));
            }
        }
        DebugLog.line("self-check of effect values: " + checked + " checked, " + bad + " differ from the game
    " + lines.join("
    "));
    }

    /** Fights already run, by the build's skills (ids, ranks, runes, the items whose power they use): fight, weapon skills, timing attributes. */
    var fights = new Map<String, Array<{sim:buildcalc.sim.Sim, pick:Array<String>, timing:Map<String, Float>}>>();
    public var fightsRun = 0;
    public var fightsReplayed = 0;
    public var fightMs = 0.0;
    /** Why fights were run again for the same skills: the timing attribute that changed, how often. */
    public var refights = new Map<String, Int>();

    /**
     * Where each weapon skill (with a cooldown) goes in the attack chain: as soon as ready, or
     * before the chain's attack i. Chosen once per weapon and its skills (greedy, one skill at a time, by the fight's
     * damage and heal) and kept: a mace whose skill pays most two attacks before the combo is played that way.
     */
    var weaves = new Map<String, Map<String, Int>>();

    /**
     * The fight choices made once and kept (the place of each weapon skill in the attack chain, the weapon skills put
     * in the two slots), as data for the last result of a questionnaire: the next calculation of it starts with the same
     * choices, so a build is valued the same as before (they were made with the build valued first, the worn one).
     */
    public function exportChoices():Dynamic {
        return {weaves: [for (k => m in weaves) {k: k, v: [for (id => pos in m) {id: id, pos: pos}]}],
            picks: [for (k => ids in picks) {k: k, ids: ids}]};
    }

    public function importChoices(d:Dynamic):Int {
        var n = 0;
        if (d == null) return 0;
        var w:Dynamic = Reflect.field(d, "weaves");
        if (Std.isOfType(w, Array)) for (e in (w : Array<Dynamic>)) {
            var m = new Map<String, Int>();
            var v:Dynamic = Reflect.field(e, "v");
            if (Std.isOfType(v, Array)) for (x in (v : Array<Dynamic>)) m.set(Std.string(Reflect.field(x, "id")), Std.int(Reflect.field(x, "pos")));
            weaves.set(Std.string(Reflect.field(e, "k")), m);
            n++;
        }
        var p:Dynamic = Reflect.field(d, "picks");
        if (Std.isOfType(p, Array)) for (e in (p : Array<Dynamic>)) {
            var ids:Dynamic = Reflect.field(e, "ids");
            if (Std.isOfType(ids, Array)) { picks.set(Std.string(Reflect.field(e, "k")), [for (x in (ids : Array<Dynamic>)) Std.string(x)]); n++; }
        }
        return n;
    }
    /** The weapon skills chosen for the slots, by the weapon skills there are to choose from. */
    var picks = new Map<String, Array<String>>();

    /**
     * The player's priorities for the choices made inside a fight (the place of skills in the chain, which weapon skills
     * fill the slots): weights of damage and heal (Optimizer: 3 high … 1 low, 0.02 not important), each against the
     * first fight's value, as the optimizer's score does. Null: damage + heal.
     */
    public var fightWeights:Array<Float> = null;
    var fightBase:Array<Float> = null;
    /** The ranges of damage and heal (Optimizer.setSpans): once known, a fight's choices are scored by them. */
    public var fightSpans:Array<Float> = null;

    public function fightScore(r:buildcalc.sim.Sim.SimResult):Float {
        var heal = r.selfHeal + r.allyHeal;
        if (fightWeights == null) return r.dps + heal;
        if (fightSpans != null) return fightWeights[0] * r.dps / Math.max(1e-9, fightSpans[0]) + fightWeights[3] * heal / Math.max(1e-9, fightSpans[1]);
        if (fightBase == null) fightBase = [Math.max(1e-9, r.dps), Math.max(1e-9, heal)];
        return fightWeights[0] * r.dps / fightBase[0] + fightWeights[3] * heal / fightBase[1];
    }

    function runFight(env:GameEnv, specs:Array<buildcalc.sim.Sim.SkillSpec>):{sim:buildcalc.sim.Sim, result:buildcalc.sim.Sim.SimResult} {
        var sim = new buildcalc.sim.Sim(env);
        var t0 = haxe.Timer.stamp();
        sim.setup(specs);
        sim.run(FIGHT);
        fightMs += (haxe.Timer.stamp() - t0) * 1000;
        fightsRun++;
        return {sim: sim, result: sim.replay(env)};
    }

    function weaveAndFight(env:GameEnv, specs:Array<buildcalc.sim.Sim.SkillSpec>):{sim:buildcalc.sim.Sim, result:buildcalc.sim.Sim.SimResult} {
        // the main weapon's skills: their place in its chain (arsenal and class skills: as soon as ready)
        var weaponSkills = [for (sp in specs) if (sp.slot == 0 && sp.kind != "enchant") {
            var d = SkillData.get(sp.id);
            if (d != null && d.type == "WeaponSkill" && d.cooldown > 0) sp;
        }];
        var classSkills:Array<buildcalc.sim.Sim.SkillSpec> = [];
        var chainLength = 0;
        for (sp in specs) if (sp.slot == 0) { var d = SkillData.get(sp.id); if (d != null && ATTACKS.indexOf(d.type) >= 0) chainLength++; }
        // the weave depends on the weapon's attacks and skills, not on its enchantments (an augment's skill)
        var key = [for (sp in specs) if (sp.slot == 0 && sp.kind != "enchant") sp.id + ":" + sp.rank].join(",");
        var known = weaves.get(key);
        if (known != null || weaponSkills.length == 0 || chainLength < 2) {
            if (known != null) for (sp in specs) if (known.exists(sp.id)) sp.weave = known.get(sp.id);
            return runFight(env, specs);
        }
        function score(r:buildcalc.sim.Sim.SimResult):Float return fightScore(r);
        var best = runFight(env, specs), bestS = score(best.result);
        // two greedy passes: a skill's best place may change once another skill has moved
        for (pass in 0...(weaponSkills.length > 1 ? 2 : 1)) for (sp in weaponSkills) {
            var keep = sp.weave;
            for (pos in -1...chainLength) {
                if (pos == keep) continue;
                sp.weave = pos;
                var f = runFight(env, specs);
                var v = score(f.result);
                if (v > bestS + 1e-6) { bestS = v; best = f; keep = pos; }
            }
            sp.weave = keep;
        }
        var chosen = new Map<String, Int>();
        for (sp in weaponSkills.concat(classSkills)) chosen.set(sp.id, sp.weave);
        weaves.set(key, chosen);
        var shown = [for (sp in weaponSkills.concat(classSkills)) if (sp.weave >= 0) sp.id + " before attack " + (sp.weave + 1)];
        if (shown.length > 0) DebugLog.line("rotation: " + shown.join(", ") + " (" + key.split(",")[0].split(":")[0] + "…)");
        return best;
    }

    function simulateInto(b:Build, e:Eval):Void {
        var srcs = sources(b);
        var perm = sums(b);
        var env = new GameEnv(this, perm, itemPartCache);
        if (noUtility) srcs = [for (s in srcs) if (!isUtility(env, s)) s];
        var keys = [for (s in srcs) s.def.id + ":" + s.rank + ":" + s.runes.join("+") + ":" + s.slot + ":" + (s.item != null && s.item.powerRatio > 0 ? s.item.id : "")];
        keys.sort((x, y) -> x < y ? -1 : (x > y ? 1 : 0));
        var key = keys.join(",");
        var best:buildcalc.sim.Sim.SimResult = null, bestPick:Array<String> = null;
        // the same skills: the fight goes the same way unless an attribute it depends on (cooldowns, cast time…) changed
        var f = null;
        var known = fights.get(key);
        if (known != null) {
            var now = env.stats([]);
            var why = "";
            for (k in known) {
                var same = true;
                for (a => v in k.timing) if (Math.abs(now.get(a) - v) > 1e-9) { same = false; why = a; break; }
                if (same) { f = k; break; }
            }
            if (f == null && statsOnly) f = known[0];
            if (f == null) refights.set(why, (refights.exists(why) ? refights.get(why) : 0) + 1);
        }
        if (f != null) {
            best = f.sim.replay(env);
            bestPick = f.pick;
            fightsReplayed++;
        } else {
            // the weapon skill slots (ent.Hero.updateSkillCache: indices 0 and 1) take the main weapon's skills and the
            // off-hand's (a shield): the player picks which; every choice is fought
            var weapon = [for (s in srcs) if ((s.slot == 0 || s.slot == Items.OFFHAND) && s.def.type == "WeaponSkill") s];
            var choices:Array<Array<Src>> = [];
            var n = Std.int(Math.min(weaponSlots, weapon.length));
            // every choice of up to n skills (the player may leave a slot empty: a shield worn for its armour, its skill
            // not used); at least one when there are weapon skills
            function pick(start:Int, cur:Array<Src>):Void {
                if (cur.length > 0 || weapon.length == 0) choices.push(cur.copy());
                if (cur.length == n) return;
                for (i in start...weapon.length) { cur.push(weapon[i]); pick(i + 1, cur); cur.pop(); }
            }
            pick(0, []);
            // the same weapon skills to choose from: the choice made the first time is kept (each choice is a fight)
            var pickKey = [for (s in weapon) s.def.id + ":" + s.rank].join(",");
            var known = picks.get(pickKey);
            if (known != null && choices.length > 1) {
                var c = [for (s in weapon) if (known.indexOf(s.def.id) >= 0) s];
                if (c.length == known.length) choices = [c];
            }
            var bestScore = -1e30, bestSim:buildcalc.sim.Sim = null;
            for (c in choices) {
                var specs:Array<buildcalc.sim.Sim.SkillSpec> = [];
                for (s in srcs) {
                    if ((s.slot == 0 || s.slot == Items.OFFHAND) && s.def.type == "WeaponSkill" && c.indexOf(s) < 0) continue;
                    specs.push({id: s.def.id, rank: s.rank, runes: s.runes, kind: s.kind, slot: s.slot, item: s.item, weave: -1});
                }
                var fight = weaveAndFight(env, specs);
                var r = fight.result;
                var score = fightScore(r);
                // equal scores: the choice with more weapon skills (a slot left empty gives nothing; a skill the fight cannot value is no reason to leave it)
                if (score > bestScore + 1e-9 || (score >= bestScore - 1e-9 && bestPick != null && c.length > bestPick.length)) {
                    bestScore = Math.max(score, bestScore); best = r; bestPick = [for (s in c) s.def.id]; bestSim = fight.sim;
                }
            }
            if (bestPick != null && choices.length > 1) picks.set(pickKey, bestPick);
            if (bestSim != null) {
                var base = env.stats([]);
                if (!fights.exists(key)) fights.set(key, []);
                bestSim.compact();
                fights.get(key).push({sim: bestSim, pick: bestPick, timing: [for (k => _ in bestSim.timing) k => base.get(k)]});
                if (fightsRun <= 3) DebugLog.line("sim: the fight's course depends on " + [for (k => _ in bestSim.timing) k].join(", ") + "; " + bestSim.log.length + " hits logged");
            }
        }
        if (best == null) return;
        lastSim = best;
        var regen = Math.max(0, get(e.vals, "HealthRegen"));
        e.dps = best.dps;
        e.selfHeal = best.selfHeal + regen;
        e.allyHeal = best.allyHeal;
        e.axes[0] = e.dps;
        e.axes[3] = e.selfHeal + e.allyHeal;
        e.perSkill = new Map();
        for (id => v in best.damage) e.perSkill.set(id, {dmg: v / FIGHT, selfHeal: 0, allyHeal: 0});
        for (id => v in best.heal) {
            var o = e.perSkill.get(id);
            if (o == null) { o = {dmg: 0, selfHeal: 0, allyHeal: 0}; e.perSkill.set(id, o); }
            o.selfHeal += v / FIGHT;
        }
        e.weaponSkills.set(0, bestPick);
        e.modelDps = e.dps;
        e.modelSelfHeal = e.selfHeal;
        e.modelAllyHeal = e.allyHeal;
        if (report != null) {
            report.push("sim: " + FIGHT + " s fight, dps " + r2(best.dps) + ", self heal " + r2(best.selfHeal) + "/s, ally heal " + r2(best.allyHeal) + "/s");
            report.push("sim casts: " + [for (id => k in best.casts) id + " " + k].join(", "));
            if (best.resources != null && best.resources != "") report.push("sim resources at the end: " + best.resources);
            report.push("sim damage/s: " + [for (id => v in best.damage) id + " " + r2(v / FIGHT)].join(", "));
            report.push("sim heal/s: " + [for (id => v in best.heal) id + " " + r2(v / FIGHT)].join(", "));
            var miss = [for (k => v in best.missing) k + " x" + v];
            report.push("sim not handled: " + (miss.length == 0 ? "nothing" : miss.join("; ")));
        }
    }

    // ---------------------------------------------------------------- the hero's real fight

    var combat:Combat = null;
    var base:Map<String, SkillOut> = null;
    var baseDmg = 0.0;
    var baseSelf = 0.0;
    var baseAlly = 0.0;

    /**
     * Values builds by the hero's last real fight (the game's combat meter): each skill's measured damage
     * and heals per second × (model value of the skill in the build / model value now). Skills the fight
     * does not show but the build adds are counted by the model × (measured total / model total now).
     */
    public function useCombat(c:Combat, worn:Build):Void {
        if (c == null || !c.ok) { DebugLog.line("calibration: no fight recorded, the model values are shown as they are"); return; }
        combat = null;
        var e = evaluate(worn);
        base = e.perSkill;
        baseDmg = e.dps; baseSelf = e.selfHeal; baseAlly = e.allyHeal;
        combat = c;
        var lines = [];
        for (id => r in c.bySkill) {
            var m = base.get(id);
            lines.push(id + ": fight " + r2(r.dmg / c.duration) + "/" + r2(r.selfHeal / c.duration) + "/" + r2(r.allyHeal / c.duration)
                + " model " + (m == null ? "-" : r2(m.dmg) + "/" + r2(m.selfHeal) + "/" + r2(m.allyHeal)));
        }
        for (id => m in base) if (!c.bySkill.exists(id) && (m.dmg + m.selfHeal + m.allyHeal) > 0)
            lines.push(id + ": not in the fight, model " + r2(m.dmg) + "/" + r2(m.selfHeal) + "/" + r2(m.allyHeal));
        DebugLog.line("calibration: fight " + r2(c.dmg / c.duration) + " dps, " + r2(c.selfHeal / c.duration) + " self heal, " + r2(c.allyHeal / c.duration)
            + " ally heal per second; model now " + r2(baseDmg) + " / " + r2(baseSelf) + " / " + r2(baseAlly) + " (dmg/self/ally)\n    " + lines.join("\n    "));
    }

    function calibrate(e:Eval):Void {
        var t = combat.duration;
        function scaled(measured:Float, now:Float, then:Float, total:Float, totalNow:Float):Float {
            if (now > 1e-9) return measured * then / now;
            return measured * (totalNow > 1e-9 ? total / totalNow : 1);
        }
        var dmg = 0.0, self = 0.0, ally = 0.0;
        for (id => r in combat.bySkill) {
            var now = base.get(id), then = e.perSkill.get(id);
            dmg += scaled(r.dmg / t, now == null ? 0 : now.dmg, then == null ? 0 : then.dmg, e.modelDps, baseDmg);
            self += scaled(r.selfHeal / t, now == null ? 0 : now.selfHeal, then == null ? 0 : then.selfHeal, e.modelSelfHeal, baseSelf);
            ally += scaled(r.allyHeal / t, now == null ? 0 : now.allyHeal, then == null ? 0 : then.allyHeal, e.modelAllyHeal, baseAlly);
        }
        // skills the build adds (the fight could not show them): the model × the fight's ratio to the model now
        var kd = baseDmg > 1e-9 ? (combat.dmg / t) / baseDmg : 1;
        var ks = baseSelf > 1e-9 ? (combat.selfHeal / t) / baseSelf : 1;
        var ka = baseAlly > 1e-9 ? (combat.allyHeal / t) / baseAlly : 1;
        for (id => o in e.perSkill) if (!combat.bySkill.exists(id) && !base.exists(id)) {
            dmg += o.dmg * kd; self += o.selfHeal * ks; ally += o.allyHeal * ka;
        }
        e.dps = dmg; e.selfHeal = self; e.allyHeal = ally;
        e.axes[0] = dmg;
        e.axes[3] = self + ally;
        e.calibrated = true;
    }

    function pass(b:Build, cdrIn:Map<String, Float>, killRate:Float):{eval:Eval, cdr:Map<String, Float>, needsSecond:Bool} {
        var firstPass = !cdrIn.keys().hasNext() && killRate == 0;
        var srcs = sources(b);
        var have = new Map<String, Bool>();
        for (src in srcs) have.set(src.def.id, true);
        var perm = sums(b);
        vals = engine.evaluate(perm);
        buffed = vals;
        mods = [];
        for (src in srcs) for (m in src.def.mods) {
            if (m.rankMin > src.rank || (m.mastery != "" && src.runes.indexOf(m.mastery) < 0)) continue;
            if (m.needSkill != "" && !have.exists(m.needSkill)) continue;
            var value = Std.parseFloat(m.value);
            if (Math.isNaN(value)) {
                var x = src.def.v(m.value, src.rank, src.runes);
                value = x == null ? 0 : x;
            }
            mods.push({mod: m, value: value * m.sign, owner: src.def});
        }
        var cdMod = Math.max(0, 1 - get(vals, "CooldownReduction"));
        var castMod = Math.max(0.1, 1 - get(vals, "SpellCastTimeReduction"));
        var events:Array<Event> = [];
        var needsSecond = false;

        // ---- the attack chain of the main weapon: each of its attacks once, then its combo attack (ent.Hero.getNextAttackSkill)
        var plain:Array<Src> = [], combo:Src = null;
        for (src in srcs) if (src.slot == 0 && src.kind == "item" && ATTACKS.indexOf(src.def.type) >= 0) {
            if (src.def.type == "AttackCombo") combo = src else plain.push(src);
        }
        var chain:Array<Src> = [];
        for (p in plain) chain.push(p);
        if (combo != null) chain.push(combo);
        var chainTime = 0.0;
        for (c in chain) chainTime += c.def.duration > 0 ? c.def.duration : 0.5;

        // ---- active skills: by cooldown, or charged by script events
        var actives:Array<{src:Src, period:Float, castTime:Float}> = [];
        var weaponSkills = new Map<Int, Array<Src>>();
        for (src in srcs) {
            if (!isActive(src.def)) continue;
            if (src.def.type == "WeaponSkill" && src.slot == 0) {
                if (!weaponSkills.exists(src.slot)) weaponSkills.set(src.slot, []);
                weaponSkills.get(src.slot).push(src);
                continue;
            }
            actives.push({src: src, period: 0, castTime: 0});
        }
        var chosenWeapon = new Map<Int, Array<String>>();
        for (slot => list in weaponSkills) {
            list.sort((x, y) -> {
                var a = quickCast(x) / Math.max(1, x.def.cooldown), c = quickCast(y) / Math.max(1, y.def.cooldown);
                a > c ? -1 : (a < c ? 1 : 0);
            });
            var n = Std.int(Math.min(weaponSlots, list.length));
            chosenWeapon.set(slot, [for (i in 0...n) list[i].def.id]);
            for (i in 0...n) actives.push({src: list[i], period: 0, castTime: 0});
        }
        function cdrFor(src:Src):Float {
            var r = 0.0;
            if (cdrIn.exists(src.def.id)) r += cdrIn.get(src.def.id);
            if (src.def.type == "WeaponSkill" && cdrIn.exists("weapons")) r += cdrIn.get("weapons");
            return r;
        }
        // cooldown skills first; then the attack chain in the time left; then skills charged by events of both
        var castFrac = 0.0;
        for (a in actives) {
            if (a.src.def.charges.length > 0) continue;
            var castT = a.src.def.durationWith(a.src.runes) * castMod;
            if (castT <= 0) castT = 0.5 * castMod;
            var cd = a.src.def.cooldownWith(a.src.runes) * cdMod / (1 + cdrFor(a.src));
            a.period = Math.max(cd, castT);
            a.castTime = castT;
            castFrac += castT / a.period;
        }
        var chainRate = 0.0, comboRate = 0.0;
        var weaponCasts = 0.0, mainWeaponCasts = 0.0, arsenalCasts = 0.0, classCasts = 0.0, skillCasts = 0.0;
        function rates():Void {
            var frac = Math.min(0.8, castFrac);
            chainRate = chainTime > 0 ? (1 - frac) / chainTime : 0;
            comboRate = combo != null ? chainRate : 0;
            weaponCasts = 0; mainWeaponCasts = 0; arsenalCasts = 0; classCasts = 0; skillCasts = 0;
            for (a in actives) if (a.period > 0) {
                var r = 1 / a.period;
                skillCasts += r;
                if (a.src.def.type == "WeaponSkill") { weaponCasts += r; if (a.src.slot == 0) mainWeaponCasts += r; }
                if (a.src.slot == 1) arsenalCasts += r;
                if (a.src.def.type == "ClassSkill") classCasts += r;
            }
        }
        rates();
        function castRate(f:Filter, owner:Src):Float {
            if (f.self) { for (a in actives) if (a.src == owner && a.period > 0) return 1 / a.period; return 0; }
            if (f.combo) return comboRate;
            if (f.fromArsenal) return arsenalCasts;
            if (f.weaponSkill) return f.notArsenal ? mainWeaponCasts : weaponCasts;
            if (f.classSkill) return classCasts;
            if (f.anySkill) return skillCasts;
            return skillCasts + chainRate * chain.length;
        }
        var prayerRate = 0.0;
        for (round in 0...2) {
            for (a in actives) {
                if (a.src.def.charges.length == 0) continue;
                var r = 0.0;
                for (c in a.src.def.charges) if (c.rankMin <= a.src.rank && (c.mastery == "" || a.src.runes.indexOf(c.mastery) >= 0))
                    r += castRate(c.filter, a.src);
                var castT = a.src.def.durationWith(a.src.runes) * castMod;
                if (castT <= 0) castT = 0.5 * castMod;
                var cd = a.src.def.cooldownWith(a.src.runes) * cdMod;
                a.period = r > 0 ? Math.max(Math.max(cd, castT), 1 / r) : 0;
                a.castTime = castT;
            }
            castFrac = 0;
            prayerRate = 0;
            for (a in actives) if (a.period > 0) {
                castFrac += a.castTime / a.period;
                if (a.src.def.charges.length > 0) prayerRate += 1 / a.period;
            }
            rates();
        }

        // ---- first-level events and hit counts
        var dmgHits = 0.0, healHits = 0.0, attackHits = 0.0, skillHits = 0.0, weaponHits = 0.0;
        var hitsBySkill = new Map<String, Float>();
        function count(src:Src, steps:Array<Step>, rate:Float, dur:Float):Void {
            var d = hitsOf(src, steps, "Damage", dur) * rate, h = (hitsOf(src, steps, "Heal", dur) + hitsOf(src, steps, "Shield", dur)) * rate;
            dmgHits += d;
            healHits += h;
            hitsBySkill.set(src.def.id, (hitsBySkill.exists(src.def.id) ? hitsBySkill.get(src.def.id) : 0) + d + h);
            if (ATTACKS.indexOf(src.def.type) >= 0) attackHits += d; else skillHits += d + h;
            if (src.def.type == "WeaponSkill") weaponHits += d + h;
        }
        var applied:Array<{id:String, self:Bool, rate:Float, parent:Src}> = [];
        function statusesOf(src:Src, steps:Array<Step>, rate:Float):Void {
            for (s in steps) {
                if (s.status != "") applied.push({id: s.status, self: s.statusSelf, rate: rate, parent: src});
                for (e in s.effects) if (e.status != "") applied.push({id: e.status, self: s.hitFilter != 1, rate: rate, parent: src});
            }
        }
        for (c in chain) {
            var steps = castSteps(c);
            events.push({src: c, steps: steps, rate: chainRate, chain: 1, dyn: 0, dynFrom: "", what: "attack", heal: "both", ticks: false});
            count(c, steps, chainRate, 0);
            statusesOf(c, steps, chainRate);
        }
        for (a in actives) {
            if (a.period <= 0) continue;
            var steps = castSteps(a.src);
            var rate = 1 / a.period;
            events.push({src: a.src, steps: steps, rate: rate, chain: 1, dyn: 0, dynFrom: "", what: "cast", heal: "both", ticks: false});
            count(a.src, steps, rate, 0);
            statusesOf(a.src, steps, rate);
        }
        var enemyStatusRate = 0.0;
        for (ap in applied) if (!ap.self) enemyStatusRate += ap.rate;

        // ---- procs of every skill of the build
        var critChance = Math.min(1, Math.max(0, get(vals, "CritChance")));
        function triggerRate(trigger:String, f:Filter, every:String, chance:String, owner:Src):Float {
            var r = 0.0;
            switch (trigger) {
                case "damageHit":
                    if (f.ally) r = healHits; // hits on allies: the heals and buffs that reach them
                    else if (f.skill != "") r = hitsBySkill.exists(f.skill) ? hitsBySkill.get(f.skill) : 0;
                    else if (f.combo) r = comboRate;
                    else if (f.attacks) r = attackHits;
                    else if (f.weaponSkill) r = weaponHits;
                    else if (f.anySkill) r = skillHits;
                    else r = dmgHits;
                case "ownHit": r = hitsBySkill.exists(owner.def.id) ? hitsBySkill.get(owner.def.id) : 0;
                case "healHit": r = f.skill != "" ? (hitsBySkill.exists(f.skill) ? hitsBySkill.get(f.skill) : 0) : healHits;
                case "cast": r = castRate(f, owner);
                case "timer":
                    var t = owner.def.v(every, owner.rank, owner.runes);
                    r = t != null && t > 0 ? 1 / t : 0;
                case "statusInflict": r = enemyStatusRate;
                case "kill":
                    r = killRate;
                    if (firstPass && foeHealth > 0) needsSecond = true;
                case "prayer": r = prayerRate;
                default:
            }
            if (f.crit) r *= critChance;
            if (chance != "") {
                var c = owner.def.v(chance, owner.rank, owner.runes);
                if (c != null) r *= Math.min(1, c);
            }
            return r;
        }
        var deferred:Array<{src:Src, p:ScriptProc, scale:Float, cap:Float}> = [];
        var late = false;
        function procOne(src:Src, p:ScriptProc, scale:Float, cap:Float):Void {
            if (p.trigger == "always") {
                for (st in p.statuses) applied.push({id: st.id, self: st.self, rate: -1, parent: src});
                return;
            }
            var rate = triggerRate(p.trigger, p.filter, p.every, p.chance, src) * scale;
            if (cap >= 0) rate = Math.min(rate, cap);
            if (rate <= 0) return;
            var steps = [];
            for (id in p.steps) {
                var s = src.def.step(id);
                if (s != null && src.def.stepActive(s, src.rank, src.runes)) steps.push(s);
            }
            var chainN = 1.0;
            if (p.chain != "") {
                var x = src.def.v(p.chain, src.rank, src.runes);
                if (x != null && x > 0) chainN = x;
            }
            var dyn = 0.0;
            if (p.dyn != "") {
                var x = src.def.v(p.dyn, src.rank, src.runes);
                if (x != null) dyn = x;
            }
            events.push({src: src, steps: steps, rate: rate, chain: chainN, dyn: dyn, dynFrom: p.filter.skill, what: "proc " + p.trigger,
                heal: p.chain != "" ? "ally" : "both", ticks: false});
            statusesOf(src, steps, rate);
            for (st in p.statuses) applied.push({id: st.id, self: st.self, rate: rate, parent: src});
        }
        function procsOf(src:Src, scale:Float, cap:Float):Void {
            for (p in src.def.procs) {
                if (p.rankMin > src.rank || (p.mastery != "" && src.runes.indexOf(p.mastery) < 0)) continue;
                if (p.needSkill != "" && !have.exists(p.needSkill)) continue;
                if (!late && p.filter.skill != "" && (p.trigger == "damageHit" || p.trigger == "healHit") && !hitsBySkill.exists(p.filter.skill)) {
                    deferred.push({src: src, p: p, scale: scale, cap: cap});
                    continue;
                }
                procOne(src, p, scale, cap);
            }
        }
        for (src in srcs) procsOf(src, 1, -1);

        // ---- statuses: uptime, their buffs, their effects per application and their own procs
        var buffSums = perm.copy();
        var seen = 0;
        var i = 0;
        var counted = events.length;
        for (round in 0...2) {
            while (i < applied.length && seen < 300) {
                var ap = applied[i++];
                seen++;
                var sd = SkillData.get(ap.id);
                if (sd == null) continue;
                var src:Src = {def: sd, rank: ap.parent.rank, runes: ap.parent.runes, kind: "status", item: ap.parent.item, slot: ap.parent.slot};
                var dur = sd.durationWith(ap.parent.runes);
                var permanent = ap.rate < 0 || dur < 0;
                // a status counts at most maxStacks times at once: re-applying it refreshes it
                var rate = permanent ? 0 : (dur > 0 ? Math.min(ap.rate, sd.maxStacks / dur) : ap.rate);
                var stacks = permanent ? 1.0 : Math.min(sd.maxStacks, ap.rate * dur);
                if (ap.self) for (a in sd.affixes) if (sd.affixActive(a, src.rank, ap.parent.runes)) buffSums.affix(index, a.ref, a.attr, a.val, stacks);
                var steps = castSteps(src);
                if (permanent) {
                    // a permanent status: its looping steps tick for ever, the others run once (nothing per second)
                    for (s in steps) {
                        var tick = sd.num(s.tick, src.rank, src.runes, 0);
                        if (tick <= 0) continue;
                        events.push({src: src, steps: [s], rate: 1 / Math.max(tick, s.targetCd), chain: 1, dyn: 0, dynFrom: "", what: "status tick",
                            heal: ap.self ? "self" : "both", ticks: true});
                    }
                } else if (steps.length > 0 && rate > 0) {
                    events.push({src: src, steps: steps, rate: rate, chain: 1, dyn: 0, dynFrom: "", what: "status", heal: ap.self ? "self" : "both", ticks: false});
                }
                // the status's own reactions while it is up (a status that consumes itself: once per application)
                var consumed = sd.consumes && !(sd.consumeUnless != "" && have.exists(sd.consumeUnless));
                if (sd.procs.length > 0) procsOf(src, Math.min(1, stacks), consumed && !permanent ? ap.rate : -1);
            }
            if (round == 1 || deferred.length == 0) break;
            // hits of the procs and statuses, then the procs that react to them
            for (k in counted...events.length) {
                var ev = events[k];
                count(ev.src, ev.steps, ev.rate * ev.chain, ev.src.def.durationWith(ev.src.runes));
            }
            late = true;
            var later = deferred;
            deferred = [];
            for (d in later) procOne(d.src, d.p, d.scale, d.cap);
        }
        buffed = engine.evaluate(buffSums);

        // ---- cooldowns shortened by script events (used by the second pass)
        var cdrOut = new Map<String, Float>();
        for (src in srcs) for (c in src.def.cdrs) {
            if (c.rankMin > src.rank || (c.mastery != "" && src.runes.indexOf(c.mastery) < 0)) continue;
            if (c.needSkill != "" && !have.exists(c.needSkill)) continue;
            var rate = triggerRate(c.trigger, c.filter, "", c.chance, src);
            var t = src.def.v(c.time, src.rank, src.runes);
            if (rate <= 0 || t == null || t <= 0) continue;
            var target = c.target == "self" ? src.def.id : c.target;
            cdrOut.set(target, (cdrOut.exists(target) ? cdrOut.get(target) : 0) + rate * t);
            if (firstPass) needsSecond = true;
        }

        // ---- values
        var damage = 0.0, selfHeal = 0.0, allyHeal = 0.0;
        var perSkill = new Map<String, SkillOut>();
        function addOut(id:String, d:Float, s:Float, a:Float):Void {
            var o = perSkill.get(id);
            if (o == null) { o = {dmg: 0, selfHeal: 0, allyHeal: 0}; perSkill.set(id, o); }
            o.dmg += d; o.selfHeal += s; o.allyHeal += a;
        }
        var perHit = new Map<String, Float>();
        var dynEvents = [];
        for (ev in events) {
            if (ev.dyn > 0) { dynEvents.push(ev); continue; }
            var d = 0.0, hs = 0.0, ha = 0.0, n = 0.0;
            var statusDur = ev.src.def.durationWith(ev.src.runes);
            for (s in ev.steps) {
                // a permanent status's tick: the value of one tick (a spread value divided over its ticks)
                var times = ev.ticks ? (s.spread ? 1 / Math.max(1, stepTicks(ev.src.def, s, ev.src.rank, ev.src.runes, statusDur)) : 1)
                    : stepValueTimes(ev.src.def, s, ev.src.rank, ev.src.runes, statusDur);
                var who = healTarget(s, ev.heal == "ally", ev.heal == "self");
                for (e in s.effects) {
                    if (e.kind != "Damage" && e.kind != "Heal" && e.kind != "Shield") continue;
                    if (e.kind == "Damage" && s.ignoreMain) continue; // one target: an area that skips it hits nobody
                    var x = effectValue(e, ev.src, effectBase(e, ev.src, buffed));
                    d += x.dmg * times;
                    if (who != "ally") hs += x.heal * times;
                    if (who != "self") ha += x.heal * times;
                    n += times;
                }
            }
            var k = ev.rate * ev.chain;
            damage += d * k;
            selfHeal += hs * ev.rate;
            allyHeal += ha * k;
            addOut(ev.src.def.id, d * k, hs * ev.rate, ha * k);
            if (n > 0) perHit.set(ev.src.def.id, (d + Math.max(hs, ha)) / n);
            if (report != null && (d + hs + ha) > 0) report.push(ev.src.def.id + " [" + ev.src.kind + ", " + ev.what + "] " + r2(ev.rate) + "/s x" + r2(ev.chain)
                + ": dmg " + r2(d * k) + "/s, self heal " + r2(hs * ev.rate) + "/s, ally heal " + r2(ha * k) + "/s");
        }
        for (ev in dynEvents) {
            var from = ev.dynFrom != "" && perHit.exists(ev.dynFrom) ? perHit.get(ev.dynFrom) : 0;
            var d = 0.0, h = 0.0;
            for (s in ev.steps) for (e in s.effects) {
                var base = e.dynVal > 0 && e.scaling.length == 0 ? from * ev.dyn : effectBase(e, ev.src, buffed);
                var x = effectValue(e, ev.src, base);
                d += x.dmg;
                h += x.heal;
            }
            damage += d * ev.rate * ev.chain;
            selfHeal += h * ev.rate;
            allyHeal += h * ev.rate;
            addOut(ev.src.def.id, d * ev.rate * ev.chain, h * ev.rate, h * ev.rate);
            if (report != null && (d + h) > 0) report.push(ev.src.def.id + " [" + ev.src.kind + ", " + ev.what + ", from " + ev.dynFrom + "] "
                + r2(ev.rate) + "/s: dmg " + r2(d * ev.rate) + "/s, heal " + r2(h * ev.rate) + "/s");
        }
        var regen = Math.max(0, get(buffed, "HealthRegen"));
        selfHeal += regen;
        addOut("HealthRegen", 0, regen, 0);

        // ---- defense: armour and magic armour against foes of the hero's level, dodge, damage taken
        var magicTaken = (1 - reduction(get(buffed, "MagicArmor"))) * Math.max(0, 1 - get(buffed, "MagicReduction"));
        var taken = 0.5 * (1 - reduction(get(buffed, "Armor"))) + 0.5 * magicTaken;
        taken *= Math.max(0, 1 - get(buffed, "Resilience")) * Math.max(0.05, get(buffed, "DamageTakenModifier"))
            * Math.max(0.05, 1 - Math.min(0.95, get(buffed, "DodgeChance")));
        if (report != null) {
            report.push("rotation: chain " + [for (c in chain) c.def.id].join(">") + " " + r2(chainTime) + "s, " + r2(chainRate) + "/s; casts "
                + [for (a in actives) if (a.period > 0) a.src.def.id + " every " + r2(a.period) + "s"].join(", ") + "; cast time " + Math.round(Math.min(0.8, castFrac) * 100) + "%");
            report.push("rates/s: damage hits " + r2(dmgHits) + ", heal hits " + r2(healHits) + ", attacks " + r2(attackHits) + ", combos " + r2(comboRate)
                + ", skill casts " + r2(skillCasts) + ", prayers " + r2(prayerRate) + ", enemy statuses " + r2(enemyStatusRate) + ", kills " + r2(killRate));
            report.push("cooldown cut per second: " + [for (k => v in cdrIn) k + " " + r2(v)].join(", "));
            report.push("script modifiers: " + [for (m in mods) m.owner.id + ":" + m.mod.stat + (m.value >= 0 ? "+" : "") + r2(m.value)
                + (m.mod.filter.skill != "" ? "@" + m.mod.filter.skill : "") + (m.mod.own ? "@own" : "")].join(", "));
            report.push("weapon skills: " + [for (s => l in chosenWeapon) s + "=" + l.join("+")].join(", "));
            for (src in srcs) if (src.def.unknown.length > 0) report.push("not valued: " + src.def.id + " (" + src.def.unknown.join(",") + ")");
        }
        if (b.arsenal != null) chosenWeapon.set(1, [for (id in b.arsenal) id]);
        var eval:Eval = {axes: [damage, 1 / Math.max(0.01, taken), get(vals, "MaxHealth"), selfHeal + allyHeal, critValue(vals)], vals: vals, buffed: buffed,
            dps: damage, selfHeal: selfHeal, allyHeal: allyHeal, weaponSkills: chosenWeapon, perSkill: perSkill,
            modelDps: damage, modelSelfHeal: selfHeal, modelAllyHeal: allyHeal, calibrated: false};
        return {eval: eval, cdr: cdrOut, needsSecond: needsSecond};
    }

    static function r2(v:Float):String return Std.string(Math.round(v * 100) / 100);
}
