package dpf;

/** The three levels of difficulty of a dungeon, as the game numbers them in its dungeon dialog. */
class Difficulties {
    public static inline var NORMAL = 0;
    public static inline var MAX_LEVEL = 1;
    public static inline var HEROIC = 2;
    public static inline var COUNT = 3;

    /**
     * Which of the three the hero may pick, by the game's own rules (InstanceLobby.getDifficultyReason): the second needs
     * the maximum level, the heroic one needs the dungeon's heroic mode to be released and the second difficulty of this
     * dungeon to have been completed once.
     */
    public static function available(level:Int, maxLevel:Int, heroicReleased:Bool, highestCompleted:Int):Array<Bool>
        return [true, level >= maxLevel, heroicReleased && highestCompleted >= 1];

    /** The first difficulty that is available at or below `wanted` (so a stale choice never stays on a locked one). */
    public static function clamp(wanted:Int, usable:Array<Bool>):Int {
        var i = wanted < 0 ? 0 : (wanted >= usable.length ? usable.length - 1 : wanted);
        while (i > 0 && !usable[i]) i--;
        return i;
    }
}
