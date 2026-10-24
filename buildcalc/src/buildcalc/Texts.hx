package buildcalc;

/**
 * Texts of the calculator in the client's language (Options.language; the game's languages, DataTools.getLangs:
 * en, de, fr, ru, zh, pt-BR, pl, tr, es, it, ko, ja, zh-TW, cz). Unknown languages: English.
 * Each text is a row of the table T: one string per language in the order of LANGS, {0} {1}… are filled in.
 */
class Texts {
    public static var LANGS = ["en", "de", "fr", "ru", "zh", "pt-BR", "pl", "tr", "es", "it", "ko", "ja", "zh-TW", "cz"];
    /** Index of the client's language in LANGS. */
    public static var lang = 0;
    public static var russian(get, never):Bool;
    static function get_russian():Bool return lang == 3;

    /** The client's language code (Options.language) -> its index; English when the game has a language we do not know. */
    public static function setLanguage(code:String):String {
        lang = 0;
        if (code == null) return LANGS[0];
        var c = code.toLowerCase();
        for (i in 0...LANGS.length) if (c == LANGS[i].toLowerCase()) { lang = i; return LANGS[i]; }
        for (i in 0...LANGS.length) if (StringTools.startsWith(c, LANGS[i].toLowerCase().split("-")[0])) { lang = i; return LANGS[i]; }
        return LANGS[0];
    }

    /** Characters a font must draw for this language (Ui picks the game's fonts that have them). */
    public static function sampleChars():Array<Int> {
        return switch (LANGS[lang]) {
            case "ru": [0x41F, 0x44B];
            case "zh": [0x4F24, 0x5BB3];
            case "zh-TW": [0x50B7, 0x5BB3];
            case "ja": [0x3042, 0x30C0];
            case "ko": [0xD53C, 0xD574];
            case "pl": [0x142, 0x15B];
            case "cz": [0x159, 0x17E];
            case "tr": [0x15F, 0x131];
            case "de": [0xDF, 0xFC];
            case "fr": [0xE9, 0xE8];
            case "es": [0xF1, 0xE1];
            case "it": [0xE0, 0xF9];
            case "pt-BR": [0xE3, 0xE7];
            default: [0x41];
        }
    }

    static function f(key:String, ?args:Array<Dynamic>):String {
        var row = T.get(key);
        if (row == null) return key;
        var s = row.length > lang && row[lang] != null && row[lang] != "" ? row[lang] : row[0];
        if (args != null) for (i in 0...args.length) s = StringTools.replace(s, "{" + i + "}", Std.string(args[i]));
        return s;
    }

