-- MacroCoach. Страницы «Мои макросы», «Как написать» и «Настройки».
local ADDON, ns = ...
local P = ns.P
local T, pages, DB, B, CustomList, Render = P.T, P.pages, P.DB, P.B, P.CustomList, P.Render
local RequestSpells, Text, PageHeader, Sound, GOLD, LIGHT = P.RequestSpells, P.Text, P.PageHeader, P.Sound, P.GOLD, P.LIGHT
local GREY, Card, BuildRow = P.GREY, P.Card, P.BuildRow

-------------------------------------------------------------------------------
--  Страница «Мои макросы»: шапка с кнопками нового макроса, затем ваши макросы
-------------------------------------------------------------------------------
local function BuildCustomPage(key)
  local page = CreateFrame("Frame", nil, P.frame.child)
  page:SetPoint("TOPLEFT")
  local width = P.frame.child:GetWidth()
  page:SetWidth(width)
  local function NewMacro() Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); P.OpenBuilder(nil, B.New()) end

  -- Шапка, как у всех страниц: крупно и одна строка.
  local header = PageHeader(page, width)
  header:Set(T("Свои макросы"), T("Собери макрос из готовых строк - код писать не нужно."))

  -- Три способа начать - плитки, как строки подсказок EasyCraft: значок,
  -- что это и коротко зачем; подробно - при наведении.
  local function OpenTemplates(owner)
    local function gen(_, root)
      root:CreateTitle(T("Начать с шаблона"))
      for _, t in ipairs(B.TEMPLATES) do
        local b = root:CreateButton(T(t.label), function() P.OpenBuilder(nil, t.make()) end)
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
     run = function() P.OpenCustomText(nil, B.New()) end },
    { icon = "Interface\\Icons\\INV_Letter_15", title = T("Отправить автору"), sub = T("в аддон для всех"),
     tip = T("Твой макрос с описанием уйдёт автору MacroCoach. Полезный появится в готовых у всех игроков."),
     run = function() ns.Helper.SuggestDialog() end },
  }
  local tiles = {}
  -- плитки по две в ряд: названию и пояснению хватает места
  local TILE_COLS = 2
  local tileW = math.floor((width - 20 - (TILE_COLS - 1) * 10) / TILE_COLS)
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
  local listHead = Text(page, "SystemFont_Large", "GameFontNormalLarge", P.INK)
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
      local col, row = (i - 1) % TILE_COLS, math.floor((i - 1) / TILE_COLS)
      t:SetPoint("TOPLEFT", 10 + col * (tileW + 10), y - row * (52 + 10))
    end
    local rows = math.ceil(#tiles / TILE_COLS)
    y = y - rows * 52 - (rows - 1) * 10 - 18
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
  if not P.host then pages[key] = page end
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
  local page = CreateFrame("Frame", nil, P.frame.child)
  page:SetPoint("TOPLEFT")
  local width = P.frame.child:GetWidth()
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
    b:SetScript("OnClick", function() P.OpenBuilder(nil, t.make()) end)
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

-- Настройки помощника (MacroCoachDB.helper): галочки на странице аддона в
-- настройках игры (Window.lua, BuildSettings). note - подсказка при наведении.
P.HELP_OPTS = {
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
  { key = "offer", label = "Предлагать исправления",
   note = "При входе в игру и после тренера аддон показывает окно с тем, что он может исправить: старые ранги на панелях и ошибки в макросах." },
}

-- Перестроить «Мои макросы» после сохранения или удаления. stay - не
-- переключаться на них (импорт и полученный макрос из другой вкладки).
P.RefreshCustom = function(stay)
  local p = pages["CUSTOM#1"]
  if p then
    p:Hide()
    pages["CUSTOM#1"] = nil
  end
  if P.frame and P.frame:IsShown() and (not stay or P.currentKey == "CUSTOM#1") then P.ShowClass("CUSTOM", 1) end
end

-- Для соседних файлов.
P.BuildCustomPage, P.BuildGuidePage, P.SmallButton = BuildCustomPage, BuildGuidePage, SmallButton
