-------------------------------------------------------------------------------
--  MacroCoach
--  Готовые популярные макросы WoW Forever для всех классов. У каждого есть
--  описание и текст, где заклинания записаны по ID. «Добавить» создаёт (или
--  обновляет) макрос и кладёт его на курсор: остаётся щёлкнуть по ячейке панели.
--  «Изменить»: свой текст, название и значок (исходный можно вернуть).
--  «Свои макросы»: конструктор по строкам, правка текстом, шаблоны и гайд.
--  «Помощник» (Helper.lua): зачем макросы и проверка. У класса первая вкладка -
--  «Рекомендации»: самые полезные макросы для старта и зачем каждый.
--  Карточка макроса: картинка «Было -> Макрос», зачем он, значки пометок
--  «Новичку», «Продвинутый», «PvP» (HelperData.lua). Текст макроса скрыт:
--  значок-записка на карточке показывает текст макроса. Свой
--  макрос можно предложить автору аддона.
--  Тексты интерфейса пишутся по-русски и проходят через T() (Locale.lua).
--  Открыть: /coach, /макросы, кнопка у миникарты, «Настройки → Модификации»
--  или вкладка «Готовые макросы» справа на окне /macro.
-------------------------------------------------------------------------------
local ADDON, ns = ...
local T = ns.T
-- Вкладки справа: «Помощник» сверху, дальше «Для всех классов», классы
-- и «Свои макросы».
tinsert(ns.CLASS_ORDER, 1, "HELPER")
ns.MACROS.HELPER = ns.MACROS.HELPER or {}
tinsert(ns.CLASS_ORDER, "CUSTOM")
ns.MACROS.CUSTOM = ns.MACROS.CUSTOM or {}
-- «Настройки» - не вкладка справа, а кнопка-шестерёнка у крестика окна.
ns.MACROS.OPTIONS = ns.MACROS.OPTIONS or {}

-------------------------------------------------------------------------------
--  Общий стиль EasyCraft и MacroCoach: одни и те же значения в обоих аддонах.
--  Отступы - с шагом 4. Кнопки - двух высот. Цвета состояний - по одному.
-------------------------------------------------------------------------------
ns.S = {
    pad = 16,      -- поле карточки: от рамки до текста
    gap = 12,      -- между карточками
    edge = 10,     -- от края страницы до карточки
    s1 = 4, s2 = 8, s3 = 12, s4 = 16, s5 = 24, -- шкала отступов
    btn = 22,      -- высота обычной кнопки
    btnBig = 26,   -- высота главной кнопки
    btnMin = 110,  -- кнопка не уже этого; шире - по тексту (+30)
    GREEN = "|cff33dd33", RED = "|cffff5555", YELLOW = "|cffffd100", GREY = "|cff9d9d9d",
}
local WIDTH, HEIGHT = 680, 670
local PAGE_W = WIDTH - 16 -- ширина пергамента внутри рамки
local ATTIC = 64 -- от верха окна до пергамента: заголовок и вкладки специализаций
local CELLAR = 34 -- от пергамента до низа окна: поиск по всем макросам
local TAB_H = 40 -- высота вкладки специализации
local QUESTION = 134400 -- значок «?»
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_01" -- если значок не из чего взять
-- значок аддона: список модификаций, портрет окна, кнопка у миникарты
local ADDON_ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Icon"
ns.ICON = ADDON_ICON
local MAX_CHARS = 255

local frame, current, editor
local pages = {}
local SetMinimapHidden -- объявлена ниже

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Macro|r|cffffd100Coach:|r " .. msg)
end

-------------------------------------------------------------------------------
--  Сохранённые настройки
-------------------------------------------------------------------------------
local function DB()
    MacroCoachDB = MacroCoachDB or {}
    local db = MacroCoachDB
    db.minimap = db.minimap or { hide = false, angle = 200 }
    db.edits = db.edits or {}
    db.barNames = db.barNames or {}
    db.helper = db.helper or {}
    return db
end