    static var T:Map<String, Array<String>> = [
        "tab" => ["Build", "Build-Rechner", "Calculateur", "Калькулятор", "配装计算", "Calculadora", "Kalkulator", "Hesaplayıcı", "Calculadora", "Calcolatore", "빌드 계산", "ビルド計算", "配裝計算", "Kalkulačka"],
        "priorities" => ["Priorities", "Prioritäten", "Priorités", "Приоритеты", "优先级", "Prioridades", "Priorytety", "Öncelikler", "Prioridades", "Priorità", "우선순위", "優先度", "優先級", "Priority"],
        "ax0" => ["Damage", "Schaden", "Dégâts", "Урон", "伤害", "Dano", "Obrażenia", "Hasar", "Daño", "Danni", "피해", "ダメージ", "傷害", "Poškození"],
        "crit" => ["Criticality (crit chance)", "Kritikalität (Krit-Chance)", "Criticité (chance de critique)", "Критичность (шанс крита)", "暴击（暴击率）", "Criticidade (chance de crítico)", "Krytyczność (szansa na krytyk)", "Kritiklik (kritik şansı)", "Criticidad (prob. de crítico)", "Criticità (probabilità critico)", "치명 (치명타 확률)", "クリティカル（会心率）", "暴擊（暴擊率）", "Kritičnost (šance na kritický zásah)"],
        "ax1" => ["Defense", "Verteidigung", "Défense", "Защита", "防御", "Defesa", "Obrona", "Savunma", "Defensa", "Difesa", "방어", "防御", "防禦", "Obrana"],
        "ax2" => ["Health", "Gesundheit", "Santé", "Здоровье", "生命", "Vida", "Zdrowie", "Can", "Salud", "Salute", "생명력", "体力", "生命", "Zdraví"],
        "ax3" => ["Healing", "Heilung", "Soins", "Лечение", "治疗", "Cura", "Leczenie", "İyileştirme", "Curación", "Cure", "치유", "回復", "治療", "Léčení"],
        "lv0" => ["None", "Egal", "Aucune", "Не важно", "不重要", "Nenhuma", "Brak", "Önemsiz", "Ninguna", "Nessuna", "무관", "不要", "不重要", "Žádná"],
        "lv1" => ["Low", "Niedrig", "Basse", "Низкий", "低", "Baixa", "Niski", "Düşük", "Baja", "Bassa", "낮음", "低", "低", "Nízká"],
        "lv2" => ["Medium", "Mittel", "Moyenne", "Средний", "中", "Média", "Średni", "Orta", "Media", "Media", "보통", "中", "中", "Střední"],
        "lv3" => ["High", "Hoch", "Haute", "Высокий", "高", "Alta", "Wysoki", "Yüksek", "Alta", "Alta", "높음", "高", "高", "Vysoká"],
        "combat" => ["Combat", "Kampf", "Combat", "Тип боя", "战斗类型", "Combate", "Walka", "Savaş", "Combate", "Combattimento", "전투", "戦闘", "戰鬥類型", "Boj"],
        "melee" => ["Melee", "Nahkampf", "Mêlée", "Ближний", "近战", "Corpo a corpo", "Wręcz", "Yakın", "Cuerpo a cuerpo", "Mischia", "근접", "近接", "近戰", "Na blízko"],
        "ranged" => ["Ranged", "Fernkampf", "Distance", "Дальний", "远程", "À distância", "Dystans", "Uzak", "A distancia", "Distanza", "원거리", "遠距離", "遠程", "Na dálku"],
        "result" => ["Result", "Ergebnis", "Résultat", "Результат", "结果", "Resultado", "Wynik", "Sonuç", "Resultado", "Risultato", "결과", "結果", "結果", "Výsledek"],
        "show" => ["Show", "Anzeigen", "Afficher", "Показать", "显示", "Mostrar", "Pokaż", "Göster", "Mostrar", "Mostra", "보기", "表示", "顯示", "Zobrazit"],
        "calculate" => ["Calculate", "Berechnen", "Calculer", "Рассчитать", "计算", "Calcular", "Oblicz", "Hesapla", "Calcular", "Calcola", "계산", "計算", "計算", "Spočítat"],
        "templates" => ["Templates", "Vorlagen", "Modèles", "Шаблоны", "模板", "Modelos", "Szablony", "Şablonlar", "Plantillas", "Modelli", "템플릿", "テンプレート", "範本", "Šablony"],
        "template" => ["Template {0}", "Vorlage {0}", "Modèle {0}", "Шаблон {0}", "模板 {0}", "Modelo {0}", "Szablon {0}", "Şablon {0}", "Plantilla {0}", "Modello {0}", "템플릿 {0}", "テンプレート {0}", "範本 {0}", "Šablona {0}"],
        "save" => ["Save", "Speichern", "Enregistrer", "Сохранить", "保存", "Salvar", "Zapisz", "Kaydet", "Guardar", "Salva", "저장", "保存", "儲存", "Uložit"],
        "resetConfirm" => ["Sure? Click again", "Sicher? Erneut klicken", "Sûr ? Recliquez", "Точно? Нажмите ещё раз", "确定？再点一次", "Certeza? Clique de novo", "Na pewno? Kliknij ponownie", "Emin misiniz? Tekrar tıklayın", "¿Seguro? Pulsa otra vez", "Sicuro? Clicca di nuovo", "확실합니까? 다시 클릭", "よろしいですか？もう一度クリック", "確定？再點一次", "Opravdu? Klikněte znovu"],
        "talents" => ["Talents", "Talente", "Talents", "Таланты", "天赋", "Talentos", "Talenty", "Yetenekler", "Talentos", "Talenti", "특성", "タレント", "天賦", "Talenty"],
        "equipment" => ["Equipment", "Ausrüstung", "Équipement", "Экипировка", "装备", "Equipamento", "Ekwipunek", "Ekipman", "Equipo", "Equipaggiamento", "장비", "装備", "裝備", "Vybavení"],
        "savedTo" => ["Saved to template {0}.", "In Vorlage {0} gespeichert.", "Enregistré dans le modèle {0}.", "Сохранено в шаблон {0}.", "已保存到模板 {0}。", "Salvo no modelo {0}.", "Zapisano w szablonie {0}.", "Şablon {0} içine kaydedildi.", "Guardado en la plantilla {0}.", "Salvato nel modello {0}.", "템플릿 {0}에 저장했습니다.", "テンプレート {0} に保存しました。", "已儲存到範本 {0}。", "Uloženo do šablony {0}."],
        "opened" => ["Template {0} opened.", "Vorlage {0} geöffnet.", "Modèle {0} ouvert.", "Открыт шаблон {0}.", "已打开模板 {0}。", "Modelo {0} aberto.", "Otwarto szablon {0}.", "Şablon {0} açıldı.", "Plantilla {0} abierta.", "Modello {0} aperto.", "템플릿 {0}을 열었습니다.", "テンプレート {0} を開きました。", "已開啟範本 {0}。", "Šablona {0} otevřena."],
        "emptyTemplate" => ["Template {0} is empty: press Save to fill it.", "Vorlage {0} ist leer: zum Füllen „Speichern“ drücken.", "Le modèle {0} est vide : appuyez sur Enregistrer.", "Шаблон {0} пуст: нажмите «Сохранить», чтобы записать его.", "模板 {0} 为空：点击“保存”写入。", "O modelo {0} está vazio: clique em Salvar.", "Szablon {0} jest pusty: naciśnij Zapisz.", "Şablon {0} boş: doldurmak için Kaydet'e basın.", "La plantilla {0} está vacía: pulsa Guardar.", "Il modello {0} è vuoto: premi Salva.", "템플릿 {0}이 비어 있습니다: 저장을 누르세요.", "テンプレート {0} は空です：保存を押してください。", "範本 {0} 為空：點擊「儲存」寫入。", "Šablona {0} je prázdná: stiskněte Uložit."],
        "noTalents" => ["This class has no talent tree.", "Diese Klasse hat keinen Talentbaum.", "Cette classe n'a pas d'arbre de talents.", "У этого класса нет дерева талантов.", "该职业没有天赋树。", "Esta classe não tem árvore de talentos.", "Ta klasa nie ma drzewka talentów.", "Bu sınıfın yetenek ağacı yok.", "Esta clase no tiene árbol de talentos.", "Questa classe non ha un albero dei talenti.", "이 직업에는 특성 트리가 없습니다.", "このクラスにはタレントツリーがありません。", "該職業沒有天賦樹。", "Tato třída nemá strom talentů."],
        "points" => ["Points: {0} / {1}", "Punkte: {0} / {1}", "Points : {0} / {1}", "Очки: {0} / {1}", "点数：{0} / {1}", "Pontos: {0} / {1}", "Punkty: {0} / {1}", "Puan: {0} / {1}", "Puntos: {0} / {1}", "Punti: {0} / {1}", "포인트: {0} / {1}", "ポイント：{0} / {1}", "點數：{0} / {1}", "Body: {0} / {1}"],
        "current" => ["The hero's current talents, skills and runes. Press \"Calculate\".", "Aktuelle Talente, Fertigkeiten und Runen des Helden. „Berechnen“ drücken.", "Talents, compétences et runes actuels du héros. Appuyez sur « Calculer ».", "Текущие таланты, умения и руны героя. Нажмите «Рассчитать».", "英雄当前的天赋、技能和符文。点击“计算”。", "Talentos, habilidades e runas atuais do herói. Clique em \"Calcular\".", "Obecne talenty, umiejętności i runy bohatera. Naciśnij „Oblicz”.", "Kahramanın mevcut yetenekleri, becerileri ve rünleri. \"Hesapla\"ya basın.", "Talentos, habilidades y runas actuales del héroe. Pulsa «Calcular».", "Talenti, abilità e rune attuali dell'eroe. Premi «Calcola».", "영웅의 현재 특성, 스킬, 룬. \"계산\"을 누르세요.", "ヒーローの現在のタレント、スキル、ルーン。「計算」を押してください。", "英雄目前的天賦、技能與符文。點擊「計算」。", "Současné talenty, dovednosti a runy hrdiny. Stiskněte „Spočítat“."],
        "skills" => ["Skills and runes", "Fertigkeiten und Runen", "Compétences et runes", "Умения и руны", "技能与符文", "Habilidades e runas", "Umiejętności i runy", "Beceriler ve rünler", "Habilidades y runas", "Abilità e rune", "스킬과 룬", "スキルとルーン", "技能與符文", "Dovednosti a runy"],
        "resetOne" => ["Reset", "Zurücksetzen", "Réinitialiser", "Сбросить", "重置", "Redefinir", "Wyczyść", "Sıfırla", "Restablecer", "Azzera", "초기화", "リセット", "重設", "Vymazat"],
        "clearedOne" => ["Template {0} reset.", "Vorlage {0} zurückgesetzt.", "Modèle {0} réinitialisé.", "Шаблон {0} сброшен.", "模板 {0} 已重置。", "Modelo {0} redefinido.", "Szablon {0} wyczyszczony.", "Şablon {0} sıfırlandı.", "Plantilla {0} restablecida.", "Modello {0} azzerato.", "템플릿 {0}을 초기화했습니다.", "テンプレート {0} をリセットしました。", "範本 {0} 已重設。", "Šablona {0} vymazána."],
        "alreadyBest" => ["Your equipment is already the best of all items of the game for these priorities.", "Deine Ausrüstung ist für diese Prioritäten bereits die beste.", "Votre équipement est déjà le meilleur pour ces priorités.", "Ваша экипировка уже лучшая из всех предметов игры для этих приоритетов.", "按这些优先级，你的装备已是最佳。", "Seu equipamento já é o melhor para estas prioridades.", "Twój ekwipunek jest już najlepszy dla tych priorytetów.", "Ekipmanınız bu öncelikler için zaten en iyisi.", "Tu equipo ya es el mejor para estas prioridades.", "Il tuo equipaggiamento è già il migliore per queste priorità.", "이 우선순위에서는 현재 장비가 이미 최고입니다.", "この優先度では現在の装備が既に最良です。", "依這些優先級，你的裝備已是最佳。", "Vaše vybavení je pro tyto priority už nejlepší."],
        "changedSlots" => ["{0} slot(s) to change (green).", "{0} Platz/Plätze zu ändern (grün).", "{0} emplacement(s) à changer (en vert).", "Заменить слотов: {0} (выделены зелёным).", "需更换 {0} 个栏位（绿色）。", "{0} espaço(s) para trocar (verde).", "Do zmiany: {0} (na zielono).", "Değiştirilecek yuva: {0} (yeşil).", "{0} ranura(s) por cambiar (en verde).", "{0} slot da cambiare (in verde).", "교체할 슬롯 {0}개 (초록색).", "交換するスロット：{0}（緑）。", "需更換 {0} 個欄位（綠色）。", "Vyměnit slotů: {0} (zeleně)."],
        "sigil" => ["sigil", "Siegel", "sceau", "печать", "印记", "selo", "pieczęć", "mühür", "sello", "sigillo", "인장", "印章", "印記", "pečeť"],
        "mainStats" => ["Main", "Haupt", "Principales", "Основные", "主要", "Principais", "Główne", "Ana", "Principales", "Principali", "주요", "主要", "主要", "Hlavní"],
        "otherStats" => ["Other", "Weitere", "Autres", "Остальные", "其他", "Outros", "Pozostałe", "Diğer", "Otros", "Altri", "기타", "その他", "其他", "Ostatní"],
        "newStats" => ["Attributes of the new build", "Werte des neuen Builds", "Attributs du nouveau build", "Характеристики нового билда", "新配装属性", "Atributos da nova build", "Atrybuty nowego buildu", "Yeni yapının özellikleri", "Atributos de la nueva build", "Attributi della nuova build", "새 빌드 능력치", "新ビルドの能力値", "新配裝屬性", "Atributy nového buildu"],
        "nowStats" => ["Attributes now", "Aktuelle Werte", "Attributs actuels", "Характеристики сейчас", "当前属性", "Atributos atuais", "Obecne atrybuty", "Mevcut özellikler", "Atributos actuales", "Attributi attuali", "현재 능력치", "現在の能力値", "目前屬性", "Současné atributy"],
        "considered" => ["Items considered: {0}.", "Geprüfte Gegenstände: {0}.", "Objets examinés : {0}.", "Проверено предметов: {0}.", "已检查物品：{0}。", "Itens verificados: {0}.", "Sprawdzone przedmioty: {0}.", "İncelenen eşya: {0}.", "Objetos revisados: {0}.", "Oggetti esaminati: {0}.", "검토한 아이템: {0}.", "確認したアイテム：{0}。", "已檢查物品：{0}。", "Prověřeno předmětů: {0}."],
        "noItems" => ["Error: no item of the game was found for the slots (see hlx/buildcalc-debug.txt).", "Fehler: kein Gegenstand für die Plätze gefunden (siehe hlx/buildcalc-debug.txt).", "Erreur : aucun objet trouvé pour les emplacements (voir hlx/buildcalc-debug.txt).", "Ошибка: не найдено ни одного предмета игры для слотов (см. hlx/buildcalc-debug.txt).", "错误：未找到适用于栏位的物品（见 hlx/buildcalc-debug.txt）。", "Erro: nenhum item encontrado para os espaços (veja hlx/buildcalc-debug.txt).", "Błąd: nie znaleziono przedmiotów do miejsc (zob. hlx/buildcalc-debug.txt).", "Hata: yuvalar için eşya bulunamadı (bkz. hlx/buildcalc-debug.txt).", "Error: no se encontró ningún objeto para las ranuras (ver hlx/buildcalc-debug.txt).", "Errore: nessun oggetto trovato per gli slot (vedi hlx/buildcalc-debug.txt).", "오류: 슬롯에 맞는 아이템이 없습니다 (hlx/buildcalc-debug.txt 참조).", "エラー：スロットに合うアイテムがありません（hlx/buildcalc-debug.txt を参照）。", "錯誤：找不到適用於欄位的物品（見 hlx/buildcalc-debug.txt）。", "Chyba: pro sloty nebyl nalezen žádný předmět (viz hlx/buildcalc-debug.txt)."],
        "craft" => ["craft", "Herst.", "artisanat", "крафт", "制作", "criar", "crafting", "üretim", "crear", "craft", "제작", "製作", "製作", "výroba"],
        "drop" => ["drop", "Beute", "butin", "дроп", "掉落", "drop", "łup", "ganimet", "botín", "bottino", "드롭", "ドロップ", "掉落", "kořist"],
        "owned" => ["owned", "vorhanden", "possédé", "есть", "已有", "possui", "masz", "sende", "tienes", "posseduto", "보유", "所持", "已有", "máte"],
        "improve" => ["upgrade", "verbess.", "amélior.", "улучш.", "改进", "melhorar", "ulepsz.", "geliştir", "mejorar", "migliora", "개선", "改善", "改進", "vylepšit"],
        "infusionOf" => ["Infusion: {0}", "Infusion: {0}", "Infusion : {0}", "Пропитка: {0}", "灌注：{0}", "Infusão: {0}", "Nasycenie: {0}", "Aşılama: {0}", "Infusión: {0}", "Infusione: {0}", "주입: {0}", "インフュージョン：{0}", "灌注：{0}", "Infuze: {0}"],
        "infusionNone" => ["No infusion", "Keine Infusion", "Aucune infusion", "Без пропитки", "无灌注", "Sem infusão", "Bez nasycenia", "Aşılama yok", "Sin infusión", "Nessuna infusione", "주입 없음", "インフュージョンなし", "無灌注", "Bez infuze"],
        "none" => ["none", "keine", "aucune", "нет", "无", "nenhuma", "brak", "yok", "ninguna", "nessuna", "없음", "なし", "無", "žádná"],
        "nowWas" => ["(now: {0})", "(jetzt: {0})", "(actuellement : {0})", "(сейчас: {0})", "（当前：{0}）", "(agora: {0})", "(teraz: {0})", "(şu an: {0})", "(ahora: {0})", "(ora: {0})", "(현재: {0})", "（現在：{0}）", "（目前：{0}）", "(nyní: {0})"],
        "chosenNote" => ["Talents, skills and runes chosen by the calculator (green: to change).", "Vom Rechner gewählte Talente, Fertigkeiten und Runen (grün: ändern).", "Talents, compétences et runes choisis par le calculateur (en vert : à changer).", "Таланты, умения и руны подобраны калькулятором (зелёным — что поменять).", "计算器选出的天赋、技能和符文（绿色：需更换）。", "Talentos, habilidades e runas escolhidos pela calculadora (verde: trocar).", "Talenty, umiejętności i runy wybrane przez kalkulator (zielone: do zmiany).", "Hesaplayıcının seçtiği yetenekler, beceriler ve rünler (yeşil: değiştir).", "Talentos, habilidades y runas elegidos por la calculadora (verde: cambiar).", "Talenti, abilità e rune scelti dal calcolatore (verde: da cambiare).", "계산기가 고른 특성, 스킬, 룬 (초록색: 변경).", "計算機が選んだタレント・スキル・ルーン（緑：変更）。", "計算器選出的天賦、技能與符文（綠色：需更換）。", "Talenty, dovednosti a runy zvolené kalkulačkou (zeleně: změnit)."],
        "calcTime" => ["Calculated in {0} s.", "Berechnet in {0} s.", "Calculé en {0} s.", "Расчёт занял {0} с.", "计算用时 {0} 秒。", "Calculado em {0} s.", "Obliczono w {0} s.", "{0} sn'de hesaplandı.", "Calculado en {0} s.", "Calcolato in {0} s.", "{0}초 만에 계산했습니다.", "{0} 秒で計算しました。", "計算耗時 {0} 秒。", "Spočítáno za {0} s."],
        "calculatingButton" => ["Calculating...", "Berechne...", "Calcul...", "Идёт расчёт…", "计算中…", "Calculando...", "Obliczanie...", "Hesaplanıyor...", "Calculando...", "Calcolo...", "계산 중...", "計算中…", "計算中…", "Počítám..."],
        "calculating" => ["Calculating... {0}%", "Berechne... {0}%", "Calcul... {0} %", "Идёт расчёт… {0}%", "计算中… {0}%", "Calculando... {0}%", "Obliczanie... {0}%", "Hesaplanıyor... %{0}", "Calculando... {0}%", "Calcolo... {0}%", "계산 중... {0}%", "計算中… {0}%", "計算中… {0}%", "Počítám... {0} %"],
        "failed" => ["The calculation failed (see hlx/buildcalc-debug.txt).", "Die Berechnung ist fehlgeschlagen (siehe hlx/buildcalc-debug.txt).", "Le calcul a échoué (voir hlx/buildcalc-debug.txt).", "Расчёт не удался (см. hlx/buildcalc-debug.txt).", "计算失败（见 hlx/buildcalc-debug.txt）。", "O cálculo falhou (veja hlx/buildcalc-debug.txt).", "Obliczenie nie powiodło się (zob. hlx/buildcalc-debug.txt).", "Hesaplama başarısız (bkz. hlx/buildcalc-debug.txt).", "El cálculo falló (ver hlx/buildcalc-debug.txt).", "Il calcolo non è riuscito (vedi hlx/buildcalc-debug.txt).", "계산에 실패했습니다 (hlx/buildcalc-debug.txt 참조).", "計算に失敗しました（hlx/buildcalc-debug.txt を参照）。", "計算失敗（見 hlx/buildcalc-debug.txt）。", "Výpočet selhal (viz hlx/buildcalc-debug.txt)."],
        "weapon" => ["Weapon", "Waffe", "Arme", "Оружие", "武器", "Arma", "Broń", "Silah", "Arma", "Arma", "무기", "武器", "武器", "Zbraň"],
        "arsenal" => ["Arsenal", "Arsenal", "Arsenal", "Арсенал", "军械库", "Arsenal", "Arsenał", "Cephanelik", "Arsenal", "Arsenale", "무기고", "アーセナル", "軍械庫", "Arzenál"],
        "mainWeapon" => ["Main", "Haupt", "Principale", "Основное", "主手", "Principal", "Główna", "Ana", "Principal", "Principale", "주무기", "メイン", "主手", "Hlavní"],
        "offhand" => ["Off-hand", "Nebenhand", "Main gauche", "Левая рука", "副手", "Mão secundária", "Druga ręka", "Yan el", "Mano izquierda", "Mano secondaria", "보조", "オフハンド", "副手", "Druhá ruka"],
        "arsenalWeapon" => ["Arsenal ×{0}", "Arsenal ×{0}", "Arsenal ×{0}", "Арсенал ×{0}", "军械库 ×{0}", "Arsenal ×{0}", "Arsenał ×{0}", "Cephanelik ×{0}", "Arsenal ×{0}", "Arsenale ×{0}", "무기고 ×{0}", "アーセナル ×{0}", "軍械庫 ×{0}", "Arzenál ×{0}"],
        "totals" => ["Model estimate: DPS {0} (now {1}) · self heal {2}/s ({3}) · allies {4}/s ({5})", "Schätzung: DPS {0} (jetzt {1}) · Selbstheilung {2}/s ({3}) · Verbündete {4}/s ({5})", "Estimation : DPS {0} (actuel {1}) · soins sur soi {2}/s ({3}) · alliés {4}/s ({5})", "Оценка мода: ДПС {0} (у текущего {1}) · лечение себя {2}/с ({3}) · союзников {4}/с ({5})", "估算：DPS {0}（当前 {1}）· 自疗 {2}/秒（{3}）· 队友 {4}/秒（{5}）", "Estimativa: DPS {0} (atual {1}) · cura própria {2}/s ({3}) · aliados {4}/s ({5})", "Szacunek: DPS {0} (teraz {1}) · leczenie siebie {2}/s ({3}) · sojuszników {4}/s ({5})", "Tahmin: DPS {0} (şu an {1}) · kendini iyileştirme {2}/sn ({3}) · müttefik {4}/sn ({5})", "Estimación: DPS {0} (actual {1}) · autocuración {2}/s ({3}) · aliados {4}/s ({5})", "Stima: DPS {0} (ora {1}) · cura propria {2}/s ({3}) · alleati {4}/s ({5})", "추정: DPS {0} (현재 {1}) · 자가 치유 {2}/초 ({3}) · 아군 {4}/초 ({5})", "推定：DPS {0}（現在 {1}）· 自己回復 {2}/秒（{3}）· 味方 {4}/秒（{5}）", "估算：DPS {0}（目前 {1}）· 自療 {2}/秒（{3}）· 隊友 {4}/秒（{5}）", "Odhad: DPS {0} (nyní {1}) · léčení sebe {2}/s ({3}) · spojenců {4}/s ({5})"],
        "infusionRecommended" => ["Recommended infusions", "Empfohlene Infusionen", "Infusions recommandées", "Рекомендуемые пропитки", "推荐灌注", "Infusões recomendadas", "Zalecane nasycenia", "Önerilen aşılamalar", "Infusiones recomendadas", "Infusioni consigliate", "추천 주입", "おすすめインフュージョン", "推薦灌注", "Doporučené infuze"],
        "infusionNow" => ["Infusions now", "Aktuelle Infusionen", "Infusions actuelles", "Пропитки сейчас", "当前灌注", "Infusões atuais", "Obecne nasycenia", "Mevcut aşılamalar", "Infusiones actuales", "Infusioni attuali", "현재 주입", "現在のインフュージョン", "目前灌注", "Současné infuze"],
        "infusionItems" => ["{0} — {1} items", "{0} — {1} Gegenstände", "{0} — {1} objets", "{0} — {1}", "{0} — {1} 件", "{0} — {1} itens", "{0} — {1} przedm.", "{0} — {1} eşya", "{0} — {1} objetos", "{0} — {1} oggetti", "{0} — {1}개", "{0} — {1} 個", "{0} — {1} 件", "{0} — {1} předm."],
        "noInfusions" => ["Infusions: none", "Infusionen: keine", "Infusions : aucune", "Пропитки: нет", "灌注：无", "Infusões: nenhuma", "Nasycenia: brak", "Aşılama: yok", "Infusiones: ninguna", "Infusioni: nessuna", "주입: 없음", "インフュージョン：なし", "灌注：無", "Infuze: žádné"],
        "arsenalShare" => ["In the arsenal it gives {0}% of its attributes:", "Im Arsenal gibt es {0}% seiner Werte:", "Dans l'arsenal, il donne {0} % de ses attributs :", "В арсенале даёт {0}% характеристик:", "在军械库中提供 {0}% 属性：", "No arsenal dá {0}% dos atributos:", "W arsenale daje {0}% atrybutów:", "Cephanelikte özelliklerinin %{0}'ını verir:", "En el arsenal da el {0}% de sus atributos:", "Nell'arsenale dà il {0}% dei suoi attributi:", "무기고에서 능력치의 {0}%를 줍니다:", "アーセナルでは能力値の {0}% を与えます：", "在軍械庫中提供 {0}% 屬性：", "V arzenálu dává {0} % atributů:"],
    ];

