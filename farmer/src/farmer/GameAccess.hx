package farmer;

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
    /** Calls a method on the object's own (runtime) class, so a subclass's override is the one that runs. */
    public static function callVirtual(object:Dynamic, name:String, ?args:Array<Dynamic>):Dynamic
        return call(typeName(object), name, object, args);
    public static function staticCall(type:String, name:String, args:Array<Dynamic>):Dynamic {
        return HlxRuntime.callResolved(member(type, name, true), args);
    }
    /** Raw allocation, bypassing the type's own constructor entirely. */
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
    public static function enumValue(type:String, name:String, ?args:Array<Dynamic>):Dynamic {
        return HlxRuntime.constructEnum(HlxRuntime.resolveType(type), name, args == null ? [] : args);
    }
    public static function typeName(object:Dynamic):String {
        if (object == null) return "";
        try return hl.Type.getDynamic(object).getTypeName() catch (_:Dynamic) return "";
    }
    public static function len(value:Dynamic):Int return value == null ? 0 : integer(field(value, "length"));
    /** Element `i` of a game array (ArrayObj / ArrayDyn / the array of a proxy). */
    public static function at(value:Dynamic, i:Int):Dynamic {
        return call(typeName(value), "getDyn", value, [i]);
    }
    public static function array(value:Dynamic, proxy:Bool = false):Array<Dynamic> {
        if (proxy) value = field(value, "array");
        var out:Array<Dynamic> = [];
        var count = integer(field(value, "length"));
        if (count <= 0) return out;
        // Replicated ArrayProxyData lists use ArrayDyn, while hero skill lists
        // use ArrayObj. Invoke the real array's reader without reinterpreting it.
        var type = typeName(value);
        for (i in 0...count) out.push(call(type, "getDyn", value, [i]));
        return out;
    }
    /** `array` for a game ArrayObj read straight from its native storage (much faster for big lists). */
    public static function fastArray(value:Dynamic):Array<Dynamic> {
        if (value == null) return [];
        try {
            if (hl.Type.getDynamic(value).getTypeName() == "hl.types.ArrayObj") {
                var native:hl.NativeArray<Dynamic> = field(value, "array");
                var count = integer(field(value, "length"), -1);
                if (native != null && count >= 0 && count <= native.length) return [for (i in 0...count) native[i]];
            }
        } catch (_:Dynamic) {}
        return array(value);
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
    /** `str`, with "" for null. */
    public static function s(value:Dynamic):String {
        var v = str(value);
        return v == null ? "" : v;
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
    /** Records of a data sheet (Data.<sheet>.all). */
    public static function sheet(name:String):Array<Dynamic> {
        var out:Array<Dynamic> = [];
        try {
            var all = field(current("Data", name), "all");
            for (i in 0...len(all)) out.push(at(all, i));
        } catch (_:Dynamic) {}
        return out;
    }
}