-------------------------------------------------------------------------------
--  Очередь «после боя»: в бою игра не даёт создавать и менять макросы и
--  панели, поэтому такие действия выполняются сразу после боя.
-------------------------------------------------------------------------------
local afterCombat, afterOrder = {}, {}
local function AfterCombat(key, fn)
    if not afterCombat[key] then afterOrder[#afterOrder + 1] = key end
    afterCombat[key] = fn
end
local combatWatch = CreateFrame("Frame")
combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatch:SetScript("OnEvent", function()
    if #afterOrder == 0 then return end
    C_Timer.After(0.2, function()
        if InCombatLockdown() then return end
        local order, fns = afterOrder, afterCombat
        afterCombat, afterOrder = {}, {}
        for _, key in ipairs(order) do
            if fns[key] then xpcall(fns[key], geterrorhandler and geterrorhandler() or print) end
        end
    end)
end)

-------------------------------------------------------------------------------
--  Конструктор своих макросов: модель
--  Макрос = строки; строка = тип команды и варианты «[условия] заклинание».
--  Несколько вариантов пишутся через «; » - сработает первый подходящий.
--  macro = { name, desc, icon, tooltip = bool, lines = { line, ... } }
--  line  = { kind = "cast", variants = { variant, ... }, reset = "", chan = "say" }
--  variant = { arg = "{s:ID}", target = "mouseover", conds = { help = 1, dead = 2 },
--              stance = "", extra = "" }   (1 - «да», 2 - «нет»)
-------------------------------------------------------------------------------
local B = {}
ns.Builder = B

B.KINDS = {
    { group = "Заклинания и предметы" },
    { key = "cast", cmd = "/cast", label = "Применить заклинание", arg = "spell", multi = true, conds = true,
      ph = "Перетащи заклинание сюда или впиши {ID}",
      desc = "Применяет заклинание. Можно добавить варианты «иначе»: сработает первый, чьи условия выполнены." },
    { key = "stopcasting", cmd = "/stopcasting", label = "Прервать применение", conds = true,
      desc = "Обрывает твоё текущее заклинание. Ставь перед прерыванием, чтобы оно сработало сразу." },
    { key = "castsequence", cmd = "/castsequence", label = "Последовательность заклинаний", arg = "spells", conds = true, reset = true,
      ph = "Перетащи заклинания: {ID}, {ID}",
      desc = "Каждое нажатие применяет следующее заклинание из списка. «Сброс» - когда начинать сначала: через сколько секунд, при смене цели (target) или после боя (combat)." },
    { key = "use", cmd = "/use", label = "Использовать предмет / слот", arg = "spell", multi = true, conds = true,
      ph = "Предмет, item:ID или слот (13, 14)",
      desc = "Использует предмет по названию или ID (item:ID), ячейку экипировки (13 и 14 это аксессуары). Предмет можно перетащить из сумки." },
    { key = "cancelaura", cmd = "/cancelaura", label = "Снять бафф", arg = "spell", conds = true, ph = "Перетащи заклинание или впиши {ID}",
      desc = "Снимает с тебя бафф, например Ледяную глыбу или Божественный щит." },
    { key = "cancelform", cmd = "/cancelform", label = "Выйти из облика", conds = true,
      desc = "Выходит из облика: облики друида, Призрачный волк, Облик Тьмы и т. п." },
    { key = "castrandom", cmd = "/castrandom", label = "Случайное заклинание", arg = "spells", conds = true, ph = "Перетащи заклинания: {ID}, {ID}",
      desc = "Применяет случайное заклинание из списка." },
    { key = "userandom", cmd = "/userandom", label = "Случайный предмет", arg = "spells", conds = true, ph = "Предметы через запятую",
      desc = "Использует случайный предмет из списка, например транспорт." },
    { key = "stopspelltarget", cmd = "/stopspelltarget", label = "Отменить выбор цели", conds = true,
      desc = "Отменяет заклинание, которое ждёт выбора цели (светящаяся рука или круг на земле)." },

    { group = "Бой и питомец" },
    { key = "startattack", cmd = "/startattack", label = "Начать атаку", conds = true,
      desc = "Включает автоатаку (ближний бой или жезл) по цели. Повторное нажатие её не выключает." },
    { key = "stopattack", cmd = "/stopattack", label = "Остановить атаку", conds = true,
      desc = "Выключает автоатаку, например чтобы не разбудить цель под контролем." },
    { key = "petattack", cmd = "/petattack", label = "Питомец: атака", conds = true,
      desc = "Питомец атакует твою цель (или выбранную в «На кого»)." },
    { key = "petfollow", cmd = "/petfollow", label = "Питомец: за мной", conds = true, desc = "Питомец бросает всё и идёт за тобой." },
    { key = "petstay", cmd = "/petstay", label = "Питомец: стоять", conds = true, desc = "Питомец остаётся на месте." },
    { key = "petmoveto", cmd = "/petmoveto", label = "Питомец: переместиться", conds = true,
      desc = "Питомец идёт в точку. В «На кого» выбери «В точку под курсором»." },
    { key = "petpassive", cmd = "/petpassive", label = "Питомец: пассивный", conds = true, desc = "Питомец сам никого не атакует." },
    { key = "petdefensive", cmd = "/petdefensive", label = "Питомец: защита", conds = true, desc = "Питомец атакует тех, кто атакует тебя или его." },
    { key = "petaggressive", cmd = "/petaggressive", label = "Питомец: агрессивный", conds = true, desc = "Питомец атакует всех врагов рядом." },
    { key = "petautocaston", cmd = "/petautocaston", label = "Питомец: включить автоприменение", arg = "spell", conds = true, ph = "Способность питомца: {ID}",
      desc = "Включает автоприменение способности питомца." },
    { key = "petautocastoff", cmd = "/petautocastoff", label = "Питомец: выключить автоприменение", arg = "spell", conds = true, ph = "Способность питомца: {ID}",
      desc = "Выключает автоприменение способности питомца." },
    { key = "petautocasttoggle", cmd = "/petautocasttoggle", label = "Питомец: переключить автоприменение", arg = "spell", conds = true, ph = "Способность питомца: {ID}",
      desc = "Включает или выключает автоприменение способности питомца." },

    { group = "Выбор цели" },
    { key = "target", cmd = "/target", label = "Цель", arg = "unit", conds = true, ph = "Имя (пусто: берётся из «На кого»)",
      desc = "Выбирает цель по имени или ту, что в «На кого», например под курсором." },
    { key = "targetexact", cmd = "/targetexact", label = "Выбрать цель по точному имени", arg = "unit", conds = true, ph = "Точное имя",
      desc = "Выбирает цель только с точно таким именем. Удобно искать редких мобов." },
    { key = "targetenemy", cmd = "/targetenemy", label = "Ближайший противник", conds = true, desc = "Выбирает ближайшего врага, как Tab." },
    { key = "targetenemyplayer", cmd = "/targetenemyplayer", label = "Ближайший вражеский игрок", conds = true, desc = "Выбирает ближайшего вражеского игрока." },
    { key = "targetfriend", cmd = "/targetfriend", label = "Ближайший союзник", conds = true, desc = "Выбирает ближайшего союзника." },
    { key = "targetfriendplayer", cmd = "/targetfriendplayer", label = "Ближайший дружественный игрок", conds = true, desc = "Выбирает ближайшего дружественного игрока." },
    { key = "targetparty", cmd = "/targetparty", label = "Выбрать участника группы", conds = true, desc = "Перебирает участников группы." },
    { key = "targetraid", cmd = "/targetraid", label = "Выбрать участника рейда", conds = true, desc = "Перебирает участников рейда." },
    { key = "targetlasttarget", cmd = "/targetlasttarget", label = "Предыдущая цель", conds = true, desc = "Возвращает прошлую цель." },
    { key = "targetlastenemy", cmd = "/targetlastenemy", label = "Последний противник", conds = true, desc = "Выбирает последнего врага, который был целью." },
    { key = "targetlastfriend", cmd = "/targetlastfriend", label = "Последний союзник", conds = true, desc = "Выбирает последнего союзника, который был целью." },
    { key = "cleartarget", cmd = "/cleartarget", label = "Сбросить цель", conds = true,
      desc = "Убирает цель. Например, только мёртвую: условие «мёртв: да»." },
    { key = "assist", cmd = "/assist", label = "Помощь", arg = "unit", conds = true, ph = "Имя (пусто: берётся из «На кого»)",
      desc = "Берёт цель другого игрока, например танка." },
    { key = "focus", cmd = "/focus", label = "Задать фокус", arg = "unit", conds = true, ph = "Имя (пусто: берётся из «На кого»)",
      desc = "Запоминает цель как фокус, чтобы потом применять по ней заклинания (в «На кого» выбери «Фокус»)." },
    { key = "clearfocus", cmd = "/clearfocus", label = "Сбросить фокус", conds = true, desc = "Убирает фокус." },
    { key = "targetmarker", cmd = "/tm", label = "Рейдовая метка", arg = "text", ph = "Номер 1-8",
      desc = "Ставит метку на цель: 1 звезда, 2 круг, 3 ромб, 4 треугольник, 5 луна, 6 квадрат, 7 крест, 8 череп." },
    { key = "follow", cmd = "/follow", label = "Следовать", arg = "unit", conds = true, ph = "Имя (пусто: берётся из «На кого»)",
      desc = "Автоматически следует за игроком." },

    { group = "Панели команд и прочее" },
    { key = "changeactionbar", cmd = "/changeactionbar", label = "Сменить страницу панели команд", arg = "text", conds = true, ph = "Страница 1-6",
      desc = "Переключает главную панель на другую страницу (как Shift+1-6)." },
    { key = "swapactionbar", cmd = "/swapactionbar", label = "Переключать две страницы панели", arg = "text", conds = true, ph = "Две страницы, например 1 2",
      desc = "Переключает главную панель между двумя страницами." },
    { key = "click", cmd = "/click", label = "Нажать кнопку", arg = "text", conds = true, ph = "Имя кнопки, например MultiBarRightButton1",
      desc = "Нажимает другую кнопку интерфейса по её имени." },
    { key = "equip", cmd = "/equip", label = "Надеть предмет", arg = "text", conds = true, ph = "item:ID или перетащи предмет",
      desc = "Надевает предмет в его обычную ячейку. В бою можно менять только оружие." },
    { key = "equipslot", cmd = "/equipslot", label = "Надеть в слот", arg = "text", conds = true, ph = "Слот и предмет, например 16 item:ID",
      desc = "Надевает предмет в нужную ячейку: 16 правая рука, 17 левая, 18 дальний бой, 13 и 14 аксессуары." },
    { key = "dismount", cmd = "/dismount", label = "Спешиться", conds = true, desc = "Слезает с транспорта." },
    { key = "stopmacro", cmd = "/stopmacro", label = "Остановить макрос здесь", conds = true,
      desc = "Если условия выполнены, строки ниже не выполняются." },
    { key = "chat", cmd = "/say", label = "Сообщение в чат", arg = "text", ph = "Текст (%t = имя цели)",
      desc = "Пишет в чат. %t заменяется именем твоей цели." },
    { key = "console", cmd = "/console", label = "Настройка консоли", arg = "text", ph = "Настройка и значение, например Sound_EnableSFX 0",
      desc = "Меняет настройку игры (CVar)." },
    { key = "script", cmd = "/run", label = "Скрипт Lua", arg = "text", ph = "Код Lua",
      desc = "Выполняет строку кода Lua. Заклинания и выбор цели скриптом в бою не работают." },
    { key = "raw", cmd = "", label = "Свободная строка", arg = "text", ph = "Любой текст макроса",
      desc = "Любой текст. Сюда попадает всё, что конструктор не понял, так что ничего не теряется." },
}
B.KIND = {}
local BY_CMD = {}
for _, k in ipairs(B.KINDS) do
    if k.key then
        B.KIND[k.key] = k
        if k.cmd ~= "" and k.key ~= "chat" then BY_CMD[k.cmd] = k end
    end
end
BY_CMD["/script"] = B.KIND.script
BY_CMD["/targetmarker"] = B.KIND.targetmarker

B.CHANNELS = {
    { value = "say", label = "Сказать" }, { value = "yell", label = "Крикнуть" }, { value = "party", label = "Группа" },
    { value = "raid", label = "Рейд" }, { value = "rw", label = "Объявление рейду" }, { value = "emote", label = "Эмоция" },
    { value = "guild", label = "Гильдия" },
}
local CHAT_CMD = { ["/s"] = "say", ["/say"] = "say", ["/y"] = "yell", ["/yell"] = "yell", ["/p"] = "party", ["/party"] = "party",
    ["/ra"] = "raid", ["/raid"] = "raid", ["/rw"] = "rw", ["/e"] = "emote", ["/emote"] = "emote", ["/me"] = "emote",
    ["/g"] = "guild", ["/guild"] = "guild" }

B.TARGETS = {
    { value = "", label = "Обычно (текущая цель)" },
    { value = "mouseover", label = "Под курсором (@mouseover)" },
    { value = "target", label = "Цель (@target)" },
    { value = "focus", label = "Фокус (@focus)" },
    { value = "player", label = "На себя (@player)" },
    { value = "targettarget", label = "Цель цели (@targettarget)" },
    { value = "pet", label = "Питомец (@pet)" },
    { value = "pettarget", label = "Цель питомца (@pettarget)" },
    { value = "cursor", label = "В точку под курсором (@cursor)" },
    { value = "party1", label = "1-й в группе (@party1)" },
    { value = "party2", label = "2-й в группе (@party2)" },
    { value = "party3", label = "3-й в группе (@party3)" },
    { value = "party4", label = "4-й в группе (@party4)" },
}

-- Условия «да / нет», в порядке записи.
B.CONDS = {
    { key = "exists", label = "существует", tip = "Цель есть." },
    { key = "help", label = "союзник", tip = "Цель дружественная: её можно лечить." },
    { key = "harm", label = "враг", tip = "Цель можно атаковать." },
    { key = "dead", label = "мёртв", tip = "Цель мертва." },
    { key = "combat", label = "в бою", tip = "Ты в бою." },
    { key = "stealth", label = "в незаметности", tip = "Ты в незаметности." },
    { key = "mounted", label = "верхом", tip = "Ты на транспорте." },
    { key = "channeling", label = "поддерживаю заклинание", tip = "Ты сейчас поддерживаешь заклинание." },
    { key = "pet", label = "есть питомец", tip = "У тебя есть питомец." },
    { key = "group", label = "в группе", tip = "Ты в группе или рейде." },
    { key = "swimming", label = "плыву", tip = "Ты плывёшь." },
    { key = "indoors", label = "в помещении", tip = "Ты в помещении." },
    { key = "outdoors", label = "на улице", tip = "Ты на улице." },
    { key = "mod:shift", label = "зажат Shift", tip = "Зажата клавиша Shift." },
    { key = "mod:ctrl", label = "зажат Ctrl", tip = "Зажата клавиша Ctrl." },
    { key = "mod:alt", label = "зажат Alt", tip = "Зажата клавиша Alt." },
    { key = "btn:2", label = "правая кнопка мыши", tip = "Кнопку на панели нажали правой кнопкой мыши." },
}
local COND_KEY = {}
for _, d in ipairs(B.CONDS) do COND_KEY[d.key] = true end

function B.NewVariant(arg)
    return { arg = arg or "", target = "", conds = {}, stance = "", extra = "" }
end

function B.NewLine(kind, arg)
    if kind == "targetmarker" and not arg then arg = "8" end
    return { kind = kind or "cast", variants = { B.NewVariant(arg) }, reset = "", chan = "say" }
end

function B.New()
    return { name = T("Мой макрос"), desc = "", tooltip = true, lines = { B.NewLine("cast") } }
end

function B.Copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = B.Copy(v) end
    return c
end

-- Модель -> текст (с {s:ID})
function B.Bracket(v)
    local parts = {}
    if v.target and v.target ~= "" then parts[#parts + 1] = "@" .. v.target end
    for _, d in ipairs(B.CONDS) do
        local x = v.conds and v.conds[d.key]
        if x == 1 then
            parts[#parts + 1] = d.key
        elseif x == 2 then
            parts[#parts + 1] = "no" .. d.key
        end
    end
    if v.stance and v.stance ~= "" then parts[#parts + 1] = "stance:" .. v.stance end
    if v.extra and v.extra ~= "" then parts[#parts + 1] = v.extra end
    return #parts > 0 and ("[" .. table.concat(parts, ",") .. "]") or ""
end

function B.LineText(l)
    local k = B.KIND[l.kind] or B.KIND.raw
    local v1 = l.variants[1] or B.NewVariant()
    if k.key == "raw" then return v1.arg or "" end
    if k.key == "chat" then return "/" .. (l.chan or "say") .. " " .. (v1.arg or "") end
    if k.key == "targetmarker" then return "/tm " .. strtrim(v1.arg or "8") end
    local out, last = {}, ""
    for i, v in ipairs(l.variants) do
        if i > 1 and not k.multi then break end
        local seg = k.conds and B.Bracket(v) or ""
        if k.reset and l.reset and l.reset ~= "" then
            seg = (seg ~= "" and seg .. " " or "") .. "reset=" .. l.reset
        end
        local arg = k.arg and strtrim(v.arg or "") or ""
        -- Пустое поле варианта «иначе» - то же заклинание, что выше.
        if arg == "" and i > 1 and k.arg == "spell" then arg = last end
        if arg ~= "" then last = arg end
        if arg ~= "" then seg = (seg ~= "" and seg .. " " or "") .. arg end
        out[#out + 1] = seg
    end
    local rest = table.concat(out, "; ")
    return rest ~= "" and (k.cmd .. " " .. rest) or k.cmd
end

function B.Build(m)
    local lines = {}
    if m.tooltip then
        lines[1] = (m.tooltipSpell and m.tooltipSpell ~= "") and ("#showtooltip " .. m.tooltipSpell) or "#showtooltip"
    end
    for _, l in ipairs(m.lines or {}) do
        local t = B.LineText(l)
        if strtrim(t) ~= "" then lines[#lines + 1] = t end
    end
    return table.concat(lines, "\n")
end

-- Текст -> модель. Строку, которую нельзя собрать обратно буква в букву,
-- конструктор держит как «Свободную строку».
local function Canon(t)
    t = t:gsub("%s+", "")
    return (t:gsub("%[(.-)%]", function(inner)
        local tokens = {}
        for token in inner:gmatch("[^,]+") do tokens[#tokens + 1] = token end
        table.sort(tokens)
        return "[" .. table.concat(tokens, ",") .. "]"
    end))
end

local function ParseVariant(seg, v, k)
    seg = strtrim(seg)
    if seg:sub(1, 1) == "[" then
        local close = seg:find("]", 1, true)
        if not close then return false end
        local inner = seg:sub(2, close - 1)
        seg = strtrim(seg:sub(close + 1))
        if seg:sub(1, 1) == "[" then return false end -- несколько скобок подряд
        local extra = {}
        for token in inner:gmatch("[^,]+") do
            token = strtrim(token)
            local unit = token:match("^@(.+)$") or token:match("^target=(.+)$")
            local neg, name = token:match("^(no)(.+)$")
            if unit then
                v.target = unit
            elseif COND_KEY[token] then
                v.conds[token] = 1
            elseif neg and COND_KEY[name] then
                v.conds[name] = 2
            elseif token:match("^stance:") then
                v.stance = token:sub(8)
            elseif token ~= "" then
                extra[#extra + 1] = token
            end
        end
        v.extra = table.concat(extra, ",")
    end
    v.arg = seg
    return true
end

function B.ParseLine(text)
    local raw = { kind = "raw", variants = { B.NewVariant(text) }, reset = "", chan = "say" }
    local cmd, rest = text:match("^(/%S+)%s*(.*)$")
    if not cmd then return raw end
    local lc = cmd:lower()
    if CHAT_CMD[lc] then
        local l = B.NewLine("chat", rest)
        l.chan = CHAT_CMD[lc]
        return l
    end
    local k = BY_CMD[lc]
    if not k or k.key == "raw" then return raw end
    local line = B.NewLine(k.key)
    if k.key == "targetmarker" then
        line.variants[1].arg = rest
        return Canon(B.LineText(line)) == Canon(text) and line or raw
    end
    line.variants = {}
    local segs = {}
    if k.multi then
        for seg in (rest .. ";"):gmatch("(.-);") do segs[#segs + 1] = seg end
    else
        segs[1] = rest
    end
    for _, seg in ipairs(segs) do
        local v = B.NewVariant()
        if not ParseVariant(seg, v, k) then return raw end
        if k.reset then
            local r, after = v.arg:match("^reset=(%S+)%s*(.*)$")
            if r then line.reset, v.arg = r, after end
        end
        if v.arg ~= "" and not k.arg then return raw end
        if (v.target ~= "" or next(v.conds) or v.stance ~= "" or v.extra ~= "") and not k.conds then return raw end
        line.variants[#line.variants + 1] = v
    end
    if #line.variants == 0 then line.variants[1] = B.NewVariant() end
    if Canon(B.LineText(line)) ~= Canon(text) then return raw end
    return line
end

function B.Parse(body, m)
    m.tooltip, m.tooltipSpell, m.lines = false, nil, {}
    for line in ((body or "") .. "\n"):gmatch("(.-)\n") do
        local t = strtrim(line)
        local tip = t:match("^#[Ss][Hh][Oo][Ww][Tt][Oo][Oo][Ll][Tt][Ii][Pp](.*)$")
        if tip and #m.lines == 0 and not m.tooltip then
            m.tooltip = true
            tip = strtrim(tip)
            if tip ~= "" then m.tooltipSpell = tip end
        elseif t ~= "" then
            m.lines[#m.lines + 1] = B.ParseLine(t)
        end
    end
    return m
end

-- Свои макросы: сохранены в MacroCoachDB.custom для всех персонажей.
local function CustomList()
    local db = DB()
    db.custom = db.custom or {}
    return db.custom
end

-- Свой макрос в том же виде, что и готовый (для карточки и «Добавить»).
local function CustomMacro(entry)
    local desc = entry.desc and entry.desc ~= "" and entry.desc or T("Свой макрос.")
    return { name = entry.name, title = entry.name, desc = desc, body = B.Build(entry), icon = entry.icon,
        prev = entry.prev, custom = true, entry = entry }
end


-- Правки игрока: edits["КЛАСС/имя"] = { name, body, icon, prev }.
local function Key(class, m) return class .. "/" .. m.name end

-- Название, заголовок и описание готового макроса на выбранном языке.
-- В данных они русские, перевод лежит в ns.EN_MACROS["КЛАСС/имя"].
local CLIENT_RU = GetLocale() == "ruRU"
local function Loc(class, m)
    local en = ns.EN_MACROS and ns.EN_MACROS[class .. "/" .. m.name]
    if en and ns.lang ~= "ruRU" then
        local TE = ns.TE
        local name = en.name and TE(en.name) or m.name
        return name, (en.title and TE(en.title)) or (en.name and name) or m.title or m.name, en.desc and TE(en.desc) or m.desc
    end
    -- Русский язык аддона на нерусском клиенте: шрифт панелей не знает
    -- кириллицу (вместо букв квадратики), поэтому название макроса в игре -
    -- английское. Заголовок и описание карточки остаются русскими.
    if en and en.name and not CLIENT_RU then return en.name, m.title or m.name, m.desc end
    return m.name, m.title or m.name, m.desc
end
ns.Loc = Loc

-- Макрос с учётом языка и правок игрока. Для своих макросов m - запись из
-- MacroCoachDB.custom. base - исходный макрос из данных: по его имени
-- находится уже созданный в игре макрос, даже если язык сменили.
local function Effective(class, m)
    if class == "CUSTOM" then return CustomMacro(m) end
    local e = DB().edits[Key(class, m)]
    -- Безопасное лечение и «Alt - на себя» (настройки, Helper.lua).
    local body = (not e and ns.SafeBody) and ns.SafeBody(m.body) or m.body
    if not e and ns.lang == "ruRU" and CLIENT_RU and body == m.body then return m end
    local name, title, desc = Loc(class, m)
    if not e then return { name = name, title = title, desc = desc, body = body, icon = m.icon, best = m.best, scan = m.scan, base = m } end
    -- Старые правки хранят исходное русское имя: это не переименование.
    local renamed = e.name and e.name ~= m.name and e.name ~= name and e.name or nil
    return { name = renamed or name, title = renamed or title, desc = desc,
        body = e.body or (ns.SafeBody and ns.SafeBody(m.body) or m.body), icon = e.icon or m.icon, best = not e.body and m.best or nil, scan = not e.body and m.scan or nil, base = m, prev = e.prev,
        edited = true }
end

-------------------------------------------------------------------------------
--  Текст макроса
-------------------------------------------------------------------------------
-- {s:ID} - название заклинания, {r:ID} - название с рангом.
local function Render(body)
    local missing
    local text = body:gsub("{([sr]):(%d+)}", function(kind, id)
        id = tonumber(id)
        local name = C_Spell.GetSpellName(id)
        if not name then
            missing = true
            return "?"
        end
        if kind == "r" then
            local rank = C_Spell.GetSpellSubtext(id)
            if rank and rank ~= "" then return name .. "(" .. rank .. ")" end
        end
        return name
    end)
    return text, missing
end

-- Вид с ID для окна аддона, без русских слов: {17364} - заклинание,
-- {r:8042} - заклинание именно этого ранга. Игра в /cast принимает только
-- названия, поэтому при добавлении макроса ID заменяются названиями (Render).
local function ToDisplay(body)
    return (body:gsub("{s:(%d+)}", "{%1}"))
end

local function ToStored(text)
    return (text:gsub("{(%d+):ранг}", "{r:%1}"):gsub("{(%d+)}", "{s:%1}"))
end

-- ID в тексте макроса - белым.
local function HighlightIDs(text)
    return (text:gsub("({r:%d+})", "|cffffffff%1|r"):gsub("({%d+})", "|cffffffff%1|r"))
end

-- Длина в символах (буквы кириллицы считаются по одной).
local function CharCount(text)
    return #text:gsub("[\128-\191]", "")
end

local function SpellIDs(body)
    local list, seen = {}, {}
    for kind, id in body:gmatch("{([sr]):(%d+)}") do
        id = tonumber(id)
        if not seen[id] then
            seen[id] = true
            list[#list + 1] = { id = id, rank = kind == "r" }
        end
    end
    return list
end

-- Заклинания макроса. У изменённого - {s:ID} из нового текста и те
-- заклинания исходного, чьи названия в тексте остались.
local function SpellsOf(m)
    local list = SpellIDs(m.body)
    if m.base then
        local seen = {}
        for _, e in ipairs(list) do seen[e.id] = true end
        local text = Render(m.body)
        for _, e in ipairs(SpellIDs(m.base.body)) do
            local name = C_Spell.GetSpellName(e.id)
            if not seen[e.id] and name and text:find(name, 1, true) then
                seen[e.id] = true
                list[#list + 1] = e
            end
        end
    end
    return list
end

local function ItemIDs(body)
    local list, seen = {}, {}
    for id in body:gmatch("item:(%d+)") do
        id = tonumber(id)
        if not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end
    return list
end

local function IDLine(m)
    local items = ItemIDs(m.body)
    if #items > 0 then
        local parts = {}
        for _, id in ipairs(items) do
            local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
            parts[#parts + 1] = ("|cffffffff%d|r %s"):format(id, name or "?")
        end
        return T("ID предметов: ") .. table.concat(parts, ", ")
    end
    local parts = {}
    for _, e in ipairs(SpellsOf(m)) do
        local name = C_Spell.GetSpellName(e.id) or "?"
        if e.rank then
            local r = C_Spell.GetSpellSubtext(e.id)
            if r and r ~= "" then name = name .. " (" .. r .. ")" end
        end
        parts[#parts + 1] = ("|cffffffff%d|r %s"):format(e.id, name)
    end
    if #parts == 0 then
        return m.edited and T("ID заклинаний: нет известных заклинаний в тексте.") or T("Без заклинаний: работает у любого класса.")
    end
    return T("ID заклинаний в WoW Forever: ") .. table.concat(parts, ", ")
end

local function RequestSpells(body)
    if C_Spell.RequestLoadSpellData then
        for _, e in ipairs(SpellIDs(body)) do C_Spell.RequestLoadSpellData(e.id) end
    end
    if C_Item.RequestLoadItemDataByID then
        for _, id in ipairs(ItemIDs(body)) do C_Item.RequestLoadItemDataByID(id) end
    end
end

-- Значок из данных: имя файла из Interface\Icons или ID файла.
local function IconPath(icon)
    if type(icon) == "string" and not icon:find("\\", 1, true) then return "Interface\\Icons\\" .. icon end
    return icon
end

local function SpellIcon(id) return C_Spell.GetSpellTexture(id) end
local function ItemIcon(id) return C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) end

-- Значок макроса: выбранный, иначе заклинание или предмет из #showtooltip,
-- иначе первое заклинание, первый предмет или аксессуар.
local function FirstIcon(m)
    if m.icon then return IconPath(m.icon) end
    local body = m.body or ""
    local tipSpell = body:match("^#showtooltip {[sr]:(%d+)}")
    local tipItem = body:match("^#showtooltip item:(%d+)")
    local icon = (tipSpell and SpellIcon(tonumber(tipSpell))) or (tipItem and ItemIcon(tonumber(tipItem)))
    if icon then return icon end
    local first = SpellsOf(m)[1]
    if first then return SpellIcon(first.id) or QUESTION end
    local item = ItemIDs(body)[1]
    if item then return ItemIcon(item) or QUESTION end
    local slot = body:match("/use (1[34])")
    if slot and GetInventoryItemTexture then return GetInventoryItemTexture("player", tonumber(slot)) or QUESTION end
    return QUESTION
end

-- Еда и питьё: в макросе остаётся одна строка с лучшим предметом, который
-- сейчас есть в сумках (иначе несколько разных предметов съедятся разом).
local function ItemCount(id)
    local f = C_Item.GetItemCount
    local ok, n = pcall(f, id)
    return ok and n or 0
end

-- Макросы-списки («зелье лечения»: лучшее из того, что есть) - тоже умные,
-- но по-своему (best = "show"): все строки /use остаются, чтобы в бою
-- сработал следующий предмет, когда лучший кончился, а первая строка
-- «#showtooltip item:ID» показывает на кнопке тот предмет, что есть в
-- сумках: настоящий значок и счёт вместо тёмной кнопки с нулём.
-- Такими становятся все готовые макросы из одного «#showtooltip» и двух и
-- более строк «/use item:ID».
for _, groups in pairs(ns.MACROS) do
    for _, g in ipairs(groups) do
        for _, m in ipairs(g.list or {}) do
            if m.best == nil and type(m.body) == "string" then
                local rest = m.body:match("^#showtooltip\n(.+)$")
                if rest then
                    local n, ok = 0, true
                    for line in (rest .. "\n"):gmatch("(.-)\n") do
                        if line:match("^/use item:%d+$") then n = n + 1 else ok = false end
                    end
                    if ok and n >= 2 then m.best = "show" end
                end
            end
        end
    end
end

local function BestBody(m)
    if not m.best then return m.body end
    if m.best == "show" then
        local rest = m.body:match("^#showtooltip[^\n]*\n(.+)$")
        if rest then
            for id in rest:gmatch("item:(%d+)") do
                if ItemCount(tonumber(id)) > 0 then return "#showtooltip item:" .. id .. "\n" .. rest end
            end
        end
        return m.body
    end
    local head = m.body:match("^(#showtooltip[^\n]*\n)") or ""
    local first
    for id in m.body:gmatch("item:(%d+)") do
        first = first or id
        if not m.scan and ItemCount(tonumber(id)) > 0 then return head .. "/use item:" .. id end
    end
    if m.scan then
        local id = ns.Food.Best(m)
        if id then return head .. "/use item:" .. id end
        if id == false then
            for x in m.body:gmatch("item:(%d+)") do
                if ItemCount(tonumber(x)) > 0 then return head .. "/use item:" .. x end
            end
        end
    end
    return first and (head .. "/use item:" .. first) or m.body
end

-- Значок для макроса в игре: всегда заранее выбранный, без «?».
local function GameIcon(m)
    local icon = FirstIcon(m.best and not m.icon and { body = BestBody(m) } or m)
    if icon == nil or icon == QUESTION then icon = DEFAULT_ICON end
    if type(icon) == "string" then
        local id = GetFileIDFromPath and GetFileIDFromPath(icon)
        if id then return id end
        return icon:match("([^\\]+)$") or icon
    end
    return icon
end

-------------------------------------------------------------------------------
--  Создание макроса
-------------------------------------------------------------------------------
-- Макросы в игре, которые записал сам аддон: название -> что записал.
-- Наш - только если в игре сейчас ровно этот текст (у другого персонажа
-- может быть свой макрос с тем же названием, или его правили в /macro).
-- Свой макрос игрока с тем же названием меняем только с его согласия.
local function OwnMacro(name, body)
    local db = DB()
    db.own = db.own or {}
    if name and body ~= nil then db.own[name] = body or nil end
end
local function IsOwn(name, body)
    local own = DB().own
    return own ~= nil and name ~= nil and type(body) == "string" and own[name] == body
end

-- Текст макроса в игре - наш: то, что аддон сам бы записал (с любыми
-- настройками безопасного лечения), или «лучшая еда» из списка этого макроса.
local function OursBody(body, m)
    if type(body) ~= "string" or not m or not m.body then return false end
    if body == (Render(BestBody(m))) then return true end
    local H = ns.Helper
    if H and H.SafeBody then
        for _, heal in ipairs({ false, true }) do
            for _, alt in ipairs({ false, true }) do
                if body == (Render(H.SafeBody(m.body, heal, alt))) then return true end
            end
        end
    end
    if m.best == "show" then
        -- тот же список, первая строка показывает любой предмет из него
        local mine, theirs = m.body:match("^#showtooltip[^\n]*\n(.+)$"), body:match("^#showtooltip[^\n]*\n(.+)$")
        return mine ~= nil and mine == theirs
    end
    if m.best then
        local id = body:match("^#showtooltip[^\n]*\n/use item:(%d+)%s*$") or body:match("^/use item:(%d+)%s*$")
        if id then
            for x in m.body:gmatch("item:(%d+)") do if x == id then return true end end
            -- предмет, который макрос со scan мог взять из сумок сам
            if m.scan and ns.Food.Fits(m.scan, tonumber(id)) then return true end
        end
    end
    return false
end

-- Макрос index в игре можно менять без вопроса.
local function MayEdit(index, m)
    local name, _, body = GetMacroInfo(index)
    if not name then return false end
    return IsOwn(name, body) or OursBody(body, m) or (m.base and OursBody(body, m.base)) or false
end

-- Макрос в игре: по текущему имени, прошлому имени или исходному.
local function FindMacro(m)
    for _, n in ipairs({ m.name, m.prev or false, m.base and m.base.name or false }) do
        if n then
            local index = GetMacroIndexByName(n)
            if index and index > 0 then return index end
        end
    end
end

-- Новый макрос: «Для всех классов» - в общие макросы, классовые - в макросы
-- персонажа. Если там нет места, - туда, где есть.
-- mode: nil - взять на курсор; "create" - только создать (после боя).
-- Возвращает индекс макроса.
local function Pickup(m, retried, shared, mode, confirmed)
    if InCombatLockdown() then
        AfterCombat("macro:" .. m.name, function() Pickup(m, nil, shared, "create", confirmed) end)
        Print((T("в бою макросы создавать нельзя: «%s» будет создан сразу после боя.")):format(m.name))
        return
    end
    local body, missing = Render(BestBody(m))
    if missing then
        if not retried then
            RequestSpells(m.body)
            C_Timer.After(0.5, function() Pickup(m, true, shared, mode, confirmed) end)
            return
        end
        Print(T("не все заклинания загружены, попробуй ещё раз через пару секунд."))
        return
    end
    if CharCount(body) > MAX_CHARS then
        Print(T("макрос длиннее 255 символов и не поместится."))
        return
    end
    local index = FindMacro(m)
    local where
    if index then
        -- в игре уже есть макрос с этим названием, и он не наш: спросить
        if not confirmed and not MayEdit(index, m) then
            local ask = T("В окне /macro уже есть твой макрос «%s». Заменить его макросом из MacroCoach?")
            StaticPopup_Show("MACROCOACH_REPLACE", ask:format(GetMacroInfo(index) or ""), nil, { m = m, shared = shared, mode = mode })
            return
        end
        EditMacro(index, m.name, GameIcon(m), body)
        OwnMacro(m.name, body)
    else
        local general, char = GetNumMacros()
        local roomShared = (general or 0) < (MAX_ACCOUNT_MACROS or 120)
        local roomChar = (char or 0) < (MAX_CHARACTER_MACROS or 18)
        local perChar = not shared
        if perChar and not roomChar then perChar = false end
        if not perChar and not roomShared then perChar = true end
        if (perChar and not roomChar) or (not perChar and not roomShared) then
            Print(T("нет свободных мест для макросов: удали ненужные в /macro."))
            return
        end
        index = CreateMacro(m.name, GameIcon(m), body, perChar)
        if index and index > 0 then OwnMacro(m.name, body) end
        where = perChar and T("в макросы персонажа") or T("в общие макросы")
    end
    if index and index > 0 then
        if mode == "create" then
            if ns.quietPickup then return index end -- набор: итог одной строкой (Share.lua)
            if where then
                Print((T("«%s» добавлен %s. Нажми «Добавить», чтобы взять его на курсор.")):format(m.name, where))
            else
                Print((T("макрос «%s» в игре обновлён.")):format(m.name))
            end
            return index
        end
        PickupMacro(index)
        if where then
            Print((T("«%s» добавлен %s и взят на курсор: щёлкни по ячейке панели.")):format(m.name, where))
        else
            Print((T("«%s» на курсоре: щёлкни по ячейке панели.")):format(m.name))
        end
        return index
    end
end

-- Заменить свой макрос игрока с тем же названием (только с согласия).
StaticPopupDialogs.MACROCOACH_REPLACE = {
    text = "%s", -- текст переводится при показе: язык известен только после загрузки
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, data) if data then Pickup(data.m, nil, data.shared, data.mode, true) end end,
    showAlert = true,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- После правки обновить макрос, если он уже создан в игре (и он наш).
local function SyncGameMacro(before, after)
    local index = FindMacro(before)
    if not index then return end
    if not MayEdit(index, before) then return end
    if InCombatLockdown() then
        AfterCombat("sync:" .. (before.name or "?"), function() SyncGameMacro(before, after) end)
        Print((T("в бою макрос в игре не обновить: «%s» обновится сразу после боя.")):format(after.name))
        return
    end
    local body, missing = Render(BestBody(after))
    if missing or CharCount(body) > MAX_CHARS then return end
    EditMacro(index, after.name, GameIcon(after), body)
    if before.name ~= after.name then OwnMacro(before.name, false) end
    OwnMacro(after.name, body)
    Print((T("макрос «%s» в игре тоже обновлён.")):format(after.name))
    if frame and frame.UpdateSlots then frame.UpdateSlots() end
end

-- Еда и питьё уже в игре: вне боя обновить лучший предмет, когда меняются сумки.
local bestPending
local function UpdateBestMacros()
    bestPending = nil
    if InCombatLockdown() then return end
    ns.Food.incomplete = nil
    for class, groups in pairs(ns.MACROS) do
        for _, g in ipairs(groups) do
            for _, m in ipairs(g.list or {}) do
                if m.best then
                    local em = Effective(class, m)
                    local index = em.best and FindMacro(em)
                    -- только свой «лучший» макрос: чужой «Еда» игрока не трогаем
                    if index and MayEdit(index, em) then
                        local name, _, body = GetMacroInfo(index)
                        local want, missing = Render(BestBody(em))
                        if not missing and want ~= body then
                            EditMacro(index, name, GameIcon(em), want)
                            OwnMacro(name, want)
                        end
                    end
                end
            end
        end
    end
    -- часть предметов в сумках ещё не загружена: проверить ещё раз чуть позже
    if ns.Food.incomplete and ns.Food.retries < 3 then
        ns.Food.retries = ns.Food.retries + 1
        bestPending = true
        C_Timer.After(2, UpdateBestMacros)
    end
end
-------------------------------------------------------------------------------
--  Макросы на панелях: какие уже стоят, названия на кнопках, очистка
-------------------------------------------------------------------------------
local MAX_ACTION_SLOT = 180
local barNames -- названия макросов, которые стоят на панелях

local function BarMacroNames()
    if barNames then return barNames end
    barNames = {}
    local getText = (C_ActionBar and C_ActionBar.GetActionText) or GetActionText
    for slot = 1, MAX_ACTION_SLOT do
        local kind = GetActionInfo(slot)
        if kind == "macro" and getText then
            local name = getText(slot)
            if name and name ~= "" then barNames[name] = true end
        end
    end
    return barNames
end

-- Стоит ли макрос на какой-нибудь панели.
local function OnBars(m)
    local index = FindMacro(m)
    if not index then return false end
    local name = GetMacroInfo(index)
    return name ~= nil and BarMacroNames()[name] == true
end

-- Кнопки панелей с названием макроса: панели игры, EllesmereUI и
-- LibActionButton (Bartender, ElvUI и подобные).
local BAR_PREFIXES = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local function ForEachBarButton(fn)
    local seen = {}
    local function visit(b)
        if type(b) == "table" and not seen[b] and type(b.Name) == "table" and b.Name.SetFont then
            seen[b] = true
            fn(b)
        end
    end
    local events = ActionBarButtonEventsFrame
    if events and type(events.frames) == "table" then
        for _, b in ipairs(events.frames) do visit(b) end
    end
    for _, prefix in ipairs(BAR_PREFIXES) do
        for i = 1, 12 do visit(_G[prefix .. i]) end
    end
    for i = 1, MAX_ACTION_SLOT do
        visit(_G["EABButton" .. i]) -- EllesmereUI
        visit(_G["BT4Button" .. i]) -- Bartender
    end
    local LAB = LibStub and LibStub("LibActionButton-1.0", true)
    if LAB and type(LAB.buttonRegistry) == "table" then
        for b in pairs(LAB.buttonRegistry) do visit(b) end
    end
end

-- Обычный размер названий на кнопках (как было до аддона).
function ns.DefaultNameSize()
    local size
    ForEachBarButton(function(b)
        if size then return end
        local f = b.Name.origFont
        size = f and f[2] or select(2, b.Name:GetFont())
    end)
    return math.floor((size or 10) + 0.5)
end

-- Наши настройки сильнее, чем у панелей: если панель (например, EllesmereUI)
-- снова ставит свой шрифт или показывает название, сразу возвращаем своё.
local applying
local function Enforce(fs)
    local cfg = DB().barNames
    applying = true
    if cfg.size then
        local path, _, flags = fs:GetFont()
        path = path or (fs.origFont and fs.origFont[1])
        if path then fs:SetFont(path, cfg.size, flags) end
    end
    if cfg.hide then fs:SetAlpha(0) end
    applying = false
end

local function HookName(fs)
    if fs.coachHooked then return end
    fs.coachHooked = true
    hooksecurefunc(fs, "SetFont", function(self)
        if not applying and DB().barNames.size then Enforce(self) end
    end)
    hooksecurefunc(fs, "SetAlpha", function(self, a)
        if not applying and DB().barNames.hide and a ~= 0 then Enforce(self) end
    end)
end

-- Применить настройки названий: скрыть или задать размер шрифта.
local namesPending
local namesTouched -- названия на кнопках уже меняли (размер или скрытие)
function ns.ApplyBarNames()
    if InCombatLockdown() then namesPending = true return end
    namesPending = nil
    local cfg = DB().barNames
    -- ничего не настроено и ничего не меняли: все кнопки панелей не обходим
    if not cfg.size and not cfg.hide and not namesTouched then return end
    namesTouched = (cfg.size or cfg.hide) and true or nil
    ForEachBarButton(function(b)
        local fs = b.Name
        if not fs.origFont then
            fs.origFont = { fs:GetFont() }
            fs.origHeight = fs:GetHeight()
        end
        HookName(fs)
        applying = true
        if cfg.size then
            local path, _, flags = fs:GetFont()
            path = path or fs.origFont[1]
            if path then fs:SetFont(path, cfg.size, flags) end
            fs:SetHeight(cfg.size + 4)
            fs.coachSized = true
        elseif fs.coachSized then
            local f = fs.origFont
            if f[1] then fs:SetFont(f[1], f[2], f[3]) end
            if fs.origHeight and fs.origHeight > 0 then fs:SetHeight(fs.origHeight) end
            fs.coachSized = nil
        end
        if cfg.hide then
            fs:SetAlpha(0)
            fs.coachHid = true
        elseif fs.coachHid then
            fs:SetAlpha(1)
            fs.coachHid = nil
        end
        applying = false
    end)
end

-- Копии перед очисткой лежат в MacroCoachDB.wiped: общие - под ключом
-- "general", макросы персонажа - под «Имя-Сервер».
local function WipeKey(perChar)
    if not perChar then return "general" end
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "")
end

-- Удалить все общие макросы или все макросы персонажа (в самой игре).
local function WipeMacros(perChar)
    if InCombatLockdown() then
        Print(T("в бою макросы удалять нельзя."))
        return
    end
    local general, char = GetNumMacros()
    local base = perChar and (MAX_ACCOUNT_MACROS or 120) or 0
    local n = perChar and (char or 0) or (general or 0)
    -- копия перед удалением: её возвращает кнопка «Вернуть удалённые»
    local saved = {}
    for i = base + 1, base + n do
        local name, icon, body = GetMacroInfo(i)
        if name then saved[#saved + 1] = { name, icon, body } end
    end
    local db = DB()
    db.wiped = db.wiped or {}
    db.wiped[WipeKey(perChar)] = saved
    for i = base + n, base + 1, -1 do DeleteMacro(i) end
    Print((perChar and T("удалено макросов персонажа: %d.") or T("удалено общих макросов: %d.")):format(n))
end

function ns.WipedCount(perChar)
    local list = DB().wiped and DB().wiped[WipeKey(perChar)]
    return list and #list or 0
end

-- Вернуть макросы, удалённые последней очисткой (на панели они не вернутся).
function ns.RestoreWiped(perChar)
    if InCombatLockdown() then
        Print(T("в бою макросы вернуть нельзя."))
        return
    end
    local wiped, key = DB().wiped, WipeKey(perChar)
    local list = wiped and wiped[key]
    if not list or #list == 0 then return end
    local general, char = GetNumMacros()
    local free = perChar and (MAX_CHARACTER_MACROS or 18) - (char or 0) or (MAX_ACCOUNT_MACROS or 120) - (general or 0)
    local total, done = #list, 0
    while list[1] and free > 0 do
        local m = list[1]
        CreateMacro(m[1], m[2] or QUESTION, m[3] or "", perChar and true or nil)
        tremove(list, 1)
        done, free = done + 1, free - 1
    end
    if not list[1] then wiped[key] = nil end
    if done == total then
        Print(T("возвращено макросов: %d."):format(done))
    else
        Print(T("не хватило места: возвращено %d из %d."):format(done, total))
    end
end

-- Таблицу игры StaticPopupDialogs не переприсваиваем (только добавляем ключ):
-- запись в саму глобальную переменную «заражает» её, и потом меню по Esc
-- не может вызвать защищённую SpellStopCasting() (ADDON_ACTION_FORBIDDEN).
StaticPopupDialogs.MACROCOACH_WIPE = {
    text = "%s",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, data) WipeMacros(data) end,
    showAlert = true,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns.AskWipe(perChar)
    local general, char = GetNumMacros()
    local n = perChar and (char or 0) or (general or 0)
    if n == 0 then return end
    local text = perChar and T("Удалить все макросы этого персонажа (%d)? Они пропадут и с панелей. Отменить нельзя.")
        or T("Удалить все общие макросы (%d)? Они пропадут и с панелей у всех персонажей. Отменить нельзя.")
    StaticPopup_Show("MACROCOACH_WIPE", text:format(n), nil, perChar)
end

local barWatch = CreateFrame("Frame")
barWatch:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
barWatch:RegisterEvent("UPDATE_MACROS")
barWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
barWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
local barPending
barWatch:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Панели других аддонов создают кнопки чуть позже: второй проход.
        C_Timer.After(1, ns.ApplyBarNames)
        C_Timer.After(5, ns.ApplyBarNames)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if namesPending then ns.ApplyBarNames() end
        return
    end
    barNames = nil
    if barPending then return end
    barPending = true
    C_Timer.After(0.2, function()
        barPending = nil
        if ns.Relayout and MacroCoachFrame and MacroCoachFrame:IsShown() then ns.Relayout() end
    end)
end)

local bestWatch = CreateFrame("Frame")
bestWatch:RegisterEvent("BAG_UPDATE_DELAYED")
bestWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
bestWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
bestWatch:RegisterEvent("PLAYER_LEVEL_UP")
bestWatch:SetScript("OnEvent", function()
    ns.Food.retries = 0
    if bestPending then return end
    bestPending = true
    C_Timer.After(1, UpdateBestMacros)
end)

-------------------------------------------------------------------------------
--  Оформление: рамка как у окна макросов игры, пергамент как в книге
--  заклинаний WoW Forever, вкладки классов справа, специализаций - сверху.
-------------------------------------------------------------------------------
local INK = { 0.25, 0.14, 0.04 }
if type(SPELLBOOK_FONT_COLOR) == "table" and SPELLBOOK_FONT_COLOR.GetRGB then
    INK = { SPELLBOOK_FONT_COLOR:GetRGB() }
end
local CODE_INK = { 0.05, 0.25, 0.05 }
local MAX_SPEC_TABS = 5

local function Font(name, fallback)
    return _G[name] or _G[fallback] or GameFontNormal
end

local function Text(parent, font, fallback, color, wrap)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(Font(font, fallback))
    if color then
        fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        fs:SetShadowOffset(0, 0)
    end
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(wrap and true or false)
    return fs
end

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-------------------------------------------------------------------------------
--  Шапка страницы - одна на все страницы, как «Зачем макросы»: прямо на
--  пергаменте крупный заголовок тёмными чернилами, одна-две строки и кнопки.
--  h:Set(title, text); h.buttons - кнопки в ряд; h:Layout(top) -> низ шапки.
-------------------------------------------------------------------------------
local INK_TITLE, INK_TEXT = { 0.16, 0.08, 0 }, { 0.24, 0.14, 0.04 }
local function PageHeader(page, width)
    local h = { buttons = {} }
    h.title = Text(page, "SystemFont_Huge1", "GameFontNormalHuge", INK_TITLE, true)
    h.title:SetWidth(width - 52)
    h.text = Text(page, "SystemFont_Med2", "GameFontHighlight", INK_TEXT, true)
    h.text:SetWidth(width - 52)
    function h:Set(title, text)
        self.title:SetText(title or "")
        self.text:SetText(text or "")
        self.text:SetShown(text ~= nil and text ~= "")
    end
    function h:Layout(top)
        local y = top or 16
        self.title:ClearAllPoints()
        self.title:SetPoint("TOPLEFT", 26, -y)
        y = y + self.title:GetStringHeight() + 8
        if self.text:IsShown() then
            self.text:ClearAllPoints()
            self.text:SetPoint("TOPLEFT", 26, -y)
            y = y + self.text:GetStringHeight() + 12
        end
        -- кнопки в ряд, не влезли - на следующую строку
        local x, rowH = 26, 0
        for _, b in ipairs(self.buttons) do
            if b:IsShown() then
                if x > 26 and x + b:GetWidth() > width - 26 then
                    x, y = 26, y + rowH + 8
                    rowH = 0
                end
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", x, -y)
                x = x + b:GetWidth() + 10
                rowH = math.max(rowH, b:GetHeight())
            end
        end
        if rowH > 0 then y = y + rowH + 4 end
        return y + 12
    end
    return h
end

-------------------------------------------------------------------------------
--  Круглый значок-кнопка в золотом кольце, как значки вкладок: «?» на
--  карточке, шестерёнка настроек у крестика окна.
--  icon - путь к значку; без него - знак «?».
-------------------------------------------------------------------------------
local function Badge(parent, size, icon)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local mask = b:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints()
    b.art = b:CreateTexture(nil, "ARTWORK")
    if icon then
        bg:SetColorTexture(0, 0, 0, 1)
        b.art:SetTexture(icon)
        b.art:SetPoint("TOPLEFT", 1, -1)
        b.art:SetPoint("BOTTOMRIGHT", -1, 1)
        b.art:AddMaskTexture(mask)
    else
        bg:SetColorTexture(0.12, 0.08, 0.03, 1)
        if HasAtlas("QuestTurnin") then
            b.art:SetAtlas("QuestTurnin", false)
            b.art:SetSize(size * 0.62, size * 0.75)
            b.art:SetPoint("CENTER", 0, 0)
        else
            local q = b:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            q:SetText("?")
            q:SetPoint("CENTER", 1, 0)
            b.art = q
        end
    end
    bg:AddMaskTexture(mask)
    local ring = b:CreateTexture(nil, "OVERLAY")
    local info = HasAtlas("Talents-Main-Ring-c60") and C_Texture.GetAtlasInfo("Talents-Main-Ring-c60")
    if info then
        ring:SetAtlas("Talents-Main-Ring-c60", false)
        local k = size / 36
        ring:SetSize((info.width or 48) * k, (info.height or 48) * k)
        ring:SetPoint("CENTER")
    else
        ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        ring:SetSize(size * 48 / 26, size * 48 / 26)
        ring:SetPoint("TOPLEFT", -size * 4 / 26, size * 4 / 26)
    end
    -- подсветка - ровный круг той же маской, что и значок
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.9, 0.5, 0.3)
    hl:SetBlendMode("ADD")
    hl:AddMaskTexture(mask)
    return b
end

local function Sound(kit)
    if PlaySound and SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

-- Классическая полоса прокрутки: кнопки со стрелками, ползунок и тёмный
-- желобок, как в окне талантов и журнале заданий.
local function ScrollTrack(sf)
    -- Тёмная подложка под полосой прокрутки, чтобы пергамент не просвечивал.
    local back = sf:CreateTexture(nil, "BACKGROUND", nil, -8)
    back:SetColorTexture(0.04, 0.03, 0.03, 0.92)
    back:SetPoint("TOPLEFT", sf, "TOPRIGHT", 0, 6)
    back:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 30, -6)
    local file = "Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar"
    local top = sf:CreateTexture(nil, "ARTWORK")
    top:SetTexture(file)
    top:SetSize(31, 102)
    top:SetPoint("TOPLEFT", sf, "TOPRIGHT", -2, 5)
    top:SetTexCoord(0, 0.484375, 0, 0.4)
    local bottom = sf:CreateTexture(nil, "ARTWORK")
    bottom:SetTexture(file)
    bottom:SetSize(31, 106)
    bottom:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", -2, -2)
    bottom:SetTexCoord(0.515625, 1, 0, 0.4140625)
    local mid = sf:CreateTexture(nil, "ARTWORK")
    mid:SetTexture(file)
    mid:SetWidth(31)
    mid:SetPoint("TOP", top, "BOTTOM")
    mid:SetPoint("BOTTOM", bottom, "TOP")
    mid:SetTexCoord(0, 0.484375, 0.75, 1)
    if type(sf.ScrollBar) == "table" then sf.ScrollBar.scrollStep = 60 end
end

-- Вкладка сбоку, как в книге заклинаний.
local function SideTab(parent, tip)
    local tab = CreateFrame("CheckButton", nil, parent)
    tab:SetSize(32, 32)
    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    bg:SetSize(64, 64)
    bg:SetPoint("TOPLEFT", -3, 11)
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetAllPoints()
    tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    local checked = tab:GetCheckedTexture()
    if checked then checked:SetBlendMode("ADD") end
    tab.tip = tip
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tip)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return tab
end

local CLASS_RU = { WARRIOR = "Воин", PALADIN = "Паладин", HUNTER = "Охотник", ROGUE = "Разбойник", PRIEST = "Жрец",
    SHAMAN = "Шаман", MAGE = "Маг", WARLOCK = "Чернокнижник", DRUID = "Друид",
    GENERAL = "Для всех классов", CUSTOM = "Свои макросы", OPTIONS = "Настройки", HELPER = "Помощник" }
local function ClassName(class)
    return CLASS_RU[class] and T(CLASS_RU[class]) or class
end

local function SetClassIcon(tex, class)
    tex:SetTexCoord(0, 1, 0, 1)
    if class == "GENERAL" then
        tex:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        return
    end
    if class == "OPTIONS" then
        tex:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
        return
    end
    if class == "HELPER" then
        tex:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
        return
    end
    if class == "CUSTOM" then
        -- Зелёный плюс, как на плитке «Новый макрос».
        if HasAtlas("communities-icon-addchannelplus") then
            tex:SetAtlas("communities-icon-addchannelplus", false)
        else
            tex:SetTexture("Interface\\Icons\\INV_Feather_05")
        end
        return
    end
    local atlas = "classicon-" .. class:lower()
    if HasAtlas(atlas) then
        tex:SetAtlas(atlas)
    else
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if tc then tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
    end
end

-------------------------------------------------------------------------------
--  Значки вкладок: специализации - как в окне талантов игры
-------------------------------------------------------------------------------
local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
-- Если игра не сообщит значок, - значки классических веток талантов.
local SPEC_ICON = {
    WARRIOR = { ["Оружие"] = "Ability_Rogue_Eviscerate", ["Неистовство"] = "Ability_Warrior_InnerRage", ["Защита"] = "INV_Shield_06" },
    PALADIN = { ["Свет"] = "Spell_Holy_HolyBolt", ["Защита"] = "Spell_Holy_DevotionAura", ["Воздаяние"] = "Spell_Holy_AuraOfLight" },
    HUNTER = { ["Повелитель зверей"] = "Ability_Hunter_BeastTaming", ["Стрельба"] = "Ability_Marksmanship", ["Выживание"] = "Ability_Hunter_SwiftStrike" },
    ROGUE = { ["Ликвидация"] = "Ability_Rogue_Eviscerate", ["Бой"] = "Ability_BackStab", ["Скрытность"] = "Ability_Stealth" },
    PRIEST = { ["Послушание"] = "Spell_Holy_WordFortitude", ["Свет"] = "Spell_Holy_HolyBolt", ["Тьма"] = "Spell_Shadow_ShadowWordPain" },
    SHAMAN = { ["Стихии"] = "Spell_Nature_Lightning", ["Совершенствование"] = "Spell_Nature_LightningShield", ["Исцеление"] = "Spell_Nature_MagicImmunity" },
    MAGE = { ["Тайная магия"] = "Spell_Holy_MagicalSentry", ["Огонь"] = "Spell_Fire_FireBolt02", ["Лёд"] = "Spell_Frost_FrostBolt02" },
    WARLOCK = { ["Колдовство"] = "Spell_Shadow_DeathCoil", ["Демонология"] = "Spell_Shadow_Metamorphosis", ["Разрушение"] = "Spell_Shadow_RainOfFire" },
    DRUID = { ["Баланс"] = "Spell_Nature_StarFall", ["Сила зверя"] = "Ability_Racial_BearForm", ["Исцеление"] = "Spell_Nature_HealingTouch" },
    GENERAL = { ["Бой"] = "Ability_DualWield", ["Расходники"] = "INV_Potion_51", ["Прочее"] = "INV_Misc_Rune_01" },
    CUSTOM = { ["Мои макросы"] = "INV_Scroll_03", ["Как написать"] = "INV_Misc_Book_09",
        ["Импорт/экспорт"] = "INV_Letter_15" },
    OPTIONS = { ["Панели и макросы"] = "INV_Misc_Gear_01", ["Импорт/экспорт"] = "INV_Letter_15" },
    HELPER = { ["Зачем макросы"] = "INV_Misc_Book_11", ["Советы"] = "Spell_Holy_SealOfWisdom",
        ["Проверка"] = "INV_Misc_Spyglass_02" },
}

-- Название специализации из игры совпадает с подписью вкладки.
local function SameSpec(name, label)
    if not label or label == "" then return false end
    return name == label or name:find(label, 1, true) ~= nil or label:find(name, 1, true) ~= nil
end

local iconCache = {}
-- Возвращает путь или ID значка; nil - значок класса.
local function SpecIcon(class, label)
    if label == "Общие" and class ~= "GENERAL" then return nil end
    local key = class .. "/" .. label
    if iconCache[key] then return iconCache[key] end
    local icon
    local id = CLASS_ID[class]
    if id and GetSpecializationInfoForClassID then
        local api = C_SpecializationInfo
        local n = api and api.GetNumSpecializationsForClassID and api.GetNumSpecializationsForClassID(id) or 3
        for i = 1, (type(n) == "number" and n or 3) do
            local ok, _, name, _, tex = pcall(GetSpecializationInfoForClassID, id, i)
            if ok and type(name) == "string" and tex and (SameSpec(name, label) or SameSpec(name, ns.EN[label]) or SameSpec(name, T(label))) then
                icon = tex
                break
            end
        end
    end
    if not icon then
        local f = SPEC_ICON[class] and SPEC_ICON[class][label]
        icon = (label == "Рекомендации" and ns.Helper and ns.Helper.NEWBIE_ICON) or (f and ("Interface\\Icons\\" .. f)) or QUESTION
    end
    iconCache[key] = icon
    return icon
end

-- Вкладка специализации: форма вкладки окна макросов игры, внутри - круглый
-- значок в кольце, как у заголовков веток в окне талантов, и название.
local TAB_ART = {
    normal = { "uiframe-tab-left", "_uiframe-tab-center", "uiframe-tab-right" },
    active = { "uiframe-activetab-left", "_uiframe-activetab-center", "uiframe-activetab-right" },
}
local TAB_ICON = 22 -- кольцо вокруг значка не должно вылезать за край вкладки

local function TabArt(b, names, layer, active)
    local parts = {}
    local ok = HasAtlas(names[1]) and HasAtlas(names[2]) and HasAtlas(names[3])
    for i = 1, 3 do
        local t = b:CreateTexture(nil, layer)
        if ok then
            t:SetAtlas(names[i], true)
            t:SetTexCoord(0, 1, 1, 0.25) -- вкладка сверху: перевёрнута, как у игры
        else
            -- Без атласа - классическая вкладка персонажа, тоже перевёрнутая.
            t:SetTexture(active and "Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab"
                or "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab")
            local l, r = ({ 0, 0.15625, 0.84375 })[i], ({ 0.15625, 0.84375, 1 })[i]
            t:SetTexCoord(l, r, 1, 0)
            if i ~= 2 then t:SetWidth(20) end
        end
        t:SetHeight(TAB_H)
        parts[i] = t
    end
    local l, m, r = parts[1], parts[2], parts[3]
    l:SetPoint("BOTTOMLEFT", active and -1 or -3, 0)
    r:SetPoint("BOTTOMRIGHT", active and 8 or 7, 0)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT")
    m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    return parts
end

local function ShowParts(parts, on)
    for _, t in ipairs(parts) do t:SetShown(on) end
end

local function SpecTabButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(TAB_H)
    b.normal = TabArt(b, TAB_ART.normal, "BACKGROUND")
    b.active = TabArt(b, TAB_ART.active, "BACKGROUND", true)
    local hl = TabArt(b, TAB_ART.normal, "HIGHLIGHT")
    for _, t in ipairs(hl) do
        t:SetBlendMode("ADD")
        t:SetAlpha(0.4)
    end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(TAB_ICON, TAB_ICON)
    b.icon:SetPoint("LEFT", 9, -3) -- ближе к краю, по центру видимой части вкладки
    local mask = b:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(TAB_ICON + 3, TAB_ICON + 3)
    mask:SetPoint("CENTER", b.icon, "CENTER", 1, -1)
    b.icon:AddMaskTexture(mask)
    b.ring = b:CreateTexture(nil, "OVERLAY")
    local ring = HasAtlas("Talents-Main-Ring-c60") and C_Texture.GetAtlasInfo("Talents-Main-Ring-c60")
    if ring then
        -- Кольцо рассчитано на значок 36: уменьшить в той же пропорции.
        b.ring:SetAtlas("Talents-Main-Ring-c60", false)
        local k = TAB_ICON / 36
        b.ring:SetSize((ring.width or 48) * k, (ring.height or 48) * k)
        b.ring:SetPoint("CENTER", b.icon, "CENTER", 0, 0)
    else
        b.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        b.ring:SetSize(48, 48)
        b.ring:SetPoint("TOPLEFT", b.icon, "TOPLEFT", -4, 4)
    end
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, -1) -- чуть ниже центра значка: по центру видимой вкладки
    function b:SetSelected(on)
        self.selected = on
        ShowParts(self.normal, not on)
        ShowParts(self.active, on)
        self.icon:SetDesaturated(false)
        self.icon:SetAlpha(on and 1 or 0.8)
        if on then
            self.text:SetTextColor(1, 1, 1)
        else
            self.text:SetTextColor(1, 0.82, 0)
        end
    end
    return b
end

-------------------------------------------------------------------------------
--  Вкладки специализаций: группы с одинаковым названием - одна вкладка
-------------------------------------------------------------------------------
local tabCache = {
    CUSTOM = { { label = "Мои макросы", custom = true, list = {} }, { label = "Как написать", guide = true, list = {} },
        { label = "Импорт/экспорт", helper = "share", list = {} } },
    OPTIONS = { { label = "Панели и макросы", options = true, list = {} },
        { label = "Импорт/экспорт", helper = "share", list = {} } },
    HELPER = { { label = "Зачем макросы", helper = "intro", list = {} }, { label = "Проверка", helper = "check", list = {} } },
}
local function SpecTabs(class)
    if tabCache[class] then return tabCache[class] end
    local tabs, byName = {}, {}
    for _, g in ipairs(ns.MACROS[class] or {}) do
        local t = byName[g.group]
        if not t then
            t = { label = g.group, list = {} }
            byName[g.group] = t
            tabs[#tabs + 1] = t
        end
        for _, m in ipairs(g.list) do t.list[#t.list + 1] = m end
    end
    local order = ns.TAB_ORDER and ns.TAB_ORDER[class]
    if order then
        local rank = {}
        for i, n in ipairs(order) do rank[n] = i end
        table.sort(tabs, function(a, b) return (rank[a.label] or 99) < (rank[b.label] or 99) end)
    end
    -- Вкладка «Рекомендации» - первой: самые полезные макросы для старта
    -- и зачем каждый (HelperData.lua).
    local rec = ns.Helper and ns.Helper.Recommended(class) or {}
    if #rec >= 2 and #tabs < MAX_SPEC_TABS then table.insert(tabs, 1, { label = "Рекомендации", list = rec, rec = true }) end
    tabCache[class] = tabs
    return tabs
end

-- Вкладка текущей специализации игрока, если игра её сообщает.
local function PlayerSpecTab(tabs)
    local api = C_SpecializationInfo
    if not (api and api.GetSpecialization and api.GetSpecializationInfo) then return end
    local ok, index = pcall(api.GetSpecialization)
    if not ok or type(index) ~= "number" then return end
    local ok2, _, name = pcall(api.GetSpecializationInfo, index)
    if not ok2 or type(name) ~= "string" or name == "" then return end
    for i, t in ipairs(tabs) do
        if SameSpec(name, t.label) or SameSpec(name, ns.EN[t.label]) or SameSpec(name, T(t.label)) then return i end
    end
end

-------------------------------------------------------------------------------
--  Строка макроса на пергаменте
-------------------------------------------------------------------------------
local OpenEditor, OpenCustomText, OpenBuilder, RefreshCustom, SaveCustom, ShowClass, builder -- объявлены ниже
local BuildOptionsPage
local currentKey, currentSpec
local selectedSpec = {}

-- Тёмная карточка с бронзовой рамкой: каждый макрос - отдельный блок.
local CARD = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local GOLD = { 1, 0.82, 0 }
local LIGHT = { 0.92, 0.92, 0.92 }
local GREY = { 0.62, 0.62, 0.62 }
local function Card(f)
    f:SetBackdrop(CARD)
    f:SetBackdropColor(0.05, 0.045, 0.04, 0.9)
    f:SetBackdropBorderColor(0.6, 0.48, 0.25, 1)
end

-- Карточка макроса - один вид везде: название, состояние, значки «было» и
-- «стало» с описанием, кнопки; текст макроса и ID - по щелчку на «?».
-- rec - вкладка «Рекомендации»: там ещё подсказка, как добавить.
local RED_C, GOLD_C, GREEN_C, YELLOW_C, GREY_C = "|cffff5555", "|cffffd100", "|cff33dd33", "|cffffd100", "|cff9d9d9d"

-- Список невыученного: до трёх названий.
local function MissingText(missing)
    local out = {}
    for i = 1, math.min(3, #missing) do out[i] = missing[i] end
    local text = table.concat(out, ", ")
    if #missing > 3 then text = text .. " " .. (T("и ещё %d")):format(#missing - 3) end
    return text
end

local function BuildRow(parent, class, m, width, rec)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetWidth(width)
    Card(row)
    local H = ns.Helper
    local function Go() Pickup(Effective(class, m), nil, class == "GENERAL" or class == "CUSTOM") end
    local artW, artH = H and H.ART_W or 206, H and H.ART_H or 70
    local textX = 16 + artW + 16
    local textW = width - textX - 16
    local wideW = width - 32

    local title = Text(row, "SystemFont_Large", "GameFontNormalLarge", GOLD)
    -- Значки пометок «Новичку», «Продвинутый», «PvP» после названия.
    local tags = H and H.TagIcons(row)
    local state = Text(row, "SystemFont_Med1", "GameFontHighlightSmall", LIGHT, true)
    state:SetWidth(wideW - 30)
    -- «?» в углу: наведение - что делает макрос простыми словами, щелчок - его текст.
    local help
    if H then
        help = H.CardHelp(row, row, function() if ns.Relayout then ns.Relayout() end end)
        help:ClearAllPoints()
        help:SetPoint("TOPRIGHT", -10, -10)
    end

    -- Картинка «Было -> Макрос»: значок макроса можно перетащить на панель.
    local art = H and H.MacroArt(row)
    local drag = art and art.after
    if drag then
        drag:RegisterForDrag("LeftButton")
        drag:SetScript("OnDragStart", Go)
        drag:SetScript("OnClick", Go)
        drag:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(T("Перетащи на панель или щёлкни"))
            if self.isAdded then GameTooltip:AddLine(T("Уже стоит на панели."), 0.3, 0.9, 0.3) end
            GameTooltip:Show()
        end)
        drag:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    -- Свой макрос - компактная карточка: маленький значок вместо картинки
    -- «Было -> Макрос», кнопки одной строкой.
    local compact = class == "CUSTOM"
    local small
    if compact then
        small = CreateFrame("Button", nil, row)
        small:SetSize(36, 36)
        small.icon = small:CreateTexture(nil, "ARTWORK")
        small.icon:SetAllPoints()
        small.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        small.border = small:CreateTexture(nil, "OVERLAY")
        small.border:SetPoint("TOPLEFT", -2, 2)
        small.border:SetPoint("BOTTOMRIGHT", 2, -2)
        small.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        small.border:SetTexCoord(0.2, 0.8, 0.2, 0.8)
        small:RegisterForDrag("LeftButton")
        small:SetScript("OnDragStart", Go)
        small:SetScript("OnClick", Go)
        small:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(T("Перетащи на панель или щёлкни"))
            GameTooltip:Show()
        end)
        small:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if art then art:Hide() end
    end
    -- Зачем макрос (проблема, что делает, когда жать) или описание.
    local about = Text(row, "SystemFont_Med2", "GameFontHighlight", LIGHT, true)
    about:SetWidth(textW)
    if about.SetSpacing then about:SetSpacing(2) end
    -- Текст макроса на тёмной подложке, как в окне макросов игры
    local code = Text(row, "SystemFont_Med1", "GameFontHighlightSmall", { 0.65, 1, 0.65 }, true)
    code:SetWidth(wideW - 28)
    local codeBg = row:CreateTexture(nil, "ARTWORK")
    codeBg:SetColorTexture(0, 0, 0, 0.7)
    codeBg:SetPoint("TOPLEFT", code, "TOPLEFT", -6, 6)
    codeBg:SetPoint("BOTTOMRIGHT", code, "BOTTOMRIGHT", 22, -6)
    local ids = Text(row, "SystemFont_Med1", "GameFontHighlightSmall", GREY, true)
    ids:SetWidth(wideW)
    -- Режим «Учусь»: объяснение под каждым макросом.
    local explain = Text(row, "SystemFont_Med1", "GameFontHighlightSmall", LIGHT, true)
    explain:SetWidth(wideW)

    -- Кнопки - под картинкой.
    local bw = math.floor((artW - 6) / 2)
    local function NewButton(text)
        local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        b:SetSize(bw, 22)
        b:SetText(text)
        return b
    end
    -- «Добавить» и «Изменить» - в шапке карточки, рядом со стрелкой текста
    -- макроса; остальные (у своих макросов) - под картинкой.
    local function HeadButton(text)
        local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        b:SetText(text)
        local fs = b:GetFontString()
        b:SetSize(math.max(90, math.ceil((fs and fs:GetStringWidth() or 60) + 26)), 22)
        return b
    end
    local add = HeadButton(T("Добавить"))
    add:SetScript("OnClick", Go)
    local edit = HeadButton(T("Изменить"))
    edit:SetScript("OnClick", function()
        if class == "CUSTOM" then OpenBuilder(m) else OpenEditor(class, m) end
    end)
    -- Ссылка на макрос в строку чата (Share.lua): круглый значок «скопировать»
    -- рядом со стрелкой текста макроса, без подписи.
    local linkSize = help and math.floor(help:GetWidth() + 0.5) or 22
    if linkSize < 16 then linkSize = 22 end
    local link = Badge(row, linkSize, "Interface\\Icons\\INV_Misc_Note_01")
    if help then
        link:SetPoint("RIGHT", help, "LEFT", -6, 0)
    else
        link:SetPoint("TOPRIGHT", -10, -10)
    end
    edit:SetPoint("RIGHT", link, "LEFT", -8, 0)
    add:SetPoint("RIGHT", edit, "LEFT", -6, 0)
    link:SetScript("OnClick", function()
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if ns.LinkToChat then ns.LinkToChat(class, m) end
    end)
    link:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(T("Ссылка в чат"))
        GameTooltip:AddLine(T("Вставит ссылку на этот макрос в строку чата. У кого стоит MacroCoach, откроет его щелчком."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    link:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local headW = linkSize + 8 + add:GetWidth() + 6 + edit:GetWidth() + 8
    local buttons = {}
    if class == "CUSTOM" then
        local del = NewButton(T("Удалить"))
        del:SetScript("OnClick", function(self)
            if not self.armed then
                self.armed = true
                self:SetText(T("Точно?"))
                C_Timer.After(3, function()
                    self.armed = nil
                    self:SetText(T("Удалить"))
                end)
                return
            end
            local list = CustomList()
            for i, entry in ipairs(list) do
                if entry == m then
                    table.remove(list, i)
                    break
                end
            end
            Print((T("свой макрос «%s» удалён из аддона. В игре он остался, удалить его можно в /macro.")):format(m.name))
            RefreshCustom()
        end)
        -- Предложить автору аддона: если макрос полезный, он станет готовым для всех.
        local suggest = NewButton(T("Предложить"))
        suggest:SetScript("OnClick", function() if H then H.Suggest(m) end end)
        suggest:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(T("Предложить для всех"))
            GameTooltip:AddLine(T("Даст код этого макроса, чтобы отправить его автору аддона. Если макрос полезный, его добавят в готовые для всех игроков."), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        suggest:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[1], buttons[2] = del, suggest
    end
    local buttonsH = #buttons > 0 and (math.ceil(#buttons / 2) * 26 - 4) or -6
    -- компактно: все кнопки одной строкой
    local cbw = math.floor((wideW - 36 - 12 - 3 * 6) / 4)
    if compact then for _, b in ipairs(buttons) do b:SetWidth(cbw) end end

    local function Place(fs, x, y)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
    end
    -- Состояние считается только для своего класса, общих и своих макросов:
    -- чужой класс эти заклинания не выучит.
    local _, playerClass = UnitClass("player")
    local ownClass = class == playerClass or class == "GENERAL" or class == "CUSTOM"

    function row:Fill()
        local em = Effective(class, m)
        local onBars = OnBars(em)
        local st, missing
        if ownClass and H then st, missing = H.TipState({ class = class, m = m }) end
        local stateText = ""
        if onBars then
            stateText = GREEN_C .. T("Уже стоит на панели.") .. "|r"
        elseif st == "later" then
            stateText = GREY_C .. T("Откроется позже, когда выучишь: ") .. MissingText(missing) .. ".|r"
        elseif st == "part" then
            stateText = YELLOW_C .. T("Работает частично, пока не выучено: ") .. MissingText(missing) .. ".|r"
        elseif st == "gone" then
            stateText = GREY_C .. T("Этих заклинаний в WoW Forever нет: макрос не сработает.") .. "|r"
        elseif st == "noitems" then
            stateText = YELLOW_C .. T("Подходящих предметов в сумках пока нет: макрос заработает, когда они появятся.") .. "|r"
        elseif rec and st == "ready" then
            stateText = GREEN_C .. T("Готов: нажми «Добавить» и щёлкни по ячейке панели.") .. "|r"
        end
        local grey = (st == "later" or st == "gone") and not onBars
        if art and not compact then
            art:Set(H.ArtList(em.body), FirstIcon(em), onBars and "ok" or (grey and "wait") or nil, grey)
            drag.isAdded = onBars
        end
        if small then
            small.icon:SetTexture(FirstIcon(em))
            small.icon:SetDesaturated(grey)
        end

        title:SetWidth(wideW - 30 - headW - (tags and tags:Width(class, m) or 0))
        title:SetText(em.edited and (em.title .. "  |cff66bbff(" .. T("изменён") .. ")|r") or em.title or em.name)
        local why = H and H.Why(class, m)
        -- На карточке - одна мысль: что делает макрос. «Проблема» и «когда
        -- жать» - в подсказке при наведении на этот текст.
        if why then
            about:SetText(why[2] or em.desc or "")
            self.whyTip = { why[1], why[2], why[3] }
        else
            about:SetText(em.desc or "")
            self.whyTip = nil
        end
        if not self.aboutZone then
            local z = CreateFrame("Frame", nil, self)
            z:EnableMouse(true)
            z:SetScript("OnEnter", function(s)
                local w = self.whyTip
                if not w then return end
                GameTooltip:SetOwner(s, "ANCHOR_CURSOR")
                GameTooltip:SetText(T("Проблема:"), 1, 0.33, 0.33)
                GameTooltip:AddLine(w[1] or "", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(T("Что делает:"), 1, 0.82, 0)
                GameTooltip:AddLine(w[2] or "", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(T("Когда жать:"), 1, 0.82, 0)
                GameTooltip:AddLine(w[3] or "", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            z:SetScript("OnLeave", function() GameTooltip:Hide() end)
            z:SetAllPoints(about)
            self.aboutZone = z
        end
        self.aboutZone:SetShown(self.whyTip ~= nil)
        local key = class .. "/" .. m.name
        -- Текст макроса и ID - по щелчку на «?» (или всегда - в настройках).
        local mine = class == "CUSTOM"
        local open = not H or H.CodeShown(key, mine)
        code:SetShown(open)
        codeBg:SetShown(open)
        ids:SetShown(open)
        if help then
            help.body, help.class, help.codeKey, help.codeOpen = em.body, class, key, mine
            help:SetOpen(open)
        end

        local y = 12
        Place(title, 16, y)
        if tags then tags:Set(class, m, title) end
        y = y + title:GetStringHeight() + 4
        state:SetText(stateText)
        state:SetShown(stateText ~= "")
        if stateText ~= "" then
            Place(state, 16, y)
            y = y + state:GetStringHeight() + 4
        end
        y = y + 6
        if compact then
            -- [значок] описание; под описанием - кнопки одной строкой;
            -- текст макроса ниже, строка «без заклинаний» не нужна
            small:ClearAllPoints()
            small:SetPoint("TOPLEFT", 16, -y)
            about:SetWidth(wideW - 36 - 12)
            Place(about, 16 + 36 + 12, y + 1)
            local by = y + math.max(about:GetStringHeight() + 8, 14)
            for i, b in ipairs(buttons) do
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 16 + 36 + 12 + (i - 1) * (cbw + 6), -by)
            end
            y = math.max(y + 36, #buttons > 0 and (by + 22) or (by - 4)) + 10
            if open then
                code:SetText(HighlightIDs(ToDisplay(em.body)))
                Place(code, 22, y)
                y = y + code:GetStringHeight() + 12
                local idl = IDLine(em)
                local useful = #ItemIDs(em.body) > 0 or #SpellsOf(em) > 0
                ids:SetShown(useful)
                if useful then
                    ids:SetText(idl)
                    Place(ids, 16, y)
                    y = y + ids:GetStringHeight() + 8
                end
            end
            self:SetHeight(y + 2)
            return y + 2
        end
        -- Левая колонка: картинка и кнопки, правая - зачем макрос.
        if art then
            art:ClearAllPoints()
            art:SetPoint("TOPLEFT", 16, -y)
        end
        for i, b in ipairs(buttons) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 16 + ((i - 1) % 2) * (bw + 6), -(y + artH + 6 + math.floor((i - 1) / 2) * 26))
        end
        Place(about, textX, y + 4)
        y = y + math.max(artH + 6 + buttonsH, about:GetStringHeight() + 8) + 14
        if open then
            code:SetText(HighlightIDs(ToDisplay(em.body)))
            ids:SetText(IDLine(em))
            Place(code, 22, y)
            y = y + code:GetStringHeight() + 14
            Place(ids, 16, y)
            y = y + ids:GetStringHeight() + 12
        end
        local learn = H and H.Opt("learn")
        explain:SetShown(learn and true or false)
        if learn then
            explain:SetText(H.ExplainText(em.body, class))
            Place(explain, 16, y - 2)
            y = y + explain:GetStringHeight() + 10
        end
        self:SetHeight(y)
        return y
    end
    return row
end

local function BuildPage(class, list, key, rec, label)
    local page = CreateFrame("Frame", nil, frame.child)
    page:SetPoint("TOPLEFT")
    local width = frame.child:GetWidth()
    page:SetWidth(width)
    page.rows = {}
    -- «Рекомендации»: шапка, как у «Зачем макросы».
    local header
    if rec then
        header = PageHeader(page, width)
        header:Set(class == "GENERAL" and T("Рекомендации для всех классов") or (T("Рекомендации: ") .. ClassName(class)),
            T("Самые полезные макросы для старта: какую проблему решает каждый, что делает и когда жать. Значок макроса перетащи на панель или нажми «Добавить»."))
    end
    for _, m in ipairs(list) do
        -- Общий макрос во вкладке «Рекомендации» класса остаётся общим (m.homeClass).
        local home = m.homeClass or class
        RequestSpells(m.body)
        RequestSpells(Effective(home, m).body)
        local row = BuildRow(page, home, m, width - 20, rec)
        row.filterEntry = { class = home, m = m }
        page.rows[#page.rows + 1] = row
    end
    function page:Layout()
        -- Книга заклинаний могла измениться: кто выучен, кто откроется позже.
        if ns.Helper and ns.Helper.ScanBook then ns.Helper.ScanBook() end
        local y = header and -header:Layout(16) or -10
        -- «Только доступные макросы»: без единого выученного заклинания - скрыть
        local H = ns.Helper
        local readyOnly = H and H.Opt("readyOnly")
        for _, row in ipairs(self.rows) do
            if readyOnly and row.filterEntry and H.TipState(row.filterEntry) == "later" then
                row:Hide()
            else
                row:Show()
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 10, y)
                y = y - row:Fill() - ns.S.gap
            end
        end
        self:SetHeight(-y)
        return -y
    end
    pages[key] = page
    return page
end

-- Перерисовать текущую страницу, не сбрасывая прокрутку.
local function Relayout()
    if not (frame and currentKey and pages[currentKey]) then return end
    local pos = frame.scroll:GetVerticalScroll()
    local h = pages[currentKey]:Layout()
    frame.child:SetHeight(h)
    frame.scroll:SetVerticalScroll(math.min(pos, math.max(0, h - frame.scroll:GetHeight())))
end
ns.Relayout = Relayout

-------------------------------------------------------------------------------
--  Значок макроса: окно игры «Смена названия/значка»
-------------------------------------------------------------------------------
-- «?» = авто: игра покажет значок первого заклинания (#showtooltip).
local function NormalizeIcon(tex)
    if tex == nil or tex == QUESTION or tex == "" then return nil end
    if type(tex) == "string" and tex:upper():find("INV_MISC_QUESTIONMARK", 1, true) then return nil end
    return tex
end

local iconPopup
local function OpenIconPicker(icon, name, onDone)
    if not (type(IconSelectorPopupFrameTemplateMixin) == "table" and type(IconDataProviderMixin) == "table"
        and CreateAndInitFromMixin and IconDataProviderExtraType and GenerateClosure) then
        Print(T("выбор значка недоступен в этой версии игры."))
        return
    end
    if not iconPopup then
        local p = CreateFrame("Frame", "MacroCoachIconPopup", UIParent, "IconSelectorPopupFrameTemplate")
        if type(p.BorderBox) ~= "table" then return end
        p:SetFrameStrata("DIALOG")
        p:SetToplevel(true)
        p:EnableMouse(true)
        p:SetClampedToScreen(true)
        p:Hide()
        p.BorderBox.EditBoxHeaderText:SetText(T("Название макроса:"))
        function p:OkayButton_OnClick()
            IconSelectorPopupFrameTemplateMixin.OkayButton_OnClick(self)
            local tex = self.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture()
            local text = (self.BorderBox.IconSelectorEditBox:GetText() or ""):gsub("\"", "")
            if self.onDone then self.onDone(NormalizeIcon(tex), strtrim(text)) end
        end
        p:HookScript("OnHide", function(self)
            if self.iconDataProvider then
                self.iconDataProvider:Release()
                self.iconDataProvider = nil
            end
        end)
        tinsert(UISpecialFrames, "MacroCoachIconPopup")
        iconPopup = p
    end
    local p = iconPopup
    p.onDone = onDone
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", frame, "TOPRIGHT", 36, 0)
    p.iconDataProvider = p.iconDataProvider or CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.Spellbook)
    p:Show()
    p:SetIconFilter(IconSelectorPopupFrameIconFilterTypes.All)
    local box = p.BorderBox.IconSelectorEditBox
    box:SetText(name or "")
    box:HighlightText()
    local cur = icon or QUESTION
    p.IconSelector:SetSelectedIndex(p:GetIndexOfIcon(cur))
    p.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(cur)
    p.IconSelector:SetSelectionsDataProvider(GenerateClosure(p.GetIconByIndex, p), GenerateClosure(p.GetNumIcons, p))
    p.IconSelector:ScrollToSelectedIndex()
    p:SetSelectedIconText()
    p.IconSelector:SetSelectedCallback(function(_, tex)
        local area = p.BorderBox.SelectedIconArea
        area.SelectedIconButton:SetIconTexture(tex)
        if type(ICON_SELECTION_CLICK) == "string" then
            area.SelectedIconText.SelectedIconDescription:SetText(ICON_SELECTION_CLICK)
            area.SelectedIconText.SelectedIconDescription:SetFontObject(GameFontHighlightSmall)
        end
    end)
end

-- Кнопка значка: ЛКМ - выбрать, ПКМ - авто.
local function IconButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(32, 32)
    local slot = b:CreateTexture(nil, "BACKGROUND")
    slot:SetTexture("Interface\\Spellbook\\UI-Spellbook-SpellBackground")
    slot:SetSize(56, 56)
    slot:SetPoint("TOPLEFT", -3, 3)
    b.tex = b:CreateTexture(nil, "BORDER")
    b.tex:SetAllPoints()
    local border = b:CreateTexture(nil, "ARTWORK")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetSize(54, 54)
    border:SetPoint("CENTER")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            self:SetIcon(nil)
        else
            onClick(self)
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(T("Значок макроса"))
        GameTooltip:AddLine(T("Левый клик: выбрать значок и название."), 1, 1, 1, true)
        GameTooltip:AddLine(T("Правый клик: значок первого заклинания."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- value - выбранный значок (nil - авто), auto - что показать для «авто».
    function b:SetIcon(icon, auto)
        self.value = NormalizeIcon(icon)
        if auto then self.auto = auto end
        self.tex:SetTexture(self.value or self.auto or QUESTION)
    end
    return b
end

-------------------------------------------------------------------------------
--  Редактор макроса (на месте списка)
-------------------------------------------------------------------------------
local function BuildEditor()
    local area = frame.page
    local INNER = PAGE_W - 20 - 32
    local e = CreateFrame("Frame", nil, area, "BackdropTemplate")
    e:SetPoint("TOPLEFT", 10, -10)
    e:SetPoint("BOTTOMRIGHT", -10, 10)
    Card(e)
    e:SetFrameLevel(area:GetFrameLevel() + 20)
    e:EnableMouse(true)
    e:Hide()

    e.title = Text(e, "SystemFont_Large", "GameFontNormalLarge", GOLD)
    e.title:SetPoint("TOPLEFT", 16, -14)
    e.title:SetWidth(INNER)

    local nameLabel = Text(e, "SystemFont_Med2", "GameFontHighlight", GOLD)
    nameLabel:SetPoint("TOPLEFT", 16, -46)
    nameLabel:SetText(T("Название (до 16 символов):"))
    local name = CreateFrame("EditBox", nil, e, "InputBoxTemplate")
    name:SetSize(240, 22)
    name:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -4)
    name:SetAutoFocus(false)
    name:SetMaxLetters(16)
    e.name = name
    local iconLabel = Text(e, "SystemFont_Med2", "GameFontHighlight", GOLD)
    iconLabel:SetPoint("LEFT", name, "RIGHT", 24, 0)
    iconLabel:SetText(T("Значок:"))
    e.iconBtn = IconButton(e, function(btn)
        OpenIconPicker(btn.value, name:GetText(), function(icon, newName)
            btn:SetIcon(icon)
            if newName and newName ~= "" then name:SetText(newName) end
        end)
    end)
    e.iconBtn:SetPoint("LEFT", iconLabel, "RIGHT", 8, 0)

    local bodyLabel = Text(e, "SystemFont_Med2", "GameFontHighlight", GOLD)
    bodyLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -40)
    bodyLabel:SetText(T("Текст макроса:"))

    -- Поле текста, как в окне макросов игры
    local box = CreateFrame("Frame", nil, e, "TooltipBackdropTemplate")
    box:SetPoint("TOPLEFT", bodyLabel, "BOTTOMLEFT", -2, -6)
    box:SetSize(INNER, 160)
    local sf = CreateFrame("ScrollFrame", "MacroCoachEditScroll", box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -30, 8)
    local body = CreateFrame("EditBox", nil, sf)
    body:SetMultiLine(true)
    body:SetAutoFocus(false)
    body:SetFontObject(GameFontHighlight)
    body:SetWidth(INNER - 40)
    body:SetHeight(144)
    sf:SetScrollChild(body)
    e.body = body
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() body:SetFocus() end)
    if type(sf.ScrollBar) ~= "table" then
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self, d)
            local range = self:GetVerticalScrollRange()
            self:SetVerticalScroll(math.min(range, math.max(0, self:GetVerticalScroll() - d * 20)))
        end)
    end
    if ScrollingEdit_OnCursorChanged and ScrollingEdit_OnUpdate then
        body:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        body:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, sf) end)
    end
    body:SetScript("OnEscapePressed", body.ClearFocus)
    name:SetScript("OnEscapePressed", name.ClearFocus)
    name:SetScript("OnEnterPressed", function() body:SetFocus() end)
    name:SetScript("OnTabPressed", function() body:SetFocus() end)

    e.count = Text(e, "SystemFont_Med1", "GameFontHighlightSmall", LIGHT)
    e.count:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", -2, -6)
    e.count:SetJustifyH("RIGHT")
    local hint = Text(e, "SystemFont_Med1", "GameFontHighlightSmall", GREY, true)
    hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -6)
    hint:SetWidth(INNER - 160)
    hint:SetText(T("Заклинания пишутся по ID: {17364}, а конкретный ранг так: {r:8042}. При добавлении в игру ID превратятся в названия, потому что /cast понимает только их. Предметы: /use item:ID. Можно вставить макрос из английского гайда: названия заклинаний переведутся сами."))
    e.orig = Text(e, "SystemFont_Med1", "GameFontHighlightSmall", LIGHT, true)
    e.orig:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)
    e.orig:SetWidth(INNER - 4)

    local save = CreateFrame("Button", nil, e, "UIPanelButtonTemplate")
    save:SetSize(120, 22)
    save:SetPoint("BOTTOMLEFT", 16, 14)
    save:SetText(T("Сохранить"))
    local cancel = CreateFrame("Button", nil, e, "UIPanelButtonTemplate")
    cancel:SetSize(100, 22)
    cancel:SetPoint("LEFT", save, "RIGHT", 6, 0)
    cancel:SetText(T("Отмена"))
    local reset = CreateFrame("Button", nil, e, "UIPanelButtonTemplate")
    reset:SetSize(170, 22)
    reset:SetPoint("BOTTOMRIGHT", -16, 14)
    reset:SetText(T("Вернуть исходный"))
    local toBuilder = CreateFrame("Button", nil, e, "UIPanelButtonTemplate")
    toBuilder:SetSize(170, 22)
    toBuilder:SetPoint("BOTTOMRIGHT", -16, 14)
    toBuilder:SetText(T("Конструктор"))
    toBuilder:Hide()
    e.save, e.reset, e.toBuilder = save, reset, toBuilder

    -- Текст поля -> хранимый вид: {ID} и английские названия -> {s:ID}.
    local function Stored(raw)
        local stored = ToStored(raw)
        if ns.Helper then stored = ns.Helper.Translate(stored).text end
        return stored
    end
    local limitFmt = T("Символы: %d/255")
    function e.Update()
        local raw = body:GetText() or ""
        local text, missing = Render(Stored(raw))
        local n = CharCount(text)
        local bad = n > MAX_CHARS or missing or strtrim(raw) == ""
        local msg = limitFmt:format(n)
        if missing then msg = T("неизвестный ID: ") .. msg end
        e.count:SetText(msg)
        if bad then
            e.count:SetTextColor(1, 0.25, 0.25)
        else
            e.count:SetTextColor(LIGHT[1], LIGHT[2], LIGHT[3])
        end
        save:SetEnabled(not bad)
        e.iconBtn:SetIcon(e.iconBtn.value, FirstIcon({ body = Stored(raw), icon = e.autoIcon }))
    end
    body:SetScript("OnTextChanged", function(self, user)
        if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(self, sf) end
        if user then RequestSpells(Stored(self:GetText() or "")) end
        e.Update()
    end)

    -- Свой макрос: текст разбирается в строки конструктора.
    local function CustomFromText()
        local m = e.model
        m.name = strtrim(name:GetText() or "")
        m.icon = e.iconBtn.value
        B.Parse(Stored((body:GetText() or ""):gsub("%s+$", "")), m)
        return m
    end
    toBuilder:SetScript("OnClick", function()
        local m = CustomFromText()
        e:Hide()
        OpenBuilder(e.entry, m)
    end)
    save:SetScript("OnClick", function()
        if e.mode == "custom" then
            if SaveCustom(e.entry, CustomFromText()) then
                e:Hide()
                RefreshCustom()
            end
            return
        end
        local class, m = e.class, e.m
        local before = Effective(class, m)
        local defName = Loc(class, m)
        local newName = strtrim(name:GetText() or "")
        if newName == "" or newName == defName or newName == m.name then newName = nil end
        local raw = Stored((body:GetText() or ""):gsub("%s+$", ""))
        local key = Key(class, m)
        local icon = e.iconBtn.value
        -- Исходный текст с учётом безопасного лечения - тоже не правка.
        local base = ns.SafeBody and ns.SafeBody(m.body) or m.body
        if not newName and (raw == m.body or raw == base or raw == (Render(m.body)) or raw == (Render(base))) and not icon then
            DB().edits[key] = nil
        else
            local after = newName or defName
            DB().edits[key] = { name = newName, body = raw, icon = icon,
                prev = before.name ~= after and before.name or before.prev }
        end
        e:Hide()
        SyncGameMacro(before, Effective(class, m))
        Relayout()
    end)
    cancel:SetScript("OnClick", function() e:Hide() end)
    -- «Вернуть исходный»: второе нажатие подтверждает.
    reset:SetScript("OnClick", function(self)
        if not self.armed then
            self.armed = true
            self:SetText(T("Точно вернуть?"))
            return
        end
        local before = Effective(e.class, e.m)
        DB().edits[Key(e.class, e.m)] = nil
        e:Hide()
        SyncGameMacro(before, Effective(e.class, e.m))
        Relayout()
    end)
    e:SetScript("OnShow", function() frame.scroll:Hide() end)
    e:SetScript("OnHide", function()
        body:ClearFocus()
        name:ClearFocus()
        reset.armed = nil
        reset:SetText(T("Вернуть исходный"))
        if not (builder and builder:IsShown()) then frame.scroll:Show() end
    end)
    return e
end

OpenEditor = function(class, m)
    editor = editor or BuildEditor()
    if builder then builder:Hide() end
    local em = Effective(class, m)
    local text = ToDisplay(em.body)
    editor.mode, editor.class, editor.m = "preset", class, m
    editor.autoIcon = m.icon
    editor.iconBtn:SetIcon(DB().edits[Key(class, m)] and DB().edits[Key(class, m)].icon, QUESTION)
    editor.reset:Show()
    editor.toBuilder:Hide()
    editor.title:SetText(T("Изменить: ") .. select(2, Loc(class, m)))
    editor.name:SetText(em.name)
    editor.body:SetText(text)
    editor.orig:SetText("|cffffd100" .. T("Исходный текст:") .. "|r\n" .. ToDisplay(ns.SafeBody and ns.SafeBody(m.body) or m.body))
    editor.reset:SetEnabled(em.edited == true)
    editor:Show()
    editor.Update()
    editor.body:SetFocus()
end

-- Свой макрос текстом: entry - сохранённый (nil - новый), model - черновик.
OpenCustomText = function(entry, model)
    editor = editor or BuildEditor()
    if builder then builder:Hide() end
    editor.mode, editor.entry, editor.model = "custom", entry, model
    editor.autoIcon = nil
    editor.title:SetText(entry and (T("Изменить текстом: ") .. entry.name) or T("Новый макрос текстом"))
    editor.name:SetText(model.name or "")
    editor.body:SetText(ToDisplay(B.Build(model)))
    editor.orig:SetText("")
    editor.reset:Hide()
    editor.toBuilder:Show()
    editor.iconBtn:SetIcon(model.icon, QUESTION)
    editor:Show()
    editor.Update()
    editor.body:SetFocus()
end
-------------------------------------------------------------------------------
--  Свои макросы: шаблоны, сохранение
-------------------------------------------------------------------------------
local function TV(target, conds, arg)
    local v = B.NewVariant(arg)
    v.target, v.conds = target or "", conds or {}
    return v
end
local function TL(kind, variants, fields)
    local l = B.NewLine(kind)
    if variants then l.variants = variants end
    for k, v in pairs(fields or {}) do l[k] = v end
    return l
end
local function Template(name, desc, lines)
    return function()
        local m = B.New()
        m.name, m.desc, m.lines = T(name), T(desc), lines()
        return m
    end
end

B.TEMPLATES = {
    { label = "Пустой макрос", desc = "Одна строка «Применить заклинание», дальше сам.", make = function() return B.New() end },
    { label = "Лечение по наведению", desc = "Лечит союзника под курсором. Если там никого, то цель, а если и её нет, то тебя. Перетащи лечащее заклинание в первое поле.",
      make = Template("Лечение", "Лечит союзника под курсором, иначе цель, иначе себя.", function()
          return { TL("cast", { TV("mouseover", { help = 1, dead = 2 }), TV("", { help = 1, dead = 2 }), TV("player") }) }
      end) },
    { label = "По врагу под курсором", desc = "Заклинание по врагу под курсором, а если там никого, то по цели. Свою цель не меняешь.",
      make = Template("По наведению", "По врагу под курсором, иначе по цели.", function()
          return { TL("cast", { TV("mouseover", { harm = 1, dead = 2 }), TV("") }) }
      end) },
    { label = "По фокусу, иначе по цели", desc = "Заклинание по врагу в фокусе, а если фокуса нет, то по цели. Удобно для контроля и прерываний.",
      make = Template("По фокусу", "По врагу в фокусе, иначе по цели.", function()
          return { TL("cast", { TV("focus", { harm = 1, dead = 2 }), TV("") }) }
      end) },
    { label = "Прервать и применить", desc = "Обрывает твой каст и сразу применяет заклинание. Подходит для прерываний.",
      make = Template("Прерывание", "Обрывает свой каст и сразу применяет заклинание.", function()
          return { TL("stopcasting"), TL("cast") }
      end) },
    { label = "Атака + заклинание", desc = "Включает автоатаку и применяет заклинание.",
      make = Template("Атака", "Автоатака и заклинание.", function() return { TL("startattack"), TL("cast") } end) },
    { label = "Разное на Shift и Ctrl", desc = "С Shift одно заклинание, с Ctrl второе, без клавиш третье. Впиши все три.",
      make = Template("Модификаторы", "Shift, Ctrl и без клавиш: три разных заклинания.", function()
          return { TL("cast", { TV("", { ["mod:shift"] = 1 }), TV("", { ["mod:ctrl"] = 1 }), TV("") }) }
      end) },
    { label = "Последовательность", desc = "Каждое нажатие применяет следующее заклинание из списка. При смене цели всё сначала.",
      make = Template("Очередь", "Заклинания по очереди, при смене цели всё сначала.", function()
          return { TL("castsequence", nil, { reset = "target" }) }
      end) },
    { label = "В точку под курсором", desc = "Заклинание по площади сразу в точку под курсором, без круга выбора.",
      make = Template("Под курсор", "Заклинание по площади сразу под курсор.", function()
          return { TL("cast", { TV("cursor") }) }
      end) },
    { label = "Аксессуары + заклинание", desc = "Оба аксессуара и сразу заклинание. Когда нужно много урона сразу.",
      make = Template("Рывок урона", "Оба аксессуара и заклинание.", function()
          return { TL("use", { TV("", nil, "13") }), TL("use", { TV("", nil, "14") }), TL("cast") }
      end) },
    { label = "Питомец атакует + заклинание", desc = "Питомец атакует твою цель, ты применяешь заклинание.",
      make = Template("Питомец", "Питомец атакует, ты применяешь заклинание.", function()
          return { TL("petattack"), TL("cast") }
      end) },
}

-- Сохраняет model в entry (или новым макросом). Возвращает true, если удалось.
SaveCustom = function(entry, model)
    -- скобки: gsub даёт ещё и число замен, а strtrim принял бы его за «что срезать»
    local name = strtrim(((model.name or ""):gsub("\"", "")))
    if name == "" then name = T("Мой макрос") end
    model.name = name
    for _, other in ipairs(CustomList()) do
        if other ~= entry and other.name == name then
            Print((T("свой макрос «%s» уже есть, выбери другое название.")):format(name))
            return false
        end
    end
    if CharCount((Render(B.Build(model)))) > MAX_CHARS then
        Print(T("макрос длиннее 255 символов, сократи его."))
        return false
    end
    if entry then
        local before = CustomMacro(entry)
        local oldName, oldPrev = entry.name, entry.prev
        wipe(entry)
        for k, v in pairs(model) do entry[k] = v end
        entry.prev = (oldName ~= name) and oldName or oldPrev
        SyncGameMacro(before, CustomMacro(entry))
    else
        model.prev = nil
        local list = CustomList()
        list[#list + 1] = model
        Print((T("свой макрос «%s» сохранён. Нажми «Добавить», чтобы поставить его на панель.")):format(name))
    end
    return true
end

-------------------------------------------------------------------------------
--  Конструктор своих макросов: окно
-------------------------------------------------------------------------------
local MAXV = 4 -- вариантов «иначе» в строке
local KEEP_OPEN = MenuResponse and MenuResponse.Refresh

local function Dropdown(parent, width)
    local d = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    d:SetWidth(width)
    return d
end

local function Setup(d, generator, text)
    if d.SetupMenu then d:SetupMenu(generator) end
    if text and d.OverrideText then d:OverrideText(text) end
end

-- Меню типов строк: группы как в EllesmereUI.
local function KindMenu(root, onPick)
    local sub
    for _, k in ipairs(B.KINDS) do
        if k.group then
            sub = root:CreateButton(T(k.group))
        elseif sub then
            local b = sub:CreateButton(T(k.label), function() onPick(k.key) end)
            if b and b.SetTooltip then
                b:SetTooltip(function(tooltip)
                    tooltip:SetText(T(k.label))
                    tooltip:AddLine(T(k.desc), 1, 1, 1, true)
                end)
            end
        end
    end
end

local function CondSummary(v)
    local parts = {}
    for _, c in ipairs(B.CONDS) do
        local x = v.conds[c.key]
        if x == 1 then
            parts[#parts + 1] = T(c.label)
        elseif x == 2 then
            parts[#parts + 1] = T("не ") .. T(c.label)
        end
    end
    if v.stance and v.stance ~= "" then parts[#parts + 1] = T("стойка ") .. v.stance end
    if v.extra and v.extra ~= "" then parts[#parts + 1] = v.extra end
    return #parts > 0 and table.concat(parts, ", ") or T("Без условий")
end

local function Glyph(parent, kind, tip)
    local files = {
        up = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-",
        down = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-",
        del = "Interface\\Buttons\\UI-GroupLoot-Pass-",
    }
    local base = files[kind]
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b:SetNormalTexture(base .. "Up")
    b:SetPushedTexture(base .. "Down")
    b:SetHighlightTexture(base .. "Highlight", "ADD")
    if kind ~= "del" then
        b:SetDisabledTexture(base .. "Disabled")
        for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
            local t = b[get](b)
            if t then t:SetTexCoord(0.2, 0.8, 0.25, 0.75) end
        end
    end
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Что лежит на курсоре: заклинание - {s:ID}, предмет - item:ID.
local function CursorToken()
    local kind, a, b, c = GetCursorInfo()
    if kind == "spell" then
        local id = c
        if not id and a and C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
            local info = C_SpellBook.GetSpellBookItemInfo(a, b)
            id = info and info.spellID
        end
        if id then return "{s:" .. id .. "}" end
    elseif kind == "item" and a then
        return "item:" .. a
    end
end

local function ArgBox(parent)
    local b = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    b:SetHeight(22)
    b:SetAutoFocus(false)
    b.ph = b:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    b.ph:SetPoint("LEFT", 2, 0)
    b.ph:SetPoint("RIGHT", -2, 0)
    b.ph:SetJustifyH("LEFT")
    b.ph:SetWordWrap(false)
    local function Ph(self) self.ph:SetShown((self:GetText() or "") == "" and not self:HasFocus()) end
    b:HookScript("OnEditFocusGained", Ph)
    b:HookScript("OnEditFocusLost", Ph)
    b:SetScript("OnEnterPressed", b.ClearFocus)
    local function Take(self)
        local token = CursorToken()
        if not token then return end
        ClearCursor()
        local cur = strtrim(self:GetText() or "")
        local text = ToDisplay(token)
        if self.list and cur ~= "" then text = cur .. ", " .. text end
        self:SetText(text)
        if self.onChange then self.onChange(text) end
        Ph(self)
    end
    b:SetScript("OnReceiveDrag", Take)
    b:HookScript("OnMouseDown", function(self) if GetCursorInfo() then Take(self) end end)
    b:SetScript("OnTextChanged", function(self, user)
        Ph(self)
        if user and self.onChange then self.onChange(self:GetText() or "") end
    end)
    function b:SetValue(text, ph)
        self:SetText(text or "")
        self.ph:SetText(ph or "")
        Ph(self)
    end
    return b
end

-- Карточка строки: все поля созданы заранее, Setup показывает нужные.
local function LineCard(parent)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    c:SetBackdrop(CARD)
    c:SetBackdropColor(0.1, 0.09, 0.08, 0.95)
    c:SetBackdropBorderColor(0.45, 0.36, 0.2, 1)
    c.num = Text(c, "GameFontNormalLarge", "GameFontNormal", GOLD)
    c.kind = Dropdown(c, 280)
    c.up = Glyph(c, "up", T("Строку выше"))
    c.down = Glyph(c, "down", T("Строку ниже"))
    c.del = Glyph(c, "del", T("Удалить строку"))
    c.desc = Text(c, "SystemFont_Med1", "GameFontHighlightSmall", GREY, true)
    c.rows = {}
    for i = 1, MAXV do
        local r = {}
        r.label = Text(c, "SystemFont_Med1", "GameFontHighlightSmall", GOLD)
        r.target = Dropdown(c, 160)
        r.cond = Dropdown(c, 160)
        r.arg = ArgBox(c)
        r.del = Glyph(c, "del", T("Убрать этот вариант"))
        c.rows[i] = r
    end
    c.chan = Dropdown(c, 150)
    c.resetLabel = Text(c, "SystemFont_Med1", "GameFontHighlightSmall", GOLD)
    c.resetLabel:SetText(T("Сброс:"))
    c.reset = ArgBox(c)
    c.reset:SetWidth(110)
    c.resetHint = Text(c, "SystemFont_Med1", "GameFontHighlightSmall", GREY, true)
    c.resetHint:SetText(T("target: при смене цели, 10: через 10 секунд без нажатий, combat: после боя"))
    c.addVar = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    c.addVar:SetSize(160, 22)
    c.addVar:SetText(T("+ Иначе (вариант)"))
    return c
end

local function HideCard(c)
    for _, r in ipairs(c.rows) do
        r.label:Hide()
        r.target:Hide()
        r.cond:Hide()
        r.arg:Hide()
        r.del:Hide()
    end
    c.chan:Hide()
    c.resetLabel:Hide()
    c.reset:Hide()
    c.resetHint:Hide()
    c.addVar:Hide()
end

local function BuildBuilder()
    local area = frame.page
    local INNER = PAGE_W - 20 - 32
    local e = CreateFrame("Frame", nil, area, "BackdropTemplate")
    e:SetPoint("TOPLEFT", 10, -10)
    e:SetPoint("BOTTOMRIGHT", -10, 10)
    Card(e)
    e:SetFrameLevel(area:GetFrameLevel() + 20)
    e:EnableMouse(true)
    e:Hide()

    e.title = Text(e, "SystemFont_Large", "GameFontNormalLarge", GOLD)
    e.title:SetPoint("TOPLEFT", 16, -14)
    e.title:SetWidth(INNER)

    local nameLabel = Text(e, "SystemFont_Med2", "GameFontHighlight", GOLD)
    nameLabel:SetPoint("TOPLEFT", 16, -50)
    nameLabel:SetText(T("Название:"))
    local name = CreateFrame("EditBox", nil, e, "InputBoxTemplate")
    name:SetSize(170, 22)
    name:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
    name:SetAutoFocus(false)
    name:SetMaxLetters(16)
    e.name = name
    local iconLabel = Text(e, "SystemFont_Med2", "GameFontHighlight", GOLD)
    iconLabel:SetPoint("LEFT", name, "RIGHT", 18, 0)
    iconLabel:SetText(T("Значок:"))
    e.iconBtn = IconButton(e, function(btn)
        OpenIconPicker(btn.value, name:GetText(), function(icon, newName)
            btn:SetIcon(icon)
            if newName and newName ~= "" then name:SetText(newName) end
        end)
    end)
    e.iconBtn:SetPoint("LEFT", iconLabel, "RIGHT", 8, 0)
    local tip = CreateFrame("CheckButton", nil, e, "UICheckButtonTemplate")
    tip:SetSize(26, 26)
    tip:SetPoint("LEFT", e.iconBtn, "RIGHT", 16, 0)
    local tipLabel = Text(e, "SystemFont_Med1", "GameFontHighlightSmall", LIGHT, true)
    tipLabel:SetPoint("LEFT", tip, "RIGHT", 2, 0)
    tipLabel:SetWidth(150)
    tipLabel:SetText(T("Значок и подсказка первого заклинания"))
    e.tip = tip

    local descLabel = Text(e, "SystemFont_Med2", "GameFontHighlight", GOLD)
    descLabel:SetPoint("TOPLEFT", 16, -88)
    descLabel:SetText(T("Описание:"))
    local desc = CreateFrame("EditBox", nil, e, "InputBoxTemplate")
    desc:SetSize(INNER - 100, 22)
    desc:SetPoint("LEFT", descLabel, "RIGHT", 12, 0)
    desc:SetAutoFocus(false)
    e.desc = desc

    local linesLabel = Text(e, "SystemFont_Med2", "GameFontHighlight", GOLD)
    linesLabel:SetPoint("TOPLEFT", 16, -120)
    linesLabel:SetText(T("Строки макроса (выполняются сверху вниз за одно нажатие):"))

    local sf = CreateFrame("ScrollFrame", "MacroCoachBuilderScroll", e, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -142)
    sf:SetPoint("BOTTOMRIGHT", -42, 150)
    ScrollTrack(sf)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(INNER - 34, 10)
    sf:SetScrollChild(child)
    if type(sf.ScrollBar) ~= "table" then
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self, d)
            local range = self:GetVerticalScrollRange()
            self:SetVerticalScroll(math.min(range, math.max(0, self:GetVerticalScroll() - d * 60)))
        end)
    end
    e.child, e.sf = child, sf
    local cardW = INNER - 34

    -- Текст макроса: его можно править прямо здесь (для тех, кто привык
    -- писать макросы руками). Правка текста меняет строки сверху, и наоборот.
    local pvLabel = Text(e, "SystemFont_Med2", "GameFontHighlight", GOLD)
    pvLabel:SetPoint("TOPLEFT", sf, "BOTTOMLEFT", 4, -12)
    pvLabel:SetText(T("Текст макроса (можно править прямо здесь):"))
    e.count = Text(e, "SystemFont_Med1", "GameFontHighlightSmall", LIGHT)
    e.count:SetPoint("TOPRIGHT", sf, "BOTTOMRIGHT", 30, -12)
    e.count:SetJustifyH("RIGHT")
    local pvBg = CreateFrame("Button", nil, e)
    pvBg:SetPoint("TOPLEFT", pvLabel, "BOTTOMLEFT", 0, -4)
    pvBg:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", -16, 62)
    local pvTex = pvBg:CreateTexture(nil, "BACKGROUND")
    pvTex:SetAllPoints()
    pvTex:SetColorTexture(0, 0, 0, 0.7)
    local pvSf = CreateFrame("ScrollFrame", "MacroCoachBuilderTextScroll", pvBg, "UIPanelScrollFrameTemplate")
    pvSf:SetPoint("TOPLEFT", 6, -6)
    pvSf:SetPoint("BOTTOMRIGHT", -26, 6)
    local body = CreateFrame("EditBox", nil, pvSf)
    body:SetMultiLine(true)
    body:SetAutoFocus(false)
    body:SetFontObject(_G.SystemFont_Med1 or GameFontHighlightSmall)
    body:SetTextColor(0.65, 1, 0.65)
    body:SetWidth(INNER - 40)
    body:SetHeight(60)
    pvSf:SetScrollChild(body)
    if type(pvSf.ScrollBar) ~= "table" then
        pvSf:EnableMouseWheel(true)
        pvSf:SetScript("OnMouseWheel", function(self, d)
            local range = self:GetVerticalScrollRange()
            self:SetVerticalScroll(math.min(range, math.max(0, self:GetVerticalScroll() - d * 20)))
        end)
    end
    if ScrollingEdit_OnCursorChanged and ScrollingEdit_OnUpdate then
        body:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        body:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, pvSf) end)
    end
    body:SetScript("OnEscapePressed", body.ClearFocus)
    pvBg:SetScript("OnClick", function() body:SetFocus() end)
    e.body = body
    -- ID заклинаний - серой строкой под полем
    e.ids = Text(e, "SystemFont_Med1", "GameFontHighlightSmall", GREY, true)
    e.ids:SetPoint("TOPLEFT", pvBg, "BOTTOMLEFT", 4, -4)
    e.ids:SetWidth(INNER - 8)
    e.ids:SetWordWrap(false)

    local save = CreateFrame("Button", nil, e, "UIPanelButtonTemplate")
    save:SetSize(120, 22)
    save:SetPoint("BOTTOMLEFT", 16, 14)
    save:SetText(T("Сохранить"))
    local cancel = CreateFrame("Button", nil, e, "UIPanelButtonTemplate")
    cancel:SetSize(100, 22)
    cancel:SetPoint("LEFT", save, "RIGHT", 6, 0)
    cancel:SetText(T("Отмена"))
    e.save = save

    local cards, used = {}, 0
    local Layout -- ниже

    local function Sync()
        local m = e.model
        -- текст правили и сразу нажали «Сохранить»: взять его как есть
        if body:HasFocus() then
            local stored = ToStored(body:GetText() or "")
            if ns.Helper then stored = ns.Helper.Translate(stored).text end
            B.Parse(stored, m)
            tip:SetChecked(m.tooltip and true or false)
            body:ClearFocus()
        end
        m.name = strtrim(name:GetText() or "")
        m.desc = strtrim(desc:GetText() or "")
        m.tooltip = tip:GetChecked() and true or false
        m.icon = e.iconBtn.value
        return m
    end

    function e.Update()
        local m = e.model
        m.tooltip = tip:GetChecked() and true or false
        local stored = B.Build(m)
        local text, missing = Render(stored)
        -- пока игрок печатает в поле, его текст не перезаписываем
        if not body:HasFocus() then body:SetText(ToDisplay(stored)) end
        e.ids:SetText(stored == "" and T("Добавь строку сверху или напиши макрос в этом поле.") or IDLine({ body = stored }))
        local n = CharCount(text)
        local msg = T("Символы: %d/255"):format(n)
        if missing then msg = T("неизвестный ID: ") .. msg end
        e.count:SetText(msg)
        if n > MAX_CHARS then
            e.count:SetTextColor(1, 0.25, 0.25)
        else
            e.count:SetTextColor(LIGHT[1], LIGHT[2], LIGHT[3])
        end
        save:SetEnabled(n <= MAX_CHARS and #m.lines > 0)
        e.iconBtn:SetIcon(e.iconBtn.value, FirstIcon({ body = stored }))
    end

    local function Changed(structural)
        if structural then Layout() else e.Update() end
    end

    local function SetKind(line, key)
        local k = B.KIND[key]
        line.kind = key
        if not k.multi then
            for i = #line.variants, 2, -1 do table.remove(line.variants, i) end
        end
        if key == "targetmarker" and strtrim(line.variants[1].arg or "") == "" then line.variants[1].arg = "8" end
        if not k.arg then
            for _, v in ipairs(line.variants) do v.arg = "" end
        end
    end

    local function SetupCard(c, i, line)
        local m = e.model
        local k = B.KIND[line.kind] or B.KIND.raw
        HideCard(c)
        c:SetWidth(cardW)
        c.num:ClearAllPoints()
        c.num:SetPoint("TOPLEFT", 12, -12)
        c.num:SetText(i .. ".")
        c.kind:ClearAllPoints()
        c.kind:SetPoint("TOPLEFT", 40, -8)
        Setup(c.kind, function(_, root)
            KindMenu(root, function(key)
                SetKind(line, key)
                Changed(true)
            end)
        end, T(k.label))
        c.del:ClearAllPoints()
        c.del:SetPoint("TOPRIGHT", -10, -11)
        c.down:ClearAllPoints()
        c.down:SetPoint("RIGHT", c.del, "LEFT", -8, 0)
        c.up:ClearAllPoints()
        c.up:SetPoint("RIGHT", c.down, "LEFT", -2, 0)
        c.up:SetEnabled(i > 1)
        c.down:SetEnabled(i < #m.lines)
        c.up:SetScript("OnClick", function()
            m.lines[i], m.lines[i - 1] = m.lines[i - 1], m.lines[i]
            Changed(true)
        end)
        c.down:SetScript("OnClick", function()
            m.lines[i], m.lines[i + 1] = m.lines[i + 1], m.lines[i]
            Changed(true)
        end)
        c.del:SetScript("OnClick", function()
            table.remove(m.lines, i)
            Changed(true)
        end)
        c.desc:ClearAllPoints()
        c.desc:SetPoint("TOPLEFT", 14, -40)
        c.desc:SetWidth(cardW - 28)
        c.desc:SetText(T(k.desc))
        local y = 40 + c.desc:GetStringHeight() + 10

        local isSpell = k.arg == "spell" or k.arg == "spells"
        if k.key == "chat" then
            local v = line.variants[1]
            c.chan:ClearAllPoints()
            c.chan:SetPoint("TOPLEFT", 14, -y)
            c.chan:Show()
            Setup(c.chan, function(_, root)
                for _, ch in ipairs(B.CHANNELS) do
                    root:CreateRadio(T(ch.label), function() return line.chan == ch.value end, function()
                        line.chan = ch.value
                        e.Update()
                    end)
                end
            end)
            local a = c.rows[1].arg
            a:ClearAllPoints()
            a:SetPoint("TOPLEFT", 176, -y - 1)
            a:SetWidth(cardW - 176 - 14)
            a:Show()
            a.list = false
            a:SetValue(v.arg, T(k.ph))
            a.onChange = function(text) v.arg = text e.Update() end
            y = y + 30
        else
            local count = k.multi and math.min(#line.variants, MAXV) or 1
            for vi = 1, count do
                local v = line.variants[vi]
                local r = c.rows[vi]
                local x = 14
                if k.multi and #line.variants > 1 then
                    r.label:ClearAllPoints()
                    r.label:SetPoint("TOPLEFT", 14, -y - 5)
                    r.label:SetText(vi == 1 and T("если") or T("иначе"))
                    r.label:Show()
                    x = 62
                end
                if k.conds then
                    r.target:ClearAllPoints()
                    r.target:SetPoint("TOPLEFT", x, -y)
                    r.target:Show()
                    Setup(r.target, function(_, root)
                        root:CreateTitle(T("На кого"))
                        for _, t in ipairs(B.TARGETS) do
                            root:CreateRadio(T(t.label), function() return v.target == t.value end, function()
                                v.target = t.value
                                e.Update()
                            end)
                        end
                    end)
                    r.cond:ClearAllPoints()
                    r.cond:SetPoint("LEFT", r.target, "RIGHT", 6, 0)
                    r.cond:Show()
                    local cond = r.cond
                    Setup(cond, function(_, root)
                        root:CreateTitle(T("Условия (должны выполниться все)"))
                        for _, cd in ipairs(B.CONDS) do
                            local st = v.conds[cd.key]
                            local label = T(cd.label) .. (st == 1 and T(": да") or st == 2 and T(": нет") or "")
                            local sub = root:CreateButton(label)
                            if sub and sub.SetTooltip then
                                sub:SetTooltip(function(tooltip)
                                    tooltip:SetText(T(cd.label))
                                    tooltip:AddLine(T(cd.tip), 1, 1, 1, true)
                                end)
                            end
                            for _, opt in ipairs({ { 0, T("не важно") }, { 1, T("да") }, { 2, T("нет") } }) do
                                sub:CreateRadio(opt[2], function() return (v.conds[cd.key] or 0) == opt[1] end, function()
                                    v.conds[cd.key] = opt[1] ~= 0 and opt[1] or nil
                                    if cond.OverrideText then cond:OverrideText(CondSummary(v)) end
                                    e.Update()
                                    return KEEP_OPEN
                                end)
                            end
                        end
                        local forms = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
                        local sub = root:CreateButton(T("стойка / облик") .. (v.stance ~= "" and (": " .. v.stance) or ""))
                        local opts = { { "", T("любая") }, { "0", T("0: без стойки или обычный облик") } }
                        for fi = 1, forms do
                            local _, _, _, spellID = GetShapeshiftFormInfo(fi)
                            local fname = spellID and C_Spell.GetSpellName(spellID) or (T("Стойка ") .. fi)
                            opts[#opts + 1] = { tostring(fi), fi .. ": " .. fname }
                        end
                        for _, o in ipairs(opts) do
                            sub:CreateRadio(o[2], function() return v.stance == o[1] end, function()
                                v.stance = o[1]
                                if cond.OverrideText then cond:OverrideText(CondSummary(v)) end
                                e.Update()
                                return KEEP_OPEN
                            end)
                        end
                        root:CreateDivider()
                        root:CreateButton(T("Сбросить условия"), function()
                            wipe(v.conds)
                            v.stance, v.extra = "", ""
                            if cond.OverrideText then cond:OverrideText(CondSummary(v)) end
                            e.Update()
                        end)
                    end, CondSummary(v))
                    x = x + 332
                end
                if k.arg then
                    local a = r.arg
                    a:ClearAllPoints()
                    a:SetPoint("TOPLEFT", x + 6, -y - 1)
                    local w = cardW - x - 6 - 14 - ((k.multi and #line.variants > 1) and 24 or 0)
                    a:SetWidth(math.max(80, w))
                    a:Show()
                    a.list = k.arg == "spells"
                    local ph = T(k.ph)
                    if vi > 1 and k.arg == "spell" then ph = T("пусто: то же заклинание") end
                    a:SetValue(isSpell and ToDisplay(v.arg or "") or (v.arg or ""), ph)
                    a.onChange = function(text)
                        v.arg = isSpell and ToStored(text) or text
                        if isSpell then RequestSpells(v.arg) end
                        e.Update()
                    end
                end
                if k.multi and #line.variants > 1 then
                    r.del:ClearAllPoints()
                    r.del:SetPoint("TOPRIGHT", -12, -y - 3)
                    r.del:Show()
                    r.del:SetScript("OnClick", function()
                        table.remove(line.variants, vi)
                        Changed(true)
                    end)
                end
                y = y + 32
            end
        end
        if k.reset then
            c.resetLabel:ClearAllPoints()
            c.resetLabel:SetPoint("TOPLEFT", 14, -y - 5)
            c.resetLabel:Show()
            c.reset:ClearAllPoints()
            c.reset:SetPoint("TOPLEFT", 74, -y)
            c.reset:Show()
            c.reset.list = false
            c.reset:SetValue(line.reset or "", "target")
            c.reset.onChange = function(text)
                line.reset = strtrim(text)
                e.Update()
            end
            c.resetHint:ClearAllPoints()
            c.resetHint:SetPoint("LEFT", c.reset, "RIGHT", 10, 0)
            c.resetHint:SetWidth(cardW - 74 - 110 - 30)
            c.resetHint:Show()
            y = y + 32
        end
        if k.multi and #line.variants < MAXV then
            c.addVar:ClearAllPoints()
            c.addVar:SetPoint("TOPLEFT", 12, -y)
            c.addVar:Show()
            c.addVar:SetScript("OnClick", function()
                line.variants[#line.variants + 1] = B.NewVariant()
                Changed(true)
            end)
            c.addVar:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(T("Вариант «иначе»"))
                GameTooltip:AddLine(T("Если условия первого варианта не выполнены, сработает следующий. Например: если под курсором союзник, лечить его, а иначе себя."), 1, 1, 1, true)
                GameTooltip:Show()
            end)
            c.addVar:SetScript("OnLeave", function() GameTooltip:Hide() end)
            y = y + 30
        end
        c:SetHeight(y + 8)
        return c:GetHeight()
    end

    e.addLine = Dropdown(child, 240)
    e.empty = Text(child, "SystemFont_Med2", "GameFontHighlight", GREY, true)
    e.empty:SetWidth(cardW)
    e.empty:SetText(T("Строк пока нет. Нажми «+ Добавить строку» и выбери, что должен делать макрос."))

    Layout = function()
        local m = e.model
        for i = 1, used do cards[i]:Hide() end
        used = 0
        local y = 0
        for i, line in ipairs(m.lines) do
            used = used + 1
            local c = cards[used] or LineCard(child)
            cards[used] = c
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 0, -y)
            c:Show()
            y = y + SetupCard(c, i, line) + 8
        end
        e.empty:ClearAllPoints()
        e.empty:SetPoint("TOPLEFT", 4, -y - 4)
        e.empty:SetShown(#m.lines == 0)
        if #m.lines == 0 then y = y + 40 end
        e.addLine:ClearAllPoints()
        e.addLine:SetPoint("TOPLEFT", 0, -y)
        Setup(e.addLine, function(_, root)
            KindMenu(root, function(key)
                local line = B.NewLine(key)
                m.lines[#m.lines + 1] = line
                Changed(true)
                C_Timer.After(0, function() sf:SetVerticalScroll(sf:GetVerticalScrollRange()) end)
            end)
        end, T("+ Добавить строку"))
        child:SetHeight(y + 40)
        e.Update()
    end
    e.Layout = Layout

    -- Правка текста: через полсекунды после ввода строки сверху
    -- пересобираются из текста ({ID} и английские названия понимаются).
    local pending = 0
    body:SetScript("OnTextChanged", function(self, user)
        if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(self, pvSf) end
        if not user then return end
        pending = pending + 1
        local mine = pending
        C_Timer.After(0.5, function()
            if mine ~= pending or not e:IsShown() then return end
            local stored = ToStored(self:GetText() or "")
            if ns.Helper then stored = ns.Helper.Translate(stored).text end
            RequestSpells(stored)
            B.Parse(stored, e.model)
            tip:SetChecked(e.model.tooltip and true or false)
            Layout()
        end)
    end)
    body:SetScript("OnEditFocusLost", function() e.Update() end)

    tip:SetScript("OnClick", function() e.Update() end)
    name:SetScript("OnEnterPressed", name.ClearFocus)
    desc:SetScript("OnEnterPressed", desc.ClearFocus)
    save:SetScript("OnClick", function()
        if SaveCustom(e.entry, Sync()) then
            e:Hide()
            RefreshCustom()
        end
    end)
    cancel:SetScript("OnClick", function() e:Hide() end)
    e:SetScript("OnShow", function() frame.scroll:Hide() end)
    e:SetScript("OnHide", function()
        name:ClearFocus()
        desc:ClearFocus()
        body:ClearFocus()
        if not (editor and editor:IsShown()) then frame.scroll:Show() end
    end)
    return e
end

-- entry - свой макрос (nil - новый), model - что показать (копия entry или шаблон).
OpenBuilder = function(entry, model)
    builder = builder or BuildBuilder()
    if editor then editor:Hide() end
    model = model or (entry and B.Copy(entry)) or B.New()
    if not model.lines then B.Parse("", model) end
    builder.entry, builder.model = entry, model
    builder.title:SetText(entry and (T("Конструктор: ") .. entry.name) or T("Новый макрос"))
    builder.name:SetText(model.name or "")
    builder.desc:SetText(model.desc or "")
    builder.tip:SetChecked(model.tooltip and true or false)
    builder.iconBtn:SetIcon(model.icon, QUESTION)
    builder:Show()
    builder.sf:SetVerticalScroll(0)
    builder.Layout()
end

-------------------------------------------------------------------------------
--  Страница «Мои макросы»: шапка с кнопками нового макроса, затем ваши макросы
-------------------------------------------------------------------------------
local function BuildCustomPage(key)
    local page = CreateFrame("Frame", nil, frame.child)
    page:SetPoint("TOPLEFT")
    local width = frame.child:GetWidth()
    page:SetWidth(width)
    local function NewMacro() Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); OpenBuilder(nil, B.New()) end

    -- Шапка, как у всех страниц: крупно и одна строка.
    local header = PageHeader(page, width)
    header:Set(T("Свои макросы"), T("Собери макрос из готовых строк - код писать не нужно."))

    -- Три способа начать - плитки, как строки подсказок EasyCraft: значок,
    -- что это и коротко зачем; подробно - при наведении.
    local function OpenTemplates(owner)
        local function gen(_, root)
            root:CreateTitle(T("Начать с шаблона"))
            for _, t in ipairs(B.TEMPLATES) do
                local b = root:CreateButton(T(t.label), function() OpenBuilder(nil, t.make()) end)
                if b and b.SetTooltip then
                    b:SetTooltip(function(tooltip)
                        tooltip:SetText(T(t.label))
                        tooltip:AddLine(T(t.desc), 1, 1, 1, true)
                    end)
                end
            end
        end
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(owner, gen)
        else
            ns.UI.Open("CUSTOM", 2) -- нет меню - шаблоны во вкладке «Как написать»
        end
    end
    local TILES = {
        { icon = "Interface\\Icons\\INV_Misc_Gear_01", title = T("Создать"), sub = T("в конструкторе"),
          tip = T("Выбери, что сделать, на кого и когда, - внизу сразу видно, что получится."), run = function() NewMacro() end },
        { icon = "Interface\\Icons\\INV_Misc_Book_09", title = T("Из шаблона"), sub = T("готовые заготовки"),
          tip = T("Лечение по наведению, прерывание, питомец и другие: останется подставить свои заклинания."), run = OpenTemplates },
        { icon = "Interface\\Icons\\INV_Misc_Note_01", title = T("Текстом"), sub = T("вставить из гайда"),
          tip = T("Вставь текст макроса, например из английского гайда: названия заклинаний переведутся сами."),
          run = function() OpenCustomText(nil, B.New()) end },
    }
    local tiles = {}
    local tileW = math.floor((width - 20 - 2 * 10) / 3)
    for i, d in ipairs(TILES) do
        local t = CreateFrame("Button", nil, page, "BackdropTemplate")
        Card(t)
        t:SetSize(tileW, 52)
        local hl = t:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 3, -3)
        hl:SetPoint("BOTTOMRIGHT", -3, 3)
        hl:SetColorTexture(1, 0.82, 0, 0.1)
        local slot = ns.Helper and ns.Helper.IconSlot and ns.Helper.IconSlot(t, 30)
        if slot then
            slot:SetPoint("LEFT", 12, 0)
            slot.tex:SetTexture(d.icon)
            slot:EnableMouse(false)
        end
        local title = Text(t, "SystemFont_Med3", "GameFontNormal", GOLD)
        title:SetPoint("TOPLEFT", 12 + 30 + 10, -10)
        title:SetText(d.title)
        local sub = Text(t, "SystemFont_Med1", "GameFontHighlightSmall", GREY)
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        sub:SetWidth(tileW - 12 - 30 - 10 - 8)
        sub:SetText(d.sub)
        t:SetScript("OnClick", function(self) Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); d.run(self) end)
        t:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(d.title)
            GameTooltip:AddLine(d.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tiles[i] = t
    end

    -- Ваши макросы: заголовок чернилами; пусто - одна тёмная строка
    local listHead = Text(page, "SystemFont_Large", "GameFontNormalLarge", INK)
    local emptyCard = CreateFrame("Frame", nil, page, "BackdropTemplate")
    Card(emptyCard)
    emptyCard:SetSize(width - 20, 44)
    local emptyIcon = ns.Helper and ns.Helper.IconSlot and ns.Helper.IconSlot(emptyCard, 24)
    if emptyIcon then
        emptyIcon:SetPoint("LEFT", 12, 0)
        emptyIcon.tex:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        emptyIcon.tex:SetDesaturated(true)
        emptyIcon:EnableMouse(false)
    end
    local empty = Text(emptyCard, "SystemFont_Med2", "GameFontHighlight", LIGHT)
    empty:SetPoint("LEFT", 12 + 24 + 10, 0)
    empty:SetText(T("Пока пусто: начни с «Создать» или шаблона."))
    page.rows = {}
    for _, entry in ipairs(CustomList()) do
        page.rows[#page.rows + 1] = BuildRow(page, "CUSTOM", entry, width - 20)
    end
    listHead:SetText(T("Твои макросы") .. (#page.rows > 0 and ("  |cff7a5a2a" .. #page.rows .. "|r") or ""))

    function page:Layout()
        local y = -header:Layout(16)
        for i, t in ipairs(tiles) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", 10 + (i - 1) * (tileW + 10), y)
        end
        y = y - 52 - 18
        listHead:ClearAllPoints()
        listHead:SetPoint("TOPLEFT", 20, y)
        y = y - listHead:GetStringHeight() - 10
        emptyCard:ClearAllPoints()
        emptyCard:SetPoint("TOPLEFT", 10, y)
        emptyCard:SetShown(#self.rows == 0)
        if #self.rows == 0 then y = y - 44 - 10 end
        for _, row in ipairs(self.rows) do
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 10, y)
            y = y - row:Fill() - ns.S.gap
        end
        self:SetHeight(-y)
        return -y
    end
    pages[key] = page
    return page
end

-------------------------------------------------------------------------------
--  Страница «Как написать»: короткие карточки по темам и шаблоны
-------------------------------------------------------------------------------
-- Разделы: steps - нумерованные шаги, text - абзацы, rows - { код, пояснение },
-- code - пример, note - серая подпись.
local GUIDE = {
    ruRU = {
        { title = "Свой макрос за 4 шага", steps = {
            "Нажми «Создать» или выбери шаблон.",
            "В строке выбери, что сделать, например «Применить заклинание».",
            "Перетащи заклинание из книги заклинаний в поле.",
            "«Сохранить», затем «Добавить» - и щёлкни по ячейке панели.",
          }, note = "Внизу конструктора сразу видно, что получится." },
        { title = "Что такое макрос", text = {
            "Несколько команд на одной кнопке: они срабатывают сверху вниз за одно нажатие.",
            "За одно нажатие - одно заклинание. Команды вроде /startattack срабатывают вместе с ним.",
          } },
        { title = "Главные команды", rows = {
            { "#showtooltip", "Первая строка: на кнопке видна подсказка заклинания." },
            { "/cast Название", "Применить заклинание." },
            { "/use Название", "Использовать предмет из сумок." },
            { "/use 13", "Аксессуар: 13 - верхний, 14 - нижний." },
            { "/startattack", "Включить автоатаку." },
            { "/stopcasting", "Оборвать свой каст (перед прерыванием)." },
            { "/petattack", "Питомец атакует твою цель." },
          } },
        { title = "Условия", text = {
            "Пишутся в [квадратных скобках] перед заклинанием. Не подошло - вариант пропускается.",
          }, rows = {
            { "[@mouseover]", "На того, кто под курсором." },
            { "[@player]", "На себя." },
            { "[help]  [harm]", "Цель - союзник. Цель - враг." },
            { "[nodead]", "Цель жива." },
            { "[combat]", "Ты в бою." },
            { "[mod:shift]", "Зажат Shift (так же ctrl и alt)." },
            { "[help,nodead]", "Через запятую - всё сразу." },
            { "[@mouseover][@player]", "Скобки подряд - первая подходящая." },
            { "[mod:shift] A; B", "С Shift - A, иначе - B." },
          } },
        { title = "Пример: по наведению", example = "mo" },
    },
    enUS = {
        { title = "Your own macro in 4 steps", steps = {
            "Press \"Create\" or pick a template.",
            "In a line, choose what to do, for example \"Cast a spell\".",
            "Drag a spell from your spellbook into the field.",
            "\"Save\", then \"Add\" - and click an action bar slot.",
          }, note = "The bottom of the builder shows the result right away." },
        { title = "What is a macro", text = {
            "A few commands on one button: they run top to bottom with one press.",
            "One press casts one spell. Commands like /startattack run along with it.",
          } },
        { title = "Main commands", rows = {
            { "#showtooltip", "First line: the button shows the spell tooltip." },
            { "/cast Name", "Cast a spell." },
            { "/use Name", "Use an item from your bags." },
            { "/use 13", "Trinket: 13 is the top one, 14 the bottom one." },
            { "/startattack", "Start auto attack." },
            { "/stopcasting", "Stop your own cast (before an interrupt)." },
            { "/petattack", "Your pet attacks your target." },
          } },
        { title = "Conditions", text = {
            "They go in [square brackets] before the spell. If one doesn't fit, that option is skipped.",
          }, rows = {
            { "[@mouseover]", "On whoever is under your cursor." },
            { "[@player]", "On yourself." },
            { "[help]  [harm]", "Target is friendly. Target is hostile." },
            { "[nodead]", "Target is alive." },
            { "[combat]", "You are in combat." },
            { "[mod:shift]", "Shift is held (ctrl and alt too)." },
            { "[help,nodead]", "Separated by commas - all at once." },
            { "[@mouseover][@player]", "Brackets in a row - the first that fits." },
            { "[mod:shift] A; B", "A with Shift, otherwise B." },
          } },
        { title = "Example: mouseover", example = "mo" },
    },
}

-- Пример «по наведению» - заклинанием своего класса: лекарям лечение
-- союзника, остальным - по врагу под курсором.
local function MouseoverExample()
    local D = ns.HelperData
    local _, class = UnitClass("player")
    local ex = D and D.EXAMPLE and (D.EXAMPLE[class] or D.EXAMPLE.SHAMAN)
    if not ex then return nil end
    if ex.moHelp then
        return "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] {s:" .. ex.mo .. "}",
            T("Лечит союзника под курсором. Никого нет - твою цель, а если и её нет, то тебя.")
    end
    return "#showtooltip\n/cast [@mouseover,harm,nodead][harm,nodead] {s:" .. ex.mo .. "}",
        T("Бьёт врага под курсором, не сбивая твою цель. Никого нет - по твоей цели.")
end

local CODE_GREEN = { 0.65, 1, 0.65 }
local CODE_W = 230

-- Карточка раздела гайда. Возвращает карточку с функцией Fit() -> высота.
local function GuideCard(parent, width, sec)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Card(card)
    card:SetWidth(width)
    local inner = width - 32
    local items = {}
    local title = Text(card, "SystemFont_Large", "GameFontNormalLarge", GOLD)
    title:SetText(sec.title)
    local function Add(fs, x, gap) items[#items + 1] = { fs = fs, x = x, gap = gap } end
    for i, step in ipairs(sec.steps or {}) do
        local fs = Text(card, "SystemFont_Med2", "GameFontHighlight", LIGHT, true)
        fs:SetWidth(inner - 22)
        fs:SetText(step)
        local num = Text(card, "SystemFont_Med2", "GameFontHighlight", GOLD)
        num:SetText(i .. ".")
        items[#items + 1] = { fs = fs, x = 22, gap = 6, num = num }
    end
    for _, para in ipairs(sec.text or {}) do
        local fs = Text(card, "SystemFont_Med2", "GameFontHighlight", LIGHT, true)
        fs:SetWidth(inner)
        fs:SetText(para)
        Add(fs, 0, 8)
    end
    for _, r in ipairs(sec.rows or {}) do
        local code = Text(card, "SystemFont_Med1", "GameFontHighlightSmall", CODE_GREEN, true)
        code:SetWidth(CODE_W)
        code:SetText(r[1])
        local fs = Text(card, "SystemFont_Med2", "GameFontHighlight", LIGHT, true)
        fs:SetWidth(inner - CODE_W - 16)
        fs:SetText(r[2])
        items[#items + 1] = { fs = fs, code = code, gap = 8 }
    end
    local codeBlock, codeBg
    local exCode = sec.code
    if sec.example == "mo" then
        local code, text = MouseoverExample()
        exCode = code
        if text then
            local fs = Text(card, "SystemFont_Med2", "GameFontHighlight", LIGHT, true)
            fs:SetWidth(inner)
            fs:SetText(text)
            Add(fs, 0, 8)
        end
    end
    if exCode then
        RequestSpells(exCode)
        codeBlock = Text(card, "SystemFont_Med1", "GameFontHighlightSmall", CODE_GREEN, true)
        codeBlock:SetWidth(inner - 12)
        -- как в игре: названия заклинаний, а не номера
        codeBlock:SetText(((Render(exCode)):gsub("|", "||")))
        codeBg = card:CreateTexture(nil, "ARTWORK")
        codeBg:SetColorTexture(0, 0, 0, 0.7)
        codeBg:SetPoint("TOPLEFT", codeBlock, "TOPLEFT", -6, 6)
        codeBg:SetPoint("BOTTOMRIGHT", codeBlock, "BOTTOMRIGHT", 6, -6)
    end
    local note
    if sec.note then
        note = Text(card, "SystemFont_Med1", "GameFontHighlightSmall", GREY, true)
        note:SetWidth(inner)
        note:SetText(sec.note)
    end
    function card:Fit()
        local y = 14
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", 16, -y)
        y = y + title:GetStringHeight() + 10
        if codeBlock then
            -- названия заклинаний могли догрузиться после первого показа
            codeBlock:SetText(((Render(exCode)):gsub("|", "||")))
            codeBlock:ClearAllPoints()
            codeBlock:SetPoint("TOPLEFT", 22, -(y + 6))
            y = y + codeBlock:GetStringHeight() + 22
        end
        for _, it in ipairs(items) do
            local h
            if it.code then
                it.code:ClearAllPoints()
                it.code:SetPoint("TOPLEFT", 16, -(y + 1))
                it.fs:ClearAllPoints()
                it.fs:SetPoint("TOPLEFT", 16 + CODE_W + 16, -y)
                h = math.max(it.code:GetStringHeight() + 1, it.fs:GetStringHeight())
            else
                it.fs:ClearAllPoints()
                it.fs:SetPoint("TOPLEFT", 16 + it.x, -y)
                if it.num then
                    it.num:ClearAllPoints()
                    it.num:SetPoint("TOPLEFT", 16, -y)
                end
                h = it.fs:GetStringHeight()
            end
            y = y + h + it.gap
        end
        if note then
            note:ClearAllPoints()
            note:SetPoint("TOPLEFT", 16, -(y + 2))
            y = y + note:GetStringHeight() + 8
        end
        self:SetHeight(y + 10)
        return y + 10
    end
    return card
end

local function BuildGuidePage(key)
    local page = CreateFrame("Frame", nil, frame.child)
    page:SetPoint("TOPLEFT")
    local width = frame.child:GetWidth()
    page:SetWidth(width)
    local header = PageHeader(page, width)
    header:Set(T("Как устроены макросы"), T("Коротко: как собрать свой макрос, главные команды и условия."))
    local cards = {}
    for _, sec in ipairs(ns.Pick(GUIDE)) do
        cards[#cards + 1] = GuideCard(page, width - 20, sec)
    end
    local tcard = CreateFrame("Frame", nil, page, "BackdropTemplate")
    Card(tcard)
    tcard:SetWidth(width - 20)
    local thead = Text(tcard, "SystemFont_Large", "GameFontNormalLarge", GOLD)
    thead:SetPoint("TOPLEFT", 16, -14)
    thead:SetText(T("Шаблоны: начни с готового"))
    local tnote = Text(tcard, "SystemFont_Med1", "GameFontHighlightSmall", GREY, true)
    tnote:SetPoint("TOPLEFT", thead, "BOTTOMLEFT", 0, -6)
    tnote:SetWidth(width - 20 - 32)
    tnote:SetText(T("Нажми на шаблон: откроется конструктор, останется перетащить свои заклинания."))
    local bw = math.floor((width - 20 - 32 - 10) / 2)
    for i, t in ipairs(B.TEMPLATES) do
        local b = CreateFrame("Button", nil, tcard, "UIPanelButtonTemplate")
        b:SetSize(bw, 22)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", 16 + col * (bw + 10), -70 - row * 30)
        b:SetText(T(t.label))
        b:SetScript("OnClick", function() OpenBuilder(nil, t.make()) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(T(t.label))
            GameTooltip:AddLine(T(t.desc), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local rows = math.ceil(#B.TEMPLATES / 2)
    function page:Layout()
        local y = -header:Layout(16)
        for _, c in ipairs(cards) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 10, y)
            y = y - c:Fit() - 10
        end
        tcard:ClearAllPoints()
        tcard:SetPoint("TOPLEFT", 10, y)
        local th = 70 + rows * 30 + 10
        tcard:SetHeight(th)
        y = y - th - 10
        self:SetHeight(-y)
        return -y
    end
    pages[key] = page
    return page
end

-------------------------------------------------------------------------------
--  Страница «Настройки»: названия макросов на панелях и очистка макросов
-------------------------------------------------------------------------------
local function SmallButton(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

function BuildOptionsPage(key)
    local page = CreateFrame("Frame", nil, frame.child)
    page:SetPoint("TOPLEFT")
    local width = frame.child:GetWidth()
    page:SetWidth(width)
    local inner = width - 20 - 32
    local header = PageHeader(page, width)
    header:Set(T("Настройки макросов"), T("Названия на панелях, подсказки и безопасность. Резервная копия и перенос - во вкладке «Импорт/экспорт»."))

    -- Названия на панелях
    local names = CreateFrame("Frame", nil, page, "BackdropTemplate")
    Card(names)
    names:SetWidth(width - 20)
    local nTitle = Text(names, "SystemFont_Large", "GameFontNormalLarge", GOLD)
    nTitle:SetPoint("TOPLEFT", 16, -14)
    nTitle:SetText(T("Названия макросов на панелях"))
    local nNote = Text(names, "SystemFont_Med1", "GameFontHighlightSmall", GREY, true)
    nNote:SetPoint("TOPLEFT", nTitle, "BOTTOMLEFT", 0, -6)
    nNote:SetWidth(inner)
    nNote:SetText(T("Подпись под значком макроса на всех панелях. Работает и с Bartender, ElvUI и похожими панелями."))
    local hide = CreateFrame("CheckButton", nil, names, "UICheckButtonTemplate")
    hide:SetSize(26, 26)
    hide:SetPoint("TOPLEFT", nNote, "BOTTOMLEFT", -4, -12)
    local hideLabel = Text(names, "SystemFont_Med2", "GameFontHighlight", LIGHT)
    hideLabel:SetPoint("LEFT", hide, "RIGHT", 4, 0)
    hideLabel:SetText(T("Скрыть названия макросов"))
    hide:SetScript("OnClick", function(self)
        DB().barNames.hide = self:GetChecked() and true or nil
        ns.ApplyBarNames()
    end)
    local sizeLabel = Text(names, "SystemFont_Med2", "GameFontHighlight", LIGHT)
    sizeLabel:SetPoint("TOPLEFT", hide, "BOTTOMLEFT", 4, -14)
    sizeLabel:SetText(T("Размер шрифта:"))
    local minus, plus, reset
    local value = Text(names, "SystemFont_Large", "GameFontNormalLarge", GOLD)
    value:SetJustifyH("CENTER")
    value:SetWidth(36)
    local function SetSize(v)
        DB().barNames.size = v
        ns.ApplyBarNames()
        page:Layout()
    end
    minus = SmallButton(names, "-", 28, function()
        SetSize(math.max(6, (DB().barNames.size or ns.DefaultNameSize()) - 1))
    end)
    minus:SetPoint("LEFT", sizeLabel, "RIGHT", 12, 0)
    value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    plus = SmallButton(names, "+", 28, function()
        SetSize(math.min(20, (DB().barNames.size or ns.DefaultNameSize()) + 1))
    end)
    plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
    reset = SmallButton(names, T("Как в игре"), 120, function() SetSize(nil) end)
    reset:SetPoint("LEFT", plus, "RIGHT", 12, 0)

    -- Безопасность и подсказки (настройки помощника, Helper.lua)
    local helpCard = CreateFrame("Frame", nil, page, "BackdropTemplate")
    Card(helpCard)
    helpCard:SetWidth(width - 20)
    local hTitle = Text(helpCard, "SystemFont_Large", "GameFontNormalLarge", GOLD)
    hTitle:SetPoint("TOPLEFT", 16, -14)
    hTitle:SetText(T("Безопасность и подсказки"))
    local HELP_OPTS = {
        { key = "altSelf", label = "Alt - лечение на себя", resync = true,
          note = "С зажатым Alt готовые макросы лечения по наведению лечат тебя. Без Alt, если под курсором никого, они лечат цель-союзника, иначе тебя." },
        { key = "showCode", label = "Показывать текст макросов",
          note = "Текст и ID заклинаний под каждым макросом сразу. Без этого - по значку-записке в углу карточки." },
        { key = "learn", label = "Режим «Учусь»",
          note = "Под каждым макросом - что делает каждая строка, простыми словами." },
        { key = "readyOnly", label = "Только доступные макросы",
          note = "Скрывает готовые макросы, для которых у тебя пока нет ни одного заклинания." },
        { key = "tips", label = "Подсказки после тренера",
          note = "Выучил новое заклинание - аддон пишет в чат, если появился полезный макрос или на панелях остался старый ранг." },
    }
    local helpChecks = {}
    for i, o in ipairs(HELP_OPTS) do
        local cb = CreateFrame("CheckButton", nil, helpCard, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        local label = Text(helpCard, "SystemFont_Med2", "GameFontHighlight", LIGHT)
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(T(o.label))
        local note = Text(helpCard, "SystemFont_Med1", "GameFontHighlightSmall", GREY, true)
        note:SetWidth(inner - 30)
        note:SetText(T(o.note))
        cb:SetScript("OnClick", function(self)
            if not ns.Helper then return end
            ns.Helper.SetOpt(o.key, self:GetChecked() and true or false)
            if o.resync then ns.Helper.ResyncReady() end
        end)
        helpChecks[i] = { cb = cb, note = note, key = o.key }
    end

    -- Резервная копия всех макросов игры (Backup.lua)
    local backupCard = CreateFrame("Frame", nil, page, "BackdropTemplate")
    Card(backupCard)
    backupCard:SetWidth(width - 20)
    local bTitle = Text(backupCard, "SystemFont_Large", "GameFontNormalLarge", GOLD)
    bTitle:SetPoint("TOPLEFT", 16, -14)
    bTitle:SetText(T("Резервная копия макросов"))
    local bNote = Text(backupCard, "SystemFont_Med1", "GameFontHighlightSmall", GREY, true)
    bNote:SetPoint("TOPLEFT", bTitle, "BOTTOMLEFT", 0, -6)
    bNote:SetWidth(inner)
    local bSave = SmallButton(backupCard, T("Сохранить копию"), 260, function()
        ns.Backup.Save()
        page:Layout()
    end)
    bSave:SetPoint("TOPLEFT", bNote, "BOTTOMLEFT", 0, -14)
    local bRestore = SmallButton(backupCard, T("Вернуть из копии"), 260, function() ns.Backup.Restore() end)
    bRestore:SetPoint("LEFT", bSave, "RIGHT", 10, 0)

    -- Макросы в игре
    local wipeCard = CreateFrame("Frame", nil, page, "BackdropTemplate")
    Card(wipeCard)
    wipeCard:SetWidth(width - 20)
    local wTitle = Text(wipeCard, "SystemFont_Large", "GameFontNormalLarge", GOLD)
    wTitle:SetPoint("TOPLEFT", 16, -14)
    wTitle:SetText(T("Очистить макросы в игре"))
    local wNote = Text(wipeCard, "SystemFont_Med1", "GameFontHighlightSmall", GREY, true)
    wNote:SetPoint("TOPLEFT", wTitle, "BOTTOMLEFT", 0, -6)
    wNote:SetWidth(inner)
    wNote:SetText(T("Удаляет макросы из окна /macro: общие (видны всем персонажам) или только этого персонажа. Готовые и свои макросы в аддоне останутся, их можно добавить снова."))
    local wipeShared = SmallButton(wipeCard, "", 260, function() ns.AskWipe(false) end)
    wipeShared:SetPoint("TOPLEFT", wNote, "BOTTOMLEFT", 0, -14)
    local wipeChar = SmallButton(wipeCard, "", 260, function() ns.AskWipe(true) end)
    wipeChar:SetPoint("LEFT", wipeShared, "RIGHT", 10, 0)
    local restoreShared = SmallButton(wipeCard, "", 260, function() ns.RestoreWiped(false) end)
    restoreShared:SetPoint("TOPLEFT", wipeShared, "BOTTOMLEFT", 0, -6)
    local restoreChar = SmallButton(wipeCard, "", 260, function() ns.RestoreWiped(true) end)
    restoreChar:SetPoint("TOPLEFT", wipeChar, "BOTTOMLEFT", 0, -6)

    function page:Layout()
        local cfg = DB().barNames
        hide:SetChecked(cfg.hide and true or false)
        value:SetText(tostring(cfg.size or ns.DefaultNameSize()))
        reset:SetEnabled(cfg.size ~= nil)
        local general, char = GetNumMacros()
        wipeShared:SetText((T("Удалить общие (%d)")):format(general or 0))
        wipeChar:SetText((T("Удалить персонажа (%d)")):format(char or 0))
        wipeShared:SetEnabled((general or 0) > 0)
        wipeChar:SetEnabled((char or 0) > 0)
        local backShared, backChar = ns.WipedCount(false), ns.WipedCount(true)
        restoreShared:SetText((T("Вернуть удалённые (%d)")):format(backShared))
        restoreChar:SetText((T("Вернуть удалённые (%d)")):format(backChar))
        restoreShared:SetShown(backShared > 0)
        restoreChar:SetShown(backChar > 0)
        local y = -header:Layout(16)
        names:ClearAllPoints()
        names:SetPoint("TOPLEFT", 10, y)
        local nh = 14 + nTitle:GetStringHeight() + 6 + nNote:GetStringHeight() + 12 + 26 + 14 + 24 + 18
        names:SetHeight(nh)
        y = y - nh - 10
        helpCard:ClearAllPoints()
        helpCard:SetPoint("TOPLEFT", 10, y)
        local hy = 14 + hTitle:GetStringHeight() + 10
        for _, h in ipairs(helpChecks) do
            h.cb:SetChecked(ns.Helper and ns.Helper.Opt(h.key) and true or false)
            h.cb:ClearAllPoints()
            h.cb:SetPoint("TOPLEFT", 12, -hy)
            h.note:ClearAllPoints()
            h.note:SetPoint("TOPLEFT", 46, -(hy + 26))
            hy = hy + 26 + h.note:GetStringHeight() + 10
        end
        helpCard:SetHeight(hy + 8)
        y = y - hy - 8 - 10
        local when, saved = ns.Backup.Info()
        local about = T("Сохраняет все макросы из окна /macro: общие и этого персонажа. Из копии можно вернуть текст изменённых макросов и удалённые макросы.")
        bNote:SetText(about .. "\n" .. (when and (T("Копия от %s: макросов %d.")):format(date("%d.%m.%Y %H:%M", when), saved) or T("Копии пока нет.")))
        bRestore:SetEnabled(when ~= nil)
        backupCard:ClearAllPoints()
        backupCard:SetPoint("TOPLEFT", 10, y)
        local bh = 14 + bTitle:GetStringHeight() + 6 + bNote:GetStringHeight() + 14 + 24 + 18
        backupCard:SetHeight(bh)
        y = y - bh - 10
        wipeCard:ClearAllPoints()
        wipeCard:SetPoint("TOPLEFT", 10, y)
        local wh = 14 + wTitle:GetStringHeight() + 6 + wNote:GetStringHeight() + 14 + 24 + 18
        if backShared > 0 or backChar > 0 then wh = wh + 30 end
        wipeCard:SetHeight(wh)
        y = y - wh - 10
        self:SetHeight(-y)
        return -y
    end
    pages[key] = page
    return page
end

-- Перестроить «Мои макросы» после сохранения или удаления. stay - не
-- переключаться на них (импорт и полученный макрос из другой вкладки).
RefreshCustom = function(stay)
    local p = pages["CUSTOM#1"]
    if p then
        p:Hide()
        pages["CUSTOM#1"] = nil
    end
    if frame and frame:IsShown() and (not stay or currentKey == "CUSTOM#1") then ShowClass("CUSTOM", 1) end
end


-------------------------------------------------------------------------------
--  Окно
-------------------------------------------------------------------------------
-- В заголовке - название аддона, дальше что открыто.
local function SetWindowTitle(text)
    text = "MacroCoach - " .. (text or "")
    if type(frame.TitleContainer) == "table" and frame.SetTitle then
        frame:SetTitle(text)
    elseif frame.titleText then
        frame.titleText:SetText(text)
    end
end

-- В портрете всегда значок аддона (класс - на вкладке справа и в заголовке).
local function SetPortrait()
    if type(frame.PortraitContainer) ~= "table" then return end
    frame:SetPortraitToAsset(ADDON_ICON)
    if frame.SetPortraitTexCoord then frame:SetPortraitTexCoord(0, 1, 0, 1) end
end

-- Размер вкладок один на всё окно: одна и та же надпись - одна и та же
-- ширина у всех классов, шрифт один. Длинное название обрезается
-- троеточием, целиком - в подсказке при наведении.
local TAB_PAD, TAB_GAP, TAB_TEXT_MAX = 12, 2, 100

local function SelectSpecTabs(class, tabs, spec)
    local pool = frame.specTabs
    for i, b in ipairs(pool) do
        local t = tabs[i]
        if t then
            local icon = SpecIcon(class, t.label)
            if icon then
                b.icon:SetTexCoord(0, 1, 0, 1)
                b.icon:SetTexture(icon)
            else
                SetClassIcon(b.icon, class)
            end
            local label = T(t.label)
            b.text:SetFontObject(GameFontNormal)
            b.text:SetWordWrap(false)
            b.text:SetWidth(0)
            b.text:SetText(label)
            local w = b.text:GetStringWidth() or 60
            b.full = w > TAB_TEXT_MAX and label or nil
            if b.full then w = TAB_TEXT_MAX end
            b.text:SetWidth(w + 1)
            b:SetWidth(9 + TAB_ICON + 5 + w + TAB_PAD)
            b:SetSelected(i == spec) -- после шрифта: он сбрасывает цвет
            b:Show()
        else
            b:Hide()
        end
    end
    for i = 2, #pool do
        pool[i]:ClearAllPoints()
        pool[i]:SetPoint("LEFT", pool[i - 1], "RIGHT", TAB_GAP, 0)
    end
end

ShowClass = function(class, spec)
    if editor then editor:Hide() end
    if builder then builder:Hide() end
    if ns.ClearSearch then ns.ClearSearch() end
    current = class
    local tabs = SpecTabs(class)
    if not spec then
        local _, playerClass = UnitClass("player")
        spec = selectedSpec[class] or (class == playerClass and PlayerSpecTab(tabs)) or 1
    end
    if spec > #tabs then spec = 1 end
    selectedSpec[class], currentSpec = spec, spec
    SelectSpecTabs(class, tabs, spec)

    local key = class .. "#" .. spec
    currentKey = key
    for k, p in pairs(pages) do p:SetShown(k == key) end
    local tab = tabs[spec]
    local page = pages[key] or (tab and tab.custom and BuildCustomPage(key)) or (tab and tab.guide and BuildGuidePage(key))
        or (tab and tab.options and BuildOptionsPage(key))
        or (tab and tab.helper and ns.BuildHelperPage and ns.BuildHelperPage(tab.helper, key))
        or BuildPage(class, tab and tab.list or {}, key, tab and tab.rec, tab and tab.label)
    page:Show()
    frame.child:SetHeight(page:Layout())
    frame.scroll:SetVerticalScroll(0)

    for _, t in ipairs(frame.classTabs) do t:SetChecked(t.class == class) end
    SetWindowTitle(class == "GENERAL" and T("Готовые макросы для всех классов") or class == "CUSTOM" and T("Свои макросы")
        or class == "OPTIONS" and T("Настройки макросов") or class == "HELPER" and T("Помощник по макросам")
        or (T("Готовые макросы: ") .. ClassName(class)))
    SetPortrait(class)
end

-------------------------------------------------------------------------------
--  Поиск по всем готовым макросам: поле над вкладками. Ищет по названию,
--  описанию, вкладке и заклинаниям в тексте макроса (их названия - на языке
--  клиента). Несколько слов - нужны все. Свой класс и общие - первыми.
-------------------------------------------------------------------------------
local SEARCH_MAX = 30 -- больше карточек сразу не строим: «уточни запрос»
local searchText, searchBack, searchGen, searchQuiet = "", nil, 0, false

-- Строчные буквы и у кириллицы (string.lower её не трогает); ё = е.
local FOLD = {}
for b = 0x90, 0x9F do FOLD["\208" .. string.char(b)] = "\208" .. string.char(b + 0x20) end -- А-П
for b = 0xA0, 0xAF do FOLD["\208" .. string.char(b)] = "\209" .. string.char(b - 0x20) end -- Р-Я
FOLD["\208\129"], FOLD["\209\145"] = "\208\181", "\208\181" -- Ё, ё -> е
local function Fold(text)
    return ((text or ""):lower():gsub("[\208\209][\128-\191]", FOLD))
end

-- Что искать у макроса: строка в нижнем регистре. Названия заклинаний
-- приходят от игры не сразу - без них строку не запоминаем.
local hayCache = {}
local function Haystack(e)
    local h = hayCache[e.m]
    if h and h.lang == ns.lang then return h.title, h.all end
    local em = Effective(e.class, e.m)
    local parts = { em.title or "", em.name or "", e.m.name or "", T(e.group or ""), em.desc or "" }
    local H = ns.Helper
    local why = H and H.Why and H.Why(e.class, e.m)
    if why then for i = 1, 3 do parts[#parts + 1] = why[i] or "" end end
    local body, missing = Render(em.body or "")
    parts[#parts + 1] = body
    local title, all = Fold(parts[1] .. "\n" .. parts[2] .. "\n" .. parts[3]), Fold(table.concat(parts, "\n"))
    if not missing then hayCache[e.m] = { lang = ns.lang, title = title, all = all } end
    return title, all
end

-- Все готовые макросы по порядку: свой класс, общие, остальные классы.
local searchIndex
local function SearchIndex()
    if searchIndex then return searchIndex end
    local _, playerClass = UnitClass("player")
    local order = { playerClass, "GENERAL" }
    for _, c in ipairs(ns.CLASS_ORDER) do
        if c ~= playerClass and c ~= "GENERAL" then order[#order + 1] = c end
    end
    searchIndex = {}
    for _, class in ipairs(order) do
        for _, g in ipairs(ns.MACROS[class] or {}) do
            for _, m in ipairs(g.list or {}) do
                searchIndex[#searchIndex + 1] = { class = class, m = m, group = g.group }
            end
        end
    end
    return searchIndex
end

-- Найденные макросы (не больше SEARCH_MAX) и сколько нашлось всего.
-- Совпало в названии - выше; внутри - порядок классов и данных.
local function FindMacros(query)
    local words = {}
    for w in Fold(query):gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return {}, 0 end
    local top, rest = {}, {}
    for _, e in ipairs(SearchIndex()) do
        local title, all = Haystack(e)
        local ok, inTitle = true, false
        for _, w in ipairs(words) do
            if not all:find(w, 1, true) then ok = false; break end
            if title:find(w, 1, true) then inTitle = true end
        end
        if ok then
            local list = inTitle and top or rest
            list[#list + 1] = e
        end
    end
    local total = #top + #rest
    for _, e in ipairs(rest) do top[#top + 1] = e end
    local out = {}
    for i = 1, math.min(SEARCH_MAX, #top) do out[i] = top[i] end
    -- одним блоком на класс, в порядке первого появления
    local rank, n = {}, 0
    for _, e in ipairs(out) do
        if not rank[e.class] then n = n + 1; rank[e.class] = n end
    end
    for i, e in ipairs(out) do e.pos = i end
    table.sort(out, function(a, b)
        if rank[a.class] ~= rank[b.class] then return rank[a.class] < rank[b.class] end
        return a.pos < b.pos
    end)
    return out, total
end

-- Страница результатов: шапка, по классам - строка «значок, класс» и
-- карточки, как на вкладках класса. Карточки строятся один раз на макрос.
local function BuildSearchPage()
    local page = CreateFrame("Frame", nil, frame.child)
    page:SetPoint("TOPLEFT")
    local width = frame.child:GetWidth()
    page:SetWidth(width)
    local header = PageHeader(page, width)
    local rows, heads = {}, {}
    local function Head(i)
        local hd = heads[i]
        if hd then return hd end
        hd = CreateFrame("Frame", nil, page)
        hd:SetSize(width - 40, 26)
        -- плашка, как заголовки разделов в окнах игры: тёмная, с золотой чертой снизу
        hd.bg = hd:CreateTexture(nil, "BACKGROUND")
        hd.bg:SetAllPoints()
        hd.bg:SetColorTexture(0.1, 0.075, 0.05, 0.95)
        hd.line = hd:CreateTexture(nil, "BORDER")
        hd.line:SetPoint("BOTTOMLEFT")
        hd.line:SetPoint("BOTTOMRIGHT")
        hd.line:SetHeight(1)
        hd.line:SetColorTexture(0.75, 0.6, 0.3, 0.55)
        hd.icon = hd:CreateTexture(nil, "ARTWORK")
        hd.icon:SetSize(20, 20)
        hd.icon:SetPoint("LEFT", 6, 0)
        hd.text = Text(hd, "SystemFont_Large", "GameFontNormalLarge", INK_TITLE)
        hd.text:SetPoint("LEFT", hd.icon, "RIGHT", 8, 0)
        heads[i] = hd
        return hd
    end
    function page:Layout()
        if ns.Helper and ns.Helper.ScanBook then ns.Helper.ScanBook() end
        local found, total = FindMacros(searchText)
        local note
        if total == 0 then
            note = T("Ничего не нашлось. Попробуй название заклинания или слова «фокус», «наведение», «питомец».")
        elseif total > #found then
            note = (T("Найдено: %d. Показаны первые %d - уточни запрос.")):format(total, #found)
        else
            note = (T("Найдено: %d.")):format(total)
        end
        header:Set((T("Поиск: «%s»")):format(searchText), note)
        local y = -header:Layout(16)
        for _, r in pairs(rows) do r:Hide() end
        for _, hd in ipairs(heads) do hd:Hide() end
        local nHead, last = 0, nil
        for _, e in ipairs(found) do
            if e.class ~= last then
                last = e.class
                nHead = nHead + 1
                local hd = Head(nHead)
                SetClassIcon(hd.icon, e.class)
                hd.text:SetText(ClassName(e.class))
                hd:ClearAllPoints()
                hd:SetPoint("TOPLEFT", 20, y - (nHead > 1 and 4 or 0))
                hd:Show()
                y = y - 32 - (nHead > 1 and 4 or 0)
            end
            local row = rows[e.m]
            if not row then
                RequestSpells(e.m.body)
                row = BuildRow(page, e.class, e.m, width - 20)
                rows[e.m] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 10, y)
            row:Show()
            y = y - row:Fill() - ns.S.gap
        end
        self:SetHeight(-y)
        return -y
    end
    return page
end

local function ShowSearch(text)
    if not frame then return end
    if editor then editor:Hide() end
    if builder then builder:Hide() end
    if current ~= "SEARCH" then
        searchBack = { current, currentSpec }
        wipe(hayCache) -- правки и язык могли смениться
    end
    searchText = text
    current, currentKey = "SEARCH", "SEARCH"
    for _, b in ipairs(frame.specTabs) do b:Hide() end
    if not pages.SEARCH then pages.SEARCH = BuildSearchPage() end
    for k, p in pairs(pages) do p:SetShown(k == "SEARCH") end
    frame.child:SetHeight(pages.SEARCH:Layout())
    frame.scroll:SetVerticalScroll(0)
    for _, t in ipairs(frame.classTabs) do t:SetChecked(false) end
    SetWindowTitle(T("Поиск макросов"))
    SetPortrait("GENERAL")
end

-- Поле очистили - назад, где были до поиска.
local function LeaveSearch()
    searchText = ""
    if current ~= "SEARCH" then return end
    local back = searchBack or {}
    searchBack = nil
    local _, playerClass = UnitClass("player")
    current = nil
    ShowClass(back[1] or (ns.MACROS[playerClass] and playerClass) or "GENERAL", back[2])
end

-- Ушли на вкладку класса - поле пустое (без возврата назад).
function ns.ClearSearch()
    searchGen = searchGen + 1
    searchText = ""
    local box = frame and frame.search
    if box and box:GetText() ~= "" then
        searchQuiet = true
        box:SetText("")
        searchQuiet = false
    end
end

-- Число букв (а не байт): «пр» - две буквы.
local function Letters(text)
    return #(text:gsub("[\128-\191]", ""))
end

local function OnSearchChanged(box)
    if searchQuiet then return end
    local text = strtrim(box:GetText() or "")
    searchGen = searchGen + 1
    local gen = searchGen
    if Letters(text) < 2 then
        if current == "SEARCH" then LeaveSearch() end
        return
    end
    -- ищем, когда перестали печатать
    C_Timer.After(0.25, function()
        if gen == searchGen and frame and frame:IsShown() then ShowSearch(text) end
    end)
end

-- Поле поиска внизу окна, под пергаментом: значок лупы, подсказка внутри,
-- крестик очистки (у шаблона игры), Esc - выйти из поля.
local function SearchBox(parent)
    local ok, box = pcall(CreateFrame, "EditBox", "MacroCoachSearch", parent, "SearchBoxTemplate")
    if not ok or not box then
        box = CreateFrame("EditBox", "MacroCoachSearch", parent, "InputBoxTemplate")
    end
    box:SetSize(300, 20)
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)
    local hint = T("Поиск по всем макросам")
    if type(box.Instructions) == "table" and box.Instructions.SetText then
        box.Instructions:SetText(hint)
    else
        -- без шаблона поиска: своя серая подсказка, пока поле пустое
        local ph = box:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        ph:SetPoint("LEFT", 2, 0)
        ph:SetText(hint)
        box:HookScript("OnEditFocusGained", function() ph:Hide() end)
        box:HookScript("OnEditFocusLost", function(self) ph:SetShown((self:GetText() or "") == "") end)
        box.placeholder = ph
    end
    box:HookScript("OnTextChanged", function(self)
        if self.placeholder and not self:HasFocus() then self.placeholder:SetShown((self:GetText() or "") == "") end
        OnSearchChanged(self)
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        -- Enter - искать сразу, не дожидаясь паузы
        local text = strtrim(self:GetText() or "")
        if Letters(text) >= 2 then searchGen = searchGen + 1; ShowSearch(text) end
    end)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(T("Поиск по всем макросам"))
        GameTooltip:AddLine(T("По названию, описанию и заклинаниям: «превращение», «фокус», «питомец», «зелье»."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return box
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "MacroCoachFrame", UIParent, "ButtonFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "MacroCoachFrame")
    if type(frame.TitleContainer) ~= "table" then
        -- Шаблона нет (другая версия игры): простой тёмный фон и заголовок.
        local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetAllPoints()
        bg:SetColorTexture(0.08, 0.08, 0.08, 0.95)
        frame.titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.titleText:SetPoint("TOP", 0, -6)
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        if type(frame.CloseButton) ~= "table" then frame.CloseButton = close end
    end

    -- Настройки - шестерёнка у крестика окна.
    local gear = Badge(frame, 20, "Interface\\Icons\\INV_Misc_Gear_01")
    if type(frame.CloseButton) == "table" then gear:SetPoint("RIGHT", frame.CloseButton, "LEFT", -4, 0)
    else gear:SetPoint("TOPRIGHT", -30, -2) end
    gear:SetFrameLevel(frame:GetFrameLevel() + 10)
    gear:SetScript("OnClick", function()
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        ShowClass("OPTIONS")
    end)
    gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(T("Настройки макросов"))
        GameTooltip:AddLine(T("Названия на панелях, безопасность, импорт и экспорт."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.gear = gear

    -- «?» рядом с шестерёнкой: знакомство с аддоном (Intro.lua).
    local help = Badge(frame, 20, "Interface\\Icons\\INV_Misc_QuestionMark")
    help:SetPoint("RIGHT", gear, "LEFT", -4, 0)
    help:SetFrameLevel(frame:GetFrameLevel() + 10)
    help:SetScript("OnClick", function()
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if ns.ShowIntro then ns.ShowIntro() end
    end)
    help:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(T("Как пользоваться MacroCoach"))
        GameTooltip:Show()
    end)

    -- «Предложить макрос»: свой макрос - автору, чтобы он стал готовым для всех.
    local suggest = SmallButton(frame, T("Предложить макрос"), 160, function()
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if ns.UI and ns.UI.Open then ns.UI.Open("CUSTOM", 3) end
    end)
    suggest:SetPoint("RIGHT", help, "LEFT", -8, 0)
    suggest:SetFrameLevel(frame:GetFrameLevel() + 10)
    suggest:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(T("Предложить макрос"))
        GameTooltip:AddLine(T("Есть свой полезный макрос? Отправь его автору - он появится в аддоне у всех."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    suggest:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.suggest = suggest
    help:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.help = help

    -- Поиск по всем макросам - в самом низу окна, во всю ширину.
    frame.search = SearchBox(frame)
    frame.search:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 7)
    frame.search:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 7)

    -- Пергамент на месте внутренней панели. Сверху - место под вкладки
    -- специализаций, снизу - под поиск.
    local page = CreateFrame("Frame", nil, frame)
    if type(frame.Inset) == "table" then
        frame.Inset:ClearAllPoints()
        frame.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -ATTIC)
        frame.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, CELLAR)
        page:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 3, -3)
        page:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -3, 3)
    else
        page:SetPoint("TOPLEFT", 7, -ATTIC - 3)
        page:SetPoint("BOTTOMRIGHT", -9, CELLAR + 3)
    end
    -- Страница книги заклинаний Forever без затемнённых краёв.
    local parchment = page:CreateTexture(nil, "BACKGROUND")
    parchment:SetAllPoints()
    local info = HasAtlas("spellbook-Page-Right-C60") and C_Texture.GetAtlasInfo("spellbook-Page-Right-C60")
    local file = info and (info.file or info.filename)
    if file and info.leftTexCoord and info.topTexCoord then
        local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
        local w, h = r - l, b - t
        parchment:SetTexture(file)
        parchment:SetTexCoord(l + w * 0.025, r - w * 0.02, t + h * 0.085, b - h * 0.025)
    elseif info then
        parchment:SetAtlas("spellbook-Page-Right-C60", false)
    else
        parchment:SetColorTexture(0.86, 0.77, 0.6)
    end
    frame.page = page

    frame.scroll = CreateFrame("ScrollFrame", "MacroCoachScroll", page, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 0, -6)
    frame.scroll:SetPoint("BOTTOMRIGHT", -30, 6)
    ScrollTrack(frame.scroll)
    frame.child = CreateFrame("Frame", nil, frame.scroll)
    frame.child:SetSize(PAGE_W - 30, 10)
    frame.scroll:SetScrollChild(frame.child)
    if type(frame.scroll.ScrollBar) ~= "table" then
        frame.scroll:EnableMouseWheel(true)
        frame.scroll:SetScript("OnMouseWheel", function(self, d)
            local range = self:GetVerticalScrollRange()
            self:SetVerticalScroll(math.min(range, math.max(0, self:GetVerticalScroll() - d * 60)))
        end)
    end

    -- Вкладки специализаций сверху: значок в кольце и название
    frame.specTabs = {}
    for i = 1, MAX_SPEC_TABS do
        local b = SpecTabButton(frame)
        if i == 1 then b:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 62, -ATTIC + 1) end
        b:SetScript("OnClick", function()
            if b.selected then return end
            Sound("IG_CHARACTER_INFO_TAB")
            ShowClass(current, i)
        end)
        -- обрезанное название - целиком в подсказке
        b:SetScript("OnEnter", function(self)
            if not self.full then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.full)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        frame.specTabs[i] = b
    end

    -- Вкладки классов справа, как в книге заклинаний
    frame.classTabs = {}
    for i, class in ipairs(ns.CLASS_ORDER) do
        local t = SideTab(frame, ClassName(class))
        t:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -40 - (i - 1) * 46)
        if class == "CUSTOM" then
            -- Плюс прозрачный: под него тёмная ячейка, как у плитки.
            local back = t:CreateTexture(nil, "BORDER")
            back:SetAllPoints()
            back:SetColorTexture(0, 0, 0, 0.75)
            t.icon:ClearAllPoints()
            t.icon:SetPoint("CENTER")
            t.icon:SetSize(24, 24)
        end
        SetClassIcon(t.icon, class)
        t.class = class
        t:SetScript("OnClick", function()
            Sound("IG_ABILITY_PAGE_TURN")
            ShowClass(class)
        end)
        frame.classTabs[i] = t
    end

    frame.UpdateSlots = function() end
    frame:SetScript("OnShow", function()
        if ns.macroTab then ns.macroTab:SetChecked(true) end
    end)
    frame:SetScript("OnHide", function()
        frame:SetFrameStrata("HIGH") -- после открытия из настроек было DIALOG
        if current == "SEARCH" then
            local back = searchBack or {}
            current, currentSpec, searchBack = back[1], back[2], nil
        end
        ns.ClearSearch()
        if editor then editor:Hide() end
        if builder then builder:Hide() end
        if iconPopup then iconPopup:Hide() end
        if ns.macroTab then ns.macroTab:SetChecked(false) end
    end)
    frame:Hide()

    -- Когда игра догрузит данные заклинаний и предметов - обновить названия.
    local pending
    frame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
    frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    frame:SetScript("OnEvent", function()
        if pending or not frame:IsShown() then return end
        pending = true
        C_Timer.After(0.3, function()
            pending = nil
            if not frame:IsShown() then return end
            Relayout()
            if editor and editor:IsShown() then editor.Update() end
            if builder and builder:IsShown() then builder.Update() end
        end)
    end)
end

local function Toggle()
    Build()
    if frame:IsShown() then
        frame:Hide()
        return
    end
    -- Первое открытие аддона: сначала знакомство отдельным окном, само окно -
    -- когда знакомство закроют (Intro.lua). Подробный рассказ остался на
    -- вкладке «Зачем макросы».
    if ns.IntroFirst and ns.IntroFirst(function()
        if not frame:IsShown() then Toggle() end
    end) then return end
    frame:Show()
    -- Открываемся там, где были, или на своём классе.
    DB().helperSeen = true
    local _, class = UnitClass("player")
    ShowClass(current or (ns.MACROS[class] and class) or "GENERAL", current and currentSpec or nil)
end
ns.Toggle = Toggle

-- Открыть окно на нужной вкладке: Open("HELPER", 2) - «Проверка».
local function Open(class, spec)
    Build()
    if not frame:IsShown() then frame:Show() end
    DB().helperSeen = true
    ShowClass(class, spec)
end

-- Открыть справа от окна anchor (окна макросов игры).
local function OpenBeside(anchor)
    Build()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 40, 0)
    if not frame:IsShown() then Toggle() end
end

-------------------------------------------------------------------------------
--  Кнопка у миникарты (можно скрыть) и страница в «Модификациях»
-------------------------------------------------------------------------------
local mmButton

local function PlaceMinimapButton()
    local angle = math.rad(DB().minimap.angle or 200)
    local r = Minimap:GetWidth() / 2 + 5
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function UpdateMinimapButton()
    if DB().minimap.hide then
        if mmButton then mmButton:Hide() end
        return
    end
    if not mmButton then
        local b = CreateFrame("Button", "MacroCoachMinimapButton", Minimap)
        b:SetSize(31, 31)
        b:SetFrameStrata("MEDIUM")
        b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(ADDON_ICON)
        icon:SetSize(19, 19)
        icon:SetPoint("CENTER", 0, 1)
        local mask = b:CreateMaskTexture()
        mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
        local ring = b:CreateTexture(nil, "OVERLAY")
        ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        ring:SetSize(53, 53)
        ring:SetPoint("TOPLEFT")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        hl:SetAllPoints()
        hl:SetBlendMode("ADD")
        b:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                ns.OpenSettings()
            else
                ns.Toggle()
            end
        end)
        b:SetScript("OnDragStart", function(self)
            if self:GetParent() ~= Minimap then return end -- двигает сборщик кнопок
            self:SetScript("OnUpdate", function()
                local mx, my = Minimap:GetCenter()
                local x, y = GetCursorPosition()
                local sc = Minimap:GetEffectiveScale()
                DB().minimap.angle = math.deg(math.atan2(y / sc - my, x / sc - mx))
                PlaceMinimapButton()
            end)
        end)
        b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
        -- подсказка в одном виде с EasyCraft: название, что это, потом
        -- кнопки мыши (ЛКМ, ПКМ, перетащить)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("|cff33ff99Macro|rCoach")
            GameTooltip:AddLine(T("Готовые макросы WoW Forever"), 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            local KEY = "|cffffd100%s|r - %s"
            GameTooltip:AddLine(KEY:format(T("ЛКМ"), T("открыть окно")), 1, 1, 1)
            GameTooltip:AddLine(KEY:format(T("ПКМ"), T("настройки")), 1, 1, 1)
            GameTooltip:AddLine(KEY:format(T("Перетащить"), T("передвинуть кнопку")), 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        mmButton = b
        -- на место у миникарты - только при создании: если кнопку забрал
        -- сборщик кнопок (MinimapButtonButton и др.), не уводим её обратно
        PlaceMinimapButton()
    end
    mmButton:Show()
end

SetMinimapHidden = function(hide)
    DB().minimap.hide = hide and true or false
    UpdateMinimapButton()
    if frame and frame.mmCheck then frame.mmCheck:SetChecked(not hide) end
end
ns.SetMinimapHidden = SetMinimapHidden

-- Страница аддона в «Настройки → Модификации».
local settingsCategory

-- Выбор языка: подпись, выпадающий список, пояснение и кнопка перезагрузки.
local function LanguageDropdown(parent)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(560, 66)
    local label = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(T("Язык"))
    local note = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetJustifyH("LEFT")
    local reload = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    reload:SetSize(200, 22)
    reload:SetText(T("Перезагрузить интерфейс"))
    reload:SetScript("OnClick", function() ReloadUI() end)
    local function Changed()
        local changed = ns.ResolveLang(DB().lang) ~= ns.lang
        note:SetText(changed and T("Язык сменится после перезагрузки интерфейса.") or "")
        reload:SetShown(changed)
    end
    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, box, "WowStyle1DropdownTemplate")
    if ok and dd and dd.SetupMenu then
        dd:SetWidth(240)
        dd:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
        dd:SetupMenu(function(_, root)
            for _, l in ipairs(ns.LANGS) do
                local text = l.code == "auto" and T(l.label) or l.label
                local r = root:CreateRadio(text, function() return (DB().lang or "auto") == l.code end, function()
                    DB().lang = l.code
                    Changed()
                end)
                if l.code ~= "auto" and not ns.READY[l.code] and r then
                    if r.SetEnabled then r:SetEnabled(false) end
                    if r.SetTooltip then
                        r:SetTooltip(function(tip) tip:SetText(T("Перевода на этот язык пока нет.")) end)
                    end
                end
            end
        end)
        -- кнопка перезагрузки в той же строке, пояснение под списком
        reload:SetPoint("LEFT", dd, "RIGHT", 12, 0)
        note:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 2, -6)
    else
        box:SetHeight(76)
        note:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
        reload:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -10)
    end
    box.Refresh = Changed
    box:SetScript("OnShow", Changed)
    Changed()
    return box
end

-- Команды чата: список в настройках и по /coach commands (описания
-- по-русски, переводятся при показе).
local COMMANDS = {
    { "/coach", "открыть или закрыть окно" },
    { "/coach help", "зачем макросы: короткое знакомство" },
    { "/coach tips", "рекомендуемые макросы для твоего класса" },
    { "/coach check", "проверить ранги и макросы на панелях" },
    { "/coach update", "обновить ранги на панелях и готовые макросы" },
    { "/coach translate", "перевести макрос с английского" },
    { "/coach share", "импорт и экспорт макросов" },
    { "/coach options", "открыть настройки" },
    { "/coach minimap", "показать или скрыть кнопку у миникарты" },
    { "/coach commands", "этот список в чат" },
}

local function CommandLines()
    local out = {}
    for _, c in ipairs(COMMANDS) do out[#out + 1] = "|cffffd100" .. c[1] .. "|r - " .. T(c[2]) end
    return out
end

local function PrintCommands()
    Print(T("команды:"))
    for _, line in ipairs(CommandLines()) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
end

-- Одинаково у MacroCoach и EasyCraft: название, язык, описание, кнопки
-- «Открыть окно» и «Как пользоваться», настройки, команды.
local function BuildSettings()
    local panel = CreateFrame("Frame")
    panel.name = "MacroCoach"
    -- страница с прокруткой: внизу список команд, всё может не влезть
    local body = panel
    local ok, sf = pcall(CreateFrame, "ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    if ok and sf then
        sf:SetPoint("TOPLEFT", 0, -2)
        sf:SetPoint("BOTTOMRIGHT", -28, 2)
        body = CreateFrame("Frame", nil, sf)
        body:SetSize(600, 700)
        sf:SetScrollChild(body)
        sf:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then body:SetWidth(w) end end)
    end

    local title = body:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cff33ff99Macro|rCoach")

    -- Язык MacroCoach (выбор - в MacroCoachDB.lang, меняется после перезагрузки)
    local lang = LanguageDropdown(body)
    lang:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)

    local sub = body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", lang, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(560)
    sub:SetJustifyH("LEFT")
    sub:SetText(T("Популярные макросы WoW Forever для всех классов: описание, ID, изменение текста и добавление одной кнопкой."))

    local function Front()
        -- Окно настроек игры не закрываем из кода аддона (это «заражает»
        -- настройки), а показываем окно макросов поверх него.
        Build()
        frame:SetFrameStrata("DIALOG")
        frame:Raise()
    end
    local open = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
    open:SetSize(200, 26)
    open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -14)
    open:SetText(T("Открыть окно"))
    open:SetScript("OnClick", function()
        Front()
        if not frame:IsShown() then ns.Toggle() end
        frame:Raise()
    end)
    local intro = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
    intro:SetSize(200, 26)
    intro:SetPoint("LEFT", open, "RIGHT", 10, 0)
    intro:SetText(T("Как пользоваться"))
    intro:SetScript("OnClick", function()
        Front()
        Open("HELPER", 1)
        frame:Raise()
    end)

    local mm = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
    mm:SetPoint("TOPLEFT", open, "BOTTOMLEFT", -2, -14)
    mm.label = mm:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    mm.label:SetPoint("LEFT", mm, "RIGHT", 4, 0)
    mm.label:SetText(T("Показывать кнопку у миникарты"))
    mm:SetScript("OnShow", function(self) self:SetChecked(not DB().minimap.hide) end)
    mm:SetScript("OnClick", function(self) SetMinimapHidden(not self:GetChecked()) end)
    -- Состояние ставим сразу: страница видима с создания, и при первом
    -- открытии настроек OnShow может не сработать.
    mm:SetChecked(not DB().minimap.hide)
    -- остальные настройки - в окне аддона (шестерёнка у крестика)
    local more = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
    more:SetSize(240, 22)
    more:SetPoint("TOPLEFT", mm, "BOTTOMLEFT", 2, -6)
    more:SetText(T("Настройки макросов в окне"))
    more:SetScript("OnClick", function()
        Front()
        Open("OPTIONS")
        frame:Raise()
    end)

    -- команды чата
    local cmdHead = body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cmdHead:SetPoint("TOPLEFT", more, "BOTTOMLEFT", 0, -24)
    cmdHead:SetText(T("Команды в чате"))
    local cmds = body:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cmds:SetPoint("TOPLEFT", cmdHead, "BOTTOMLEFT", 0, -8)
    cmds:SetWidth(560)
    cmds:SetJustifyH("LEFT")
    if cmds.SetSpacing then cmds:SetSpacing(4) end
    cmds:SetText(table.concat(CommandLines(), "\n") .. "\n|cff9d9d9d" .. T("То же по-русски: /макросы, /coach помощь, /coach советы, /coach проверка.") .. "|r")

    panel:SetScript("OnShow", function()
        mm:SetChecked(not DB().minimap.hide)
        lang.Refresh()
    end)
    panel:Hide()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(settingsCategory)
    end
end

function ns.OpenSettings()
    if not settingsCategory then
        ns.Toggle()
        return
    end
    if Settings and Settings.OpenToCategory and settingsCategory.GetID then
        Settings.OpenToCategory(settingsCategory:GetID())
    end
end

-- Меню аддонов у миникарты: ЛКМ - окно, ПКМ - настройки.
function MacroCoach_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then ns.OpenSettings() else ns.Toggle() end
end

SLASH_MACROCOACH1 = "/coach"
SLASH_MACROCOACH2 = "/макросы"
SLASH_MACROCOACH3 = "/macrocoach"
SlashCmdList.MACROCOACH = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "minimap" or msg == "миникарта" then
        SetMinimapHidden(not DB().minimap.hide)
        Print(DB().minimap.hide and T("кнопка у миникарты скрыта (вернуть: /coach minimap).") or T("кнопка у миникарты показана."))
    elseif msg == "help" or msg == "помощь" or msg == "start" then
        Open("HELPER", 1)
    elseif msg == "tips" or msg == "советы" or msg == "рекомендации" then
        local _, class = UnitClass("player")
        class = ns.MACROS[class] and class or "GENERAL"
        Open(class, ns.UI.TabIndex(class, "Рекомендации") or 1)
    elseif msg == "check" or msg == "проверка" or msg == "ranks" or msg == "ранги" then
        Open("HELPER", 2)
    elseif msg == "update" or msg == "обновить" then
        ns.UpdateAll()
    elseif msg == "translate" or msg == "перевод" then
        Open("CUSTOM", 1)
        OpenCustomText(nil, B.New())
    elseif msg == "intro" or msg == "знакомство" then
        local _, class = UnitClass("player")
        Open(current or (ns.MACROS[class] and class) or "GENERAL")
        if ns.ShowIntro then ns.ShowIntro() end
    elseif msg == "lang" or msg == "язык" then
        -- перевести готовые макросы в игре на нынешний язык и сказать, что не тронуто
        if ns.Helper and ns.Helper.ResyncLanguage then ns.Helper.ResyncLanguage(0, true) end
    elseif msg == "beside" or msg == "рядом" then
        local db = DB()
        db.besideMacro = db.besideMacro == false
        Print(db.besideMacro and T("окно будет открываться рядом с окном макросов игры.")
            or T("окно больше не открывается само рядом с окном макросов игры."))
    elseif msg == "share" or msg == "обмен" or msg == "export" or msg == "экспорт" then
        Open("CUSTOM", 3)
    elseif msg == "data" or msg == "данные" then
        if ns.Helper then ns.Helper.PrintDataCheck() end
    elseif msg == "options" or msg == "config" or msg == "настройки" then
        ns.OpenSettings()
    elseif msg == "" then
        Toggle()
    else
        -- commands, ?, команды и всё незнакомое - список команд
        PrintCommands()
    end
end

-- Вкладка «Готовые макросы» справа на окне макросов игры (/macro),
-- как вкладки книги заклинаний.
local function AddMacroFrameTab()
    if not MacroFrame or ns.macroTab then return end
    local tab = SideTab(MacroFrame, "MacroCoach: " .. T("Готовые макросы"))
    tab:SetPoint("TOPLEFT", MacroFrame, "TOPRIGHT", 0, -36)
    tab.icon:SetTexture(ADDON_ICON)
    tab:SetScript("OnClick", function(self)
        if frame and frame:IsShown() then
            frame:Hide()
        else
            OpenBeside(MacroFrame)
        end
        self:SetChecked(frame and frame:IsShown() or false)
    end)
    ns.macroTab = tab
    -- Окно макросов игры открыли - MacroCoach сам встаёт рядом, закрыли -
    -- уходит вместе с ним (если открылся сам). Выключить: /coach beside.
    MacroFrame:HookScript("OnShow", function()
        if DB().besideMacro == false then return end
        if InCombatLockdown and InCombatLockdown() then return end
        if frame and frame:IsShown() then return end
        local ok = pcall(OpenBeside, MacroFrame)
        ns.openedBeside = ok and frame and frame:IsShown() or nil
        tab:SetChecked(frame and frame:IsShown() or false)
    end)
    MacroFrame:HookScript("OnHide", function()
        if ns.openedBeside and frame and frame:IsShown() then frame:Hide() end
        ns.openedBeside = nil
    end)
end

-- Функции окна для помощника (Helper.lua загружается после этого файла).
ns.UI = {
    DB = DB, Print = Print, Effective = Effective, Loc = Loc, Key = Key, Pickup = Pickup, FindMacro = FindMacro,
    Render = Render, ToDisplay = ToDisplay, FirstIcon = FirstIcon, RequestSpells = RequestSpells,
    CharCount = CharCount, MAX_CHARS = MAX_CHARS, SpellIDs = SpellIDs, SpellIcon = SpellIcon, ItemIcon = ItemIcon,
    OnBars = OnBars, AfterCombat = AfterCombat, Card = Card, Text = Text, GOLD = GOLD, LIGHT = LIGHT, GREY = GREY,
    SetClassIcon = SetClassIcon, ClassName = ClassName, CustomList = CustomList,
    RefreshCustom = function(stay) RefreshCustom(stay) end, Relayout = Relayout, Open = Open,
    Frame = function() return frame end, Pages = function() return pages end,
    PageHeader = PageHeader, Badge = Badge,
    ShowSearch = function(text) ShowSearch(text) end, FindMacros = FindMacros, Fold = Fold,
    -- Номер вкладки класса по названию (nil - нет такой).
    TabIndex = function(class, label)
        for i, t in ipairs(SpecTabs(class)) do
            if t.label == label then return i end
        end
    end,
}

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_MacroUI" then
        AddMacroFrameTab()
    elseif name == ADDON then
        ns.SetLang(DB().lang)
        BuildSettings()
        UpdateMinimapButton()
        if C_AddOns.IsAddOnLoaded("Blizzard_MacroUI") then AddMacroFrameTab() end
    end
end)
