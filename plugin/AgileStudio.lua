--!strict
-- AgileStudio Plugin — a fresh Roblox Studio AI assistant (expanded build).
-- Bold branded dark/light UI, mascot everywhere, multi-chat, streaming, tools.
-- No code copied from any other plugin; built from scratch.

-- ============================================================ Services
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local StudioService = nil
pcall(function() StudioService = game:GetService("StudioService") end)

local PLUGIN = (typeof(plugin) == "Instance" and plugin) or nil

-- ============================================================ Palette
local RGB = {
	dark = {
		bg = {18,18,30}, panel = {30,30,48}, panel2 = {24,24,40}, surface = {42,42,66},
		indigo = {91,91,214}, indigoLight = {150,150,245}, mint = {61,220,151}, amber = {255,178,62},
		text = {240,240,248}, textDim = {165,168,188}, userBubble = {91,91,214},
		assistBubble = {38,38,60}, danger = {240,90,110}, code = {20,22,34}, border = {60,60,92},
	},
	light = {
		bg = {244,245,250}, panel = {255,255,255}, panel2 = {238,240,248}, surface = {228,231,242},
		indigo = {91,91,214}, indigoLight = {110,110,230}, mint = {40,170,120}, amber = {230,150,40},
		text = {30,32,48}, textDim = {110,114,140}, userBubble = {91,91,214},
		assistBubble = {235,237,245}, danger = {220,70,90}, code = {246,247,251}, border = {210,214,228},
	},
}
local function col(t, key)
	local a = t[key]
	return Color3.fromRGB(a[1], a[2], a[3])
end
local THEME = "dark"
local function P() return RGB[THEME] end
local function C(key) return col(P(), key) end

-- ============================================================ Config / settings
local SET = {
	backend = "https://agilestudio.onrender.com",
	theme = "dark",
	model = "",
	token = "",
	autoTools = {},
}
local SETTING_KEY = "AgileStudioSettings"
local CONV_KEY = "AgileStudioConversations"

local function loadSettings()
	if PLUGIN then
		local ok, v = pcall(function() return PLUGIN:GetSetting(SETTING_KEY) end)
		if ok and type(v) == "string" and v ~= "" then
			pcall(function() SET = HttpService:JSONDecode(v) end)
		end
	else
		pcall(function()
			local f = isfile and nil
		end)
	end
	THEME = SET.theme or "dark"
end
local function saveSettings()
	if PLUGIN then
		pcall(function() PLUGIN:SetSetting(SETTING_KEY, HttpService:JSONEncode(SET)) end)
	end
end

-- ============================================================ Small UI helpers
local function inst(class, parent, name)
	local o = Instance.new(class)
	if name then o.Name = name end
	if parent then o.Parent = parent end
	return o
end
local function corner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = o
	return c
end
local function stroke(o, color, w, transparent)
	local s = Instance.new("UIStroke")
	s.Color = color or C("border")
	s.Thickness = w or 1
	s.Transparency = transparent or 0
	s.ApplyStrokeTransparencyToCorners = true
	s.Parent = o
	return s
end
local function pad(o, p)
	local u = Instance.new("UIPadding")
	u.PaddingTop = UDim.new(0, p); u.PaddingBottom = UDim.new(0, p)
	u.PaddingLeft = UDim.new(0, p); u.PaddingRight = UDim.new(0, p)
	u.Parent = o
	return u
end
local function listlayout(parent, pad, align, dir, fill)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, pad or 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	if align then l.HorizontalAlignment = align end
	if dir then l.FillDirection = dir end
	if fill ~= nil then l.FillDirection = fill end
	l.Parent = parent
	return l
end
local function label(parent, name, text, size, color, align, font)
	local t = inst("TextLabel", parent, name)
	t.BackgroundTransparency = 1
	t.Font = font or Enum.Font.Gotham
	t.Text = text or ""
	t.TextSize = size or 14
	t.TextColor3 = color or C("text")
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextWrapped = true
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Size = UDim2.new(1, 0, 0, 0)
	t.RichText = true
	return t
end
local function button(parent, name, text, color, textColor)
	local b = inst("TextButton", parent, name)
	b.BackgroundColor3 = color or C("indigo")
	b.TextColor3 = textColor or C("text")
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 14
	b.Text = text or ""
	b.AutoButtonColor = false
	b.ClipsDescendants = true
	corner(b, 8)
	return b
end
local function iconButton(parent, name, text, color)
	local b = button(parent, name, text, color or C("panel2"))
	b.TextColor3 = C("text")
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	return b
end

-- ============================================================ Toast
local Toasts = { gui = nil, list = nil }
local function ensureToasts()
	if Toasts.gui then return end
	local g = inst("ScreenGui", CoreGui, "AgileStudioToasts")
	g.ResetOnSpawn = false
	local f = inst("Frame", g, "Wrap")
	f.Size = UDim2.new(0, 280, 1, 0)
	f.Position = UDim2.new(1, -300, 0, 12)
	f.BackgroundTransparency = 1
	listlayout(f, 8, Enum.HorizontalAlignment.Right, Enum.FillDirection.Vertical)
	Toasts.gui = g; Toasts.list = f
end
local function toast(msg, kind)
	ensureToasts()
	local c = (kind == "error" and C("danger")) or (kind == "ok" and C("mint")) or C("indigo")
	local t = inst("Frame", Toasts.list, "Toast")
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.BackgroundColor3 = C("panel")
	t.BackgroundTransparency = 0.05
	t.Size = UDim2.new(1, 0, 0, 0)
	corner(t, 10); stroke(t, c, 1.5)
	pad(t, 10)
	label(t, "Msg", msg, 13, C("text"))
	t.BackgroundTransparency = 0
	local born = tick()
	task.spawn(function()
		task.wait(3.2)
		local fade = TweenService:Create(t, TweenInfo.new(0.4), {BackgroundTransparency = 1})
		fade:Play(); task.wait(0.45); t:Destroy()
	end)
end

