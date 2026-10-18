package buildcalc;

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
    /** Name lookups share caches (ours and HlxRuntime's); the calculation's thread and the game's use them: one at a time. */
    static var lock = new sys.thread.Mutex();

    public static function type(name:String):hl.Bytes {
        lock.acquire();
        var t:hl.Bytes = null;
        try t = HlxRuntime.resolveType(name) catch (e:Dynamic) { lock.release(); throw e; }
        lock.release();
        return t;
    }

    static var members = new Map<String, hlx.runtime.ResolvedMember>();

    static function member(typeName:String, name:String, isStatic:Bool):hlx.runtime.ResolvedMember {
        var key = (isStatic ? "s:" : "m:") + typeName + "#" + name;
        lock.acquire();
        var m = members.get(key);
        if (m == null) {
            try {
                var t = HlxRuntime.resolveType(typeName);
                m = isStatic ? HlxRuntime.resolveStaticMember(t, name) : HlxRuntime.resolveMember(t, name);
                if (m != null) members.set(key, m);
            } catch (e:Dynamic) { lock.release(); throw e; }
        }
        lock.release();
        return m;
    }

    public static function at(arr:Dynamic, i:Int):Dynamic {
        try {
            var read = member(typeName(arr), "getDyn", false);
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

    public static function call(typeName:String, name:String, args:Array<Dynamic>):Dynamic {
        return HlxRuntime.callResolved(member(typeName, name, false), args);
    }

    public static function callStatic(typeName:String, name:String, args:Array<Dynamic>):Dynamic {
        return HlxRuntime.callResolved(member(typeName, name, true), args);
    }
}
