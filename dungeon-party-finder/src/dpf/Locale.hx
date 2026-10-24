package dpf;

/** Every text the mod shows in its own windows, in English and Russian (the client's language picks one). */
class Locale {
    public static function isRussian(language:String):Bool
        return language != null && StringTools.startsWith(language.toLowerCase(), "ru");

    static inline function t(ru:Bool, en:String, rus:String):String return ru ? rus : en;

    public static function listTitle(ru:Bool):String return t(ru, "Dungeon Party Finder", "Поиск группы в данжи");
    public static function listHint(ru:Bool):String return t(ru, "Pick a dungeon to look for a group", "Выберите данж, чтобы найти группу");
    public static function listEmpty(ru:Bool):String return t(ru, "No dungeons found", "Данжи не найдены");
    public static function level(ru:Bool, n:Int):String return t(ru, "Lv. " + n, "Ур. " + n);
    public static function page(ru:Bool, from:Int, to:Int, total:Int):String return from + "-" + to + " / " + total;

    public static function chooseDifficulty(ru:Bool):String return t(ru, "Choose difficulty", "Выберите уровень сложности");
    public static function requiredLevel(ru:Bool, n:Int):String return t(ru, "Required level: " + n, "Требуемый уровень: " + n);
    public static function recommendedLevel(ru:Bool, n:Int):String return t(ru, "Recommended level: " + n, "Рекомендуемый уровень: " + n);

    public static function difficultyName(ru:Bool, difficulty:Int):String
        return switch difficulty {
            case 1: t(ru, "Max level", "Максимальный уровень");
            case 2: t(ru, "Heroic", "Героическая");
            default: t(ru, "Normal", "Обычная");
        };

    public static function matching(ru:Bool, difficulty:Int, bracket:String):String
        return t(ru, "Group: " + difficultyName(ru, difficulty) + ", levels " + bracket, "Группа: " + difficultyName(ru, difficulty) + ", уровни " + bracket);

    public static function search(ru:Bool):String return t(ru, "Search", "Поиск");
    public static function searching(ru:Bool):String return t(ru, "Searching...", "Поиск...");
    public static function cancel(ru:Bool):String return t(ru, "Cancel", "Отмена");
    public static function start(ru:Bool):String return t(ru, "Start", "Начать");
    public static function ready(ru:Bool):String return t(ru, "Ready", "Готов");
    public static function waitPlayers(ru:Bool):String return t(ru, "Waiting for players", "Ожидание игроков");
    public static function loading(ru:Bool):String return t(ru, "Loading...", "Загрузка...");
    public static function waitLobby(ru:Bool):String return t(ru, "Opening the dungeon...", "Открываем данж...");

    public static function found(ru:Bool, n:Int, max:Int):String return t(ru, "Players found: " + n + "/" + max, "Найдено игроков: " + n + "/" + max);
    public static function inviting(ru:Bool):String return t(ru, "Group found, inviting...", "Группа найдена, отправляем приглашения...");
    public static function partyFormed(ru:Bool):String return t(ru, "Group formed", "Группа собрана");

    public static function inParty(ru:Bool):String
        return t(ru, "Leave your current group to start a search", "Выйдите из текущей группы, чтобы начать поиск");
    public static function platformDown(ru:Bool):String
        return t(ru, "Matchmaking is unavailable: the platform's lobbies do not answer", "Подбор недоступен: лобби платформы не отвечают");
    public static function noHero(ru:Bool):String return t(ru, "No hero in the world", "Нет героя в мире");
    public static function locked(ru:Bool):String return t(ru, "Not available for this hero", "Недоступно для этого героя");
    public static function partyLost(ru:Bool):String return t(ru, "The group has broken up", "Группа распалась");
    public static function lobbyRefused(ru:Bool):String
        return t(ru, "The game did not open this dungeon for the group (check levels and requirements)", "Игра не открыла данж для группы (проверьте уровни и условия)");
    public static function leaderMark(ru:Bool):String return t(ru, "Leader", "Лидер");
}
