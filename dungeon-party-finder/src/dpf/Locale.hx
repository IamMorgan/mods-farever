package dpf;

/**
 * Every text the mod shows, in the client's language (Options.language; the game's languages, as the calculator mod lists them:
 * en, de, fr, ru, zh, pt-BR, pl, tr, es, it, ko, ja, zh-TW, cz). An unknown language gets English.
 * Each text is a row of the table T: one string per language in the order of LANGS; {0} is filled in.
 */
class Locale {
    public static var LANGS = ["en", "de", "fr", "ru", "zh", "pt-BR", "pl", "tr", "es", "it", "ko", "ja", "zh-TW", "cz"];
    /** Index of the client's language in LANGS. */
    public static var lang = 0;

    /** The client's language code -> its index (an exact code first, then the language part: "pt" is "pt-BR"); English if unknown. */
    public static function setLanguage(code:String):String {
        lang = 0;
        if (code == null) return LANGS[0];
        var c = StringTools.replace(StringTools.trim(code).toLowerCase(), "_", "-");
        for (i in 0...LANGS.length) if (c == LANGS[i].toLowerCase()) { lang = i; return LANGS[i]; }
        var base = c.split("-")[0];
        for (i in 0...LANGS.length) if (base == LANGS[i].toLowerCase().split("-")[0]) { lang = i; return LANGS[i]; }
        return LANGS[0];
    }

    public static function f(key:String, ?arg:Dynamic):String {
        var row = T.get(key);
        if (row == null) return key;
        var s = row.length > lang && row[lang] != null && row[lang] != "" ? row[lang] : row[0];
        return arg == null ? s : StringTools.replace(s, "{0}", Std.string(arg));
    }

    public static function listTitle():String return f("listTitle");
    public static function listEmpty():String return f("listEmpty");
    public static function level(n:Int):String return f("level", n);
    public static function search():String return f("search");
    public static function searching():String return f("searching");
    public static function cancel():String return f("cancel");
    public static function inParty():String return f("inParty");
    public static function platformDown():String return f("platformDown");
    public static function noHero():String return f("noHero");
    public static function partyLost():String return f("partyLost");

