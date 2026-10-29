package comixmod;

import comixmod.GameAccess as G;

/** Comic outlines drawn on an h2d.Graphics. */
class Shapes {
    /** A filled polygon (flat x,y list) with an outline. */
    public static function polygon(g:Dynamic, points:Array<Float>, fill:Int, line:Int, lineSize:Float):Void {
        G.call("h2d.Graphics", "lineStyle", g, [lineSize, line, 1.0]);
        G.call("h2d.Graphics", "beginFill", g, [fill, 1.0]);
        G.call("h2d.Graphics", "moveTo", g, [points[0], points[1]]);
        var i = 2;
        while (i < points.length) {
            G.call("h2d.Graphics", "lineTo", g, [points[i], points[i + 1]]);
            i += 2;
        }
        G.call("h2d.Graphics", "lineTo", g, [points[0], points[1]]);
        G.call("h2d.Graphics", "endFill", g, []);
    }

    /** A spiky explosion: `spikes` points out to `outer`, notches in to `inner`. */
    public static function star(cx:Float, cy:Float, outer:Float, inner:Float, spikes:Int, turn:Float):Array<Float> {
        var out:Array<Float> = [];
        for (i in 0...spikes * 2) {
            var a = turn + Math.PI * i / spikes, r = i % 2 == 0 ? outer : inner;
            out.push(cx + Math.cos(a) * r);
            out.push(cy + Math.sin(a) * r * 0.8);
        }
        return out;
    }

    /** A scalloped cloud with `bumps` lobes. */
    public static function cloud(cx:Float, cy:Float, radius:Float, bumps:Int, turn:Float):Array<Float> {
        var out:Array<Float> = [], steps = bumps * 6;
        for (i in 0...steps) {
            var a = turn + Math.PI * 2 * i / steps;
            var r = radius * (0.84 + 0.16 * Math.abs(Math.sin(a * bumps / 2)));
            out.push(cx + Math.cos(a) * r);
            out.push(cy + Math.sin(a) * r * 0.75);
        }
        return out;
    }

    /** An ellipse as a polygon. */
    public static function ellipse(cx:Float, cy:Float, rx:Float, ry:Float):Array<Float> {
        var out:Array<Float> = [];
        for (i in 0...32) {
            var a = Math.PI * 2 * i / 32;
            out.push(cx + Math.cos(a) * rx);
            out.push(cy + Math.sin(a) * ry);
        }
        return out;
    }
}
