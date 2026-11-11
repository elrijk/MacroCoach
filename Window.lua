-- MacroCoach. Окно аддона: страницы классов, поиск, кнопка у миникарты, команды чата.
local ADDON, ns = ...
local P = ns.P
local T, WIDTH, HEIGHT, PAGE_W, ATTIC, CELLAR = P.T, P.WIDTH, P.HEIGHT, P.PAGE_W, P.ATTIC, P.CELLAR
local ADDON_ICON, MAX_CHARS, pages, Print, DB, AfterCombat = P.ADDON_ICON, P.MAX_CHARS, P.pages, P.Print, P.DB, P.AfterCombat
local B, CustomList, Key, Loc, Effective, Render = P.B, P.CustomList, P.Key, P.Loc, P.Effective, P.Render
local ToDisplay, CharCount, SpellIDs, RequestSpells, SpellIcon, ItemIcon = P.ToDisplay, P.CharCount, P.SpellIDs, P.RequestSpells, P.SpellIcon, P.ItemIcon
local FirstIcon, FindMacro, Pickup, OnBars, MAX_SPEC_TABS, Text = P.FirstIcon, P.FindMacro, P.Pickup, P.OnBars, P.MAX_SPEC_TABS, P.Text
local HasAtlas, INK_TITLE, PageHeader, Badge, Sound, ScrollTrack = P.HasAtlas, P.INK_TITLE, P.PageHeader, P.Badge, P.Sound, P.ScrollTrack
local SideTab, ClassName, SetClassIcon, SpecIcon, TAB_ICON, SpecTabButton = P.SideTab, P.ClassName, P.SetClassIcon, P.SpecIcon, P.TAB_ICON, P.SpecTabButton
local SpecTabs, PlayerSpecTab, selectedSpec, GOLD, LIGHT, GREY = P.SpecTabs, P.PlayerSpecTab, P.selectedSpec, P.GOLD, P.LIGHT, P.GREY
local Card, BuildRow, BuildPage, Relayout, BuildCustomPage, BuildGuidePage = P.Card, P.BuildRow, P.BuildPage, P.Relayout, P.BuildCustomPage, P.BuildGuidePage
local SmallButton = P.SmallButton

-------------------------------------------------------------------------------
--  Окно
-------------------------------------------------------------------------------
-- В заголовке - название аддона, дальше что открыто.
local function SetWindowTitle(text)
  text = "MacroCoach - " .. (text or "")
  if type(P.frame.TitleContainer) == "table" and P.frame.SetTitle then
    P.frame:SetTitle(text)
  elseif P.frame.titleText then
    P.frame.titleText:SetText(text)
  end
end

-- В портрете всегда значок аддона (класс - на вкладке справа и в заголовке).
local function SetPortrait()
  if type(P.frame.PortraitContainer) ~= "table" then return end
  P.frame:SetPortraitToAsset(ADDON_ICON)
  if P.frame.SetPortraitTexCoord then P.frame:SetPortraitTexCoord(0, 1, 0, 1) end
end

-- Размер вкладок один на всё окно: одна и та же надпись - одна и та же
-- ширина у всех классов, шрифт один. Длинное название обрезается
-- троеточием, целиком - в подсказке при наведении.
local TAB_PAD, TAB_GAP, TAB_TEXT_MAX = 12, 2, 100

local function SelectSpecTabs(class, tabs, spec)
  local pool = P.frame.specTabs
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

