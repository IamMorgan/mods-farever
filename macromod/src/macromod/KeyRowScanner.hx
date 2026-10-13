package macromod;

import macromod.RowFinder.SceneTree;

/** Adds something to a settings row; the real one draws the X button, tests use a fake. */
interface RowDecorator {
    /** Decorate the key button of `key`'s row. Returns the object that was added, or null if nothing could be added. */
    function decorate(key:String, button:Dynamic):Dynamic;
    /** False once the object is gone from the screen (its settings page was closed or rebuilt). Also asked about key buttons. */
    function isAlive(added:Dynamic):Bool;
}

/**
 * Looks for the settings rows of the macro keys while the settings window is open, a few hundred UI nodes
 * per frame so it never causes a hitch, and decorates each row once.
 */
class KeyRowScanner {
    /** UI nodes inspected per frame. */
    public static inline var BUDGET = 250;
    /** Pause between two full passes over the UI. */
    public static inline var PASS_GAP = 0.4;

    var tree:SceneTree;
    var decorator:RowDecorator;
    var labels:Map<String, String>; // row label -> setting key
    var stack:Array<Dynamic> = [];
    var scanning = false;
    var nextPass = 0.0;
    var done:Array<{button:Dynamic, added:Dynamic}> = [];
    var failed:Array<Dynamic> = []; // rows that could not be decorated: not retried

    public function new(tree:SceneTree, decorator:RowDecorator, labels:Map<String, String>) {
        this.tree = tree;
        this.decorator = decorator;
        this.labels = labels;
    }

    /** True while at least one decoration is still on screen (so the window is still open). */
    public function hasLive():Bool {
        prune();
        return done.length > 0;
    }

    function prune():Void {
        var i = done.length;
        while (i-- > 0) if (!decorator.isAlive(done[i].added)) done.splice(i, 1);
    }

    public function tick(root:Dynamic, now:Float):Void {
        if (root == null) return;
        if (!scanning) {
            if (now < nextPass) return;
            prune();
            stack = [root];
            scanning = true;
        }
        var budget = BUDGET;
        while (budget-- > 0 && stack.length > 0) {
            var node = stack.pop();
            var text = tree.text(node);
            if (text != null && labels.exists(text)) handle(node, labels.get(text));
            var kids = tree.children(node);
            var i = kids.length;
            while (i-- > 0) stack.push(kids[i]);
        }
        if (stack.length == 0) {
            scanning = false;
            nextPass = now + PASS_GAP;
        }
    }

    function handle(labelNode:Dynamic, key:String):Void {
        var button = RowFinder.buttonNear(labelNode, tree);
        // A page closed in the middle of a pass can leave stale nodes on the stack: skip anything off screen.
        if (button == null || !decorator.isAlive(button)) return;
        for (entry in done) if (entry.button == button) return;
        if (failed.indexOf(button) >= 0) return;
        var added = decorator.decorate(key, button);
        if (added != null) done.push({button: button, added: added});
        else { failed.push(button); if (failed.length > 100) failed.shift(); }
    }
}
