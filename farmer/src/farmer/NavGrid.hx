package farmer;

import farmer.GameAccess as G;

/** `fly`: the way to this waypoint is a throw from a bumper (see Pads): the hero stands on the pad before it and is thrown here. */
typedef Waypoint = {x:Float, y:Float, jump:Bool, fly:Bool};

private class Node {
    public var ix:Int;
    public var iy:Int;
    public var z:Float;
    public var g:Float;
    public var f:Float;
    public var parent:Node;
    public var jump = false;
    public var fly = false;
    public var closed = false;

    public function new(ix:Int, iy:Int, z:Float) {
        this.ix = ix;
        this.iy = iy;
        this.z = z;
    }
}

/**
 * A path over the ground around the hero: A* on a grid of 1 m cells, each cell's height read from the game's physics
 * (the same surface heights the dodge uses, AutoDodge.worldZ). A step is open when the ground rises less than a jump (1.1 m);
 * a drop costs more the deeper it is, and from a cliff of more than 7 m the glider is opened in the air (see Nav.glide);
 * walls, fences and rocks close the way, and so does any cell under water or a harmful liquid (see Hazard). The search is cut into slices (see `step`), so it never costs a frame much.
 * With the spot out of the search window, the path leads to the reachable cell nearest it.
 */
class NavGrid {
    static inline var CELL = 1.0;
    static inline var RADIUS = 120;
    static inline var MAX_NODES = 45000;
    /** The highest rise a jump clears (set from the jump the hero was measured to make, see Nav.measureJump). */
    public static var JUMP_UP = 1.1;
    static inline var STEP_UP = 0.5;
    /** A drop deeper than this is a cliff (the user's rule: 1.7 m). */
    public static inline var CLIFF = 1.7;
    /**
     * A drop up to this is a step down, not a cliff: whatever ledge the hero can jump up it can step down again (a climb that
     * could not be undone leaves the hero in a pocket), so the drop is never below the jump height.
     */
    public static function safeDrop():Float return Math.max(CLIFF, JUMP_UP + 0.8);
    /** A drop deeper than this is glided down. */
    public static inline var GLIDE_DROP = 7.0;
    /** Around a start standing in water the cells of water stay open this far (to swim out). */
    static inline var ESCAPE = 14;
    /** Water this close to a cell's centre closes the cell (the cell's half width 0.5 and the hero's body). */
    static inline var WATER_MARGIN = 0.8;
    /** Around the start the margin does not apply (the hero already stands there). */
    static inline var START_BANK = 2;
    static inline var SLICE = 0.004;
    static inline var CACHE_MAX = 250000;
    static inline var CACHE_TIME = 90.0;
    /** Without a glider a fall of more than this is no way down. */
    static inline var NO_GLIDER_DROP = 6.0;
    /** A spot where a partial path ended without progress: the search keeps away from it. */
    static inline var DEAD_RADIUS = 10.0;
    /** Near the start and the goal the clearance rules do not apply (a node can stand at a wall). */
    static inline var ENDS = 3;
    /** A node of the search on the goal's cell is the goal only within this height of goalZ. */
    static inline var GOAL_DZ = 7.0;

    /**
     * A flood search: no goal, the whole reachable ground of the window is explored (soft rules, bumpers included) and kept in `reach`
     * (cell -> height), so the bot can tell at once whether a monster or node can be walked to at all.
     */
    public var flood = false;
    public var reach:Map<Int, Float> = new Map();
    public var reachCount = 0;
    /** True when the flood never reached the border of its window: the reachable ground is a closed region (an island, a ledge, a pocket). */
    public var reachClosed = false;
    var reachX = 0;
    var reachY = 0;

