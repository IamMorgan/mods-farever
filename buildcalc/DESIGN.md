# Калькулятор билда — ТЗ и находки в коде игры

Документ для разработчика (ассистента). Правила пользователя те же, что в `C:\mods\teleport\README.md`:
общение по-русски, без явной команды ничего не коммитить и не пушить, сначала диагностика, потом правка.

## Что делает мод

1. **Анкета**: четыре оси — Урон, Защита, Здоровье, Лечение. У каждой приоритет:
   Высокий (вес 3), Средний (2), Низкий (1), Не важно (0). Плюс выбор **«Ближний бой» / «Дальний бой»**:
   основное оружие подбирается только этого типа.
2. **Два варианта билда**:
   - **Идеальный** — из всех предметов, которые есть в игре (данные `Data.item`, только вещи класса героя);
   - **Из своих вещей** — надетое + сумка + склад.
3. В каждом варианте мод подбирает: экипировку по слотам, оружие, таланты, пропитки (комбинацию по
   слотам), камни/усиления в слоты, уровень улучшения. Тип урона (криты или нет) мод выбирает сам —
   по тому, что даёт больше ожидаемого урона этому классу.
4. **Интерфейс — своя вкладка «Калькулятор» в окне «Профиль героя»** (рядом с Герой / Навыки класса /
   Таланты / Репутация):
   - слева: ползунки приоритетов четырёх осей и кнопка «Рассчитать», переключатель варианта
     (идеальный / из своих вещей), шаблоны;
   - в центре: дерево талантов как в игре, с талантами, выбранными модом;
   - справа: экипировка, подобранная модом, как в профиле героя (слоты с иконками и подсказками игры,
     оружие основной/второй руки), с пропитками, камнями и улучшениями; итоговые характеристики,
     полоски «% от максимума», разница с надетым.
5. **Шаблоны**: кнопка «Сохранить», 3 слота шаблонов, переключение между ними, кнопка «Сбросить
   шаблоны». Сохранённый шаблон показывается при следующем открытии окна.
   Хранение: `hlx/config/<мод>/templates.json`.

## Ограничения, которые учитывает подбор

- **Очки талантов** ограничены (`HeroSpecialization.getTotalTalentPoints`, у жреца 25 ур. — 16).
  Таланты по ярусам и веткам (корень tier 0, ветки 1–3, ярусы 1–4); ранги — `getTalent(id)`.
- **Зачарование шлема с талантом**: сигилы `AugmentDemonSigil` → Head, по одному на ветку класса
  (таланты 4-го яруса; у жреца DemonSigil_Priest_LuminousBastion / _SolarDevotion / _SunHalo);
  дают талант без очков. Подбор решает, какой талант взять сигилом, а какие — очками.
- **Ближний/дальний бой**: скилл ближнего боя — все шаги не дальше
  `Const.Skills.MeleeSkill_MaxStepRange` (`st.skill.Skill.isMelee`); у набора движений `moveSet`
  есть `props.range` (`ent.Unit.isRanged`); у типа оружия (`Data.itemType`) свой `moveSet`.
- Пропитки: 8 вещей, пороги 2/4/6 (`Item_InfusionCaps`), призматика (`Item_PrismaticChance` 0.1).

## Как считается оценка (согласовано с пользователем)

- По каждой оси сначала ищется **максимум, достижимый из доступных предметов** (для идеального
  варианта — из всех, для своего — из своих). Значение оси комплекта = % от этого максимума.
- Оценка комплекта = Σ (вес оси × % оси). Высокий приоритет дополнительно требует не меньше 80%
  своего максимума; если недостижимо — порог снижается, окно пишет об этом.
- Комплект оценивается **целиком** (не по одной вещи, как Pawn): характеристики считаются по правилам
  игры для всего набора, с пропитками, камнями и улучшениями.
- Урон = ожидаемый урон: учитывает шанс и силу крита, пробивание, мастерство — так мод сам решает,
  выгоден ли крит-билд.

## Находки в коде игры (hlboot.dat, Farever 2026-10-15)

### Пропитки (инфузии)
- Пропитка вещи: `st.item.Gear.infusion` (id). Виды: скиллы `Infusion_<Фракция>_<Роль>` —
  фракции Bee, Crimson, Kobold, Manfish, Nightling; роли DPS, Tank, Support. Эффекты — скрипты
  (`script.skills.Infusion_*`), не простые характеристики.
