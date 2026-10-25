package farmer;

/**
 * Auto-dodge diagnostics, switched off for release: nothing is written anywhere. Kept as empty
 * calls so the diagnostics can be brought back by giving these bodies again (they wrote
 * hlx/teleport-debug.txt: what auto-dodge saw and decided, and every hit the hero took).
 */
class DodgeLog {
    public static inline function write(now:Float, line:String):Void {}
    public static inline function tick(now:Float):Void {}
    public static inline function flush(now:Float):Void {}
}