    /** 1 the spot (within `slack` cells, within 6 m of height z when z is known) was reached by the flood, 0 it was not, -1 not known (out of the window). */
    public function reached(x:Float, y:Float, z:Float, slack:Int):Int {
        if (reachCount == 0) return -1;
        if (Math.abs(cell(x) - reachX) > RADIUS - 6 || Math.abs(cell(y) - reachY) > RADIUS - 6) return reachClosed ? 0 : -1; // (beyond a closed region nothing is reachable)
        for (ox in -slack...slack + 1) for (oy in -slack...slack + 1) {
            var zz = reach.get(key(cell(x) + ox, cell(y) + oy));
            if (zz != null && (!Math.isFinite(z) || Math.abs(zz - z) < 6)) return 1;
        }
        return 0;
    }

    public function floodCentre(hx:Float, hy:Float):Float {
        var dx = hx - reachX * CELL, dy = hy - reachY * CELL;
        return Math.sqrt(dx * dx + dy * dy);
    }

    /** 0 nothing, 1 searching, 2 path ready, 3 no way found. */
    public var state = 0;
    public var path:Array<Waypoint> = [];
    /** How far from the spot the path ends (0: it reaches it). */
    public var shortBy = 0.0;

    static var heights:Map<Int, Float> = new Map();
    static var wet:Map<Int, Bool> = new Map();
    /** Cells with water right on the ground (without the margin of `wet`). */
    static var drowned:Map<Int, Bool> = new Map();
    /** Cells with a body of the physics world standing in them (a bench, a post, a flower bed: see Solid). */
    static var solids:Map<Int, Bool> = new Map();
    static var heightsSince = 0.0;
    static var blocked:Map<Int, Float> = new Map();
    /** False when the hero has no glider equipped: high drops are closed. */
    public static var hasGlider = true;
    /** True once a glide was seen to hold in this session (Nav.glideWorks): only then are the drops above UNTRUSTED_DROP planned. */
    public static var glideTrusted = false;
    static inline var UNTRUSTED_DROP = 25.0;
    /** The glider opens by toggleGlide (the game's own jump key, held in every live test) but has not been seen yet in this session: drops up to this are planned (obelisk platforms stand higher than UNTRUSTED_DROP). */
    static inline var ASSUMED_DROP = 70.0;
    public static var glideAssumed = false;
    public static var deadEnds:Array<{x:Float, y:Float}> = [];
    /** The bumpers of the loaded world as launches: a throw from the pad's cell lands on ground up to `rise` m higher within `reach` m. */
    public static var pads:Array<{ix:Int, iy:Int, z:Float, rise:Float, reach:Float}> = [];
    /** Landing cells of throws that failed (the hero did not get there): closed for a while. */
    static var badLandings:Map<Int, Float> = new Map();
    /** A throw costs this much more than the walk of the same length (it is a gamble: dearer than a short way round, cheaper than a long one). */
    static inline var LAUNCH_COST = 14.0;
    static inline var LAUNCH_STEP = 3;
    static inline var LAUNCH_MIN_RISE = 2.5;

    public static function setPads(list:Array<Pads.Pad>):Void {
        pads = [for (p in list) {ix: cell(p.x), iy: cell(p.y), z: p.z, rise: Pads.expectedRise(p), reach: Pads.expectedReach(p)}];
    }

    /** A throw that did not reach its landing: the cell stays closed for 3 minutes. */
    public static function badLanding(x:Float, y:Float, now:Float):Void {
        for (ox in -1...2) for (oy in -1...2) badLandings.set(key(cell(x) + ox, cell(y) + oy), now + 180);
    }

