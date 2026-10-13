package macromod;

/** Read-only view of the game's UI tree; the real one is GameScene, tests use a fake. */
interface SceneTree {
    function children(node:Dynamic):Array<Dynamic>;
    function parent(node:Dynamic):Dynamic;
    /** The node's text if it has a string `text`, otherwise null. */
    function text(node:Dynamic):Null<String>;
    function isButton(node:Dynamic):Bool;
}

/** Finds the button that sits in the settings row with a given label. */
class RowFinder {
    static inline var MAX_NODES = 60000;
    static inline var MAX_CLIMB = 4;

    /** First node in the tree whose text is exactly `label`. */
    public static function findLabel(root:Dynamic, label:String, tree:SceneTree):Dynamic {
        var stack:Array<Dynamic> = [root];
        var visited = 0;
        while (stack.length > 0 && visited++ < MAX_NODES) {
            var node = stack.pop();
            if (tree.text(node) == label) return node;
            var kids = tree.children(node);
            var i = kids.length;
            while (i-- > 0) stack.push(kids[i]); // keeps document order
        }
        return null;
    }

    static function buttonsIn(root:Dynamic, tree:SceneTree, out:Array<Dynamic>):Void {
        var stack:Array<Dynamic> = [root];
        var visited = 0;
        while (stack.length > 0 && visited++ < MAX_NODES) {
            var node = stack.pop();
            if (tree.isButton(node)) { out.push(node); if (out.length > 1) return; }
            for (kid in tree.children(node)) stack.push(kid);
        }
    }

    /**
     * Climbs from a label node to the smallest container that holds a button. Only a container with exactly
     * one button counts: a bigger one would hold several rows, and guessing the wrong row is worse than doing nothing.
     */
    public static function buttonNear(labelNode:Dynamic, tree:SceneTree):Dynamic {
        var level = tree.parent(labelNode);
        for (_ in 0...MAX_CLIMB) {
            if (level == null) return null;
            var found = [];
            buttonsIn(level, tree, found);
            if (found.length == 1) return found[0];
            if (found.length > 1) return null;
            level = tree.parent(level);
        }
        return null;
    }

    public static function findButton(root:Dynamic, label:String, tree:SceneTree):Dynamic {
        var labelNode = findLabel(root, label, tree);
        return labelNode == null ? null : buttonNear(labelNode, tree);
    }
}
