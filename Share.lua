local ADDON, ns = ...
local T = ns.T
local UI = ns.UI
local H = ns.Helper

-------------------------------------------------------------------------------
--  Наборы по специализации и ссылка на макрос в чат.
--
--  Набор: все макросы вкладки специализации создаются в игре одним нажатием
--  (кнопка в шапке вкладки). На панель их кладёт игрок сам.
--
--  Ссылка: в строку чата вставляется «[MacroCoach:...]». У тех, у кого стоит
--  MacroCoach, она становится ссылкой: щелчок по готовому макросу открывает
--  его в окне аддона, по своему - предлагает добавить его в «Мои макросы».
--  Готовый: «[MacroCoach:R~КЛАСС/имя]». Свой: «[MacroCoach:C~...]» - та же
--  запись, что в «Импорт/экспорт», скобки внутри заменены на \( и \).
-------------------------------------------------------------------------------
local HEADER = "MacroCoach:1"
local CHAT_MAX = 255

-------------------------------------------------------------------------------
--  Набор
-------------------------------------------------------------------------------
function ns.AddSet(class, list, label)
  if InCombatLockdown() then
    UI.Print(T("в бою макросы создавать нельзя."))
    return
  end
  local shared = class == "GENERAL"
  local added, had, failed = 0, 0, 0
  ns.quietPickup = true
  for _, m in ipairs(list) do
    local home = m.homeClass or class
    local em = UI.Effective(home, m)
    if UI.FindMacro(em) then
      had = had + 1
    else
      local ok, index = pcall(UI.Pickup, em, nil, shared or home == "GENERAL", "create")
      if ok and index then added = added + 1 else failed = failed + 1 end
    end
  end
  ns.quietPickup = nil
  UI.Print((T("набор «%s»: добавлено %d, уже было %d, не получилось %d.")):format(T(label or ""), added, had, failed))
  if failed > 0 then
    UI.Print(T("не получилось - значит, нет места в /macro или заклинания ещё загружаются: нажми ещё раз."))
  end
  if UI.Relayout then UI.Relayout() end
end

-------------------------------------------------------------------------------
--  Ссылка в чат
-------------------------------------------------------------------------------
local function Wrap(s) return (s:gsub("%[", "\\("):gsub("%]", "\\)")) end
local function Unwrap(s)
  return (s:gsub("\\(.)", function(c)
    if c == "(" then return "[" elseif c == ")" then return "]" end
    return "\\" .. c
  end))
end

local function ToChat(text)
  local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
  if box then
    box:Insert(text)
  elseif ChatFrameUtil and ChatFrameUtil.OpenChat then
    ChatFrameUtil.OpenChat(text)
  elseif ChatFrame_OpenChat then
    ChatFrame_OpenChat(text)
  end
end

function ns.LinkToChat(class, m)
  local text
  if class == "CUSTOM" then
    if not (H and H.RecordCustom) then return end
    text = "[MacroCoach:" .. Wrap(H.RecordCustom(m)) .. "]"
  else
    text = "[MacroCoach:R~" .. class .. "/" .. m.name .. "]"
  end
  if #text > CHAT_MAX then
    UI.Print(T("макрос слишком длинный для чата: отправь его кодом из «Импорт/экспорт»."))
    return
  end
  ToChat(text)
end

-- Готовый макрос по ключу «КЛАСС/имя».
local function FindReady(key)
  local class, name = key:match("^(%u+)/(.+)$")
  for _, g in ipairs(class and ns.MACROS[class] or {}) do
    for _, m in ipairs(g.list) do
      if m.name == name then return class, m end
    end
  end
end

-- Что показать в ссылке: название макроса или nil (запись не наша).
local function LinkName(payload)
  local kind, rest = payload:match("^(%u)~(.+)$")
  if kind == "R" then
    local class, m = FindReady(rest)
    if not m then return nil end
    local em = UI.Effective(class, m)
    return em.title or em.name
  elseif kind == "C" then
    local name = Unwrap(rest):match("^(.-)~")
    if name and name ~= "" then return (name:gsub("\\(.)", "%1")) end
  end
end

local function Filter(_, _, msg, ...)
  if type(msg) ~= "string" or not msg:find("[MacroCoach:", 1, true) then return false end
  local changed
  local new = msg:gsub("%[MacroCoach:(.-)%]", function(payload)
    local name = LinkName(payload)
    if not name then return nil end
    changed = true
    return "|cff33ff99|Haddon:" .. ADDON .. ":" .. payload .. "|h[MacroCoach: " .. name .. "]|h|r"
  end)
  if changed then return false, new, ... end
  return false
end

local EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
  "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
  "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }
local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then
  for _, e in ipairs(EVENTS) do pcall(addFilter, e, Filter) end
end

-- Свой макрос из чата: только с согласия и только в «Мои макросы» аддона -
-- в игру он попадёт, когда игрок сам нажмёт «Добавить».
StaticPopupDialogs.MACROCOACH_CHAT_IMPORT = {
  text = "%s",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function(_, record)
    if not (record and H and H.Import) then return end
    local nc, _, _, same = H.Import(HEADER .. "\n" .. record)
    if (nc or 0) > 0 then
      UI.Print(T("макрос из чата добавлен в «Мои макросы». Посмотри его текст, прежде чем добавлять в игру."))
    elseif (same or 0) > 0 then
      UI.Print(T("такой макрос у тебя уже есть."))
    else
      UI.Print(T("не получилось прочитать макрос из ссылки."))
    end
    UI.RefreshCustom()
    UI.Open("CUSTOM", 1)
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local lastClick = 0
local function OnLink(link)
  if type(link) ~= "string" then return end
  local payload = link:match("^addon:" .. ADDON .. ":(.+)$")
  if not payload then return end
  -- и хук, и событие игры могут прийти на один щелчок
  local now = GetTime()
  if now - lastClick < 0.2 then return end
  lastClick = now
  local kind, rest = payload:match("^(%u)~(.+)$")
  if kind == "R" then
    local class, m = FindReady(rest)
    if not m then return end
    local em = UI.Effective(class, m)
    UI.Open(class)
    UI.ShowSearch(em.title or em.name)
  elseif kind == "C" then
    local name = LinkName(payload) or "?"
    StaticPopup_Show("MACROCOACH_CHAT_IMPORT", (T("Добавить макрос «%s» из чата в «Мои макросы»?")):format(name), nil,
      "C~" .. Unwrap(rest))
  end
end

if EventRegistry and EventRegistry.RegisterCallback then
  EventRegistry:RegisterCallback("SetItemRef", function(_, link) OnLink(link) end, ns)
end
if type(SetItemRef) == "function" then
  hooksecurefunc("SetItemRef", function(link) OnLink(link) end)
end