    var nodes:Map<Int, Node> = new Map();
    var heap:Array<Node> = [];
    var sx = 0;
    var sy = 0;
    var tx = 0;
    var ty = 0;
    var goalX = 0.0;
    var goalY = 0.0;
    var escape = false;
    /** True when the search ran out of ground (not of nodes or window) without reaching a spot inside the window: no way there. */
    public var unreachable = false;
    /** The height of the spot (NaN when not known): the search does not go down below it. */
    public var goalZ = Math.NaN;
    /** True in a fight: no cliff is jumped or glided down at all (a drop deeper than CLIFF closes the way). */
    public var noCliff = false;
    var exhausted = false;
    /** True when the search reached the border of its window: the ground goes on, so "ran out of ground" proves nothing about spots outside. */
    var touchedWindow = false;
    var strict = true;
    var softTried = false;
    var startX = 0.0;
    var startY = 0.0;
    var startZ = 0.0;
    var startLiquid = false;
    var roughMemo:Map<Int, Bool> = new Map();
    var best:Node;
    /** The node on the border of the window nearest the spot: with the spot beyond the window the path leads there (a cliff's edge nearer the spot is a dead end), not to the nearest interior node. */
    var edgeBest:Node;
    var edgeH = Math.POSITIVE_INFINITY;
    var startH = 0.0;
    var bestH = Math.POSITIVE_INFINITY;
    var count = 0;

    public function new() {}

    static inline function cell(v:Float):Int return Math.round(v / CELL);

    static function key(ix:Int, iy:Int):Int return ((ix + 4096) & 8191) << 13 | ((iy + 4096) & 8191);

    static function heightKey(ix:Int, iy:Int, z:Float):Int return key(ix, iy) * 31 + (Math.round(z / 3) & 63);

    /** A cell the hero ran into: closed for a while. */
    public static function block(x:Float, y:Float, now:Float):Void {
        blocked.set(key(cell(x), cell(y)), now + 25);
    }

    /** The cell of (x, y) and the cells within `radius` of it, except those next to the hero (hx, hy): closed for a while. */
    public static function blockAround(x:Float, y:Float, radius:Int, hx:Float, hy:Float, now:Float):Void {
        for (ox in -radius...radius + 1) for (oy in -radius...radius + 1) {
            var cx = cell(x) + ox, cy = cell(y) + oy;
            if (Math.abs(cx * CELL - hx) < 1.2 && Math.abs(cy * CELL - hy) < 1.2) continue;
            blocked.set(key(cx, cy), now + 25);
        }
    }

    public static function clearBlocked():Void blocked = new Map();

    /** A cell with something solid the heights do show (a wall met on the run): closed for long. */
    public static function blockLong(x:Float, y:Float, now:Float):Void {
        blocked.set(key(cell(x), cell(y)), now + 150);
    }

    public static function addDeadEnd(x:Float, y:Float):Void {
        for (d in deadEnds) if (Math.abs(d.x - x) + Math.abs(d.y - y) < 4) return;
        deadEnds.push({x: x, y: y});
        if (deadEnds.length > 8) deadEnds.shift();
    }

    /** The ground height at a spot (not a cell's centre), NaN when none: the fine look along a run (see Nav). */
    public static function fineZ(x:Float, y:Float, ref:Float):Float {
        var z = AutoDodge.worldZ(x, y, ref, 2.2);
        if (!Math.isFinite(z) || z <= ref - 100) {
            z = AutoDodge.worldZ(x, y, ref - 30, 30);
            if (!Math.isFinite(z) || z <= ref - 100) return Math.NaN;
        }
        return z;
    }

    static function isBlocked(ix:Int, iy:Int, now:Float):Bool {
        var until = blocked.get(key(ix, iy));
        if (until == null) return false;
        if (now > until) { blocked.remove(key(ix, iy)); return false; }
        return true;
    }

