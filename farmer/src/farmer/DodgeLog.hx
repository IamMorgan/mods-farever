package farmer;

/** Auto-dodge diagnostics: what the dodge saw and decided and every hit the hero took go to the mod's log (tag "dodge"). */
class DodgeLog {
    public static inline function write(now:Float, line:String):Void Log.t("dodge", line);
    public static inline function tick(now:Float):Void {}
    public static inline function flush(now:Float):Void Log.flush();
}