-- ============================================================ Mascot (vector, on-brand)
local function buildMascot(parent, size, opts)
	opts = opts or {}
	local m = inst("Frame", parent, "Mascot")
	m.Size = size or UDim2.new(0, 38, 0, 38)
	m.BackgroundColor3 = C("indigo")
	m.BackgroundTransparency = 0
	m.AnchorPoint = Vector2.new(0.5, 0.5)
	corner(m, 18); stroke(m, C("indigoLight"), 2)
	local belly = inst("Frame", m, "Belly")
	belly.Size = UDim2.new(0.7, 0, 0.7, 0)
	belly.Position = UDim2.new(0.15, 0, 0.25, 0)
	belly.BackgroundColor3 = C("indigoLight")
	belly.BackgroundTransparency = 0.4
	corner(belly, 14)
	local function eye(x)
		local e = inst("Frame", m, "Eye")
		e.Size = UDim2.new(0.16, 0, 0.16, 0)
		e.Position = UDim2.new(x, 0, 0.4, 0)
		e.AnchorPoint = Vector2.new(0.5, 0.5)
		e.BackgroundColor3 = C("text"); corner(e, 6)
		local p = inst("Frame", e, "Pupil")
		p.Size = UDim2.new(0.5, 0, 0.5, 0); p.AnchorPoint = Vector2.new(0.5,0.5)
		p.Position = UDim2.new(0.5,0,0.5,0); p.BackgroundColor3 = Color3.new(0.1,0.1,0.15); corner(p,4)
		return e
	end
	eye(0.38); eye(0.62)
	local ant = inst("Frame", m, "Antenna")
	ant.Size = UDim2.new(0.03, 0, 0.22, 0)
	ant.Position = UDim2.new(0.5, 0, -0.18, 0)
	ant.AnchorPoint = Vector2.new(0.5, 1)
	ant.BackgroundColor3 = C("indigoLight")
	local glow = inst("Frame", m, "Glow")
	glow.Size = UDim2.new(0.2, 0, 0.2, 0)
	glow.Position = UDim2.new(0.5, 0, -0.34, 0)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.BackgroundColor3 = C("amber"); corner(glow, 8)
	local gt = TweenService:Create(glow, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {BackgroundTransparency = 0.35})
	gt:Play()
	if opts.bob then
		local bob = TweenService:Create(m, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Rotation = 6})
		bob:Play()
	end
	return m
end

-- ============================================================ State
local State = {
	backend = SET.backend,
	conversations = {},
	activeId = nil,
	models = {},
	modelsLoaded = false,
	isSending = false,
	pollToken = nil,
	activeOp = nil,
	allowAlways = {},   -- tool_name -> true
}
local UI = {
	root = nil, chatScroll = nil, composer = nil, input = nil, sendBtn = nil,
	stopBtn = nil, modelLabel = nil, sidebar = nil, sidebarList = nil,
	topStatus = nil, drawer = nil, drawerTitle = nil, drawerBody = nil,
	dock = nil, mascotTop = nil, thinking = false,
}

-- Conversation shape:
-- { id, name, backendId=nil, messages={{role, text, ts, reasoning, tool}}, created }
local function newConversation(name)
	local c = { id = HttpService:GenerateGUID(false), name = name or "New Chat",
		backendId = nil, messages = {}, created = os.time() }
	table.insert(State.conversations, 1, c)
	return c
end
local function getActive()
	for _, c in ipairs(State.conversations) do
		if c.id == State.activeId then return c end
	end
	return nil
end
local function persistConversations()
	if not PLUGIN then return end
	pcall(function()
		local slim = {}
		for _, c in ipairs(State.conversations) do
			table.insert(slim, { id = c.id, name = c.name, backendId = c.backendId, created = c.created,
				messages = c.messages })
		end
		PLUGIN:SetSetting(CONV_KEY, HttpService:JSONEncode(slim))
	end)
end
local function loadConversations()
	if not PLUGIN then return end
	pcall(function()
		local raw = PLUGIN:GetSetting(CONV_KEY)
		if type(raw) == "string" and raw ~= "" then
			local data = HttpService:JSONDecode(raw)
			if type(data) == "table" then State.conversations = data end
		end
	end)
end

-- ============================================================ Networking
local function requestJSON(method, path, body, raw)
	local url = State.backend .. path
	-- Roblox HttpService can't set Authorization headers, so the plugin sends the
	-- API token as a query param. The backend accepts it there (and via header for
	-- non-Roblox clients).
	if SET.token and SET.token ~= "" then
		url = url .. (string.find(url, "?") and "&" or "?") .. "token=" .. HttpService:UrlEncode(SET.token)
	end
	local payload = nil
	if body ~= nil then payload = HttpService:JSONEncode(body) end
	local ok, res = pcall(function()
		if method == "GET" then
			return HttpService:GetAsync(url, false, {["Content-Type"] = "application/json"})
		else
			return HttpService:PostAsync(url, payload, Enum.HttpContentType.ApplicationJson, false)
		end
	end)
	if not ok then
		return nil, tostring(res)
	end
	if raw then return res, nil end
	local data = nil
	pcall(function() data = HttpService:JSONDecode(res) end)
	return data, nil
end

