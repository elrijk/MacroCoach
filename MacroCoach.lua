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
--  Открыть: /mc (или /coach), кнопка у миникарты, «Настройки → Модификации»
--  или вкладка «Готовые макросы» справа на окне /macro.
-------------------------------------------------------------------------------
local ADDON, ns = ...
-- Общее для файлов окна: состояние и функции, нужные в соседних файлах.
local P = {}
ns.P = P
local T = ns.T
-- Вкладки справа: «Помощник» сверху, дальше «Для всех классов», классы
-- и «Свои макросы».
tinsert(ns.CLASS_ORDER, 1, "HELPER")
ns.MACROS.HELPER = ns.MACROS.HELPER or {}
tinsert(ns.CLASS_ORDER, "CUSTOM")
ns.MACROS.CUSTOM = ns.MACROS.CUSTOM or {}

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

local pages = {}

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
  if P.frame and P.frame.UpdateSlots then P.frame.UpdateSlots() end
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

-- Для соседних файлов.
P.T, P.WIDTH, P.HEIGHT, P.PAGE_W, P.ATTIC, P.CELLAR = T, WIDTH, HEIGHT, PAGE_W, ATTIC, CELLAR
P.TAB_H, P.QUESTION, P.ADDON_ICON, P.MAX_CHARS, P.pages, P.Print = TAB_H, QUESTION, ADDON_ICON, MAX_CHARS, pages, Print
P.DB, P.AfterCombat, P.B, P.CustomList, P.CustomMacro, P.Key = DB, AfterCombat, B, CustomList, CustomMacro, Key
P.Loc, P.Effective, P.Render, P.ToDisplay, P.ToStored, P.HighlightIDs = Loc, Effective, Render, ToDisplay, ToStored, HighlightIDs
P.CharCount, P.SpellIDs, P.SpellsOf, P.ItemIDs, P.IDLine, P.RequestSpells = CharCount, SpellIDs, SpellsOf, ItemIDs, IDLine, RequestSpells
P.SpellIcon, P.ItemIcon, P.FirstIcon, P.FindMacro, P.Pickup, P.SyncGameMacro = SpellIcon, ItemIcon, FirstIcon, FindMacro, Pickup, SyncGameMacro
P.OnBars = OnBars
