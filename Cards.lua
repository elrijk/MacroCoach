-- MacroCoach. Оформление окна и карточка макроса: шапка страницы, значки, вкладки, строка макроса.
local ADDON, ns = ...
local P = ns.P
local T, TAB_H, QUESTION, pages, Print, CustomList = P.T, P.TAB_H, P.QUESTION, P.pages, P.Print, P.CustomList
local Effective, ToDisplay, HighlightIDs, SpellsOf, ItemIDs, IDLine = P.Effective, P.ToDisplay, P.HighlightIDs, P.SpellsOf, P.ItemIDs, P.IDLine
local RequestSpells, FirstIcon, Pickup, OnBars = P.RequestSpells, P.FirstIcon, P.Pickup, P.OnBars

-------------------------------------------------------------------------------
--  Оформление: рамка как у окна макросов игры, пергамент как в книге
--  заклинаний WoW Forever, вкладки классов справа, специализаций - сверху.
-------------------------------------------------------------------------------
P.INK = { 0.25, 0.14, 0.04 }
if type(SPELLBOOK_FONT_COLOR) == "table" and SPELLBOOK_FONT_COLOR.GetRGB then
  P.INK = { SPELLBOOK_FONT_COLOR:GetRGB() }
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
        -- h.stack - кнопки столбиком, каждая на своей строке
        if x > 26 and (self.stack or x + b:GetWidth() > width - 26) then
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
    if class == "CUSTOM" then P.OpenBuilder(m) else P.OpenEditor(class, m) end
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
      P.RefreshCustom()
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
  local page = CreateFrame("Frame", nil, P.frame.child)
  page:SetPoint("TOPLEFT")
  local width = P.frame.child:GetWidth()
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
  if not (P.frame and P.currentKey and pages[P.currentKey]) then return end
  local pos = P.frame.scroll:GetVerticalScroll()
  local h = pages[P.currentKey]:Layout()
  P.frame.child:SetHeight(h)
  P.frame.scroll:SetVerticalScroll(math.min(pos, math.max(0, h - P.frame.scroll:GetHeight())))
end
ns.Relayout = Relayout

-- Для соседних файлов.
P.MAX_SPEC_TABS, P.Text, P.HasAtlas, P.INK_TITLE, P.PageHeader, P.Badge = MAX_SPEC_TABS, Text, HasAtlas, INK_TITLE, PageHeader, Badge
P.Sound, P.ScrollTrack, P.SideTab, P.ClassName, P.SetClassIcon, P.SpecIcon = Sound, ScrollTrack, SideTab, ClassName, SetClassIcon, SpecIcon
P.TAB_ICON, P.SpecTabButton, P.SpecTabs, P.PlayerSpecTab, P.selectedSpec, P.CARD = TAB_ICON, SpecTabButton, SpecTabs, PlayerSpecTab, selectedSpec, CARD
P.GOLD, P.LIGHT, P.GREY, P.Card, P.BuildRow, P.BuildPage = GOLD, LIGHT, GREY, Card, BuildRow, BuildPage
P.Relayout = Relayout
