package macromod;

/**
 * Turns "is the key down" samples into single press events.
 * A held key gives exactly one press, however many frames or OS auto-repeat events it lasts,
 * so a Toggle macro can't flip on and off while its key is held.
 */
class Edges {
    /** Presses closer together than this are treated as contact bounce. */
    public static inline var DEBOUNCE = 0.15;

    var previous:Map<Int, Bool> = new Map();
    var lastPress:Map<Int, Float> = new Map();

    public function new() {}

    public function pressed(code:Int, down:Bool, now:Float):Bool {
        var was = previous.get(code) == true;
        previous.set(code, down);
        if (!down || was) return false;
        var last = lastPress.get(code);
        if (last != null && now - last < DEBOUNCE) return false;
        lastPress.set(code, now);
        return true;
    }
}