    /** Ground height of a cell seen from `refZ` (NaN: no ground). */
    static function height(ix:Int, iy:Int, refZ:Float, now:Float):Float {
        if (now - heightsSince > CACHE_TIME || cached > CACHE_MAX) { heights = new Map(); wet = new Map(); drowned = new Map(); solids = new Map(); heightsSince = now; cached = 0; }
        var k = heightKey(ix, iy, refZ);
        var known = heights.get(k);
        if (known != null) return known;
        var z = AutoDodge.worldZ(ix * CELL, iy * CELL, refZ, 2.2);
        if (!Math.isFinite(z) || z <= refZ - 100) { // no ground within a step: look deeper for a drop
            z = AutoDodge.worldZ(ix * CELL, iy * CELL, refZ - 30, 30);
            if (!Math.isFinite(z) || z <= refZ - 100) z = Math.NaN;
        }
        // Water is death: such a cell is no ground at all (kept apart from the heights, to let a swimmer out of it).
        if (Math.isFinite(z) && Hazard.deadly(ix * CELL, iy * CELL, z, WATER_MARGIN)) {
            wet.set(k, true);
            if (Hazard.deadly(ix * CELL, iy * CELL, z)) drowned.set(k, true);
        }
        heights.set(k, z);
        cached++;
        return z;
    }

    static var cached = 0;

    static function padCell(ix:Int, iy:Int):Bool {
        for (p in pads) if (p.ix == ix && p.iy == iy) return true;
        return false;
    }

    static function solid(ix:Int, iy:Int, z:Float, k:Int):Bool {
        var known = solids.get(k);
        if (known != null) return known;
        var v = Solid.blocksCell(ix * CELL, iy * CELL, z);
        solids.set(k, v);
        return v;
    }

    /** The height of a cell for the path, NaN when it is no place to stand (no ground, water, a harmful liquid). */
    function open(ix:Int, iy:Int, refZ:Float, now:Float):Float {
        var z = height(ix, iy, refZ, now);
        if (!Math.isFinite(z)) return z;
        // a trap closes its area (the hero's own surroundings at the start stay open: it may stand in one and must get out)
        if (Hazard.trapCount() > 0 && Hazard.trapAt(ix * CELL, iy * CELL, z) && !(Math.abs(ix - sx) <= START_BANK && Math.abs(iy - sy) <= START_BANK)) return Math.NaN;
        var k = heightKey(ix, iy, refZ);
        // a prop with a body closes its cell (the hero's own surroundings at the start stay open, it may stand next to one)
        if (strict && !(ix == sx && iy == sy) && !padCell(ix, iy) && solid(ix, iy, z, k)) return Math.NaN; // (the soft search passes them at a price, see `step`)
        if (wet.exists(k)) {
            var near = Math.abs(ix - sx) <= ESCAPE && Math.abs(iy - sy) <= ESCAPE;
            if (!(escape && near)) {
                // right at the start only the water on the ground itself closes a cell (a dock or a shore path has water within the margin)
                var bank = Math.abs(ix - sx) <= START_BANK && Math.abs(iy - sy) <= START_BANK;
                if (!bank || drowned.exists(k)) return Math.NaN;
            }
        }
        return z;
    }

    /** Developer: what the planner sees in the column at (x, y), looking from heights `from`..`to` every 3 m. */
    public static function column(x:Float, y:Float, from:Float, to:Float):Array<String> {
        var now = haxe.Timer.stamp();
        var out = [];
        var ref = from;
        while (ref <= to) {
            var z = height(cell(x), cell(y), ref, now);
            out.push("ref " + Math.round(ref) + " -> " + (Math.isFinite(z) ? Std.string(Math.round(z * 10) / 10) : "none") + (Math.isFinite(z) && Math.abs(z - ref) <= 2.6 ? " HIT" : ""));
            ref += 3;
        }
        return out;
    }

