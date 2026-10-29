package farmer;

import farmer.GameAccess as G;
import farmer.Services.ServiceJob;

/**
 * The farming bot. It works through the plan of the window:
 *  1. resources: ore and plants (walks to the node and gathers it), monsters that drop the wanted items (kills them);
 *  2. leveling: kills monsters of the hero's own level until the wanted level;
 *  3. the bag: when it is full the recycler (chosen qualities) or, with "empty the bag", the bank is used, from anywhere;
 *  4. the end: resources go to the bank (if asked), then the teleportation stone takes the hero to the saved city and it waits.
 * It runs the dodge of the old auto-dodge on the way (AutoDodge), picks up its loot, and flies by obelisk over long ways.
 */
class Bot {
    public var running = false;
    public var finished = false;
    /** The bot's own skill use passes the "hold skills while dodging" hooks. */
    public var ownCast = false;

    var nav = new Nav();
    var plan:FarmPlan;
    var app:Dynamic;
    var hero:Dynamic;
    var message = "";
    var changed = false;
    var nextThink = 0.0;
    var counts:Map<String, Int> = new Map();
    var countsReady = false;
    var job:ServiceJob = null;
    var jobFailedAt = -100.0;
    var scrapFailedAt = -1000.0;
    var sellFailedAt = -1000.0;
    var phase = "";
    var finishStage = 0;
    var finishAt = 0.0;
    var noHome = false;

    // the current target
    var targetKind = ""; // "node", "mob", ""
    var target:Dynamic = null;
    var targetSince = 0.0;
    var lockedFoe:Dynamic = null;
    var blacklist:Map<String, Float> = new Map();
    /** Monsters the way-finder found no way to: not chosen for a while, not blacklisted (the hero may come to them later). */
    var skipped:Map<String, Float> = new Map();
    /** Places no way led to (a plateau): the monsters standing there are not chosen for a while, one after another would each cost a try. */
    var deadAreas:Array<{x:Float, y:Float, until:Float}> = [];
    var lastInteract = 0.0;
    var lastAttack = 0.0;
    /** The Attack key is held down while a monster is in reach: the game chains the combo hits itself from a held key. */
    var attackDown = false;
    var attackResumeAt = 0.0;
    /** After a node broke: its drops are on their way, nothing else is started before this time. */
    var lootWait = 0.0;
    var bagWarnAt = -100.0;
    var skipBank = false; // the bank is done (or full) while gathering: recycling is next
    var seekKey = "";
    var seekSince = 0.0;
    var defendAt = -100.0;
    var defendKey = "";
    /** Where the hero died: monsters and hunting grounds within DEATH_RADIUS of it are avoided for a while (too strong a place for this hero). */
    var deathSpots:Array<{x:Float, y:Float, until:Float}> = [];
    static inline var DEATH_RADIUS = 40.0; // (130 m for 15 min blacklisted a whole hunting ground after a death: 28.10)

    function nearDeath(x:Float, y:Float, now:Float):Bool return false; // (no avoiding the place of a death: farming through deaths, the user's order, 28.10)
    function nearDeathOld(x:Float, y:Float, now:Float):Bool {
        for (d in deathSpots) if (now < d.until && (d.x - x) * (d.x - x) + (d.y - y) * (d.y - y) < DEATH_RADIUS * DEATH_RADIUS) return true;
        return false;
    }
    var idleTick = -100.0;
    var idleSince = -1.0;
    var fightKey = "";
    var leashSince = -1.0;
    var leashLogAt = -100.0;
    var lastFightAt = 0.0;
    var fightAx = Math.NaN;
    var fightAy = Math.NaN;
    var unfinished:Dynamic = null;
    var lenientTarget = false;
    var lastNoTarget = 0.0;
    var lastNote = 0.0;
    var wasDead = false;
    var lastBasicSeen = 0.0;
    var comboSince = 0.0;
    var lastFightLog = 0.0;
    /** The reach map with the glider's descents is asked for (nothing was left to go to on foot), and a target that needs one. */
    var needDescents = false;
    var descentNoteAt = -100.0;
    var targetDescent = false;
    var lastCut = 0;
    var progressBest = 1e9;
    var progressAt = 0.0;
    var progressKey = "";
    var progressHp = 1e12;
    var lastSeenLog = -100.0;
    var gotoX:Null<Float> = null;
    var gotoY:Null<Float> = null;
    var gotoArrive = 2.0;
    var gotoZ = Math.NaN;

    static inline var LOOT_SEEK = 16.0;
    /** The most levels below the hero a monster may be to be hunted (while leveling), and what each level below costs in score metres: a monster of the hero's own
        level is preferred to a lower one that is nearer by this much, but the hero does not run the map over for the last few levels of difference. */
    static inline var MIN_DIFF = -1;
    static inline var LOWER_COST = 450.0;
    static inline var MAX_DIFF = 1;
    /** A monster this many levels above the hero is not fought, nor anything within STRONG_RANGE of it. */
    static inline var STRONG_DIFF = 3;
    static inline var STRONG_RANGE = 20.0;
    /** Metres a monster of another level (±1) counts farther than one of the hero's own level. */
    static inline var OFF_LEVEL_COST = 150.0;
    /** A fight starts inside this radius around where the hero first struck: farther from that spot (a dodge, a fleeing foe) the foe is let go. */
    static inline var LEASH = 40.0;
    /** A monster this much above or below the hero is on another tier (a plateau, a gorge): the way there is long or none, and the walk along the edge circles. */
    static inline var MAX_DZ = 8.0;
    /** A monster farther than this (score metres) is not picked while hunting drops: the roaming goes there first. */
    static inline var FAR_TARGET = 300.0;
    /** A monster this close to the hero is fought before going on with a node. */
    static inline var THREAT_RANGE = 9.0;
    /** A ready skill waits at most this long for the weapon's combo series to end. */
    static inline var COMBO_WAIT = 2.5;
    /** A monster that has the hero as its target is fought from this far. */
    static inline var AGGRO_RANGE = 45.0;
    /** Monsters this close to the node that is to be gathered are cleared first. */
    static inline var NODE_GUARD = 8.0;
    /** A foe in reach that loses no health for this long is let go (hits into the void). */
    static inline var NO_DAMAGE_TIME = 8.0;
    /** The most a target may differ in height from the hero to be hit from where the hero stands. */
    static inline var HIT_HEIGHT = 3.5;
    /** Monsters this near each other are one group: a lone one is fought before a group (the group's others join the fight). */
    static inline var GROUP_RANGE = 10.0;
    static inline var GROUP_COST = 120.0;
    /** A group counts for at most this many others (past that it is simply a group). */
    static inline var GROUP_MAX = 4;

    public function new() {}

    // ---- control ----

    public function start():Void {
        running = true;
        lastFightAt = haxe.Timer.stamp();
        finished = false;
        finishStage = 0;
        countsReady = false;
        job = null;
        blacklist = new Map(); deadAreas = [];
        target = null;
        targetKind = "";
        AutoDodge.enabled = true;
        message = Locale.f("stTravel");
        Log.t("mod", "BOT START plan " + (plan == null ? "?" : plan.toJson()) + (hero == null ? "" : " hero L" + G.integer(G.field(hero, "_level")) + " glider " + Nav.hasGlider(hero)));
    }

    public function stop():Void {
        if (running) Log.t("mod", "BOT STOP (" + message + ")");
        running = false;
        AutoDodge.enabled = false;
        AutoDodge.botDriven = false;
        nav.stop();
        releaseAttack();
        kiting = false;
        engaged = false;
        target = null;
        targetKind = "";
        if (job != null && app != null) job.close(app);
        job = null;
        message = Locale.f("idle");
    }

    public function reset():Void {
        if (running) stop();
        finished = false;
    }

    public function say(text:String):Void message = text;

    public function statusText():String return message;

    public function consumeChanged():Bool {
        var c = changed;
        changed = false;
        return c;
    }

    /** The bot's skills and held Attack key wait only while the dodge is actually running (the dodge's own pause after a run would let a fight crawl). */
    public function holdingSkills():Bool return running && (AutoDodge.castOnTheRun ? AutoDodge.castRunning() : AutoDodge.dodging());

    public function moving():Bool return running && (AutoDodge.dodging() || (hero != null && nav.wantsMove(hero)));

    /** In place of the keyboard's direction: the dodge's run first, then the way to the target. */
    public function steer(controller:Dynamic, input:Dynamic):Dynamic {
        if (!running) return null;
        var dodge = AutoDodge.steer(controller, input);
        if (dodge != null) return dodge;
        var h = G.field(controller, "unit");
        if (h == null || !nav.active) return null;
        try G.set(controller, "skillRequiresReinputToMove", false) catch (_:Dynamic) {}
        var d = null;
        try d = nav.direction(h, haxe.Timer.stamp()) catch (e:Dynamic) { Log.w("steer error: " + Std.string(e)); }
        return d == null ? null : G.create("h3d.VectorImpl", [d.x, d.y, 0.0]);
    }

    // ---- every frame ----