-- ============================================================ Tool execution (local)
local function findScript(path, create)
	local svc = game:GetService("ServerScriptService")
	local parts = {}
	for p in string.gmatch(path or "", "[^/]+") do table.insert(parts, p) end
	local parent = svc
	for i = 1, #parts - 1 do
		local f = parent:FindFirstChild(parts[i])
		if not f then f = inst("Folder", parent, parts[i]) end
		parent = f
	end
	local fname = parts[#parts] or "Script"
	local scr = parent:FindFirstChild(fname)
	if not scr and create then
		scr = inst(string.find(fname, "Module") and "ModuleScript" or "Script", parent, fname)
	end
	return scr
end

local function runTool(tr)
	local name = tr.tool_name or tr.name
	local args = tr.arguments or tr.args or {}
	if name == "create_animation" then
		local fname = args.name or "Animation"
		local fps = args.fps or 30
		local loop = args.loop ~= false
		local kfs = args.keyframes or {}
		local folder = game:GetService("ServerStorage"):FindFirstChild("AgileStudioAnimations")
		if not folder then folder = inst("Folder", game:GetService("ServerStorage"), "AgileStudioAnimations") end
		local ks = inst("KeyframeSequence", folder, fname)
		ks.FrameRate = fps; ks.Loop = loop
		for _, k in ipairs(kfs) do
			local kf = inst("Keyframe", ks, "K" .. tostring(k.time))
			kf.Time = k.time or 0
		end
		return "Created animation '" .. fname .. "' with " .. #kfs .. " keyframes at " .. fps .. "fps."
	elseif name == "write_script" then
		local scr = findScript(args.path, true)
		if not scr then return "Failed to create " .. tostring(args.path) end
		scr.Source = args.content or ""
		return "Wrote " .. args.path
	elseif name == "edit_script" then
		local scr = findScript(args.path, true)
		if not scr then return "Script not found: " .. tostring(args.path) end
		local cur = scr.Source or ""
		scr.Source = cur .. "\n-- AgileStudio edit:\n" .. (args.changes or "")
		return "Edited " .. args.path
	elseif name == "read_script" then
		local scr = findScript(args.path, false)
		if scr and (scr:IsA("Script") or scr:IsA("ModuleScript")) then return scr.Source end
		return "Script not found: " .. tostring(args.path)
	elseif name == "list_scripts" then
		local out = {}
		for _, v in ipairs(game:GetService("ServerScriptService"):GetDescendants()) do
			if v:IsA("Script") or v:IsA("ModuleScript") then table.insert(out, v:GetFullName()) end
		end
		return "Scripts (" .. #out .. "):\n" .. table.concat(out, "\n")
	elseif name == "execute_script" then
		local fn; local ok, err = pcall(function() fn = loadstring(args.code or "") end)
		if not ok or not fn then return "Compile error: " .. tostring(err) end
		local ok2, res = pcall(fn)
		if not ok2 then return "Runtime error: " .. tostring(res) end
		return "Executed. Result: " .. tostring(res)
	elseif name == "search_toolbox" then
		return "Toolbox search '" .. tostring(args.keyword) .. "' (" .. tostring(args.category) .. ") — open the Toolbox window to insert."
	elseif name == "get_documentation" then
		return "Docs for '" .. tostring(args.topic) .. "': see https://create.roblox.com/docs"
	else
		return "Unknown tool: " .. tostring(name)
	end
end

-- ============================================================ Chat rendering
local function codeBlock(parent, code)
	local f = inst("Frame", parent, "Code")
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundColor3 = C("code")
	f.BackgroundTransparency = 0.1
	f.Size = UDim2.new(1, -8, 0, 0)
	corner(f, 8); stroke(f, C("border"), 1)
	local tb = inst("TextLabel", f, "CodeText")
	tb.BackgroundTransparency = 1
	tb.Font = Enum.Font.Code
	tb.Text = code
	tb.TextSize = 12
	tb.TextColor3 = C("text")
	tb.TextXAlignment = Enum.TextXAlignment.Left
	tb.TextWrapped = true
	tb.AutomaticSize = Enum.AutomaticSize.Y
	tb.RichText = false
	tb.Size = UDim2.new(1, -12, 0, 0)
	pad(tb, 8)
	local copy = iconButton(f, "Copy", "Copy", C("surface"))
	copy.Size = UDim2.new(0, 56, 0, 22); copy.Position = UDim2.new(1, -62, 0, 6)
	copy.TextSize = 11
	copy.MouseButton1Click:Connect(function()
		pcall(function() setclipboard(code) end)
		copy.Text = "Copied"; task.wait(1); copy.Text = "Copy"
	end)
	return f
end

local function renderMessage(parent, msg)
	local isUser = msg.role == "user"
	local row = inst("Frame", parent, "Row")
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -8, 0, 0)
	local inner = inst("Frame", row, "Inner")
	inner.AutomaticSize = Enum.AutomaticSize.Y
	inner.BackgroundColor3 = isUser and C("userBubble") or C("assistBubble")
	inner.BackgroundTransparency = isUser and 0.1 or 0.25
	inner.Size = UDim2.new(isUser and 0.82 or 0.96, 0, 0, 0)
	inner.Position = UDim2.new(isUser and 0.18 or 0, 0, 0, 0)
	inner.AnchorPoint = Vector2.new(isUser and 0.18 or 0, 0)
	corner(inner, 12); stroke(inner, C("border"), 1)
	local pad_ = inst("UIPadding", inner); pad_.PaddingTop = UDim.new(0,8); pad_.PaddingBottom=UDim.new(0,8); pad_.PaddingLeft=UDim.new(0,10); pad_.PaddingRight=UDim.new(0,10)
	listlayout(inner, 6, nil, Enum.FillDirection.Vertical)

	-- header (role + time)
	local head = inst("Frame", inner, "Head")
	head.Size = UDim2.new(1, 0, 0, 18); head.BackgroundTransparency = 1
	local who = label(head, "Who", isUser and "You" or "AgileStudio", 12, isUser and C("text") or C("mint"))
	who.Font = Enum.Font.GothamBold; who.Size = UDim2.new(0, 120, 1, 0)
	local ts = label(head, "Ts", os.date("%H:%M", msg.ts or os.time()), 11, C("textDim"))
	ts.Size = UDim2.new(1, -130, 1, 0); ts.Position = UDim2.new(0, 120, 0, 0); ts.TextXAlignment = Enum.TextXAlignment.Right

	-- reasoning row (collapsible)
	if msg.reasoning and msg.reasoning ~= "" then
		local rbtn = button(inner, "Reason", "💡 Reasoning", C("surface"))
		rbtn.Size = UDim2.new(1, 0, 0, 26); rbtn.TextSize = 12; rbtn.TextColor3 = C("amber"); rbtn.Font = Enum.Font.GothamMedium
		local rbox = inst("Frame", inner, "RBox")
		rbox.AutomaticSize = Enum.AutomaticSize.Y; rbox.BackgroundTransparency = 1
		rbox.Size = UDim2.new(1, 0, 0, 0); rbox.Visible = false
		label(rbox, "RText", msg.reasoning, 12, C("textDim")).Font = Enum.Font.Gotham
		rbtn.MouseButton1Click:Connect(function()
			rbox.Visible = not rbox.Visible
			rbtn.Text = rbox.Visible and "💡 Reasoning ▲" or "💡 Reasoning"
		end)
	end

	-- text (split code blocks by ``` fences)
	local text = msg.text or ""
	local parts = {}
	local i = 1
	while true do
		local s, e = string.find(text, "```", i)
		if not s then table.insert(parts, {code = false, t = string.sub(text, i)}); break end
		if s > i then table.insert(parts, {code = false, t = string.sub(text, i, s - 1)}) end
		local s2, e2 = string.find(text, "```", e + 1)
		if not s2 then table.insert(parts, {code = true, t = string.sub(text, e + 1)}); break end
		table.insert(parts, {code = true, t = string.sub(text, e + 1, s2 - 1)})
		i = e2 + 1
	end
	for _, p in ipairs(parts) do
		if p.t and p.t ~= "" then
			if p.code then codeBlock(inner, p.t) else label(inner, "Txt", p.t, 14, C("text")) end
		end
	end

	-- tool result / permission card
	if msg.tool then
		buildToolCard(inner, msg.tool, msg)
	end
end

function buildToolCard(parent, tool, msg)
	local card = inst("Frame", parent, "ToolCard")
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = C("surface")
	card.BackgroundTransparency = 0.15
	card.Size = UDim2.new(1, 0, 0, 0)
	corner(card, 10); stroke(card, C("amber"), 1.5)
	pad(card, 10)
	listlayout(card, 6, nil, Enum.FillDirection.Vertical)
	label(card, "TName", "🔧 " .. (tool.tool_name or tool.name or "tool"), 13, C("amber")).Font = Enum.Font.GothamBold
	local argsStr = ""
	pcall(function() argsStr = HttpService:JSONEncode(tool.arguments or tool.args or {}) end)
	label(card, "TArgs", argsStr, 12, C("textDim")).Font = Enum.Font.Code
	if msg.toolStatus == "pending" then
		local row = inst("Frame", card, "Btns"); row.Size = UDim2.new(1,0,0,30); row.BackgroundTransparency=1; row.LayoutOrder=5
		listlayout(row, 8, Enum.HorizontalAlignment.Left, Enum.FillDirection.Horizontal)
		local allow = button(row, "Allow", "Allow", C("mint")); allow.Size = UDim2.new(0,80,0,28); allow.Font = Enum.Font.GothamMedium
		local deny = button(row, "Deny", "Deny", C("danger")); deny.Size = UDim2.new(0,80,0,28); deny.Font = Enum.Font.GothamMedium
		local always = button(row, "Always", "Always", C("indigoLight")); always.Size = UDim2.new(0,80,0,28); always.Font = Enum.Font.GothamMedium
		allow.MouseButton1Click:Connect(function() resolveTool(msg, true, false) end)
		deny.MouseButton1Click:Connect(function() resolveTool(msg, false, false) end)
		always.MouseButton1Click:Connect(function() resolveTool(msg, true, true) end)
	else
		label(card, "TRes", "↳ " .. (msg.toolResult or ""), 12, C("mint"))
	end
end

function resolveTool(msg, allowed, always)
	if always then State.allowAlways[msg.tool.tool_name or msg.tool.name] = true end
	msg.toolStatus = allowed and "allowed" or "denied"
	msg.toolResult = allowed and runTool(msg.tool) or "User denied."
	-- report back to backend
	local reqId = msg.tool.render_id or (msg.tool.tool_request_id)
	local op = State.activeOp
	if op then
		requestJSON("POST", "/operations/" .. op .. "/tool_results",
			{ tool_request_id = tostring(reqId), allowed = allowed, result = msg.toolResult })
	end
	renderChat()
end

function renderChat()
	if not UI.chatScroll then return end
	for _, c in ipairs(UI.chatScroll:GetChildren()) do
		if c:IsA("Frame") and c.Name == "Row" then c:Destroy() end
	end
	local conv = getActive()
	if not conv then
		label(UI.chatScroll, "Empty", "Start a conversation on the left →", 16, C("textDim")).TextAlignment = Enum.TextXAlignment.Center
		return
	end
	for _, m in ipairs(conv.messages) do
		renderMessage(UI.chatScroll, m)
	end
	task.defer(function()
		if UI.chatScroll then UI.chatScroll.CanvasPosition = Vector2.new(0, UI.chatScroll.AbsoluteCanvasSize.Y) end
	end)
end

-- ============================================================ Sidebar (conversations)
function renderSidebar()
	if not UI.sidebarList then return end
	for _, c in ipairs(UI.sidebarList:GetChildren()) do
		if c:IsA("Frame") and c.Name == "ConvRow" then c:Destroy() end
	end
	for _, c in ipairs(State.conversations) do
		local row = inst("Frame", UI.sidebarList, "ConvRow")
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.BackgroundColor3 = (c.id == State.activeId) and C("indigo") or C("panel2")
		row.BackgroundTransparency = (c.id == State.activeId) and 0.15 or 0.4
		row.Size = UDim2.new(1, -8, 0, 0)
		corner(row, 8)
		local click = inst("TextButton", row, "Hit"); click.BackgroundTransparency = 1; click.Size = UDim2.new(1,0,1,0); click.Text = ""
		local nm = label(row, "Name", c.name, 13, C("text")); nm.Font = Enum.Font.GothamMedium
		nm.Size = UDim2.new(1, -56, 0, 22); nm.Position = UDim2.new(0, 8, 0, 4)
		local del = iconButton(row, "Del", "×", C("danger")); del.Size = UDim2.new(0, 24, 0, 24)
		del.Position = UDim2.new(1, -30, 0, 4); del.TextSize = 16; del.Font = Enum.Font.GothamBold
		click.MouseButton1Click:Connect(function()
			State.activeId = c.id; persistConversations(); renderSidebar(); renderChat()
		end)
		del.MouseButton1Click:Connect(function()
			for i, cc in ipairs(State.conversations) do
				if cc.id == c.id then table.remove(State.conversations, i); break end
			end
			if State.activeId == c.id then State.activeId = (State.conversations[1] and State.conversations[1].id) or nil end
			persistConversations(); renderSidebar(); renderChat()
		end)
	end
end

-- ============================================================ Streaming
function startPolling(operationId, conv)
	State.activeOp = operationId
	State.pollToken = { cancelled = false }
	local token = State.pollToken
	local after = 0
	setThinking(true)
	task.spawn(function()
		local lastMsg = nil
		while not token.cancelled do
			local data = requestJSON("GET", "/operations/" .. operationId .. "/events?after_seq=" .. after .. "&limit=50")
			if data and data.events then
				for _, ev in ipairs(data.events) do
					after = math.max(after, ev.seq or 0)
					local p = ev.payload or {}
					if ev.type == "block_upsert" then
						local b = p.block
						if b then
							if b.role == "assistant" then
								lastMsg = ensureAssistant(conv)
								lastMsg.text = b.text or ""
								lastMsg.streaming = b.streaming
							elseif b.role == "permission" then
								local tm = b.tool_request or {}
								local existing = findToolMsg(conv, tm.tool_request_id or tm.id)
								if not existing then
									local m = { role = "assistant", ts = os.time(), text = "", tool = { tool_name = tm.tool_name, name = tm.name, arguments = tm.arguments or tm.args, render_id = tm.tool_request_id or tm.id }, toolStatus = "pending" }
									table.insert(conv.messages, m)
									-- auto-allow
									if State.allowAlways[tm.tool_name or tm.name] then
										resolveTool(m, true, false)
									end
								end
							end
							renderChat()
						end
					elseif ev.type == "block_patch" then
						local bid = p.block_id or p.render_id
						local pp = p.patch or {}
						if lastMsg and (bid == lastMsg.render_id or pp.text_append or pp.text) then
							if pp.text_append then lastMsg.text = (lastMsg.text or "") .. pp.text_append end
							if pp.text ~= nil then lastMsg.text = pp.text end
							if pp.streaming ~= nil then lastMsg.streaming = pp.streaming end
							renderChat()
						end
					elseif ev.type == "tool_result" then
						-- backend acknowledges; nothing extra
					end
				end
				if data.status == "completed" or data.status == "failed" then break end
			end
			task.wait(0.7)
		end
		setThinking(false)
		-- reconcile from timeline (single canonical set, no dup)
		local tl = requestJSON("GET", "/conversations/" .. (conv.backendId or "") .. "/timeline")
		if tl and tl.timeline and conv.backendId then
			-- keep only user/assistant/text; rebuild from server truth
			conv.messages = {}
			for _, b in ipairs(tl.timeline) do
				table.insert(conv.messages, { role = b.role, ts = os.time(), text = b.text or "" })
			end
		end
		persistConversations()
		State.isSending = false
		UI.composer.Visible = true
		UI.stopBtn.Visible = false
		renderChat(); renderSidebar()
	end)
end

function ensureAssistant(conv)
	for i = #conv.messages, 1, -1 do
		if conv.messages[i].role == "assistant" and conv.messages[i].streaming then return conv.messages[i] end
	end
	local m = { role = "assistant", ts = os.time(), text = "", streaming = true, render_id = "ast:" .. HttpService:GenerateGUID(false) }
	table.insert(conv.messages, m)
	return m
end
function findToolMsg(conv, rid)
	if not rid then return nil end
	for _, m in ipairs(conv.messages) do
		if m.tool and (m.tool.render_id == rid or (m.tool.tool_request_id == rid)) then return m end
	end
	return nil
end

function setThinking(on)
	State.thinking = on
	if UI.mascotTop then
		local t = TweenService:Create(UI.mascotTop, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Rotation = on and 12 or 0})
		if on then t:Play() else t:Cancel(); UI.mascotTop.Rotation = 0 end
	end
	if UI.topStatus then
		UI.topStatus.BackgroundColor3 = on and C("amber") or C("mint")
		UI.topStatus.Tooltip = on and "AgileStudio is thinking…" or "AgileStudio ready"
	end
