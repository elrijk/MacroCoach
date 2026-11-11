local _, ns = ...
local T = ns.T
local UI = ns.UI
local floor, max = math.floor, math.max

-------------------------------------------------------------------------------
--  Знакомство с аддоном одним экраном (тот же вид - в EasyCraft): три
--  главные возможности, «И ещё» и одна кнопка. Показывается при первом
--  открытии; дальше - по кнопке «?» у крестика окна и по /coach intro.
-------------------------------------------------------------------------------
local WIDTH = 760
local SIDE = 28 -- поля окна слева и справа
local GAP = 12 -- между блоками
local COLS = 3
local ICONS = "Interface\\Icons\\"

local TITLE = "MacroCoach: готовые макросы без кода"
local KILLER = {
  { "INV_Misc_Book_09", "Готовые макросы", "294 для всех классов" },
  { "Ability_Hunter_SniperShot", "Одна кнопка", "«Добавить» - и на панель" },
  { "Spell_Holy_HolyBolt", "Проверка", "Находит старые ранги и ошибки" },
}
local MORE_HEAD = "И ещё"
local MORE = {
  { "INV_Misc_Gear_01", "Конструктор", "Свой макрос из готовых строк - код писать не нужно." },
  { "INV_Letter_15", "Ссылка в чат", "Значок на карточке: друг с MacroCoach откроет макрос щелчком." },
  { "INV_Misc_Note_06", "Импорт и экспорт", "Все свои макросы - одним кодом." },
  { "INV_Misc_Book_11", "Смена языка игры", "Сменил язык игры - макросы на панелях переведутся сами." },
  { "INV_Potion_51", "Умные расходники", "Кнопка показывает то зелье и те бинты, что есть в сумках." },
  { "INV_Misc_QuestionMark", "Объяснение", "«?» на карточке: что делает каждая строка макроса." },
}
local BUTTON = "Поехали"

local win

