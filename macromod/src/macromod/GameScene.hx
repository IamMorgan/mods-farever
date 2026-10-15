package macromod;

import macromod.RowFinder.SceneTree;

/** The game's UI tree (h2d objects) read through HlxRuntime. */
class GameScene implements SceneTree {
    var buttonSetText:hlx.runtime.ResolvedMember;
    /** The settings control a row is searched for: key buttons, or text fields ("ui.comp.InputBox"). */
    var controlType:String;

    public function new(controlType = "ui.comp.Button") this.controlType = controlType;

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
        if (value == null) return null;
        if (Std.isOfType(value, String)) return value;
        // A game-side String (from another module) still has the same bytes/length layout.
        return Reflect.hasField(value, "bytes") && Reflect.hasField(value, "length") ? GameAccess.str(value) : null;
    }

    public function isButton(node:Dynamic):Bool return GameAccess.isA(node, controlType);

    /** Shows `text` in a settings text field (ui.comp.InputBox) without going through its edit events. */
    public static function setInputText(box:Dynamic, text:String):Void {
        var input = field(box, "input");
        if (input != null) GameAccess.call("h2d.TextInput", "set_text", input, [text]);
    }

    /** Changes a key button's caption the same way Better Mod Settings does after a right-click unbind. */
    public function setButtonText(button:Dynamic, text:String):Void {
        if (buttonSetText == null) buttonSetText = HlxRuntime.resolveMember(HlxRuntime.resolveType("ui.comp.Button"), "setText");
        if (buttonSetText != null) HlxRuntime.callResolved(buttonSetText, [button, text]);
    }
}