end

-- ============================================================ Send
function sendMessage(text)
	if State.isSending or (text or "") == "" then return end
	local conv = getActive()
	if not conv then conv = newConversation(string.sub(text, 1, 40)); State.activeId = conv.id end
	table.insert(conv.messages, { role = "user", ts = os.time(), text = text })
	State.isSending = true
	UI.composer.Visible = false
	renderChat()

	local path, body
	if conv.backendId then
		path = "/conversations/" .. conv.backendId .. "/messages"
		body = { message = text, model = SET.model ~= "" and SET.model or "freellmapi/auto" }
	else
		path = "/conversations"
		body = { message = text, model = SET.model ~= "" and SET.model or "freellmapi/auto" }
	end
	local data, err = requestJSON("POST", path, body)
	if not data then
		toast("Backend error: " .. (err or "unknown"), "error")
		State.isSending = false; UI.composer.Visible = true
		return
	end
	if data.conversation and data.conversation.id then conv.backendId = data.conversation.id end
	if data.conversation and data.conversation.name and conv.name == "New Chat" then conv.name = data.conversation.name end
	persistConversations(); renderSidebar()
	if data.status == "running" then
		UI.stopBtn.Visible = true
		startPolling(data.operation_id, conv)
	else
		State.isSending = false; UI.composer.Visible = true
	end
