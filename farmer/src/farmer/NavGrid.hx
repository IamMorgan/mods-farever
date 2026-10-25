package farmer;

import farmer.GameAccess as G;

typedef Waypoint = {x:Float, y:Float, jump:Bool};

private class Node {
    public var ix:Int;
    public var iy:Int;
    public var z:Float;
    public var g:Float;
    public var f:Float;
    public var parent:Node;
    public var jump = false;
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
    static inline var JUMP_UP = 1.1;
    static inline var STEP_UP = 0.5;
    /** A drop deeper than this is a cliff (the user's rule: 1.7 m). */
    public static inline var CLIFF = 1.7;
    static inline var SAFE_DROP = CLIFF;
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

    /** 0 nothing, 1 searching, 2 path ready, 3 no way found. */
    public var state = 0;
    public var path:Array<Waypoint> = [];
    /** How far from the spot the path ends (0: it reaches it). */
    public var shortBy = 0.0;

    static var heights:Map<Int, Float> = new Map();
    static var wet:Map<Int, Bool> = new Map();
    /** Cells with water right on the ground (without the margin of `wet`). */
    static var drowned:Map<Int, Bool> = new Map();
    static var heightsSince = 0.0;
    static var blocked:Map<Int, Float> = new Map();
    /** False when the hero has no glider equipped: high drops are closed. */
    public static var hasGlider = true;
    public static var deadEnds:Array<{x:Float, y:Float}> = [];

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
    var strict = true;
    var softTried = false;
    var startX = 0.0;
    var startY = 0.0;
    var startZ = 0.0;
    var startLiquid = false;
    var roughMemo:Map<Int, Bool> = new Map();
    var best:Node;
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
        if (now - heightsSince > CACHE_TIME || cached > CACHE_MAX) { heights = new Map(); wet = new Map(); drowned = new Map(); heightsSince = now; cached = 0; }
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

    /** The height of a cell for the path, NaN when it is no place to stand (no ground, water, a harmful liquid). */
    function open(ix:Int, iy:Int, refZ:Float, now:Float):Float {
        var z = height(ix, iy, refZ, now);
        if (!Math.isFinite(z)) return z;
        // a trap closes its area (the hero's own surroundings at the start stay open: it may stand in one and must get out)
        if (Hazard.trapCount() > 0 && Hazard.trapAt(ix * CELL, iy * CELL, z) && !(Math.abs(ix - sx) <= START_BANK && Math.abs(iy - sy) <= START_BANK)) return Math.NaN;
        var k = heightKey(ix, iy, refZ);
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
                    ch = wet.exists(heightKey(ix, iy, refZ)) ? "~" : d > JUMP_UP ? "#" : d > STEP_UP ? "^" : d < -GLIDE_DROP ? "V" : d < -SAFE_DROP ? "v" : ".";
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

    /** One search; `strict` keeps a cell's width away from walls and water (a second, soft one follows when that finds no way). */
    function begin(strict:Bool, goalX:Float, goalY:Float):Void {
        var hx = startX, hy = startY, hz = startZ;
        this.strict = strict;
        exhausted = false;
        unreachable = false;
        roughMemo = new Map();
        escape = startLiquid || Hazard.deadly(hx, hy, hz);
        nodes = new Map();
        heap = [];
        count = 0;
        best = null;
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
        nodes.set(nodeKey(sx, sy), first);
        push(first);
        best = first;
        bestH = first.f;
    }

    inline function nodeKey(ix:Int, iy:Int):Int return (ix - sx + 128) * 512 + (iy - sy + 128);

    function h(ix:Int, iy:Int):Float {
        var dx = Math.abs(ix - tx), dy = Math.abs(iy - ty);
        var v = (dx + dy) + (1.4142 - 2) * Math.min(dx, dy);
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
            if (!Math.isFinite(nz) || nz - z > JUMP_UP || wet.exists(heightKey(nx, ny, z)) || isBlocked(nx, ny, now)) { r = true; break; }
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
            if (n.ix == tx && n.iy == ty) { finish(n, now); return; }
            if (++count > MAX_NODES) { finish(best, now); return; }
            for (dir in 0...8) {
                var dx = DX[dir], dy = DY[dir];
                var nx = n.ix + dx, ny = n.iy + dy;
                if (Math.abs(nx - sx) > RADIUS || Math.abs(ny - sy) > RADIUS) continue;
                if (isBlocked(nx, ny, now)) continue;
                var existing = nodes.get(nodeKey(nx, ny));
                if (existing != null && existing.closed) continue;
                var z = open(nx, ny, n.z, now);
                if (!Math.isFinite(z)) continue;
                var dz = z - n.z;
                var extra = 0.0;
                var jump = false;
                if (dz > JUMP_UP) continue;
                if (dz > STEP_UP) { jump = true; extra = 2; }
                if (dz < -SAFE_DROP) {
                    if (noCliff) continue; // in a fight a cliff is never gone down
                    if (!hasGlider && -dz > NO_GLIDER_DROP) continue; // no glider: too high to fall
                    // never down below the level of the spot (a gorge or a pit cannot be climbed out of): only as far as it needs
                    if (Math.isFinite(goalZ) && z < goalZ - 4) continue;
                    extra = Math.min(70, 8 + -dz * 1.5); // a drop is a one-way road: dearer than a long walk round; above GLIDE_DROP the glider is opened in the air
                }
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
                    push(existing);
                }
            }
        }
        exhausted = true;
        finish(best, now);
    }

    static var DX = [1, -1, 0, 0, 1, 1, -1, -1];
    static var DY = [0, 0, 1, -1, 1, -1, 1, -1];

    function finish(end:Node, now:Float):Void {
        var ex0 = end.ix * CELL - goalX, ey0 = end.iy * CELL - goalY;
        if (strict && !softTried && Math.sqrt(ex0 * ex0 + ey0 * ey0) > 3 && Math.abs(goalX - startX) < RADIUS - 20 && Math.abs(goalY - startY) < RADIUS - 20) {
            // no clean way: the same search again, now allowed to pass close to walls
            Log.t("nav", "strict path failed (short by " + Math.round(Math.sqrt(ex0 * ex0 + ey0 * ey0)) + " m): soft search");
            softTried = true;
            begin(false, goalX, goalY);
            return;
        }
        unreachable = exhausted && Math.sqrt(ex0 * ex0 + ey0 * ey0) > 3 && Math.abs(goalX - startX) < RADIUS - 8 && Math.abs(goalY - startY) < RADIUS - 8;
        var list:Array<Waypoint> = [];
        var n = end;
        while (n != null) {
            list.push({x: n.ix * CELL, y: n.iy * CELL, jump: n.jump});
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
