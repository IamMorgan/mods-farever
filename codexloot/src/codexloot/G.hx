package codexloot;

/** Small null-safe helpers. The game is only ever reached through HlxRuntime. */
class G {
    public static function field(object:Dynamic, name:String):Dynamic {
        if (object == null) return null;
        try return HlxRuntime.resolveField(object, name) catch (_:Dynamic) return null;
    }

    public static function str(v:Dynamic):String {
        return v == null ? "" : Std.string(v);
    }

    /** Number, or 0 for null. */
    public static function num(v:Dynamic):Float {
        return v == null ? 0.0 : Std.parseFloat(Std.string(v));
    }

    public static function typeName(v:Dynamic):String {
        if (v == null) return "";
        try {
            var t = hl.Type.getDynamic(v);
            var n = t == null ? null : t.getTypeName();
            return n == null ? "" : n;
        } catch (_:Dynamic) {}
        return "";
    }

    public static function len(arr:Dynamic):Int {
        return arr == null ? 0 : Std.int(num(field(arr, "length")));
    }

    static var readers:Map<String, hlx.runtime.ResolvedMember> = new Map();

    public static function at(arr:Dynamic, i:Int):Dynamic {
        try {
            var tn = typeName(arr);
            var read = readers.get(tn);
            if (read == null) {
                read = HlxRuntime.resolveMember(HlxRuntime.resolveType(tn), "getDyn");
                readers.set(tn, read);
            }
            return HlxRuntime.callResolved(read, [arr, i]);
        } catch (_:Dynamic) {}
        return null;
    }

    public static function children(node:Dynamic):Array<Dynamic> {
        var out:Array<Dynamic> = [];
        var list = field(node, "children");
        for (i in 0...len(list)) out.push(at(list, i));
        return out;
    }

    public static function call(typeName:String, member:String, args:Array<Dynamic>):Dynamic {
        return HlxRuntime.callResolved(HlxRuntime.resolveMember(HlxRuntime.resolveType(typeName), member), args);
    }

    public static function callStatic(typeName:String, member:String, args:Array<Dynamic>):Dynamic {
        return HlxRuntime.callResolved(HlxRuntime.resolveStaticMember(HlxRuntime.resolveType(typeName), member), args);
    }
}
