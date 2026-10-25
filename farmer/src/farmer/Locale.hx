package farmer;

/**
 * Every text the mod shows, in the client's language (Options.language; the game's languages:
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

    public static function f(key:String, ?arg:Dynamic, ?arg2:Dynamic):String {
        var row = T.get(key);
        if (row == null) return key;
        var s = row.length > lang && row[lang] != null && row[lang] != "" ? row[lang] : row[0];
        if (arg != null) s = StringTools.replace(s, "{0}", Std.string(arg));
        if (arg2 != null) s = StringTools.replace(s, "{1}", Std.string(arg2));
        return s;
    }

    static var T:Map<String, Array<String>> = [
        "button" => ["Farm", "Farm", "Farm", "Farm", "Farm", "Farm", "Farm", "Farm", "Farm", "Farm", "Farm", "Farm", "Farm", "Farm"],
        "title" => ["Farmer", "Farmer", "Farmer", "Фармер", "农夫", "Farmer", "Farmer", "Farmer", "Farmer", "Farmer", "파머", "ファーマー", "農夫", "Farmer"],
        "gather" => ["Gathering", "Sammeln", "Collecte", "Сбор", "采集", "Coleta", "Zbieranie", "Toplama", "Recolección", "Raccolta", "채집", "採取", "採集", "Sběr"],
        "hunt" => ["Hunting", "Jagd", "Chasse", "Добыча", "狩猎", "Caça", "Łowy", "Av", "Caza", "Caccia", "사냥", "狩猟", "狩獵", "Lov"],
        "recycle" => ["Recycle gear", "Ausrüstung recyceln", "Recycler l'équipement", "Переработка снаряжения", "回收装备", "Reciclar equipamento", "Przetwarzaj ekwipunek", "Ekipmanı geri dönüştür", "Reciclar equipo", "Ricicla equipaggiamento", "장비 분해", "装備を分解", "回收裝備", "Recyklovat vybavení"],
        "clear" => ["Empty the bag", "Tasche leeren", "Vider le sac", "Очистить сумку", "清空背包", "Esvaziar a bolsa", "Opróżnij torbę", "Çantayı boşalt", "Vaciar la bolsa", "Svuota la borsa", "가방 비우기", "バッグを空にする", "清空背包", "Vyprázdnit tašku"],
        "leveling" => ["Leveling", "Leveln", "Montée de niveau", "Левелинг", "升级", "Evolução", "Poziomowanie", "Seviye atlama", "Subida de nivel", "Livellamento", "레벨업", "レベル上げ", "升級", "Levelování"],
        "level" => ["Target level", "Ziel-Stufe", "Niveau cible", "Нужный уровень", "目标等级", "Nível alvo", "Docelowy poziom", "Hedef seviye", "Nivel objetivo", "Livello obiettivo", "목표 레벨", "目標レベル", "目標等級", "Cílová úroveň"],
        "green" => ["Green", "Grün", "Vert", "Зелёное", "绿色", "Verde", "Zielony", "Yeşil", "Verde", "Verde", "초록", "緑", "綠色", "Zelená"],
        "blue" => ["Blue", "Blau", "Bleu", "Синее", "蓝色", "Azul", "Niebieski", "Mavi", "Azul", "Blu", "파랑", "青", "藍色", "Modrá"],
        "epic" => ["Epic", "Episch", "Épique", "Эпическое", "史诗", "Épico", "Epicki", "Epik", "Épico", "Epico", "에픽", "エピック", "史詩", "Epická"],
        "legendary" => ["Legendary", "Legendär", "Légendaire", "Легендарное", "传说", "Lendário", "Legendarny", "Efsanevi", "Legendario", "Leggendario", "전설", "レジェンダリー", "傳說", "Legendární"],
        "start" => ["Farm", "Farmen", "Farmer", "Фарм", "开始", "Farmar", "Farm", "Farm", "Farmear", "Farm", "파밍", "ファーム", "開始", "Farmit"],
        "stop" => ["Stop", "Stopp", "Arrêter", "Стоп", "停止", "Parar", "Stop", "Durdur", "Detener", "Stop", "중지", "停止", "停止", "Stop"],
        "needCount" => ["{0} to farm", "{0} zu farmen", "{0} à farmer", "Нужно: {0}", "还需 {0}", "Faltam {0}", "Do zdobycia: {0}", "{0} gerekli", "Faltan {0}", "Ne servono {0}", "{0} 필요", "あと{0}", "還需 {0}", "Zbývá {0}"],
        "nothing" => ["Pick resources, a level or both", "Wähle Ressourcen, eine Stufe oder beides", "Choisissez des ressources, un niveau ou les deux", "Выберите ресурсы, уровень или и то и другое", "请选择资源、等级或两者", "Escolha recursos, um nível ou ambos", "Wybierz surowce, poziom lub oba", "Kaynak, seviye veya ikisini seçin", "Elige recursos, un nivel o ambos", "Scegli risorse, un livello o entrambi", "자원, 레벨 또는 둘 다 선택", "資源、レベル、または両方を選択", "請選擇資源、等級或兩者", "Vyber suroviny, úroveň nebo obojí"],
        "idle" => ["Idle", "Leerlauf", "Inactif", "Ожидание", "空闲", "Parado", "Bezczynny", "Boşta", "Inactivo", "Inattivo", "대기", "待機", "閒置", "Nečinný"],
        "stGather" => ["Gathering resources", "Sammelt Ressourcen", "Collecte des ressources", "Сбор ресурсов", "正在采集资源", "Coletando recursos", "Zbiera surowce", "Kaynak topluyor", "Recolectando recursos", "Raccolta risorse", "자원 채집 중", "資源を採取中", "正在採集資源", "Sbírá suroviny"],
        "stHunt" => ["Hunting monsters", "Jagt Monster", "Chasse les monstres", "Охота на мобов", "正在狩猎怪物", "Caçando monstros", "Poluje na potwory", "Canavar avlıyor", "Cazando monstruos", "Caccia ai mostri", "몬스터 사냥 중", "モンスターを狩猟中", "正在狩獵怪物", "Loví příšery"],
        "stTravel" => ["Travelling", "Unterwegs", "En déplacement", "В пути", "正在移动", "Viajando", "W drodze", "Yolda", "Viajando", "In viaggio", "이동 중", "移動中", "正在移動", "Na cestě"],
        "stRecycle" => ["Recycling gear", "Recycelt Ausrüstung", "Recycle l'équipement", "Переработка снаряжения", "正在回收装备", "Reciclando equipamento", "Przetwarza ekwipunek", "Ekipman geri dönüştürülüyor", "Reciclando equipo", "Ricicla l'equipaggiamento", "장비 분해 중", "装備を分解中", "正在回收裝備", "Recykluje vybavení"],
        "stBank" => ["Emptying the bag", "Leert die Tasche", "Vide le sac", "Очистка сумки", "正在清空背包", "Esvaziando a bolsa", "Opróżnia torbę", "Çantayı boşaltıyor", "Vaciando la bolsa", "Svuota la borsa", "가방 비우는 중", "バッグを空にしています", "正在清空背包", "Vyprazdňuje tašku"],
        "stHome" => ["Returning to the city", "Kehrt in die Stadt zurück", "Retour en ville", "Возвращение в город", "正在返回城镇", "Voltando para a cidade", "Wraca do miasta", "Şehre dönüyor", "Volviendo a la ciudad", "Ritorno in città", "도시로 귀환 중", "街へ戻っています", "正在返回城鎮", "Vrací se do města"],
        "stDone" => ["Done", "Fertig", "Terminé", "Готово", "完成", "Concluído", "Gotowe", "Bitti", "Hecho", "Fatto", "완료", "完了", "完成", "Hotovo"],
        "stWait" => ["Waiting", "Wartet", "En attente", "Ожидание", "等待中", "Aguardando", "Czeka", "Bekliyor", "Esperando", "In attesa", "대기 중", "待機中", "等待中", "Čeká"],
        "showButton" => ["Show the Farm button", "Farm-Button anzeigen", "Afficher le bouton Farm", "Показывать кнопку Farm", "显示 Farm 按钮", "Mostrar o botão Farm", "Pokaż przycisk Farm", "Farm düğmesini göster", "Mostrar el botón Farm", "Mostra il pulsante Farm", "Farm 버튼 표시", "Farmボタンを表示", "顯示 Farm 按鈕", "Zobrazit tlačítko Farm"],
        "buttonScale" => ["Button size %", "Button-Größe %", "Taille du bouton %", "Размер кнопки, %", "按钮大小 %", "Tamanho do botão %", "Rozmiar przycisku %", "Düğme boyutu %", "Tamaño del botón %", "Dimensione pulsante %", "버튼 크기 %", "ボタンサイズ %", "按鈕大小 %", "Velikost tlačítka %"],
        "bagFull" => ["The bag is full", "", "", "Сумка заполнена", "", "", "", "", "", "", "", "", "", ""],
        "noStone" => ["No teleportation stone: staying here", "", "", "Нет камня телепортации: остаюсь на месте", "", "", "", "", "", "", "", "", "", ""],
        "noTargets" => ["No targets right now", "", "", "Сейчас нет целей", "", "", "", "", "", "", "", "", "", ""],
        "stLevel" => ["Leveling up", "", "", "Набор уровня", "", "", "", "", "", "", "", "", "", ""],
        "stLoot" => ["Picking up loot", "", "", "Подбор добычи", "", "", "", "", "", "", "", "", "", ""],
        "unpinned" => ["Unpin (drag the Farm button with the left mouse button)", "Lösen (Farm-Button mit der linken Maustaste ziehen)", "Détacher (déplacer le bouton Farm avec le clic gauche)", "Открепить (переносить кнопку Farm зажатием левой кнопки мыши)", "解除固定（按住鼠标左键拖动 Farm 按钮）", "Desafixar (arraste o botão Farm com o botão esquerdo do mouse)", "Odepnij (przeciągaj przycisk Farm lewym przyciskiem myszy)", "Sabitlemeyi kaldır (Farm düğmesini sol fare tuşuyla sürükle)", "Desanclar (arrastra el botón Farm con el botón izquierdo del ratón)", "Sblocca (trascina il pulsante Farm con il tasto sinistro del mouse)", "고정 해제 (마우스 왼쪽 버튼으로 Farm 버튼 이동)", "固定解除（マウス左ボタンでFarmボタンを移動）", "解除固定（按住滑鼠左鍵拖曳 Farm 按鈕）", "Odepnout (táhni tlačítko Farm levým tlačítkem myši)"],
        "pickupLoot" => ["Pick up loot", "Beute aufheben", "Ramasser le butin", "Подбирать лут", "拾取战利品", "Pegar o saque", "Podnoś łupy", "Ganimeti topla", "Recoger botín", "Raccogli il bottino", "전리품 줍기", "戦利品を拾う", "拾取戰利品", "Sbírat kořist"],
        "replaceGear" => ["Replace gear", "Ausrüstung ersetzen", "Remplacer l'équipement", "Заменять экипировку", "更换装备", "Trocar equipamento", "Wymieniaj ekwipunek", "Ekipmanı değiştir", "Reemplazar equipo", "Sostituisci l'equipaggiamento", "장비 교체", "装備を入れ替える", "更換裝備", "Měnit vybavení"]
    ];
}
