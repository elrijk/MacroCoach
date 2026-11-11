-- MacroCoach. Правка макроса: выбор значка, редактор текста, шаблоны и конструктор своих макросов.
local ADDON, ns = ...
local P = ns.P
local T, PAGE_W, QUESTION, MAX_CHARS, Print, DB = P.T, P.PAGE_W, P.QUESTION, P.MAX_CHARS, P.Print, P.DB
local B, CustomList, CustomMacro, Key, Loc, Effective = P.B, P.CustomList, P.CustomMacro, P.Key, P.Loc, P.Effective
local Render, ToDisplay, ToStored, CharCount, IDLine, RequestSpells = P.Render, P.ToDisplay, P.ToStored, P.CharCount, P.IDLine, P.RequestSpells
local FirstIcon, SyncGameMacro, Text, ScrollTrack, CARD, GOLD = P.FirstIcon, P.SyncGameMacro, P.Text, P.ScrollTrack, P.CARD, P.GOLD
local LIGHT, GREY, Card, Relayout = P.LIGHT, P.GREY, P.Card, P.Relayout

-------------------------------------------------------------------------------
--  Значок макроса: окно игры «Смена названия/значка»
-------------------------------------------------------------------------------
-- «?» = авто: игра покажет значок первого заклинания (#showtooltip).
local function NormalizeIcon(tex)
  if tex == nil or tex == QUESTION or tex == "" then return nil end
  if type(tex) == "string" and tex:upper():find("INV_MISC_QUESTIONMARK", 1, true) then return nil end
  return tex
end

local function OpenIconPicker(icon, name, onDone)
  if not (type(IconSelectorPopupFrameTemplateMixin) == "table" and type(IconDataProviderMixin) == "table"
    and CreateAndInitFromMixin and IconDataProviderExtraType and GenerateClosure) then
    Print(T("выбор значка недоступен в этой версии игры."))
    return
  end
  if not P.iconPopup then
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
    P.iconPopup = p
  end
  local p = P.iconPopup
  p.onDone = onDone
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", P.frame, "TOPRIGHT", 36, 0)
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
  local area = P.frame.page
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
    P.OpenBuilder(e.entry, m)
  end)
  save:SetScript("OnClick", function()
    if e.mode == "custom" then
      if P.SaveCustom(e.entry, CustomFromText()) then
        e:Hide()
        P.RefreshCustom()
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
  e:SetScript("OnShow", function() P.frame.scroll:Hide() end)
  e:SetScript("OnHide", function()
    body:ClearFocus()
    name:ClearFocus()
    reset.armed = nil
    reset:SetText(T("Вернуть исходный"))
    if not (P.builder and P.builder:IsShown()) then P.frame.scroll:Show() end
  end)
  return e
end

P.OpenEditor = function(class, m)
  P.editor = P.editor or BuildEditor()
  if P.builder then P.builder:Hide() end
  local em = Effective(class, m)
  local text = ToDisplay(em.body)
  P.editor.mode, P.editor.class, P.editor.m = "preset", class, m
  P.editor.autoIcon = m.icon
  P.editor.iconBtn:SetIcon(DB().edits[Key(class, m)] and DB().edits[Key(class, m)].icon, QUESTION)
  P.editor.reset:Show()
  P.editor.toBuilder:Hide()
  P.editor.title:SetText(T("Изменить: ") .. select(2, Loc(class, m)))
  P.editor.name:SetText(em.name)
  P.editor.body:SetText(text)
  P.editor.orig:SetText("|cffffd100" .. T("Исходный текст:") .. "|r\n" .. ToDisplay(ns.SafeBody and ns.SafeBody(m.body) or m.body))
  P.editor.reset:SetEnabled(em.edited == true)
  P.editor:Show()
  P.editor.Update()
  P.editor.body:SetFocus()
end

-- Свой макрос текстом: entry - сохранённый (nil - новый), model - черновик.
P.OpenCustomText = function(entry, model)
  P.editor = P.editor or BuildEditor()
  if P.builder then P.builder:Hide() end
  P.editor.mode, P.editor.entry, P.editor.model = "custom", entry, model
  P.editor.autoIcon = nil
  P.editor.title:SetText(entry and (T("Изменить текстом: ") .. entry.name) or T("Новый макрос текстом"))
  P.editor.name:SetText(model.name or "")
  P.editor.body:SetText(ToDisplay(B.Build(model)))
  P.editor.orig:SetText("")
  P.editor.reset:Hide()
  P.editor.toBuilder:Show()
  P.editor.iconBtn:SetIcon(model.icon, QUESTION)
  P.editor:Show()
  P.editor.Update()
  P.editor.body:SetFocus()
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
P.SaveCustom = function(entry, model)
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

-- Line type menu, grouped.
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
  local area = P.frame.page
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
    if P.SaveCustom(e.entry, Sync()) then
      e:Hide()
      P.RefreshCustom()
    end
  end)
  cancel:SetScript("OnClick", function() e:Hide() end)
  e:SetScript("OnShow", function() P.frame.scroll:Hide() end)
  e:SetScript("OnHide", function()
    name:ClearFocus()
    desc:ClearFocus()
    body:ClearFocus()
    if not (P.editor and P.editor:IsShown()) then P.frame.scroll:Show() end
  end)
  return e
end

-- entry - свой макрос (nil - новый), model - что показать (копия entry или шаблон).
P.OpenBuilder = function(entry, model)
  P.builder = P.builder or BuildBuilder()
  if P.editor then P.editor:Hide() end
  model = model or (entry and B.Copy(entry)) or B.New()
  if not model.lines then B.Parse("", model) end
  P.builder.entry, P.builder.model = entry, model
  P.builder.title:SetText(entry and (T("Конструктор: ") .. entry.name) or T("Новый макрос"))
  P.builder.name:SetText(model.name or "")
  P.builder.desc:SetText(model.desc or "")
  P.builder.tip:SetChecked(model.tooltip and true or false)
  P.builder.iconBtn:SetIcon(model.icon, QUESTION)
  P.builder:Show()
  P.builder.sf:SetVerticalScroll(0)
  P.builder.Layout()
end