    public function update(app:Dynamic, hero:Dynamic, plan:FarmPlan, now:Float, dt:Float):Void {
        this.app = app;
        this.hero = hero;
        this.plan = plan;
        Probe.app = app;
        AutoDodge.botDriven = running;
        // the fight zone binds the dodge too (see LEASH)
        if (running && targetKind == "mob" && target != null && !Math.isNaN(fightAx) && now - lastFightAt < 20) { AutoDodge.zoneX = fightAx; AutoDodge.zoneY = fightAy; AutoDodge.zoneR = LEASH - 1; }
        else AutoDodge.zoneR = -1;
        if (!running) { releaseAttack(); return; }
        try AutoDodge.update(hero, now) catch (error:Dynamic) Log.err("dodge update", error);
        try Hazard.refreshTraps(hero, now) catch (error:Dynamic) Log.err("traps", error);
        nav.update(hero, now);
        try watchTwitch(now) catch (error:Dynamic) Log.err("twitch", error);
        try heartbeat(now) catch (error:Dynamic) Log.err("heartbeat", error);
        if (now < nextThink) return;
        nextThink = now + 0.1;
        try think(now) catch (error:Dynamic) {
            Log.w("[Farmer] think: " + Std.string(error) + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
            if (job != null) { try job.close(app) catch (_:Dynamic) {} job = null; jobFailedAt = now; message = "error: " + Std.string(error); }
        }
    }

    // ---- twitching ----

    var twitchTrail:Array<{t:Float, x:Float, y:Float}> = [];
    var twitchLogAt = -100.0;
    var twitchTotal = 0;

    /**
     * The measure of "the hero twitches": from the hero's real positions (ten a second, the last 4 s) the number of times it turned back on
     * itself (a step of 12 cm or more, then one that goes against it). Four reversals in 4 s are logged with what was steering.
     */
    function watchTwitch(now:Float):Void {
        var x = G.number(G.field(hero, "posx")), y = G.number(G.field(hero, "posy"));
        if (twitchTrail.length == 0 || now - twitchTrail[twitchTrail.length - 1].t >= 0.1) twitchTrail.push({t: now, x: x, y: y});
        while (twitchTrail.length > 0 && now - twitchTrail[0].t > 4.0) twitchTrail.shift();
        if (now - twitchLogAt < 4.0 || twitchTrail.length < 10) return;
        var reversals = 0;
        var px = 0.0, py = 0.0, have = false;
        for (i in 1...twitchTrail.length) {
            var vx = twitchTrail[i].x - twitchTrail[i - 1].x, vy = twitchTrail[i].y - twitchTrail[i - 1].y;
            var len = Math.sqrt(vx * vx + vy * vy);
            if (len < 0.12) continue;
            if (have && (vx * px + vy * py) / (len * Math.sqrt(px * px + py * py)) < -0.3) reversals++;
            px = vx; py = vy; have = true;
        }
        if (reversals < 4) return;
        twitchLogAt = now;
        twitchTotal++;
        Log.t("fight", "TWITCH: " + reversals + " reversals in 4 s at " + Math.round(x) + "," + Math.round(y) + " | dodge " + AutoDodge.dodging() + " nav " + nav.active + " kiting " + kiting + " engaged " + engaged
            + " target " + targetKind + " | total " + twitchTotal);
    }

    // ---- the log's status beat ----

    var beatAt = 0.0;

    /** Every second (twice a second in a fight): where the hero is and everything the bot is doing, in one line. */
    function heartbeat(now:Float):Void {
        var fighting = targetKind == "mob";
        if (now - beatAt < (fighting ? 0.5 : 1.0)) return;
        beatAt = now;
        var hp = G.number(G.call("ent.Unit", "get_health", hero), -1), max = G.number(G.call("ent.Unit", "get_maxHealth", hero), -1);
        var active = G.call("ent.GameObject", "getActiveSkill", hero);
        var tgt = "-";
        if (target != null) {
            var inf = G.field(target, "inf");
            tgt = targetKind + " " + G.s(G.field(inf, "id") != null ? G.field(inf, "id") : G.field(G.field(target, "gatherInf"), "id")) + (targetKind == "mob" ? " L" + G.integer(G.field(target, "_level")) : "")
                + " d=" + Math.round(Nav.distance(hero, G.number(G.field(target, "posx")), G.number(G.field(target, "posy"))) * 10) / 10
                + " dz=" + Math.round((G.number(G.field(target, "posz")) - G.number(G.field(hero, "posz"))) * 10) / 10
                + (targetKind == "mob" ? " hp " + Math.round(G.number(G.call("ent.Unit", "get_health", target), -1)) + "/" + Math.round(G.number(G.call("ent.Unit", "get_maxHealth", target), -1)) : "");
        }
        Log.t("beat", "pos " + Math.round(G.number(G.field(hero, "posx")) * 10) / 10 + "," + Math.round(G.number(G.field(hero, "posy")) * 10) / 10 + "," + Math.round(G.number(G.field(hero, "posz")) * 10) / 10
            + " hp " + Math.round(hp) + "/" + Math.round(max) + " L" + G.integer(G.field(hero, "_level")) + " | " + (message == "" ? "-" : message) + " | target " + tgt
            + " | " + nav.status(hero, now) + " | dodge " + AutoDodge.dodging() + " glide " + (G.field(hero, "gliding") == true)
            + " | combo " + G.integer(G.field(hero, "attackComboCount")) + " held " + attackDown + " skill " + (active == null ? "-" : G.s(G.field(active, "kind")))
            + " | free " + Services.freeSlots(hero) + " traps " + Hazard.trapCount() + (job != null ? " job " + job.kind : "")
            + " focus " + windowFocused());
    }

    static function windowFocused():Bool {
        try return G.call("hxd.Window", "get_isFocused", G.staticCall("hxd.Window", "getInstance", [])) == true catch (_:Dynamic) return false;
    }

    function think(now:Float):Void {
        if (!Catalog.build()) return; // the data sheets are not loaded yet
        if (G.call("ent.GameObject", "isDead", hero) == true) {
            if (!wasDead) Log.t("mod", "HERO DIED at " + Math.round(G.number(G.field(hero, "posx"))) + "," + Math.round(G.number(G.field(hero, "posy"))) + "," + Math.round(G.number(G.field(hero, "posz")))
                + " (target " + targetKind + ", " + nav.status(hero, now) + "): respawning");
            if (!wasDead) deathSpots.push({x: G.number(G.field(hero, "posx")), y: G.number(G.field(hero, "posy")), until: now + 240}); // (the ground it fell on is left alone for 4 min)
            wasDead = true;
            nav.stop();
            target = null;
            targetKind = "";
            message = "";
            try { G.call("client.PlayerController", "respawn", G.current("client.PlayerController", "inst"), [null]); } catch (_:Dynamic) {}
            return;
        }
        if (wasDead) { wasDead = false; nextThink = now + 3; return; }
        if (G.field(hero, "inCutscene") == true) return;

        var held = false;
        try held = watchdog(now, plan.targetLevel > 0 && G.integer(G.field(hero, "_level")) < plan.targetLevel) catch (error:Dynamic) Log.err("watchdog", error);
        if (held) return;
        try hitLog(now) catch (error:Dynamic) Log.err("hitlog", error);
        updateCounts();
        Services.noteStation(hero, now);
        if (job == null && leaveWater(now)) return;
        Nodes.remember(hero, now);
        if (Nodes.scanning() && wantsGather() && Hunt.onWorld(hero)) Nodes.scanStep(15); // (the whole map's nodes are read from the chunk files in the background)
        // once, at the start: a jump on the spot, to learn how high the hero jumps (the planner's jump height)
        if (target == null && gotoX == null && nav.calibrateJump(hero, now)) return;

        if (gotoX != null) {
            if (Nav.distance(hero, gotoX, gotoY) < gotoArrive + 1) { gotoX = null; nav.stop(); message = "arrived"; return; }
            if (nav.gaveUp && !nav.walkingToObelisk()) { gotoX = null; nav.stop(); message = "unreachable"; Log.t("bot", "goto: the spot cannot be reached"); return; }
            moveTo(gotoX, gotoY, gotoArrive, now, gotoZ);
            return;
        }
        if (job != null) { runJob(now); return; }
        if (returnTo != null) { runReturn(now); return; }
        var level = G.integer(G.field(hero, "_level"));
        var leveling = plan.targetLevel > 0 && level < plan.targetLevel;
        var workLeft = plan.resourcesLeft() || leveling;
        if (!workLeft) { finish(now); return; }
        finishStage = 0;

        if (Services.freeSlots(hero) > 1) skipBank = false;
        if (Services.freeSlots(hero) <= 1 && now - jobFailedAt > 30 && now - scrapFailedAt > 240) {
            // gathering: first the bank (its window opens from anywhere), then, if the bag is still full, recycle the chosen gear
            // (the recycler needs a walk to its station: the server only opens it within reach); leveling: only recycle, else fight on
            if (plan.resourcesLeft() && !skipBank) { startJob("bank", now); return; }
            if (now - sellFailedAt > 120 && Services.sellCandidates(hero, plan, new Map()).length > 0) { startJob("sell", now); return; }
            if (plan.recycle && anyQuality() && Services.hasScrapGear(hero, plan)) { startJob("scrap", now); return; }
            warnBagFull(now); // a full bag does not stop the run: it keeps fighting (drops are left on the ground)
        }
        farm(now, leveling, level);
    }

    var lastHp = -1.0;
    var hitLogAt = 0.0;

    /** The hero lost health: who is after it (every foe within 60 m that has it as its target, plus the nearest others) and what the bot is doing about it. */
    function hitLog(now:Float):Void {
        var hp = G.number(G.call("ent.Unit", "get_health", hero), -1);
        var before = lastHp;
        lastHp = hp;
        if (before < 0 || hp >= before - 0.5 || now - hitLogAt < 0.4) return;
        hitLogAt = now;
        var rows:Array<{d:Float, text:String}> = [];
        for (e in G.fastArray(G.field(G.field(hero, "layer"), "units"))) {
            if (e == null || e == hero || !G.isA(e, "ent.Foe") || G.field(e, "removed") == true) continue;
            if (G.call("ent.GameObject", "isDead", e) == true || G.field(e, "dying") == true) continue;
            var d = Nav.distance(hero, G.number(G.field(e, "posx")), G.number(G.field(e, "posy")));
            if (d > 60) continue;
            var aggro = false;
            try aggro = G.call("ent.Unit", "getTarget", e) == hero catch (_:Dynamic) {}
            if (!aggro && d > 15) continue;
            rows.push({d: d, text: G.s(G.field(G.field(e, "inf"), "id")) + " L" + G.field(e, "_level") + " d=" + Math.round(d) + " dz=" + Math.round(G.number(G.field(e, "posz")) - G.number(G.field(hero, "posz")))
                + (aggro ? " AGGRO" : "") + (e == target ? " =TARGET" : "") + (blacklisted(e, now) ? " blacklisted" : "") + (isUntouchable(e, now) ? " untouchable" : "")});
        }
        rows.sort((a, b) -> a.d < b.d ? -1 : a.d > b.d ? 1 : 0);
        var threat = nearbyThreat(now);
        Log.t("hit", "hp " + Math.round(before) + " -> " + Math.round(hp) + " | target " + (target == null ? "-" : G.s(G.field(G.field(target, "inf"), "id"))) + " " + targetKind + " engaged " + engaged
            + " | defend choice " + (threat == null ? "none" : G.s(G.field(G.field(threat, "inf"), "id"))) + " | foes: " + [for (r in rows.slice(0, 8)) r.text].join("; "));
    }

    /** Out of combat (nothing fought, nothing hitting the hero, no bag job): the time to change gear. */
    public function calm(now:Float):Bool {
        if (hero == null || job != null || engaged || kiting || AutoDodge.dodging()) return false;
        // (a far target to walk to is no reason to keep the bag's better gear off; a foe that fights the hero or stands near is)
        return nearbyThreat(now) == null;
    }

    function anyQuality():Bool {
        for (q in plan.recycleQualities) if (q) return true;
        return false;
    }

    // ---- counting what was gathered ----

    function updateCounts():Void {
        var now:Map<String, Int> = new Map();
        for (stack in Services.stacks(Services.bag(hero))) {
            var id = Services.itemId(G.field(stack, "item"));
            if (!plan.isPicked(false, id) && !plan.isPicked(true, id)) continue;
            now.set(id, (now.exists(id) ? now.get(id) : 0) + G.integer(G.field(stack, "count")));
        }
        if (countsReady) {
            for (id => n in now) {
                var before = counts.exists(id) ? counts.get(id) : 0;
                if (n > before) { plan.credit(id, n - before); changed = true; }
            }
        }
        counts = now;
        countsReady = true;
    }

    // ---- bag services ----

    function startJob(kind:String, now:Float):Void {
        nav.stop();
        target = null;
        targetKind = "";
        job = new ServiceJob(kind);
        if (kind == "scrap") { tripOrigin = {x: G.number(G.field(hero, "posx")), y: G.number(G.field(hero, "posy")), z: G.number(G.field(hero, "posz"))}; tripStoned = false; tripWaitUntil = 0; tripSince = now; }
        Log.t("svc", "job " + kind + " started, free slots " + Services.freeSlots(hero));
        message = Locale.f(kind == "bank" ? "stBank" : "stRecycle");
    }

    // ---- the recycling trip: home stone, obelisks, the nearest recycler, and back to where the hero left the farm ----
    var tripOrigin:Null<{x:Float, y:Float, z:Float}> = null;
    var tripStoned = false;
    var tripWaitUntil = 0.0;
    var tripSince = 0.0;
    var returnTo:Null<{x:Float, y:Float, z:Float}> = null;
    var returnSince = 0.0;
    var returnStoned = false;
    var returnWaitUntil = 0.0;

    /** The job is over (done or failed): a recycling trip sends the hero back to where it was. */
    function jobEnded(kind:String, now:Float):Void {
        if (kind != "scrap" || tripOrigin == null) return;
        returnTo = tripOrigin;
        tripOrigin = null;
        returnSince = now;
        returnStoned = !tripStoned;
        returnWaitUntil = 0;
        nav.stop();
        Log.t("svc", "back to the farm: " + Math.round(returnTo.x) + "," + Math.round(returnTo.y));
    }

    /** Goes back to where the recycling trip began (by obelisk when far, fighting back when attacked on the way). */
    function runReturn(now:Float):Void {
        var r = returnTo;
        message = Locale.f("stTravel");
        if (Nav.distance(hero, r.x, r.y) < 30 || now - returnSince > 900 || !Hunt.onWorld(hero)) {
            Log.t("svc", "back at the farm (" + Math.round(Nav.distance(hero, r.x, r.y)) + " m from the old place)");
            returnTo = null;
            nav.stop();
            return;
        }
        var foe = nearbyThreat(now);
        if (foe != null) {
            if (target != foe) { target = foe; targetKind = "mob"; lockedFoe = null; targetSince = now; nav.stop(); }
            workMob(now, false);
            return;
        } else if (targetKind == "mob") { target = null; targetKind = ""; releaseAttack(); }
        if (now < returnWaitUntil) return; // (the home stone is being cast / the hero is carried)
        // the recycler stands on a platform with no way down on foot: the stone carries the hero to the obelisk, which flies on to the farm
        if (!returnStoned) {
            returnStoned = true;
            if (useHomeStone()) {
                stoneAt = now;
                stoneTimes.push(now);
                nav.stop();
                nav.forgetObeliskTrouble();
                returnWaitUntil = now + 14;
                Log.t("svc", "back to the farm: home stone used (the farm is " + Math.round(Nav.distance(hero, r.x, r.y)) + " m away)");
                return;
            }
        }
        nav.goalZ = r.z;
        if (nav.gaveUp && !nav.walkingToObelisk()) { Log.t("svc", "no way back to the old place: the farm goes on from here"); nav.gaveUp = false; returnTo = null; nav.stop(); return; }
        if (!nav.travel(hero, r.x, r.y, now)) nav.go(r.x, r.y, 3, now);
    }

    function runJob(now:Float):Void {
        if (job.walkTo != null) { // the recycler is out of the server's reach: walk up to it first
            var w = job.walkTo;
            if (now - tripSince > 1200) { Log.t("svc", "job " + job.kind + ": the trip took too long"); job.close(app); var k0 = job.kind; job = null; jobFailedAt = now; scrapFailedAt = now; jobEnded(k0, now); return; }
            if (now < tripWaitUntil) return; // (the home stone is being cast / the hero is carried)
            // the home stone first: it takes the hero to the city, from where the obelisks lead on; used when the recycler is far (the stone is cast once per trip)
            if (job.kind == "scrap" && !tripStoned) {
                tripStoned = true;
                if (useHomeStone()) {
                    stoneAt = now;
                    stoneTimes.push(now);
                    nav.stop();
                    nav.forgetObeliskTrouble();
                    tripWaitUntil = now + 14;
                    Log.t("svc", "recycling trip: home stone used (the recycler is " + Math.round(Nav.distance(hero, w.x, w.y)) + " m away)");
                    return;
                }
                Log.t("svc", "recycling trip: no home stone in the bag, going by obelisk / on foot");
            }
            var spot2 = job.kind == "scrap" ? Services.stationSpot(hero) : null; // (the nearest recycler, after the stone it may be another one)
            if (spot2 != null && Services.scrapStation(hero) == null) { w = {x: spot2.x, y: spot2.y}; job.walkTo = w; }
            message = Locale.f("stTravel");
            var foe = nearbyThreat(now);
            if (foe != null) { // attacked on the way: fight back first
                if (target != foe) { target = foe; targetKind = "mob"; lockedFoe = null; targetSince = now; nav.stop(); }
                workMob(now, false);
                return;
            } else if (targetKind == "mob") { target = null; targetKind = ""; releaseAttack(); }
            nav.goalZ = Math.NaN;
            // (the recycler opens from anywhere once its station is loaded: the walk to its remembered place ends as soon as it appears)
            var stationNear = Services.scrapStation(hero);
            if (Nav.distance(hero, w.x, w.y) <= job.walkArrive || (job.walkArrive > 3 && stationNear != null)
                || (stationNear != null && Nav.distance(hero, G.number(G.field(stationNear, "posx")), G.number(G.field(stationNear, "posy"))) <= 3)) { nav.stop(); job.retry(); return; }
            if (nav.gaveUp && !nav.walkingToObelisk()) { // no way to the recycler from here: the trip is dropped for a while
                nav.gaveUp = false;
                nav.stop();
                Log.t("svc", "job " + job.kind + ": no way to the recycler");
                job.close(app);
                job = null;
                jobFailedAt = now;
                scrapFailedAt = now;
                jobEnded("scrap", now);
                return;
            }
            if (!nav.travel(hero, w.x, w.y, now)) nav.go(w.x, w.y, 1.4, now);
            return;
        }
        var r = job.step(app, hero, plan, now);
        if (r == "run") return;
        var kind = job.kind;
        job = null;
        countsReady = false; // what left the bag is not "lost" progress
        Log.t("svc", "job " + kind + ": " + r);
        jobEnded(kind, now);
        if (r == "done") {
            if (Services.freeSlots(hero) <= 1) {
                if (kind == "bank") skipBank = true; // the bank took what it could: recycling is next
                else jobFailedAt = now;
            }
            return;
        }
        jobFailedAt = now;
        if (kind == "sell") sellFailedAt = now;
        if (kind == "scrap") scrapFailedAt = now; // (the recycler is in the city: a failed trip is not made again at once)
        message = r.substr(5);
        if (kind == "bank") { skipBank = true; jobFailedAt = -100; } // the bank is full or failed: recycling is next
        if (Services.freeSlots(hero) <= 1 && !(kind == "bank" && plan.recycle && anyQuality() && Services.hasScrapGear(hero, plan))) warnBagFull(now);
    }

    /** Tells about the full bag at most once a minute; the bot goes on. */
    function warnBagFull(now:Float):Void {
        if (now - bagWarnAt < 60) return;
        bagWarnAt = now;
        say(Locale.f("bagFull"));
        Log.t("svc", "bag full, going on");
    }

    // ---- the end of a run ----

    function finish(now:Float):Void {
        nav.stop();
        target = null;
        targetKind = "";
        switch (finishStage) {
            case 0:
                finishStage = 1;
                if (plan.clearBag && Services.bankCandidates(hero).length > 0) { startJob("bank", now); return; }
            case 1:
                finishStage = 2;
                finishAt = now;
                message = Locale.f("stHome");
                if (noHome || !useHomeStone()) { message = Locale.f("noStone"); finishStage = 3; }
                return;
            case 2:
                if (now - finishAt < 8) return;
                finishStage = 3;
            default:
        }
        if (finishStage >= 3) {
            running = false;
            finished = true;
            AutoDodge.enabled = false;
            if (message != Locale.f("noStone")) message = Locale.f("stDone");
        }
    }

    var wetSince = -1.0;
    var leaveAt = -100.0;

    /**
     * The hero stands in water and no way is being walked: it makes for the nearest dry ground at once (breath runs out under water; the 26.10 log has it
     * standing in a pool for a minute after the way on was given up). True while it is on its way out.
     */
    function leaveWater(now:Float):Bool {
        if (!Hazard.heroInLiquid(hero)) { wetSince = -1; return false; }
        if (wetSince < 0) wetSince = now;
        if (nav.active && !nav.gaveUp) { message = Locale.f("stTravel"); return true; } // the way out (or on) is walked first, nothing else is started in the water: a fight there is lost to the breath
        if (now - leaveAt < 1.5) return true;
        leaveAt = now;
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy")), hz = G.number(G.field(hero, "posz"));
        var tx = target != null ? G.number(G.field(target, "posx")) : hx, ty = target != null ? G.number(G.field(target, "posy")) : hy;
        var best:Null<{x:Float, y:Float}> = null;
        var bestScore = Math.POSITIVE_INFINITY;
        for (r in [3.0, 5.0, 8.0, 12.0, 17.0, 24.0]) {
            for (i in 0...16) {
                var a = i * Math.PI / 8;
                var px = hx + Math.cos(a) * r, py = hy + Math.sin(a) * r;
                var z = NavGrid.fineZ(px, py, hz + 6);
                if (!Math.isFinite(z) || z - hz > 16 || Hazard.wetCell(px, py, z, 0.8)) continue; // (the bank of a pool stands well above its floor)
                var score = r * 3 + Nav.distance(hero, px, py) * 0 + Math.sqrt((px - tx) * (px - tx) + (py - ty) * (py - ty)) * 0.05;
                if (score < bestScore) { bestScore = score; best = {x: px, y: py}; }
            }
            if (best != null) break;
        }
        if (best == null) { Log.t("nav", "in the water for " + Math.round(now - wetSince) + " s and no dry ground within 24 m"); return false; }
        Log.t("nav", "in the water (" + Math.round(now - wetSince) + " s): out to the dry ground at " + Math.round(best.x) + "," + Math.round(best.y));
        nav.goalZ = Math.NaN;
        nav.noCliff = false;
        nav.go(best.x, best.y, 1.5, now);
        return true;
    }

    function useHomeStone():Bool {
        for (stack in Services.stacks(Services.bag(hero))) {
            var item = G.field(stack, "item");
            if (Services.itemId(item) == "TeleportationStone") {
                try { G.call("st.Item", "requestUse", item, [hero]); return true; } catch (_:Dynamic) {}
            }
        }
        return false;
    }

    // ---- choosing and working a target ----

    var stoneAt = -1000.0;

    // ---- no loop of flights, no standing still ----
    /** Until this time the hero does not fly by obelisk; it fights what lives near, down to GRIND_DIFF levels below it. */
    var grindUntil = 0.0;
    static inline var GRIND_DIFF = -1;
    /** Grounds no way led to (the flight landed on a plateau the spot lies beyond, a pocket): not chosen again for a long time, whatever wipes the sweep's memory. */
    var deadGround:Map<Int, Float> = new Map();
    /** Foes that took no damage from the hero for a long time (under the ground, behind a wall, immune): left alone even when they have the hero as target. */
    var untouchable:Map<String, Float> = new Map();
    var stoneTimes:Array<Float> = [];

    function minDiff():Int return haxe.Timer.stamp() < grindUntil ? GRIND_DIFF : MIN_DIFF;

    /** The sweep's memory with the dead grounds kept (they are wiped by nothing but their time). */
    function resetVisited(now:Float):Void {
        roamVisited = new Map();
        for (c => until in deadGround) if (until > now) roamVisited.set(c, until);
    }

    function killDeadGround(now:Float, ground:Int):Void {
        for (c in Hunt.around(ground, 6)) { deadGround.set(c, now + 2400); roamVisited.set(c, now + 2400); }
    }

    function isUntouchable(e:Dynamic, now:Float):Bool {
        if (G.isA(e, "ent.Foe")) return false; // (no black list of monsters at all - the user's order, 28.10)
        var until = untouchable.get(key(e));
        return until != null && now < until;
    }

    /** The terrain's height at (x, y) seen from just above the hero's height, NaN when it cannot be read. */
    function surfaceAt(x:Float, y:Float, hz:Float):Float {
        return try G.number(G.call("world.World", "getZ", G.current("world.World", "inst"), [x, y, hz + 2.2, null, null]), Math.NaN) catch (_:Dynamic) Math.NaN;
    }

    /** A monster far below the ground at its place (a burrow, a cave under the map): no spell reaches it, nor can the hero get there. */
    function underground(e:Dynamic):Bool {
        var ez = G.number(G.field(e, "posz"));
        var hz = G.number(G.field(hero, "posz"));
        if (ez > hz - 3) return false;
        var surface = surfaceAt(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), hz);
        return Math.isFinite(surface) && ez < surface - 6;
    }

    var trail:Array<{t:Float, x:Float, y:Float}> = [];
    var trailAt = 0.0;
    var trapStrikes = 0;
    var trapAt = -1000.0;
    var trapX = Math.NaN;
    var trapY = Math.NaN;