    /** Developer: a text map around (cx, cy) of how the planner sees the ground (seen from refZ). */
    public static function debugMap(cx:Float, cy:Float, r:Int, refZ:Float, route:Array<Waypoint>, heroX:Float, heroY:Float, goalX:Float, goalY:Float):Array<String> {
        var now = haxe.Timer.stamp();
        var rows = [];
        var onRoute:Map<Int, Bool> = new Map();
        if (route != null) for (w in route) onRoute.set(key(cell(w.x), cell(w.y)), true);
        var oy = cell(cy), ox = cell(cx);
        var iy = oy + r;
        while (iy >= oy - r) {
            var line = "";
            for (ix in ox - r...ox + r + 1) {
                var ch = " ";
                var z = height(ix, iy, refZ, now);
                if (Math.isFinite(z)) {
                    var d = z - refZ;
                    ch = wet.exists(heightKey(ix, iy, refZ)) ? "~" : d > JUMP_UP ? "#" : d > STEP_UP ? "^" : d < -GLIDE_DROP ? "V" : d < -safeDrop() ? "v" : ".";
                }
                if (isBlocked(ix, iy, now)) ch = "X";
                if (onRoute.exists(key(ix, iy))) ch = "*";
                if (ix == cell(heroX) && iy == cell(heroY)) ch = "@";
                if (ix == cell(goalX) && iy == cell(goalY)) ch = "T";
                line += ch;
            }
            rows.push(line);
            iy--;
        }
        return rows;
    }

    // ---- the search ----

    public function start(hx:Float, hy:Float, hz:Float, goalX:Float, goalY:Float, inLiquid:Bool):Void {
        startX = hx;
        startY = hy;
        startZ = hz;
        startLiquid = inLiquid;
        softTried = false;
        begin(true, goalX, goalY);
    }

    /** Starts a flood search from the hero's place (see `flood`). */
    public function startFlood(hx:Float, hy:Float, hz:Float, inLiquid:Bool):Void {
        flood = true;
        startX = hx;
        startY = hy;
        startZ = hz;
        startLiquid = inLiquid;
        softTried = true; // (no second pass: the one search is the soft one)
        begin(false, hx + 100000, hy);
    }

    /** One search; `strict` keeps a cell's width away from walls and water (a second, soft one follows when that finds no way). */
    function begin(strict:Bool, goalX:Float, goalY:Float):Void {
        var hx = startX, hy = startY, hz = startZ;
        this.strict = strict;
        exhausted = false;
        touchedWindow = false;
        unreachable = false;
        roughMemo = new Map();
        escape = startLiquid || Hazard.deadly(hx, hy, hz);
        nodes = new Map();
        heap = [];
        count = 0;
        best = null;
        edgeBest = null;
        edgeH = Math.POSITIVE_INFINITY;
        bestH = Math.POSITIVE_INFINITY;
        path = [];
        shortBy = 0;
        state = 1;
        this.goalX = goalX;
        this.goalY = goalY;
        sx = cell(hx);
        sy = cell(hy);
        tx = cell(goalX);
        ty = cell(goalY);
        var first = new Node(sx, sy, hz);
        first.g = 0;
        first.f = h(sx, sy);
        startH = raw(sx, sy);
        nodes.set(nodeKey(sx, sy), first);
        push(first);
        best = first;
        bestH = first.f;
    }

    inline function nodeKey(ix:Int, iy:Int):Int return (ix - sx + 128) * 512 + (iy - sy + 128);

    /** The plain distance to the spot (octile, in cells). */
    function raw(ix:Int, iy:Int):Float {
        var dx = Math.abs(ix - tx), dy = Math.abs(iy - ty);
        return (dx + dy) + (1.4142 - 2) * Math.min(dx, dy);
    }

    function h(ix:Int, iy:Int):Float {
        if (flood) return 0;
        var v = raw(ix, iy);
        for (d in deadEnds) if (Math.abs(ix * CELL - d.x) < DEAD_RADIUS && Math.abs(iy * CELL - d.y) < DEAD_RADIUS) { v += 80; break; }
        return v;
    }

    inline function nearEnds(ix:Int, iy:Int):Bool
        return (Math.abs(ix - sx) <= ENDS && Math.abs(iy - sy) <= ENDS) || (Math.abs(ix - tx) <= ENDS && Math.abs(iy - ty) <= ENDS);

