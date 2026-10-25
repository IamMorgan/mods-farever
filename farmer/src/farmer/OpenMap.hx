package farmer;

/**
 * A small grid around the hero (CELL metres a cell) of what is in the way - walls, fences,
 * posts, cliff edges, anything learnt by running into it - and, for every cell, how far it is
 * to the nearest such thing. Used to keep the hero in the open: away from walls and above all
 * out of corners, where there is no room left to dodge.
 * Pure logic: heights come from the caller, so it can be tested on its own.
 */
class OpenMap {
    public static inline var CELL = 0.5;
    static inline var FAR = 1e9;

    public var radius(default, null):Int;   // cells either side of the centre
    var size:Int;
    var cx = 0;
    var cy = 0;
    var blocked:Array<Bool>;
    var dist:Array<Float>;                  // metres to the nearest blocked cell

    public function new(radius:Int) {
        this.radius = radius;
        size = radius * 2 + 1;
        blocked = [for (_ in 0...size * size) false];
        dist = [for (_ in 0...size * size) FAR];
    }

    public static inline function cellOf(v:Float):Int return Math.round(v / CELL);

    /**
     * Rebuilds the map around cell (centreX, centreY).
     * `height(ix, iy)`: the walking surface's height there, NaN when not known (counts as open).
     * `solid(ix, iy)`: something there regardless of heights (taller than the hero, learnt).
     * Between two neighbouring cells a rise of more than `stepUp` is a wall or a ledge: the
     * higher cell is marked (a wall's foot, or the edge one could fall off).
     */
    public function build(centreX:Int, centreY:Int, height:(Int, Int) -> Float, solid:(Int, Int) -> Bool, stepUp:Float):Void {
        cx = centreX;
        cy = centreY;
        var z = [for (i in 0...size * size) {
            var ix = cx - radius + i % size, iy = cy - radius + Std.int(i / size);
            height(ix, iy);
        }];
        for (i in 0...size * size) {
            var ix = cx - radius + i % size, iy = cy - radius + Std.int(i / size);
            blocked[i] = solid(ix, iy);
        }
        for (j in 0...size) for (i in 0...size) {
            var here = z[j * size + i];
            if (!Math.isFinite(here)) continue;
            if (i + 1 < size) mark(j * size + i, j * size + i + 1, here, z[j * size + i + 1], stepUp);
            if (j + 1 < size) mark(j * size + i, (j + 1) * size + i, here, z[(j + 1) * size + i], stepUp);
        }
        distances();
    }

    inline function mark(a:Int, b:Int, za:Float, zb:Float, stepUp:Float):Void {
        if (!Math.isFinite(zb) || Math.abs(za - zb) <= stepUp) return;
        if (za > zb) blocked[a] = true else blocked[b] = true;
    }

    /** Two-pass chamfer distance transform: metres from every cell to the nearest blocked one. */
    function distances():Void {
        var d1 = CELL, d2 = CELL * Math.sqrt(2);
        for (i in 0...size * size) dist[i] = blocked[i] ? 0 : FAR;
        for (j in 0...size) for (i in 0...size) {
            var k = j * size + i;
            var v = dist[k];
            if (i > 0) v = Math.min(v, dist[k - 1] + d1);
            if (j > 0) {
                v = Math.min(v, dist[k - size] + d1);
                if (i > 0) v = Math.min(v, dist[k - size - 1] + d2);
                if (i + 1 < size) v = Math.min(v, dist[k - size + 1] + d2);
            }
            dist[k] = v;
        }
        var j = size - 1;
        while (j >= 0) {
            var i = size - 1;
            while (i >= 0) {
                var k = j * size + i;
                var v = dist[k];
                if (i + 1 < size) v = Math.min(v, dist[k + 1] + d1);
                if (j + 1 < size) {
                    v = Math.min(v, dist[k + size] + d1);
                    if (i + 1 < size) v = Math.min(v, dist[k + size + 1] + d2);
                    if (i > 0) v = Math.min(v, dist[k + size - 1] + d2);
                }
                dist[k] = v;
                i--;
            }
            j--;
        }
    }

    inline function index(x:Float, y:Float):Int {
        var i = cellOf(x) - cx + radius, j = cellOf(y) - cy + radius;
        return i < 0 || j < 0 || i >= size || j >= size ? -1 : j * size + i;
    }

    /** True if (x, y) is a blocked cell (outside the map: not known, so not blocked). */
    public function blockedAt(x:Float, y:Float):Bool {
        var k = index(x, y);
        return k >= 0 && blocked[k];
    }

    /** Metres from (x, y) to the nearest wall, edge or obstacle; `cap` when none is that close (or off the map). */
    public function clearance(x:Float, y:Float, cap:Float):Float {
        var k = index(x, y);
        return k < 0 ? cap : Math.min(cap, dist[k]);
    }

    /** How many of `count` directions around (x, y) are free of obstacles for `range` metres. */
    public function openDirections(x:Float, y:Float, count:Int, range:Float):Int {
        var open = 0;
        for (n in 0...count) {
            var a = n * 2 * Math.PI / count;
            var ux = Math.cos(a), uy = Math.sin(a);
            var free = true;
            var d = CELL;
            while (d <= range + 0.001) {
                if (blockedAt(x + ux * d, y + uy * d)) { free = false; break; }
                d += CELL;
            }
            if (free) open++;
        }
        return open;
    }

    public function blockedCount():Int {
        var n = 0;
        for (b in blocked) if (b) n++;
        return n;
    }
}
