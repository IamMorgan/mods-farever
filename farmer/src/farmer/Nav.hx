package farmer;

import farmer.GameAccess as G;
import farmer.NavGrid.Waypoint;

typedef ObeliskInfo = {id:String, x:Float, y:Float, z:Float, entity:Dynamic};

/**
 * Walking for the bot: the direction the hero runs in replaces the keyboard's (see Bot.steer), straight towards a spot, with
 * the obstacle handling of a player: a jump over a low obstacle, a sidestep around a wall, giving up on a spot that cannot be
 * reached. Water is never entered (see Hazard and NavGrid). Long ways go by obelisk (Hero.flyToObelisk) when that is much shorter,
 * and a fall from a cliff higher than NavGrid.GLIDE_DROP is glided down.
 */
class Nav {
    static inline var STUCK_CHECK = 0.25;
    static inline var STUCK_SHARE = 0.3;
    static inline var SPEED = 8.0;          // m/s, only to judge "stuck"
    static inline var GIVE_UP = 9.0;
    static inline var OBELISK_GAIN = 50.0;  // an obelisk trip must save at least this many metres
    static inline var OBELISK_FROM = 110.0; // ... and is only thought of for spots this far away
    static inline var BODY_SIDE = 0.42;
    static inline var FINE_STEP = 0.5;
    /** A rise of more than this between two samples half a metre apart is something the hero cannot walk over. */
    static inline var FINE_RISE = 0.75;
    /** The glider opens when the ground is this far below in a fall: every cliff above NavGrid.GLIDE_DROP is flown down. */
    static inline var GLIDE_HEIGHT = 4.0;

    public var active = false;
    public var tx = 0.0;
    public var ty = 0.0;
    public var arrive = 2.0;
    /** True once the spot was given up (stuck for too long). */
    public var gaveUp = false;
    /** The height of the spot the hero goes to (NaN: unknown). Set by the caller before `go`. */
    public var goalZ = Math.NaN;
    /** True when the last direction() gave a way to run: only then does the bot fake a pressed movement key (see Bot.moving). */
    public var hasDirection = false;
    var lastDiag = 0.0;
    var why = "";
    var calls = 0;
    var stuckLevel = 0;

    var lastX = 0.0;
    var lastY = 0.0;
    var lastCheck = 0.0;
    var blockedSince = -1.0;
    var sidestepUntil = 0.0;
    var sidestepSign = 1.0;
    var startedAt = 0.0;
    var jumpedAt = -10.0;
    var flightWait = 0.0;
    var flightTo = "";
    var obeliskTried:Map<String, Float> = new Map();
    var obeliskBad:Map<String, Float> = new Map();
    /** No flights by obelisk at all (the bot has been flying about without a fight: it walks and fights where it is). */
    public var noFly = false;
    /** When the flights by obelisk were started (the bot counts them: many and no fight is a loop). */
    public var flights:Array<Float> = [];
    /** Obelisks the hero flew to and found nothing to walk on from (a plateau, an island): not flown to again for an hour. */
    var obeliskDead:Map<String, Float> = new Map();
    var lastLandingId = "";
    var lastLandingAt = -1000.0;

    /** The obelisk of the last flight is a dead end if it was started less than `within` seconds ago. True when one was marked. */
    public function banLastLanding(now:Float, within:Float):Bool {
        if (lastLandingId == "" || now - lastLandingAt > within) return false;
        obeliskDead.set(lastLandingId, now + 3600);
        Log.t("nav", "the flight to " + lastLandingId + " led nowhere: it is not flown to for an hour");
        lastLandingId = "";
        return true;
    }

    /** The opened obelisks without the dead ends. */
    public function liveObelisks(hero:Dynamic, now:Float):Array<ObeliskInfo> {
        return [for (o in obelisks(hero)) if (!(obeliskDead.exists(o.id) && now < obeliskDead.get(o.id))) o];
    }
    /** The obelisk the hero is walking to (to fly from there), "" when none. */
    var walkId = "";
    /** True when no opened obelisk can be walked to: the caller must use another way (the home stone). */
    public var stranded = false;
    public function forgetObeliskTrouble():Void { obeliskBad = new Map(); stranded = false; }
    public function walkingToObelisk():Bool return walkId != "";
    var grid = new NavGrid();
    /** The reach maps: what ground the hero can walk to from where it stands (see NavGrid.flood), without cliffs and with the descents (glider) allowed. */
    var floodPlain = new FloodMap(false);
    var floodDown = new FloodMap(true);

    var reachHx = 0.0;
    var reachHy = 0.0;

    function floodOf(descents:Bool):FloodMap return descents ? floodDown : floodPlain;

    /** The hero stands in a region the reach map says is closed on foot (a gorge, a ledge, an island). */
    public function inClosedRegion(hero:Dynamic, now:Float):Bool {
        var f = floodPlain;
        // (a map of a few cells is made from a hero still falling after a flight: not a pit)
        return f.ready && floodFresh(f, hero, now) && f.grid.reachCount >= 30 && f.grid.reachClosed && !airborne(hero) && !flying(hero) && now >= flightWait + 8;
    }

    /** True when the reach map is known and was made near here lately. */
    function floodFresh(f:FloodMap, hero:Dynamic, now:Float):Bool {
        return f.ready && now - f.at < 60 && f.grid.floodCentre(G.number(G.field(hero, "posx")), G.number(G.field(hero, "posy"))) < 35;
    }

    function requestFlood(f:FloodMap, hero:Dynamic, now:Float):Void {
        NavGrid.hasGlider = hasGlider(hero);
        NavGrid.glideTrusted = glideWorks;
        NavGrid.glideAssumed = glideMode == 1 && glideFails == 0;
        NavGrid.setPads([for (pad in Pads.list) if (pad.id.indexOf("Flying") < 0 && pad.id.indexOf("Wall") < 0) pad]);
        f.grid.goalZ = Math.NaN;
        f.grid.noCliff = !f.descents;
        f.at = now; // (the old map stays in use until the new one is done: `ready` is not cleared)
        f.grid.startFlood(G.number(G.field(hero, "posx")), G.number(G.field(hero, "posy")), G.number(G.field(hero, "posz")), Hazard.heroInLiquid(hero));
    }

    /**
     * Can the hero walk to (x, y) at height z (NaN: any)? 1 yes, 0 no, -1 not known (no reach map yet, or the spot is beyond it).
     * `descents`: the map with the glider's descents allowed (for a hero on a ledge, an island).
     */
    /** The way's length (about metres) from where the reach map was made to the spot, NaN when not known. */
    public function pathCost(x:Float, y:Float, z:Float, descents:Bool = false):Float {
        var f = floodOf(descents);
        return f.ready ? f.grid.costTo(x, y, z, 2) : Math.NaN;
    }

    public function canReach(x:Float, y:Float, z:Float, descents:Bool = false):Int {
        var f = floodOf(descents);
        if (!f.ready) return -1;
        if (f.grid.floodCentre(reachHx, reachHy) > 70) return -1; // (a map made elsewhere - before a flight or the home stone - says nothing about here)
        return f.grid.reached(x, y, z, 2);
    }

    /**
     * Keeps the reach map fresh: true while it is being made (the caller waits a moment, at most a few seconds).
     */
    public function ensureReach(hero:Dynamic, now:Float, descents:Bool = false):Bool {
        reachHx = G.number(G.field(hero, "posx"));
        reachHy = G.number(G.field(hero, "posy"));
        var f = floodOf(descents);
        if (f.grid.state == 1) {
            if (f.waitSince < 0) f.waitSince = now;
            return now - f.waitSince < 5;
        }
        f.waitSince = -1;
        if (airborne(hero) || flying(hero)) return false;
        if (floodFresh(f, hero, now)) {
            // a closed region (a ledge, an island): the map with the descents is made too, the way out is by glider
            if (!descents && f.grid.reachCount > 0 && f.grid.reachClosed && !floodFresh(floodDown, hero, now)) return ensureReach(hero, now, true);
            return false;
        }
        requestFlood(f, hero, now);
        f.waitSince = now;
        return true;
    }

    public function floodCells(descents:Bool = false):Int return floodOf(descents).grid.reachCount;
    var route:Array<Waypoint> = null;
    var routeIndex = 0;
    var routeShort = 0.0;
    var needPlan = false;
    var planBlock = 0.0;
    var lastPlanX = 1e9;
    var lastPlanY = 1e9;
    var plannedAt = 0.0;
    var jumpedFor = -1;
    var lastDirX = 1.0;
    var lastDirY = 0.0;
    var aimAt = -10.0;
    var aimIdx = 0;
    var aimFrom = -1;
    var badAhead = 0;
    var deadTries = 0;
    var glideAskedAt = -10.0;
    /** How far ahead on the way the hero aims (m). */
    static inline var LOOK = 3.0;
    var atEnd = false;
    /** The route index of the landing waypoint of a throw under way (-1: none), and when the throw was seen. */
    var launchIdx = -1;
    var launchAt = 0.0;
    var padSince = -1.0;
    var lastFlipAt = -10.0;
    var goalHeading = false;
    var aimPX = 0.0;
    var aimPY = 0.0;

