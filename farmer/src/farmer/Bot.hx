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
    var attackCode = -1;
    var attackResendAt = 0.0;
    var attackResumeAt = 0.0;
    /** After a node broke: its drops are on their way, nothing else is started before this time. */
    var lootWait = 0.0;
    var seekKey = "";
    var seekSince = 0.0;
    var lastNoTarget = 0.0;
    var lastNote = 0.0;
    var wasDead = false;
    var gotoX:Null<Float> = null;
    var gotoY:Null<Float> = null;

    static inline var LOOT_SEEK = 16.0;
    /** A monster this close to the hero is fought before going on with a node. */
    static inline var THREAT_RANGE = 9.0;

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
    }

    public function stop():Void {
        running = false;
        AutoDodge.enabled = false;
        nav.stop();
        releaseAttack();
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

    public function holdingSkills():Bool return running && AutoDodge.holdingSkills();

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
        if (!running) { releaseAttack(); return; }
        try AutoDodge.update(hero, now) catch (_:Dynamic) {}
        nav.update(hero, now);
        if (now < nextThink) return;
        nextThink = now + 0.1;
        try think(now) catch (error:Dynamic) {
            Log.w("[Farmer] think: " + Std.string(error) + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
            if (job != null) { try job.close(app) catch (_:Dynamic) {} job = null; jobFailedAt = now; message = "error: " + Std.string(error); }
        }
    }

    function think(now:Float):Void {
        if (!Catalog.build()) return; // the data sheets are not loaded yet
        if (G.call("ent.GameObject", "isDead", hero) == true) {
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

        if (Services.freeSlots(hero) <= 1 && now - jobFailedAt > 30) {
            if (plan.recycle && anyQuality()) { startJob("scrap", now); return; }
            if (plan.clearBag) { startJob("bank", now); return; }
            message = "";
            say(Locale.f("bagFull"));
            stop();
            return;
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
        message = Locale.f(kind == "scrap" ? "stRecycle" : "stBank");
    }

    function runJob(now:Float):Void {
        if (job.walkTo != null) { // the recycler is out of the server's reach: walk up to it first
            var w = job.walkTo;
            message = Locale.f("stTravel");
            if (Nav.distance(hero, w.x, w.y) <= 2.2) { nav.stop(); job.retry(); return; }
            if (!nav.travel(hero, w.x, w.y, now)) nav.go(w.x, w.y, 1.4, now);
            return;
        }
        var r = job.step(app, hero, plan, now);
        if (r == "run") return;
        var kind = job.kind;
        job = null;
        countsReady = false; // what left the bag is not "lost" progress
        Log.w("job " + kind + ": " + r);
        if (r == "done") { if (Services.freeSlots(hero) <= 1) jobFailedAt = now; return; }
        jobFailedAt = now;
        message = r.substr(5);
        if (kind == "scrap" && plan.clearBag) return; // the bank is next time round
        if (Services.freeSlots(hero) <= 1) { say(message); stop(); }
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

    function farm(now:Float, leveling:Bool, level:Int):Void {
        if (target != null && !targetValid(now, leveling)) {
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
        if (target == null) {
            // what lies on the ground is taken first (the pick-up itself is Loot.update's)
            if (seekLoot(now)) return;
            if (now < lootWait) { nav.stop(); message = Locale.f("stLoot"); return; }
            pickTarget(now, leveling, level);
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

    /** The nearest living enemy within reach of the hero (not a boss, a dummy or a harmless animal), or null. */
    function nearbyThreat(now:Float):Dynamic {
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy")), hz = G.number(G.field(hero, "posz"));
        var best:Dynamic = null;
        var bestD = THREAT_RANGE;
        for (e in G.fastArray(G.field(G.field(hero, "layer"), "units"))) {
            if (e == null || e == hero || !G.isA(e, "ent.Foe") || G.field(e, "removed") == true || blacklisted(e, now)) continue;
            if (G.call("ent.GameObject", "isDead", e) == true || G.field(e, "dying") == true || G.field(e, "summonOwner") != null) continue;
            try if (G.call("ent.GameObject", "isEnemyWith", hero, [e]) != true) continue catch (_:Dynamic) continue;
            var inf = G.field(e, "inf");
            var unitType = G.s(G.field(inf, "type"));
            if (unitType == "Environment" || unitType == "Critter") continue;
            var unit = Catalog.unitRecord(G.s(G.field(inf, "id")));
            if (unit != null && Catalog.isBoss(unit)) continue;
            if (Math.abs(G.number(G.field(e, "posz")) - hz) > 5) continue;
            var d = Nav.distance(hero, G.number(G.field(e, "posx")), G.number(G.field(e, "posy")));
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
        if (nav.gaveUp) { blacklist.set(key(target), now + 120); nav.gaveUp = false; return false; }
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
            return Math.sqrt(dx * dx + dy * dy) + Math.abs(dz) * 0.5;
        }
        var wantGather = false;
        for (id in plan.active(false)) { wantGather = true; break; }
        if (wantGather) {
            for (e in G.fastArray(G.field(layer, "interactibles"))) {
                if (e == null || G.field(e, "removed") == true || !G.isA(e, "ent.interactible.Gatherable")) continue;
                if (G.field(e, "enabled") != true || G.call("ent.Element", "isHidden", e) == true || blacklisted(e, now)) continue;
                if (!wantsNode(e)) continue;
                if (Hazard.deadly(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), G.number(G.field(e, "posz")), 1.2)) continue; // in the water
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
        for (e in G.fastArray(G.field(layer, "units"))) {
            if (e == null || e == hero || !G.isA(e, "ent.Foe") || G.field(e, "removed") == true || blacklisted(e, now)) continue;
            if (G.call("ent.GameObject", "isDead", e) == true || G.field(e, "dying") == true) continue;
            if (G.field(e, "summonOwner") != null) continue;
            try if (G.call("ent.GameObject", "isEnemyWith", hero, [e]) != true) continue catch (_:Dynamic) continue;
            var inf = G.field(e, "inf");
            var unitType = G.s(G.field(inf, "type"));
            if (unitType == "Environment" || unitType == "Critter") continue; // training dummies, harmless animals
            var unit = Catalog.unitRecord(G.s(G.field(inf, "id")));
            if (unit != null && Catalog.isBoss(unit)) continue;
            if (Hazard.deadly(G.number(G.field(e, "posx")), G.number(G.field(e, "posy")), G.number(G.field(e, "posz")), 1.2)) continue; // in the water
            var foeLevel = G.integer(G.call("ent.GameObject", "get_level", e));
            var score = cost(e);
            var drops = false;
            if (wantHunt.length > 0 && unit != null) {
                var items = Catalog.unitItems(unit);
                for (id in wantHunt) if (items.exists(id)) { drops = true; break; }
            }
            if (leveling) {
                var diff = Math.abs(foeLevel - level);
                if (diff > (drops ? 6 : 3)) continue; // only monsters of about the hero's own level are worth the time
                score += diff * (drops ? 100 : 400);
            } else {
                if (!drops) continue;
                score += Math.max(0, foeLevel - level) * 250;
            }
            if (score < bestScore) { bestScore = score; best = e; kind = "mob"; }
        }
        if (best != null) {
            target = best; targetKind = kind; lockedFoe = null;
            Log.w("target mob " + G.s(G.field(G.field(best, "inf"), "id")) + " lvl " + G.call("ent.GameObject", "get_level", best) + " at " + Math.round(Nav.distance(hero, G.number(G.field(best, "posx")), G.number(G.field(best, "posy")))) + " m");
        }
    }

    function moveTo(x:Float, y:Float, arrive:Float, now:Float):Void {
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
            moveTo(x, y, Math.max(0.6, range * 0.5), now);
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

    function workMob(now:Float, leveling:Bool):Void {
        var x = G.number(G.field(target, "posx")), y = G.number(G.field(target, "posy"));
        message = Locale.f(leveling ? "stLevel" : "stHunt");
        var d = Nav.distance(hero, x, y);
        var range = rangedWeapon() ? 9.0 : 2.6;
        if (lockedFoe != target) {
            lockedFoe = target;
            try G.call("client.PlayerController", "lockTarget", G.current("client.PlayerController", "inst"), [target]) catch (_:Dynamic) {}
        }
        if (d > range) { releaseAttack(); moveTo(x, y, range - 0.6, now); return; }
        nav.stop();
        attack(now, x, y);
    }

    // ---- attacking ----

    /**
     * Fights the target: skills first (each one the moment the game says it is ready), and between them the Attack key is held, so
     * the combo goes on hit after hit (a held key asks for the next hit every frame; a tap per hit would lose the ones in between).
     */
    function attack(now:Float, tx:Float, ty:Float):Void {
        if (G.call("ent.GameObject", "isUnderAnyCC", hero) == true) return;
        holdAttack(now);
        if (now - lastAttack < 0.1) return;
        var active = G.call("ent.GameObject", "getActiveSkill", hero);
        if (active != null && !isBasic(active)) return; // a skill is being cast
        lastAttack = now;
        var ctl = G.current("client.PlayerController", "inst");
        for (skill in G.array(G.field(hero, "skills"))) {
            if (skill == null || G.field(skill, "removed") == true) continue;
            if (!usable(skill)) continue;
            var ok = false;
            try ok = Type.enumConstructor(G.call("st.skill.Skill", "checkUse", skill, [null])) == "Ok" catch (_:Dynamic) {}
            if (!ok) continue;
            var kind = G.s(G.field(skill, "kind"));
            try {
                releaseAttack(); // the held key would ask for a basic hit over the skill
                attackResumeAt = now + 0.35;
                if (isAim(skill)) {
                    var point = G.enumValue("st.skill.SkillTarget", "Point", [{x: tx, y: ty, z: G.number(G.field(target, "posz"))}]);
                    G.call("client.UnitController", "tryUseSkill", ctl, [skill, point]);
                } else G.call("client.UnitController", "requestSkillKind", ctl, ["Skill1", kind]);
                return;
            } catch (_:Dynamic) {}
        }
    }

    function isBasic(skill:Dynamic):Bool {
        try return G.call("st.skill.BaseSkill", "isBasicAttack", skill) == true catch (_:Dynamic) return false;
    }

    /** Not a passive, a dash, a block, a mount or a basic attack (that one is the Attack key). */
    function usable(skill:Dynamic):Bool {
        try {
            var nature = G.integer(G.field(G.field(skill, "inf"), "nature"), -1);
            if (nature == 5) return false;
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

    /** Presses the Attack key (the keyboard's own binding) and keeps it down. */
    function holdAttack(now:Float):Void {
        if (now < attackResumeAt) return;
        try {
            var binding = G.staticCall("lib.Input", "getBinding", ["Attack"]);
            var code = G.integer(G.field(binding, "code"), -1);
            if (code < 0) return;
            if (attackDown && attackCode == code && (now < attackResendAt || G.staticCall("hxd.Key", "isDown", [code]) == true)) return;
            attackCode = code;
            attackDown = true;
            attackResendAt = now + 0.3; // the game reads a key-down only on the frame after the event
            sendKey(code, true);
        } catch (_:Dynamic) {}
    }

    function releaseAttack():Void {
        if (attackDown && attackCode >= 0) sendKey(attackCode, false);
        attackDown = false;
    }

    function sendKey(code:Int, down:Bool):Void {
        try {
            var keyType = HlxRuntime.resolveType("hxd.Key");
            var eventType = HlxRuntime.resolveType("hxd.Event");
            var kindType = HlxRuntime.resolveType("hxd.EventKind");
            var kind = HlxRuntime.resolveStaticField(kindType, down ? "EKeyDown" : "EKeyUp");
            var event = HlxRuntime.constructInstanceByName(eventType, 3, [kind, 0.0, 0.0]);
            HlxRuntime.setField(event, "keyCode", code);
            HlxRuntime.callResolved(HlxRuntime.resolveStaticMember(keyType, "onEvent"), [event]);
        } catch (_:Dynamic) {}
    }

    // ---- loot ----

    /** Walks to the nearest drop (the pick-up itself is Loot.update's, the moment the hero is in the server's reach). */
    function seekLoot(now:Float):Bool {
        var best = Loot.nearest(hero, LOOT_SEEK, now);
        if (best == null) return false;
        var k = Loot.key(best);
        if (k != seekKey) { seekKey = k; seekSince = now; }
        // a drop that cannot be reached or taken (12 s of trying) is left alone for a minute
        if (nav.gaveUp || now - seekSince > 12) { nav.gaveUp = false; Loot.skip(best, now, 60); seekKey = ""; return false; }
        var x = G.number(G.field(best, "posx")), y = G.number(G.field(best, "posy"));
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
                    rows.push(i + ": near " + Math.round(AutoDodge.worldZ(x, y, hz, 2.2) * 10) / 10 + " deep " + Math.round(AutoDodge.worldZ(x, y, hz - 30, 30) * 10) / 10);
                }
                return {hero: [hx, hy, hz], rows: rows};
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
