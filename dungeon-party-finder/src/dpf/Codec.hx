package dpf;

/**
 * Plain numbers for what goes through the game's lobby code. The game's serializer lives in another HL module than this
 * mod, so a String or an Array made here is not one of its own classes; whole numbers and plain objects of them are,
 * so strings travel as numbers: text packed two UTF-16 units to a number, and a search key as a single 49-bit number
 * (kept under 10^15 so that the game's text form of it is exact).
 */
class Codec {
    /** Longest text that is packed (account ids are far shorter). */
    public static inline var MAX_TEXT = 64;

    /** Two UTF-16 units to a number, in order; an odd last unit sits alone in the high half. */
    public static function pack(text:String):Array<Int> {
        var out:Array<Int> = [];
        var length = Std.int(Math.min(text.length, MAX_TEXT));
        var i = 0;
        while (i < length) {
            var high = StringTools.fastCodeAt(text, i);
            var low = i + 1 < length ? StringTools.fastCodeAt(text, i + 1) : 0;
            out.push((high << 16) | low);
            i += 2;
        }
        return out;
    }

    public static function unpack(numbers:Array<Int>):String {
        var buf = new StringBuf();
        for (n in numbers) {
            var high = (n >>> 16) & 0xFFFF, low = n & 0xFFFF;
            if (high != 0) buf.addChar(high);
            if (low != 0) buf.addChar(low);
        }
        return buf.toString();
    }

    /** 49 bits of two FNV-1a runs, as a whole Float below 10^15. */
    public static function hash(text:String):Float {
        var a:haxe.Int32 = 0x811C9DC5, b:haxe.Int32 = 0x050C5D1F;
        var prime:haxe.Int32 = 0x01000193;
        for (i in 0...text.length) {
            var c:haxe.Int32 = StringTools.fastCodeAt(text, i);
            a = (a ^ c) * prime;
            b = (b ^ c) * prime;
            b = (b << 13) | (b >>> 19);
        }
        var high:Int = (a : Int) & 0x1FFFF;
        var lowInt:Int = (b : Int);
        var low:Float = lowInt < 0 ? lowInt + 4294967296.0 : lowInt;
        return high * 4294967296.0 + low;
    }
}