    public function new() {}

    /** True in a fight: no cliff (a drop deeper than NavGrid.CLIFF) is gone down; set by the caller before `go`. */
    public var noCliff = false;
    var plannedCliff = false;
    /**
     * Set by the caller before `go`: when no way exists without a cliff (the hero perched on a ledge a bumper threw it onto, a plateau),
     * the cliffs may be glided down after all (once per goal). Never in a fight.
     */
    public var descentOk = false;
    var cliffRetried = false;
    var noGain = 0;
    var cliffOverride = false;
    // circling / dithering detector: the hero's place once a second
    var trail:Array<{t:Float, x:Float, y:Float}> = [];
    var circleStrikes = 0;
    var lastCircleAt = -100.0;
    /** How often the direction flipped by more than 100 degrees in the last seconds (a jitter). */
    var flips = 0;
    var dirRing:Array<String> = [];
    var flipFrom = 0.0;

    public function go(x:Float, y:Float, arrive:Float, now:Float):Void {
        if (active && Math.abs(tx - x) < 0.5 && Math.abs(ty - y) < 0.5) {
            this.arrive = arrive;
            if (noCliff != plannedCliff) { needPlan = true; Log.t("nav", "cliff rule changed to " + noCliff + ": new path"); }
            return;
        }
        // a goal that only moved a little (a monster on the run) keeps the way: no stop to plan again at every step
        // (also while the way is still being worked out: starting the search over at every step would never let it finish)
        if (active && Math.abs(tx - x) < 6 && Math.abs(ty - y) < 6 && (route != null || grid.state == 1 || needPlan)) {
            tx = x;
            ty = y;
            this.arrive = arrive;
            return;
        }
        cliffRetried = false;
        cliffOverride = false;
        wadeGoal = false;
        wadeTried = false;
        noGain = 0;
        Log.t("nav", "go to " + Math.round(x) + "," + Math.round(y) + " (z " + (Math.isFinite(goalZ) ? Std.string(Math.round(goalZ)) : "?") + ", arrive " + arrive + ", noCliff " + noCliff + ")");
        trail = [];
        circleStrikes = 0;
        if (Math.abs(tx - x) > 8 || Math.abs(ty - y) > 8 || !active) { NavGrid.deadEnds = []; deadTries = 0; }
        active = true;
        gaveUp = false;
        tx = x;
        ty = y;
        this.arrive = arrive;
        blockedSince = -1;
        stuckLevel = 0;
        sidestepUntil = 0;
        startedAt = now;
        lastCheck = 0;
        route = null;
        needPlan = true;
        lastPlanX = 1e9;
        lastPlanY = 1e9;
        grid.state = 0;
    }

    /** One line for the log's status beat. */
    public function status(hero:Dynamic, now:Float):String {
        if (!active) return "nav off";
        return "nav " + Math.round(tx) + "," + Math.round(ty) + " d=" + Math.round(distance(hero, tx, ty) * 10) / 10 + " route " + (route == null ? "none" : routeIndex + "/" + route.length)
            + " dir " + hasDirection + " why " + why + " blocked " + (blockedSince < 0 ? "-" : Std.string(Math.round((now - blockedSince) * 10) / 10))
            + " stuckLvl " + stuckLevel + " flips " + flips + " cliff " + noCliff;
    }

    public function stop():Void {
        if (active) Log.t("nav", "stop (at " + Math.round(tx) + "," + Math.round(ty) + (gaveUp ? ", given up" : "") + ")");
        active = false;
        hasDirection = false;
        gaveUp = false;
        route = null;
        grid.state = 0;
    }

    public static function distance(hero:Dynamic, x:Float, y:Float):Float {
        var dx = x - G.number(G.field(hero, "posx")), dy = y - G.number(G.field(hero, "posy"));
        return Math.sqrt(dx * dx + dy * dy);
    }

    /**
     * True when the bot has a way to run (a path, or the spot is near): only then does it fake a pressed movement key (Bot.moving).
     * Not judged by direction(): the game asks for a direction only while a key is held, so that would never start.
     */
    public function wantsMove(hero:Dynamic):Bool {
        if (!active || flying(hero)) return false;
        return (route != null && route.length > 0) || distance(hero, tx, ty) <= 6 || airborne(hero);
    }

    public function debugRoute():Array<Waypoint> return route;
    public function goalX():Float return tx;
    public function goalY():Float return ty;

    public function arrived(hero:Dynamic):Bool return !active || distance(hero, tx, ty) <= arrive;

    /** Every frame: the path search, stuck handling, jumping, gliding. */
    public function update(hero:Dynamic, now:Float):Void {
        glide(hero);
        for (f in [floodPlain, floodDown]) {
            if (f.grid.state != 1) continue;
            f.grid.step(now);
            if (f.grid.state == 2) { f.grid.state = 0; f.ready = true; f.at = now; }
        }
        Pads.scan(hero, now);
        Pads.watch(hero, now, groundUnder(hero));
        checkLanding(hero, now);
        watchJump(hero, now);
        try watchFall(hero, now) catch (_:Dynamic) {}
        var wasWading = wade;
        wade = wadeGoal || Hazard.heroInLiquid(hero);
        NavGrid.wade = wade;
        if (wade != wasWading && active) { Log.t("nav", "wading " + (wade ? "on (" + (wadeGoal ? "the only way leads through water" : "the hero is in the water") + ")" : "off")); needPlan = true; planBlock = 0; }
        if (!active) return;
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy")), hz = G.number(G.field(hero, "posz"));
        if (distance(hero, tx, ty) <= arrive) { stop(); return; }
        planning(hero, hx, hy, hz, now);
        if (lastCheck == 0) { lastCheck = now; lastX = hx; lastY = hy; return; }
        if (now - lastCheck < STUCK_CHECK) return;
        var moved = Math.sqrt((hx - lastX) * (hx - lastX) + (hy - lastY) * (hy - lastY));
        var expected = SPEED * (now - lastCheck);
        lastCheck = now;
        lastX = hx;
        lastY = hy;
        if (now - lastDiag > 1.0) {
            lastDiag = now;
            trail.push({t: now, x: hx, y: hy});
            while (trail.length > 0 && now - trail[0].t > 9) trail.shift();
            circling(hero, hx, hy, now);
        }
        if (route == null || isHeld(hero) || flying(hero) || recentlyHit(hero)) { blockedSince = -1; return; }
        if (moved >= expected * STUCK_SHARE) { blockedSince = -1; return; }
        if (blockedSince < 0) blockedSince = now;
        var blocked = now - blockedSince;
        if (blocked > GIVE_UP) { stop(); gaveUp = true; return; }
        if (blocked > 0.35 && now - jumpedAt > 0.8) {
            // a jump only helps before a rise it clears; against a high wall it is only noise
            if (ledgeAhead(hero, hx, hy, lastDirX, lastDirY)) {
                jumpedAt = now;
                if (jumpSafe(hero, lastDirX, lastDirY)) { jump(hero); Log.t("nav", "stuck against a low ledge: jump"); trackJump(hero, now); }
            }
            else if (now - jumpedAt > 3) { jumpedAt = now; Log.t("nav", "stuck, no ledge a jump clears ahead (" + solidsAhead(hx, hy, hz, hx + lastDirX, hy + lastDirY) + "): no jump"); }
        }
        if (blocked > 0.7 && now - plannedAt > 1.0) {
            // ran into something the heights did not show: close the cells ahead (the path's own next cells and the line of
            // the run) and plan again; stuck at the same place again, the closed area grows, so the new path must differ
            stuckLevel = Math.abs(hx - lastPlanX) + Math.abs(hy - lastPlanY) < 3 ? stuckLevel + 1 : 1;
            var radius = Std.int(Math.min(1, stuckLevel - 1));
            var ahead:Array<{x:Float, y:Float}> = [{x: hx + lastDirX * 1.2, y: hy + lastDirY * 1.2}, {x: hx + lastDirX * 2.0, y: hy + lastDirY * 2.0}];
            if (route != null) for (i in routeIndex + 1...Std.int(Math.min(routeIndex + 4, route.length))) ahead.push({x: route[i].x, y: route[i].y});
            for (a in ahead) NavGrid.blockAround(a.x, a.y, radius, hx, hy, now);
            if (stuckLevel >= 6) { // the closed cells did not help: this spot cannot be reached from here
                Log.t("nav", "stuck at " + Math.round(hx) + "," + Math.round(hy) + " for good: spot given up");
                NavGrid.clearBlocked();
                stop();
                gaveUp = true;
                return;
            }
            Log.t("nav", "stuck at " + Math.round(hx) + "," + Math.round(hy) + " level " + stuckLevel + ": cells ahead closed");
            dumpStuck(hero, hx, hy, hz);
            needPlan = true;
            blockedSince = -1; // the new path gets its own time to prove itself
        }
    }