- Число вещей с пропиткой: `Hero.refreshInfusions` → `infusionStacks[id]`.
- Ранг: `HInfusion.getRankFromStacks(n)` = сколько порогов `Const.Items.Item_InfusionCaps` набрано
  (по словам пользователя 2/4/6 → ранги 1/2/3). Слотов под пропитку — 8.
- Комбинации по 8 слотам: 3×2+2, 4+4, 4+2+2, 2+2+2+2, 6+2 и т.д. — перебирать все.
- **Бонус пропитки на вещи**: `Gear.infusionBonusStat` — случайная характеристика (при создании,
  `HInfusion.pickInfusionBonusStat`, из `UnitAttributes.infusionBonusAttributes`, кроме группы 3).
  Величина: `round(Item_InfusionBonusRatio × масштаб аптитуды InfusionBonus по iLevel)`, тип
  `TAttribute_Flat` (`Gear.getInfusionBonusAffix`).
- **Активен** (`Gear.isInfusionBonusActive`): если у экземпляра вещи флаг 2 (призматическая,
  шанс `Item_PrismaticChance`) — всегда; иначе только если фракция пропитки
  (`HInfusion.getInfusionFaction`) == фракция происхождения вещи (`HItem.getFactionOrigin`).
- Совместимость: `HInfusion.checkGearInfusionCompatibility`, `canBeInfused`, стоимость
  `getInfusionCost`, `Item_InfusionCost`, `getInfusionPattern` (выкройки фракций).

### Камни / усиления в слотах, улучшение
- `Gear.slots` + `slotAugment` / `applyAugment` / `isConflictingAugmentType`: предметы-усиления
  вставляются в слоты вещи; их аффиксы — `Gear.getSlotAffixes` (с `Item_FlawlessSlotMRatio`).
- Улучшение: `Gear.upgradeLevel`, максимум `rarity.props.gearUpgrades` (`getMaxUpgradeLevel`),
  стоимость `getUpgradeCost` (`Const.Items.GearUpgrades.Materials`), уровень вещи растёт:
  `getILevel = база + upgradeLevel × Item_GearUpgradeILevelBonus`.

### Аффиксы и характеристики
- Все аффиксы вещи: `Gear.getAffixes` = базовые + слоты + бонус пропитки (если активен).
- Значение атрибута на клиенте (`ent.Unit.atb`):
  `(сохранённое + getAtbScaling(уровень) + atbValFlat) × atbValModAdd × atbValModMul`,
  флаг 2048 → ceil, флаг 128 → не ниже 0. Аффиксы: `TAttribute_Flat`, `_ARatio`, `_MRatio`,
  `_MRatioMin`; сумма через `GameObject.getAfxVal`.
- Атрибуты (`ent.UnitAttributes`): vitality, strength, dexterity, faith, intellect, critChanceRating →
  critChance, critDamage, armorPenetration(Rating), spellPenetration(Rating), fervor(Rating),
  blockMitigation, dodgeChance, magicMastery, physicalMastery, cooldownReduction, armor, magicArmor,
  magicReduction, maxHealth, healthRegen, damage, heal, … Рейтинг → значение: `AttributeOperator.Rating`.
- Масштаб по уровню вещи: `HItem.computeAtbScaling`, `HAttributes.getAtbLevelScaling`.

### Производные характеристики (рейтинги → шансы)
- Каждая характеристика в `Data.attribute` имеет список `scaling`: {attribute, scale, scalingOperator}.
  `ent.Unit.getAtbScaling` складывает их: `Linear` → `scale × значение`; `Rating` — убывающая
  отдача (`… 1/(1 + значение × scale …)`, точная формула в f4880); третий оператор — по уровню
  (`getEffectiveLevel`). Так из critChanceRating получается critChance и т.п. — всё из данных.

### Урон и лечение скилла
- Подсказка игры: `HText.skillEffectValText` → `HSkill.getStepEffectBaseVal` (база шага по рангу) +
  `HSkill.getStepEffectScaling` / `GameObject.flattenAtbScaling` (Σ характеристика × ratio шага),
  × `getDamageRatio(стихия)`; лечение × `getHealGivenMultiplier`, щит × `getShieldPowerMultiplier`.
  Есть и `HSkill.getStepEffectVal`.
- Удар в бою (`Unit.computeDamage`, `BaseSkill.calcDamageAmount`): (amount + dmgAdd) × dmgMult ×
  physical/magicDmgMult × critDmgMult (если крит) × сопротивление стихии цели × получаемый целью урон ×
  броня цели × блок. Крит: `HitData.criticalRoll` (Math.random против шанса).
