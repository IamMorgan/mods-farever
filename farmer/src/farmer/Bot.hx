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
    var lastNoTarget = 0.0;
    var lastNote = 0.0;
    var wasDead = false;
    var lastBasicSeen = 0.0;
    var comboSince = 0.0;
    var lastFightLog = 0.0;
    var failTimes:Array<Float> = [];
    var escapeBumper:Dynamic = null;
    var escapeAt = 0.0;
    var progressBest = 1e9;
    var progressAt = 0.0;
    var progressKey = "";
    var progressHp = 1e12;
    var lastSeenLog = -100.0;
    var bumperHopAt = -100.0;
    var gotoX:Null<Float> = null;
    var gotoY:Null<Float> = null;

    static inline var LOOT_SEEK = 16.0;
    /** A monster this close to the hero is fought before going on with a node. */
    static inline var THREAT_RANGE = 9.0;
    static inline var BUMPER_RANGE = 90.0;
    /** A ready skill waits at most this long for the weapon's combo series to end. */
    static inline var COMBO_WAIT = 2.5;
    /** A monster that has the hero as its target is fought from this far. */
    static inline var AGGRO_RANGE = 28.0;
    /** Monsters this close to the node that is to be gathered are cleared first. */
    static inline var NODE_GUARD = 8.0;
    /** A foe in reach that loses no health for this long is let go (hits into the void). */
    static inline var NO_DAMAGE_TIME = 8.0;
    /** The most a target may differ in height from the hero to be hit from where the hero stands. */
    static inline var HIT_HEIGHT = 3.5;
    /** Monsters this near each other are one group: a lone one is fought before a group (the group's others join the fight). */
    static inline var GROUP_RANGE = 10.0;
    static inline var GROUP_COST = 45.0;
    /** A group counts for at most this many others (past that it is simply a group). */
    static inline var GROUP_MAX = 4;

    public function new() {}

    // ---- control ----

    public function start():Void {
        running = true;
        finished = false;
        finishStage = 0;
        countsReady = false;
        job = null;
        blacklist = new Map();
        target = null;
        targetKind = "";
        AutoDodge.enabled = true;
        message = Locale.f("stTravel");
        failTimes = [];
        escapeBumper = null;
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
    public function holdingSkills():Bool return running && AutoDodge.dodging();

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
            + " | free " + Services.freeSlots(hero) + " traps " + Hazard.trapCount() + (job != null ? " job " + job.kind : "") + (escapeBumper != null ? " escaping" : "")
            + " fails " + failTimes.length + " focus " + windowFocused());
    }

    static function windowFocused():Bool {
        try return G.call("hxd.Window", "get_isFocused", G.staticCall("hxd.Window", "getInstance", [])) == true catch (_:Dynamic) return false;
    }

    function think(now:Float):Void {
        if (!Catalog.build()) return; // the data sheets are not loaded yet
        if (G.call("ent.GameObject", "isDead", hero) == true) {
            if (!wasDead) Log.t("mod", "HERO DIED at " + Math.round(G.number(G.field(hero, "posx"))) + "," + Math.round(G.number(G.field(hero, "posy"))) + "," + Math.round(G.number(G.field(hero, "posz")))
                + " (target " + targetKind + ", " + nav.status(hero, now) + "): respawning");
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

        updateCounts();
        // once, at the start: a jump on the spot, to learn how high the hero jumps (the planner's jump height)
        if (target == null && gotoX == null && nav.calibrateJump(hero, now)) return;

        if (gotoX != null) {
            if (Nav.distance(hero, gotoX, gotoY) < 3) { gotoX = null; nav.stop(); message = "arrived"; return; }
            moveTo(gotoX, gotoY, 2.0, now);
            return;
        }
        if (job != null) { runJob(now); return; }
        var level = G.integer(G.field(hero, "_level"));
        var leveling = plan.targetLevel > 0 && level < plan.targetLevel;
        var workLeft = plan.resourcesLeft() || leveling;
        if (!workLeft) { finish(now); return; }
        finishStage = 0;

        if (Services.freeSlots(hero) > 1) skipBank = false;
        if (Services.freeSlots(hero) <= 1 && now - jobFailedAt > 30) {
            // gathering: first the bank (its window opens from anywhere), then, if the bag is still full, recycle the chosen gear
            // (the recycler needs a walk to its station: the server only opens it within reach); leveling: only recycle, else fight on
            if (plan.resourcesLeft() && !skipBank) { startJob("bank", now); return; }
            if (plan.recycle && anyQuality() && Services.hasScrapGear(hero, plan)) { startJob("scrap", now); return; }
            warnBagFull(now); // a full bag does not stop the run: it keeps fighting (drops are left on the ground)
        }
        farm(now, leveling, level);
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
        Log.t("svc", "job " + kind + " started, free slots " + Services.freeSlots(hero));
        message = Locale.f(kind == "scrap" ? "stRecycle" : "stBank");
    }

    function runJob(now:Float):Void {
        if (job.walkTo != null) { // the recycler is out of the server's reach: walk up to it first
            var w = job.walkTo;
            message = Locale.f("stTravel");
            var foe = nearbyThreat(now);
            if (foe != null) { // attacked on the way: fight back first
                if (target != foe) { target = foe; targetKind = "mob"; lockedFoe = null; targetSince = now; nav.stop(); }
                workMob(now, false);
                return;
            } else if (targetKind == "mob") { target = null; targetKind = ""; releaseAttack(); }
            nav.goalZ = Math.NaN;
            if (Nav.distance(hero, w.x, w.y) <= 2.2) { nav.stop(); job.retry(); return; }
            if (!nav.travel(hero, w.x, w.y, now)) nav.go(w.x, w.y, 1.4, now);
            return;
        }
        var r = job.step(app, hero, plan, now);
        if (r == "run") return;
        var kind = job.kind;
        job = null;
        countsReady = false; // what left the bag is not "lost" progress
        Log.t("svc", "job " + kind + ": " + r);
        if (r == "done") {
            if (Services.freeSlots(hero) <= 1) {
                if (kind == "bank") skipBank = true; // the bank took what it could: recycling is next
                else jobFailedAt = now;
            }
            return;
        }
        jobFailedAt = now;
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

    // ---- out of a pit ----

    /** Three targets in a minute that no way leads to: the hero sits in a place it cannot walk out of (a pit, a gorge). */
    function trapped():Bool return failTimes.length >= 3;

    /** The nearest bumper (a trampoline of the world) on about the hero's level that is within reach, or null. */
    function nearestBumper():Dynamic {
        var hz = G.number(G.field(hero, "posz"));
        var best:Dynamic = null;
        var bestD = BUMPER_RANGE;
        for (e in G.fastArray(G.field(G.field(hero, "layer"), "interactibles"))) {
            if (e == null || G.field(e, "removed") == true || !G.isA(e, "ent.interactible.Bumper")) continue;
            var id = G.s(G.field(G.field(e, "inf"), "id"));
            if (id.indexOf("Flying") >= 0 || id.indexOf("Wall") >= 0) continue; // a bumper in the air, one that bounces off a wall
            if (G.field(e, "enabled") == false || Math.abs(G.number(G.field(e, "posz")) - hz) > 4) continue;
            var d = Nav.distance(hero, G.number(G.field(e, "posx")), G.number(G.field(e, "posy")));
            if (d < bestD) { bestD = d; best = e; }
        }
        return best;
    }

    /** Walks onto a bumper (it throws the hero up, the glider and the way on do the rest); without one the home stone is used. */
    function escapePit(now:Float):Void {
        if (escapeBumper == null) {
            var b = nearestBumper();
            if (b == null) {
                Log.w("trapped: no bumper near, the home stone");
                failTimes = [];
                if (useHomeStone()) { message = Locale.f("stHome"); nextThink = now + 12; blacklist = new Map(); }
                return;
            }
            Log.w("trapped: walking onto the bumper " + G.s(G.field(G.field(b, "inf"), "id")));
            escapeBumper = b;
            escapeAt = now;
            target = null;
            targetKind = "";
            releaseAttack();
        }
        var x = G.number(G.field(escapeBumper, "posx")), y = G.number(G.field(escapeBumper, "posy"));
        nav.goalZ = G.number(G.field(escapeBumper, "posz"));
        nav.noCliff = false;
        message = Locale.f("stTravel");
        if (now - escapeAt > 30 || G.field(escapeBumper, "removed") == true || Nav.distance(hero, x, y) < 0.8) {
            Log.w("bumper step done (" + Math.round(now - escapeAt) + " s)");
            escapeBumper = null;
            failTimes = [];
            blacklist = new Map();
            nav.stop();
            return;
        }
        // a monster in the way is fought first
        var foe = nearbyThreat(now);
        if (foe != null) { target = foe; targetKind = "mob"; lockedFoe = null; targetSince = now; nav.stop(); workMob(now, false); return; }
        if (targetKind == "mob") { target = null; targetKind = ""; releaseAttack(); }
        nav.go(x, y, 0.4, now);
    }

    var stoneAt = -1000.0;

    /** Every opened obelisk is out of reach on foot (the hero sits in a gorge or on a ledge): the home stone takes the hero to its city. */
    function strandedStone(now:Float):Bool {
        if (!nav.stranded) return false;
        nav.stranded = false;
        if (now - stoneAt < 300) return false;
        stoneAt = now;
        var used = useHomeStone();
        Log.t("bot", "STRANDED (no obelisk can be walked to from here): home stone " + (used ? "used" : "not in the bag"));
        if (used) {
            message = Locale.f("stHome");
            nav.stop();
            nav.forgetObeliskTrouble();
            target = null;
            targetKind = "";
            roamKey = -1;
            blacklist = new Map();
            nextThink = now + 14;
        }
        return used;
    }

    function farm(now:Float, leveling:Bool, level:Int):Void {
        if (strandedStone(now)) return;
        if (escapeBumper != null || trapped()) { escapePit(now); return; }
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
                Log.w("defending against " + G.s(G.field(G.field(threat, "inf"), "id")) + " at " + Math.round(Nav.distance(hero, G.number(G.field(threat, "posx")), G.number(G.field(threat, "posy")))) + " m");
                target = threat; targetKind = "mob"; lockedFoe = null; targetSince = now;
                nav.stop();
            }
        }
        if (targetKind == "mob" && target != null && !engaged && now - defendAt > 1.0) {
            // a far target and an enemy hitting the hero on the way: that one first (walking on past it under fire is what made the dodge
            // twitch in short runs and the monsters gather into a crowd behind the hero)
            defendAt = now;
            var attacker = nearbyThreat(now);
            if (attacker != null && attacker != target) {
                var toTarget = Nav.distance(hero, G.number(G.field(target, "posx")), G.number(G.field(target, "posy")));
                var toAttacker = Nav.distance(hero, G.number(G.field(attacker, "posx")), G.number(G.field(attacker, "posy")));
                if (toAttacker + 3 < toTarget) {
                    Log.t("bot", "defending against " + G.s(G.field(G.field(attacker, "inf"), "id")) + " at " + Math.round(toAttacker) + " m instead of the target at " + Math.round(toTarget) + " m");
                    target = attacker; targetKind = "mob"; lockedFoe = null; targetSince = now;
                    nav.stop();
                }
            }
        }
        if (target == null) {
            // what lies on the ground is taken first (the pick-up itself is Loot.update's)
            if (seekLoot(now)) return;
            if (now < lootWait) { nav.stop(); message = Locale.f("stLoot"); return; }
            pickTarget(now, leveling, level);
            if (target == null && leveling && roam(now, level)) return;
            if (target == null) {
                // nothing to do right now: wait for nodes to respawn
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
            if (e == null || e == hero || !G.isA(e, "ent.Foe") || G.field(e, "removed") == true || blacklisted(e, now)) continue;
            if (G.call("ent.GameObject", "isDead", e) == true || G.field(e, "dying") == true || G.field(e, "summonOwner") != null) continue;
            try if (G.call("ent.GameObject", "isEnemyWith", hero, [e]) != true) continue catch (_:Dynamic) continue;
            var inf = G.field(e, "inf");
            var unitType = G.s(G.field(inf, "type"));
            if (unitType == "Environment" || unitType == "Critter") continue;
            var ex = G.number(G.field(e, "posx")), ey = G.number(G.field(e, "posy"));
            if (Math.abs(G.number(G.field(e, "posz")) - hz) > 6) continue;
            var d = Nav.distance(hero, ex, ey);
            if (d > AGGRO_RANGE) continue;
            var aggro = false;
            try aggro = G.call("ent.Unit", "getTarget", e) == hero catch (_:Dynamic) {}
            var near = d <= THREAT_RANGE || (haveNode && Math.sqrt((ex - nodeX) * (ex - nodeX) + (ey - nodeY) * (ey - nodeY)) <= NODE_GUARD && d <= 30);
            if (!aggro && !near) continue;
            var unit = Catalog.unitRecord(G.s(G.field(inf, "id")));
            if (unit != null && Catalog.isBoss(unit) && !aggro) continue;
            if (d < bestD) { bestD = d; best = e; }
        }
        return best;
    }

    static function key(e:Dynamic):String return Std.string(G.field(e, "__uid"));

    function blacklisted(e:Dynamic, now:Float):Bool {
        var until = blacklist.get(key(e));
        return until != null && now < until;
    }

    function targetValid(now:Float, leveling:Bool):Bool {
        if (G.field(target, "removed") == true) return false;
        if (now - targetSince > 150) { blacklist.set(key(target), now + 120); return false; }
        // no nearer after 35 s of trying (a way that does not lead there): another target
        var dNow = Nav.distance(hero, G.number(G.field(target, "posx")), G.number(G.field(target, "posy")));
        if (dNow < progressBest - 3 || progressKey != key(target)) { progressBest = dNow; progressAt = now; progressKey = key(target); }
        if (targetKind == "mob") { // a fight that wears the foe down is progress, however far the dodge has carried the hero
            var thp = G.number(G.call("ent.Unit", "get_health", target), -1);
            if (thp >= 0 && thp < progressHp - 1) progressAt = now;
            progressHp = thp;
        }
        if (dNow > 12 && now - progressAt > 35) {
            Log.w("no progress towards the target for 35 s (still " + Math.round(dNow) + " m): another one");
            blacklist.set(key(target), now + 180);
            return false;
        }
        if (targetKind == "mob" && dNow <= 12 && now - progressAt > NO_DAMAGE_TIME) {
            // in reach and fighting, yet the monster has lost no health for a while (out of the hits' reach, on a ledge, immune): another one
            Log.t("bot", "the foe lost no health for " + NO_DAMAGE_TIME + " s at " + Math.round(dNow * 10) / 10 + " m (dz " + Math.round(G.number(G.field(target, "posz")) - G.number(G.field(hero, "posz"))) + "): another one");
            blacklist.set(key(target), now + 120);
            return false;
        }
        if (nav.gaveUp && !nav.walkingToObelisk()) {
            var rise = G.number(G.field(target, "posz")) - G.number(G.field(hero, "posz"));
            Log.w("target " + targetKind + " given up by the way-finder (rise " + Math.round(rise) + " m, " + Math.round(dNow) + " m away): blacklisted for 2 min");
            blacklist.set(key(target), now + 120);
            nav.gaveUp = false;
            if (rise > 4 && escapeBumper == null && now - bumperHopAt > 60) {
                // the target lies on a height no way leads to: a trampoline of the world throws the hero up (the glider and the way on do the rest)
                var b = nearestBumper();
                if (b != null) {
                    bumperHopAt = now;
                    escapeBumper = b;
                    escapeAt = now;
                    Log.w("target is " + Math.round(rise) + " m higher and unreachable on foot: the trampoline " + G.s(G.field(G.field(b, "inf"), "id")) + " is used");
                }
            }
            failTimes.push(now);
            while (failTimes.length > 0 && now - failTimes[0] > 70) failTimes.shift();
            return false;
        }
        if (targetKind == "node") {
            if (G.field(target, "enabled") != true || G.call("ent.Element", "isHidden", target) == true) return false;
            return wantsNode(target);
        }
        if (G.call("ent.GameObject", "isDead", target) == true || G.field(target, "dying") == true) return false;
        return true;
    }

    function wantsNode(node:Dynamic):Bool {
        var inf = G.field(node, "gatherInf");
        if (inf == null) return false;
        for (id in Catalog.gatherItems(inf).keys()) if (plan.count(false, id) > 0) return true;
        return false;
    }

    function pickTarget(now:Float, leveling:Bool, level:Int):Void {
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
        var wantGather = false;
        for (id in plan.active(false)) { wantGather = true; break; }
        if (wantGather) {
            for (e in G.fastArray(G.field(layer, "interactibles"))) {
                if (e == null || G.field(e, "removed") == true || !G.isA(e, "ent.interactible.Gatherable")) continue;
                if (G.field(e, "enabled") != true || G.call("ent.Element", "isHidden", e) == true || blacklisted(e, now)) continue;
                if (!wantsNode(e)) continue;
                if (Hazard.deadly(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), G.number(G.field(e, "posz")), 1.2)) continue; // in the water
                if (Hazard.trapAt(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), G.number(G.field(e, "posz")))) continue; // in a trap
                try if (!Services.isOk(G.call("ent.interactible.Gatherable", "getNoActionReason", e, [player]))) continue catch (_:Dynamic) continue;
                var c = cost(e);
                if (c < bestScore) { bestScore = c; best = e; kind = "node"; }
            }
            if (best != null) {
                target = best; targetKind = kind;
                Log.w("target node " + G.s(G.field(G.field(best, "gatherInf"), "id")) + " at " + Math.round(Nav.distance(hero, G.number(G.field(best, "posx")), G.number(G.field(best, "posy")))) + " m");
                return;
            }
        }
        var wantHunt = [for (id in plan.active(true)) id];
        if (wantHunt.length == 0 && !leveling) return;
        var seen:Map<Int, Int> = new Map();
        var foePos:Array<{x:Float, y:Float}> = [];
        var cands:Array<{e:Dynamic, score:Float, x:Float, y:Float}> = [];
        for (e in G.fastArray(G.field(layer, "units"))) {
            if (e == null || e == hero || !G.isA(e, "ent.Foe") || G.field(e, "removed") == true) continue;
            if (G.call("ent.GameObject", "isDead", e) == true || G.field(e, "dying") == true) continue;
            if (G.field(e, "summonOwner") != null) continue;
            try if (G.call("ent.GameObject", "isEnemyWith", hero, [e]) != true) continue catch (_:Dynamic) continue;
            var inf = G.field(e, "inf");
            var unitType = G.s(G.field(inf, "type"));
            if (unitType == "Environment" || unitType == "Critter") continue; // training dummies, harmless animals
            foePos.push({x: G.number(G.field(e, "posx")), y: G.number(G.field(e, "posy"))}); // (every hostile monster counts for a group, wanted or not)
            if (blacklisted(e, now)) continue;
            var unit = Catalog.unitRecord(G.s(G.field(inf, "id")));
            if (unit != null && Catalog.isBoss(unit)) continue;
            if (Hazard.deadly(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), G.number(G.field(e, "posz")), 1.2)) continue; // in the water
            var foeLevel = G.integer(G.field(e, "_level"));
            // another height (a plateau, a gorge, an upper storey) is a long way round or none: such monsters are not chosen
            if (Math.abs(G.number(G.field(e, "posz")) - hz) > 14) continue;
            var score = cost(e);
            var drops = false;
            if (wantHunt.length > 0 && unit != null) {
                var items = Catalog.unitItems(unit);
                for (id in wantHunt) if (items.exists(id)) { drops = true; break; }
            }
            seen.set(foeLevel, (seen.exists(foeLevel) ? seen.get(foeLevel) : 0) + 1);
            if (Hazard.trapAt(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), G.number(G.field(e, "posz")))) continue; // stands in a trap
            if (leveling) {
                // the hero hunts monsters of its OWN level (a little above is fine, below gives next to nothing): lower ones are
                // not touched, the bot looks for its own level, as far away as that is (the obelisk or the road takes it there)
                var diff = foeLevel - level;
                // (when the zone has none of the hero's level, the nearest lower ones - up to 3 below - are the best there is: they
                // cost so much in the score that any monster of the hero's level, however far, is chosen before them)
                if (drops ? Math.abs(diff) > 6 : (diff < -3 || diff > 2)) continue;
                score += (diff < 0 ? -diff * 600 : diff * 250);
            } else {
                if (!drops) continue;
                score += Math.max(0, foeLevel - level) * 250;
            }
            cands.push({e: e, score: score, x: G.number(G.field(e, "posx")), y: G.number(G.field(e, "posy"))});
        }
        // a lone monster before a group: the group's others would join the fight and press the hero into a corner
        var groupOfBest = 0;
        for (c in cands) {
            var others = -1; // (the monster itself is in the list)
            for (p in foePos) if ((p.x - c.x) * (p.x - c.x) + (p.y - c.y) * (p.y - c.y) <= GROUP_RANGE * GROUP_RANGE) others++;
            var counted = Std.int(Math.min(GROUP_MAX, Math.max(0, others)));
            var s = c.score + counted * GROUP_COST;
            if (s < bestScore) { bestScore = s; best = c.e; kind = "mob"; groupOfBest = Std.int(Math.max(0, others)); }
        }
        if (best != null) {
            target = best; targetKind = kind; lockedFoe = null;
            Log.w("target mob " + G.s(G.field(G.field(best, "inf"), "id")) + " lvl " + G.field(best, "_level") + " (hero " + level + ") at " + Math.round(Nav.distance(hero, G.number(G.field(best, "posx")), G.number(G.field(best, "posy")))) + " m, dz "
                + Math.round(G.number(G.field(best, "posz")) - hz) + ", score " + Math.round(bestScore) + ", " + groupOfBest + " others within " + GROUP_RANGE + " m" + (leveling ? ", leveling" : ", hunting drops"));
        } else if (haxe.Timer.stamp() - lastSeenLog > 10) {
            lastSeenLog = haxe.Timer.stamp();
            var levels = [for (l => n in seen) l + "x" + n];
            levels.sort(Reflect.compare);
            Log.w("no mob to fight for hero L" + level + (leveling ? " (own level -3..+2 wanted)" : "") + "; monsters in the loaded world by level: " + (levels.length == 0 ? "none" : levels.join(" ")));
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
    function roam(now:Float, level:Int):Bool {
        if (!Hunt.onWorld(hero)) return false;
        if (!Hunt.ready()) { Hunt.scan(250); message = Locale.f("stTravel"); return true; }
        if (now < roamWaitUntil) { nav.stop(); message = Locale.f("noTargets"); return true; } // just arrived: the monsters are loading
        if (roamKey >= 0) {
            var arrived = Nav.distance(hero, roamX, roamY) < 30;
            if (arrived || (nav.gaveUp && !nav.walkingToObelisk()) || now - roamSince > 300) {
                Log.t("hunt", "ground " + roamKey + " " + (arrived ? "reached, no monster to fight in sight" : nav.gaveUp ? "cannot be reached" : "took too long") + ": leaving it alone for 5 min");
                roamVisited.set(roamKey, now + 300);
                roamKey = -1;
                nav.gaveUp = false;
                nav.stop();
                if (arrived) { roamWaitUntil = now + 4; return true; }
            }
        }
        if (roamKey < 0) {
            var g = Hunt.find(hero, level, roamVisited, now, Nav.obelisks(hero));
            if (g == null) { Log.t("hunt", "no hunting ground of level " + level + ".." + (level + 2) + " on the map"); return false; }
            roamKey = g.key;
            roamX = g.x;
            roamY = g.y;
            roamSince = now;
            Log.t("hunt", "going to a hunting ground: zone " + g.zone + " (level " + g.level + ") at " + Math.round(g.x) + "," + Math.round(g.y) + ", " + Math.round(g.away) + " m away");
        }
        message = Locale.f("stTravel");
        // far from every opened obelisk and the ground is far too: the home stone first (the city has an obelisk at hand), as a player would
        if (Nav.distance(hero, roamX, roamY) > 500 && now - stoneAt > 600) {
            var nearest = Math.POSITIVE_INFINITY;
            for (o in Nav.obelisks(hero)) nearest = Math.min(nearest, Nav.distance(hero, o.x, o.y));
            if (nearest > 200) {
                stoneAt = now;
                var used = useHomeStone();
                Log.t("bot", "the ground is " + Math.round(Nav.distance(hero, roamX, roamY)) + " m away and the nearest obelisk " + Math.round(nearest) + " m: home stone " + (used ? "used" : "not in the bag"));
                if (used) { nav.stop(); nav.forgetObeliskTrouble(); message = Locale.f("stHome"); nextThink = now + 14; return true; }
            }
        }
        moveTo(roamX, roamY, 8, now);
        return true;
    }

    function moveTo(x:Float, y:Float, arrive:Float, now:Float, ?z:Float):Void {
        nav.goalZ = z == null ? Math.NaN : z;
        // no cliff is ever gone down (a fall is no way to a monster, a node or a hunting ground: a spot below is reached by the way round,
        // by obelisk or not at all); only the climb out of a pit (escapePit) may. No water is entered ever.
        nav.noCliff = escapeBumper == null;
        if (!nav.travel(hero, x, y, now)) nav.go(x, y, arrive, now);
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
        if (AutoDodge.dodging()) return;
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
        var range = rangedWeapon() ? 9.0 : 2.6;
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
            moveTo(x, y, level && seen ? range - 0.6 : 1.5, now, z);
            return;
        }
        engaged = true;
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
        if (close >= 3) reason = close + " monsters at the hero";
        else if (close >= 2 && frac < 0.5) reason = close + " monsters and the hero at " + Math.round(frac * 100) + "% health";
        else if (frac < 0.25) reason = "hero at " + Math.round(frac * 100) + "% health";
        else if (Nav.edgeNear(hx, hy, hz, 1.8)) reason = "a cliff's edge under the fight";
        else if (close >= 2 && freeDirections(hx, hy, hz, 3.0) <= 3) reason = close + " monsters and the hero in a corner";
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
        if (underCC()) {
            if (now - lastFightLog > 2) { lastFightLog = now; Log.t("fight", "hero is under crowd control: no attack"); }
            return;
        }
        var active = G.call("ent.GameObject", "getActiveSkill", hero);
        var combo = G.integer(G.field(hero, "attackComboCount"));
        if (active != null && isBasic(active)) lastBasicSeen = now;
        if (combo == 0) comboSince = now;
        if (now - skillDumpAt > 20) { skillDumpAt = now; dumpSkills(); }
        // Did the last cast take? (a ready skill that never starts would otherwise be tried every tenth of a second, and the
        // Attack key, let go before each try, would never be held: the series would never run)
        if (castKind != "") {
            if (active != null && !isBasic(active)) castSeen = true;
            // the cast is judged when it ran and is over, or when 0.7 s went by without it starting
            if ((castSeen && active == null) || now - castAt > 0.7) {
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
                if (skillOk(skill)) { ready = skill; break; }
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
    function underCC():Bool {
        try return G.call("ent.GameObject", "isUnderAnyCC", hero) == true catch (_:Dynamic) return false;
    }

    var castKind = "";
    var castSkill:Dynamic = null;
    var castAt = 0.0;
    var castSeen = false;
    var castFails:Map<String, Int> = new Map();
    var castBan:Map<String, Float> = new Map();
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
                rows.push(G.s(G.field(skill, "kind")) + "{type " + G.integer(G.field(inf, "type"), -1) + " nature " + G.integer(G.field(inf, "nature"), -1) + (usable(skill) ? " BOT-USES" : " skipped") + " " + use + "}");
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
            if (type != 7 && type != 17 && type != 5) return false; // weapon-slot skills, the signature skill, the secondary skill
            if (G.integer(G.field(inf, "nature"), -1) == 5) return false;
            if (G.isA(skill, "st.skill.Mount") || G.isA(skill, "st.skill.Block")) return false;
            for (check in ["isDash", "isBlock", "isBasicAttack"]) if (G.call("st.skill.BaseSkill", check, skill) == true) return false;
            return true;
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
            case "obelisks":
                return [for (o in Nav.obelisks(hero)) o.id + " " + Math.round(o.x) + "," + Math.round(o.y)];
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
                AutoDodge.enabled = true;
                gotoX = Reflect.field(cmd, "x");
                gotoY = Reflect.field(cmd, "y");
                return "going";
            case "stop":
                gotoX = null;
                stop();
                return "stopped";
            case "plan":
                var p = FarmPlan.fromJson(Std.string(Reflect.field(cmd, "json")));
                plan.gather = p.gather; plan.hunt = p.hunt; plan.recycle = p.recycle; plan.recycleQualities = p.recycleQualities;
                plan.clearBag = p.clearBag; plan.targetLevel = p.targetLevel;
                return plan.toJson();
            case "start":
                start();
                return "started";
            case "state":
                return {running: running, phase: phase, target: targetKind, nav: nav.active, free: hero == null ? -1 : Services.freeSlots(hero),
                    message: message, counts: [for (k => v in counts) k + "=" + v]};
            case "catalog":
                return {ready: Catalog.build(), gather: [for (r in Catalog.gather) r.id], hunt: [for (r in Catalog.hunt) r.id]};
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