end

function stopGeneration()
	if State.pollToken then State.pollToken.cancelled = true end
	State.isSending = false
	UI.composer.Visible = true; UI.stopBtn.Visible = false
	setThinking(false)
	toast("Stopped generation", "ok")
end

-- ============================================================ Drawer panels
function openDrawer(title)
	if not UI.drawer then return end
	label(UI.drawerTitle, "T", title, 16, C("text")).Font = Enum.Font.GothamBold
	UI.drawer.Visible = true
end
function closeDrawer()
	if UI.drawer then UI.drawer.Visible = false end
end

function buildSettings()
	local b = UI.drawerBody; clearDrawer()
	openDrawer("Settings")
	-- Backend URL
	label(b, "L1", "Backend URL", 13, C("textDim")).Font = Enum.Font.GothamMedium
	local tb = inst("TextBox", b, "Backend"); tb.Size = UDim2.new(1,0,0,32); tb.BackgroundColor3 = C("surface")
	tb.TextColor3 = C("text"); tb.Font = Enum.Font.Gotham; tb.TextSize = 13; tb.Text = SET.backend
	tb.ClearTextOnFocus = false; tb.PlaceholderText = "https://…"; corner(tb, 8); stroke(tb, C("border"),1)
	-- API Token
	label(b, "L1b", "API Token (from agilestudio dashboard)", 13, C("textDim")).Font = Enum.Font.GothamMedium
	local tk = inst("TextBox", b, "TokenBox"); tk.Size = UDim2.new(1,0,0,32); tk.BackgroundColor3 = C("surface")
	tk.TextColor3 = C("text"); tk.Font = Enum.Font.Code; tk.TextSize = 13; tk.Text = SET.token or ""
	tk.ClearTextOnFocus = false; tk.PlaceholderText = "agst_…"; corner(tk, 8); stroke(tk, C("border"),1)
	local save = button(b, "Save", "Save", C("mint")); save.Size = UDim2.new(0, 120, 0, 30); save.LayoutOrder = 2
	save.MouseButton1Click:Connect(function()
		SET.backend = tb.Text; State.backend = tb.Text
		SET.token = tk.Text; saveSettings(); loadModels(false)
		toast("Settings saved", "ok")
	end)
	divider(b)
	-- Theme
	label(b, "L2", "Theme", 13, C("textDim")).Font = Enum.Font.GothamMedium
	local themeRow = inst("Frame", b, "TR"); themeRow.Size = UDim2.new(1,0,0,32); themeRow.BackgroundTransparency=1
	listlayout(themeRow, 10, Enum.HorizontalAlignment.Left, Enum.FillDirection.Horizontal)
	local dark = button(themeRow, "Dark", "Dark", THEME == "dark" and C("indigo") or C("surface"))
	dark.Size = UDim2.new(0, 100, 1, 0)
	local light = button(themeRow, "Light", THEME == "light" and C("indigo") or C("surface"))
	light.Size = UDim2.new(0, 100, 1, 0)
	dark.MouseButton1Click:Connect(function() applyTheme("dark") end)
	light.MouseButton1Click:Connect(function() applyTheme("light") end)
	divider(b)
	-- Default model
	label(b, "L3", "Default model", 13, C("textDim")).Font = Enum.Font.GothamMedium
	local ml = label(b, "ModelCur", "Current: " .. (SET.model ~= "" and SET.model or "auto (first)"), 13, C("text"))
	local pick = button(b, "Pick", "Refresh models", C("indigo")); pick.Size = UDim2.new(0,160,0,30); pick.LayoutOrder=2
	pick.MouseButton1Click:Connect(function() loadModels(true); toast("Models refreshed", "ok") end)
	divider(b)
	label(b, "Info", "AgileStudio — your Roblox coding buddy.\nChats are saved locally on this machine.", 12, C("textDim"))