- Ожидаемый урон для оценки: урон по формуле подсказки × (1 + шанс крита × (critDamage − 1)) ×
  пробивание против типичной брони цели.

### Проверено пробой (жрец 25 ур., 2026-10-16)
- Формулы характеристик данных совпали с игрой: CritChance = (Ловкость + Вера) × 0.014 + рейтинг
  крита / scale(уровень) × 20 → 17.49% при Ловк. 28, Вере 176, рейтинге 183.
- Оператор `scalingOperator`: `[0]` — линейно (`scale × значение`); `[2, a, b, c]` — рейтинг:
  `значение / HAttributes.getAtbLevelScaling(atb, уровень, a, b) × c`,
  где масштаб = `a × (b/a)^((уровень−1)/(Const.Attributes.LevelScalingFormula_EarlyMaxLevel−1))`
  (функцию можно вызывать из мода напрямую, ref-параметры необязательны).
- Флаг атрибута 4 → значение × 0.01 (проценты), 2048 → ceil, 128 → не ниже 0.
- Fervor (рвение) даёт HealGivenMultiplier и ShieldPowerMultiplier (+1 × Fervor) и снижает
  DamageTakenModifier (−0.5 × Fervor); MaxHealth = Живучесть × 3; MaxPoise = MaxHealth × 0.6.
- Камни: «демонические усиления» `DemonGearUpgradeRare_<A>To<B>` (тип AugmentDemon) — переводят
  характеристику вещи A в B.
- Классы вещей: `st.item.Gear`, `st.item.Armor`, `st.item.Weapon` (у оружия `rarity`, `effects` —
  бонусы оружия); есть `st.item.Mastery` (мастерства скиллов).
- Склад (`loadout.banks`) пуст даже после открытия склада — мод будет запоминать содержимое склада,
  пока окно склада открыто (найти окно склада и его инвентари на этапе 3).
- Пропитки читаются: `Hero.getInfusionStacks/getInfusionRank(id)`, `HInfusion.getInfusionFaction`
  (Nightling → фракция Demon). Таланты: `HeroSpecialization.getTalent(id)`, `skill.props.talent.maxPoints`.
- Каталог усилений (`ItemType.props.augmentTargets`): AugmentBlacksmith → Chest, AugmentJeweller →
  GearFinger/GearNeck, AugmentOutfitter → Back, AugmentEnchantFeet/Hands → Feet/Hands (характеристики),
  AugmentEnchantWeapon → MainhandWeapon (скиллы Enchant_*), AugmentDemon → Weapon (перевод A→B ±20/±40),
  AugmentDemonSigil → Head (таланты).

### Окно профиля героя
- `ui.win.CharacterUI` (наследник `ui.win.TitleWindow`), вкладки — enum `ui.win.CharacterTab`
  (Character, Apperance, Skills, Talents, Reputation), но механизм вкладок общий: `TitleWindow.tabs` —
  массив `{key:dyn, name, onTabClick, getSelected, checkEnable, getTip, getNoReason}`,
  `setTab(key)` → `BaseWindow.rebuild`, содержимое — `titleWindowContent`.
- Окно приводит ключ к enum (`getTab` = SafeCast, `getTabClass` = Type.enumConstructor) — ключ другого
  типа уронит игру. Значение `CharacterTab.Apperance` игра не использует (внешний вид — флаг
  `apperanceMode`), поэтому оно — ключ вкладки калькулятора (`BuildTab.hx`): копия описания вкладки
  (`Reflect.copy`) с этим ключом добавляется после `initTabs`, панель рисуется после `init`.

### Таланты и оружие
- Деревья: `Data.unit[класс].talentTrees` (`talents`, `branch`), таланты — скиллы с `props.talent`.
- Ранги героя: `st.player.HeroSpecialization` (`getTalent`, `getTalentPoints`,
  `getTotalTalentPoints`, `setTalentRank` — RPC на сервер, мод не вызывает).
- Многие таланты — скрипты (`script.skills.<Класс>_Talent_*`): их числа надо брать из данных скилла,
  а не из характеристик.
- Скиллы оружия: `Gear.getSkills(hero)`, `canGiveSlotSkills`.

### Инвентарь и склад
- `ent.Hero.loadout` (`st.Loadout`): `inventory`, `equipment`, `banks`.
- Надетое: `Hero.get_equipment().content`, сумка: `Hero.get_inventory().content`.
- Склад: `loadout.banks` (так игра сама берёт материалы для пропитки — `HInfusion.getCostInventories`),
  значит, содержимое склада на клиенте есть.