    /**
     * The hero must never be held in one place. Every second its place is noted; if in 45 s it never left a circle of 8 m (a hero that stands, that runs
     * into a wall, that circles in a pit, that is stuck in a pond) and no fight wears a foe down, everything it was doing is dropped, the place is marked
     * dead and a new way is looked for; the second time at the same place, or at once after 15 s in water, the home stone is used.
     * It runs before everything else the bot does (the water, a goto, a service job), so nothing can keep it from running.
     */
    function watchdog(now:Float, leveling:Bool):Bool {
        var x = G.number(G.field(hero, "posx")), y = G.number(G.field(hero, "posy"));
        var fighting = (engaged && target != null && now - progressAt < 20) || now - lastFightAt < 8;
        var dead = false;
        try dead = G.call("ent.GameObject", "isDead", hero) == true catch (_:Dynamic) {}
        var flying = false;
        try flying = G.call("ent.Hero", "isFlyingToObelisk", hero) == true catch (_:Dynamic) {}
        // (gathering waits for the nodes to grow back standing: only a hero that has something to do - a target, a ground to walk to, leveling - is watched)
        var idleOk = !leveling && target == null && roamKey < 0 && job == null;
        if (dead || flying || fighting || idleOk) { trail = []; trailAt = now; return false; }
        if (now - trailAt >= 1.0) {
            trailAt = now;
            trail.push({t: now, x: x, y: y});
            while (trail.length > 0 && now - trail[0].t > 46) trail.shift();
        }
        if (trail.length < 10) return false;
        var wet = false;
        try wet = Hazard.heroInLiquid(hero) catch (_:Dynamic) {}
        var window = wet ? 15.0 : 45.0;
        var minX = x, maxX = x, minY = y, maxY = y, first = now;
        for (p in trail) {
            if (now - p.t > window) continue;
            if (p.t < first) first = p.t;
            minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x);
            minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y);
        }
        if (now - first < window - 1.5 || Math.max(maxX - minX, maxY - minY) >= (wet ? 4.0 : 8.0)) return false;
        // held: the same place as the last strike counts again, a new place starts over
        if (!Math.isNaN(trapX) && Math.abs(x - trapX) < 25 && Math.abs(y - trapY) < 25 && now - trapAt < 400) trapStrikes++; else trapStrikes = 1;
        trapX = x; trapY = y; trapAt = now;
        trail = [];
        var what = "no target";
        if (target != null) what = "target " + targetKind + " " + (try G.s(G.field(G.field(target, "inf"), "id")) catch (_:Dynamic) "?");
        Log.w("WATCHDOG: the hero has not left a " + (wet ? "4" : "8") + " m circle for " + Math.round(window) + " s" + (wet ? " (in the water)" : "") + " at " + Math.round(x) + "," + Math.round(y) + " (" + what + ", roam ground " + roamKey + ", " + message + "), strike " + trapStrikes + ": everything is dropped");
        if (target != null) {
            blacklist.set(key(target), now + 180);
            untouchable.set(key(target), now + 180);
            if (targetKind == "mob") deadAreas.push({x: G.number(G.field(target, "posx")), y: G.number(G.field(target, "posy")), until: now + 180});
        }
        if (roamKey >= 0) killDeadGround(now, roamKey);
        // the flight that brought the hero here led into a trap: that obelisk is not flown to again
        nav.banLastLanding(now, 300);
        target = null; targetKind = ""; engaged = false; gotoX = null;
        roamKey = -1; carrotX = Math.NaN; leaving = false;
        nav.gaveUp = false;
        nav.stop();
        releaseAttack();
        nextThink = now;
        if (wet || trapStrikes >= 2) {
            stoneAt = Math.min(stoneAt, now - 1000); // (this is no ordinary idle: the stone is used now)
            // (the stone's cast is cut by any move: nothing else is started this tick, and idleStone holds the bot for 14 s)
            if (!idleStone(now, "held in one place: " + (wet ? "in the water" : "strike " + trapStrikes))) Log.w("WATCHDOG: no home stone to use");
        }
        return true;
    }

    /** Four flights by obelisk or home stone in fifteen minutes and no fight meanwhile: they lead nowhere. The hero stops flying for a quarter of an hour and fights what is near. */
    function grindCheck(now:Float):Void {
        nav.flights = [for (t in nav.flights) if (now - t < 900) t];
        stoneTimes = [for (t in stoneTimes) if (now - t < 900) t];
        nav.noFly = false; // (no GRIND: the hero never stops flying nor drops to lower monsters - it ran about a level-15 land for hours, 28.10)
        if (now - lastFightAt < 240 || now - grindNoteAt < 900) return;
        if (nav.flights.length + stoneTimes.length >= 4) {
            grindNoteAt = now;
            Log.w("flights: " + nav.flights.length + " by obelisk and " + stoneTimes.length + " home stones in 15 minutes without a fight (the own level is still hunted)");
        }
    }
    var grindNoteAt = -1000.0;
    var closedSince = -1.0;

    /** The hero sits where nothing can be done (a closed gorge, an island): the home stone takes it to the city, from where the obelisks lead on. True when it was used. */
    function idleStone(now:Float, why:String):Bool {
        if (now - stoneAt < (now < grindUntil ? 600 : 150)) return false;
        stoneAt = now;
        var used = useHomeStone();
        Log.t("bot", "STUCK (" + why + "): home stone " + (used ? "used" : "not in the bag"));
        if (!used) return false;
        stoneTimes.push(now);
        message = Locale.f("stHome");
        nav.stop();
        nav.forgetObeliskTrouble();
        target = null;
        targetKind = "";
        roamKey = -1;
        resetVisited(now);
        blacklist = new Map(); deadAreas = [];
        idleSince = -1;
        nextThink = now + 14;
        return true;
    }

    var levelZoneLevel = -1;
    var levelZoneLo = 0;
    var levelZoneSet:Map<String, Bool> = null;

    /** The zones where monsters of the hero's level (up to +2) live, from the game's unit sheet and spawner tables: the whole map is searched with them, not just the zones the map calls that level. */
    function levelZones(level:Int):Map<String, Bool> {
        if (levelZoneLevel != level || levelZoneSet == null || levelZoneLo != minDiff()) {
            levelZoneLevel = level;
            levelZoneLo = minDiff();
            var units = [for (u in Catalog.unitsOfLevels(level + levelZoneLo, level + MAX_DIFF)) u];
            levelZoneSet = Hunt.zonesOf(units);
            var names = [for (z in levelZoneSet.keys()) z];
            names.sort(Reflect.compare);
            Log.t("hunt", "monsters of level " + (level + levelZoneLo) + ".." + (level + MAX_DIFF) + ": " + units.length + " kinds, living in " + names.length + " zones: " + names.slice(0, 40).join(" "));
        }
        return levelZoneSet;
    }

    /** Every opened obelisk is out of reach on foot (the hero sits in a gorge or on a ledge): the home stone takes the hero to its city. */
    function strandedStone(now:Float):Bool {
        if (!nav.stranded) return false;
        nav.stranded = false;
        if (now - stoneAt < 300) return false;
        stoneAt = now;
        var used = useHomeStone();
        Log.t("bot", "STRANDED (no obelisk can be walked to from here): home stone " + (used ? "used" : "not in the bag"));
        if (used) {
            stoneTimes.push(now);
            message = Locale.f("stHome");
            nav.stop();
            nav.forgetObeliskTrouble();
            target = null;
            targetKind = "";
            roamKey = -1;
            blacklist = new Map(); deadAreas = [];
            nextThink = now + 14;
        }
        return used;
    }

    function farm(now:Float, leveling:Bool, level:Int):Void {
        // (in the air on the way to an obelisk nothing is chosen: the flight lasts half a minute, and a target picked then is lost on landing)
        var inAir = false;
        try inAir = G.call("ent.Hero", "isFlyingToObelisk", hero) == true catch (_:Dynamic) {}
        if (inAir) {
            if (target != null) { target = null; targetKind = ""; engaged = false; }
            message = Locale.f("stTravel");
            return;
        }
        grindCheck(now);
        if (strandedStone(now)) return;
        if (target != null && !targetValid(now, leveling)) {
            var lostId = "";
            try lostId = G.s(G.field(G.field(target, "inf"), "id")) catch (_:Dynamic) {}
            var why = G.field(target, "removed") == true ? "removed (killed or gone)" : (G.call("ent.GameObject", "isDead", target) == true || G.field(target, "dying") == true) ? "dead (killed)" : nav.gaveUp ? "unreachable" : "no longer wanted/timeout";
            Log.t("bot", "target " + targetKind + " " + lostId + " lost: " + why + " after " + Math.round(now - targetSince) + " s");
            if (targetKind == "node") lootWait = now + 1.2; // the node broke: what it dropped is on its way
            target = null;
            targetKind = "";
            nav.stop();
            releaseAttack();
        }
        if (target == null || targetKind == "node") {
            // a monster at the hero's feet is fought first: running from it (the dodge) and back to the node would go on for ever
            var threat = nearbyThreat(now);
            if (threat != null) {
                lastFightAt = now;
                Log.w("defending against " + G.s(G.field(G.field(threat, "inf"), "id")) + " at " + Math.round(Nav.distance(hero, G.number(G.field(threat, "posx")), G.number(G.field(threat, "posy")))) + " m");
                target = threat; targetKind = "mob"; lockedFoe = null; targetSince = now; defendKey = key(threat);
                nav.stop();
            }
        }
        if (targetKind == "mob" && target != null && now - defendAt > (engaged ? 0.6 : 1.0)) {
            // an enemy hitting the hero while it walks to (or fights) another one: that one first (walking on past it under fire is what made the dodge
            // twitch in short runs and the monsters gather into a crowd behind the hero; fighting on at a foe that has not even noticed the hero
            // while another one beats it was the "forgets to hit what attacks" of the 26.10 log)
            defendAt = now;
            var attacker = nearbyThreat(now);
            if (attacker != null && attacker != target && (!engaged || now - targetSince > 1.5)) {
                var toTarget = Nav.distance(hero, G.number(G.field(target, "posx")), G.number(G.field(target, "posy")));
                var toAttacker = Nav.distance(hero, G.number(G.field(attacker, "posx")), G.number(G.field(attacker, "posy")));
                var tHp = G.number(G.call("ent.Unit", "get_health", target), 1), tMax = G.number(G.call("ent.Unit", "get_maxHealth", target), 1);
                var finishing = engaged && tMax > 0 && tHp / tMax < 0.25 && toTarget <= combatRange() + REACH_HOLD; // (a foe nearly dead in reach is finished first)
                var margin = engaged ? 6.0 : 3.0; // (two foes at the hero's feet stand about as near: swapping between them hit neither - the 26.10 deaths)
                if (hurt(target) && toTarget <= 12) finishing = true; // a foe already hurt and near is finished first, whoever else is about
                var unnoticed = aggroOnHero(attacker) && !aggroOnHero(target) && toAttacker <= toTarget + 2;
                if (!finishing && (toAttacker + margin < toTarget || unnoticed)) {
                    Log.t("bot", "defending against " + G.s(G.field(G.field(attacker, "inf"), "id")) + " at " + Math.round(toAttacker) + " m instead of the target at " + Math.round(toTarget) + " m" + (unnoticed ? " (the target has not noticed the hero)" : ""));
                    if (hurt(target)) unfinished = target; // (it is gone back to once the attacker is down)
                    target = attacker; targetKind = "mob"; lockedFoe = null; targetSince = now; defendKey = key(attacker);
                    engaged = false;
                    nav.stop();
                }
            }
        }
        // a long time in a pit (a closed region) with no fight: the home stone, not a wander
        // (the minute is counted from the first moment the hero stands in a closed region, not from the last fight)
        if (nav.inClosedRegion(hero, now)) { if (closedSince < 0) closedSince = now; } else closedSince = -1;
        if (leveling && closedSince >= 0 && now - closedSince > 60 && now - lastFightAt > 60 && now - stoneAt > 150 && idleStone(now, "a minute in a closed region (pit) with no fight")) return;
        if (target == null && unfinished != null) {
            var back = unfinished;
            unfinished = null;
            try {
                if (G.field(back, "removed") != true && G.call("ent.GameObject", "isDead", back) != true && G.field(back, "dying") != true
                    && G.number(G.call("ent.Unit", "get_health", back), 1) > 0 && Nav.distance(hero, G.number(G.field(back, "posx")), G.number(G.field(back, "posy"))) < 40) {
                    target = back; targetKind = "mob"; lockedFoe = null; targetSince = now;
                    Log.t("bot", "back to the foe left unfinished: " + G.s(G.field(G.field(back, "inf"), "id")));
                }
            } catch (_:Dynamic) {}
        }
        if (target == null) {
            // what lies on the ground is taken first (the pick-up itself is Loot.update's)
            if (seekLoot(now)) return;
            if (now < lootWait) { nav.stop(); message = Locale.f("stLoot"); return; }
            // what ground the hero can walk to from here is worked out first (a moment): no monster or node is chosen that no way leads to
            if (nav.ensureReach(hero, now, needDescents)) { message = Locale.f("stTravel"); return; }
            pickTarget(now, leveling, level, needDescents);
            if (target == null && !needDescents && lastCut > 0) {
                // nothing on the ground the hero can walk to: the ground below, reached by the glider, is looked at next
                needDescents = true;
                if (now - descentNoteAt > 20) { descentNoteAt = now; Log.w(lastCut + " candidates are out of reach on foot: looking at the ground the glider reaches"); }
                return;
            }
            needDescents = false;
            if (target == null && leveling && roam(now, level, 2, null, levelZones(level), true)) return;
            // the map has no ground of the hero's level at all (the top zones are below it): the nearest lower monsters (up to 3 below) are better than none.
            // While such ground exists the hero keeps going to it, by obelisk or on foot, however long it takes - never settles for low monsters near by
            if (target == null && leveling && Hunt.onWorld(hero) && !Hunt.groundExists(level, 2)) pickTarget(now, leveling, level, needDescents, true);
            else if (target == null && leveling && !Hunt.onWorld(hero)) pickTarget(now, leveling, level, needDescents, true); // (a dungeon has no zone map: its monsters are what there is)
            if (target == null && !leveling && wantsGather() && nodeRoam(now)) return;
            if (target == null && !leveling && huntRoam(now, level)) return;
            if (target == null) {
                // nothing to do right now: wait for nodes to respawn. A minute of it and the hero is stuck somewhere (a gorge, an island): the home stone
                if (now - idleTick > 1.5) idleSince = now;
                idleTick = now;
                if (leveling && now - idleSince > 45 && idleStone(now, "no target for " + Math.round(now - idleSince) + " s")) return;
                nav.stop();
                message = Locale.f("noTargets");
                lastNoTarget = now;
                return;
            }
            targetSince = now;
        }
        if (targetKind == "node") workNode(now); else workMob(now, leveling);
    }

    /**
     * The enemy the hero must deal with first, or null: one that has taken the hero as its target (within AGGRO_RANGE), one at the
     * hero's feet, or one standing at the node the hero wants to gather (it would not let the ore be taken). Not a harmless
     * animal, a dummy or (unless it fights the hero already) a boss.
     */
    function nearbyThreat(now:Float):Dynamic {
        var hz = G.number(G.field(hero, "posz"));
        var best:Dynamic = null;
        var bestD = Math.POSITIVE_INFINITY;
        var nodeX = 0.0, nodeY = 0.0, haveNode = false;
        if (target != null && targetKind == "node") { nodeX = G.number(G.field(target, "posx")); nodeY = G.number(G.field(target, "posy")); haveNode = true; }
        for (e in G.fastArray(G.field(G.field(hero, "layer"), "units"))) {
            if (e == null || e == hero || !G.isA(e, "ent.Foe") || G.field(e, "removed") == true) continue;
            if (G.call("ent.GameObject", "isDead", e) == true || G.field(e, "dying") == true || G.field(e, "summonOwner") != null) continue;
            try if (G.call("ent.GameObject", "isEnemyWith", hero, [e]) != true) continue catch (_:Dynamic) continue;
            var inf = G.field(e, "inf");
            var unitType = G.s(G.field(inf, "type"));
            if (unitType == "Environment" || unitType == "Critter") continue;
            var ex = G.number(G.field(e, "posx")), ey = G.number(G.field(e, "posy"));
            var aggro = false;
            try aggro = G.call("ent.Unit", "getTarget", e) == hero catch (_:Dynamic) {}
            // (whoever has taken the hero as its target is answered at any height and as far as it can strike: archers shoot from 30 m, wolves leap down from ledges)
            if (Math.abs(G.number(G.field(e, "posz")) - hz) > (aggro ? 20 : 6)) continue;
            var d = Nav.distance(hero, ex, ey);
            if (d > (aggro ? AGGRO_RANGE : THREAT_RANGE + 6)) continue;
            if (!aggro && isUntouchable(e, now)) continue; // (hit for long and never hurt: under the ground, behind a wall)
            if (!aggro && blacklisted(e, now)) continue; // (a foe that was given up but hits the hero is fought all the same)
            var near = d <= THREAT_RANGE || (haveNode && Math.sqrt((ex - nodeX) * (ex - nodeX) + (ey - nodeY) * (ey - nodeY)) <= NODE_GUARD && d <= 30);
            if (!aggro && !near) continue;
            var unit = Catalog.unitRecord(G.s(G.field(inf, "id")));
            if (unit != null && Catalog.isBoss(unit) && !aggro) continue;
            if (d < bestD) { bestD = d; best = e; }
        }
        return best;
    }

    /** The monster has lost health (the hero has begun to kill it). */
    function hurt(e:Dynamic):Bool {
        var hp = G.number(G.call("ent.Unit", "get_health", e), -1), max = G.number(G.call("ent.Unit", "get_maxHealth", e), -1);
        return max > 0 && hp >= 0 && hp < max - 0.5;
    }

    function aggroOnHero(e:Dynamic):Bool {
        try return G.call("ent.Unit", "getTarget", e) == hero catch (_:Dynamic) return false;
    }

    static function key(e:Dynamic):String return Std.string(G.field(e, "__uid"));

    function blacklisted(e:Dynamic, now:Float):Bool {
        if (G.isA(e, "ent.Foe")) return false; // (no black list of monsters at all - the user's order, 28.10)
        var until = blacklist.get(key(e));
        if (until != null && now < until) return true;
        if (deathSpots.length > 0 && G.isA(e, "ent.Foe") && nearDeath(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), now)) return true;
        if (deadAreas.length > 0 && G.isA(e, "ent.Foe")) {
            var ex = G.number(G.field(e, "posx")), ey = G.number(G.field(e, "posy"));
            for (a in deadAreas) if (now < a.until && (a.x - ex) * (a.x - ex) + (a.y - ey) * (a.y - ey) < 30 * 30) return true;
        }
        return false;
    }

    function targetValid(now:Float, leveling:Bool):Bool {
        if (G.field(target, "removed") == true) return false;
        if (now - targetSince > 150 && !(targetKind == "mob" && engaged)) { blacklist.set(key(target), now + 120); return false; }
        // no nearer after 35 s of trying (a way that does not lead there): another target
        var dNow = Nav.distance(hero, G.number(G.field(target, "posx")), G.number(G.field(target, "posy")));
        if (dNow < progressBest - 3 || progressKey != key(target)) { progressBest = dNow; progressAt = now; progressKey = key(target); }
        if (targetKind == "mob") { // a fight that wears the foe down is progress, however far the dodge has carried the hero
            var thp = G.number(G.call("ent.Unit", "get_health", target), -1);
            if (thp >= 0 && thp < progressHp - 1) progressAt = now;
            progressHp = thp;
        }
        if (targetKind == "mob" && now - targetSince > 3 && underground(target)) {
            Log.w("target is under the ground (z " + Math.round(G.number(G.field(target, "posz"))) + "): let go");
            blacklist.set(key(target), now + 600);
            untouchable.set(key(target), now + 600);
            return false;
        }
        // (the hero fights or walks and the foe loses nothing and gets no nearer for 20 s - even one that has the hero as its target: it cannot be hit from here)
        if (targetKind == "mob" && now - progressAt > 20 && now - targetSince > 20) {
            Log.w("no damage dealt and no way nearer for " + Math.round(now - progressAt) + " s (" + Math.round(dNow) + " m, dz " + Math.round(G.number(G.field(target, "posz")) - G.number(G.field(hero, "posz"))) + "): the foe is left alone for 3 min");
            blacklist.set(key(target), now + 180);
            untouchable.set(key(target), now + 180);
            return false;
        }
        if (dNow > 12 && now - progressAt > 22) {
            Log.w("no progress towards the target for 22 s (still " + Math.round(dNow) + " m): another one");
            blacklist.set(key(target), now + 180);
            return false;
        }
        // (a foe the hero has hurt is never given up while it stands in reach: only one that took no damage at all for a long time, out of the hits' reach)
        if (targetKind == "mob" && dNow <= 12 && !aggroOnHero(target) && now - progressAt > (hurt(target) ? NO_DAMAGE_TIME * 6 : NO_DAMAGE_TIME)) {
            // in reach and fighting, yet the monster has lost no health for a while (out of the hits' reach, on a ledge, immune): another one
            Log.t("bot", "the foe lost no health for " + NO_DAMAGE_TIME + " s at " + Math.round(dNow * 10) / 10 + " m (dz " + Math.round(G.number(G.field(target, "posz")) - G.number(G.field(hero, "posz"))) + "): another one");
            blacklist.set(key(target), now + 120);
            return false;
        }
        if (nav.gaveUp && !nav.walkingToObelisk() && targetKind == "mob") { // no way to the monster now: the next nearest is taken, this one stays a candidate for later
            Log.t("bot", "no way to the target mob: the next nearest one is taken, this one is skipped for 10 min");
            skipped.set(key(target), now + 600);
            nav.gaveUp = false;
            return false;
        }
        if (nav.gaveUp && !nav.walkingToObelisk()) {
            var rise = G.number(G.field(target, "posz")) - G.number(G.field(hero, "posz"));
            Log.w("target " + targetKind + " given up by the way-finder (rise " + Math.round(rise) + " m, " + Math.round(dNow) + " m away): blacklisted for 2 min");
            blacklist.set(key(target), now + 120);
            if (targetKind == "mob") {
                deadAreas = [for (a in deadAreas) if (now < a.until) a];
                deadAreas.push({x: G.number(G.field(target, "posx")), y: G.number(G.field(target, "posy")), until: now + 120});
            }
            nav.gaveUp = false;
            return false;
        }
        if (targetKind == "node") {
            // right under or over the node (a floor above it, a ledge below it): out of reach however near
            if (dNow < 6 && Math.abs(G.number(G.field(target, "posz")) - G.number(G.field(hero, "posz"))) > 8 && now - targetSince > 6) {
                Log.w("node at another height (dz " + Math.round(G.number(G.field(target, "posz")) - G.number(G.field(hero, "posz"))) + " m) with no way there: blacklisted for 2 min");
                blacklist.set(key(target), now + 120);
                return false;
            }
            if (G.field(target, "enabled") != true || G.call("ent.Element", "isHidden", target) == true) return false;
            return wantsNode(target);
        }
        if (G.call("ent.GameObject", "isDead", target) == true || G.field(target, "dying") == true) return false;
        // the hero has grown past the monster on the way to it (a level gained in the last fight): one of its own level is looked for, unless this one
        // fights the hero or is hurt already
        // (a foe that is being defended against, or already near, is fought out: dropping it and picking it up again as a threat made the bot stop and
        // start ten times a second, the 26.10 log)
        if (leveling && !lenientTarget && !hurt(target) && !aggroOnHero(target) && key(target) != defendKey && dNow > 14 && G.integer(G.field(target, "_level")) < G.integer(G.field(hero, "_level")) + minDiff()) {
            Log.t("bot", "the target is below the hero's level now: another one");
            return false;
        }
        // (health 0 and still standing: the kill is done, the body just has not been removed yet - the log had the hero casting at one for 6 s while another foe hit it)
        if (G.number(G.call("ent.Unit", "get_health", target), 1) <= 0) return false;
        return true;
    }

    function wantsGather():Bool {
        for (id in plan.active(false)) return true;
        return false;
    }

    function wantsNode(node:Dynamic):Bool {
        var inf = G.field(node, "gatherInf");
        if (inf == null) return false;
        for (id in Catalog.gatherItems(inf).keys()) if (plan.count(false, id) > 0) return true;
        return false;
    }

    /** While leveling a monster this near a pack leader, an elite or a boss is left alone (its pack joins the fight). */
    static inline var DANGER_RANGE = 25.0;
    /** While leveling a monster beyond the reach map is a target only this near. */
    static inline var FAR_UNKNOWN = 400.0;

    var censusAt = 0.0;

    /** Every unit of the layer within 150 m, whatever it is, with the verdict the target choice gave it (so nothing the hero fails to see goes unnoticed). */
    function census(now:Float, level:Int, verdict:Map<String, String>):Void {
        if (now - censusAt < 6) return;
        censusAt = now;
        try {
            var units = G.fastArray(G.field(G.field(hero, "layer"), "units"));
            var rows:Array<{d:Float, text:String}> = [];
            var classes:Map<String, Int> = new Map();
            for (e in units) {
                if (e == null || e == hero) continue;
                var cls = G.typeName(e);
                classes.set(cls, (classes.exists(cls) ? classes.get(cls) : 0) + 1);
                var d = Nav.distance(hero, G.number(G.field(e, "posx")), G.number(G.field(e, "posy")));
                if (d > 150) continue;
                var inf = G.field(e, "inf");
                var isFoe = G.isA(e, "ent.Foe");
                var enemy = "?";
                try enemy = Std.string(G.call("ent.GameObject", "isEnemyWith", hero, [e])) catch (_:Dynamic) {}
                var v = verdict.get(key(e));
                if (v == null) {
                    if (!isFoe) v = "not a Foe";
                    else if (G.field(e, "removed") == true) v = "removed";
                    else if (G.call("ent.GameObject", "isDead", e) == true || G.field(e, "dying") == true) v = "dead";
                    else if (G.field(e, "summonOwner") != null) v = "summon";
                    else if (enemy != "true") v = "not an enemy";
                    else v = "type " + G.s(G.field(inf, "type")) + " skipped";
                }
                rows.push({d: d, text: cls + " " + G.s(G.field(inf, "id")) + " type " + G.s(G.field(inf, "type")) + " L" + G.field(e, "_level") + " d=" + Math.round(d) + " dz="
                    + Math.round(G.number(G.field(e, "posz")) - G.number(G.field(hero, "posz"))) + " enemy " + enemy + " -> " + v});
            }
            rows.sort((a, b) -> a.d < b.d ? -1 : a.d > b.d ? 1 : 0);
            Log.t("census", "hero L" + level + ", layer has " + units.length + " units [" + [for (c => n in classes) c + " " + n].join(", ") + "], within 150 m: " + rows.length);
            for (r in rows) Log.t("census", "  " + r.text);
        } catch (error:Dynamic) Log.err("census", error);
    }

    function pickTarget(now:Float, leveling:Bool, level:Int, descents:Bool, lenient:Bool = false, quiet:Bool = false):Void {
        lenientTarget = lenient;
        targetDescent = false;
        lastCut = 0;
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy")), hz = G.number(G.field(hero, "posz"));
        var layer = G.field(hero, "layer");
        var player = G.field(hero, "player");
        var best:Dynamic = null;
        var bestScore = Math.POSITIVE_INFINITY;
        var kind = "";
        function cost(e:Dynamic):Float {
            var dx = G.number(G.field(e, "posx")) - hx, dy = G.number(G.field(e, "posy")) - hy, dz = G.number(G.field(e, "posz")) - hz;
            return Math.sqrt(dx * dx + dy * dy) + Math.abs(dz) * 4.0; // another level (a plateau, a gorge) means a long way round
        }
        var cut = 0; // candidates no way leads to
        var wantGather = false;
        for (id in plan.active(false)) { wantGather = true; break; }
        if (wantGather) {
            for (e in G.fastArray(G.field(layer, "interactibles"))) {
                if (e == null || G.field(e, "removed") == true || !G.isA(e, "ent.interactible.Gatherable")) continue;
                if (G.field(e, "enabled") != true || G.call("ent.Element", "isHidden", e) == true || blacklisted(e, now)) continue;
                if (!wantsNode(e)) continue;
                var rc = nav.canReach(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), G.number(G.field(e, "posz")), descents);
                if (rc == 0) { cut++; continue; } // no way there from here
                // beyond the reach map and on another tier: a way round on foot is a guess (it ran the hero in circles); only the glider's descent, from a higher tier, is tried
                var nodeDz = G.number(G.field(e, "posz")) - hz;
                if (rc < 0 && Math.abs(nodeDz) > 8 && (!descents || nodeDz > 0)) { cut++; continue; }
                if (Hazard.deadly(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), G.number(G.field(e, "posz")), 1.2)) continue; // in the water
                if (Hazard.trapAt(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), G.number(G.field(e, "posz")))) continue; // in a trap
                try if (!Services.isOk(G.call("ent.interactible.Gatherable", "getNoActionReason", e, [player]))) continue catch (_:Dynamic) continue;
                var c = cost(e);
                // a trip to a far spot is under way: a node that has just come into view takes the hero off it only when it is clearly nearer than
                // what is left of the trip (else the hero turns round for every node that loads on the way, to run to the next one)
                if (nodeKey >= 0 && c > Nav.distance(hero, nodeX, nodeY) * 0.7) continue;
                if (c < bestScore) { bestScore = c; best = e; kind = "node"; }
            }
            if (best != null) {
                nodeKey = -1; // (the trip is over: the node in view is gathered)
                targetDescent = descents && nav.canReach(G.number(G.field(best, "posx")), G.number(G.field(best, "posy")), G.number(G.field(best, "posz")), false) != 1;
                lastCut = cut;
                target = best; targetKind = kind;
                Log.w("target node " + G.s(G.field(G.field(best, "gatherInf"), "id")) + " at " + Math.round(Nav.distance(hero, G.number(G.field(best, "posx")), G.number(G.field(best, "posy")))) + " m");
                return;
            }
        }
        var wantHunt = [for (id in plan.active(true)) id];
        if (wantHunt.length == 0 && !leveling) return;
        var padRise = 0.0; // the highest throw of a bumper the hero can walk to
        for (pad in Pads.list) {
            if (pad.id.indexOf("Flying") >= 0 || pad.id.indexOf("Wall") >= 0 || Math.abs(pad.z - hz) > 3 || Nav.distance(hero, pad.x, pad.y) > 110) continue;
            padRise = Math.max(padRise, Pads.expectedRise(pad));
        }
        var seen:Map<Int, Int> = new Map();
        var why:Map<String, Int> = new Map();
        var verdict:Map<String, String> = new Map();
        var curKey = "";
        var drop = (r:String) -> { why.set(r, (why.exists(r) ? why.get(r) : 0) + 1); verdict.set(curKey, r); };
        var rawNear = 0;
        var foePos:Array<{x:Float, y:Float}> = [];
        var cands:Array<{e:Dynamic, score:Float, x:Float, y:Float}> = [];
        // monsters far above the hero's level (an L20 captain killed an L17 hero in three blows, 27.10): nothing standing near one is attacked
        var strongPos:Array<{x:Float, y:Float}> = [];
        for (e in G.fastArray(G.field(layer, "units"))) {
            if (e == null || e == hero || !G.isA(e, "ent.Foe") || G.field(e, "removed") == true || G.field(e, "dying") == true) continue;
            if (G.integer(G.field(e, "_level")) >= level + STRONG_DIFF) strongPos.push({x: G.number(G.field(e, "posx")), y: G.number(G.field(e, "posy"))});
        }
        for (e in G.fastArray(G.field(layer, "units"))) {
            if (e == null || e == hero || !G.isA(e, "ent.Foe") || G.field(e, "removed") == true) continue;
            if (G.call("ent.GameObject", "isDead", e) == true || G.field(e, "dying") == true) continue;
            if (G.field(e, "summonOwner") != null) continue;
            try if (G.call("ent.GameObject", "isEnemyWith", hero, [e]) != true) continue catch (_:Dynamic) continue;
            curKey = key(e);
            var inf = G.field(e, "inf");
            var unitType = G.s(G.field(inf, "type"));
            if (unitType == "Environment" || unitType == "Critter") continue; // training dummies, harmless animals
            foePos.push({x: G.number(G.field(e, "posx")), y: G.number(G.field(e, "posy"))}); // (every hostile monster counts for a group, wanted or not)
            if (Nav.distance(hero, G.number(G.field(e, "posx")), G.number(G.field(e, "posy"))) < 200) rawNear++;
            var unit = Catalog.unitRecord(G.s(G.field(inf, "id")));
            if (blacklisted(e, now) || isUntouchable(e, now)) { drop("blacklist"); continue; }
            if (skipped.exists(curKey) && now < skipped.get(curKey)) { drop("no way"); continue; }
            if (unit != null && Catalog.isBoss(unit)) { drop("boss"); continue; }
            if (Hazard.deadly(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), G.number(G.field(e, "posz")), 1.2)) { drop("water"); continue; } // in the water
            var foeLevel = G.integer(G.field(e, "_level"));
            // another height (a plateau, a gorge, an upper storey) is a long way round or none: such monsters are not chosen
            // (hunting drops: a monster across the map is the roaming's business, not a target; leveling goes as far as its level needs)
            if (!leveling && cost(e) > FAR_TARGET) continue;
            var dzFoe = Math.abs(G.number(G.field(e, "posz")) - hz);
            // (a bumper within reach lifts the hero onto a ledge up to its throw: then a monster up there is a target too)
            var reach = nav.canReach(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), G.number(G.field(e, "posz")), descents);
            // (no monster is "unreachable": the hero goes to the nearest one however the way winds - the user's order, 28.10)
            // beyond the reach map the way is a guess: a monster far off is the hunting grounds' business (the obelisk or the road takes the hero there), not a
            // target (the 26.10 runs walked 800-1200 m towards a slime the way-finder never found a way to, in circles)
            // beyond the reach map the way is a guess: such a monster is the hunting grounds' business (they walk the hero there), not a target
            if (reach != 1) { // (no map yet, or the monster is beyond it: the old rules by height)
                var lift = G.number(G.field(e, "posz")) > hz && padRise >= dzFoe - 1;
                if (G.number(G.field(e, "posz")) - hz > 40) { drop("high, no full way"); continue; } // (a floating island: the way there is by trampolines only)
            }
            if (underground(e)) { drop("underground"); continue; }
            var score = cost(e);
            // the way there may wind round a cliff or a pool: what the reach map says it costs counts, not the straight line (a wolf 100 m off over a
            // gorge was a 300 m walk the other way, and the hero seemed to run from it)
            var way = nav.pathCost(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), G.number(G.field(e, "posz")), descents);
            if (!Math.isNaN(way) && way > score) score = way;
            if (hurt(e)) score -= 60; // a wounded foe (one the hero began, or one that fought it) is finished before a fresh one is started
            var drops = false;
            if (wantHunt.length > 0 && unit != null) {
                var items = Catalog.unitItems(unit);
                for (id in wantHunt) if (items.exists(id)) { drops = true; break; }
            }
            seen.set(foeLevel, (seen.exists(foeLevel) ? seen.get(foeLevel) : 0) + 1);
            if (Hazard.trapAt(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), G.number(G.field(e, "posz")))) { drop("trap"); continue; } // stands in a trap
            if (leveling) {
                // the hero hunts monsters of its OWN level (a little above is fine, below gives next to nothing): lower ones are
                // not touched, the bot looks for its own level, as far away as that is (the obelisk or the road takes it there)
                var diff = foeLevel - level;
                // (when the zone has none of the hero's level, the nearest lower ones - up to 3 below - are the best there is: they
                // cost so much in the score that any monster of the hero's level, however far, is chosen before them)
                if (drops ? Math.abs(diff) > 6 : (diff < (lenient ? Std.int(Math.min(-3, minDiff())) : minDiff()) || diff > MAX_DIFF)) { drop("level"); continue; }
                // own level first: a monster one level off is taken only when no own-level one is within OFF_LEVEL_COST metres nearer
                if (diff != 0) score += OFF_LEVEL_COST;
            } else {
                if (!drops) { drop("no-drop"); continue; }
            }
            if (leveling) {
                var sx = G.number(G.field(e, "posx")), sy = G.number(G.field(e, "posy"));
                var nearStrong = false;
                for (p in strongPos) if ((p.x - sx) * (p.x - sx) + (p.y - sy) * (p.y - sy) < STRONG_RANGE * STRONG_RANGE) { nearStrong = true; break; }
                if (nearStrong) { drop("near-much-stronger"); continue; }
            }
            verdict.set(curKey, "CANDIDATE score " + Math.round(score));
            cands.push({e: e, score: score, x: G.number(G.field(e, "posx")), y: G.number(G.field(e, "posy"))});
        }
        if (!quiet) census(now, level, verdict);
        // the nearest one (by the way there)
        var groupOfBest = 0;
        for (c in cands) {
            if (c.score < bestScore) { bestScore = c.score; best = c.e; kind = "mob"; }
        }
        if (best != null) {
            var bx = G.number(G.field(best, "posx")), by = G.number(G.field(best, "posy"));
            for (p in foePos) if ((p.x - bx) * (p.x - bx) + (p.y - by) * (p.y - by) <= GROUP_RANGE * GROUP_RANGE) groupOfBest++;
            groupOfBest = Std.int(Math.max(0, groupOfBest - 1));
        }
        lastCut = cut;
        if (best != null) {
            targetDescent = descents && nav.canReach(G.number(G.field(best, "posx")), G.number(G.field(best, "posy")), G.number(G.field(best, "posz")), false) != 1;
            target = best; targetKind = kind; lockedFoe = null;
            if (!quiet) Log.w("target mob " + G.s(G.field(G.field(best, "inf"), "id")) + " lvl " + G.field(best, "_level") + " (hero " + level + ") at " + Math.round(Nav.distance(hero, G.number(G.field(best, "posx")), G.number(G.field(best, "posy")))) + " m, dz "
                + Math.round(G.number(G.field(best, "posz")) - hz) + ", score " + Math.round(bestScore) + ", " + groupOfBest + " others within " + GROUP_RANGE + " m" + (leveling ? ", leveling" : ", hunting drops"));
        } else if (!quiet && haxe.Timer.stamp() - lastSeenLog > 10) {
            lastSeenLog = haxe.Timer.stamp();
            var levels = [for (l => n in seen) l + "x" + n];
            levels.sort(Reflect.compare);
            Log.w((cut > 0 ? cut + " candidates cut as unreachable; " : "") + "no mob to fight for hero L" + level + (leveling ? " (own level " + MIN_DIFF + "..+" + MAX_DIFF + " wanted)" : "") + "; monsters in the loaded world by level: " + (levels.length == 0 ? "none" : levels.join(" ")) + " | hostile within 200 m: " + rawNear + ", dropped: " + [for (r => n in why) r + "=" + n].join(" "));
        }
    }

    // ---- going to where the monsters of the hero's level are ----

    var roamKey = -1;
    var roamX = 0.0;
    var roamY = 0.0;
    var roamSince = 0.0;
    var roamWaitUntil = 0.0;
    var roamVisited:Map<Int, Float> = new Map();

    /** No monster of the hero's level is loaded: walks (or flies by obelisk) to the nearest zone of that level. True while it does. */
    var huntKey = "";
    var huntLevels:Array<Int> = [];
    var huntZones:Map<String, Bool> = new Map();

    /** Hunting drops and none of the wanted monsters is loaded: goes to a zone where monsters that drop them live. */
    function huntRoam(now:Float, level:Int):Bool {
        var wanted = [for (id in plan.active(true)) id];
        if (wanted.length == 0) return false;
        var k = wanted.join(",");
        if (k != huntKey) {
            huntKey = k;
            huntLevels = Catalog.dropLevels(wanted);
            var units = Catalog.dropUnits(wanted);
            huntZones = Hunt.zonesOf(units);
            var zoneNames = [for (z in huntZones.keys()) z];
            zoneNames.sort(Reflect.compare);
            Log.t("hunt", "monsters that drop the wanted items: " + units.length + " kinds (levels " + huntLevels.join(" ") + "), living in " + zoneNames.length + " zones of the map: " + zoneNames.slice(0, 40).join(" "));
        }
        if (huntLevels.length == 0) return false;
        return roam(now, level, 3, huntLevels, huntZones);
    }

    var roamFails:Array<Float> = [];
    var wipeTimes:Array<Float> = [];
    var leaving = false;
    var leaveFailed = false;
    var leaveWaitUntil = 0.0;

    /** Walks to the nearest opened obelisk and flies from it to another one. True while that goes on, false when it cannot be done. */
    function leaveByObelisk(now:Float, ?spots:Array<{x:Float, y:Float}>):Bool {
        message = Locale.f("stTravel");
        if (G.call("ent.Hero", "isFlyingToObelisk", hero) == true) { leaveWaitUntil = now + 3; return true; }
        if (now < leaveWaitUntil) return true;
        if (nav.flyElsewhere(hero, now, spots != null && spots.length > 0 ? spots : [{x: roamX, y: roamY}])) { resetVisited(now); leaveWaitUntil = now + 3; leaving = false; return true; } // (one flight: the hunt goes on where the hero lands)
        var best = null, bestD = 350.0;
        for (o in Nav.obelisks(hero)) {
            var d = Nav.distance(hero, o.x, o.y);
            if (d < bestD) { bestD = d; best = o; }
        }
        if (best == null || bestD < 2.5 || (nav.gaveUp && !nav.walkingToObelisk())) { nav.gaveUp = false; nav.stop(); return false; }
        nav.goalZ = Math.isFinite(best.z) ? best.z : Math.NaN;
        nav.noCliff = true;
        nav.go(best.x, best.y, 1.5, now);
        return true;
    }

    var roamFar = false;
    var farFlew = false;
    var carrotX = Math.NaN;
    var carrotY = Math.NaN;
    var carrotBad:Array<{x:Float, y:Float, until:Float}> = [];
    var carrotFails:Array<Float> = [];
    var roamPath:Array<{x:Float, y:Float}> = [];
    var roamPathIdx = 0;
    var farBlocked:Map<Int, Float> = new Map();
    var roamFarGround = false;
    var roamZone = "";
    var roamZoneLevel = -1;

    /**
     * The zones the hunting ground is chosen from. While leveling these are the zones where monsters of the hero's own level live AND whose
     * map level is the hero's (-1..+1): the others (a lower zone with a few stragglers) are left aside. Once a zone is chosen the hero stays in it
     * and sweeps it cell by cell (the nearest first) until every cell was visited; only then the next zone is chosen. No changing of mind half way.
     */
    function groundZones(now:Float, level:Int, zoneIds:Map<String, Bool>, ownLevel:Bool):Null<Map<String, Bool>> {
        if (zoneIds == null || Hunt.spotsIn(zoneIds) == 0) return null;
        if (roamZoneLevel != level) { roamZoneLevel = level; roamZone = ""; }
        if (roamZone != "" && zoneIds.exists(roamZone) && Hunt.hasFreeCell(roamZone, roamVisited, now)) return [roamZone => true];
        roamZone = "";
        if (ownLevel) {
            var own = Hunt.zonesOfLevels(zoneIds, level + minDiff(), level + MAX_DIFF);
            if (own != null) return own;
        }
        return zoneIds;
    }

    function roam(now:Float, level:Int, wide:Int = 2, ?zoneLevels:Array<Int>, ?zoneIds:Map<String, Bool>, ownLevel:Bool = false):Bool {
        if (!Hunt.onWorld(hero)) return false;
        if (!Hunt.ready()) { Hunt.scan(250); message = Locale.f("stTravel"); return true; }
        if (G.call("ent.Hero", "isFlyingToObelisk", hero) == true) { message = Locale.f("stTravel"); return true; } // (the ground is chosen where the hero lands)
        if (now < roamWaitUntil) { nav.stop(); message = Locale.f("noTargets"); return true; } // just arrived: the monsters are loading
        if (roamKey >= 0) {
            var arrived = Nav.distance(hero, roamX, roamY) < 30;
            var carrotOn = roamFarGround && roamPath.length > 0 && !Math.isNaN(carrotX);
            var stuckWay = !arrived && !nav.walkingToObelisk() && (carrotOn ? noProgress(carrotX, carrotY, now, 25) : noProgress(roamX, roamY, now));
            if (roamFarGround && roamPath.length > 0 && !arrived) {
                if (carrotOn && ((nav.gaveUp && !nav.walkingToObelisk()) || stuckWay)) {
                    // the way-finder cannot get to this carrot: it is left alone for five minutes and another one is chosen
                    Log.t("hunt", "carrot " + Math.round(carrotX) + "," + Math.round(carrotY) + " cannot be reached: another one is chosen");
                    carrotBad.push({x: carrotX, y: carrotY, until: now + 300});
                    carrotFails = [for (t in carrotFails) if (now - t < 90) t];
                    carrotFails.push(now);
                    carrotX = Math.NaN;
                    nav.gaveUp = false;
                    nav.stop();
                    if (carrotFails.length >= 8) {
                        // the route itself is bad here: the cells round the hero's place on it are shut and the route is worked out again
                        carrotFails = [];
                        Log.t("hunt", "route is bad here: the cells ahead are shut, a new route is worked out");
                        for (i in roamPathIdx...Std.int(Math.min(roamPath.length, roamPathIdx + 6))) for (c in Hunt.around(Hunt.cellAt(roamPath[i].x, roamPath[i].y), 1)) farBlocked.set(c, now + 900);
                        roamKey = -1;
                        return true;
                    }
                }
                if (now - roamSince > 1800) { roamKey = -1; farBlocked = new Map(); return true; }
            }
            if (arrived || (nav.gaveUp && !nav.walkingToObelisk()) || now - roamSince > (roamFarGround ? 1200 : 300) || stuckWay) {
                Log.t("hunt", "ground " + roamKey + " " + (arrived ? "reached, no monster to fight in sight" : nav.gaveUp ? "cannot be reached" : "took too long") + ": leaving it alone for 8 min");
                if (!arrived) { killDeadGround(now, roamKey); if (nav.gaveUp || now - roamSince < 240) nav.banLastLanding(now, 240); }
                for (c in Hunt.around(roamKey, arrived ? 4 : 6)) roamVisited.set(c, now + 480); // (a ground the way-finder gave up: the whole pocket around it is the same trouble) // (the cells next to it are the same ground; the monsters take minutes to come back)
                roamKey = -1;
                nav.gaveUp = false;
                nav.stop();
                if (arrived) { roamFails = []; roamWaitUntil = now + 4; return true; }
                // three grounds in two minutes that no way leads to: the hero sits in a pocket (the city's basin, a ledge): the obelisks lead out of it
                roamFails.push(now);
                roamFails = [for (t in roamFails) if (now - t < 120) t];
                if (roamFails.length >= 3) { roamFails = []; leaving = now >= grindUntil; Log.t("hunt", "three grounds in a row cannot be walked to: out of this place by obelisk"); }
            }
        }
        if (leaving) {
            // the way to the obelisk led out of the pocket: ground the reach map holds now means no flight (the hero walks on)
            if (nav.ensureReach(hero, now, true)) { message = Locale.f("stTravel"); return true; }
            var useZ = groundZones(now, level, zoneIds, ownLevel);
            var here = Hunt.find(hero, level, roamVisited, now, nav.liveObelisks(hero, now), wide, zoneLevels, useZ, (x, y) -> (nav.canReach(x, y, Math.NaN) == 1 || nav.canReach(x, y, Math.NaN, true) == 1) && !nearDeath(x, y, now));
            if (here != null && !nav.inClosedRegion(hero, now) && G.call("ent.Hero", "isFlyingToObelisk", hero) != true) { leaving = false; nav.stop(); }
            else {
                if (leaveByObelisk(now, Hunt.spotList(level, wide, zoneLevels, useZ))) return true;
                leaving = false;
                // no obelisk to fly from: the home stone (the city's obelisks lead on)
                if (idleStone(now, "no way out of this place by obelisk")) return true;
            }
        }
        if (roamKey < 0) {
            // the monsters' own zones when the game's tables know them (the whole map), else the zones of their levels
            var useZones = groundZones(now, level, zoneIds, ownLevel);
            // first only ground the reach map on foot really contains (a ground it merely might reach, or only by a glider's one-way drop, sent the
            // hero 100 m one way, the way-finder gave up, and the next ground lay the other way: the 26.10 pacing), then the old rule
            // (the map with the glider's descents too: the way out of a basin by a drop and a ford is a way)
            if (nav.ensureReach(hero, now, true)) { message = Locale.f("stTravel"); return true; }
            var g = Hunt.find(hero, level, roamVisited, now, nav.liveObelisks(hero, now), wide, zoneLevels, useZones, (x, y) -> (nav.canReach(x, y, Math.NaN) == 1 || nav.canReach(x, y, Math.NaN, true) == 1) && !nearDeath(x, y, now));
            // no ground inside the closed region the hero stands in (the city's basin, a ledge): out by obelisk, not paced out on foot
            if (g == null && nav.inClosedRegion(hero, now) && !leaveFailed && now >= grindUntil) { leaving = true; if (leaveByObelisk(now, Hunt.spotList(level, wide, zoneLevels, useZones))) return true; leaving = false; leaveFailed = true; }
            if (g != null) leaveFailed = false;
            // (a ground far beyond the reach map has no way the planner can find - its window is about 120 m: the hero ran back and forth on pieces
            // of path that changed at every replan; such a ground is walked to in steps of other grounds, or reached after the home stone)
            if (g == null) g = Hunt.find(hero, level, roamVisited, now, nav.liveObelisks(hero, now), wide, zoneLevels, useZones, (x, y) -> footOrFlight(x, y, Math.NaN) && !farUnknown(x, y) && !nearDeath(x, y, now));
            // leveling: the ground of the hero's own level may lie far beyond the reach map and every opened obelisk (no obelisk was opened there yet):
            // it is walked to all the same, the way-finder works it out in steps; the home stone is not used on the way
            roamFar = false;
            if (g == null && ownLevel) {
                var far = Hunt.farFind(hero, level, roamVisited, now, farBlocked, wide, zoneLevels, useZones);
                if (far != null) {
                    g = far;
                    roamFar = true;
                    roamPath = far.path;
                    roamPathIdx = 0;
                    carrotX = Math.NaN;
                    Log.t("hunt", "no ground of the own level within the reach map: walking to the nearest one by a land route, " + Math.round(g.away) + " m away in a straight line, " + far.path.length + " way points: "
                        + [for (p in far.path) Math.round(p.x) + "," + Math.round(p.y)].join(" "));
                }
            }
            if (g == null && roamZone != "") {
                // nothing more to walk to in the zone chosen: the choice is dropped (the whole set is looked at next time)
                Log.t("hunt", "zone " + roamZone + ": no cell left that can be walked to, the next zone is chosen");
                roamZone = "";
                return true;
            }
            if (g == null) {
                var remembered = Lambda.count({iterator: () -> roamVisited.keys()});
                // the sweep came to its end twice in four minutes with no monster met: this place has none left that the hero can walk to - the
                // obelisks lead to where the monsters live (the memory is kept, so that the walk to the obelisk is not turned back)
                wipeTimes.push(now);
                wipeTimes = [for (t in wipeTimes) if (now - t < 240) t];
                if (wipeTimes.length >= 2 && remembered > 0) {
                    wipeTimes = [];
                    leaving = now >= grindUntil;
                    Log.t("hunt", "the sweep ended twice in a row with nothing found: out of this place by obelisk");
                    return true;
                }
                Log.t("hunt", "no hunting ground left that was not visited lately (" + remembered + " cells remembered): the memory is wiped, the sweep starts over");
                resetVisited(now);
                // none even with an empty memory: the map has such ground but no way leads there from here (a gorge, a closed island) - the home stone
                if (remembered == 0 && Hunt.groundExists(level, wide) && idleStone(now, "ground of the hero's level exists but no way leads to it")) return true;
                roamWaitUntil = now + 6; // (look again in a few seconds: the reach map may be made by then)
                return false;
            }
            roamKey = g.key;
            roamZone = useZones != null ? g.zone : "";
            roamFarGround = roamFar;
            roamX = g.x;
            roamY = g.y;
            roamSince = now;
            progressReset(now);
            Log.t("hunt", "going to a hunting ground: zone " + g.zone + " (level " + g.level + ") at " + Math.round(g.x) + "," + Math.round(g.y) + ", " + Math.round(g.away) + " m away");
        }
        message = Locale.f("stTravel");
        if (!roamFarGround && stoneIfFar(roamX, roamY, now)) return true;
        if (roamFarGround && roamPath.length > 0) {
            // an opened obelisk that saves a long walk: the flight to the one nearest the ground comes first (the whole way to the ground is judged, not the next carrot);
            // after the landing the route is worked out again from there
            if (nav.travel(hero, roamX, roamY, now)) { farFlew = true; message = Locale.f("stTravel"); return true; }
            if (farFlew) { farFlew = false; roamKey = -1; carrotX = Math.NaN; nav.stop(); return true; }
            // the hero's place on the coarse route, then a carrot a little ahead on it: a point the reach map does not rule out (moved a little aside if need be)
            var bi = roamPathIdx, bd = 1e18;
            for (i in roamPathIdx...Std.int(Math.min(roamPath.length, roamPathIdx + 25))) {
                var d = Nav.distance(hero, roamPath[i].x, roamPath[i].y);
                if (d < bd) { bd = d; bi = i; }
            }
            roamPathIdx = bi;
            if (Math.isNaN(carrotX) || Nav.distance(hero, carrotX, carrotY) < 18) {
                carrotX = Math.NaN;
                var offs = [[0, 0], [16, 0], [-16, 0], [0, 16], [0, -16], [32, 0], [-32, 0], [0, 32], [0, -32], [24, 24], [-24, 24], [24, -24], [-24, -24]];
                var ahead = 4;
                while (ahead >= 1 && Math.isNaN(carrotX)) {
                    var p = roamPath[Std.int(Math.min(roamPathIdx + ahead, roamPath.length - 1))];
                    for (o in offs) {
                        var qx = p.x + o[0], qy = p.y + o[1];
                        var bad = false;
                        for (b in carrotBad) if (now < b.until && (b.x - qx) * (b.x - qx) + (b.y - qy) * (b.y - qy) < 30 * 30) { bad = true; break; }
                        if (bad) continue;
                        var a = nav.canReach(qx, qy, Math.NaN), b2 = nav.canReach(qx, qy, Math.NaN, true);
                        if (a == 0 && b2 == 0) continue; // (the reach map says no way leads there)
                        carrotX = qx;
                        carrotY = qy;
                        break;
                    }
                    ahead--;
                }
                if (Math.isNaN(carrotX)) {
                    // nothing ahead is fit: the cells round the next stretch are shut and the route is worked out again
                    Log.t("hunt", "no carrot ahead on the route fits: the cells ahead are shut, a new route is worked out");
                    for (i in roamPathIdx...Std.int(Math.min(roamPath.length, roamPathIdx + 6))) for (c in Hunt.around(Hunt.cellAt(roamPath[i].x, roamPath[i].y), 1)) farBlocked.set(c, now + 900);
                    roamKey = -1;
                    return true;
                }
                if (Nav.distance(hero, carrotX, carrotY) < 12 && roamPathIdx >= roamPath.length - 2) {
                    // the hero stands at the end of the land route: nothing is left to walk to on it (standing there for ever was the 27.10 log)
                    Log.t("hunt", "the end of the land route is reached at " + Math.round(carrotX) + "," + Math.round(carrotY) + ": the ground is left");
                    for (c in Hunt.around(roamKey, 4)) roamVisited.set(c, now + 480);
                    roamKey = -1;
                    carrotX = Math.NaN;
                    roamWaitUntil = now + 2;
                    return true;
                }
                if (Nav.distance(hero, carrotX, carrotY) >= 12) progressReset(now); // (a carrot already under the hero's feet is no progress)
            }
            moveTo(carrotX, carrotY, 10, now);
            return true;
        }
        moveTo(roamX, roamY, 8, now);
        return true;
    }

    /** Far from every opened obelisk and the place is far too: the home stone first (the city has an obelisk at hand), as a player would. True when it was used. */
    function stoneIfFar(x:Float, y:Float, now:Float):Bool {
        if (Nav.distance(hero, x, y) <= 500 || now - stoneAt <= 600) return false;
        var nearest = Math.POSITIVE_INFINITY;
        for (o in Nav.obelisks(hero)) nearest = Math.min(nearest, Nav.distance(hero, o.x, o.y));
        if (nearest <= 200) return false;
        stoneAt = now;
        var used = useHomeStone();
        Log.t("bot", "the place is " + Math.round(Nav.distance(hero, x, y)) + " m away and the nearest obelisk " + Math.round(nearest) + " m: home stone " + (used ? "used" : "not in the bag"));
        if (used) { stoneTimes.push(now); nav.stop(); nav.forgetObeliskTrouble(); message = Locale.f("stHome"); nextThink = now + 14; }
        return used;
    }

    // ---- going to where the wanted ore and plants grow ----

    var flightAt = -100.0;
    var flightOut = false;

    static inline var HUNT_UNKNOWN = 200.0;

    /** The spot lies beyond HUNT_UNKNOWN and the reach maps neither hold it nor close it off: no way to it is known. */
    function farUnknown(x:Float, y:Float):Bool {
        if (Nav.distance(hero, x, y) <= HUNT_UNKNOWN) return false;
        for (o in Nav.obelisks(hero)) if (Math.sqrt((o.x - x) * (o.x - x) + (o.y - y) * (o.y - y)) <= 150) return false; // (reached by a flight, the walk from the obelisk is short)
        var a = nav.canReach(x, y, Math.NaN), b = nav.canReach(x, y, Math.NaN, true);
        return a != 1 && b != 1 && (a < 0 || b < 0);
    }

    /** The spot can be walked to (or the reach map does not know), or the hero can walk to an opened obelisk and fly (a closed region, an island). */
    function footOrFlight(x:Float, y:Float, z:Float):Bool {
        if (nav.canReach(x, y, z) != 0 || nav.canReach(x, y, z, true) != 0) return true; // (on foot, or with the glider's descents)
        var now = haxe.Timer.stamp();
        if (now - flightAt > 5) {
            flightAt = now;
            flightOut = false;
            var list = Nav.obelisks(hero);
            if (list.length >= 2) for (o in list) if (nav.canReach(o.x, o.y, o.z) != 0) { flightOut = true; break; }
        }
        return flightOut;
    }

    var progBest = 1e9;
    var progAt = 0.0;

    /** A new place to go to: the progress is measured from the start. */
    function progressReset(now:Float):Void { progBest = 1e9; progAt = now; }

    /** True when the hero got no nearer (by 15 m) to (x, y) in `limit` seconds: a way that runs in circles (back and forth along a ridge, round a pocket). */
    function noProgress(x:Float, y:Float, now:Float, limit:Float = 50):Bool {
        var d = Nav.distance(hero, x, y);
        if (d < progBest - 15) { progBest = d; progAt = now; }
        return now - progAt > limit;
    }

    var nodeKey = -1;
    var nodeX = 0.0;
    var nodeY = 0.0;
    var nodeZ = Math.NaN;
    var nodeSince = 0.0;
    var nodeWaitUntil = 0.0;
    var nodeVisited:Map<Int, Float> = new Map();
    var nodeFailRun = 0;
    var nodeFailAt = -100.0;

    /** No known node can be reached from here: flies from this obelisk to another one, or uses the home stone. True when something was started. */
    function escapeNodeTrap(now:Float):Bool {
        nodeFailRun = 0;
        if (nav.flyElsewhere(hero, now, Nodes.wanted(plan))) {
            nodeVisited = new Map();
            nodeKey = -1;
            message = Locale.f("stTravel");
            nodeWaitUntil = now + 3;
            return true;
        }
        if (now - stoneAt < 300) return false;
        stoneAt = now;
        var used = useHomeStone();
        Log.t("bot", "no node can be reached from here: home stone " + (used ? "used" : "not in the bag"));
        if (used) { nav.stop(); nav.forgetObeliskTrouble(); nodeVisited = new Map(); nodeKey = -1; message = Locale.f("stHome"); nextThink = now + 14; }
        return used;
    }

    /** No wanted node is loaded: goes to the nearest one of the whole world's table (by obelisk when far). True while it does. */
    function nodeRoam(now:Float):Bool {
        if (!Hunt.onWorld(hero)) return false;
        if (now < nodeWaitUntil) { nav.stop(); message = Locale.f("noTargets"); return true; } // just arrived: the nodes are loading
        if (nodeKey >= 0) {
            var arrived = Nav.distance(hero, nodeX, nodeY) < 18;
            var stuckWay = !arrived && !nav.walkingToObelisk() && noProgress(nodeX, nodeY, now);
            if (arrived || (nav.gaveUp && !nav.walkingToObelisk()) || now - nodeSince > 300 || stuckWay) {
                Log.t("hunt", "node spot " + Math.round(nodeX) + "," + Math.round(nodeY) + " " + (arrived ? "reached, no node to gather in sight" : nav.gaveUp ? "cannot be reached" : stuckWay ? "no nearer in 50 s (the way runs in circles)" : "took too long") + ": the outcrop is left alone for 6 min");
                for (s in Nodes.near(nodeX, nodeY, 70, nodeZ)) nodeVisited.set(s.key, now + 360); // (the outcrop on the hero's own tier: the nodes above and below are another way)
                nodeKey = -1;
                nav.gaveUp = false;
                nav.stop();
                if (arrived) { nodeFailRun = 0; nodeWaitUntil = now + 3; return true; }
                if (now - nodeFailAt > 20) nodeFailRun = 0;
                nodeFailAt = now;
                nodeFailRun++;
                // three spots in a row that no way leads to: the hero sits in a pocket (an obelisk's plateau, an island): another obelisk, else the home stone
                if (nodeFailRun >= 3 && escapeNodeTrap(now)) return true;
            }
        }
        if (nodeKey < 0) {
            if (Nodes.scanning()) { nav.stop(); message = Locale.f("stTravel"); Nodes.scanStep(); return true; } // (the map's chunk files are read first: every node of the world is known before the first step)
            var g = Nodes.find(hero, plan, nodeVisited, now, Nav.obelisks(hero), (x, y, z) -> footOrFlight(x, y, z), (x, y, z) -> nav.canReach(x, y, z) == 1 ? 0.0 : 60.0);
            if (g == null) {
                if (nodeVisited.keys().hasNext()) {
                    Log.t("hunt", "every known node of the wanted resources was visited lately: the memory is wiped");
                    nodeVisited = new Map();
                    if (escapeNodeTrap(now)) return true;
                    nodeWaitUntil = now + 15; // (no round of the same spots again at once)
                    return true;
                }
                // none seen yet anywhere: the world is searched zone by zone (the loaded world reaches a few hundred metres, so one stop covers a lot)
                return explore(now);
            }
            nodeKey = g.spot.key;
            nodeX = g.spot.x;
            nodeY = g.spot.y;
            nodeZ = g.spot.z;
            nodeSince = now;
            progressReset(now);
            Log.t("hunt", "going to a node of the wanted resources: " + g.spot.gatherable + " at " + Math.round(nodeX) + "," + Math.round(nodeY) + ", " + Math.round(g.away) + " m away (" + g.count + " such nodes in the world)");
        }
        message = Locale.f("stTravel");
        if (stoneIfFar(nodeX, nodeY, now)) return true;
        moveTo(nodeX, nodeY, 8, now, nodeZ);
        return true;
    }

    var exploreKey = -1;
    var exploreX = 0.0;
    var exploreY = 0.0;
    var exploreSince = 0.0;
    var exploreVisited:Map<Int, Float> = new Map();

    /** Nothing known about where the wanted nodes grow: visits the map's zones that suit the hero's level, nearest first, until a node shows up. True while it does. */
    function explore(now:Float):Bool {
        if (!Hunt.ready()) { Hunt.scan(250); message = Locale.f("stTravel"); return true; }
        var level = G.integer(G.field(hero, "_level"), 1);
        if (exploreKey >= 0) {
            var arrived = Nav.distance(hero, exploreX, exploreY) < 40;
            var stuckWay = !arrived && !nav.walkingToObelisk() && noProgress(exploreX, exploreY, now);
            if (arrived || (nav.gaveUp && !nav.walkingToObelisk()) || now - exploreSince > 300 || stuckWay) {
                Log.t("hunt", "search spot " + Math.round(exploreX) + "," + Math.round(exploreY) + " " + (arrived ? "reached" : nav.gaveUp ? "cannot be reached" : stuckWay ? "no nearer in 50 s" : "took too long") + ": the surroundings are left alone for 20 min");
                for (c in Hunt.around(exploreKey, 8)) exploreVisited.set(c, now + 1200); // (the loaded world reaches ~400 m: a stop covers a lot)
                exploreKey = -1;
                nav.gaveUp = false;
                nav.stop();
                if (arrived) { nodeWaitUntil = now + 4; return true; }
            }
        }
        if (exploreKey < 0) {
            var lv = [for (l in 1...level + 1) l];
            var g = Hunt.find(hero, level, exploreVisited, now, Nav.obelisks(hero), 0, lv, null, (x, y) -> footOrFlight(x, y, Math.NaN));
            if (g == null) { Log.t("hunt", "nothing left to search on the map"); exploreVisited = new Map(); return false; }
            exploreKey = g.key;
            exploreX = g.x;
            exploreY = g.y;
            exploreSince = now;
            progressReset(now);
            Log.t("hunt", "no node of the wanted resources known: searching the zone " + g.zone + " (level " + g.level + ") at " + Math.round(g.x) + "," + Math.round(g.y) + ", " + Math.round(g.away) + " m away");
        }
        message = Locale.f("stTravel");
        if (stoneIfFar(exploreX, exploreY, now)) return true;
        moveTo(exploreX, exploreY, 12, now);
        return true;
    }

    function moveTo(x:Float, y:Float, arrive:Float, now:Float, ?z:Float):Void {
        nav.goalZ = z == null ? Math.NaN : z;
        // no cliff is ever gone down (a fall is no way to a monster, a node or a hunting ground: a spot below is reached by the way round,
        // by obelisk or not at all); only the climb out of a pit (escapePit) may. No water is entered ever.
        var zz = z == null ? Math.NaN : z;
        var plain = nav.canReach(x, y, zz);
        var viaGlide = (targetDescent && target != null) || (plain == 0 && nav.canReach(x, y, zz, true) != 0); // (only the glider's descents lead there: the cliffs are open)
        nav.noCliff = !(viaGlide && !engaged);
        nav.descentOk = !engaged;
        // a spot the reach map says no way on foot leads to: by obelisk, whatever the gain (the glider's descents excepted)
        var force = !viaGlide && plain == 0;
        if (!nav.travel(hero, x, y, now, force)) nav.go(x, y, arrive, now);
    }

    function workNode(now:Float):Void {
        var x = G.number(G.field(target, "posx")), y = G.number(G.field(target, "posy"));
        message = Locale.f("stGather");
        var inReach = false;
        try inReach = G.call("ent.Interactible", "isInRange", target, [hero]) == true catch (_:Dynamic) {}
        var range = 2.0;
        try range = G.number(G.call("ent.Interactible", "getInteractRange", target), 2.0) catch (_:Dynamic) {}
        if (!inReach) {
            if (now - lastNote > 2) { lastNote = now; Log.w("node not in range: d=" + Math.round(Nav.distance(hero, x, y) * 10) / 10 + " range=" + range + " z " + Math.round(G.number(G.field(hero, "posz"))) + "/" + Math.round(G.number(G.field(target, "posz")))); }
            moveTo(x, y, Math.max(0.6, range * 0.5), now, G.number(G.field(target, "posz")));
            return;
        }
        nav.stop();
        if (G.call("ent.GameObject", "getActiveSkill", hero) != null || now - lastInteract < 0.7) return;
        lastInteract = now;
        var ctl = G.current("client.PlayerController", "inst");
        var can = false;
        try can = G.call("client.PlayerController", "canInteract", ctl, [target]) == true catch (_:Dynamic) {}
        var reason = "";
        try { var r = G.call("ent.interactible.Gatherable", "getNoActionReason", target, [G.field(hero, "player")]); reason = Type.enumConstructor(r) + Std.string(Type.enumParameters(r)); } catch (_:Dynamic) {}
        Log.w("interact node d=" + Math.round(Nav.distance(hero, x, y) * 10) / 10 + " canInteract=" + can + " reason=" + reason + " hp=" + G.field(target, "hitPoints"));
        G.call("ent.Unit", "requestInteractAction", hero, [target]);
    }

    static inline var MAX_FIGHT_RANGE = 22.0;
    var rangeAt = -100.0;
    var rangeValue = 2.6;
    var rangeLogged = -1.0;

    /**
     * How far from the foe the hero stands to fight: the reach of its own basic attack (the game's BaseSkill.getMaxRange, the series the
     * Attack key runs) less a margin, so a ranged hero shoots from where the weapon reaches instead of walking up to the monster. The old
     * fixed 9 m (ranged) / 2.6 m (melee) is the fallback when the game gives no figure.
     */
    function combatRange():Float {
        var now = haxe.Timer.stamp();
        if (now - rangeAt < 2.0) return rangeValue;
        rangeAt = now;
        var basic = 0.0;
        try {
            for (skill in G.array(G.field(hero, "skills"))) {
                if (skill == null || G.field(skill, "removed") == true || !isBasic(skill)) continue;
                var r = G.number(G.call("st.skill.BaseSkill", "getMaxRange", skill), 0);
                if (Math.isFinite(r) && r > 0 && r < 60) basic = Math.max(basic, r);
            }
        } catch (_:Dynamic) {}
        var fallback = rangedWeapon() ? 9.0 : 2.6;
        // (the margin keeps the hero inside the reach while the foe steps about; melee reach is the body's too, so it stays close)
        rangeValue = rangedWeapon() ? MAX_FIGHT_RANGE : basic > 0 ? Math.max(2.2, Math.min(MAX_FIGHT_RANGE, basic * 0.8)) : fallback; // (a ranged hero strikes from 22 m: the skills that reach, the foe comes to the rest)
        if (Math.abs(rangeValue - rangeLogged) > 0.3) { rangeLogged = rangeValue; Log.t("fight", "fight range " + Math.round(rangeValue * 10) / 10 + " m (basic attack reach " + Math.round(basic * 10) / 10 + " m, " + (basic > 0 ? "from the game" : "fallback for the weapon") + ")"); }
        return rangeValue;
    }

    function rangedWeapon():Bool {
        var weapon = G.field(hero, "weaponInHand");
        var type = G.s(G.field(G.field(weapon, "inf"), "type"));
        return type == "Bow" || type == "Staff" || type == "Book" || type == "Halos" || type == "Scepter" || type == "Thrown" || type == "Crescent";
    }

    /** The target's attack spot is held until it is this much farther than the reach (a foe on the edge of the reach would flip "go"/"stop" every think). */
    static inline var REACH_HOLD = 1.5;
    var engaged = false;
    var wrongHeightSince = -1.0;
    var noSightSince = -1.0;
    var losAt = -10.0;
    var losOpen = true;

    /** Lets go of the target for two minutes and says why. */
    function dropTarget(now:Float, why:String):Void {
        var id = "";
        try id = G.s(G.field(G.field(target, "inf"), "id")) catch (_:Dynamic) {}
        Log.t("fight", "target " + id + " let go: " + why);
        blacklist.set(key(target), now + 120);
        target = null;
        targetKind = "";
        engaged = false;
        nav.stop();
        releaseAttack();
    }

    /** False when a body of the physics world (a wall, a statue, a bench) stands between the hero's chest and the target's (a spell would hit that). */
    function lineOpen(tx:Float, ty:Float, tz:Float, now:Float):Bool {
        if (now - losAt < 0.25) return losOpen;
        losAt = now;
        losOpen = true;
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy")), hz = G.number(G.field(hero, "posz"));
        var len = Math.sqrt((tx - hx) * (tx - hx) + (ty - hy) * (ty - hy) + (tz - hz) * (tz - hz));
        if (len > 2.5) {
            var r = Solid.ray(hx, hy, hz + 1.0, tx, ty, tz + 1.0);
            if (r >= 0 && r < len - 2.0) losOpen = false; // (a hit near the target is its own body)
        }
        return losOpen;
    }

    function workMob(now:Float, leveling:Bool):Void {
        var x = G.number(G.field(target, "posx")), y = G.number(G.field(target, "posy")), z = G.number(G.field(target, "posz"));
        message = Locale.f(leveling ? "stLevel" : "stHunt");
        // the dodge has the legs and the skills while it runs: nothing is asked of the game meanwhile (a hit queued now would fire the
        // moment the run ends, and walking back to the foe at once is what made the hero twitch)
        if (AutoDodge.dodging()) {
            // (the hero walks through its casts: the fight goes on while it runs from a hit, the legs are the dodge's)
            if (AutoDodge.castOnTheRun && engaged && lockedFoe == target) attack(now, x, y);
            return;
        }
        if (lockedFoe != target) {
            lockedFoe = target;
            engaged = false;
            wrongHeightSince = -1;
            noSightSince = -1;
            try G.call("client.PlayerController", "lockTarget", G.current("client.PlayerController", "inst"), [target]) catch (_:Dynamic) {}
        }
        if (crowdStep(now)) return;
        var d = Nav.distance(hero, x, y);
        var dz = z - G.number(G.field(hero, "posz"));
        var range = combatRange();
        // the fight is held inside a zone of LEASH metres around the spot where it began: a hero the dodge has carried out of it walks back in, a foe that
        // stands outside it is not chased (it is waited for inside; one that never comes in is let go after a few seconds)
        // (the zone belongs to the whole fight: a new foe inside it, e.g. an attacker the hero turns to, does not move its centre)
        if (fightKey != key(target)) {
            fightKey = key(target);
            leashSince = -1;
            if (!Math.isNaN(fightAx) && (now - lastFightAt > 20 || Nav.distance(target, fightAx, fightAy) > LEASH - 4)) { fightAx = Math.NaN; fightAy = Math.NaN; }
        }
        if (!Math.isNaN(fightAx)) {
            var heroOut = Nav.distance(hero, fightAx, fightAy);
            var foeOut = Nav.distance(target, fightAx, fightAy);
            // (with monsters near the hero the fight simply goes on where it stands: walking back through them is what drew the crowd)
            if ((heroOut > LEASH || (foeOut > LEASH && d > range)) && foesAround(18).length == 0) {
                if (foeOut > LEASH && !aggroOnHero(target)) {
                    if (leashSince < 0) leashSince = now;
                    else if (now - leashSince > 8) {
                        Log.t("fight", "the foe stays outside the " + LEASH + " m fight zone (" + Math.round(foeOut) + " m from where the fight began): let go");
                        blacklist.set(key(target), now + 30);
                        fightKey = "";
                        target = null;
                        targetKind = "";
                        engaged = false;
                        nav.stop();
                        releaseAttack();
                        return;
                    }
                } else leashSince = -1;
                engaged = false;
                releaseAttack();
                if (heroOut > LEASH - 10) {
                    if (now - leashLogAt > 5) { leashLogAt = now; Log.t("fight", "outside the fight zone (" + Math.round(heroOut) + " m from where it began): back in"); }
                    moveTo(fightAx, fightAy, LEASH * 0.6, now);
                } else nav.stop();
                return;
            }
            leashSince = -1;
        }
        // a foe on another height (a ledge above, a pit below) is not hit from here, however near it is on the map: closer in on a way up
        // or down, or let go when none leads there
        var level = Math.abs(dz) <= HIT_HEIGHT;
        if (!level && d <= range + 3) {
            if (wrongHeightSince < 0) wrongHeightSince = now;
            else if (now - wrongHeightSince > 6) { dropTarget(now, "on another height (dz " + Math.round(dz * 10) / 10 + " m, " + Math.round(d * 10) / 10 + " m away on the map)"); return; }
        } else wrongHeightSince = -1;
        // (the line of fire matters only where the hero is about to strike: a far target is simply walked to)
        var seen = !level || d > range + REACH_HOLD + 1 || lineOpen(x, y, z, now);
        if (level && !seen) {
            if (noSightSince < 0) noSightSince = now;
            else if (now - noSightSince > 8) { dropTarget(now, "a body of the world stands between (no way to see it for 8 s)"); return; }
        } else noSightSince = -1;
        if (d > (engaged ? range + REACH_HOLD : range) || !level || !seen) {
            engaged = false;
            releaseAttack();
            // never beyond the fight zone: a foe that stands outside it is waited for at its edge (it comes, or is let go by the zone rule)
            var gx = x, gy = y;
            if (!Math.isNaN(fightAx)) {
                var fromCentre = Nav.distance(target, fightAx, fightAy);
                if (fromCentre > LEASH - 2) {
                    var k = (LEASH - 2) / fromCentre;
                    gx = fightAx + (x - fightAx) * k;
                    gy = fightAy + (y - fightAy) * k;
                }
            }
            moveTo(gx, gy, level && seen ? range - 0.6 : 1.5, now, z);
            return;
        }
        engaged = true;
        lastFightAt = now;
        if (Math.isNaN(fightAx)) { fightAx = G.number(G.field(hero, "posx")); fightAy = G.number(G.field(hero, "posy")); } // (the zone's centre: where the hero first strikes, not where it set out for the foe)
        nav.stop();
        attack(now, x, y);
    }

    // ---- a crowd: the way out of a corner ----

    var kiting = false;
    var kiteUntil = 0.0;
    var kiteAt = -100.0;
    var crowdCheckAt = -100.0;
    var kiteFailLogAt = -100.0;

    /** Hostile, living, fighting monsters within `radius` m on about the hero's height (a training dummy, a harmless animal, a summon do not count). */
    function foesAround(radius:Float):Array<{x:Float, y:Float, d:Float, aggro:Bool}> {
        var hz = G.number(G.field(hero, "posz"));
        var out = [];
        for (e in G.fastArray(G.field(G.field(hero, "layer"), "units"))) {
            if (e == null || e == hero || !G.isA(e, "ent.Foe") || G.field(e, "removed") == true) continue;
            if (G.call("ent.GameObject", "isDead", e) == true || G.field(e, "dying") == true || G.field(e, "summonOwner") != null) continue;
            try if (G.call("ent.GameObject", "isEnemyWith", hero, [e]) != true) continue catch (_:Dynamic) continue;
            var unitType = G.s(G.field(G.field(e, "inf"), "type"));
            if (unitType == "Environment" || unitType == "Critter") continue;
            if (Math.abs(G.number(G.field(e, "posz")) - hz) > 5) continue;
            var ex = G.number(G.field(e, "posx")), ey = G.number(G.field(e, "posy"));
            var d = Nav.distance(hero, ex, ey);
            if (d > radius) continue;
            var aggro = false;
            try aggro = G.call("ent.Unit", "getTarget", e) == hero catch (_:Dynamic) {}
            out.push({x: ex, y: ey, d: d, aggro: aggro});
        }
        return out;
    }

    /** The distance from the point (px, py) to the segment (ax, ay)-(bx, by). */
    static function segmentDistance(ax:Float, ay:Float, bx:Float, by:Float, px:Float, py:Float):Float {
        var dx = bx - ax, dy = by - ay;
        var len2 = dx * dx + dy * dy;
        var t = len2 < 0.0001 ? 0.0 : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2));
        var cx = ax + dx * t - px, cy = ay + dy * t - py;
        return Math.sqrt(cx * cx + cy * cy);
    }

    /** How many of eight directions are free (no wall, no cliff, no water) for `len` metres from (x, y): the fewer, the more the place is a corner. */
    static function freeDirections(x:Float, y:Float, z:Float, len:Float):Int {
        var n = 0;
        for (i in 0...8) {
            var a = i * Math.PI / 4;
            if (Nav.corridorClear(x, y, z, x + Math.cos(a) * len, y + Math.sin(a) * len, true, false)) n++;
        }
        return n;
    }

    /** A cast in progress is broken off (a running hero does not move while it goes on). */
    function cancelCast():Void {
        try {
            var s = G.call("ent.GameObject", "getActiveSkill", hero);
            if (s != null && !isBasic(s)) G.call("st.skill.Skill", "requestInterrupt", s);
        } catch (_:Dynamic) {}
        castKind = "";
        castSkill = null;
    }

    /**
     * A crowd (three or more fighting the hero, two when it is hurt), a hurt hero among foes, or a hero in a corner or at a cliff's edge with a foe
     * on it: the hero walks a few metres to open ground away from the monsters (by a way that does not pass them and has no cliff), then fights on.
     * True while the walk goes on (the caller asks nothing of the fight then).
     */
    function crowdStep(now:Float):Bool {
        if (kiting) {
            if (nav.active && now < kiteUntil) return true;
            kiting = false;
            nav.stop();
        }
        if (now - kiteAt < 3.5 || now - crowdCheckAt < 0.5) return false;
        crowdCheckAt = now;
        var foes = foesAround(14);
        var close = 0;
        for (f in foes) if (f.d <= 4 || (f.aggro && f.d <= 9)) close++;
        if (close == 0) return false;
        var hp = G.number(G.call("ent.Unit", "get_health", hero), -1), max = G.number(G.call("ent.Unit", "get_maxHealth", hero), -1);
        var frac = max > 0 && hp >= 0 ? hp / max : 1.0;
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy")), hz = G.number(G.field(hero, "posz"));
        var reason = "";
        // The hero never backs away from a fight (a step back among the monsters woke the ones near by and made the crowd that killed it, 26.10):
        // it stands and kills what is at it. Only a cliff's edge under the fight is left (a fall is worse than any monster).
        if (Nav.edgeNear(hx, hy, hz, 1.8)) reason = "a cliff's edge under the fight";
        if (reason == "") return false;
        var spot = retreatSpot(foes, hx, hy, hz);
        if (spot == null) {
            if (now - kiteFailLogAt > 5) { kiteFailLogAt = now; Log.t("fight", "CROWD (" + reason + "): no open ground to walk to, the fight goes on here"); }
            return false;
        }
        kiteAt = now;
        kiting = true;
        kiteUntil = now + 4.0;
        cancelCast();
        releaseAttack();
        engaged = false;
        nav.goalZ = Math.NaN;
        nav.noCliff = true;
        nav.go(spot.x, spot.y, 1.2, now);
        Log.t("fight", "CROWD (" + reason + "): retreat to " + Math.round(spot.x) + "," + Math.round(spot.y) + " (" + Math.round(Math.sqrt((spot.x - hx) * (spot.x - hx) + (spot.y - hy) * (spot.y - hy))) + " m), " + foes.length + " monsters within 14 m");
        return true;
    }

    /** The best open ground 7 or 11 m away: farthest from the monsters, not through them, no cliff, room around it. Null when none is better than here. */
    function retreatSpot(foes:Array<{x:Float, y:Float, d:Float, aggro:Bool}>, hx:Float, hy:Float, hz:Float):Null<{x:Float, y:Float}> {
        var nearest = 1e9;
        for (f in foes) nearest = Math.min(nearest, f.d);
        var cands:Array<{x:Float, y:Float, score:Float}> = [];
        for (i in 0...16) for (len in [7.0, 11.0]) {
            var a = i * Math.PI / 8;
            var px = hx + Math.cos(a) * len, py = hy + Math.sin(a) * len;
            var through = false, endMin = 1e9, sum = 0.0;
            for (f in foes) {
                if (segmentDistance(hx, hy, px, py, f.x, f.y) < 2.2) { through = true; break; }
                var de = Math.sqrt((px - f.x) * (px - f.x) + (py - f.y) * (py - f.y));
                endMin = Math.min(endMin, de);
                sum += de;
            }
            if (through || endMin < nearest + 2) continue;
            cands.push({x: px, y: py, score: Math.min(endMin, 14) + 0.3 * sum / Math.max(1, foes.length)});
        }
        cands.sort((a, b) -> a.score > b.score ? -1 : a.score < b.score ? 1 : 0);
        var best:Null<{x:Float, y:Float}> = null;
        var bestScore = -1e9;
        var tried = 0;
        for (c in cands) {
            if (tried >= 6) break;
            if (!Nav.corridorClear(hx, hy, hz, c.x, c.y, true, false)) continue;
            tried++;
            var ez = NavGrid.fineZ(c.x, c.y, hz);
            if (!Math.isFinite(ez)) continue;
            var s = c.score + freeDirections(c.x, c.y, ez, 3.0);
            for (d in NavGrid.deadEnds) if (Math.abs(d.x - c.x) + Math.abs(d.y - c.y) < 6) s -= 6;
            if (s > bestScore) { bestScore = s; best = {x: c.x, y: c.y}; }
        }
        return best;
    }

    // ---- attacking ----

    /**
     * Fights the target: skills first (each one the moment the game says it is ready), and between them the Attack key is held, so
     * the combo goes on hit after hit (a held key asks for the next hit every frame; a tap per hit would lose the ones in between).
     */
    function attack(now:Float, tx:Float, ty:Float):Void {
        var active = G.call("ent.GameObject", "getActiveSkill", hero);
        var combo = G.integer(G.field(hero, "attackComboCount"));
        if (active != null && isBasic(active)) lastBasicSeen = now;
        // how long each skill's cast really runs (the data's figure is 0 for a channel or a totem): a cast the dodge did not cut, timed from start to end
        var runKind = active != null && !isBasic(active) ? G.s(G.field(active, "kind")) : "";
        if (runKind != "") { if (trackKind != runKind) { trackKind = runKind; trackAt = now; } }
        else if (trackKind != "") {
            var took = now - trackAt;
            if (!(AutoDodge.interruptedKind == trackKind && AutoDodge.interruptedAt >= trackAt - 0.1) && took > 0.15 && took < 8)
                runTimes.set(trackKind, runTimes.exists(trackKind) ? runTimes.get(trackKind) * 0.6 + took * 0.4 : took);
            trackKind = "";
        }
        if (combo == 0) comboSince = now;
        if (now - skillDumpAt > 20) { skillDumpAt = now; dumpSkills(); }
        // Did the last cast take? (a ready skill that never starts would otherwise be tried every tenth of a second, and the
        // Attack key, let go before each try, would never be held: the series would never run)
        if (castKind != "") {
            if (active != null && !isBasic(active)) castSeen = true;
            // the cast is judged when it ran and is over, or when 0.7 s went by without it starting
            if ((castSeen && active == null) || now - castAt > 0.7) {
                // a cast the dodge cut: twice in 20 s and the skill is left alone for 15 s (the hero strikes with the quick ones and the basic attack
                // meanwhile); a long cast in a crowd of hits is a cast that never lands, and the fight of it never ends
                var wasCut = AutoDodge.interruptedKind == castKind && AutoDodge.interruptedAt >= castAt - 0.1;
                // (the game itself cancels a cast that cannot go on while the hero runs - the totem - after a tenth of a second: the same loss as a cut)
                try {
                    var why = Type.enumConstructor(G.field(castSkill, "stopReason"));
                    var ran = G.number(G.field(castSkill, "stopTime")) - G.number(G.field(castSkill, "startTime"));
                    Log.t("fight", "cast of " + castKind + " ended: " + why + " after " + Math.round(ran * 100) / 100 + " s of " + castTime(castSkill) + " s, dodge " + AutoDodge.dodging());
                    if ((why == "Cancel" || why == "Interrupt") && ran < castTime(castSkill) * 0.6) wasCut = true;
                } catch (_:Dynamic) {}
                if (wasCut) {
                    var times = cutCasts.exists(castKind) ? cutCasts.get(castKind) : [];
                    times = [for (t in times) if (now - t < 20) t];
                    times.push(now);
                    cutCasts.set(castKind, times);
                    var hist = cutHistory.exists(castKind) ? cutHistory.get(castKind) : [];
                    hist = [for (t in hist) if (now - t < 120) t];
                    hist.push(now);
                    cutHistory.set(castKind, hist);
                    if (times.length >= 2) {
                        // the ban grows while the skill keeps being cut (15, 30, 60, 120 s) and covers every other skill the dodge has cut lately
                        var bans = banHistory.exists(castKind) ? banHistory.get(castKind) : [];
                        bans = [for (t in bans) if (now - t < 150) t];
                        var span = Math.min(120.0, 15.0 * Math.pow(2, bans.length));
                        bans.push(now);
                        banHistory.set(castKind, bans);
                        castBan.set(castKind, now + span);
                        cutCasts.set(castKind, []);
                        var also = [];
                        for (other => stamps in cutHistory) {
                            if (other == castKind) continue;
                            if (Lambda.exists(stamps, t -> now - t < 60)) { castBan.set(other, Math.max(castBan.exists(other) ? castBan.get(other) : 0.0, now + span)); also.push(other); }
                        }
                        Log.t("fight", castKind + " is cut by the dodge again and again: left alone for " + Math.round(span) + " s" + (also.length > 0 ? " (with " + also.join(", ") + ")" : "") + ", the quick skills and the basic attack strike instead");
                    }
                }

                var fails = castFails.exists(castKind) ? castFails.get(castKind) : 0;
                if (!castSeen && castSkill != null && skillOk(castSkill)) {
                    fails++;
                    castFails.set(castKind, fails);
                    Log.t("fight", "cast of " + castKind + " did not start (" + fails + " in a row)" + (fails >= 2 ? ": left alone for 6 s" : ""));
                    if (fails >= 2) { castBan.set(castKind, now + 6); castFails.set(castKind, 0); }
                } else {
                    castFails.set(castKind, 0);
                    Log.t("fight", "cast of " + castKind + " " + (castSeen ? "started" : "went (the game took it, cooling down)"));
                }
                castKind = "";
                castSkill = null;
            }
        }
        if (active != null && !isBasic(active)) return; // a skill is being cast
        if (castKind != "") return; // a cast was just asked for: no other skill (it would cancel this one) and no basic hit until it started or failed
        var ctl = G.current("client.PlayerController", "inst");
        var ready:Dynamic = null;
        if (now - lastAttack >= 0.1) {
            lastAttack = now;
            for (skill in G.array(G.field(hero, "skills"))) {
                if (skill == null || G.field(skill, "removed") == true || !usable(skill)) continue;
                var kindName = G.s(G.field(skill, "kind"));
                if (kindName == castKind) continue;
                var banned = castBan.get(kindName);
                if (banned != null && now < banned) continue;
                var skillRange = G.number(G.call("st.skill.BaseSkill", "getMaxRange", skill), 0);
                if (skillRange > 0 && skillRange < Nav.distance(hero, tx, ty) - 0.5) continue; // (a skill that does not reach the foe from here is not cast: the basic attack does)
                if (crowded(now) && castTime(skill) > LONG_CAST) continue; // (surrounded, a long cast is cut by the dodge before it lands: the quick ones strike)
                if (skillOk(skill)) {
                    if (isBuff(skill)) { ready = skill; break; } // (the shield and the cooldown boost go first: they make the rest of the fight shorter and safer)
                    if (ready == null) ready = skill;
                }
            }
        }
        if (now - lastFightLog > 1.0) {
            lastFightLog = now;
            Log.t("fight", "combo " + combo + " active " + (active == null ? "-" : G.s(G.field(active, "kind"))) + " asked " + attackDown + " basic requests " + basicRequests + " ready " + (ready == null ? "-" : G.s(G.field(ready, "kind")))
                + " dodge " + AutoDodge.dodging() + " resume in " + Math.max(0, Math.round((attackResumeAt - now) * 100) / 100) + " target d=" + Math.round(Nav.distance(hero, tx, ty) * 10) / 10);
        }
        // The weapon's combo series is not cut: a ready skill waits until the running series has been struck (the key is let go
        // after the second hit so the series ends by itself, then the skill goes off), or for at most COMBO_WAIT seconds.
        if (ready != null && combo > 0 && now - comboSince < COMBO_WAIT) {
            if (combo >= 2) releaseAttack(); else holdAttack(now);
            if (active != null) return;
            if (combo >= 2 && !attackDown) { /* the series is over: the skill goes now */ } else return;
        } else holdAttack(now);
        if (ready == null || active != null) return;
        var skill = ready;
        var kind = G.s(G.field(skill, "kind"));
        castKind = kind;
        castSkill = skill;
        castAt = now;
        castSeen = false;
        Log.t("fight", "CAST " + kind + " (combo " + combo + ", " + (isAim(skill) ? "aimed at the foe" : "own") + ")");
        try {
            releaseAttack(); // the held key would ask for a basic hit over the skill
            attackResumeAt = now + 0.35;
            ownCast = true; // the bot's own skill passes the "hold while dodging" hooks: a monster that keeps the hero dodging is still fought
            if (isAim(skill)) {
                var point = G.enumValue("st.skill.SkillTarget", "Point", [{x: tx, y: ty, z: G.number(G.field(target, "posz"))}]);
                G.call("client.UnitController", "tryUseSkill", ctl, [skill, point]);
            } else G.call("client.UnitController", "requestSkillKind", ctl, ["Skill1", kind]);
        } catch (error:Dynamic) Log.err("cast " + kind, error);
        ownCast = false;
    }

    /** The game's own check throws now and then (a skill without data while it changes): then the hero counts as free. */
    static inline var LONG_CAST = 1.0;
    var crowdAt = -100.0;
    var crowdValue = false;

    /** Two or more hostile monsters within 8 m (the dodge keeps the hero moving: a long cast has no time to finish). */
    function crowded(now:Float):Bool {
        if (now - crowdAt < 0.5) return crowdValue;
        crowdAt = now;
        var n = 0;
        try for (f in foesAround(8)) n++ catch (_:Dynamic) {}
        crowdValue = n >= 2;
        return crowdValue;
    }

    /** The time a skill takes from the start to the end of its cast (seconds), 0 when the data has none. */
    function castTime(skill:Dynamic):Float {
        try {
            var inf = G.field(skill, "inf");
            var t = G.number(G.field(inf, "duration"), 0);
            var anim = G.field(inf, "anim");
            if (anim != null) t = Math.max(t, G.number(G.field(anim, "duration"), 0));
            var learnt = runTimes.get(G.s(G.field(skill, "kind")));
            if (learnt != null) t = Math.max(t, learnt);
            return Math.isFinite(t) ? t : 0;
        } catch (_:Dynamic) return 0;
    }

    var castKind = "";
    var trackKind = "";
    var trackAt = 0.0;
    /** When the dodge cut a skill (per kind, the last 2 minutes), when bans were laid on it, and how long its casts really run (seconds, learnt). */
    var cutHistory:Map<String, Array<Float>> = new Map();
    var banHistory:Map<String, Array<Float>> = new Map();
    var runTimes:Map<String, Float> = new Map();
    var castSkill:Dynamic = null;
    var castAt = 0.0;
    var castSeen = false;
    var castFails:Map<String, Int> = new Map();
    var castBan:Map<String, Float> = new Map();
    var cutCasts:Map<String, Array<Float>> = new Map();
    var skillDumpAt = -100.0;

    function skillOk(skill:Dynamic):Bool {
        try return Type.enumConstructor(G.call("st.skill.Skill", "checkUse", skill, [null])) == "Ok" catch (_:Dynamic) return false;
    }

    /** The log gets every skill the hero has, what the bot makes of it and whether the game would let it be used now. */
    function dumpSkills():Void {
        var rows = [];
        try {
            for (skill in G.array(G.field(hero, "skills"))) {
                if (skill == null || G.field(skill, "removed") == true) continue;
                var inf = G.field(skill, "inf");
                var use = "?";
                try { var r = G.call("st.skill.Skill", "checkUse", skill, [null]); use = Type.enumConstructor(r) + (Type.enumParameters(r).length > 0 ? Std.string(Type.enumParameters(r)) : ""); } catch (_:Dynamic) {}
                rows.push(G.s(G.field(skill, "kind")) + "{type " + G.integer(G.field(inf, "type"), -1) + " nature " + G.integer(G.field(inf, "nature"), -1) + (usable(skill) ? " BOT-USES" : " skipped") + " " + use + " cast " + Math.round(castTime(skill) * 100) / 100 + "s range " + Math.round(G.number(G.call("st.skill.BaseSkill", "getMaxRange", skill), -1) * 10) / 10 + "}");
            }
        } catch (error:Dynamic) Log.err("dumpSkills", error);
        Log.t("fight", "skills of the hero: " + rows.join(" "));
    }

    function isBasic(skill:Dynamic):Bool {
        try return G.call("st.skill.BaseSkill", "isBasicAttack", skill) == true catch (_:Dynamic) return false;
    }

    /**
     * Only the skills of the weapon-skill slots (data type 7: the game's input "WeaponSkill1".."WeaponSkill4") and the signature
     * skill (17) are cast: what a player has on the bar. Combo steps (type 4), the basic attack (the Attack key), passives, learnt
     * but unequipped skills of other classes, the dash, the block and the mount are left alone.
     */
    function usable(skill:Dynamic):Bool {
        try {
            var inf = G.field(skill, "inf");
            var type = G.integer(G.field(inf, "type"), -1);
            if (type != 7 && type != 17 && type != 5 && !(type == 9 && isBuff(skill))) return false; // weapon-slot skills, the signature skill, the secondary skill, a self-buff of the skill bar
            if (G.integer(G.field(inf, "nature"), -1) == 5) return false;
            if (G.isA(skill, "st.skill.Mount") || G.isA(skill, "st.skill.Block")) return false;
            for (check in ["isDash", "isBlock", "isBasicAttack"]) if (G.call("st.skill.BaseSkill", check, skill) == true) return false;
            return true;
        } catch (_:Dynamic) return false;
    }

    /**
     * A self-buff the hero carries on its skill bar (data type 9, reach 0: the mage's Spark Shield and Mystic Empowerment, which cuts
     * cooldowns). Steps (Blink, dash, leap, mount) are not buffs, and a learnt skill that is not on the bar is not cast.
     */
    function isBuff(skill:Dynamic):Bool {
        try {
            var inf = G.field(skill, "inf");
            if (G.integer(G.field(inf, "type"), -1) != 9) return false;
            var kind = G.s(G.field(skill, "kind"));
            if (~/Blink|Dash|Leap|Jump|Teleport|Charge|Mount|Dodge|Step/i.match(kind)) return false;
            if (G.number(G.call("st.skill.BaseSkill", "getMaxRange", skill), 0) > 0.5) return false;
            for (slot in G.array(G.field(hero, "skillSlots"))) if (G.s(slot) == kind) return true;
            return false;
        } catch (_:Dynamic) return false;
    }

    function isAim(skill:Dynamic):Bool {
        try {
            if (G.call("st.skill.BaseSkill", "getStepByType", skill, [25]) == null) return false;
            var script = G.field(skill, "script");
            if (script == null) return false;
            var type = hl.Type.getDynamic(script).getTypeName();
            try return G.call(type, "allowAiming", script) == true
            catch (_:Dynamic) return G.call("script.SkillScript", "allowAiming", script) == true;
        } catch (_:Dynamic) return false;
    }

    /**
     * The weapon's basic attack (the Attack input, skill type 0), asked of the game's own skill queue as its input handler does
     * (UnitController.updateSkillInput -> requestSkillType). A faked mouse key does not reach the game's Input when its window
     * is not in front, the queued request does; it is renewed on every think, the queue keeps it for Const.Controls.SkillQueueTime.
     */
    function holdAttack(now:Float):Void {
        if (now < attackResumeAt) return;
        try {
            G.call("client.UnitController", "requestSkillType", G.current("client.PlayerController", "inst"), ["Attack", 0, 0]);
            attackDown = true;
            basicRequests++;
        } catch (error:Dynamic) { if (now - lastNote > 5) { lastNote = now; Log.err("basic attack request", error); } }
    }

    var basicRequests = 0;

    function releaseAttack():Void {
        attackDown = false;
    }

    // ---- loot ----

    /** Walks to the nearest drop (the pick-up itself is Loot.update's, the moment the hero is in the server's reach). */
    function seekLoot(now:Float):Bool {
        if (Services.freeSlots(hero) <= 0) return false; // nowhere to put it: do not walk after drops
        var best = Loot.nearest(hero, LOOT_SEEK, now);
        if (best == null) return false;
        var k = Loot.key(best);
        if (k != seekKey) { seekKey = k; seekSince = now; }
        // a drop that cannot be reached or taken (12 s of trying) is left alone for a minute
        if ((nav.gaveUp && !nav.walkingToObelisk()) || now - seekSince > 12) { nav.gaveUp = false; Loot.skip(best, now, 60); seekKey = ""; return false; }
        var x = G.number(G.field(best, "posx")), y = G.number(G.field(best, "posy"));
        nav.goalZ = G.number(G.field(best, "posz"));
        nav.noCliff = true;
        if (Nav.distance(hero, x, y) > 1.0) nav.go(x, y, 1.0, now);
        message = Locale.f("stLoot");
        return true;
    }

    // ---- developer commands (see Probe) ----

    public function debug(what:String, cmd:Dynamic):Dynamic {
        switch (what) {
            case "job":
                var kind = Std.string(Reflect.field(cmd, "kind"));
                if (plan == null) return "no plan";
                job = new ServiceJob(kind);
                job.hold = haxe.Timer.stamp() + 8;
                noHome = true;
                running = true;
                return "job " + kind;
            case "stone":
                return useHomeStone() ? "stone used" : "no stone";
            case "trip":
                // developer: the recycling trip from here, as when the bag is full
                if (plan == null) return "no plan";
                running = true;
                AutoDodge.enabled = true;
                startJob("scrap", haxe.Timer.stamp());
                return "trip";
            case "move":
                // developer: moves the stack of an item to the bank (to=bank) or back (to=bag)
                var id = Std.string(Reflect.field(cmd, "item")), toBank = Reflect.field(cmd, "to") == "bank";
                var from = toBank ? Services.bag(hero) : Services.bankTabs(hero)[0];
                for (stack in Services.stacks(from)) {
                    if (Services.itemId(G.field(stack, "item")) != id) continue;
                    var dest = toBank ? Services.bankTabFor(hero, G.field(stack, "item")) : Services.bag(hero);
                    return dest == null ? "no room" : (Services.transfer(from, stack, dest) ? "sent" : "refused");
                }
                return "not found";
            case "z":
                // developer: ground heights west of the hero (dir dx,dy; steps of 1 m)
                var dx:Float = Reflect.field(cmd, "dx"), dy:Float = Reflect.field(cmd, "dy");
                var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy")), hz = G.number(G.field(hero, "posz"));
                var rows = [];
                for (i in 0...Std.int(Reflect.field(cmd, "n"))) {
                    var x = hx + dx * i, y = hy + dy * i;
                    rows.push(i + ": near " + Math.round(AutoDodge.worldZ(x, y, hz, 2.2) * 10) / 10 + " deep " + Math.round(AutoDodge.worldZ(x, y, hz - 30, 30) * 10) / 10 + " tall " + Math.round(AutoDodge.worldZ(x, y, hz, 9.0) * 10) / 10);
                }
                return {hero: [hx, hy, hz], rows: rows};
            case "map":
                // developer: a text map of the planner's view around (x, y) (the hero when missing), r cells either side
                var mx:Float = Reflect.hasField(cmd, "x") ? Reflect.field(cmd, "x") : G.number(G.field(hero, "posx"));
                var my:Float = Reflect.hasField(cmd, "y") ? Reflect.field(cmd, "y") : G.number(G.field(hero, "posy"));
                var rr = Reflect.hasField(cmd, "r") ? Std.int(Reflect.field(cmd, "r")) : 25;
                var hzz = Reflect.hasField(cmd, "z") ? G.number(Reflect.field(cmd, "z")) : G.number(G.field(hero, "posz"));
                return {rows: NavGrid.debugMap(mx, my, rr, hzz, nav.debugRoute(), G.number(G.field(hero, "posx")), G.number(G.field(hero, "posy")), nav.goalX(), nav.goalY())};
            case "ray":
                // developer: horizontal rays of the physics cast around the hero (16 directions, three heights), raw results
                var rx:Float = Reflect.hasField(cmd, "x") ? Reflect.field(cmd, "x") : G.number(G.field(hero, "posx"));
                var ry:Float = Reflect.hasField(cmd, "y") ? Reflect.field(cmd, "y") : G.number(G.field(hero, "posy"));
                var rz:Float = Reflect.hasField(cmd, "z") ? Reflect.field(cmd, "z") : G.number(G.field(hero, "posz"));
                var rlen:Float = Reflect.hasField(cmd, "len") ? Reflect.field(cmd, "len") : 6.0;
                var rmask = Reflect.hasField(cmd, "mask") ? Std.int(Reflect.field(cmd, "mask")) : 4;
                var rl = ["works " + Solid.works + " " + Solid.error];
                for (hh in [0.3, 0.9, 1.5]) {
                    var parts = [];
                    for (i in 0...16) {
                        var a = i * Math.PI / 8;
                        parts.push(Std.string(Math.round(Solid.ray(rx, ry, rz + hh, rx + Math.cos(a) * rlen, ry + Math.sin(a) * rlen, rz + hh, rmask) * 100) / 100));
                    }
                    rl.push("h " + hh + ": " + parts.join(" "));
                }
                return rl;
            case "solidbench":
                // developer: what the body tests cost (microseconds each) and how many cells of a 41 x 41 block the broad phase flags
                var bx = Math.round(G.number(G.field(hero, "posx"))), by = Math.round(G.number(G.field(hero, "posy"))), bz = G.number(G.field(hero, "posz"));
                var t0 = haxe.Timer.stamp();
                var flagged = 0, blockedCells = 0, cellsSeen = 0;
                for (ix in -20...21) for (iy in -20...21) {
                    var gzz = NavGrid.fineZ(bx + ix, by + iy, bz);
                    if (!Math.isFinite(gzz)) continue;
                    cellsSeen++;
                    if (Solid.anyBox(bx + ix - 0.45, by + iy - 0.45, gzz + 0.4, bx + ix + 0.45, by + iy + 0.45, gzz + 1.4)) flagged++;
                }
                var t1 = haxe.Timer.stamp();
                for (ix in -20...21) for (iy in -20...21) {
                    var gzz = NavGrid.fineZ(bx + ix, by + iy, bz);
                    if (Math.isFinite(gzz) && Solid.blocksCell(bx + ix, by + iy, gzz)) blockedCells++;
                }
                var t2 = haxe.Timer.stamp();
                var t3 = haxe.Timer.stamp();
                for (i in 0...1000) Solid.ray(bx, by, bz + 1, bx + 1, by, bz + 1);
                var t4 = haxe.Timer.stamp();
                return ["cells with ground " + cellsSeen + ", flagged by the broad phase " + flagged + ", blocked after rays " + blockedCells,
                    "heights + broad phase: " + Math.round((t1 - t0) * 1000) + " ms, heights + blocksCell: " + Math.round((t2 - t1) * 1000) + " ms, 1000 rays: " + Math.round((t4 - t3) * 1000) + " ms"];
            case "rayfull":
                // developer: the full hit record of one ray (dir in degrees, h height above the feet, len)
                var fx = G.number(G.field(hero, "posx")), fy = G.number(G.field(hero, "posy")), fz = G.number(G.field(hero, "posz"));
                var fa = (Reflect.hasField(cmd, "dir") ? G.number(Reflect.field(cmd, "dir")) : 0.0) * Math.PI / 180;
                var fh = Reflect.hasField(cmd, "h") ? G.number(Reflect.field(cmd, "h")) : 0.9;
                var fln = Reflect.hasField(cmd, "len") ? G.number(Reflect.field(cmd, "len")) : 6.0;
                var fromV = G.create("h3d.VectorImpl", [fx, fy, fz + fh]);
                var toV = G.create("h3d.VectorImpl", [fx + Math.cos(fa) * fln, fy + Math.sin(fa) * fln, fz + fh]);
                var hit = G.call("world.World", "raycastFull", G.current("world.World", "inst"), [fromV, toV, 4]);
                return Probe.toJson(hit, Reflect.hasField(cmd, "depth") ? Std.int(Reflect.field(cmd, "depth")) : 4);
            case "solidmap":
                // developer: a text map around the hero: '#' a physics body in the way at waist height (a 1 m cross of rays), '.' free, '~' no ground
                var sr = Reflect.hasField(cmd, "r") ? Std.int(Reflect.field(cmd, "r")) : 20;
                var sx0 = G.number(G.field(hero, "posx")), sy0 = G.number(G.field(hero, "posy")), sz0 = G.number(G.field(hero, "posz"));
                var srows = [];
                var siy = sr;
                while (siy >= -sr) {
                    var line = "";
                    for (six in -sr...sr + 1) {
                        var px = Math.round(sx0) + six, py = Math.round(sy0) + siy;
                        var gz = NavGrid.fineZ(px, py, sz0);
                        var ch = "~";
                        if (Math.isFinite(gz)) {
                            ch = ".";
                            var hit = Solid.blocksCell(px, py, gz);
                            if (Solid.anyBox(px - 0.45, py - 0.45, gz + 0.4, px + 0.45, py + 0.45, gz + 1.4)) ch = hit ? "#" : "o";
                            if (ch == "." && gz - sz0 > 1.1) ch = "^";
                        }
                        if (six == 0 && siy == 0) ch = "@";
                        line += ch;
                    }
                    srows.push(line);
                    siy--;
                }
                return srows;
            case "foes":
                // developer: the monsters within r metres with every level the game can tell
                var fr = Reflect.hasField(cmd, "r") ? G.number(Reflect.field(cmd, "r")) : 40.0;
                var fl = [];
                for (e in G.fastArray(G.field(G.field(hero, "layer"), "units"))) {
                    if (e == null || e == hero || !G.isA(e, "ent.Foe") || Nav.distance(hero, G.number(G.field(e, "posx")), G.number(G.field(e, "posy"))) > fr) continue;
                    var fi = G.field(e, "inf");
                    var enemy = false, aggro = false;
                    try enemy = G.call("ent.GameObject", "isEnemyWith", hero, [e]) == true catch (_:Dynamic) {}
                    try aggro = G.call("ent.Unit", "getTarget", e) == hero catch (_:Dynamic) {}
                    fl.push(G.s(G.field(fi, "id")) + " get_level=" + G.call("ent.GameObject", "get_level", e) + " _level=" + G.field(e, "_level") + " lvl=" + G.field(fi, "lvl") + " max=" + G.field(fi, "maxLvl")
                        + " hp=" + Math.round(G.number(G.call("ent.Unit", "get_health", e), -1)) + "/" + Math.round(G.number(G.call("ent.Unit", "get_maxHealth", e), -1)) + " enemy=" + enemy + " aggro=" + aggro + " type=" + G.s(G.field(fi, "type"))
                        + " flags=" + G.field(fi, "flags") + " d=" + Math.round(Nav.distance(hero, G.number(G.field(e, "posx")), G.number(G.field(e, "posy")))) + " dying=" + G.field(e, "dying") + " summon=" + (G.field(e, "summonOwner") != null));
                }
                return fl;
            case "zoneat":
                // developer: the zone record at x,y,z (the hero's place when missing), and the same for a list of offsets
                var zxx:Float = Reflect.hasField(cmd, "x") ? Reflect.field(cmd, "x") : G.number(G.field(hero, "posx"));
                var zyy:Float = Reflect.hasField(cmd, "y") ? Reflect.field(cmd, "y") : G.number(G.field(hero, "posy"));
                var zzz:Float = Reflect.hasField(cmd, "z") ? Reflect.field(cmd, "z") : G.number(G.field(hero, "posz"));
                var out = [];
                for (dz in [0.0, 50.0, -50.0]) {
                    var zr = null;
                    try zr = G.call("world.World", "getZone", G.current("world.World", "inst"), [zxx, zyy, zzz + dz, null]) catch (e:Dynamic) out.push("dz " + dz + " error " + Std.string(e));
                    if (zr != null) out.push("dz " + dz + ": " + G.s(G.field(zr, "id")) + " L" + G.integer(G.field(zr, "level")));
                }
                return out;
            case "zonemap":
                // developer: obelisks of the world with their zones and levels
                var rowsZ = [];
                for (def in G.fastArray(G.current("HElement", "obelisks"))) {
                    if (def == null) continue;
                    var props = G.field(G.field(def, "inf"), "props");
                    var zid = G.s(G.field(props, "targetZone"));
                    var pre = G.field(def, "prefab");
                    rowsZ.push(G.s(G.field(G.field(def, "inf"), "id")) + " map " + G.s(G.field(def, "mapId")) + " at " + Math.round(G.number(G.field(pre, "x"))) + "," + Math.round(G.number(G.field(pre, "y"))) + "," + Math.round(G.number(G.field(pre, "z"))) + " zone " + zid);
                }
                return rowsZ;
            case "scan":
                // developer: reads every chunk of the world for nodes now and says what was found
                var ld = [];
                for (e in G.fastArray(G.field(G.field(hero, "layer"), "interactibles"))) {
                    if (e == null || G.field(e, "removed") == true || !G.isA(e, "ent.interactible.Gatherable")) continue;
                    ld.push({x: G.number(G.field(e, "posx")), y: G.number(G.field(e, "posy"))});
                }
                if (Reflect.hasField(cmd, "ids")) return [for (i in (Reflect.field(cmd, "ids"):Array<String>)) Nodes.elementInfo(i)];
                return Nodes.debugScan(G.number(G.field(hero, "posx")), G.number(G.field(hero, "posy")), ld);
            case "elements":
                // developer: the world's element definitions that are gatherables (ore, plants): count and a few samples
                var all = G.staticCall("HElement", "all", []);
                var total = G.len(all), gat = 0, byMap:Map<String, Int> = new Map(), sample = [];
                for (def in G.fastArray(all)) {
                    if (def == null) continue;
                    var gid = G.s(G.field(G.field(G.field(def, "inf"), "props"), "gatherable"));
                    if (gid == "") continue;
                    gat++;
                    var mid = G.s(G.field(def, "mapId"));
                    byMap.set(mid, (byMap.exists(mid) ? byMap.get(mid) : 0) + 1);
                    if (sample.length < 6) {
                        var pre = G.field(def, "prefab");
                        sample.push(G.s(G.field(G.field(def, "inf"), "id")) + " -> " + gid + " map " + mid + " at " + Math.round(G.number(G.field(pre, "x"))) + "," + Math.round(G.number(G.field(pre, "y"))) + "," + Math.round(G.number(G.field(pre, "z"))));
                    }
                }
                var byGid:Map<String, Int> = new Map(), loaded = [];
                for (def in G.fastArray(all)) {
                    if (def == null) continue;
                    var g2 = G.s(G.field(G.field(G.field(def, "inf"), "props"), "gatherable"));
                    if (g2 != "") byGid.set(g2, (byGid.exists(g2) ? byGid.get(g2) : 0) + 1);
                }
                for (e in G.fastArray(G.field(G.field(hero, "layer"), "interactibles"))) {
                    if (e == null || G.field(e, "removed") == true || !G.isA(e, "ent.interactible.Gatherable")) continue;
                    if (loaded.length < 12) loaded.push(G.s(G.field(G.field(e, "inf"), "id")) + " / " + G.s(G.field(G.field(e, "gatherInf"), "id")) + " kind=" + G.s(G.field(e, "kind")) + " at " + Math.round(G.number(G.field(e, "posx"))) + "," + Math.round(G.number(G.field(e, "posy"))) + " d=" + Math.round(Nav.distance(hero, G.number(G.field(e, "posx")), G.number(G.field(e, "posy")))));
                }
                return {total: total, gatherables: gat, byMap: [for (k => v in byMap) k + "=" + v], byGid: [for (k => v in byGid) k + "=" + v], loaded: loaded, sample: sample};
            case "glidemode":
                Nav.glideMode = Std.int(Reflect.field(cmd, "mode"));
                return "glide mode " + Nav.glideMode;
            case "pads":
                return Pads.describe(hero);
            case "column":
                return NavGrid.column(Reflect.field(cmd, "x"), Reflect.field(cmd, "y"), Reflect.field(cmd, "from"), Reflect.field(cmd, "to"));
            case "spawns":
                // developer: where a monster lives (unit) / which monsters live in a zone (zone), from the game's spawner tables
                var smap = G.current("HSpawner", Reflect.hasField(cmd, "zone") ? "zoneUnits" : "unitZones");
                var skey = Std.string(Reflect.hasField(cmd, "zone") ? Reflect.field(cmd, "zone") : Reflect.field(cmd, "unit"));
                var sval = G.call("haxe.ds.StringMap", "get", smap, [skey]);
                return {type: G.typeName(sval), value: sval == null ? null : [for (v in G.fastArray(sval)) G.s(v)].join(" ")};
            case "obelisks":
                return [for (o in Nav.obelisks(hero)) o.id + " " + Math.round(o.x) + "," + Math.round(o.y)];
            case "zonecenter":
                // developer: the middle of the zones whose id contains `zone`
                return Hunt.zoneCenter(Std.string(Reflect.field(cmd, "zone")));
            case "tp":
                // developer: puts the hero at x,y (z when given) by the teleport mod's own move, to test the routes from another place
                var tx:Float = Reflect.field(cmd, "x"), ty:Float = Reflect.field(cmd, "y");
                var tz:Float = Reflect.hasField(cmd, "z") ? Reflect.field(cmd, "z") : G.number(G.field(hero, "posz"));
                nav.stop(); target = null; targetKind = ""; blacklist = new Map(); deadAreas = [];
                return AutoDodge.teleport == null ? "no teleport" : AutoDodge.teleport(hero, {x: tx, y: ty, z: tz});
            case "zones":
                // developer: trigger elements (traps, bumpers, liquids) within `r` metres of the hero
                var zr = Reflect.hasField(cmd, "r") ? G.number(Reflect.field(cmd, "r")) : 80.0;
                var zones = [];
                for (e in G.fastArray(G.field(G.field(hero, "layer"), "interactibles"))) {
                    if (e == null || G.field(e, "removed") == true || !G.isA(e, "ent.interactible.TriggerElement")) continue;
                    var zx = G.number(G.field(e, "posx")), zy = G.number(G.field(e, "posy"));
                    if (Nav.distance(hero, zx, zy) > zr) continue;
                    var ti = G.field(e, "triggerInf");
                    if (Reflect.hasField(cmd, "full")) { zones.push(haxe.Json.stringify(Probe.toJson(G.field(e, "inf"), 4))); continue; }
                    zones.push(G.typeName(e) + " " + G.s(G.field(ti, "id")) + " kind=" + G.s(G.field(e, "triggerKind")) + " flags=" + G.field(ti, "flags") + " effects=" + G.len(G.field(ti, "effects")) + " at " + Math.round(zx) + "," + Math.round(zy) + "," + Math.round(G.number(G.field(e, "posz")))
                        + " r=" + G.field(e, "hitRadius") + " sx=" + G.field(e, "scaleX") + " push=" + haxe.Json.stringify(Probe.toJson(G.field(G.field(ti, "props"), "pushForce"), 2)));
                }
                return zones;
            case "goto":
                // developer: walks (by obelisk when far) to x,y without a plan
                running = true;
                noHome = true;
                AutoDodge.enabled = true;
                gotoX = Reflect.field(cmd, "x");
                gotoY = Reflect.field(cmd, "y");
                gotoArrive = Reflect.hasField(cmd, "arrive") ? Reflect.field(cmd, "arrive") : 2.0;
                gotoZ = Reflect.hasField(cmd, "z") ? Reflect.field(cmd, "z") : Math.NaN;
                return "going";
            case "stop":
                gotoX = null;
                stop();
                return "stopped";
            case "plan":
                var p = FarmPlan.fromJson(Std.string(Reflect.field(cmd, "json")));
                plan.gather = p.gather; plan.hunt = p.hunt; plan.recycle = p.recycle; plan.recycleQualities = p.recycleQualities;
                plan.clearBag = p.clearBag; plan.replaceGear = p.replaceGear; plan.targetLevel = p.targetLevel;
                return plan.toJson();
            case "start":
                start();
                return "started";
            case "state":
                return {running: running, phase: phase, target: targetKind, nav: nav.active, free: hero == null ? -1 : Services.freeSlots(hero),
                    message: message, counts: [for (k => v in counts) k + "=" + v]};
            case "catalog":
                return {ready: Catalog.build(), gather: [for (r in Catalog.gather) G.s(r.id)].join(","), hunt: [for (r in Catalog.hunt) G.s(r.id)].join(",")};
            case "candidates":
                var inv = Services.bag(hero);
                var station = Services.scrapStation(hero);
                var sInv = station == null ? null : G.call("ent.interactible.ElementStation", "getInventory", station, [G.field(hero, "player")]);
                Log.w("station inventory: " + (sInv == null ? "null" : "ok") + " " + G.typeName(station));
                return {station: station != null, gear: [for (s in Services.stacks(inv)) if (Services.isGear(G.field(s, "item"))) Services.itemId(G.field(s, "item")) + ":" + Services.itemRarity(G.field(s, "item"))],
                    ok: [for (s in Services.scrapCandidates(hero, plan, sInv)) Services.itemId(G.field(s, "item"))], bank: [for (s in Services.bankCandidates(hero)) Services.itemId(G.field(s, "item"))]};
            default:
                return "unknown";
        }
    }
}