    /** A wall, a drop with no ground, or water right next to the cell (4 sides): the hero's body would scrape it. */
    function rough(ix:Int, iy:Int, z:Float, now:Float):Bool {
        var k = heightKey(ix, iy, z);
        var known = roughMemo.get(k);
        if (known != null) return known;
        var r = false;
        for (d in 0...4) {
            var nx = ix + DX[d], ny = iy + DY[d];
            var nz = height(nx, ny, z, now);
            if (!Math.isFinite(nz) || nz - z > JUMP_UP || (noCliff && z - nz > safeDrop()) || wet.exists(heightKey(nx, ny, z)) || isBlocked(nx, ny, now) || solid(nx, ny, nz, heightKey(nx, ny, z))) { r = true; break; }
        }
        roughMemo.set(k, r);
        return r;
    }

    function push(n:Node):Void {
        heap.push(n);
        var i = heap.length - 1;
        while (i > 0) {
            var p = (i - 1) >> 1;
            if (heap[p].f <= heap[i].f) break;
            var t = heap[p]; heap[p] = heap[i]; heap[i] = t;
            i = p;
        }
    }

    function pop():Node {
        var top = heap[0];
        var last = heap.pop();
        if (heap.length > 0) {
            heap[0] = last;
            var i = 0;
            while (true) {
                var l = i * 2 + 1, r = l + 1, m = i;
                if (l < heap.length && heap[l].f < heap[m].f) m = l;
                if (r < heap.length && heap[r].f < heap[m].f) m = r;
                if (m == i) break;
                var t = heap[m]; heap[m] = heap[i]; heap[i] = t;
                i = m;
            }
        }
        return top;
    }

    /** Works on the search for a few milliseconds. */
    public function step(now:Float):Void {
        if (state != 1) return;
        var until = haxe.Timer.stamp() + SLICE;
        while (heap.length > 0) {
            if (haxe.Timer.stamp() > until) return;
            var n = pop();
            if (n.closed) continue;
            n.closed = true;
            var hh = h(n.ix, n.iy);
            if (hh < bestH) { bestH = hh; best = n; }
            // (the spot of a known height counts only at that height: a ledge above a node or a floor below one is not the spot)
            if (n.ix == tx && n.iy == ty && (!Math.isFinite(goalZ) || Math.abs(n.z - goalZ) < GOAL_DZ)) { finish(n, now); return; }
            if (++count > MAX_NODES) { finish(partialEnd(), now); return; }
            for (dir in 0...8) {
                var dx = DX[dir], dy = DY[dir];
                var nx = n.ix + dx, ny = n.iy + dy;
                if (Math.abs(nx - sx) > RADIUS || Math.abs(ny - sy) > RADIUS) {
                    touchedWindow = true;
                    var rr = raw(n.ix, n.iy);
                    if (rr < edgeH) { edgeH = rr; edgeBest = n; } // the ground goes on from this node: a way out of the window
                    continue;
                }
                if (isBlocked(nx, ny, now)) continue;
                var existing = nodes.get(nodeKey(nx, ny));
                if (existing != null && existing.closed) continue;
                var z = open(nx, ny, n.z, now);
                if (!Math.isFinite(z)) continue;
                var dz = z - n.z;
                var extra = 0.0;
                var jump = false;
                if (dz > JUMP_UP) continue;
                if (dz > STEP_UP) { jump = true; extra = 5; } // a jump costs: a way round a bench is better
                if (dz < -safeDrop()) {
                    if (noCliff) continue; // in a fight a cliff is never gone down
                    if (!hasGlider && -dz > NO_GLIDER_DROP) continue; // no glider: too high to fall
                    if (!glideTrusted && -dz > (glideAssumed ? ASSUMED_DROP : UNTRUSTED_DROP)) continue; // the glider has not been seen to hold yet: a fall this high is no gamble to take
                    // never down below the level of the spot (a gorge or a pit cannot be climbed out of): only as far as it needs
                    if (Math.isFinite(goalZ) && z < goalZ - 4) continue;
                    extra = Math.min(70, 8 + -dz * 1.5); // a drop is a one-way road: dearer than a long walk round; above GLIDE_DROP the glider is opened in the air
                }
                if (!strict && !(nx == sx && ny == sy) && solid(nx, ny, z, heightKey(nx, ny, n.z))) extra += 10;
                if (!nearEnds(nx, ny) && rough(nx, ny, z, now)) {
                    if (strict) continue;
                    extra += 3;
                }
                if (dx != 0 && dy != 0) { // no cutting a corner of a wall
                    var z1 = open(n.ix + dx, n.iy, n.z, now), z2 = open(n.ix, n.iy + dy, n.z, now);
                    if (!Math.isFinite(z1) || !Math.isFinite(z2) || z1 - n.z > JUMP_UP || z2 - n.z > JUMP_UP) continue;
                }
                var g = n.g + (dx != 0 && dy != 0 ? 1.4142 : 1.0) + extra;
                if (existing == null) {
                    existing = new Node(nx, ny, z);
                    existing.g = g;
                    existing.f = g + h(nx, ny);
                    existing.parent = n;
                    existing.jump = jump;
                    nodes.set(nodeKey(nx, ny), existing);
                    push(existing);
                } else if (g < existing.g) {
                    existing.g = g;
                    existing.f = g + h(nx, ny);
                    existing.parent = n;
                    existing.z = z;
                    existing.jump = jump;
                    existing.fly = false;
                    push(existing);
                }
            }
            if (pads.length > 0) launches(n, now);
        }
        exhausted = true;
        finish(partialEnd(), now);
    }