- Элемент содержимого: `{item: st.Item}`; экипировка — `st.item.Gear`.
- Вещи «из мира» для идеального варианта: `st.Item.create(id, drop)` (так мод codexloot строит
  подсказки), затем выставить пропитку/улучшение у копии — сервер это не трогает.

## Риски и открытые вопросы

1. Эффекты пропиток и многих талантов — скрипты (проки, щиты, DoT). Точные числа берём из данных
   скиллов; то, что зависит от боя (частота проков), считаем по допущениям и подписываем в окне.
2. Формула урона скиллов (коэффициенты оружия/скиллов, мастерство, пробивание) — следующий этап
   исследования.
3. Идеальный вариант: бонус пропитки у вещи случайный — в идеале берём лучший возможный и помечаем.
4. Полный перебор слишком большой: отбор кандидатов по слоту + локальное улучшение комплекта,
   отдельный точный перебор комбинаций пропиток по 8 слотам.

## Этапы

1. ✅ Исследование кода игры (этот документ).
2. ✅ Проба данных (была `Probe.hx`, хоткей F9; удалена, результаты выше): сверка модели с игрой —
   характеристики героя, формулы `scaling`, аффиксы вещей, слоты, пропитки, склад, таланты.
3. Движок характеристик по данным (с тестами): аффиксы → характеристики → оси оценки.
4. Оптимизатор: кандидаты по слотам, комбинации пропиток по 8 слотам, камни, улучшения, таланты.
5. Интерфейс: анкета, окно результата (2 варианта), 3 шаблона, сброс.

## Состояние (2026-10-17)

- Вкладка «Калькулятор» в профиле героя: анкета, шаблоны (3, сброс у каждого), дерево талантов,
  умения с рунами, экипировка; подсказки игры на всех иконках (`ui.UIElement.set_getTip/set_textTip`;
  `ui.Tooltip.fromSkill/fromItem` и `HText.skillMastery` ждут запись «скилл героя»
  `{inf, rank, maxRank, masteries, heroic}`, массивы — только динамические, т.к. игра делает deepCopy).
- Расчёт v1 (`StatEngine`, `Scoring`, `Optimizer`): только экипировка из своих вещей (надето + сумка).
  Броня: `A / (A + F0 + F1 × уровень)`, F = `Const.Attributes.ResistanceScalableReductionFormula`
  (из `GameObject.getAffinityDamageReduction`); итоговый урон × `DamageTakenModifier`.
- Дальше: таланты (очки + сигил), руны, пропитки (2/4/6 по 8 слотам, призматика), камни/зачарования,
  улучшения, склад, идеальный вариант, порядок умений по вкладу.

## Находки 2026-10-17 (расчёт v2: весь билд)

- **Данные игры офлайн**: `data.cdb` лежит в `res.light.pak` (формат PAK heaps: заголовок `PAK`, версия,
  размер заголовка, дерево файлов: имя, флаги (1 = папка, 2 = позиция double), позиция, размер, контрольная
  сумма). Русские тексты — `lang/export_ru.xml` там же. Скрипт извлечения — в scratchpad (`pak.py`).
- **Пропитать можно только эпические вещи** (`Const.Item_InfusionMinRarity = Epic`, `HInfusion.canBeInfused`).
- **Эпические вещи** — из героических таблиц боссов (`unit.props.heroicLootTable`, напр. `Crabgantua_HM`) и
  контейнеров (`HM_Gear_Cache_25` → `props.gainItem.lootTable`). Кодекс (`zones[].items`) их не перечисляет:
  доступность теперь = монстры зон Кодекса (`zones[].units`) со всеми их таблицами + рецепты + мировой лут
  + вещи героя. `Маска добродетели` = `Head_ECrimson_Cle` из `Phrixes_HM`.
- **Ошибка v1**: тип предметов отбрасывался целиком, если первый предмет типа недоступен → в пуле не было
  шлемов, плеч, нагрудников и т.д.; надетые вещи не участвовали → «подобранное» было хуже надетого.
- **Таланты**: корень обязателен; талант яруса t требует в ветке (с корнем) на ярусах ниже ≥
  `Const.Hero.Talents_TierThresholds[t]` = 0,1,2,4,8 очков (`HeroSpecialization.implInlineSetTalentRank`).
- **Аффиксы**: `TAttribute_Flat` (+), `_ARatio` (val — доля, складывается в ModAdd = 1 + Σ), `_MRatio` (val —
  множитель, перемножается); `ent.Unit.atb = (stored + scaling + flat) × ModAdd × ModMul`.
