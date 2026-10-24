package dpf;

import dpf.GameAccess as G;
import dpf.NativeUi as N;
import dpf.Session.Mode;

/**
 * The finder's part of the game's own dungeon window: a "Search" button under the "Start" button, and above them, while a
 * search runs, a turning circle with "Searching...". While it runs "Start" is off and the button reads "Cancel". The window
 * is built by the game; this adds its controls to the window's row of action controls (startBtn and its neighbours) and
 * looks after them every frame the game updates the window.
 */
class SearchControl {
    static inline var SPOKES = 12;
    static inline var SPIN_SPEED = 7.0;


    var ui:UiKit;
    var session:Session;
    var party:GameParty;
    var bound:Dynamic;
    var actions:Dynamic;
    var status:Dynamic;
    var button:Dynamic;
    var spin:Dynamic;
    /** The step being run, for the error report when a call into the game fails. */
    public var stage = "";
    var angle = 0.0;
    var buttonText = "";
    var statusText = "";

    public function new(ui:UiKit, session:Session, party:GameParty) {
        this.ui = ui;
        this.session = session;
        this.party = party;
    }

    /** True while a search for this very dungeon runs: the window must not start it. */
    public function blocks(screen:Dynamic):Bool
        return session.mode() == Searching && session.activityId == DungeonScreens.activityOf(screen);

    function forget():Void {
        bound = null;
        actions = status = button = spin = null;
        buttonText = statusText = "";
    }

    function bind(screen:Dynamic):Void {
        forget();
        stage = "bind: find start";
        var start = G.field(screen, "startBtn");
        var parent = start == null ? null : G.field(start, "parent");
        if (parent == null) return;
        bound = screen;
        if (!DungeonScreens.isDungeon(DungeonScreens.activityOf(screen))) return;
        actions = parent;
        var dom = G.field(actions, "dom");
        var index = N.children(actions).indexOf(start);
        if (index < 0) { forget(); return; }
        stage = "bind: status label";
        if (!TestFlags.has("nostatus")) status = N.label(dom, "", "dpfSearchStatus");
        stage = "bind: button";
        if (!TestFlags.has("nobutton")) button = N.button(dom, Locale.search(), "dpfSearchButton", () -> press(screen));
        buttonText = Locale.search();
        stage = "bind: insert";
        if (status != null) G.call("h2d.Flow", "addChildAt", actions, [status, index]);
        if (button != null) G.call("h2d.Flow", "addChildAt", actions, [button, index + (status == null ? 1 : 2)]);
        stage = "bind: width";
        var width = G.integer(G.field(start, "minWidth"), 0);
        if (width > 0 && button != null) N.size(button, width);

        stage = "bind: spinner";
        // The circle is one Graphics drawn around its own origin (so turning the object turns the circle), a child of the status
        // text: a child of the flow itself cannot be taken out of the flow's layout here (that call crashes).
        if (status != null && !TestFlags.has("nospin")) {
            spin = G.create("h2d.Graphics", [status]);
            stage = "bind: spinner spokes";
            var g = spin;
            for (i in 0...SPOKES) {
                var a0 = i * 2 * Math.PI / SPOKES, a1 = (i + 0.7) * 2 * Math.PI / SPOKES;
                var inner = 6.0, outer = 10.0;
                ui.poly(g, [Math.cos(a0) * inner, Math.sin(a0) * inner, Math.cos(a0) * outer, Math.sin(a0) * outer,
                    Math.cos(a1) * outer, Math.sin(a1) * outer, Math.cos(a1) * inner, Math.sin(a1) * inner], 0xFFE4AA, 0.15 + 0.85 * i / (SPOKES - 1));
            }
        }
        N.show(spin, false);
        N.show(status, false);
    }

    function press(screen:Dynamic):Void {
        try {
            if (session.mode() == Searching) { session.cancel(); return; }
            var lobby = DungeonScreens.lobbyOf(screen);
            if (lobby == null) return;
            session.start(DungeonScreens.activityOf(screen), G.integer(G.field(lobby, "difficulty")), haxe.Timer.stamp());
        } catch (error:Dynamic) trace("[DPF] search button failed: " + Std.string(error));
    }

    /** Every frame the game updates the dungeon window `screen`. */
    public function update(screen:Dynamic, dt:Float):Void {
        if (bound != screen || (button != null && G.field(button, "parent") == null)) bind(screen);
        if (button == null) return;
        stage = "update: mode";
        var mode = session.mode();
        var here = session.activityId == DungeonScreens.activityOf(screen);
        var searching = mode == Searching && here;
        stage = "update: shown";
        var shown = searching || (mode == Idle && party.groupSize() == 1);
        stage = "update: show button";
        N.show(button, shown);
        var text = searching ? Locale.cancel() : Locale.search();
        if (text != buttonText) { buttonText = text; N.setButtonText(button, text); }

        stage = "update: status line";
        var line = searching
            ? Locale.searching() + (session.found() > 0 ? "  " + session.found() + "/" + Session.GROUP : "")
            : (shown ? session.message : "");
        if (line != statusText) { statusText = line; N.setText(status, line); }
        N.show(status, line != "");
        N.show(spin, searching);

        stage = "update: searching";
        if (searching) {
            N.enable(G.field(screen, "startBtn"), false);
            angle += dt * SPIN_SPEED;
            if (spin != null && status != null) {
                G.call("h2d.Object", "set_rotation", spin, [angle]);
                var height = G.number(G.call("h2d.Text", "get_textHeight", status));
                N.position(spin, -16, height / 2);
            }
            // A different difficulty picked in the window: look for that one instead.
            var lobby = DungeonScreens.lobbyOf(screen);
            if (lobby != null && G.integer(G.field(lobby, "difficulty"), -1) != session.difficulty) {
                var activity = session.activityId;
                var difficulty = G.integer(G.field(lobby, "difficulty"));
                session.cancel();
                session.start(activity, difficulty, haxe.Timer.stamp());
            }
        }
    }
}