    /** Where a path that does not reach the spot ends: at the window's border when the spot lies beyond the window and the ground goes on there. */
    function partialEnd():Node {
        // (only when it is nearer the spot than the start was: from one border node the nearest border node of the next window may lead back, and the hero would pace between the two)
        if (!flood && edgeBest != null && edgeH < startH - 5 && (Math.abs(tx - sx) > RADIUS || Math.abs(ty - sy) > RADIUS)) return edgeBest;
        return best;
    }

    /**
     * The throws from the bumper at node `n`: every dry, roomy cell of higher ground within the flight's reach (sampled every
     * LAUNCH_STEP cells) is a node reached by a flight. Only real climbs count (a rise the legs cannot make).
     */
    function launches(n:Node, now:Float):Void {
        for (p in pads) {
            if (p.ix != n.ix || p.iy != n.iy || Math.abs(p.z - n.z) > 3) continue;
            var found = 0, tried = 0;
            var r = Std.int(p.reach);
            var ox = -r;
            while (ox <= r) {
                var oy = -r;
                while (oy <= r) {
                    var d = Math.sqrt(ox * ox + oy * oy);
                    var lx = p.ix + ox, ly = p.iy + oy;
                    oy += LAUNCH_STEP;
                    if (d < 3 || d > p.reach || Math.abs(lx - sx) > RADIUS || Math.abs(ly - sy) > RADIUS) continue;
                    var bad = badLandings.get(key(lx, ly));
                    if (bad != null && now < bad) continue;
                    var existing = nodes.get(nodeKey(lx, ly));
                    if (existing != null && existing.closed) continue;
                    // the ground there at the heights a throw can reach (the highest that is dry and roomy wins)
                    var bestZ = Math.NaN;
                    var probe = p.rise * 0.9 + n.z;
                    while (probe >= n.z + LAUNCH_MIN_RISE - 1.0) {
                        var z = open(lx, ly, probe, now);
                        if (Math.isFinite(z) && Math.abs(z - probe) <= 2.6 && z - n.z >= LAUNCH_MIN_RISE && z - n.z <= p.rise && d <= Pads.RISE_RUN + Pads.GLIDE_RATIO * (p.rise - (z - n.z))) { bestZ = z; break; }
                        probe -= 3.0;
                    }
                    tried++;
                    if (!Math.isFinite(bestZ)) continue;
                    // (a narrow ledge or one at a wall is rough: fine for a landing, the strict search skips it, the soft one takes it at a price)
                    var rg = rough(lx, ly, bestZ, now);
                    if (strict && rg) continue;
                    found++;
                    var g = n.g + LAUNCH_COST + d * 0.8 + (rg ? 4 : 0);
                    if (existing == null) {
                        existing = new Node(lx, ly, bestZ);
                        existing.g = g;
                        existing.f = g + h(lx, ly);
                        existing.parent = n;
                        existing.jump = true;
                        existing.fly = true;
                        nodes.set(nodeKey(lx, ly), existing);
                        push(existing);
                    } else if (g < existing.g) {
                        existing.g = g;
                        existing.f = g + h(lx, ly);
                        existing.parent = n;
                        existing.z = bestZ;
                        existing.jump = true;
                        existing.fly = true;
                        push(existing);
                    }
                }
                ox += LAUNCH_STEP;
            }
            Log.t("nav", "pad at " + p.ix + "," + p.iy + " z " + Math.round(p.z) + " (rise " + Math.round(p.rise) + ", reach " + Math.round(p.reach) + "): " + found + " landings of " + tried + " cells looked at");
        }
    }

