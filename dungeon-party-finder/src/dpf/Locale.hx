package dpf;

/** Every text the mod shows in its own windows, in English and Russian (the client's language picks one). */
class Locale {
    public static function isRussian(language:String):Bool
        return language != null && StringTools.startsWith(language.toLowerCase(), "ru");

    static inline function t(ru:Bool, en:String, rus:String):String return ru ? rus : en;

    public static function listTitle(ru:Bool):String return t(ru, "Dungeon Party Finder", "Поиск группы в данжи");
    public static function listEmpty(ru:Bool):String return t(ru, "No dungeons found", "Данжи не найдены");
    public static function level(ru:Bool, n:Int):String return t(ru, "Lv. " + n, "Ур. " + n);
    public static function search(ru:Bool):String return t(ru, "Search", "Поиск");
    public static function searching(ru:Bool):String return t(ru, "Searching...", "Поиск...");
    public static function cancel(ru:Bool):String return t(ru, "Cancel", "Отмена");
    public static function inParty(ru:Bool):String
        return t(ru, "Leave your current group to start a search", "Выйдите из текущей группы, чтобы начать поиск");
    public static function platformDown(ru:Bool):String
        return t(ru, "Matchmaking is unavailable: the platform's lobbies do not answer", "Подбор недоступен: лобби платформы не отвечают");
    public static function noHero(ru:Bool):String return t(ru, "No hero in the world", "Нет героя в мире");
    public static function partyLost(ru:Bool):String return t(ru, "The group has broken up", "Группа распалась");
}
