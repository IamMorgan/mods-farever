package macromod;

import hlx.runtime.ResolvedMember;

/** All game objects stay in their original HL module; never cast game arrays to Array<Dynamic>. */
class GameAccess {
    static var members:Map<String, ResolvedMember> = [];
    public static function field(object:Dynamic, name:String):Dynamic {
        if (object == null) return null;
        try return HlxRuntime.resolveField(object, name) catch (_:Dynamic) return null;
    }
    public static function text(value:Dynamic, fallback:String = ""):String {
        return value == null ? fallback : Std.string(value);
    }
    public static function number(value:Dynamic, fallback:Float = 0):Float {
        if (value == null) return fallback;
        var n = Std.parseFloat(Std.string(value));
        return Math.isFinite(n) ? n : fallback;
    }
    public static function integer(value:Dynamic, fallback:Int = 0):Int {
        return Std.int(number(value, fallback));
    }
    public static function member(type:String, name:String, isStatic:Bool = false):ResolvedMember {
        var key = type + (isStatic ? "::" : ".") + name;
        if (members.exists(key)) return members[key];
        var t = HlxRuntime.resolveType(type);
        if (t == null) throw "Game type unavailable: " + type;
        var m = isStatic ? HlxRuntime.resolveStaticMember(t, name) : HlxRuntime.resolveMember(t, name);
        if (m == null) throw "Game member unavailable: " + key;
        members[key] = m;
        return m;
    }
    public static function call(type:String, name:String, object:Dynamic, ?args:Array<Dynamic>):Dynamic {
        var all:Array<Dynamic> = [object];
        if (args != null) for (a in args) all.push(a);
        return HlxRuntime.callResolved(member(type, name), all);
    }
    public static function staticCall(type:String, name:String, args:Array<Dynamic>):Dynamic {
        return HlxRuntime.callResolved(member(type, name, true), args);
    }
    /** Raw allocation, bypassing the type's own constructor entirely - for types (like h2d.col.Point)
        whose real constructor signature isn't known/proven; fields are set directly afterward. */
    public static function allocRaw(type:String):Dynamic {
        var t = HlxRuntime.resolveType(type);
        if (t == null) throw "Game type unavailable: " + type;
        return HlxRuntime.allocInstance(t);
    }
    public static function current(type:String, name:String):Dynamic {
        var t = HlxRuntime.resolveType(type);
        return t == null ? null : HlxRuntime.resolveStaticField(t, name);
    }
    public static function create(type:String, args:Array<Dynamic>):Dynamic {
        var t = HlxRuntime.resolveType(type);
        if (t == null) throw "Game type unavailable: " + type;
        return HlxRuntime.constructInstanceByName(t, args.length, args);
    }
    public static function array(value:Dynamic, proxy:Bool = false):Array<Dynamic> {
        if (proxy) value = field(value, "array");
        var out:Array<Dynamic> = [];
        var count = integer(field(value, "length"));
        if (count <= 0) return out;
        // Replicated ArrayProxyData lists use ArrayDyn, while hero skill lists
        // use ArrayObj. Invoke the real array's reader without reinterpreting it.
        var type = hl.Type.getDynamic(value).getTypeName();
        for (i in 0...count) out.push(call(type, "getDyn", value, [i]));
        return out;
    }
    /** A game String as this module's own String (a native one fails Std.isOfType and would
        serialize as an object). Null stays null. */
    public static function str(value:Dynamic):Null<String> {
        if (value == null) return null;
        if (Std.isOfType(value, String)) return value;
        var bytes:hl.Bytes = Reflect.field(value, "bytes");
        var length:Null<Int> = Reflect.field(value, "length");
        if (bytes == null || length == null || length < 0) return Std.string(value);
        return @:privateAccess String.__alloc__(bytes, length);
    }
    /** True if the object's class, or one of its parents, is `typeName`. */
    public static function isA(object:Dynamic, typeName:String):Bool {
        if (object == null) return false;
        try {
            var type = hl.Type.getDynamic(object);
            while (type != null && type.kind == HObj) {
                if (type.getTypeName() == typeName) return true;
                type = type.getSuper();
            }
        } catch (_:Dynamic) {}
        return false;
    }
    public static function set(object:Dynamic, name:String, value:Dynamic):Void {
        if (object != null) HlxRuntime.setField(object, name, value);
    }
}
