package selftest;

import hlx.runtime.HlxPrefixResult;
import selftest.GameAccess as G;

/**
 * Test helper for Dungeon Party Finder: not a feature, only eyes. Twice a second it writes what the game's UI looks like
 * (windows, buttons, scroll bars, with their screen positions) to hlx/logs/dpf-selftest.txt, so a driver script can click the
 * right places and check what opened. It changes nothing in the game.
 */
@:build(hlx.runtime.Mod.build())
class SelfTest {
    static var next = 0.0;
    static var dumped = false;
    static var lines:Array<String> = [];

    static function main():Void {}

    @:hlx.prefix(GameApp.update)
    static function before(instance:Dynamic, dt:Float):HlxPrefixResult<Void> {
        try tick(instance) catch (error:Dynamic) trace("[SELFTEST] tick failed: " + Std.string(error));
        return Continue;
    }

    static function typeName(o:Dynamic):String {
        try return hl.Type.getDynamic(o).getTypeName() catch (_:Dynamic) return "?";
    }

    static function children(o:Dynamic):Array<Dynamic> {
        var n = G.integer(G.call("h2d.Object", "get_numChildren", o));
        return [for (i in 0...n) G.call("h2d.Object", "getChildAt", o, [i])];
    }

    static function global(o:Dynamic):String {
        try {
            var p = G.call("h2d.Object", "localToGlobal", o, [null]);
            var w = 0, h = 0;
            if (G.isA(o, "h2d.Flow")) { w = G.integer(G.call("h2d.Flow", "get_outerWidth", o)); h = G.integer(G.call("h2d.Flow", "get_outerHeight", o)); }
            return "at " + Std.int(G.number(G.field(p, "x"))) + "," + Std.int(G.number(G.field(p, "y"))) + " size " + w + "x" + h;
        } catch (e:Dynamic) return "at ?";
    }

    static function textOf(o:Dynamic, depth = 0):String {
        if (G.isA(o, "h2d.Text")) return G.text(G.str(G.field(o, "text")));
        if (depth > 4) return "";
        for (c in children(o)) { var t = textOf(c, depth + 1); if (t != "") return t; }
        return "";
    }

    static function walk(o:Dynamic, depth:Int, budget:Array<Int>):Void {
        if (budget[0]-- <= 0 || depth > 12) return;
        var name = typeName(o);
        if (G.isA(o, "ui.comp.Button")) {
            lines.push("  button '" + textOf(o) + "' " + global(o) + " visible=" + G.field(o, "visible") + " enabled=" + G.field(o, "enable"));
            return;
        }
        if (G.isA(o, "h2d.Flow")) {
            var bar = G.field(o, "scrollBar");
            if (bar != null) lines.push("  scrollflow " + name + " " + global(o) + " bar visible=" + G.field(bar, "visible") + " " + global(bar) + " overflow=" + Std.string(G.field(o, "overflow")) + " barMinW=" + G.field(bar, "minWidth") + " barBg=" + (G.field(bar, "backgroundTile") != null) + " cursor=" + global(G.field(o, "scrollBarCursor")));
        }
        for (c in children(o)) walk(c, depth + 1, budget);
    }

    static function tree(o:Dynamic, depth:Int):Void {
        if (depth > 10 || lines.length > 400) return;
        var info = typeName(o) + " x=" + Std.int(G.number(G.field(o, "x"))) + " y=" + Std.int(G.number(G.field(o, "y"))) + " vis=" + G.field(o, "visible");
        if (G.isA(o, "h2d.Flow")) info += " w=" + G.integer(G.call("h2d.Flow", "get_outerWidth", o)) + " h=" + G.integer(G.call("h2d.Flow", "get_outerHeight", o));
        if (G.isA(o, "h2d.Mask")) info += " mask=" + G.field(o, "width") + "x" + G.field(o, "height") + " scroll=" + G.field(o, "scrollX") + "," + G.field(o, "scrollY");
        if (G.isA(o, "h2d.Bitmap")) {
            var tile = G.field(o, "tile");
            info += " tile=" + (tile != null);
            if (tile != null) {
                info += " " + Std.int(G.number(G.field(tile, "width"))) + "x" + Std.int(G.number(G.field(tile, "height")));
                var tex = G.field(tile, "innerTex");
                if (tex != null) info += " tex=" + (try Std.string(G.call("h3d.mat.Texture", "isDisposed", tex)) catch (_:Dynamic) "?");
            }
        }
        if (G.isA(o, "h2d.Text")) info += " '" + G.text(G.str(G.field(o, "text"))) + "'";
        lines.push(StringTools.lpad("", " ", depth * 2 + 2) + info);
        for (c in children(o)) tree(c, depth + 1);
    }

    static function tick(app:Dynamic):Void {
        var now = haxe.Timer.stamp();
        if (now < next) return;
        next = now + 0.5;
        lines = [];
        if (!dumped) {
            dumped = true;
            var out = [];
            for (entry in G.array(G.staticCall("HActivity", "allFiltered", [null]))) {
                var inf = G.field(entry, "inf");
                if (inf == null || G.staticCall("HActivity", "isDungeon", [inf]) != true) continue;
                out.push(G.text(G.str(G.field(inf, "id"))) + " rift=" + G.staticCall("HActivity", "isRift", [inf]) + " loadingScreen=" + G.str(G.field(G.field(inf, "props"), "loadingScreen")));
            }
            sys.io.File.saveContent("hlx/logs/dpf-selftest-activities.txt", out.join("
") + "
");
        }
        var hero = G.field(app, "hero");
        var gui = G.field(app, "gui");
        lines.push("time " + Std.int(now) + " hero=" + (hero != null) + " gui=" + (gui != null));
        if (gui != null) {
            var scene = G.field(gui, "s2d");
            var root = G.field(gui, "root");
            lines.push("scene " + Std.int(G.number(G.field(scene, "width"))) + "x" + Std.int(G.number(G.field(scene, "height"))) + " rootScale " + G.number(G.field(root, "scaleX"), 1));
            for (w in G.array(G.field(gui, "windows"))) {
                if (w == null) continue;
                lines.push("window " + typeName(w) + " " + global(w) + " parent=" + (G.field(w, "parent") != null));
            }
            walk(root, 0, [20000]);
            for (w in G.array(G.field(gui, "windows"))) {
                if (w != null && G.isA(w, "ui.win.element.InstanceSelectScreen")) { lines.push("dungeon window tree:"); tree(w, 0); }
            }
        }
        sys.io.File.saveContent("hlx/logs/dpf-selftest.txt", lines.join("\n") + "\n");
    }
}