    public static function tabName():String return f("tab");
    public static function priorities():String return f("priorities");
    public static function axes():Array<String> return [f("ax0"), f("ax1"), f("ax2"), f("ax3")];
    /** The criticality checkbox under the damage priority. */
    public static function crit():String return f("crit");
    /** Priority names by value: 3 high .. 0 none. */
    public static function levels():Array<String> return [f("lv0"), f("lv1"), f("lv2"), f("lv3")];
    public static function combat():String return f("combat");
    public static function melee():String return f("melee");
    public static function ranged():String return f("ranged");
    public static function calculate():String return f("calculate");
    public static function show():String return f("show");
    public static function result():String return f("result");
    public static function templates():String return f("templates");
    public static function template(i:Int):String return f("template", [i + 1]);
    public static function save():String return f("save");
    public static function resetConfirm():String return f("resetConfirm");
    public static function talents():String return f("talents");
    public static function equipment():String return f("equipment");
    public static function savedTo(i:Int):String return f("savedTo", [i + 1]);
    public static function opened(i:Int):String return f("opened", [i + 1]);
    public static function emptyTemplate(i:Int):String return f("emptyTemplate", [i + 1]);
    public static function noTalents():String return f("noTalents");
    public static function pointsSpent(spent:Int, total:Int):String return f("points", [spent, total]);
    public static function current():String return f("current");
    public static function skillsTitle():String return f("skills");
    public static function resetOne():String return f("resetOne");
    public static function clearedOne(i:Int):String return f("clearedOne", [i + 1]);
    public static function alreadyBest():String return f("alreadyBest");
    public static function changedSlots(n:Int):String return f("changedSlots", [n]);
    public static function sigil():String return f("sigil");
    public static function mainStats():String return f("mainStats");
    public static function otherStats():String return f("otherStats");
    public static function newStats():String return f("newStats");
    public static function nowStats():String return f("nowStats");
    public static function considered(n:Int):String return f("considered", [n]);
    public static function noItems():String return f("noItems");
    public static function craftLabel():String return f("craft");
    public static function dropLabel():String return f("drop");
    /** An item the hero has (bag, mail, bank). */
    public static function ownLabel():String return f("owned");
    public static function improveLabel():String return f("improve");
    public static function infusionOf(name:String):String return f("infusionOf", [name]);
    public static function infusionNone():String return f("infusionNone");
    public static function infusionNoneShort():String return f("none");
    public static function infusionNowWas(name:String):String return f("nowWas", [name]);
    public static function chosenNote():String return f("chosenNote");
    public static function calcTime(ms:Int, builds:Int):String return f("calcTime", [num(Math.round(ms / 100) / 10)]);
    /** The button while the calculation runs (its percent is in the status line under it). */
    public static function calculatingButton():String return f("calculatingButton");
    public static function calculating(p:Int):String return f("calculating", [p]);
    public static function failed():String return f("failed");
    public static function weaponTitle():String return f("weapon");
    public static function arsenalTitle():String return f("arsenal");
    public static function mainWeapon():String return f("mainWeapon");
    public static function offhandWeapon():String return f("offhand");
    public static function arsenalWeapon(x:Float):String return f("arsenalWeapon", [num(x)]);
    public static function totalsLine(dps:Float, dpsNow:Float, self:Float, selfNow:Float, ally:Float, allyNow:Float):String
        return f("totals", [r(dps), r(dpsNow), r(self), r(selfNow), r(ally), r(allyNow)]);
    public static function infusionRecommended():String return f("infusionRecommended");
    public static function infusionNow():String return f("infusionNow");
    /** "name — n items" (Russian: the word agrees with the number). */
    public static function infusionItems(name:String, n:Int):String return f("infusionItems", [name, russian ? n + " " + things(n) : Std.string(n)]);
    public static function noInfusions():String return f("noInfusions");
    public static function arsenalShare(p:Int):String return f("arsenalShare", [p]);

    static function r(v:Float):String return Std.string(Math.round(v));
    /** A decimal number with the comma of the languages that write it so. */
    static function num(v:Float):String {
        var s = Std.string(v);
        return ["en", "zh", "ko", "ja", "zh-TW"].indexOf(LANGS[lang]) >= 0 ? s : StringTools.replace(s, ".", ",");
    }
    static function things(n:Int):String return n % 10 == 1 && n % 100 != 11 ? "предмет" : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20) ? "предмета" : "предметов");
}