-- Значок в золотой рамке, как значки макросов.
local function ring(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetAllPoints()
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.edge = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f.edge:SetPoint("TOPLEFT", -4, 4)
  f.edge:SetPoint("BOTTOMRIGHT", 4, -4)
  if f.edge.SetBackdrop then
    f.edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
    f.edge:SetBackdropBorderColor(1, 0.82, 0, 1)
  end
  return f
end

local function centered(fs, width)
  fs:SetJustifyH("CENTER")
  fs:SetWidth(width)
end

local function rule(parent, w, a)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(w, 1)
  t:SetColorTexture(0.85, 0.68, 0.3, a or 0.8)
  return t
end

local function build()
  local f = CreateFrame("Frame", "MacroCoachIntroFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(WIDTH, 400)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  UI.Card(f)
  f:SetBackdropColor(0.04, 0.03, 0.02, 1)
  f:SetBackdropBorderColor(0.75, 0.6, 0.3, 1)
  tinsert(UISpecialFrames, "MacroCoachIntroFrame")
  -- фон: сверху тёплый коричневый, книзу уходит в чёрный
  local bg = f:CreateTexture(nil, "BORDER")
  bg:SetPoint("TOPLEFT", 4, -4)
  bg:SetPoint("BOTTOMRIGHT", -4, 4)
  bg:SetColorTexture(1, 1, 1, 1)
  local ok = CreateColor and pcall(bg.SetGradient, bg, "VERTICAL", CreateColor(0.03, 0.025, 0.02, 1), CreateColor(0.2, 0.14, 0.08, 1))
  if not ok then bg:SetColorTexture(0.1, 0.075, 0.05, 1) end
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- шапка: что за аддон
  f.title = UI.Text(f, "SystemFont_Huge1", "GameFontNormalHuge", UI.GOLD, true)
  centered(f.title, WIDTH - SIDE * 2 - 40)
  f.title:SetPoint("TOP", 0, -26)
  local file, _, flags = f.title:GetFont()
  if file then f.title:SetFont(file, 24, flags) end

  -- три главные возможности: крупные блоки в золотой рамке
  f.killer = {}
  for i = 1, #KILLER do
    local c = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    UI.Card(c)
    c:SetBackdropColor(0.2, 0.14, 0.05, 0.9)
    c:SetBackdropBorderColor(1, 0.82, 0, 1)
    c.icon = ring(c, 72)
    c.icon:SetPoint("TOP", 0, -28)
    c.head = UI.Text(c, "SystemFont_Large", "GameFontNormalLarge", UI.GOLD, true)
    c.head:SetJustifyH("CENTER")
    c.head:SetPoint("TOP", c.icon, "BOTTOM", 0, -20)
    c.text = UI.Text(c, "SystemFont_Med2", "GameFontHighlight", { 0.92, 0.9, 0.84 }, true)
    c.text:SetJustifyH("CENTER")
    c.text:SetPoint("TOP", c.head, "BOTTOM", 0, -8)
    f.killer[i] = c
  end

  -- «И ещё»: подзаголовок с линиями по бокам
  f.moreHead = UI.Text(f, "SystemFont_Med3", "GameFontNormal", UI.GOLD)
  f.moreHead:SetJustifyH("CENTER")
  f.moreL, f.moreR = rule(f, 10, 0.5), rule(f, 10, 0.5)

  -- остальное: значок и название под ним, в один ряд; что это - в подсказке
  f.more = {}
  for i = 1, #MORE do
    local c = CreateFrame("Frame", nil, f)
    c:EnableMouse(true)
    c.icon = ring(c, 40)
    c.icon:SetPoint("TOP", 0, -4)
    c.head = UI.Text(c, "SystemFont_Med2", "GameFontHighlight", UI.GOLD, true)
    c.head:SetJustifyH("CENTER")
    c.head:SetPoint("TOP", c.icon, "BOTTOM", 0, -10)
    c:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(T(MORE[i][2]), 1, 0.82, 0)
      GameTooltip:AddLine(T(MORE[i][3]), 1, 1, 1, true)
      GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.more[i] = c
  end

  -- одна кнопка
  f.go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.go:SetSize(220, 32)
  f.go:SetPoint("BOTTOM", 0, 22)
  f.go:SetScript("OnClick", function() f:Hide() end)
  f:Hide()
  return f
end

local function show(f)
  f.title:SetText(T(TITLE))
  local y = 26 + f.title:GetStringHeight() + 24

  -- главные возможности
  local colW = floor((WIDTH - SIDE * 2 - GAP * (COLS - 1)) / COLS)
  local h = 0
  for i, c in ipairs(f.killer) do
    local d = KILLER[i]
    c.icon.icon:SetTexture(ICONS .. d[1])
    c.head:SetWidth(colW - 24)
    c.head:SetText(T(d[2]))
    c.text:SetWidth(colW - 28)
    c.text:SetText(T(d[3]))
    h = max(h, 28 + 72 + 20 + c.head:GetStringHeight() + 8 + c.text:GetStringHeight() + 24)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", SIDE + (i - 1) * (colW + GAP), -y)
    c:SetWidth(colW)
  end
  for _, c in ipairs(f.killer) do c:SetHeight(h) end
  y = y + h + 24

  -- подзаголовок с линиями по бокам
  f.moreHead:SetText(T(MORE_HEAD))
  f.moreHead:ClearAllPoints()
  f.moreHead:SetPoint("TOP", f, "TOP", 0, -y)
  local tw = f.moreHead:GetStringWidth() or 60
  local lw = floor((WIDTH - SIDE * 2 - tw - 32) / 2)
  f.moreL:SetWidth(lw)
  f.moreR:SetWidth(lw)
  f.moreL:ClearAllPoints()
  f.moreL:SetPoint("RIGHT", f.moreHead, "LEFT", -16, 0)
  f.moreR:ClearAllPoints()
  f.moreR:SetPoint("LEFT", f.moreHead, "RIGHT", 16, 0)
  y = y + f.moreHead:GetStringHeight() + 18

  -- остальное: все значки в один ряд
  -- значки рядом друг с другом, по центру окна
  local cellW = 112
  local x0 = floor((WIDTH - #MORE * cellW) / 2)
  local mh = 0
  for i, c in ipairs(f.more) do
    local d = MORE[i]
    c.icon.icon:SetTexture(ICONS .. d[1])
    c.head:SetWidth(cellW - 8)
    c.head:SetText(T(d[2]))
    mh = max(mh, 4 + 40 + 10 + c.head:GetStringHeight())
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", x0 + (i - 1) * cellW, -y)
    c:SetWidth(cellW)
  end
  for _, c in ipairs(f.more) do c:SetHeight(mh) end
  y = y + mh

  f.go:SetText(T(BUTTON))
  f:SetHeight(y + 26 + 32 + 22)
end

-- after - что сделать, когда окно закроют (любым способом), один раз.
function ns.ShowIntro(after)
  local main = UI.Frame()
  if not win then
    win = build()
    win:SetScript("OnHide", function(s)
      local fn = s.after
      s.after = nil
      if fn then pcall(fn) end
    end)
  end
  local shown = main and main:IsShown()
  win:ClearAllPoints()
  win:SetPoint("CENTER", shown and main or UIParent, "CENTER", 0, shown and 0 or 40)
  UI.DB().onboarded = true
  win.after = after
  local ok, err = pcall(show, win)
  if not ok then UI.Print(tostring(err)) end
  win:Show()
  win:Raise()
end

-- ВРЕМЕННО, ДЛЯ ПРОВЕРКИ: знакомство показывается при каждом открытии
-- аддона. Перед релизом поставить false.
local TEST_ALWAYS = false

-- Первое открытие аддона: сначала знакомство, само окно MacroCoach - когда
-- знакомство закроют. Возвращает true, если окно открывать пока не надо.
function ns.IntroFirst(openMain)
  if ns.skipIntro then ns.skipIntro = nil; return false end -- открываем окно после знакомства
  if UI.DB().onboarded and not TEST_ALWAYS then return false end
  ns.ShowIntro(function()
    ns.skipIntro = true
    openMain()
    ns.skipIntro = nil
  end)
  return true
end