- **Перезарядка**: `КД × max(0, 1 − CooldownReduction)` (`GameObject.getCooldownModifier`).
- **Скейлинг умений** (`HSkill.getStepEffectScaling`): `AllAttributes` = среднее атрибутов с флагом 8192;
  `WeaponPower` у умений оружия = среднее statGroup-0 атрибутов аптитуд оружия; для умений вещи доля
  `WeaponPowerRatio` (основное оружие 0.4, аксессуар 1) заменяется силой самой вещи
  (`getStepEffectItemScaling`), у атрибутов с флагом 512 остаётся (1 − доля).
- **Ранг умений оружия** — прогресс игрока (`st.player.Progress.getSkillRank`).
- **Руны**: шаги умений с `cond.mastery`, переопределения `mastery.props.cooldown/duration`, `vars`; руна
  одна на умение (две с `Const.Hero.UnlockLevel_SecondMastery` = 50). Слоты умений оружия —
  `Const.Hero.UnlockLevel_WeaponSkillSlots`.
- **Статусы-баффы**: шаг с `props.status.ref` → навык-статус с `duration` и `affixes` (учёт × доля времени).
- **Скрипты** (таланты, пропитки): разбор текста — модификаторы в `…Eval` (dmgMult, critChance, critDmgMult,
  armorIgnore), процы (`playStep/chainStep/addStatus`, `checkProba(vars.X)`), условия блока `rank >= N`,
  `hasMastery`, `hasSkill`; закомментированный код не считается. Что не разобрано — пишется в лог как
  «not valued».

## Находки 2026-10-17 (v3)

- **Множитель урона** (`GameObject.getDamageRatio`, `SkillContext.initVars`): `(1 + Мастерство(физ/маг) + Рвение)
  × DamageModifier`; крит: `CritChance`, `CritDamage`; у DoT/HoT-статусов крита нет (`HSkill.isDoT/isHoT`).
  Лечение × `HealGivenMultiplier` (= 1 + Рвение), щиты × `ShieldPowerMultiplier`.
- **Шаги с циклом**: флаг `SpreadEffects` (loop.flags bit 0) — значение делится на тики
  (`HSkill.getStepEffectVal`), иначе каждый тик полный.
- **Цепочка атак**: `Data.moveSet.comboLength` ударов (у скипетра/посоха 4), последний — AttackCombo.
- **Молитвы жреца** (и любые навыки с `chargePrayer()/addCharges()` в скрипте) применяются столько раз,
  сколько срабатывает их событие (`PriestComponent.chargePrayer`), а не по откату 1 с.
- **Улучшать можно только оружие** (`ui.win.GearUpgrade` принимает только `st.item.Weapon`).
- **Арсенал**: зачарования оружия арсенала тоже дают умения (`Gear.getSkills`); одно умение у героя — одно.
- **Отрицательные значения** характеристик игра оставляет только с флагом 128, иначе 0 (`ent.Unit.atb`).
- **Цели**: броня, магическая броня и здоровье берутся у врагов рядом с героем (`GameApp.inst.units`,
  ±5 уровней); если их нет — ожидаемая броня `Armor_ExpectedReduction`. Убийства в секунду = ДПС / здоровье.
- Расчёт идёт порциями по ~6 мс за кадр (`Optimizer.run`), игра не замирает.

## Находки 2026-10-17 (v4)

- **Счётчик боя игры**: `hero.combatStats.damages` — все `st.skill.DamageResult` героя (урон, лечение, щиты:
  умение `ctx.skill.inf.id`, `get_amount`, `target`, `_critical`, `effect`); прошлые бои —
  `combatDamageHistory[] {duration, damages}`. Мод калибрует ДПС и лечение по последнему бою (манекен):
  измеренное в секунду по каждому умению × (модель в новом билде / модель сейчас).
- **Арсенал**: выбирается `ent.Hero.getNbArsenalSkillSlots` умений из «умений оружия» и «пассивок оружия»
  (`st.item.Weapon.isValidArsenalSkill`); текущий выбор — `HeroSpecialization.getArsenalSkills(itemId)`.
  Пассивка арсенального оружия действует, только если выбрана.
- **Защита** (`GameObject.getAffinityDamageReduction`, `Data.affinity`): физический урон режет `Armor`,
  магический — `MagicArmor` и `MagicReduction`; дальше `Resilience`, `DamageTakenModifier`, `DodgeChance`.
- Карта использования характеристик в коде игры — `atbuse.py` в scratchpad (какая функция читает какую).
