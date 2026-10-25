package farmer;

typedef Point2 = {x:Float, y:Float};
typedef Line = {x:Float, y:Float, dx:Float, dy:Float, length:Float, radius:Float};

/** Pure geometry and timing for auto-dodge (no game access), so it can be tested on its own. */
class DodgeMath {
    /** How far along a projectile's path (from where it is now) the point lies; negative: behind it. */
    public static function along(line:Line, x:Float, y:Float):Float
        return (x - line.x) * line.dx + (y - line.y) * line.dy;

    /** True if a body of `bodyRadius` at (x, y) is in the projectile's way, ahead of it and within its remaining range. */
    public static function onLine(line:Line, x:Float, y:Float, bodyRadius:Float):Bool {
        var a = along(line, x, y);
        var reach = line.radius + bodyRadius;
        if (a < -reach || a > line.length + reach) return false;
        var side = Math.abs((x - line.x) * line.dy - (y - line.y) * line.dx);
        return side < reach;
    }

    /** Direction (radians) pointing from the dangers' sources to the hero: the way to run.
        Sources on the hero's own spot don't count; with none left, 0. */
    public static function awayAngle(hx:Float, hy:Float, sources:Array<Point2>):Float {
        var sx = 0.0, sy = 0.0;
        for (p in sources) {
            var dx = hx - p.x, dy = hy - p.y;
            var length = Math.sqrt(dx * dx + dy * dy);
            if (length < 0.01) continue;
            sx += dx / length; sy += dy / length;
        }
        return sx == 0 && sy == 0 ? 0.0 : Math.atan2(sy, sx);
    }

    /** `count` directions around the circle, `first` first, then alternating either side of it. */
    public static function searchAngles(first:Float, count:Int):Array<Float> {
        var step = 2 * Math.PI / count;
        var out = [first];
        var i = 1;
        while (out.length < count) {
            out.push(first + i * step);
            if (out.length < count) out.push(first - i * step);
            i++;
        }
        return out;
    }

    /** How much closer a monster can be when its swing lands: what its skill still moves it
        (`lunge`), plus walking at its current `speed` until then if it is moving at all; capped. */
    public static function advance(lunge:Float, speed:Float, moving:Float, timeLeft:Float, walkCap:Float, cap:Float):Float {
        var walk = speed >= moving ? Math.min(walkCap, speed * Math.max(0, timeLeft)) : 0.0;
        return Math.min(cap, Math.max(0, lunge) + walk);
    }

    /** True if a body of `bodyRadius` at (x, y) is within `reach` of (ox, oy). */
    public static function inReach(ox:Float, oy:Float, x:Float, y:Float, reach:Float, bodyRadius:Float):Bool {
        var dx = x - ox, dy = y - oy;
        var limit = reach + bodyRadius;
        return dx * dx + dy * dy < limit * limit;
    }

    /** Signed difference between two angles, in (-PI, PI]. */
    public static function angleDiff(a:Float, b:Float):Float {
        var d = (a - b) % (2 * Math.PI);
        if (d > Math.PI) d -= 2 * Math.PI;
        if (d <= -Math.PI) d += 2 * Math.PI;
        return d;
    }

    /** Where a spot at (x, y) is relative to a monster at (ox, oy) that came `by` closer to it,
        expressed back in world space: the same direction, `by` nearer to the monster. Null when
        the monster can come all the way there. */
    public static function closerBy(ox:Float, oy:Float, x:Float, y:Float, by:Float):Null<Point2> {
        if (by <= 0) return {x: x, y: y};
        var dx = x - ox, dy = y - oy;
        var distance = Math.sqrt(dx * dx + dy * dy);
        if (distance <= by) return null;
        var k = (distance - by) / distance;
        return {x: ox + dx * k, y: oy + dy * k};
    }

    /** Points every `step` along the straight way from (x0, y0) to (x1, y1), the end included, the start not. */
    public static function pathPoints(x0:Float, y0:Float, x1:Float, y1:Float, step:Float):Array<Point2> {
        var dx = x1 - x0, dy = y1 - y0;
        var length = Math.sqrt(dx * dx + dy * dy);
        var count = Std.int(Math.max(1, Math.ceil(length / step)));
        return [for (i in 1...count + 1) {x: x0 + dx * i / count, y: y0 + dy * i / count}];
    }

    /** A point beside the hero on the projectile's path (the nearest point of the path), so
        "away from it" means sideways out of the path. Hero right on the path: a point just to
        its left, so the hero goes right. */
    public static function sideSource(line:Line, hx:Float, hy:Float):Point2 {
        var a = along(line, hx, hy);
        var cx = line.x + line.dx * a, cy = line.y + line.dy * a;
        var ox = hx - cx, oy = hy - cy;
        if (ox * ox + oy * oy > 0.0001) return {x: cx, y: cy};
        return {x: hx + line.dy * 0.1, y: hy - line.dx * 0.1};
    }

    /** Where the hero is `t` seconds after setting off along `path` at `speed`, the first
        `dashDistance` metres covered in `dashTime` by a dash (0: no dash). */
    public static function positionAt(path:Array<Point2>, t:Float, speed:Float, dashDistance:Float, dashTime:Float):Point2 {
        var tt = Math.max(0, t);
        var s = dashDistance > 0
            ? (tt < dashTime ? dashDistance * tt / dashTime : dashDistance + (tt - dashTime) * speed)
            : tt * speed;
        for (i in 1...path.length) {
            var a = path[i - 1], b = path[i];
            var leg = Math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
            if (s <= leg && leg > 0) return {x: a.x + (b.x - a.x) * s / leg, y: a.y + (b.y - a.y) * s / leg};
            s -= leg;
        }
        return path[path.length - 1];
    }

    /** Seconds to walk `distance` at `speed`; infinite when the hero can't move. */
    public static function walkTime(distance:Float, speed:Float):Float
        return speed > 0 ? distance / speed : Math.POSITIVE_INFINITY;
}
