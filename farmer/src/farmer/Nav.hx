package farmer;

import farmer.GameAccess as G;
import farmer.NavGrid.Waypoint;

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
    static inline var OBELISK_GAIN = 110.0; // an obelisk trip must save at least this many metres
    /** The glider opens when the ground is this far below in a fall: every cliff above NavGrid.GLIDE_DROP is flown down. */
    static inline var GLIDE_HEIGHT = 4.0;

    public var active = false;
    public var tx = 0.0;
    public var ty = 0.0;
    public var arrive = 2.0;
    /** True once the spot was given up (stuck for too long). */
    public var gaveUp = false;
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

    public function new() {}

    public function go(x:Float, y:Float, arrive:Float, now:Float):Void {
        if (active && Math.abs(tx - x) < 0.5 && Math.abs(ty - y) < 0.5) { this.arrive = arrive; return; }
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

    public function stop():Void {
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
            Log.w("nav pos " + Math.round(hx * 10) / 10 + "," + Math.round(hy * 10) / 10 + "," + Math.round(hz * 10) / 10 + " moved " + Math.round(moved * 100) / 100 + "/" + Math.round(expected * 100) / 100
                + " route " + (route == null ? "none" : routeIndex + "/" + route.length) + " dir " + hasDirection + " why " + why + " calls " + calls + " dodge " + AutoDodge.dodging() + " held " + isHeld(hero) + " blocked " + (blockedSince < 0 ? "-" : Std.string(Math.round((now - blockedSince) * 10) / 10)));
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
                Log.w("stuck at " + Math.round(hx) + "," + Math.round(hy) + " for good: spot given up");
                NavGrid.clearBlocked();
                stop();
                gaveUp = true;
                return;
            }
            Log.w("stuck at " + Math.round(hx) + "," + Math.round(hy) + " level " + stuckLevel + ": cells ahead closed");
            needPlan = true;
            blockedSince = -1; // the new path gets its own time to prove itself
        }
    }

    function planning(hero:Dynamic, hx:Float, hy:Float, hz:Float, now:Float):Void {
        if (route != null && now - plannedAt > 14) needPlan = true;
        if (needPlan && grid.state != 1 && now >= planBlock) {
            needPlan = false;
            plannedAt = now;
            lastPlanX = hx;
            lastPlanY = hy;
            grid.start(hx, hy, hz, tx, ty, Hazard.heroInLiquid(hero));
        }
        if (grid.state == 1) grid.step(now);
        if (grid.state == 2) {
            route = grid.path;
            routeShort = grid.shortBy;
            routeIndex = 0;
            jumpedFor = -1;
            grid.state = 0;
        } else if (grid.state == 3) {
            grid.state = 0;
            route = null;
            planBlock = now + 1.5;
            if (distance(hero, tx, ty) > 6) { stop(); gaveUp = true; }
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

    /** Falling from a height: open the glider (the way down from a cliff). */
    function glide(hero:Dynamic):Void {
        try {
            if (G.field(hero, "gliding") == true) return;
            var above = G.number(G.field(hero, "posz")) - G.number(G.field(hero, "serverGroundZ"), G.number(G.field(hero, "posz")));
            if (above < GLIDE_HEIGHT) return;
            if (G.call("ent.Hero", "canStartGlide", hero) == true) G.call("ent.Hero", "enterGlider", hero);
        } catch (_:Dynamic) {}
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
        var hx = G.number(G.field(hero, "posx")), hy = G.number(G.field(hero, "posy"));
        var aimX = tx, aimY = ty;
        if (route != null && route.length > 0) {
            while (routeIndex < route.length - 1 && Math.abs(route[routeIndex].x - hx) + Math.abs(route[routeIndex].y - hy) < 1.1) routeIndex++;
            var last = route.length - 1;
            if (routeIndex >= last && routeShort > 3 && !needPlan) {
                // the path only led part of the way: plan again from here, unless the last plan started here too
                if (Math.abs(hx - lastPlanX) + Math.abs(hy - lastPlanY) < 4) { why = "short route end"; stop(); gaveUp = true; return null; }
                needPlan = true;
            }
            var wp = route[Std.int(Math.min(routeIndex + 2, last))];
            // aiming past a corner must not cut across water: the nearer waypoint then
            var hz = G.number(G.field(hero, "posz"));
            if (wp != route[Std.int(Math.min(routeIndex + 1, last))] && Hazard.lineDeadly(hx, hy, wp.x, wp.y, hz)) wp = route[Std.int(Math.min(routeIndex + 1, last))];
            aimX = wp.x;
            aimY = wp.y;
            var next = route[Std.int(Math.min(routeIndex + 1, last))];
            if (next.jump && jumpedFor != routeIndex && Math.abs(next.x - hx) + Math.abs(next.y - hy) < 2.2) { jumpedFor = routeIndex; jump(hero); }
        } else if (distance(hero, tx, ty) > 6) { why = "planning"; return null; }
        var dx = aimX - hx, dy = aimY - hy;
        var d = Math.sqrt(dx * dx + dy * dy);
        if (d < 0.01) { why = "at aim"; return null; }
        lastDirX = dx / d;
        lastDirY = dy / d;
        hasDirection = true;
        return {x: lastDirX, y: lastDirY};
    }

    // ---- obelisks ----

    public static function obelisks(hero:Dynamic):Array<{id:String, x:Float, y:Float, entity:Dynamic}> {
        var out = [];
        var layer = G.field(hero, "layer");
        var progress = G.field(G.field(hero, "player"), "progress");
        for (e in G.fastArray(G.field(layer, "interactibles"))) {
            if (e == null || G.field(e, "removed") == true || !G.isA(e, "ent.interactible.Obelisk")) continue;
            var id = G.s(G.field(G.field(e, "inf"), "id"));
            if (id == "") continue;
            try if (G.call("st.player.Progress", "hasElementCompleted", progress, [id]) != true) continue catch (_:Dynamic) continue;
            out.push({id: id, x: G.number(G.field(e, "posx")), y: G.number(G.field(e, "posy")), entity: e});
        }
        return out;
    }

    /**
     * For a far spot: walks to the nearest obelisk and flies to the one nearest the spot, when that saves a lot of walking.
     * Returns true while a trip is under way (the caller waits), false when the spot is to be walked to.
     */
    public function travel(hero:Dynamic, x:Float, y:Float, now:Float):Bool {
        if (flying(hero)) { flightWait = now + 1.5; return true; }
        if (now < flightWait) return true; // just landed: wait for the world to settle
        var direct = distance(hero, x, y);
        if (direct < 200) return false;
        var list = obelisks(hero);
        if (list.length < 2) return false;
        var near = list[0], far = list[0];
        var nd = Math.POSITIVE_INFINITY, fd = Math.POSITIVE_INFINITY;
        for (o in list) {
            var a = distance(hero, o.x, o.y), b = Math.sqrt((o.x - x) * (o.x - x) + (o.y - y) * (o.y - y));
            if (a < nd) { nd = a; near = o; }
            if (b < fd) { fd = b; far = o; }
        }
        if (near.id == far.id || direct - (nd + fd) < OBELISK_GAIN) return false;
        var last = obeliskTried.get(far.id);
        if (last != null && now - last < 60) return false;
        var standing = null;
        try standing = G.call("ent.Hero", "getStandingObelisk", hero) catch (_:Dynamic) {}
        if (standing != null && G.s(G.field(G.field(standing, "inf"), "id")) == near.id || nd < 2.0) {
            try {
                if (G.call("ent.Hero", "canFlyToObelisk", hero, [far.id]) == true) {
                    G.call("ent.Hero", "flyToObelisk", hero, [far.id]);
                    flightWait = now + 1.5;
                    stop();
                    return true;
                }
            } catch (_:Dynamic) {}
            obeliskTried.set(far.id, now);
            return false;
        }
        go(near.x, near.y, 1.5, now);
        return true;
    }
}