P.ShowClass = function(class, spec)
  if P.editor then P.editor:Hide() end
  if P.builder then P.builder:Hide() end
  if ns.ClearSearch then ns.ClearSearch() end
  P.current = class
  local tabs = SpecTabs(class)
  if not spec then
    local _, playerClass = UnitClass("player")
    spec = selectedSpec[class] or (class == playerClass and PlayerSpecTab(tabs)) or 1
  end
  if spec > #tabs then spec = 1 end
  selectedSpec[class], P.currentSpec = spec, spec
  SelectSpecTabs(class, tabs, spec)

  local key = class .. "#" .. spec
  P.currentKey = key
  for k, p in pairs(pages) do p:SetShown(k == key) end
  local tab = tabs[spec]
  local page = pages[key] or (tab and tab.custom and BuildCustomPage(key)) or (tab and tab.guide and BuildGuidePage(key))
    or (tab and tab.helper and ns.BuildHelperPage and ns.BuildHelperPage(tab.helper, key))
    or BuildPage(class, tab and tab.list or {}, key, tab and tab.rec, tab and tab.label)
  page:Show()
  P.frame.child:SetHeight(page:Layout())
  P.frame.scroll:SetVerticalScroll(0)

  for _, t in ipairs(P.frame.classTabs) do t:SetChecked(t.class == class) end
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
  local page = CreateFrame("Frame", nil, P.frame.child)
  page:SetPoint("TOPLEFT")
  local width = P.frame.child:GetWidth()
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
  if not P.frame then return end
  if P.editor then P.editor:Hide() end
  if P.builder then P.builder:Hide() end
  if P.current ~= "SEARCH" then
    searchBack = { P.current, P.currentSpec }
    wipe(hayCache) -- правки и язык могли смениться
  end
  searchText = text
  P.current, P.currentKey = "SEARCH", "SEARCH"
  for _, b in ipairs(P.frame.specTabs) do b:Hide() end
  if not pages.SEARCH then pages.SEARCH = BuildSearchPage() end
  for k, p in pairs(pages) do p:SetShown(k == "SEARCH") end
  P.frame.child:SetHeight(pages.SEARCH:Layout())
  P.frame.scroll:SetVerticalScroll(0)
  for _, t in ipairs(P.frame.classTabs) do t:SetChecked(false) end
  SetWindowTitle(T("Поиск макросов"))
  SetPortrait("GENERAL")
end

-- Поле очистили - назад, где были до поиска.
local function LeaveSearch()
  searchText = ""
  if P.current ~= "SEARCH" then return end
  local back = searchBack or {}
  searchBack = nil
  local _, playerClass = UnitClass("player")
  P.current = nil
  P.ShowClass(back[1] or (ns.MACROS[playerClass] and playerClass) or "GENERAL", back[2])
end

