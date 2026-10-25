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
    static inline var BODY_SIDE = 0.45;
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
    /** The obelisk the hero is walking to (to fly from there), "" when none. */
    var walkId = "";
    /** True when no opened obelisk can be walked to: the caller must use another way (the home stone). */
    public var stranded = false;
    public function forgetObeliskTrouble():Void { obeliskBad = new Map(); stranded = false; }
    public function walkingToObelisk():Bool return walkId != "";
    var grid = new NavGrid();
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

    public function new() {}

    /** True in a fight: no cliff (a drop deeper than NavGrid.CLIFF) is gone down; set by the caller before `go`. */
    public var noCliff = false;
    var plannedCliff = false;
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
        return (route != null && route.length > 0) || distance(hero, tx, ty) <= 6;
    }

    public function debugRoute():Array<Waypoint> return route;
    public function goalX():Float return tx;
    public function goalY():Float return ty;

    public function arrived(hero:Dynamic):Bool return !active || distance(hero, tx, ty) <= arrive;

    /** Every frame: the path search, stuck handling, jumping, gliding. */
    public function update(hero:Dynamic, now:Float):Void {
        glide(hero);
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
        if (route == null || isHeld(hero) || flying(hero)) { blockedSince = -1; return; }
        if (moved >= expected * STUCK_SHARE) { blockedSince = -1; return; }
        if (blockedSince < 0) blockedSince = now;
        var blocked = now - blockedSince;
        if (blocked > GIVE_UP) { stop(); gaveUp = true; return; }
        if (blocked > 0.35 && now - jumpedAt > 0.8) { jump(hero); jumpedAt = now; }
        if (blocked > 0.7 && now - plannedAt > 1.0) {
            // ran into something the heights did not show: close the cells ahead (the path's own next cells and the line of
            // the run) and plan again; stuck at the same place again, the closed area grows, so the new path must differ
            stuckLevel = Math.abs(hx - lastPlanX) + Math.abs(hy - lastPlanY) < 3 ? stuckLevel + 1 : 1;
            var radius = Std.int(Math.min(1, stuckLevel - 1));
            var ahead:Array<{x:Float, y:Float}> = [{x: hx + lastDirX * 1.2, y: hy + lastDirY * 1.2}, {x: hx + lastDirX * 2.0, y: hy + lastDirY * 2.0}];
            if (route != null) for (i in routeIndex + 1...Std.int(Math.min(routeIndex + 4, route.length))) ahead.push({x: route[i].x, y: route[i].y});
            for (a in ahead) NavGrid.blockAround(a.x, a.y, radius, hx, hy, now);
            if (stuckLevel >= 4) { // the closed cells did not help: this spot cannot be reached from here
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
        } catch (e:Dynamic) Log.t("nav", "dumpStuck failed: " + Std.string(e));
    }

    static function windowFocused():Bool {
        try return G.call("hxd.Window", "get_isFocused", G.staticCall("hxd.Window", "getInstance", [])) == true catch (_:Dynamic) return false;
    }

    function planning(hero:Dynamic, hx:Float, hy:Float, hz:Float, now:Float):Void {
        if (route != null && now - plannedAt > 14) needPlan = true;
        if (needPlan && grid.state != 1 && now >= planBlock) {
            needPlan = false;
            plannedAt = now;
            lastPlanX = hx;
            lastPlanY = hy;
            NavGrid.hasGlider = hasGlider(hero);
            grid.goalZ = goalZ;
            grid.noCliff = noCliff;
            plannedCliff = noCliff;
            Log.t("nav", "planning from " + Math.round(hx) + "," + Math.round(hy) + "," + Math.round(hz) + " to " + Math.round(tx) + "," + Math.round(ty) + " glider " + NavGrid.hasGlider + " noCliff " + noCliff + " traps " + Hazard.trapCount());
            grid.start(hx, hy, hz, tx, ty, Hazard.heroInLiquid(hero));
        }
        if (grid.state == 1) grid.step(now);
        if (grid.state == 2) {
            if (grid.unreachable && distance(hero, tx, ty) > 6) {
                Log.t("nav", "spot " + Math.round(tx) + "," + Math.round(ty) + " cannot be reached from here (the ground around runs out " + Math.round(grid.shortBy) + " m short): given up");
                grid.state = 0;
                stop();
                gaveUp = true;
                return;
            }
            route = grid.path;
            routeShort = grid.shortBy;
            routeIndex = 0;
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

    function isHeld(hero:Dynamic):Bool {
        try {
            if (G.call("ent.GameObject", "isUnderAnyCC", hero) == true) return true;
            return G.call("ent.GameObject", "getActiveSkill", hero) != null;
        } catch (_:Dynamic) return false;
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
            if (G.field(hero, "gliding") == true) return;
            var t = haxe.Timer.stamp();
            if (t - glideAskedAt < 0.5) return; // the request travels to the server and back: one at a time
            var above = G.number(G.field(hero, "posz")) - groundUnder(hero);
            if (above < GLIDE_HEIGHT) return;
            if (G.call("ent.Hero", "canStartGlide", hero) == true) {
                glideAskedAt = t;
                G.call("ent.Hero", "enterGlider", hero);
                Log.t("nav", "glider opened at " + Math.round(above) + " m above the ground");
            }
        } catch (_:Dynamic) {}
    }

    function airborne(hero:Dynamic):Bool {
        try return G.field(hero, "gliding") == true || G.number(G.field(hero, "posz")) - groundUnder(hero) > 2.5 catch (_:Dynamic) return false;
    }

    /**
     * The way the hero can run from (hx, hy) to (wx, wy) as a body: the ground rises no more than a step half a metre on, on the
     * middle line and on both sides, and no water lies on it. Thin things (posts, bushes) that the cells' centres miss show here.
     */
    public static function corridorClear(hx:Float, hy:Float, hz:Float, wx:Float, wy:Float, cliff:Bool = false):Bool {
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
            if (!Math.isFinite(z)) return false;
            if (z - prev > FINE_RISE) return false;
            if (cliff && prev - z > NavGrid.CLIFF) return false;
            if (Hazard.wetCell(px, py, z, 0.45) || Hazard.trapAt(px, py, z)) return false;
            for (side in [1.0, -1.0]) {
                var qx = px + sx * side, qy = py + sy * side;
                var q = NavGrid.fineZ(qx, qy, z);
                if (!Math.isFinite(q)) return false;
                if (q - z > FINE_RISE) return false;
                if (Hazard.wetCell(qx, qy, q, 0.3)) return false;
            }
            prev = z;
        }
        return true;
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
            while (routeIndex < route.length - 1 && Math.abs(route[routeIndex].x - hx) + Math.abs(route[routeIndex].y - hy) < 1.1) routeIndex++;
            var last = route.length - 1;
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
            if (aimFrom != routeIndex || now - aimAt > 0.12) {
                // aim at the farthest of the next waypoints that the body can really run to (corners are not cut across walls or
                // water); never past a jump
                aimAt = now;
                aimFrom = routeIndex;
                var far = Std.int(Math.min(routeIndex + 4, last));
                for (j in pick...far + 1) if (route[j].jump) { far = j; break; }
                var chosen = pick;
                var k = far;
                while (k > pick) {
                    // a waypoint right at the hero (the path curls back on itself) is no aim: the heading would be noise
                    if (Math.abs(route[k].x - hx) + Math.abs(route[k].y - hy) > 1.6 && corridorClear(hx, hy, hz, route[k].x, route[k].y, noCliff)) { chosen = k; break; }
                    k--;
                }
                aimIdx = chosen;
                if (chosen == pick && !route[pick].jump && distance(hero, route[pick].x, route[pick].y) > 1.0 && !airborne(hero)) {
                    if (!corridorClear(hx, hy, hz, route[pick].x, route[pick].y, noCliff)) {
                        if (++badAhead >= 3 && now - plannedAt > 0.8) {
                            // the next cell is not passable for a body (a post, a bush the cells' centres missed): closed, a new path
                            NavGrid.blockLong(route[pick].x, route[pick].y, now);
                            Log.t("nav", "blocked ahead at " + Math.round(route[pick].x) + "," + Math.round(route[pick].y) + ": replanning");
                            needPlan = true;
                            badAhead = 0;
                        }
                    } else badAhead = 0;
                } else badAhead = 0;
            }
            var wp = route[Std.int(Math.min(aimIdx, last))];
            aimX = wp.x;
            aimY = wp.y;
            var next = route[pick];
            if (next.jump && jumpedFor != routeIndex && Math.abs(next.x - hx) + Math.abs(next.y - hy) < 2.2) { jumpedFor = routeIndex; jump(hero); }
        } else if (distance(hero, tx, ty) > 6) { why = "planning"; return null; }
        var dx = aimX - hx, dy = aimY - hy;
        var d = Math.sqrt(dx * dx + dy * dy);
        if (d < 0.01) { why = "at aim"; return null; }
        dx /= d;
        dy /= d;
        if (airborne(hero)) { var h = airHeading(hx, hy, hz, dx, dy); dx = h.x; dy = h.y; }
        // jitter: the heading turning back on itself again and again
        if (dx * lastDirX + dy * lastDirY < -0.17) flips++;
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
    public function travel(hero:Dynamic, x:Float, y:Float, now:Float):Bool {
        if (flying(hero)) { flightWait = now + 1.5; return true; }
        if (now < flightWait) return true; // just landed: wait for the world to settle
        // the walk to an obelisk that no way leads to (a plateau, a gorge) was given up: that obelisk is left alone for 10 minutes
        if (gaveUp && walkId != "") {
            obeliskBad.set(walkId, now + 600);
            Log.t("nav", "no way on foot to the obelisk " + walkId + ": left alone for 10 min");
            walkId = "";
            gaveUp = false;
        }
        walkId = "";
        var direct = distance(hero, x, y);
        if (direct < OBELISK_FROM) return false;
        var list = obelisks(hero);
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
        if (near.id == far.id || direct - (nd + fd) < OBELISK_GAIN) { travelNote(now, "obelisk not used: no gain (spot " + Math.round(direct) + " m, obelisk near me " + Math.round(nd) + " m, near the spot " + Math.round(fd) + " m), walking"); return false; }
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

    var travelNoteAt = -100.0;

    function travelNote(now:Float, text:String):Void {
        if (now - travelNoteAt < 8) return;
        travelNoteAt = now;
        Log.t("nav", text);
    }
}
