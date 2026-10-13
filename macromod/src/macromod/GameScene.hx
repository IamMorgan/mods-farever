package macromod;

import macromod.RowFinder.SceneTree;

/** The game's UI tree (h2d objects) read through HlxRuntime. */
class GameScene implements SceneTree {
    var buttonSetText:hlx.runtime.ResolvedMember;

    public function new() {}

    static function field(object:Dynamic, name:String):Dynamic {
        if (object == null) return null;
        try return HlxRuntime.resolveField(object, name) catch (_:Dynamic) return null;
    }

    public function children(node:Dynamic):Array<Dynamic> {
        var list = field(node, "children");
        var out:Array<Dynamic> = [];
        if (list == null) return out;
        try {
            var count = Std.int(Std.parseFloat(Std.string(field(list, "length"))));
            var type = hl.Type.getDynamic(list).getTypeName();
            var read = HlxRuntime.resolveMember(HlxRuntime.resolveType(type), "getDyn");
            for (i in 0...count) out.push(HlxRuntime.callResolved(read, [list, i]));
        } catch (_:Dynamic) {}
        return out;
    }

    public function parent(node:Dynamic):Dynamic return field(node, "parent");

    public function text(node:Dynamic):Null<String> {
        var value:Dynamic = field(node, "text");
        return value != null && Std.isOfType(value, String) ? value : null;
    }

    public function isButton(node:Dynamic):Bool {
        try {
            var type = hl.Type.getDynamic(node);
            while (type != null && type.kind == HObj) {
                if (type.getTypeName() == "ui.comp.Button") return true;
                type = type.getSuper();
            }
        } catch (_:Dynamic) {}
        return false;
    }

    /** Changes a key button's caption the same way Better Mod Settings does after a right-click unbind. */
    public function setButtonText(button:Dynamic, text:String):Void {
        if (buttonSetText == null) buttonSetText = HlxRuntime.resolveMember(HlxRuntime.resolveType("ui.comp.Button"), "setText");
        if (buttonSetText != null) HlxRuntime.callResolved(buttonSetText, [button, text]);
    }
}