-- Ушли на вкладку класса - поле пустое (без возврата назад).
function ns.ClearSearch()
  searchGen = searchGen + 1
  searchText = ""
  local box = P.frame and P.frame.search
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
    if P.current == "SEARCH" then LeaveSearch() end
    return
  end
  -- ищем, когда перестали печатать
  C_Timer.After(0.25, function()
    if gen == searchGen and P.frame and P.frame:IsShown() then ShowSearch(text) end
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
  if P.frame then return end
  P.frame = CreateFrame("Frame", "MacroCoachFrame", UIParent, "ButtonFrameTemplate")
  P.frame:SetSize(WIDTH, HEIGHT)
  P.frame:SetPoint("CENTER")
  P.frame:SetFrameStrata("HIGH")
  P.frame:SetToplevel(true)
  P.frame:SetClampedToScreen(true)
  P.frame:EnableMouse(true)
  P.frame:SetMovable(true)
  P.frame:RegisterForDrag("LeftButton")
  P.frame:SetScript("OnDragStart", P.frame.StartMoving)
  P.frame:SetScript("OnDragStop", P.frame.StopMovingOrSizing)
  tinsert(UISpecialFrames, "MacroCoachFrame")
  if type(P.frame.TitleContainer) ~= "table" then
    -- Шаблона нет (другая версия игры): простой тёмный фон и заголовок.
    local bg = P.frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.95)
    P.frame.titleText = P.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    P.frame.titleText:SetPoint("TOP", 0, -6)
    local close = CreateFrame("Button", nil, P.frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    if type(P.frame.CloseButton) ~= "table" then P.frame.CloseButton = close end
  end

  -- Настройки - шестерёнка у крестика окна.
  local gear = Badge(P.frame, 20, "Interface\\Icons\\INV_Misc_Gear_01")
  if type(P.frame.CloseButton) == "table" then gear:SetPoint("RIGHT", P.frame.CloseButton, "LEFT", -4, 0)
  else gear:SetPoint("TOPRIGHT", -30, -2) end
  gear:SetFrameLevel(P.frame:GetFrameLevel() + 10)
  gear:SetScript("OnClick", function()
    Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    ns.OpenSettings()
  end)
  gear:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(T("Настройки макросов"))
    GameTooltip:AddLine(T("Названия на панелях, безопасность, импорт и экспорт."), 1, 1, 1, true)
    GameTooltip:Show()
  end)
  gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
  P.frame.gear = gear

  -- «?» рядом с шестерёнкой: знакомство с аддоном (Intro.lua).
  local help = Badge(P.frame, 20, "Interface\\Icons\\INV_Misc_QuestionMark")
  help:SetPoint("RIGHT", gear, "LEFT", -4, 0)
  help:SetFrameLevel(P.frame:GetFrameLevel() + 10)
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
  local suggest = SmallButton(P.frame, T("Предложить макрос"), 160, function()
    Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    ns.Helper.SuggestDialog()
  end)
  suggest:SetPoint("RIGHT", help, "LEFT", -8, 0)
  suggest:SetFrameLevel(P.frame:GetFrameLevel() + 10)
  suggest:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(T("Предложить макрос"))
    GameTooltip:AddLine(T("Есть свой полезный макрос? Отправь его автору - он появится в аддоне у всех."), 1, 1, 1, true)
    GameTooltip:Show()
  end)
  suggest:SetScript("OnLeave", function() GameTooltip:Hide() end)
  P.frame.suggest = suggest
  help:SetScript("OnLeave", function() GameTooltip:Hide() end)
  P.frame.help = help

  -- Поиск по всем макросам - в самом низу окна, во всю ширину.
  P.frame.search = SearchBox(P.frame)
  P.frame.search:SetPoint("BOTTOMLEFT", P.frame, "BOTTOMLEFT", 20, 7)
  P.frame.search:SetPoint("BOTTOMRIGHT", P.frame, "BOTTOMRIGHT", -14, 7)

  -- Пергамент на месте внутренней панели. Сверху - место под вкладки
  -- специализаций, снизу - под поиск.
  local page = CreateFrame("Frame", nil, P.frame)
  if type(P.frame.Inset) == "table" then
    P.frame.Inset:ClearAllPoints()
    P.frame.Inset:SetPoint("TOPLEFT", P.frame, "TOPLEFT", 4, -ATTIC)
    P.frame.Inset:SetPoint("BOTTOMRIGHT", P.frame, "BOTTOMRIGHT", -6, CELLAR)
    page:SetPoint("TOPLEFT", P.frame.Inset, "TOPLEFT", 3, -3)
    page:SetPoint("BOTTOMRIGHT", P.frame.Inset, "BOTTOMRIGHT", -3, 3)
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
  P.frame.page = page

  P.frame.scroll = CreateFrame("ScrollFrame", "MacroCoachScroll", page, "UIPanelScrollFrameTemplate")
  P.frame.scroll:SetPoint("TOPLEFT", 0, -6)
  P.frame.scroll:SetPoint("BOTTOMRIGHT", -30, 6)
  ScrollTrack(P.frame.scroll)
  P.frame.child = CreateFrame("Frame", nil, P.frame.scroll)
  P.frame.child:SetSize(PAGE_W - 30, 10)
  P.frame.scroll:SetScrollChild(P.frame.child)
  if type(P.frame.scroll.ScrollBar) ~= "table" then
    P.frame.scroll:EnableMouseWheel(true)
    P.frame.scroll:SetScript("OnMouseWheel", function(self, d)
      local range = self:GetVerticalScrollRange()
      self:SetVerticalScroll(math.min(range, math.max(0, self:GetVerticalScroll() - d * 60)))
    end)
  end

  -- Вкладки специализаций сверху: значок в кольце и название
  P.frame.specTabs = {}
  for i = 1, MAX_SPEC_TABS do
    local b = SpecTabButton(P.frame)
    if i == 1 then b:SetPoint("BOTTOMLEFT", P.frame, "TOPLEFT", 62, -ATTIC + 1) end
    b:SetScript("OnClick", function()
      if b.selected then return end
      Sound("IG_CHARACTER_INFO_TAB")
      P.ShowClass(P.current, i)
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
    P.frame.specTabs[i] = b
  end

  -- Вкладки классов справа, как в книге заклинаний
  P.frame.classTabs = {}
  for i, class in ipairs(ns.CLASS_ORDER) do
    local t = SideTab(P.frame, ClassName(class))
    -- «Помощник» стоит первым и отдельно: остальные вкладки ниже с зазором
    t:SetPoint("TOPLEFT", P.frame, "TOPRIGHT", 0, -40 - (i - 1) * 46 - (class ~= "HELPER" and 16 or 0))
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
      P.ShowClass(class)
    end)
    P.frame.classTabs[i] = t
  end

  P.frame.UpdateSlots = function() end
  P.frame:SetScript("OnShow", function()
    if ns.macroTab then ns.macroTab:SetChecked(true) end
  end)
  P.frame:SetScript("OnHide", function()
    P.frame:SetFrameStrata("HIGH") -- после открытия из настроек было DIALOG
    if P.current == "SEARCH" then
      local back = searchBack or {}
      P.current, P.currentSpec, searchBack = back[1], back[2], nil
    end
    ns.ClearSearch()
    if P.editor then P.editor:Hide() end
    if P.builder then P.builder:Hide() end
    if P.iconPopup then P.iconPopup:Hide() end
    if ns.macroTab then ns.macroTab:SetChecked(false) end
  end)
  P.frame:Hide()

  -- Когда игра догрузит данные заклинаний и предметов - обновить названия.
  local pending
  P.frame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
  P.frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
  P.frame:SetScript("OnEvent", function()
    if pending or not P.frame:IsShown() then return end
    pending = true
    C_Timer.After(0.3, function()
      pending = nil
      if not P.frame:IsShown() then return end
      Relayout()
      if P.editor and P.editor:IsShown() then P.editor.Update() end
      if P.builder and P.builder:IsShown() then P.builder.Update() end
    end)
  end)
