package dpf;

import dpf.GameAccess as G;

/**
 * A small crown on the party leader's banner in the list of party members on the left of the screen (the game's
 * ui.hud.GroupBar of ui.hud.UnitBanner). The leader of a group is its first player. The list lists the other members, so
 * the crown shows on the leader's banner for everyone but the leader.
 */
class CrownMarker {
    static inline var SIZE = 20.0;

    var ui:UiKit;
    var marks:Array<{banner:Dynamic, crown:Dynamic}> = [];
    var nextCheck = 0.0;

    public function new(ui:UiKit) this.ui = ui;

    public function hide():Void {
        for (m in marks) ui.remove(m.crown);
        marks = [];
    }

    /** About every half second: puts a crown on the leader's banner, takes it off the others'. */
    public function update(party:GameParty, now:Float):Void {
        if (now < nextCheck) return;
        nextCheck = now + 0.5;
        try {
            var banners = bannerList();
            var leader = party.groupSize() > 1 ? party.leader() : null;
            // forget crowns whose banner is gone
            marks = marks.filter(m -> {
                var alive = banners.indexOf(m.banner) >= 0 && G.field(m.crown, "allocated") == true;
                if (!alive) ui.remove(m.crown);
                return alive;
            });
            for (banner in banners) {
                var wanted = leader != null && playerOf(banner) == leader;
                var mark = marks.filter(m -> m.banner == banner)[0];
                if (wanted && mark == null) marks.push({banner: banner, crown: makeCrown(banner)});
                else if (!wanted && mark != null) { ui.remove(mark.crown); marks.remove(mark); }
                else if (mark != null) place(banner, mark.crown);
            }
        } catch (_:Dynamic) {}
    }

    function bannerList():Array<Dynamic> {
        var gameUi = G.current("ui.BaseUI", "current");
        if (gameUi == null) return [];
        var hud = G.call("ui.GameUI", "get_hud", gameUi);
        var bar = G.field(hud, "groupBar");
        if (bar == null) return [];
        var listed = G.array(G.field(bar, "banners"));
        return listed.length > 0 ? listed : collect(bar, 0);
    }

    /** Banners found by walking the bar's own children (in case the bar does not keep a list). */
    function collect(node:Dynamic, depth:Int):Array<Dynamic> {
        var out:Array<Dynamic> = [];
        if (node == null || depth > 4) return out;
        if (G.isA(node, "ui.hud.UnitBanner")) return [node];
        var count = G.integer(G.call("h2d.Object", "get_numChildren", node));
        for (i in 0...count) for (b in collect(G.call("h2d.Object", "getChildAt", node, [i]), depth + 1)) out.push(b);
        return out;
    }

    static function playerOf(banner:Dynamic):Dynamic {
        var unit = G.field(banner, "unit");
        return unit == null ? null : G.field(unit, "player");
    }

    function makeCrown(banner:Dynamic):Dynamic {
        var crown = G.create("h2d.Object", [banner]);
        var properties = G.call("h2d.Flow", "getProperties", banner, [crown]);
        G.call("h2d.FlowProperties", "set_isAbsolute", properties, [true]);
        G.set(properties, "offsetX", 0);
        G.set(properties, "offsetY", 0);
        place(banner, crown);
        Style.crown(ui, ui.shapes(crown), 0, 0, SIZE);
        return crown;
    }

    /** The crown sits on the banner's top right corner. */
    function place(banner:Dynamic, crown:Dynamic):Void {
        var width = 0.0;
        try width = G.number(G.call("h2d.Flow", "get_outerWidth", banner)) catch (_:Dynamic) {}
        G.call("h2d.Object", "setPosition", crown, [width > SIZE ? width - SIZE + 6 : -6, -9]);
    }
}