    static var T:Map<String, Array<String>> = [
        "listTitle" => ["Dungeon Party Finder", "Dungeon-Gruppensuche", "Recherche de groupe de donjon", "Поиск группы в данжи", "地下城组队", "Busca de grupo para masmorras", "Wyszukiwarka grup do lochów", "Zindan Grup Bulucu", "Buscador de grupo de mazmorras", "Ricerca gruppo per dungeon", "던전 파티 찾기", "ダンジョンパーティ募集", "地城組隊", "Hledání družiny do dungeonů"],
        "listEmpty" => ["No dungeons found", "Keine Dungeons gefunden", "Aucun donjon trouvé", "Данжи не найдены", "未找到地下城", "Nenhuma masmorra encontrada", "Nie znaleziono lochów", "Zindan bulunamadı", "No se encontraron mazmorras", "Nessun dungeon trovato", "던전을 찾을 수 없습니다", "ダンジョンが見つかりません", "未找到地城", "Žádné dungeony nenalezeny"],
        "level" => ["Lv. {0}", "St. {0}", "Niv. {0}", "Ур. {0}", "{0}级", "Nv. {0}", "Poz. {0}", "Sv. {0}", "Nv. {0}", "Liv. {0}", "{0}레벨", "Lv.{0}", "{0}級", "Úr. {0}"],
        "search" => ["Search", "Suchen", "Rechercher", "Поиск", "搜索", "Buscar", "Szukaj", "Ara", "Buscar", "Cerca", "찾기", "検索", "搜尋", "Hledat"],
        "searching" => ["Searching...", "Suche läuft...", "Recherche...", "Поиск...", "搜索中...", "Buscando...", "Szukanie...", "Aranıyor...", "Buscando...", "Ricerca...", "찾는 중...", "検索中...", "搜尋中...", "Hledání..."],
        "cancel" => ["Cancel", "Abbrechen", "Annuler", "Отмена", "取消", "Cancelar", "Anuluj", "İptal", "Cancelar", "Annulla", "취소", "キャンセル", "取消", "Zrušit"],
        "inParty" => ["Leave your current group to start a search", "Verlasse deine Gruppe, um die Suche zu starten", "Quittez votre groupe actuel pour lancer une recherche", "Выйдите из текущей группы, чтобы начать поиск", "请先离开当前队伍再开始搜索", "Saia do seu grupo atual para iniciar a busca", "Opuść obecną grupę, aby rozpocząć wyszukiwanie", "Aramayı başlatmak için mevcut gruptan ayrıl", "Abandona tu grupo actual para iniciar la búsqueda", "Lascia il gruppo attuale per avviare la ricerca", "검색을 시작하려면 현재 파티를 나가세요", "検索を始めるには現在のパーティを抜けてください", "請先離開目前隊伍再開始搜尋", "Pro zahájení hledání opusť svou družinu"],
        "platformDown" => ["Matchmaking is unavailable: the platform's lobbies do not answer", "Gruppensuche nicht verfügbar: Die Lobbys der Plattform antworten nicht", "Recherche indisponible : les lobbies de la plateforme ne répondent pas", "Подбор недоступен: лобби платформы не отвечают", "匹配不可用：平台大厅无响应", "Busca indisponível: os lobbies da plataforma não respondem", "Wyszukiwanie niedostępne: lobby platformy nie odpowiadają", "Eşleştirme kullanılamıyor: platform lobileri yanıt vermiyor", "Búsqueda no disponible: las salas de la plataforma no responden", "Ricerca non disponibile: le lobby della piattaforma non rispondono", "매칭을 사용할 수 없습니다: 플랫폼 로비가 응답하지 않습니다", "マッチングを利用できません：プラットフォームのロビーが応答しません", "配對無法使用：平台大廳無回應", "Hledání není dostupné: lobby platformy neodpovídají"],
        "noHero" => ["No hero in the world", "Kein Held in der Welt", "Aucun héros dans le monde", "Нет героя в мире", "世界中没有英雄", "Nenhum herói no mundo", "Brak bohatera w świecie", "Dünyada kahraman yok", "No hay héroe en el mundo", "Nessun eroe nel mondo", "월드에 영웅이 없습니다", "ワールドにヒーローがいません", "世界中沒有英雄", "Ve světě není žádný hrdina"],
        "partyLost" => ["The group has broken up", "Die Gruppe hat sich aufgelöst", "Le groupe s'est dissous", "Группа распалась", "队伍已解散", "O grupo se desfez", "Grupa się rozpadła", "Grup dağıldı", "El grupo se ha disuelto", "Il gruppo si è sciolto", "파티가 해산되었습니다", "パーティが解散しました", "隊伍已解散", "Družina se rozpadla"],
        "showButton" => ["Show the DPF button", "DPF-Button anzeigen", "Afficher le bouton DPF", "Показывать кнопку DPF", "显示 DPF 按钮", "Mostrar o botão DPF", "Pokaż przycisk DPF", "DPF düğmesini göster", "Mostrar el botón DPF", "Mostra il pulsante DPF", "DPF 버튼 표시", "DPFボタンを表示", "顯示 DPF 按鈕", "Zobrazit tlačítko DPF"],
        "unpinned" => ["Unpin (drag the DPF button with the left mouse button)", "Lösen (DPF-Button mit der linken Maustaste ziehen)", "Détacher (déplacer le bouton DPF avec le clic gauche)", "Открепить (переносить кнопку DPF зажатием левой кнопки мыши)", "解除固定（按住鼠标左键拖动 DPF 按钮）", "Desafixar (arraste o botão DPF com o botão esquerdo do mouse)", "Odepnij (przeciągaj przycisk DPF lewym przyciskiem myszy)", "Sabitlemeyi kaldır (DPF düğmesini sol fare tuşuyla sürükle)", "Desanclar (arrastra el botón DPF con el botón izquierdo del ratón)", "Sblocca (trascina il pulsante DPF con il tasto sinistro del mouse)", "고정 해제 (마우스 왼쪽 버튼으로 DPF 버튼 이동)", "固定解除（マウス左ボタンでDPFボタンを移動）", "解除固定（按住滑鼠左鍵拖曳 DPF 按鈕）", "Odepnout (táhni tlačítko DPF levým tlačítkem myši)"],
        "buttonScale" => ["Button size %", "Button-Größe %", "Taille du bouton %", "Размер кнопки, %", "按钮大小 %", "Tamanho do botão %", "Rozmiar przycisku %", "Düğme boyutu %", "Tamaño del botón %", "Dimensione pulsante %", "버튼 크기 %", "ボタンサイズ %", "按鈕大小 %", "Velikost tlačítka %"]
    ];
}