end

local function Toggle()
  Build()
  if P.frame:IsShown() then
    P.frame:Hide()
    return
  end
  -- Первое открытие аддона: сначала знакомство отдельным окном, само окно -
  -- когда знакомство закроют (Intro.lua). Подробный рассказ остался на
  -- вкладке «Зачем макросы».
  if ns.IntroFirst and ns.IntroFirst(function()
    if not P.frame:IsShown() then Toggle() end
  end) then return end
  P.frame:Show()
  -- Открываемся там, где были; в первый раз за вход - на «Помощнике»:
  -- дальше игрок сам переключает, куда ему нужно.
  DB().helperSeen = true
  P.ShowClass(P.current or "HELPER", P.current and P.currentSpec or nil)
end
ns.Toggle = Toggle

-- Открыть окно на нужной вкладке: Open("HELPER", 2) - «Проверка».
local function Open(class, spec)
  Build()
  if not P.frame:IsShown() then P.frame:Show() end
  DB().helperSeen = true
  P.ShowClass(class, spec)
end

-- Открыть справа от окна anchor (окна макросов игры).
local function OpenBeside(anchor)
  Build()
  P.frame:ClearAllPoints()
  P.frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 40, 0)
  if not P.frame:IsShown() then Toggle() end
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

P.SetMinimapHidden = function(hide)
  DB().minimap.hide = hide and true or false
  UpdateMinimapButton()
  if P.frame and P.frame.mmCheck then P.frame.mmCheck:SetChecked(not hide) end
end
ns.SetMinimapHidden = P.SetMinimapHidden

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