end

function divider(parent)
	local d = inst("Frame", parent, "Div"); d.Size = UDim2.new(1,0,0,1); d.BackgroundColor3 = C("border"); d.BackgroundTransparency = 0.5; d.LayoutOrder = 3
end
function clearDrawer()
	for _, c in ipairs(UI.drawerBody:GetChildren()) do
		if c:IsA("GuiObject") and c.Name ~= "UIListLayout" and c.Name ~= "UIPadding" then c:Destroy() end
	end
end

function buildUsage()
	local b = UI.drawerBody; clearDrawer(); openDrawer("Usage")
	label(b, "U1", "Plan: Free (AgileStudio)", 14, C("mint")).Font = Enum.Font.GothamBold
	label(b, "U2", "Models available: " .. tostring(#State.models), 13, C("text"))
	label(b, "U3", "Tool set: 8 (create_animation, write_script, edit_script, read_script, list_scripts, execute_script, search_toolbox, get_documentation)", 12, C("textDim")).TextWrapped = true
	local bar = inst("Frame", b, "Bar"); bar.Size = UDim2.new(1,0,0,10); bar.BackgroundColor3 = C("surface"); corner(bar, 5)
	local fill = inst("Frame", bar, "Fill"); fill.Size = UDim2.new(0.15,0,1,0); fill.BackgroundColor3 = C("mint"); corner(fill, 5)
	label(b, "U4", "Local session — quotas are managed by your backend key.", 12, C("textDim"))
end

function buildSounds()
	local b = UI.drawerBody; clearDrawer(); openDrawer("Sounds")
	label(b, "S1", "Sound effects", 14, C("text")).Font = Enum.Font.GothamBold
	local row = inst("Frame", b, "SR"); row.Size = UDim2.new(1,0,0,32); row.BackgroundTransparency=1
	listlayout(row, 10, Enum.HorizontalAlignment.Left, Enum.FillDirection.Horizontal)
	local on = button(row, "On", "Enabled", C("mint")); on.Size = UDim2.new(0, 110, 1, 0)
	local off = button(row, "Off", "Muted", C("surface")); off.Size = UDim2.new(0, 110, 1, 0)
	on.MouseButton1Click:Connect(function() SET.sounds = true; saveSettings(); toast("Sounds on", "ok") end)
	off.MouseButton1Click:Connect(function() SET.sounds = false; saveSettings(); toast("Sounds muted", "ok") end)
	label(b, "S2", "Plays a soft chime when AgileStudio finishes a reply.", 12, C("textDim"))
end

function buildMods()
	local b = UI.drawerBody; clearDrawer(); openDrawer("Mods")
	label(b, "M1", "Mods", 14, C("text")).Font = Enum.Font.GothamBold
	local mods = { "Auto-format scripts", "Safe save before AI edits", "Verbose tool logs", "Confirm destructive tools" }
	for _, m in ipairs(mods) do
		local row = inst("Frame", b, "Mod"); row.AutomaticSize = Enum.AutomaticSize.Y; row.BackgroundColor3 = C("panel2"); row.BackgroundTransparency = 0.3
		row.Size = UDim2.new(1,0,0,0); corner(row, 8); pad(row, 8)
		label(row, "Name", m, 13, C("text"))
		local tog = button(row, "T", "ON", C("mint")); tog.Size = UDim2.new(0, 56, 0, 26); tog.Position = UDim2.new(1, -62, 0.5, -13)
		local state = true
		tog.MouseButton1Click:Connect(function()
			state = not state; tog.Text = state and "ON" or "OFF"; tog.BackgroundColor3 = state and C("mint") or C("surface")
		end)
	end
end

function applyTheme(name)
	THEME = name; SET.theme = name; saveSettings()
	-- rebuild UI colors by re-rendering everything
	if UI.root then
		UI.root.BackgroundColor3 = C("bg")
		-- recolor main panels
	end
	renderChat(); renderSidebar(); buildTopRecolor()
	toast("Theme: " .. name, "ok")
end
function buildTopRecolor()
	-- light recolor of static panels without full rebuild
	if UI.dock then UI.dock.BackgroundColor3 = C("bg"); stroke(UI.dock, C("indigo"), 2) end
end

function loadModels(force)
	if not force and State.modelsLoaded then return end
	local data = requestJSON("GET", "/models/gateway")
	if data and data.models then
		State.models = data.models
		State.modelsLoaded = true
		if SET.model == "" and #State.models > 0 then
			SET.model = State.models[1].id
			saveSettings()
		end
		if UI.modelLabel then
			UI.modelLabel.Text = "Model: " .. (SET.model ~= "" and SET.model or "auto")
		end
	end
end

-- ============================================================ Shell
function buildShell()
	local gui
	local dockParent
	if PLUGIN then
		local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 380, 560, 300, 400)
		local ok, dw = pcall(function() return PLUGIN:CreateDockWidgetPluginGui("AgileStudio", info) end)
		if ok and dw then gui = dw; dockParent = dw; gui.Title = "AgileStudio" end
	end
	if not gui then
		gui = inst("ScreenGui", CoreGui, "AgileStudioGui"); gui.ResetOnSpawn = false; dockParent = gui
	end
	UI.gui = gui

	local dock = inst("Frame", dockParent, "Dock")
	dock.Size = UDim2.new(1, 0, 1, 0)
	dock.BackgroundColor3 = C("bg")
	dock.ClipsDescendants = true
	UI.dock = dock

	-- Top bar
	local top = inst("Frame", dock, "Top"); top.Size = UDim2.new(1, 0, 0, 54); top.BackgroundColor3 = C("panel"); top.BorderSizePixel = 0
	local tc = corner(top, 0); tc.CornerRadius = UDim.new(0, 0)
	UI.mascotTop = buildMascot(top, UDim2.new(0, 40, 0, 40)); UI.mascotTop.Position = UDim2.new(0, 12, 0.5, 0)
	local title = label(top, "Title", "AgileStudio", 20, C("text")); title.Position = UDim2.new(0, 60, 0, 0); title.Size = UDim2.new(0, 200, 1, 0); title.Font = Enum.Font.GothamBold
	-- status dot
	local dot = inst("Frame", top, "Status"); dot.Size = UDim2.new(0, 10, 0, 10); dot.Position = UDim2.new(0, 56, 0.5, 14); dot.BackgroundColor3 = C("mint"); corner(dot, 5)
	UI.topStatus = dot
	-- menu buttons (text-only, transparent — standing rule)
	local menu = inst("Frame", top, "Menu"); menu.Size = UDim2.new(0, 300, 1, 0); menu.Position = UDim2.new(1, -308, 0, 0); menu.BackgroundTransparency = 1
	listlayout(menu, 4, Enum.HorizontalAlignment.Right, Enum.FillDirection.Horizontal)
	local function mbtn(txt, cb)
		local b = iconButton(menu, txt, txt, Color3.new(1,1,1)); b.BackgroundTransparency = 1; b.TextColor3 = C("text")
		b.Font = Enum.Font.GothamMedium; b.TextSize = 13; b.Size = UDim2.new(0, 48, 0, 30)
		b.MouseButton1Click:Connect(cb); return b
	end
	mbtn("Chat", function() closeDrawer() end)
	mbtn("History", function() closeDrawer() end)
	mbtn("Settings", function() buildSettings() end)
	mbtn("Usage", function() buildUsage() end)
	mbtn("Sounds", function() buildSounds() end)
	mbtn("Mods", function() buildMods() end)

	-- Sidebar
	local side = inst("Frame", dock, "Side"); side.Size = UDim2.new(0, 140, 1, -54); side.Position = UDim2.new(0, 0, 0, 54); side.BackgroundColor3 = C("panel2"); side.BorderSizePixel = 0
	local sl = inst("UIListLayout", side); sl.Padding = UDim.new(0, 6); sl.SortOrder = Enum.SortOrder.LayoutOrder; sl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	label(side, "ST", "Chats", 13, C("textDim")).Font = Enum.Font.GothamBold
	local newBtn = button(side, "New", "+ New Chat", C("mint")); newBtn.Size = UDim2.new(1, -16, 0, 32); newBtn.LayoutOrder = 1
	newBtn.MouseButton1Click:Connect(function()
		local c = newConversation("New Chat"); State.activeId = c.id; persistConversations(); renderSidebar(); renderChat()
	end)
	local listWrap = inst("ScrollingFrame", side, "ListWrap"); listWrap.Size = UDim2.new(1, -8, 1, -80); listWrap.Position = UDim2.new(0, 4, 0, 76); listWrap.BackgroundTransparency = 1; listWrap.BorderSizePixel = 0; listWrap.ScrollBarThickness = 4; listWrap.ScrollBarImageColor3 = C("indigo")
	listlayout(listWrap, 6, Enum.HorizontalAlignment.Center, Enum.FillDirection.Vertical)
	UI.sidebarList = listWrap

	-- Main chat
	local main = inst("Frame", dock, "Main"); main.Size = UDim2.new(1, -140, 1, -54); main.Position = UDim2.new(0, 140, 0, 54); main.BackgroundColor3 = C("bg"); main.BorderSizePixel = 0
	UI.chatScroll = inst("ScrollingFrame", main, "Chat"); UI.chatScroll.Size = UDim2.new(1, -16, 1, -70); UI.chatScroll.Position = UDim2.new(0, 8, 0, 8); UI.chatScroll.BackgroundTransparency = 1; UI.chatScroll.BorderSizePixel = 0; UI.chatScroll.ScrollBarThickness = 6; UI.chatScroll.ScrollBarImageColor3 = C("indigo")
	listlayout(UI.chatScroll, 12, Enum.HorizontalAlignment.Center, Enum.FillDirection.Vertical)

	-- Composer
	local comp = inst("Frame", main, "Composer"); comp.Size = UDim2.new(1, -16, 0, 56); comp.Position = UDim2.new(0, 8, 1, -64); comp.BackgroundColor3 = C("surface"); corner(comp, 12); stroke(comp, C("border"), 1)
	UI.composer = comp
	UI.input = inst("TextBox", comp, "Input"); UI.input.Size = UDim2.new(1, -150, 1, -12); UI.input.Position = UDim2.new(0, 10, 0, 6); UI.input.BackgroundTransparency = 1; UI.input.TextColor3 = C("text"); UI.input.Font = Enum.Font.Gotham; UI.input.TextSize = 14; UI.input.TextWrapped = true; UI.input.ClearTextOnFocus = false; UI.input.MultiLine = true
	UI.input.PlaceholderText = "Ask AgileStudio to build something…"; UI.input.PlaceholderColor3 = C("textDim")
	UI.input.FocusLost:Connect(function(enter) if enter and UI.input.Text ~= "" then local t = UI.input.Text; UI.input.Text = ""; sendMessage(t) end end)

	UI.sendBtn = button(comp, "Send", "Send", C("indigo")); UI.sendBtn.Size = UDim2.new(0, 64, 0, 38); UI.sendBtn.Position = UDim2.new(1, -74, 0.5, -19); UI.sendBtn.MouseButton1Click:Connect(function() local t = UI.input.Text; if t ~= "" then UI.input.Text = ""; sendMessage(t) end end)
	UI.stopBtn = button(comp, "Stop", "Stop", C("danger")); UI.stopBtn.Size = UDim2.new(0, 64, 0, 38); UI.stopBtn.Position = UDim2.new(1, -74, 0.5, -19); UI.stopBtn.Visible = false; UI.stopBtn.MouseButton1Click:Connect(stopGeneration)

	-- model label
	UI.modelLabel = label(comp, "Model", "", 11, C("textDim")); UI.modelLabel.Position = UDim2.new(0, 10, 0, -2); UI.modelLabel.Size = UDim2.new(0, 200, 0, 14)

	-- Drawer
	local drawer = inst("Frame", dock, "Drawer"); drawer.Size = UDim2.new(0, 300, 1, -54); drawer.Position = UDim2.new(1, -300, 0, 54); drawer.BackgroundColor3 = C("panel"); drawer.BorderSizePixel = 0; drawer.Visible = false
	UI.drawer = drawer
	local dtop = inst("Frame", drawer, "DTop"); dtop.Size = UDim2.new(1, 0, 0, 40); dtop.BackgroundColor3 = C("panel2"); dtop.BorderSizePixel = 0
	UI.drawerTitle = inst("Frame", dtop, "DTWrap"); UI.drawerTitle.Size = UDim2.new(1, -40, 1, 0); UI.drawerTitle.BackgroundTransparency = 1
	listlayout(UI.drawerTitle, 8, nil, Enum.FillDirection.Vertical)
	local closeB = iconButton(dtop, "X", "×", C("danger")); closeB.Size = UDim2.new(0, 34, 0, 34); closeB.Position = UDim2.new(1, -38, 0.5, -17); closeB.Font = Enum.Font.GothamBold; closeB.TextSize = 18
	closeB.MouseButton1Click:Connect(closeDrawer)
	UI.drawerBody = inst("ScrollingFrame", drawer, "DBody"); UI.drawerBody.Size = UDim2.new(1, -12, 1, -48); UI.drawerBody.Position = UDim2.new(0, 6, 0, 44); UI.drawerBody.BackgroundTransparency = 1; UI.drawerBody.BorderSizePixel = 0; UI.drawerBody.ScrollBarThickness = 5; UI.drawerBody.ScrollBarImageColor3 = C("indigo")
	listlayout(UI.drawerBody, 10, nil, Enum.FillDirection.Vertical)
end

-- ============================================================ Boot
local function main()
	loadSettings()
	loadConversations()
	if #State.conversations == 0 then newConversation("New Chat") end
	State.activeId = State.conversations[1] and State.conversations[1].id
	buildShell()
	loadModels(false)
	renderSidebar()
	renderChat()
	task.spawn(function()
		while true do
			task.wait(2)
			if UI.modelLabel then UI.modelLabel.Text = "Model: " .. (SET.model ~= "" and SET.model or "auto") end
		end
	end)
	toast("AgileStudio ready — pick a model in Settings", "ok")
end

main()