    /** Ran in circles / back and forth: a lot of way covered in nine seconds, no distance made. The cells of the route ahead are closed and a new way is looked for. */
    function circling(hero:Dynamic, hx:Float, hy:Float, now:Float):Void {
        if (route == null || isHeld(hero) || flying(hero) || trail.length < 8 || now - lastCircleAt < 9) return;
        var path = 0.0;
        for (i in 1...trail.length) path += Math.sqrt((trail[i].x - trail[i - 1].x) * (trail[i].x - trail[i - 1].x) + (trail[i].y - trail[i - 1].y) * (trail[i].y - trail[i - 1].y));
        var a = trail[0], b = trail[trail.length - 1];
        var net = Math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
        if (path > 18 && net < 5 && distance(hero, tx, ty) > arrive + 3) {
            lastCircleAt = now;
            circleStrikes++;
            Log.t("nav", "CIRCLING: " + Math.round(path) + " m run, " + Math.round(net) + " m made in 9 s at " + Math.round(hx) + "," + Math.round(hy) + " (strike " + circleStrikes + ")");
            NavGrid.addDeadEnd(hx, hy);
            for (i in routeIndex + 1...Std.int(Math.min(routeIndex + 5, route.length))) NavGrid.blockAround(route[i].x, route[i].y, 0, hx, hy, now);
            dumpStuck(hero, hx, hy, G.number(G.field(hero, "posz")));
            trail = [];
            if (circleStrikes >= 3) { Log.t("nav", "circling for good: spot given up"); NavGrid.clearBlocked(); stop(); gaveUp = true; return; }
            needPlan = true;
        } else if (net > 8) circleStrikes = 0;
    }