-- Команды чата: список в настройках и по /mc commands (описания
-- по-русски, переводятся при показе).
local COMMANDS = {
  { "/mc", "открыть или закрыть окно" },
  { "/mc help", "зачем макросы: короткое знакомство" },
  { "/mc tips", "рекомендуемые макросы для твоего класса" },
  { "/mc check", "проверить ранги и макросы на панелях" },
  { "/mc update", "обновить ранги на панелях и готовые макросы" },
  { "/mc translate", "перевести макрос с английского" },
  { "/mc share", "импорт и экспорт макросов" },
  { "/mc options", "открыть настройки" },
  { "/mc minimap", "показать или скрыть кнопку у миникарты" },
  { "/mc commands", "этот список в чат" },
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
    P.frame:SetFrameStrata("DIALOG")
    P.frame:Raise()
  end
  local open = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
  open:SetSize(200, 26)
  open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -14)
  open:SetText(T("Открыть окно"))
  open:SetScript("OnClick", function()
    Front()
    if not P.frame:IsShown() then ns.Toggle() end
    P.frame:Raise()
  end)
  local intro = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
  intro:SetSize(200, 26)
  intro:SetPoint("LEFT", open, "RIGHT", 10, 0)
  intro:SetText(T("Как пользоваться"))
  intro:SetScript("OnClick", function()
    Front()
    Open("HELPER", 1)
    P.frame:Raise()
  end)

  -- Настройки - простым списком, как у EasyCraft: галочки (что это - в
  -- подсказке при наведении), ползунок размера подписей и кнопки.
  local CHECKS = {
    { label = "Показывать кнопку у миникарты",
      get = function() return not DB().minimap.hide end,
      set = function(v) P.SetMinimapHidden(not v) end },
    { label = "Скрыть названия макросов",
      note = "Подпись под значком макроса на всех панелях. Работает и с Bartender, ElvUI и похожими панелями.",
      get = function() return DB().barNames.hide and true or false end,
      set = function(v)
        DB().barNames.hide = v or nil
        ns.ApplyBarNames()
      end },
  }
  for _, o in ipairs(P.HELP_OPTS or {}) do
    CHECKS[#CHECKS + 1] = { label = o.label, note = o.note, learn = o.key == "learn",
      get = function() return ns.Helper and ns.Helper.Opt(o.key) and true or false end,
      set = function(v)
        if not ns.Helper then return end
        ns.Helper.SetOpt(o.key, v)
        if o.resync then ns.Helper.ResyncReady() end
      end }
  end
  local checks, prev = {}, open
  for i, o in ipairs(CHECKS) do
    local c = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
    c:SetSize(26, 26)
    c:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -14 or -4)
    c.label = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    c.label:SetPoint("LEFT", c, "RIGHT", 4, 0)
    c.label:SetText(T(o.label))
    -- наведение и щелчок - и по подписи тоже
    c:SetHitRectInsets(0, -math.min(420, math.ceil(c.label:GetStringWidth() or 0) + 6), 0, 0)
    c:SetScript("OnClick", function(self) o.set(self:GetChecked() and true or false) end)
    if o.note then
      c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(T(o.label), 1, 0.82, 0)
        GameTooltip:AddLine(T(o.note) .. (o.learn and (" " .. T("То же - в подсказке, когда наводишь на макрос на панели.")) or ""), 1, 1, 1, true)
        GameTooltip:Show()
      end)
      c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    c.opt = o
    checks[i] = c
    prev = c
  end

  local Refresh
  -- размер подписей макросов на панелях
  local okS, sl = pcall(CreateFrame, "Slider", "MacroCoachNameSizeSlider", body, "OptionsSliderTemplate")
  if not okS then sl = nil end
  local slText, slSetting
  if sl then
    sl:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 6, -28)
    sl:SetWidth(220)
    sl:SetMinMaxValues(6, 20)
    sl:SetValueStep(1)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
    slText = sl.Text or _G[sl:GetName() .. "Text"]
    local low, high = sl.Low or _G[sl:GetName() .. "Low"], sl.High or _G[sl:GetName() .. "High"]
    if type(low) == "table" and low.SetText then low:SetText("6") end
    if type(high) == "table" and high.SetText then high:SetText("20") end
    sl:SetScript("OnValueChanged", function(_, v)
      if slSetting then return end -- значение ставит сама страница
      DB().barNames.size = math.floor(v + 0.5)
      ns.ApplyBarNames()
      Refresh()
    end)
  end
  local function PlainButton(text, width, onClick, tip)
    local b = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    b:SetScript("OnEnter", function(self)
      local text2 = type(tip) == "function" and tip() or tip
      if not text2 then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
      GameTooltip:SetText(self:GetText() or "", 1, 0.82, 0)
      GameTooltip:AddLine(text2, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
  end
  local sizeReset = PlainButton(T("Как в игре"), 120, function()
    DB().barNames.size = nil
    ns.ApplyBarNames()
    Refresh()
  end)
  if sl then sizeReset:SetPoint("LEFT", sl, "RIGHT", 18, 0) else sizeReset:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 2, -14) end

  -- резервная копия и очистка макросов игры
  local function BackupTip()
    local when, saved = ns.Backup.Info()
    return T("Сохраняет все макросы из окна /macro: общие и этого персонажа. Из копии можно вернуть текст изменённых макросов и удалённые макросы.")
      .. "\n" .. (when and (T("Копия от %s: макросов %d.")):format(date("%d.%m.%Y %H:%M", when), saved) or T("Копии пока нет."))
  end
  local WIPE_TIP = T("Удаляет макросы из окна /macro: общие (видны всем персонажам) или только этого персонажа. Готовые и свои макросы в аддоне останутся, их можно добавить снова.")
  local bSave = PlainButton(T("Сохранить копию"), 240, function()
    ns.Backup.Save()
    Refresh()
  end, BackupTip)
  if sl then bSave:SetPoint("TOPLEFT", sl, "BOTTOMLEFT", -4, -30) else bSave:SetPoint("TOPLEFT", sizeReset, "BOTTOMLEFT", 0, -14) end
  local bRestore = PlainButton(T("Вернуть из копии"), 240, function() ns.Backup.Restore() end, BackupTip)
  bRestore:SetPoint("LEFT", bSave, "RIGHT", 10, 0)
  local wipeShared = PlainButton("", 240, function() ns.AskWipe(false) end, WIPE_TIP)
  wipeShared:SetPoint("TOPLEFT", bSave, "BOTTOMLEFT", 0, -8)
  local wipeChar = PlainButton("", 240, function() ns.AskWipe(true) end, WIPE_TIP)
  wipeChar:SetPoint("LEFT", wipeShared, "RIGHT", 10, 0)
  local restoreShared = PlainButton("", 240, function()
    ns.RestoreWiped(false)
    Refresh()
  end)
  restoreShared:SetPoint("TOPLEFT", wipeShared, "BOTTOMLEFT", 0, -8)
  local restoreChar = PlainButton("", 240, function()
    ns.RestoreWiped(true)
    Refresh()
  end)
  restoreChar:SetPoint("TOPLEFT", wipeChar, "BOTTOMLEFT", 0, -8)

  -- Импорт и экспорт - той же страницей, что во вкладке «Свои макросы»
  -- окна аддона. Строится при первом показе: к этому времени загружены все
  -- файлы и известна ширина страницы.
  local hostB = CreateFrame("Frame", nil, body)
  hostB:SetSize(600, 10)
  local sharePage
  local restoreRows = false

  Refresh = function()
    for _, c in ipairs(checks) do c:SetChecked(c.opt.get() and true or false) end
    local cfg = DB().barNames
    local size = cfg.size or ns.DefaultNameSize()
    if sl then
      slSetting = true
      sl:SetValue(size)
      slSetting = nil
      if slText then slText:SetText(T("Размер шрифта:") .. " " .. size) end
    end
    sizeReset:SetEnabled(cfg.size ~= nil)
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
    restoreRows = backShared > 0 or backChar > 0
    bRestore:SetEnabled(ns.Backup.Info() ~= nil)
    hostB:ClearAllPoints()
    hostB:SetPoint("TOPLEFT", restoreRows and restoreShared or wipeShared, "BOTTOMLEFT", -16, -16)
  end

  -- команды чата
  local cmdHead = body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  cmdHead:SetPoint("TOPLEFT", hostB, "BOTTOMLEFT", 16, -20)
  cmdHead:SetText(T("Команды в чате"))
  local cmds = body:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  cmds:SetPoint("TOPLEFT", cmdHead, "BOTTOMLEFT", 0, -8)
  cmds:SetWidth(560)
  cmds:SetJustifyH("LEFT")
  if cmds.SetSpacing then cmds:SetSpacing(4) end
  cmds:SetText(table.concat(CommandLines(), "\n"))

  local function LayoutHosted()
    Refresh()
    local h2 = sharePage and sharePage:Layout() or 10
    hostB:SetHeight(h2)
    -- высота всей страницы: шапка, галочки, ползунок, кнопки, импорт и команды
    body:SetHeight(170 + #checks * 30 + 64 + (restoreRows and 3 or 2) * 30 + 16 + h2 + 20 + 24
      + (cmds:GetStringHeight() or 200) + 30)
  end
  panel:SetScript("OnShow", function()
    lang.Refresh()
    if not sharePage and ns.BuildHelperPage then
      Build() -- страница обращается к окну аддона
      hostB:SetWidth(math.max(520, math.floor(body:GetWidth() or 600) - 4))
      P.host = { child = hostB }
      sharePage = ns.BuildHelperPage("share", "host:share")
      P.host = nil
    end
    P.hostRelayout = LayoutHosted
    LayoutHosted()
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

SLASH_MACROCOACH1 = "/mc"
SLASH_MACROCOACH2 = "/coach" -- прежняя команда: работает и дальше
SLASH_MACROCOACH3 = "/macrocoach"
SlashCmdList.MACROCOACH = function(msg)
  msg = strtrim((msg or ""):lower())
  if msg == "minimap" then
    P.SetMinimapHidden(not DB().minimap.hide)
    Print(DB().minimap.hide and T("кнопка у миникарты скрыта (вернуть: /mc minimap).") or T("кнопка у миникарты показана."))
  elseif msg == "help" or msg == "start" then
    Open("HELPER", 1)
  elseif msg == "tips" then
    local _, class = UnitClass("player")
    class = ns.MACROS[class] and class or "GENERAL"
    Open(class, ns.UI.TabIndex(class, "Рекомендации") or 1)
  elseif msg == "check" or msg == "ranks" then
    Open("HELPER", 2)
  elseif msg == "update" then
    ns.UpdateAll()
  elseif msg == "translate" then
    Open("CUSTOM", 1)
    P.OpenCustomText(nil, B.New())
  elseif msg == "intro" then
    Open(P.current or "HELPER")
    if ns.ShowIntro then ns.ShowIntro() end
  elseif msg == "lang" then
    -- перевести готовые макросы в игре на нынешний язык и сказать, что не тронуто
    if ns.Helper and ns.Helper.ResyncLanguage then ns.Helper.ResyncLanguage(0, true) end
  elseif msg == "beside" then
    local db = DB()
    db.besideMacro = db.besideMacro == false
    Print(db.besideMacro and T("окно будет открываться рядом с окном макросов игры.")
      or T("окно больше не открывается само рядом с окном макросов игры."))
  elseif msg == "share" or msg == "export" then
    Open("CUSTOM", 3)
  elseif msg == "data" then
    if ns.Helper then ns.Helper.PrintDataCheck() end
  elseif msg == "options" or msg == "config" then
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
    if P.frame and P.frame:IsShown() then
      P.frame:Hide()
    else
      OpenBeside(MacroFrame)
    end
    self:SetChecked(P.frame and P.frame:IsShown() or false)
  end)
  ns.macroTab = tab
  -- Окно макросов игры открыли - MacroCoach сам встаёт рядом, закрыли -
  -- уходит вместе с ним (если открылся сам). Выключить: /mc beside.
  MacroFrame:HookScript("OnShow", function()
    if DB().besideMacro == false then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if P.frame and P.frame:IsShown() then return end
    local ok = pcall(OpenBeside, MacroFrame)
    ns.openedBeside = ok and P.frame and P.frame:IsShown() or nil
    tab:SetChecked(P.frame and P.frame:IsShown() or false)
  end)
  MacroFrame:HookScript("OnHide", function()
    if ns.openedBeside and P.frame and P.frame:IsShown() then P.frame:Hide() end
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
  RefreshCustom = function(stay) P.RefreshCustom(stay) end, Relayout = Relayout, Open = Open,
  Frame = function() return P.frame end, Pages = function() return pages end,
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