    static var DX = [1, -1, 0, 0, 1, 1, -1, -1];
    static var DY = [0, 0, 1, -1, 1, -1, 1, -1];

    function finish(end:Node, now:Float):Void {
        if (flood) {
            reach = new Map();
            reachCount = 0;
            for (n in nodes) { reach.set(key(n.ix, n.iy), n.z); reachCount++; }
            reachX = sx;
            reachY = sy;
            reachClosed = exhausted && !touchedWindow;
            flood = false;
            path = [];
            state = 2;
            Log.t("nav", "reach map from " + sx + "," + sy + ": " + reachCount + " cells can be walked to" + (noCliff ? "" : " (descents allowed)") + (reachClosed ? ", a closed region" : ""));
            nodes = new Map();
            heap = [];
            return;
        }
        var ex0 = end.ix * CELL - goalX, ey0 = end.iy * CELL - goalY;
        if (strict && !softTried && Math.sqrt(ex0 * ex0 + ey0 * ey0) > 3 && ((Math.abs(goalX - startX) < RADIUS - 20 && Math.abs(goalY - startY) < RADIUS - 20) || count < 150 || (exhausted && !touchedWindow))) {
            // no clean way: the same search again, now allowed to pass close to walls
            Log.t("nav", "strict path failed (short by " + Math.round(Math.sqrt(ex0 * ex0 + ey0 * ey0)) + " m): soft search");
            softTried = true;
            begin(false, goalX, goalY);
            return;
        }
        // the reachable ground was all searched: a spot inside the window is not on it, and a spot outside is not either when the ground never reached the window's border (a closed pocket)
        unreachable = exhausted && Math.sqrt(ex0 * ex0 + ey0 * ey0) > 3 && ((Math.abs(goalX - startX) < RADIUS - 8 && Math.abs(goalY - startY) < RADIUS - 8) || !touchedWindow);
        var list:Array<Waypoint> = [];
        var n = end;
        while (n != null) {
            list.push({x: n.ix * CELL, y: n.iy * CELL, jump: n.jump, fly: n.fly});
            n = n.parent;
        }
        list.reverse();
        path = list;
        var ex = end.ix * CELL - goalX, ey = end.iy * CELL - goalY;
        shortBy = Math.sqrt(ex * ex + ey * ey);
        state = list.length >= 2 || shortBy < 1.5 ? 2 : 3;
        Log.t("nav", "path from " + sx + "," + sy + " to " + tx + "," + ty + ": " + list.length + " cells, " + count + " nodes, short by " + Math.round(shortBy) + " m, state " + state);
        nodes = new Map();
        heap = [];
    }
}