    /** Developer: a fine map (every 0.25 m) of the ground around the stuck hero and the objects near it, into the test log. */
    function dumpStuck(hero:Dynamic, hx:Float, hy:Float, hz:Float):Void {
        try {
            var ux = lastDirX, uy = lastDirY;
            hz = groundUnder(hero);
            var rows = ["fine map, heading " + Math.round(Math.atan2(uy, ux) * 180 / Math.PI) + " deg, '@' hero, up = ahead, ' ' none . flat o 0.35-0.75 # >0.75 v drop ~ water"];
            var u = 14;
            while (u >= -4) {
                var line = "";
                for (v in -8...9) {
                    var px = hx + ux * u * 0.25 - uy * v * 0.25, py = hy + uy * u * 0.25 + ux * v * 0.25;
                    var z = NavGrid.fineZ(px, py, hz);
                    var ch = " ";
                    if (Math.isFinite(z)) {
                        var d = z - hz;
                        ch = Hazard.wetCell(px, py, z, 0.0) ? "~" : d > 0.75 ? "#" : d > 0.35 ? "o" : d < -0.5 ? "v" : ".";
                    }
                    if (u == 0 && v == 0) ch = "@";
                    line += ch;
                }
                rows.push(line);
                u--;
            }
            Log.t("nav", rows.join("
"));
            var t = G.number(G.field(G.call("client.UnitController", "get_time", G.current("client.PlayerController", "inst")), "serverNow"), 0);
            Log.t("nav", "hero state: waitBeforeMove " + G.field(hero, "waitBeforeMove") + " ledgeBlock " + Math.round((G.number(G.field(hero, "ledgeBlockEnd")) - t) * 100) / 100 + " hitFreeze " + Math.round((G.number(G.field(hero, "hitFreezeEnd")) - t) * 100) / 100
                + " move " + Math.round(G.number(G.field(hero, "moveX")) * 100) / 100 + "," + Math.round(G.number(G.field(hero, "moveY")) * 100) / 100 + " running " + G.field(hero, "running") + " sprinting " + G.field(hero, "sprinting") + " jumpCount " + G.field(hero, "jumpCount")
                + " dash " + (G.field(hero, "activeDash") != null) + " queued " + (G.field(hero, "queuedSkill") != null) + " inaccessible " + G.field(hero, "inaccessibleStart") + " onPlatform " + G.field(hero, "isOnPlatform") + " gliding " + G.field(hero, "gliding")
                + " z " + Math.round(G.number(G.field(hero, "posz")) * 100) / 100 + " groundZ " + Math.round(groundUnder(hero) * 100) / 100 + " speed " + G.number(G.call("ent.Unit", "getMoveSpeed", hero, [null]), -1) + " cc " + (G.call("ent.GameObject", "isUnderAnyCC", hero) == true));
            var near = [];
            for (list in ["units", "interactibles", "entities"]) {
                var arr = G.field(G.field(hero, "layer"), list);
                if (arr == null) continue;
                for (e in G.fastArray(arr)) {
                    if (e == null || e == hero || G.field(e, "removed") == true) continue;
                    var ex = G.number(G.field(e, "posx"), 1e9), ey = G.number(G.field(e, "posy"), 1e9);
                    if (Math.abs(ex - hx) > 4 || Math.abs(ey - hy) > 4) continue;
                    var tag = "";
                    if (G.isA(e, "ent.Foe")) {
                        var foeInf = G.field(e, "inf");
                        var enemy = false;
                        try enemy = G.call("ent.GameObject", "isEnemyWith", hero, [e]) == true catch (_:Dynamic) {}
                        tag = "[" + G.s(G.field(foeInf, "id")) + (enemy ? " enemy" : " friend") + (G.field(e, "summonOwner") != null ? " summon" : "") + "]";
                    }
                    near.push(list + ":" + G.typeName(e) + tag + " " + Math.round((ex - hx) * 10) / 10 + "," + Math.round((ey - hy) * 10) / 10);
                }
            }
            Log.t("nav", "near objects: " + near.join(" | "));
            var rays = [];
            for (h in [0.3, 1.0]) {
                var row = [];
                for (i in 0...16) {
                    var a = i * Math.PI / 8;
                    row.push(Std.string(Math.round(Solid.ray(hx, hy, hz + h, hx + Math.cos(a) * 3, hy + Math.sin(a) * 3, hz + h) * 10) / 10));
                }
                rays.push("h" + h + ": " + row.join(" "));
            }
            Log.t("nav", "physics rays (3 m, 16 directions from east, counter-clockwise; -1 free): " + rays.join(" | "));
        } catch (e:Dynamic) Log.t("nav", "dumpStuck failed: " + Std.string(e));
    }

    static function windowFocused():Bool {
        try return G.call("hxd.Window", "get_isFocused", G.staticCall("hxd.Window", "getInstance", [])) == true catch (_:Dynamic) return false;
    }

    /** The hostile monsters within the search window except those at the spot itself (the target): the path keeps away from them. */
    function foesForPath(hero:Dynamic, gx:Float, gy:Float):Array<{x:Float, y:Float, r:Float}> {
        var out = [];
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy"));
        try {
            for (e in G.fastArray(G.field(G.field(hero, "layer"), "units"))) {
                if (out.length >= 40) break;
                if (e == null || e == hero || !G.isA(e, "ent.Foe") || G.field(e, "removed") == true || G.field(e, "dying") == true) continue;
                if (G.call("ent.GameObject", "isDead", e) == true || G.field(e, "summonOwner") != null) continue;
                if (G.call("ent.GameObject", "isEnemyWith", hero, [e]) != true) continue;
                var type = G.s(G.field(G.field(e, "inf"), "type"));
                if (type == "Environment" || type == "Critter") continue;
                var x = G.number(G.field(e, "posx")), y = G.number(G.field(e, "posy"));
                if (Math.abs(x - hx) > 135 || Math.abs(y - hy) > 135) continue;
                var id = G.s(G.field(G.field(e, "inf"), "id"));
                var unit = Catalog.unitRecord(id);
                // a boss: its whole ground is closed to the path
                var danger = unit != null && Catalog.isBoss(unit);
                var gd2 = (x - gx) * (x - gx) + (y - gy) * (y - gy);
                if (gd2 < 9) continue;
                if ((x - hx) * (x - hx) + (y - hy) * (y - hy) < 16) continue; // (the ones at the hero's feet are in a fight, not on the way)
                out.push({x: x, y: y, r: danger ? 28.0 : 7.0});
            }
        } catch (_:Dynamic) {}
        return out;
    }

    function planning(hero:Dynamic, hx:Float, hy:Float, hz:Float, now:Float):Void {
        // in the air (a jump, a fall, a glide, a trampoline's throw) the height under the hero is no place to plan from: a search from there
        // finds no ground to walk, counts as a dead end and the hero is left bouncing; the way is planned after the landing
        if (airborne(hero) && grid.state != 1) return;
        if (route != null && now - plannedAt > 6) needPlan = true;
        if (needPlan && grid.state != 1 && now >= planBlock) {
            needPlan = false;
            plannedAt = now;
            lastPlanX = hx;
            lastPlanY = hy;
            NavGrid.hasGlider = hasGlider(hero);
            NavGrid.glideTrusted = glideWorks;
        NavGrid.glideAssumed = glideMode == 1 && glideFails == 0;
            NavGrid.setPads([for (pad in Pads.list) if (pad.id.indexOf("Flying") < 0 && pad.id.indexOf("Wall") < 0) pad]);
            grid.goalZ = goalZ;
            grid.noCliff = noCliff && !cliffOverride;
            grid.foePts = foesForPath(hero, tx, ty);
            grid.dipOk = Math.isFinite(goalZ) && (canReach(tx, ty, goalZ, true) == 1 || canReach(tx, ty, goalZ, false) == 1);
            plannedCliff = noCliff;
            Log.t("nav", "planning from " + Math.round(hx) + "," + Math.round(hy) + "," + Math.round(hz) + " to " + Math.round(tx) + "," + Math.round(ty) + " glider " + NavGrid.hasGlider + " noCliff " + noCliff + " traps " + Hazard.trapCount());
            grid.start(hx, hy, hz, tx, ty, Hazard.heroInLiquid(hero));
        }
        if (grid.state == 1) grid.step(now);
        if ((grid.state == 2 && grid.unreachable || grid.state == 3) && noCliff && descentOk && !cliffRetried && distance(hero, tx, ty) > 6) {
            // no way without a cliff (a ledge, a plateau the hero stands on): the glider may take the hero down after all
            cliffRetried = true;
            cliffOverride = true;
            grid.state = 0;
            needPlan = true;
            planBlock = 0;
            Log.t("nav", "no way to " + Math.round(tx) + "," + Math.round(ty) + " without a cliff: descents by glider allowed for this goal");
            return;
        }
        if (grid.state == 2) {
            if (grid.unreachable && distance(hero, tx, ty) > 6 && !wade && !wadeTried) {
                // no dry way: a stretch of water on the way is walked through (a swim of a few metres is cheaper than never getting there)
                wadeTried = true;
                wadeGoal = true;
                wade = true;
                NavGrid.wade = true;
                grid.state = 0;
                needPlan = true;
                planBlock = 0;
                Log.t("nav", "no dry way to " + Math.round(tx) + "," + Math.round(ty) + ": wading through water allowed for this goal");
                return;
            }
            if (grid.unreachable && distance(hero, tx, ty) > 6) {
                Log.t("nav", "spot " + Math.round(tx) + "," + Math.round(ty) + " cannot be reached from here (the ground around runs out " + Math.round(grid.shortBy) + " m short): given up");
                grid.state = 0;
                stop();
                gaveUp = true;
                return;
            }
            // a path that ends short of the spot and brings the hero no nearer to it (a dead end against a wall, a way that first leads away): a few of
            // them in a row mean the spot cannot be reached from here by planning window after window - given up, not paced out
            if (grid.shortBy > 3) {
                var gain = distance(hero, tx, ty) - grid.shortBy;
                noGain = gain < 10 ? noGain + 1 : 0;
                if (noGain >= 4 && distance(hero, tx, ty) > 40) {
                    Log.t("nav", "the last " + noGain + " paths to " + Math.round(tx) + "," + Math.round(ty) + " end short without bringing the hero nearer: given up");
                    noGain = 0;
                    grid.state = 0;
                    stop();
                    gaveUp = true;
                    return;
                }
            } else noGain = 0;
            route = grid.path;
            routeShort = grid.shortBy;
            routeIndex = 0;
            atEnd = false;
            goalHeading = false;
            aimFrom = -1;
            jumpedFor = -1;
            grid.state = 0;
        } else if (grid.state == 3) {
            grid.state = 0;
            route = null;
            planBlock = now + 1.5;
            NavGrid.addDeadEnd(hx, hy);
            if (distance(hero, tx, ty) > 6 && ++deadTries > 4) { stop(); gaveUp = true; }
            else needPlan = true;
        }
    }

    /** A throw is over (the hero is on the ground again): on the ledge aimed at, or a miss (the landing is closed and the way planned again). */
    function checkLanding(hero:Dynamic, now:Float):Void {
        if (launchIdx < 0) return;
        if (route == null || launchIdx >= route.length) { launchIdx = -1; return; }
        if (airborne(hero) || Pads.flying() || now - launchAt < 0.6) return;
        var w = route[launchIdx];
        var miss = distance(hero, w.x, w.y);
        if (miss <= 4.5 && Math.abs(G.number(G.field(hero, "posz")) - NavGrid.fineZ(w.x, w.y, G.number(G.field(hero, "posz")))) < 3.5) {
            Log.t("nav", "LANDED on the ledge (" + Math.round(miss * 10) / 10 + " m from the landing)");
            routeIndex = launchIdx;
            aimFrom = -1;
        } else if (miss <= 10 && Math.abs(G.number(G.field(hero, "posz")) - NavGrid.fineZ(w.x, w.y, G.number(G.field(hero, "posz")))) < 3.5) {
            // on the same ledge, a few metres off the aimed cell: a new way from here (the throw itself worked)
            Log.t("nav", "LANDED on the ledge, " + Math.round(miss) + " m from the aimed cell: new way from here");
            needPlan = true;
        } else {
            Log.t("nav", "throw MISSED the landing by " + Math.round(miss) + " m (hero z " + Math.round(G.number(G.field(hero, "posz"))) + "): landing closed, new way");
            NavGrid.badLanding(w.x, w.y, now);
            Pads.shrink();
            needPlan = true;
        }
        launchIdx = -1;
    }

    /** A hit just landed (the hero staggers a moment): standing still then is no sign of a wall. */
    function recentlyHit(hero:Dynamic):Bool {
        try {
            var t = G.number(G.field(G.call("client.UnitController", "get_time", G.current("client.PlayerController", "inst")), "serverNow"), -1);
            var last = G.number(G.field(hero, "lastDamageTime"), -1000);
            return t >= 0 && t - last < 1.2;
        } catch (_:Dynamic) return false;
    }

    function isHeld(hero:Dynamic):Bool {
        try {
            if (G.call("ent.GameObject", "isUnderAnyCC", hero) == true) return true;
            return G.call("ent.GameObject", "getActiveSkill", hero) != null;
        } catch (_:Dynamic) return false;
    }

    /**
     * A jump carries the hero about 4 m forward in 0.75 s (measured): the ground 1..5 m ahead on the heading must be there, no deeper than a
     * cliff and dry - or the jump is a fall (the heading is the hero's run, (ux, uy) a unit vector).
     */
    function jumpSafe(hero:Dynamic, ux:Float, uy:Float):Bool {
        var gz = groundUnder(hero);
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy"));
        for (a in [1.0, 2.0, 3.0, 4.0, 5.0]) {
            var z = NavGrid.fineZ(hx + ux * a, hy + uy * a, gz);
            if (!Math.isFinite(z) || gz - z > NavGrid.safeDrop() || Hazard.wetCell(hx + ux * a, hy + uy * a, z, 0.5)) {
                Log.t("nav", "jump refused: no safe landing " + a + " m ahead (" + (Math.isFinite(z) ? "a drop of " + Math.round((gz - z) * 10) / 10 + " m or water" : "no ground") + ")");
                return false;
            }
        }
        return true;
    }

    public static function jump(hero:Dynamic):Void {
        try {
            var ctl = G.current("client.PlayerController", "inst");
            var now = G.number(G.field(G.call("client.UnitController", "get_time", ctl), "serverNow"), -1);
            if (now >= 0) G.set(ctl, "requestJumpTime", now);
        } catch (_:Dynamic) {}
    }

    public static function hasGlider(hero:Dynamic):Bool {
        try return G.call("st.Equipment", "getSlot", G.call("ent.Hero", "get_equipment", hero), ["Slot_Glider"]) != null catch (_:Dynamic) return true;
    }

    /** The height of the ground under the hero (the game's own question), the hero's own height when unknown. */
    static function groundUnder(hero:Dynamic):Float {
        var z = G.number(G.field(hero, "posz"));
        try return G.number(G.call("ent.Entity", "getGroundZ", hero), z) catch (_:Dynamic) return z;
    }

    /** Falling from a height: open the glider (the way down from a cliff). The game itself says when it may open (canStartGlide). */
    function glide(hero:Dynamic):Void {
        try {
            if (G.field(hero, "gliding") == true) { glideWorks = true; glideSeen = true; return; }
            var t = haxe.Timer.stamp();
            if (glideCheckAt > 0 && t >= glideCheckAt) {
                glideCheckAt = -1;
                glideFails++;
                Log.t("nav", "GLIDER did not hold 0.35 s after the request (mode " + glideMode + "): " + glideWhy(hero));
                if (glideFails % 3 == 0) { glideMode = 1 - glideMode; Log.t("nav", "glider mode switched to " + glideMode); } // (the other way of opening it)
            }
            if (t - glideAskedAt < 0.5) return; // the request travels to the server and back: one at a time
            var above = G.number(G.field(hero, "posz")) - groundUnder(hero);
            if (above < GLIDE_HEIGHT) return;
            if (G.call("ent.Hero", "canStartGlide", hero) == true) {
                glideAskedAt = t;
                if (glideMode == 1) G.call("ent.Hero", "toggleGlide", hero, [true]); // (what the game's own jump key does in the toggle mode)
                else G.call("ent.Hero", "enterGlider", hero);
                glideCheckAt = t + 0.35;
                Log.t("nav", "glider opened at " + Math.round(above) + " m above the ground");
            }
        } catch (_:Dynamic) {}
    }

    /** Developer: how the glider is opened (0 the server request enterGlider, 1 toggleGlide as the jump key does). */
    public static var glideMode = 1;
    var glideCheckAt = -1.0;
    var glideFails = 0;
    var glideSeen = false;
    /** True once a glide was seen to hold in this session (a descent by glider is trusted only after that). */
    public static var glideWorks = false;

    /** Diagnostics: why a glide the bot asked for did not hold (every condition of the game's canGlide, one by one). */
    function glideWhy(hero:Dynamic):String {
        var parts = [];
        function chk(name:String, f:() -> Dynamic):Void { try parts.push(name + "=" + Std.string(f())) catch (_:Dynamic) parts.push(name + "=?"); }
        var t = G.number(G.field(G.call("client.UnitController", "get_time", G.current("client.PlayerController", "inst")), "serverNow"), 0);
        chk("propulsion", () -> G.call("ent.Unit", "isInPropulsion", hero));
        chk("blockEnd", () -> Math.round((G.number(G.field(hero, "gliderBlockEnd")) - t) * 100) / 100);
        chk("grapple", () -> G.call("ent.Unit", "isGrappling", hero));
        chk("moveModeOk", () -> G.call("ent.Hero", "moveModeAllowGlide", hero));
        chk("canGlide", () -> G.call("ent.Hero", "canGlide", hero));
        chk("canStart", () -> G.call("ent.Hero", "canStartGlide", hero));
        chk("gliding", () -> G.field(hero, "gliding"));
        chk("timeOnGround", () -> G.field(G.field(hero, "body"), "timeOnGround"));
        chk("inTrigger2", () -> G.call("ent.Unit", "isInTriggerWithFlag", hero, [2]));
        chk("water", () -> G.call("ent.Unit", "isInWater", hero));
        chk("lastGlideEnd", () -> Math.round((G.number(G.field(hero, "lastGlideEnd")) - t) * 100) / 100);
        chk("z", () -> Math.round(G.number(G.field(hero, "posz"))));
        return parts.join(" ");
    }

    function airborne(hero:Dynamic):Bool {
        try return G.field(hero, "gliding") == true || G.number(G.field(hero, "posz")) - groundUnder(hero) > 2.5 catch (_:Dynamic) return false;
    }

    /**
     * The way the hero can run from (hx, hy) to (wx, wy) as a body: the ground rises no more than a step half a metre on, on the
     * middle line and on both sides, and no water lies on it. Thin things (posts, bushes) that the cells' centres miss show here.
     */
    /** Why the last corridor check said no (for the log). */
    public static var corridorWhy = "";
    /** Water may be walked through (the hero is in it, or no dry way leads to the goal): the corridor test and the planner let it pass. */
    public static var wade = false;
    var wadeGoal = false;
    var wadeTried = false;

    public static function corridorClear(hx:Float, hy:Float, hz:Float, wx:Float, wy:Float, cliff:Bool = false, solids:Bool = true):Bool {
        var dx = wx - hx, dy = wy - hy;
        var len = Math.sqrt(dx * dx + dy * dy);
        if (len < 0.3) return true;
        var ux = dx / len, uy = dy / len;
        var sx = -uy * BODY_SIDE, sy = ux * BODY_SIDE;
        var prev = NavGrid.fineZ(hx, hy, hz);
        if (!Math.isFinite(prev) || Math.abs(prev - hz) > 3) prev = hz;
        var n = Std.int(Math.ceil(len / FINE_STEP));
        for (i in 1...n + 1) {
            var t = Math.min(len, i * FINE_STEP);
            var px = hx + ux * t, py = hy + uy * t;
            var z = NavGrid.fineZ(px, py, prev);
            if (!Math.isFinite(z)) { corridorWhy = "no ground at " + Math.round(px) + "," + Math.round(py); return false; }
            if (z - prev > FINE_RISE) { corridorWhy = "rise " + Math.round((z - prev) * 100) / 100 + " m at " + Math.round(px * 10) / 10 + "," + Math.round(py * 10) / 10; return false; }
            if (cliff && prev - z > NavGrid.safeDrop()) { corridorWhy = "drop " + Math.round((prev - z) * 100) / 100 + " m at " + Math.round(px) + "," + Math.round(py); return false; }
            if ((!wade && Hazard.wetCell(px, py, z, 0.45)) || Hazard.trapAt(px, py, z)) { corridorWhy = "water or trap at " + Math.round(px) + "," + Math.round(py); return false; }
            // a prop with a body (bench, post, flower bed) that the heights miss: rays along this half metre, over the rising ground, on the
            // middle line and on both sides of the body
            if (solids && Solid.works) {
                var lift = Math.max(z, prev);
                var ax = hx + ux * Math.max(0, t - FINE_STEP), ay = hy + uy * Math.max(0, t - FINE_STEP);
                for (line in [0.0, 1.0, -1.0]) {
                    for (h in [0.45, 1.0]) {
                        if (Solid.ray(ax + sx * line, ay + sy * line, lift + h, px + sx * line, py + sy * line, lift + h) >= 0) { corridorWhy = "body on line " + line + " h " + h + " at " + Math.round(px * 10) / 10 + "," + Math.round(py * 10) / 10; return false; }
                    }
                }
            }
            for (side in [1.0, -1.0]) {
                var qx = px + sx * side, qy = py + sy * side;
                var q = NavGrid.fineZ(qx, qy, z);
                if (!Math.isFinite(q)) { corridorWhy = "no ground beside at " + Math.round(qx) + "," + Math.round(qy); return false; }
                if (q - z > FINE_RISE) { corridorWhy = "wall beside (" + Math.round((q - z) * 100) / 100 + " m) at " + Math.round(qx * 10) / 10 + "," + Math.round(qy * 10) / 10; return false; }
                if (cliff && z - q > NavGrid.safeDrop()) { corridorWhy = "cliff edge beside (" + Math.round((z - q) * 100) / 100 + " m) at " + Math.round(qx * 10) / 10 + "," + Math.round(qy * 10) / 10; return false; }
                if (!wade && Hazard.wetCell(qx, qy, q, 0.3)) { corridorWhy = "water beside"; return false; }
            }
            prev = z;
        }
        return true;
    }

    /** True when a cliff (a drop deeper than NavGrid.CLIFF) or no ground at all lies within `r` metres of (hx, hy): a knock or a dodge there would be a fall. */
    public static function edgeNear(hx:Float, hy:Float, hz:Float, r:Float):Bool {
        for (i in 0...8) {
            var a = i * Math.PI / 4;
            var z = NavGrid.fineZ(hx + Math.cos(a) * r, hy + Math.sin(a) * r, hz);
            if (!Math.isFinite(z) || hz - z > NavGrid.CLIFF) return true;
        }
        return false;
    }

    var zRing:Array<{t:Float, z:Float}> = [];
    var lastFellAt = -100.0;

    /**
     * Diagnostics: the ground under the hero is more than 2.5 m lower than 1.2 s ago (a jump changes the hero's height, not the ground's),
     * and the hero is not flying to an obelisk: what the bot was doing, so a fall can be explained, not guessed.
     */
    function watchFall(hero:Dynamic, now:Float):Void {
        var z = groundUnder(hero);
        zRing.push({t: now, z: z});
        while (zRing.length > 0 && now - zRing[0].t > 1.2) zRing.shift();
        // (more than 40 m in a second is a teleport - the home stone, a zone change - not a fall)
        if (zRing.length < 2 || zRing[0].z - z <= NavGrid.safeDrop() + 0.4 || zRing[0].z - z > 40 || now - lastFellAt < 3 || flying(hero)) return;
        lastFellAt = now;
        Log.t("nav", "FELL " + Math.round((zRing[0].z - z) * 10) / 10 + " m in " + Math.round((now - zRing[0].t) * 10) / 10 + " s at " + Math.round(G.number(G.field(hero, "posx"))) + "," + Math.round(G.number(G.field(hero, "posy")))
            + " | nav " + (active ? "on" : "off") + " noCliff " + noCliff + " route " + routeIndex + "/" + (route == null ? 0 : route.length) + " heading " + Math.round(lastDirX * 100) / 100 + "," + Math.round(lastDirY * 100) / 100
            + " | dodge " + AutoDodge.dodging() + " gliding " + (G.field(hero, "gliding") == true) + " jumped " + (now - jumpedAt > 100 ? "long ago" : Std.string(Math.round((now - jumpedAt) * 10) / 10) + " s ago") + " | cc " + (G.call("ent.GameObject", "isUnderAnyCC", hero) == true)
            + " knocked " + (G.call("ent.GameObject", "isKnocked", hero) == true));
    }

    /** In the air the hero must not come down in water: the heading is turned to the nearest direction whose landing ground is dry. */
    function airHeading(hx:Float, hy:Float, hz:Float, dx:Float, dy:Float):{x:Float, y:Float} {
        var base = Math.atan2(dy, dx);
        for (turn in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4, 3.14]) {
            var a = base + turn;
            var ux = Math.cos(a), uy = Math.sin(a);
            var bad = false;
            for (r in [5.0, 9.0, 14.0]) {
                var px = hx + ux * r, py = hy + uy * r;
                var z = NavGrid.fineZ(px, py, hz - 12);
                if (Math.isFinite(z) && Hazard.wetCell(px, py, z, 1.2)) { bad = true; break; }
            }
            if (!bad) return {x: ux, y: uy};
        }
        return {x: dx, y: dy};
    }

    function flying(hero:Dynamic):Bool {
        try return G.call("ent.Hero", "isFlyingToObelisk", hero) == true catch (_:Dynamic) return false;
    }

    /** The direction (unit vector x, y) to run in, or null when there is nowhere to go (or the path is still being worked out). */
    public function direction(hero:Dynamic, now:Float):Null<{x:Float, y:Float}> {
        hasDirection = false;
        calls++;
        why = "";
        if (!active || flying(hero)) { why = "inactive/flying"; return null; }
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy")), hz = G.number(G.field(hero, "posz"));
        var aimX = tx, aimY = ty;
        if (route != null && route.length > 0) {
            var last = route.length - 1;
            // progress along the way: a waypoint is passed when the hero is at it, or (not a jump) beyond it along its segment
            while (routeIndex < last) {
                var from = route[routeIndex], to = route[routeIndex + 1];
                var near = Math.abs(to.x - hx) + Math.abs(to.y - hy) < 1.1;
                var beyond = !to.jump && (hx - to.x) * (to.x - from.x) + (hy - to.y) * (to.y - from.y) >= 0 && Math.abs(to.x - hx) + Math.abs(to.y - hy) < 2.5;
                if (near || beyond) routeIndex++; else break;
            }
            if (routeIndex >= last && routeShort > 3 && !needPlan) {
                // the path only led part of the way: plan again from here, away from the dead ends found so far
                if (Math.abs(hx - lastPlanX) + Math.abs(hy - lastPlanY) < 4) {
                    NavGrid.addDeadEnd(hx, hy);
                    if (++deadTries > 5) { why = "short route end"; stop(); gaveUp = true; return null; }
                }
                needPlan = true;
            }
            if (routeIndex >= last && routeShort <= 3 && !needPlan && distance(hero, tx, ty) > arrive + 1.5 && now - plannedAt > 0.6) needPlan = true; // the goal moved on: a new way from here
            var pick = Std.int(Math.min(routeIndex + 1, last));
            if (routeIndex >= last) atEnd = true;
            var flyLeg = !atEnd && route[pick].fly;
            if (!flyLeg && padSince >= 0) padSince = -1;
            if (!flyLeg && !atEnd && (aimFrom != routeIndex || now - aimAt > 0.12)) {
                aimAt = now;
                aimFrom = routeIndex;
                // pure pursuit: the aim is the point on the way LOOK metres ahead of the hero (never past a jump), so it always lies
                // ahead and the heading cannot flip; when the body cannot run straight to it, a nearer point is tried
                var chosenX = route[pick].x, chosenY = route[pick].y, chosenIdx = pick;
                var found = false;
                for (look in [LOOK, LOOK * 0.6, 1.2]) {
                    var acc = 0.0, cx = hx, cy = hy, px = route[pick].x, py = route[pick].y, pi = pick;
                    var j = pick;
                    while (j <= last) {
                        var seg = Math.sqrt((route[j].x - cx) * (route[j].x - cx) + (route[j].y - cy) * (route[j].y - cy));
                        if (acc + seg >= look && seg > 0.001) {
                            var t = (look - acc) / seg;
                            px = cx + (route[j].x - cx) * t;
                            py = cy + (route[j].y - cy) * t;
                            pi = j;
                            break;
                        }
                        acc += seg;
                        cx = route[j].x;
                        cy = route[j].y;
                        px = cx;
                        py = cy;
                        pi = j;
                        if (route[j].jump) break;
                        j++;
                    }
                    // not across a hairpin of the way: the aim stays within 60 degrees of the next waypoint's direction
                    var toPick = Math.sqrt((route[pick].x - hx) * (route[pick].x - hx) + (route[pick].y - hy) * (route[pick].y - hy));
                    var toAim = Math.sqrt((px - hx) * (px - hx) + (py - hy) * (py - hy));
                    var cosTurn = toPick < 0.3 || toAim < 0.3 ? 1.0 : ((route[pick].x - hx) * (px - hx) + (route[pick].y - hy) * (py - hy)) / (toPick * toAim);
                    if (look <= 1.2 || (cosTurn > 0.5 && corridorClear(hx, hy, hz, px, py, noCliff))) { chosenX = px; chosenY = py; chosenIdx = pi; found = true; break; }
                }
                aimIdx = chosenIdx;
                aimPX = chosenX;
                aimPY = chosenY;
                if (found && chosenIdx == pick && !route[pick].jump && distance(hero, route[pick].x, route[pick].y) > 1.0 && !airborne(hero)) {
                    if (!corridorClear(hx, hy, hz, route[pick].x, route[pick].y, noCliff)) {
                        if (++badAhead >= 3 && now - plannedAt > 0.8) {
                            // the next cell is not passable for a body (a post, a bush the cells' centres missed): closed, a new path
                            NavGrid.blockLong(route[pick].x, route[pick].y, now);
                            Log.t("nav", "blocked ahead at " + Math.round(route[pick].x) + "," + Math.round(route[pick].y) + ": replanning, reason: " + corridorWhy + " (" + solidsAhead(hx, hy, hz, route[pick].x, route[pick].y) + ")");
                            needPlan = true;
                            badAhead = 0;
                        }
                    } else badAhead = 0;
                } else badAhead = 0;
            }
            if (flyLeg) {
                // a throw from a bumper: onto the pad's centre first, then (thrown) straight at the landing
                var pad = route[routeIndex];
                var inAir = airborne(hero) || Pads.flying();
                if (inAir) {
                    if (launchIdx < 0) { launchIdx = pick; launchAt = now; Log.t("nav", "thrown towards " + Math.round(route[pick].x) + "," + Math.round(route[pick].y) + " (" + Math.round(distance(hero, route[pick].x, route[pick].y)) + " m)"); }
                    aimX = route[pick].x; aimY = route[pick].y;
                } else {
                    aimX = pad.x; aimY = pad.y;
                    if (distance(hero, pad.x, pad.y) < 0.8) {
                        if (padSince < 0) padSince = now;
                        aimX = route[pick].x; aimY = route[pick].y; // (on the pad: keep going the way of the throw)
                        if (now - padSince > 2.5) {
                            Log.t("nav", "the bumper at " + Math.round(pad.x) + "," + Math.round(pad.y) + " did not throw the hero: closed for a while");
                            NavGrid.blockLong(pad.x, pad.y, now);
                            padSince = -1;
                            needPlan = true;
                        }
                    } else padSince = -1;
                }
            }
            else if (atEnd) { aimX = route[last].x; aimY = route[last].y; }
            else { aimX = aimPX; aimY = aimPY; }
            var next = route[pick];
            if (next.jump && !next.fly && jumpedFor != routeIndex && jumpDue(hero, hx, hy, hz, next)) {
                jumpedFor = routeIndex;
                var jd = Math.sqrt((next.x - hx) * (next.x - hx) + (next.y - hy) * (next.y - hy));
                if (jd < 0.1 || jumpSafe(hero, (next.x - hx) / jd, (next.y - hy) / jd)) { jump(hero); noteJump(hero, hx, hy, next); }
                else { NavGrid.blockLong(next.x, next.y, now); needPlan = true; } // the ledge cannot be taken safely: another way
            }
        } else if (distance(hero, tx, ty) > 6 && !airborne(hero)) { why = "planning"; return null; }
        // (in the air without a way the hero glides straight towards the spot, see airHeading below)
        var dx = aimX - hx, dy = aimY - hy;
        var d = Math.sqrt(dx * dx + dy * dy);
        var keepHeading = d < 0.6 && !atEnd && route != null;
        if (keepHeading) {
            // on the pursuit point in the middle of the way: the next one is picked within a moment, the run goes on (turning to the far spot
            // from here and back to the way the next frame is what made the hero shake in place)
            dx = lastDirX;
            dy = lastDirY;
            d = 1.0;
        } else if (d < 0.6 || (atEnd && goalHeading)) {
            // right at the end of the way: on to the spot itself (and once on it, only that: a heading from so near flips between the two)
            if (distance(hero, tx, ty) <= arrive) { why = "at aim"; return null; }
            dx = tx - hx;
            dy = ty - hy;
            d = Math.sqrt(dx * dx + dy * dy);
            if (d < 0.6) { why = "at aim"; return null; }
            goalHeading = true;
            if (route != null && !needPlan && now - plannedAt > 0.6 && distance(hero, tx, ty) > 3) needPlan = true;
        }
        dx /= d;
        dy /= d;
        if (airborne(hero)) { var h = airHeading(hx, hy, hz, dx, dy); dx = h.x; dy = h.y; }
        // jitter: the heading turning back on itself again and again
        if (dx * lastDirX + dy * lastDirY < -0.17) {
            // a second turn-around within 0.7 s is not followed (a hero that reverses again and again goes nowhere): the last heading holds
            if (now - lastFlipAt < 0.7 && !goalHeading) { dx = lastDirX; dy = lastDirY; }
            else { flips++; lastFlipAt = now; }
        }
        if (now - flipFrom > 5) {
            if (flips >= 6) Log.t("nav", "JITTER: the heading flipped " + flips + " times in 5 s at " + Math.round(hx) + "," + Math.round(hy) + " (last headings: " + dirRing.join(" | ") + "; aim " + Math.round(aimX) + "," + Math.round(aimY) + ", route " + routeIndex + "/" + (route == null ? 0 : route.length) + ")");
            flips = 0;
            flipFrom = now;
        }
        dirRing.push(Math.round(dx * 100) / 100 + "," + Math.round(dy * 100) / 100 + "@" + Math.round(hx * 10) / 10 + "," + Math.round(hy * 10) / 10 + " aim" + aimIdx + "/" + routeIndex + (airborne(hero) ? " air" : ""));
        if (dirRing.length > 10) dirRing.shift();
        lastDirX = dx;
        lastDirY = dy;
        hasDirection = true;
        return {x: lastDirX, y: lastDirY};
    }

    // ---- jumps ----

    /** The jump height the hero was measured to make (0: not yet), the seconds it takes to climb to each tenth of a metre (-1: never). */
    public static var jumpPeak = 0.0;
    static var jumpClimb:Array<Float> = [];
    var jumpTrack = false;
    var jumpBase = 0.0;
    var jumpMax = 0.0;
    var jumpT0 = 0.0;
    var jumpX0 = 0.0;
    var jumpY0 = 0.0;
    var jumpProfile:Array<String> = [];
    var profT:Array<Float> = [];
    var profZ:Array<Float> = [];
    /** The measured climb of the standing jump: seconds to reach each height (see timeToReach). */
    static var climbT:Array<Float> = [];
    static var climbZ:Array<Float> = [];
    var jumpWantRise = Math.NaN;
    var jumpWantX = 0.0;
    var jumpWantY = 0.0;
    var jumpCalibrating = false;
    var jumpTries = 0;
    var calibNoteAt = -10.0;
    var calibSeen = false;

    /** Starts watching a jump: the highest point and the time up are measured (and logged, so the planner's jump height is known). */
    function trackJump(hero:Dynamic, now:Float):Void {
        jumpTrack = true;
        jumpWantRise = Math.NaN;
        jumpBase = G.number(G.field(hero, "posz"));
        jumpMax = 0;
        jumpT0 = now;
        jumpX0 = G.number(G.field(hero, "posx"));
        jumpY0 = G.number(G.field(hero, "posy"));
        jumpProfile = [];
        profT = [];
        profZ = [];
    }

    function watchJump(hero:Dynamic, now:Float):Void {
        if (!jumpTrack) return;
        var z = G.number(G.field(hero, "posz")) - jumpBase;
        var t = now - jumpT0;
        if (z > jumpMax) jumpMax = z;
        if (t < 2.0) { jumpProfile.push(Math.round(t * 100) / 100 + ":" + Math.round(z * 100) / 100); profT.push(t); profZ.push(z); }
        var grounded = G.number(G.field(hero, "posz")) - groundUnder(hero) < 0.1;
        if (t > 0.25 && grounded || t > 3) {
            jumpTrack = false;
            var fwd = Math.sqrt(Math.pow(G.number(G.field(hero, "posx")) - jumpX0, 2) + Math.pow(G.number(G.field(hero, "posy")) - jumpY0, 2));
            var level = Math.abs(G.number(G.field(hero, "posz")) - groundUnder(hero) - 0) < 0.5;
            Log.t("nav", "JUMP measured: peak " + Math.round(jumpMax * 100) / 100 + " m above the takeoff, air time " + Math.round(t * 100) / 100 + " s, " + Math.round(fwd * 10) / 10 + " m along, profile " + jumpProfile.slice(0, 40).join(" "));
            if (jumpCalibrating && jumpMax > 0.3) {
                jumpPeak = jumpMax;
                climbT = profT;
                climbZ = profZ;
                // the planner sees rises up to 2.2 m (the height probe, see NavGrid.height): jumps are planned up to the lower of that and the peak less a margin
                NavGrid.JUMP_UP = Math.max(0.8, Math.min(NavGrid.JUMP_MAX, jumpMax - 0.8));
                Log.t("nav", "jump height learnt: peak " + Math.round(jumpMax * 100) / 100 + " m, the planner jumps up to " + Math.round(NavGrid.JUMP_UP * 100) / 100 + " m");
            }
            if (Math.isFinite(jumpWantRise)) {
                var got = G.number(G.field(hero, "posz")) - jumpBase;
                var ok = got >= jumpWantRise - 0.35;
                Log.t("nav", "JUMP result: wanted a rise of " + Math.round(jumpWantRise * 100) / 100 + " m, got " + Math.round(got * 100) / 100 + " m (peak " + Math.round(jumpMax * 100) / 100 + "): " + (ok ? "ON the ledge" : "FAILED, the ledge is closed"));
                if (!ok) NavGrid.blockLong(jumpWantX, jumpWantY, haxe.Timer.stamp());
                jumpWantRise = Math.NaN;
            }
            jumpCalibrating = false;
        }
    }

    /** Standing still on the flat, one jump to learn how high the hero jumps; true while the measurement is going on or just started. */
    public function calibrateJump(hero:Dynamic, now:Float):Bool {
        if (!calibSeen) { calibSeen = true; Log.t("nav", "jump calibration check: peak " + jumpPeak + " tries " + jumpTries); }
        if (jumpPeak > 0 || jumpTries >= 3) return false;
        if (jumpCalibrating) return true;
        var onGround = G.number(G.field(hero, "posz")) - groundUnder(hero) < 0.15;
        if (isHeld(hero) || flying(hero) || airborne(hero) || !onGround) {
            if (now - calibNoteAt > 5) { calibNoteAt = now; Log.t("nav", "jump calibration waits: held " + isHeld(hero) + " flying " + flying(hero) + " airborne " + airborne(hero) + " onGround " + onGround); }
            return false;
        }
        jumpCalibrating = true;
        jumpTries++;
        trackJump(hero, now);
        jump(hero);
        Log.t("nav", "jump calibration started");
        return true;
    }

    /** Seconds the standing jump takes to climb `h` metres (measured; before the measurement a fit of it). */
    static function timeToReach(h:Float):Float {
        for (i in 0...climbT.length) if (climbZ[i] >= h) return climbT[i];
        return climbT.length > 0 ? climbT[climbT.length - 1] : 0.07 * h;
    }

    /** The hero's running speed (m/s). */
    function runSpeed(hero:Dynamic):Float {
        try return Math.max(4.0, G.number(G.call("ent.Unit", "getMoveSpeed", hero, [null]), SPEED)) catch (_:Dynamic) return SPEED;
    }

    /**
     * The takeoff of a jump onto the next waypoint: the hero must be above the ledge when it reaches the ledge's face, so the jump
     * starts as many metres before the face as it runs while climbing the rise (and a margin) - from the measured climb.
     */
    function jumpDue(hero:Dynamic, hx:Float, hy:Float, hz:Float, next:Waypoint):Bool {
        var d = Math.sqrt((next.x - hx) * (next.x - hx) + (next.y - hy) * (next.y - hy));
        var gz = groundUnder(hero);
        var top = NavGrid.fineZ(next.x, next.y, gz);
        var rise = Math.isFinite(top) ? top - gz : 1.0;
        if (rise < 0.45) return false; // the cells' heights differ, the ground at the waypoint is no higher: walk on, no jump
        var run = Math.max(0.3, Math.min(3.5, runSpeed(hero) * timeToReach(rise + 0.4)));
        return d <= run + 0.5; // the waypoint's centre is half a cell behind the face
    }

    function noteJump(hero:Dynamic, hx:Float, hy:Float, next:Waypoint):Void {
        var rise = NavGrid.fineZ(next.x, next.y, G.number(G.field(hero, "posz"))) - G.number(G.field(hero, "posz"));
        Log.t("nav", "JUMP onto the waypoint " + Math.round(next.x) + "," + Math.round(next.y) + " (rise " + Math.round(rise * 100) / 100 + " m, " + Math.round(Math.sqrt((next.x - hx) * (next.x - hx) + (next.y - hy) * (next.y - hy)) * 10) / 10 + " m away, jump height " + NavGrid.JUMP_UP + ")");
        trackJump(hero, haxe.Timer.stamp());
        jumpWantRise = Math.isFinite(rise) ? rise : Math.NaN;
        jumpWantX = next.x;
        jumpWantY = next.y;
    }

    /** What stands in the way (for the log): the distance of the first body at three heights straight ahead. */
    function solidsAhead(hx:Float, hy:Float, hz:Float, wx:Float, wy:Float):String {
        var dx = wx - hx, dy = wy - hy;
        var len = Math.sqrt(dx * dx + dy * dy);
        if (len < 0.1) return "";
        var parts = [];
        for (h in [0.3, 0.6, 1.0, 1.6]) parts.push("h" + h + "=" + Math.round(Solid.ray(hx, hy, hz + h, hx + dx / len * 3, hy + dy / len * 3, hz + h) * 10) / 10);
        return "rays to the body ahead: " + parts.join(" ");
    }

    /** A rise ahead that a jump clears (not a wall): the ground 0.8..1.5 m ahead on the heading is higher than the hero's by a step to the jump height. */
    function ledgeAhead(hero:Dynamic, hx:Float, hy:Float, ux:Float, uy:Float):Bool {
        var gz = groundUnder(hero);
        var top = Math.NEGATIVE_INFINITY;
        for (a in [0.6, 0.9, 1.2, 1.5]) {
            var z = NavGrid.fineZ(hx + ux * a, hy + uy * a, gz);
            if (Math.isFinite(z) && z > top) top = z;
        }
        if (!Math.isFinite(top)) return false;
        var rise = top - gz;
        return rise > 0.3 && rise <= NavGrid.JUMP_UP;
    }

    // ---- obelisks ----

    /** The obelisks of this world the hero has opened (the game's own list: loaded or not), with their places. */
    public static function obelisks(hero:Dynamic):Array<ObeliskInfo> {
        var out = [];
        var progress = G.field(G.field(hero, "player"), "progress");
        var map = "";
        try map = G.s(G.field(G.call("ent.Hero", "getWorldLocation", hero), "mapId")) catch (_:Dynamic) {}
        var found = false;
        try {
            for (def in G.fastArray(G.current("HElement", "obelisks"))) {
                if (def == null) continue;
                var id = G.s(G.field(G.field(def, "inf"), "id"));
                if (id == "" || id == "LEVEL_Obelisk") continue;
                var mapId = G.s(G.field(def, "mapId"));
                if (map != "" && mapId != map) continue;
                try if (G.call("st.player.Progress", "hasElementCompleted", progress, [id]) != true) continue catch (_:Dynamic) continue;
                var prefab = G.field(def, "prefab"); // the obelisks' prefabs hang straight in the world: their own x, y are the place
                out.push({id: id, x: G.number(G.field(prefab, "x")), y: G.number(G.field(prefab, "y")), z: G.number(G.field(prefab, "z"), Math.NaN), entity: null});
                found = true;
            }
        } catch (_:Dynamic) {}
        if (found) return out;
        var layer = G.field(hero, "layer");
        for (e in G.fastArray(G.field(layer, "interactibles"))) {
            if (e == null || G.field(e, "removed") == true || !G.isA(e, "ent.interactible.Obelisk")) continue;
            var id = G.s(G.field(G.field(e, "inf"), "id"));
            if (id == "") continue;
            try if (G.call("st.player.Progress", "hasElementCompleted", progress, [id]) != true) continue catch (_:Dynamic) continue;
            out.push({id: id, x: G.number(G.field(e, "posx")), y: G.number(G.field(e, "posy")), z: G.number(G.field(e, "posz")), entity: e});
        }
        return out;
    }

    /**
     * For a far spot: walks to the nearest opened obelisk and flies to the one nearest the spot, when that saves a lot of walking
     * (from any opened obelisk the hero stands at, the flight starts at once). Returns true while a trip is under way (the caller
     * waits), false when the spot is to be walked to.
     */
    public function travel(hero:Dynamic, x:Float, y:Float, now:Float, force:Bool = false):Bool {
        if (flying(hero)) { flightWait = now + 1.5; return true; }
        if (now < flightWait) return true; // just landed: wait for the world to settle
        if (noFly) return false;
        // the walk to an obelisk that no way leads to (a plateau, a gorge) was given up: that obelisk is left alone for 10 minutes
        if (gaveUp && walkId != "") {
            obeliskBad.set(walkId, now + 600);
            Log.t("nav", "no way on foot to the obelisk " + walkId + ": left alone for 10 min");
            walkId = "";
            gaveUp = false;
        }
        walkId = "";
        var direct = distance(hero, x, y);
        if (direct < OBELISK_FROM && !force) return false;
        var list = liveObelisks(hero, now);
        if (list.length < 2) { travelNote(now, "obelisk not used: only " + list.length + " opened here, walking " + Math.round(direct) + " m"); return false; }
        var hz = G.number(G.field(hero, "posz"));
        var near = null, far = list[0];
        var nd = Math.POSITIVE_INFINITY, fd = Math.POSITIVE_INFINITY, nCost = Math.POSITIVE_INFINITY;
        for (o in list) {
            var a = distance(hero, o.x, o.y), b = Math.sqrt((o.x - x) * (o.x - x) + (o.y - y) * (o.y - y));
            var bad = obeliskBad.get(o.id);
            // an obelisk on another height costs more: its way round is long (or there is none)
            var cost = a + (Math.isFinite(o.z) ? Math.abs(o.z - hz) * 3 : 0);
            if ((bad == null || now > bad) && cost < nCost) { nCost = cost; nd = a; near = o; }
            if (b < fd) { fd = b; far = o; }
        }
        if (near == null) { stranded = true; travelNote(now, "every opened obelisk is out of reach on foot: stranded"); return false; }
        if (near.id == far.id || (!force && direct - (nd + fd) < OBELISK_GAIN)) { travelNote(now, "obelisk not used: no gain (spot " + Math.round(direct) + " m, obelisk near me " + Math.round(nd) + " m, near the spot " + Math.round(fd) + " m), walking"); return false; }
        var last = obeliskTried.get(far.id);
        if (last != null && now - last < 60) { travelNote(now, "obelisk " + far.id + " refused " + Math.round(now - last) + " s ago, walking"); return false; }
        var standing = null;
        try standing = G.call("ent.Hero", "getStandingObelisk", hero) catch (_:Dynamic) {}
        var standId = standing == null ? "" : G.s(G.field(G.field(standing, "inf"), "id"));
        if (standId != "" && standId != far.id || nd < 2.0) {
            try {
                if (G.call("ent.Hero", "canFlyToObelisk", hero, [far.id]) == true) {
                    Log.t("nav", "flying by obelisk to " + far.id + " (spot " + Math.round(direct) + " m away, obelisk " + Math.round(fd) + " m from it)");
                    G.call("ent.Hero", "flyToObelisk", hero, [far.id]);
                    flights.push(now);
                    lastLandingId = far.id;
                    lastLandingAt = now;
                    flightWait = now + 1.5;
                    stop();
                    return true;
                }
            } catch (_:Dynamic) {}
            Log.t("nav", "the game refused the flight to " + far.id + " (canFlyToObelisk false): walking");
            obeliskTried.set(far.id, now);
            return false;
        }
        travelNote(now, "walking to the obelisk " + near.id + " (" + Math.round(nd) + " m, z " + Math.round(near.z) + ") to fly to " + far.id);
        walkId = near.id;
        go(near.x, near.y, 1.5, now);
        return true;
    }

    var elsewhereTried:Map<String, Float> = new Map();

    /**
     * The hero stands at an obelisk whose surroundings lead to none of the wanted spots (a plateau, an island): flies to another opened
     * obelisk, the one with most of the spots around it (an obelisk is not tried twice in 10 minutes). True when a flight was started.
     */
    public function flyElsewhere(hero:Dynamic, now:Float, spots:Array<{x:Float, y:Float}>):Bool {
        var standing = null;
        try standing = G.call("ent.Hero", "getStandingObelisk", hero) catch (_:Dynamic) {}
        var standId = standing == null ? "" : G.s(G.field(G.field(standing, "inf"), "id"));
        if (standId == "") return false; // (a flight starts only from an obelisk)
        elsewhereTried.set(standId, now + 600);
        var best = null;
        var bestCount = -1;
        var bestD = Math.POSITIVE_INFINITY;
        for (o in liveObelisks(hero, now)) {
            if (o.id == standId) continue;
            var until = elsewhereTried.get(o.id);
            if (until != null && now < until) continue;
            var count = 0;
            var nearest = Math.POSITIVE_INFINITY;
            for (p in spots) {
                var d = Math.sqrt((p.x - o.x) * (p.x - o.x) + (p.y - o.y) * (p.y - o.y));
                if (d < 200) count++;
                nearest = Math.min(nearest, d);
            }
            if (count > bestCount || (count == bestCount && nearest < bestD)) { best = o; bestCount = count; bestD = nearest; }
        }
        if (best == null) return false;
        try {
            if (G.call("ent.Hero", "canFlyToObelisk", hero, [best.id]) == true) {
                Log.t("nav", "this obelisk's surroundings lead to no wanted spot: flying to " + best.id + " (" + bestCount + " spots within 200 m of it)");
                elsewhereTried.set(best.id, now + 600);
                G.call("ent.Hero", "flyToObelisk", hero, [best.id]);
                flights.push(now);
                lastLandingId = best.id;
                lastLandingAt = now;
                flightWait = now + 1.5;
                stop();
                return true;
            }
        } catch (_:Dynamic) {}
        return false;
    }

    var travelNoteAt = -100.0;

    function travelNote(now:Float, text:String):Void {
        if (now - travelNoteAt < 8) return;
        travelNoteAt = now;
        Log.t("nav", text);
    }
}

private class FloodMap {
    public var grid = new NavGrid();
    public var ready = false;
    public var at = -1000.0;
    public var waitSince = -1.0;
    public var descents:Bool;

    public function new(descents:Bool) this.descents = descents;
}
