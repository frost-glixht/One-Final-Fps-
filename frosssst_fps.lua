--[[
	FROST FPS  -  FPS boost + look hub (Roblox / Luau, mobile + PC)

	BOOST   one mode at a time: OFF / BOOST / POTATO / ULTRA / MAX (big jobs run in tiny slices, no freezes)
	LOOK    brightness, shaders, sky changer, fog (client side)
	TOOLS   anti-AFK, mute, stretch
	USERS   hide players, nametag changer
	FONTS   change the game's fonts (built-in or your own file)
	SERVER  server browser + console (join any server, sorted by ping)
	MORE    theme, floating chip, smoothness, hub key

	Drag the header to move it. X folds it into the gear; tap the gear to open it again.
]]

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
local CONFIG = {
	ShowIntro = true,            -- intro on start (tap to skip)
	ParentToPlayerGui = false,   -- set true if you can't type in the boxes (keyboard won't open)
	SliceBudget = 0.0015,        -- seconds of heavy work per frame (lower = smoother, slower to apply)
}
-- optional overrides from a loader:  getgenv().FrostFpsConfig = { ShowIntro = false }
do
	local ok, env = pcall(function() return getgenv() end)
	local o = ok and type(env) == "table" and (env.FrostFpsConfig or env.FrostGlixhtConfig) or nil
	if type(o) == "table" then
		for k, v in pairs(o) do CONFIG[k] = v end
	end
end

------------------------------------------------------------
-- Services + helpers
------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Stats = game:GetService("Stats")
local player = Players.LocalPlayer

local conns = {}
local cleanups = {}
local function track(c)
	conns[#conns + 1] = c
	return c
end

-- if this (or an older version) is already running, shut it down first
do
	local ok, env = pcall(function() return getgenv() end)
	if ok and type(env) == "table" then
		local ran = false
		for _, key in ipairs({ "FrostFpsCleanup", "FrostGlixhtCleanup", "FrostUniversalCleanup", "FrostHubzCleanup", "FrostBoostCleanup" }) do
			if type(env[key]) == "function" then
				pcall(env[key])
				ran = true
			end
		end
		if ran then task.wait(0.6) end
	end
end

local C = {
	ice = Color3.fromRGB(0, 220, 255),       -- main accent
	glitch = Color3.fromRGB(255, 60, 160),   -- second accent
	blue = Color3.fromRGB(50, 110, 255),
	green = Color3.fromRGB(60, 225, 160),
	red = Color3.fromRGB(255, 85, 105),
	gray = Color3.fromRGB(52, 62, 90),
	dark = Color3.fromRGB(6, 9, 18),
	panel = Color3.fromRGB(10, 14, 26),
	row = Color3.fromRGB(18, 25, 44),
	text = Color3.new(1, 1, 1),
	dim = Color3.fromRGB(150, 170, 205),
}

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function corner(inst, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, inst)
end

local function getParent()
	if CONFIG.ParentToPlayerGui then
		return player:WaitForChild("PlayerGui")
	end
	local ok, ui = pcall(function()
		return (gethui and gethui()) or game:GetService("CoreGui")
	end)
	if ok and ui then return ui end
	return player:WaitForChild("PlayerGui")
end

do
	local parent = getParent()
	for _, n in ipairs({ "FrostFps", "FrostGlixht", "FrostUniversal", "FrostHubz", "FrostBoostFPS" }) do
		local old = parent:FindFirstChild(n)
		if old then old:Destroy() end
	end
end

local hubKey = { code = Enum.KeyCode.RightShift }
local playIntro   -- (defined near the bottom)

------------------------------------------------------------
-- Window
------------------------------------------------------------
local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(800, 600)
local HEADER_H = 40
local NAV_H = 46
local W = math.clamp(vp.X - 40, 360, 460)
local H = math.clamp(vp.Y - 40, 250, 320)
local themeHooks = {}

local gui = new("ScreenGui", {
	Name = "FrostFps",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, nil)
gui.Parent = getParent()

local main = new("Frame", {
	Name = "Main",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(W, H),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.03,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Active = true,
	Visible = false,
}, gui)
corner(main, 12)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(15, 22, 40), Color3.fromRGB(6, 9, 18)),
	Rotation = 90,
}, main)
local stroke = new("UIStroke", { Thickness = 1.5, Color = Color3.new(1, 1, 1), Transparency = 0.05 }, main)
local strokeGrad = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.ice),
		ColorSequenceKeypoint.new(0.5, C.glitch),
		ColorSequenceKeypoint.new(1, C.ice),
	}),
	Rotation = 35,
}, stroke)
themeHooks[#themeHooks + 1] = function()
	strokeGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.ice),
		ColorSequenceKeypoint.new(0.5, C.glitch),
		ColorSequenceKeypoint.new(1, C.ice),
	})
end
local openScale = new("UIScale", { Scale = 1 }, main)
-- fade layer for the open/close animation (fully transparent the rest of the time)
local curtain = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(4, 6, 12),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 50,
}, main)

-- header (inset, so it never pokes out of the rounded corners)
local header = new("Frame", {
	Name = "Header",
	Position = UDim2.fromOffset(6, 6),
	Size = UDim2.new(1, -12, 0, HEADER_H - 6),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
}, main)
corner(header, 8)

local ledDot = new("Frame", {
	Position = UDim2.fromOffset(12, 12),
	Size = UDim2.fromOffset(10, 10),
	BackgroundColor3 = C.gray,
	BorderSizePixel = 0,
}, header)
corner(ledDot, 5)

local titleLbl = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(30, 3),
	Size = UDim2.fromOffset(130, 18),
	Font = Enum.Font.GothamBlack,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "FROST FPS",
}, header)
local titleGrad = new("UIGradient", {
	Color = ColorSequence.new(Color3.new(1, 1, 1), C.ice),
	Rotation = 0,
}, titleLbl)
themeHooks[#themeHooks + 1] = function()
	titleGrad.Color = ColorSequence.new(Color3.new(1, 1, 1), C.ice)
end
new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(30, 20),
	Size = UDim2.fromOffset(130, 11),
	Font = Enum.Font.Code,
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.ice,
	TextTransparency = 0.2,
	Text = "OPTIMIZED BY FROST",
}, header)

local function chip(x, w)
	local f = new("TextLabel", {
		Position = UDim2.new(1, x, 0.5, -10),
		Size = UDim2.fromOffset(w, 20),
		BackgroundColor3 = C.dark,
		BackgroundTransparency = 0.25,
		Font = Enum.Font.Code,
		TextSize = 10,
		TextColor3 = C.text,
		Text = "--",
	}, header)
	corner(f, 6)
	return f
end
local pingLabel = chip(-118, 54)
local fpsLabel = chip(-166, 44)
fpsLabel.Text = "-- fps"
pingLabel.Text = "-- ms"

local function headerButton(text, x)
	local b = new("TextButton", {
		Position = UDim2.new(1, x, 0.5, -12),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = C.dark,
		BackgroundTransparency = 0.2,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = C.text,
	}, header)
	corner(b, 6)
	return b
end
local minBtn = headerButton("–", -56)
local closeBtn = headerButton("X", -28)

-- body (everything under the header; hidden while minimized)
local body = new("Frame", {
	Position = UDim2.fromOffset(0, HEADER_H),
	Size = UDim2.new(1, 0, 1, -HEADER_H),
	BackgroundTransparency = 1,
}, main)

local navBg = new("Frame", {
	Position = UDim2.new(0, 6, 1, -(NAV_H + 8)),
	Size = UDim2.new(1, -12, 0, NAV_H + 4),
	BackgroundColor3 = C.dark,
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
}, body)
corner(navBg, 12)
local tabBar = new("Frame", {
	Position = UDim2.new(0, 8, 1, -(NAV_H + 6)),
	Size = UDim2.new(1, -16, 0, NAV_H),
	BackgroundTransparency = 1,
}, body)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, tabBar)

local PAGE_Y = 6
local function makePage()
	local sf = new("ScrollingFrame", {
		Position = UDim2.fromOffset(8, PAGE_Y),
		Size = UDim2.new(1, -16, 1, -(PAGE_Y + NAV_H + 34)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.ice,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
	}, body)
	new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, sf)
	new("UIPadding", { PaddingRight = UDim.new(0, 6) }, sf)
	return sf
end
local pgBoost, pgLook, pgTools, pgPlayers, pgFonts, pgServer, pgAura, pgMore = makePage(), makePage(), makePage(), makePage(), makePage(), makePage(), makePage(), makePage()
local pages = { pgBoost, pgLook, pgTools, pgPlayers, pgFonts, pgServer, pgAura, pgMore }
local TAB_NAMES = { "BOOST", "LOOK", "TOOLS", "USERS", "FONTS", "SERVER", "AURA", "MORE" }

local statusLabel = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 1, -(NAV_H + 32)),
	Size = UDim2.new(1, -24, 0, 18),
	Font = Enum.Font.Code,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.dim,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Text = "> ready",
}, body)
local function setStatus(t) statusLabel.Text = "> " .. t end

local tabBtns, tabNames, current = {}, {}, 0
local TAB_ICONS = { "⚡", "🎨", "🔧", "👥", "🔤", "🌐", "✨", "⚙️" }
local tabW = math.floor((W - 16 - 2 * (#TAB_NAMES - 1)) / #TAB_NAMES)
W = math.clamp(vp.X - 40, 400, 500)   -- slightly wider so 8 tabs fit
local function indPos(i)
	return UDim2.new(0, 8 + (i - 1) * (tabW + 2) + tabW * 0.25, 1, -(NAV_H + 8))
end
local tabInd = new("Frame", {
	Position = indPos(1),
	Size = UDim2.fromOffset(tabW * 0.5, 3),
	BackgroundColor3 = C.ice,
	BorderSizePixel = 0,
	ZIndex = 3,
}, body)
corner(tabInd, 2)
local function selectTab(i)
	if i == current then return end
	current = i
	for k, pg in ipairs(pages) do
		local on = (k == i)
		pg.Visible = on
		tabNames[k].TextColor3 = on and C.ice or C.dim
		tabBtns[k].BackgroundTransparency = on and 0.85 or 1
	end
	TweenService:Create(tabInd, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = indPos(i),
	}):Play()
	local pg = pages[i]
	pg.Position = UDim2.fromOffset(18, PAGE_Y)
	TweenService:Create(pg, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(8, PAGE_Y),
	}):Play()
end
for i, name in ipairs(TAB_NAMES) do
	local b = new("TextButton", {
		LayoutOrder = i,
		Size = UDim2.fromOffset(tabW, NAV_H),
		BackgroundColor3 = C.ice,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	}, tabBar)
	corner(b, 10)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.new(1, 0, 0, 22),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		Text = TAB_ICONS[i],
		TextColor3 = C.text,
	}, b)
	tabNames[i] = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -16),
		Size = UDim2.new(1, 0, 0, 12),
		Font = Enum.Font.GothamBold,
		TextSize = 9,
		Text = name,
		TextColor3 = C.dim,
	}, b)
	tabBtns[i] = b
	b.MouseButton1Click:Connect(function() selectTab(i) end)
end

------------------------------------------------------------
-- Toast: small popup, ~2 seconds
------------------------------------------------------------
local toastCur = nil
local function showToast(text)
	if toastCur then
		pcall(function() toastCur:Destroy() end)
		toastCur = nil
	end
	text = tostring(text)
	local up = text:upper()
	local accent = C.ice
	if up:find("OFF", 1, true) then
		accent = C.red
	elseif up:find(": ON", 1, true) then
		accent = C.green
	end
	local inset = game:GetService("GuiService"):GetGuiInset()
	local card = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, inset.Y + 10),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 120,
	}, gui)
	corner(card, 9)
	local st = new("UIStroke", { Thickness = 1, Color = accent, Transparency = 1 }, card)
	local lbl = new("TextLabel", {
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = C.text,
		TextTransparency = 1,
		Text = text,
		ZIndex = 121,
	}, card)
	new("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 14) }, lbl)
	local bar = new("Frame", {
		Size = UDim2.new(0, 3, 0.6, 0),
		Position = UDim2.new(0, 7, 0.2, 0),
		BackgroundColor3 = accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 121,
	}, card)
	corner(bar, 2)
	toastCur = card
	local fi = TweenInfo.new(0.15)
	TweenService:Create(card, fi, { BackgroundTransparency = 0.08 }):Play()
	TweenService:Create(lbl, fi, { TextTransparency = 0 }):Play()
	TweenService:Create(st, fi, { Transparency = 0.45 }):Play()
	TweenService:Create(bar, fi, { BackgroundTransparency = 0 }):Play()
	task.delay(1.8, function()
		if toastCur ~= card then return end
		local fo = TweenInfo.new(0.2)
		TweenService:Create(card, fo, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(lbl, fo, { TextTransparency = 1 }):Play()
		TweenService:Create(st, fo, { Transparency = 1 }):Play()
		TweenService:Create(bar, fo, { BackgroundTransparency = 1 }):Play()
		task.wait(0.22)
		if toastCur == card then toastCur = nil end
		card:Destroy()
	end)
end

------------------------------------------------------------
-- Widgets
------------------------------------------------------------
local function makeButton(parent, text, order, color)
	local b = new("TextButton", {
		LayoutOrder = order,
		Size = UDim2.new(1, -4, 0, 38),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.12,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = C.text,
	}, parent)
	corner(b, 8)
	b.MouseButton1Down:Connect(function()
		b.BackgroundTransparency = 0
		TweenService:Create(b, TweenInfo.new(0.25), { BackgroundTransparency = 0.12 }):Play()
	end)
	return b
end

local function makeToggle(parent, text, order, initial, callback)
	local btn = new("TextButton", {
		LayoutOrder = order,
		Size = UDim2.new(1, -4, 0, 38),
		BackgroundColor3 = C.row,
		BackgroundTransparency = 0.2,
		Text = "",
		AutoButtonColor = false,
	}, parent)
	corner(btn, 8)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -64, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = C.text,
		Text = text,
	}, btn)
	local pill = new("Frame", {
		Size = UDim2.fromOffset(36, 18),
		Position = UDim2.new(1, -46, 0.5, -9),
		BorderSizePixel = 0,
	}, btn)
	corner(pill, 9)
	local knob = new("Frame", {
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = C.text,
		BorderSizePixel = 0,
	}, pill)
	corner(knob, 7)

	local state = initial and true or false
	local function paint(animate)
		local pc = state and C.ice or C.gray
		local kp = state and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2)
		if animate then
			local ti = TweenInfo.new(0.12)
			TweenService:Create(pill, ti, { BackgroundColor3 = pc }):Play()
			TweenService:Create(knob, ti, { Position = kp }):Play()
		else
			pill.BackgroundColor3 = pc
			knob.Position = kp
		end
	end
	paint(false)

	btn.MouseButton1Down:Connect(function()
		btn.BackgroundTransparency = 0.02
		TweenService:Create(btn, TweenInfo.new(0.25), { BackgroundTransparency = 0.2 }):Play()
	end)
	btn.MouseButton1Click:Connect(function()
		state = not state
		paint(true)
		local ok, err = pcall(callback, state)
		if not ok then warn("[FrostFps] " .. text .. ": " .. tostring(err)) end
	end)

	return {
		set = function(on)
			on = on and true or false
			if on == state then return end
			state = on
			paint(true)
		end,
		destroy = function() btn:Destroy() end,
	}
end

local function makeBox(parent, order, placeholder, text, height, multi)
	local box = new("TextBox", {
		LayoutOrder = order,
		Size = UDim2.new(1, -4, 0, height or 32),
		BackgroundColor3 = C.dark,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Font = Enum.Font.Code,
		TextSize = 12,
		TextColor3 = C.text,
		PlaceholderText = placeholder,
		PlaceholderColor3 = Color3.fromRGB(110, 130, 165),
		Text = text or "",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		MultiLine = multi and true or false,
		TextWrapped = multi and true or false,
	}, parent)
	corner(box, 8)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, multi and 6 or 0),
	}, box)
	return box
end

-- touch friendly slider: drag the bar, tap the bar, or use the - / + buttons
local function makeSlider(parent, order, label, minV, maxV, value, step, fmt, onChange)
	local row = new("Frame", {
		LayoutOrder = order, Size = UDim2.new(1, -4, 0, 52),
		BackgroundColor3 = C.row, BackgroundTransparency = 0.2, BorderSizePixel = 0,
	}, parent)
	corner(row, 8)
	new("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -84, 0, 16),
		Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.text, Text = label,
	}, row)
	local valLbl = new("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.new(1, -72, 0, 4), Size = UDim2.fromOffset(60, 16),
		Font = Enum.Font.Code, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.ice, Text = "",
	}, row)
	local function stepBtn(text, pos)
		local b = new("TextButton", {
			Position = pos, Size = UDim2.fromOffset(24, 20),
			BackgroundColor3 = C.dark, BackgroundTransparency = 0.2,
			Text = text, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.text,
		}, row)
		corner(b, 6)
		return b
	end
	local minus = stepBtn("-", UDim2.fromOffset(10, 26))
	local plus = stepBtn("+", UDim2.new(1, -34, 0, 26))
	local bar = new("TextButton", {
		Position = UDim2.fromOffset(40, 33), Size = UDim2.new(1, -80, 0, 8),
		BackgroundColor3 = C.dark, BorderSizePixel = 0, Text = "", AutoButtonColor = false,
	}, row)
	corner(bar, 4)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.ice, BorderSizePixel = 0 }, bar)
	corner(fill, 4)
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14), BackgroundColor3 = C.text, BorderSizePixel = 0,
	}, bar)
	corner(knob, 7)

	local cur = value
	local function show()
		local a = (cur - minV) / (maxV - minV)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		valLbl.Text = fmt and fmt(cur) or tostring(cur)
	end
	local function setV(v, fire)
		v = math.clamp(v, minV, maxV)
		v = math.floor(v / step + 0.5) * step
		v = math.floor(v * 1000 + 0.5) / 1000
		cur = math.clamp(v, minV, maxV)
		show()
		if fire and onChange then pcall(onChange, cur) end
	end
	setV(value, false)

	minus.MouseButton1Click:Connect(function() setV(cur - step, true) end)
	plus.MouseButton1Click:Connect(function() setV(cur + step, true) end)

	local dragging = false
	local function fromX(x)
		local w = math.max(bar.AbsoluteSize.X, 1)
		local a = math.clamp((x - bar.AbsolutePosition.X) / w, 0, 1)
		setV(minV + (maxV - minV) * a, true)
	end
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(input.Position.X)
		end
	end)
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			fromX(input.Position.X)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	return {
		set = function(v, fire) setV(v, fire) end,
		get = function() return cur end,
	}
end

local function sectionLabel(parent, order, text)
	return new("TextLabel", {
		LayoutOrder = order,
		Size = UDim2.new(1, -4, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.glitch,
		Text = "// " .. text,
	}, parent)
end

------------------------------------------------------------
-- Dragging (kept on screen) + gear button + open / close / minimize
------------------------------------------------------------
local minimized = false
local draggables = {}

local function clampCenter(d)
	local s = gui.AbsoluteSize
	if s.X < 50 or s.Y < 50 then return end
	local w, h = d.getSize()
	local p = d.target.Position
	local x = p.X.Scale * s.X + p.X.Offset
	local y = p.Y.Scale * s.Y + p.Y.Offset
	x = math.clamp(x, w / 2, math.max(s.X - w / 2, w / 2))
	y = math.clamp(y, h / 2, math.max(s.Y - h / 2, h / 2))
	d.target.Position = UDim2.fromOffset(x, y)
end

local function reclampAll()
	for _, d in ipairs(draggables) do pcall(clampCenter, d) end
end

-- drag `target` (center anchored) by grabbing `handle`; d.moved tells taps from drags
local function makeDraggable(handle, target, getSize)
	local d = { target = target, getSize = getSize, moved = false }
	draggables[#draggables + 1] = d
	local active, startInput, dragStart, startPos = false, nil, nil, nil
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			active = true
			d.moved = false
			startInput = input
			dragStart = input.Position
			local s = gui.AbsoluteSize
			local p = target.Position
			startPos = Vector2.new(p.X.Scale * s.X + p.X.Offset, p.Y.Scale * s.Y + p.Y.Offset)
		end
	end)
	track(UserInputService.InputChanged:Connect(function(input)
		if not active then return end
		if input == startInput or input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			if delta.Magnitude > 6 then d.moved = true end
			if d.moved then
				target.Position = UDim2.fromOffset(startPos.X + delta.X, startPos.Y + delta.Y)
				clampCenter(d)
			end
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if not active then return end
		if input == startInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
			active = false
		end
	end))
	return d
end

local function mainSize()
	return W, minimized and (HEADER_H + 6) or H
end
makeDraggable(header, main, mainSize)
pcall(function() track(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(reclampAll)) end)

-- the gear: shows while the hub is closed
local gear = new("TextButton", {
	Name = "Gear",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0, 36, 0.5, 0),
	Size = UDim2.fromOffset(46, 46),
	BackgroundColor3 = C.dark,
	Text = "⚙️",
	TextSize = 24,
	Font = Enum.Font.GothamBold,
	TextColor3 = C.text,
	AutoButtonColor = false,
	Visible = false,
}, gui)
corner(gear, 23)
new("UIStroke", { Thickness = 2, Color = C.ice }, gear)
local gearScale = new("UIScale", { Scale = 1 }, gear)
local gearDrag = makeDraggable(gear, gear, function() return 46, 46 end)

local animGen = 0
local hubOpen = false

local function openHub()
	animGen += 1
	hubOpen = true
	gear.Visible = false
	main.Visible = true
	pcall(reclampAll)
	openScale.Scale = 0.86
	curtain.BackgroundTransparency = 0
	TweenService:Create(openScale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(curtain, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	stroke.Thickness = 3.5
	TweenService:Create(stroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Thickness = 1.5 }):Play()
end

local function closeHub()
	animGen += 1
	local gen = animGen
	hubOpen = false
	TweenService:Create(openScale, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 }):Play()
	local tw = TweenService:Create(curtain, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { BackgroundTransparency = 0 })
	tw.Completed:Connect(function()
		if gen ~= animGen then return end
		main.Visible = false
		openScale.Scale = 1
		curtain.BackgroundTransparency = 1
		gearScale.Scale = 0
		gear.Visible = true
		pcall(reclampAll)
		TweenService:Create(gearScale, TweenInfo.new(0.36, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	tw:Play()
end

local function setMinimized(v)
	minimized = v
	minBtn.Text = v and "+" or "–"
	if v then
		body.Visible = false
		TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(W, HEADER_H + 6) }):Play()
	else
		TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(W, H) }):Play()
		task.delay(0.12, function()
			if not minimized then body.Visible = true end
		end)
	end
	task.delay(0.25, reclampAll)
end
minBtn.MouseButton1Click:Connect(function() setMinimized(not minimized) end)
closeBtn.MouseButton1Click:Connect(closeHub)
gear.Activated:Connect(function()
	if not gearDrag.moved then openHub() end
end)

local introActive = false
track(UserInputService.InputBegan:Connect(function(input, processed)
	if processed or introActive then return end
	if input.KeyCode == hubKey.code then
		if hubOpen then closeHub() else openHub() end
	end
end))

------------------------------------------------------------
-- Performance helpers: big jobs run a few milliseconds per frame
------------------------------------------------------------
local SLICE_BUDGET = tonumber(CONFIG.SliceBudget) or 0.0015

-- run fn(item) over `list` without ever hogging a frame; stops early if alive() turns false
local function sliceEach(list, fn, alive)
	local i, n = 1, #list
	while i <= n do
		if alive and not alive() then return false end
		local t0 = os.clock()
		repeat
			local stop = math.min(i + 11, n)
			for k = i, stop do pcall(fn, list[k]) end
			i = stop + 1
		until i > n or os.clock() - t0 > SLICE_BUDGET
		RunService.Heartbeat:Wait()
	end
	return true
end

-- only one heavy workspace scan (boost / dark textures) runs at a time, so
-- toggling several things at once can no longer stack up and cause a freeze
local heavyLock = { busy = false, queue = {} }
local function runHeavy(fn, onDone)
	if heavyLock.busy then
		table.insert(heavyLock.queue, { fn = fn, onDone = onDone })
		return
	end
	heavyLock.busy = true
	task.spawn(function()
		local ok, err = pcall(fn)
		if not ok then warn("[FrostBoost] " .. tostring(err)) end
		if onDone then pcall(onDone) end
		heavyLock.busy = false
		local nxt = table.remove(heavyLock.queue, 1)
		if nxt then runHeavy(nxt.fn, nxt.onDone) end
	end)
end

local function getProp(inst, prop) return inst[prop] end
local function setProp(inst, prop, value) inst[prop] = value end

-- records look like { instance, prop1, value1, prop2, value2, ... }
local function restoreRecords(records, onDone)
	runHeavy(function()
		sliceEach(records, function(rec)
			local inst = rec[1]
			for k = 2, #rec, 2 do pcall(setProp, inst, rec[k], rec[k + 1]) end
		end)
	end, onDone)
end


local lookActive = function() return false end   -- (the LOOK tab replaces this)

------------------------------------------------------------
-- BOOST ENGINE: one mode at a time. OFF / BOOST / POTATO / ULTRA
-- (switching always restores the old mode first, so nothing ever stacks or sticks)
------------------------------------------------------------
local function weakTable() return setmetatable({}, { __mode = "k" }) end
local boost = { mode = 0, busy = false, saved = {}, seen = weakTable(), conn = nil, gen = 0, tech = nil, freeze = {} }
local MODE_NAMES = { [0] = "OFF", "BOOST", "POTATO", "ULTRA", "MAX" }
local MODE_DESC = {
	[0] = "Everything is back to normal.",
	"Smooth materials, no decals, particles, effects, shadows or fog.",
	"BOOST + lights off, flat untextured meshes, no haze or grass, lowest quality.",
	"POTATO + no PBR textures and other players' animations frozen. Max FPS.",
	"ULTRA + world GUIs and sounds off. Players are still visible.
(Other players' animations already frozen by ULTRA.)",
}
local SMOOTH = Enum.Material.SmoothPlastic
local PERF = Enum.RenderFidelity.Performance
local FX_OFF = {
	ParticleEmitter = true, Trail = true, Beam = true, Smoke = true, Fire = true, Sparkles = true,
	BloomEffect = true, BlurEffect = true, ColorCorrectionEffect = true,
	DepthOfFieldEffect = true, SunRaysEffect = true,
}
local LIGHT_OFF = { PointLight = true, SpotLight = true, SurfaceLight = true, Highlight = true }

-- is this part inside a character? (cached so big models aren't re-scanned for every part)
local charCache = weakTable()
local function isCharModel(m)
	if Players:GetPlayerFromCharacter(m) then
		charCache[m] = true
		return true
	end
	local c = charCache[m]
	if c == true then return true end
	local now = os.clock()
	if c and now < c then return false end
	local is = m:FindFirstChildOfClass("Humanoid") ~= nil
	charCache[m] = is or (now + 5)
	return is
end
local function isCharPart(inst)
	local p, depth = inst.Parent, 0
	while p and p ~= workspace and depth < 8 do
		if p.ClassName == "Model" and isCharModel(p) then return true end
		p = p.Parent
		depth += 1
	end
	return false
end

-- set a property and remember the old value (only when it really changes)
local function put(rec, inst, prop, target)
	local okR, cur = pcall(getProp, inst, prop)
	if okR and cur ~= target and pcall(setProp, inst, prop, target) then
		rec[#rec + 1] = prop
		rec[#rec + 1] = cur
	end
end

local function optimizeItem(inst)
	local seen = boost.seen
	if seen[inst] then return end
	local lvl = boost.mode
	local cls = inst.ClassName
	local rec = { inst }
	if lvl >= 4 then
		-- MAX: world GUIs + sounds off, other players hidden
		local handled = false
		if cls == "BillboardGui" or cls == "SurfaceGui" then
			put(rec, inst, "Enabled", false)
			handled = true
		elseif cls == "Sound" then
			put(rec, inst, "Volume", 0)
			handled = true
		end
		if handled then
			seen[inst] = true
			if #rec > 1 then
				local s = boost.saved
				s[#s + 1] = rec
			end
			return
		end
	end
	if FX_OFF[cls] then
		seen[inst] = true
		put(rec, inst, "Enabled", false)
	elseif cls == "Decal" or cls == "Texture" then
		seen[inst] = true
		put(rec, inst, "Transparency", 1)
	elseif LIGHT_OFF[cls] then
		if lvl < 2 then return end
		seen[inst] = true
		put(rec, inst, "Enabled", false)
	elseif cls == "SurfaceAppearance" then
		if lvl < 3 then return end
		seen[inst] = true
		local parent = inst.Parent
		if parent then put(rec, inst, "Parent", nil) end
	elseif cls == "MeshPart" then
		seen[inst] = true
		put(rec, inst, "Material", SMOOTH)
		put(rec, inst, "Reflectance", 0)
		if lvl >= 2 and not isCharPart(inst) then
			put(rec, inst, "RenderFidelity", PERF)
			put(rec, inst, "TextureID", "")
		end
	elseif cls == "UnionOperation" then
		seen[inst] = true
		put(rec, inst, "Material", SMOOTH)
		put(rec, inst, "Reflectance", 0)
		if lvl >= 2 then put(rec, inst, "RenderFidelity", PERF) end
	elseif cls ~= "Terrain" and inst:IsA("BasePart") then
		seen[inst] = true
		put(rec, inst, "Material", SMOOTH)
		put(rec, inst, "Reflectance", 0)
	end
	if #rec > 1 then
		local s = boost.saved
		s[#s + 1] = rec
	end
end

local function putGlobal(inst, prop, target)
	local rec = { inst }
	put(rec, inst, prop, target)
	if #rec > 1 then
		local s = boost.saved
		s[#s + 1] = rec
	end
end

local function applyGlobals(m)
	putGlobal(Lighting, "GlobalShadows", false)
	putGlobal(Lighting, "FogEnd", 9e9)
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		for _, p in ipairs({ "WaterWaveSize", "WaterWaveSpeed", "WaterReflectance", "WaterTransparency" }) do
			putGlobal(terrain, p, 0)
		end
	end
	pcall(function() putGlobal(settings().Rendering, "QualityLevel", Enum.QualityLevel.Level01) end)
	if m >= 2 then
		putGlobal(Lighting, "EnvironmentDiffuseScale", 0)
		putGlobal(Lighting, "EnvironmentSpecularScale", 0)
		putGlobal(Lighting, "ShadowSoftness", 0)
		for _, child in ipairs(Lighting:GetChildren()) do
			if child.ClassName == "Atmosphere" then
				putGlobal(child, "Density", 0)
				putGlobal(child, "Haze", 0)
				putGlobal(child, "Glare", 0)
			end
		end
		if terrain then putGlobal(terrain, "Decoration", false) end
		pcall(function() putGlobal(settings().Rendering, "MeshPartDetailLevel", Enum.MeshPartDetailLevel.Level04) end)
		pcall(function()
			if gethiddenproperty and sethiddenproperty then
				local cur = gethiddenproperty(Lighting, "Technology")
				if cur ~= Enum.Technology.Compatibility then
					boost.tech = cur
					sethiddenproperty(Lighting, "Technology", Enum.Technology.Compatibility)
				end
			end
		end)
	end
end

-- ULTRA: freeze other players' animations (client side)
local function setFreeze(on)
	for _, c in ipairs(boost.freeze) do pcall(function() c:Disconnect() end) end
	boost.freeze = {}
	if not on then return end
	local function freezeChar(char)
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
		if not hum or boost.mode < 3 then return end
		local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5)
		if not animator or boost.mode < 3 then return end
		for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
			pcall(function() tr:Stop(0) end)
		end
		boost.freeze[#boost.freeze + 1] = animator.AnimationPlayed:Connect(function(tr)
			pcall(function() tr:Stop(0) end)
		end)
	end
	local function freezePlayer(p)
		if p == player then return end
		if p.Character then task.spawn(freezeChar, p.Character) end
		boost.freeze[#boost.freeze + 1] = p.CharacterAdded:Connect(function(c)
			task.spawn(freezeChar, c)
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do freezePlayer(p) end
	boost.freeze[#boost.freeze + 1] = Players.PlayerAdded:Connect(freezePlayer)
end

local function stopCurrent(onDone)
	boost.mode = 0
	boost.gen += 1
	if boost.conn then
		boost.conn:Disconnect()
		boost.conn = nil
	end
	setFreeze(false)
	local saved = boost.saved
	boost.saved = {}
	boost.seen = weakTable()
	boost.busy = true
	restoreRecords(saved, function()
		pcall(function()
			if boost.tech ~= nil and sethiddenproperty then
				sethiddenproperty(Lighting, "Technology", boost.tech)
			end
		end)
		boost.tech = nil
		boost.busy = false
		if onDone then onDone() end
	end)
end

local function startMode(m)
	boost.mode = m
	boost.saved = {}
	boost.seen = weakTable()
	boost.gen += 1
	boost.busy = true
	local gen = boost.gen
	applyGlobals(m)
	if m >= 3 then setFreeze(true) end

	-- things created while a mode is active are queued and handled in small slices
	local pending, pHead, pTail = {}, 1, 0
	boost.conn = workspace.DescendantAdded:Connect(function(inst)
		pTail += 1
		pending[pTail] = inst
	end)
	local function alive() return boost.mode == m and boost.gen == gen end

	local list = workspace:GetDescendants()
	local total, done = math.max(#list, 1), 0
	setStatus("Applying " .. MODE_NAMES[m] .. "...")
	runHeavy(function()
		for _, inst in ipairs(Lighting:GetChildren()) do pcall(optimizeItem, inst) end
		sliceEach(list, function(inst)
			optimizeItem(inst)
			done += 1
			if done % 600 == 0 then
				setStatus(("Applying %s %d%%"):format(MODE_NAMES[m], math.floor(done / total * 100)))
			end
		end, alive)
	end, function()
		boost.busy = false
		if not alive() then return end
		setStatus(("%s active (%d changes)"):format(MODE_NAMES[m], #boost.saved))
		showToast(MODE_NAMES[m] .. ": ON")
		task.spawn(function()
			while alive() do
				if pHead <= pTail then
					local t0 = os.clock()
					while pHead <= pTail and os.clock() - t0 < SLICE_BUDGET do
						local item = pending[pHead]
						pending[pHead] = nil
						pHead += 1
						if item.Parent then pcall(optimizeItem, item) end
					end
					if pHead > pTail then pending, pHead, pTail = {}, 1, 0 end
					RunService.Heartbeat:Wait()
				else
					task.wait(0.4)
				end
			end
		end)
	end)
end

-- returns false if it was busy (nothing changed)
local function setMode(m)
	if boost.busy then
		setStatus("Still working, one moment...")
		return false
	end
	if m ~= 0 and lookActive() then
		setStatus("Reset the LOOK effects first (LOOK tab > RESET LOOK).")
		showToast("Reset LOOK first")
		return false
	end
	if m == boost.mode then return true end
	if boost.mode ~= 0 then
		stopCurrent(function()
			if m ~= 0 then
				startMode(m)
			else
				setStatus("Boost off: original settings restored.")
				showToast("Boost: OFF")
			end
		end)
	elseif m ~= 0 then
		startMode(m)
	end
	return true
end

-- BOOST page: mode selector
local modeBtns, descLabel = {}, nil
local function modeColor(m)
	if m == 0 then return C.gray end
	if m == 1 then return C.ice end
	if m == 2 then return C.green end
	if m == 3 then return C.glitch end
	return C.red
end
local function refreshModeUI(sel)
	for m = 0, 4 do
		local on = (m == sel)
		modeBtns[m].BackgroundColor3 = on and modeColor(m) or C.row
		modeBtns[m].BackgroundTransparency = on and 0.05 or 0.3
		modeBtns[m].TextColor3 = on and ((m == 0) and C.text or Color3.fromRGB(6, 10, 20)) or C.dim
	end
	descLabel.Text = MODE_DESC[sel]
end

sectionLabel(pgBoost, 1, "FPS MODE")
local modeRow = new("Frame", {
	LayoutOrder = 2, Size = UDim2.new(1, -4, 0, 36), BackgroundTransparency = 1,
}, pgBoost)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, modeRow)
for m = 0, 4 do
	local b = new("TextButton", {
		LayoutOrder = m, Size = UDim2.new(0.2, -4, 1, 0),
		BackgroundColor3 = C.row, BackgroundTransparency = 0.3,
		Text = MODE_NAMES[m], Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.dim,
		AutoButtonColor = false,
	}, modeRow)
	corner(b, 8)
	modeBtns[m] = b
	b.MouseButton1Click:Connect(function()
		if setMode(m) then
			refreshModeUI(m)
			if m ~= 0 then showToast(MODE_NAMES[m] .. "...") end
		end
	end)
end
descLabel = new("TextLabel", {
	LayoutOrder = 3, Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = C.dim, Text = "",
}, pgBoost)
refreshModeUI(0)
cleanups[#cleanups + 1] = function()
	boost.gen += 1
	if boost.conn then pcall(function() boost.conn:Disconnect() end) end
	setFreeze(false)
	if boost.mode ~= 0 then stopCurrent() end
end

------------------------------------------------------------
-- BOOST page extras + TOOLS page
------------------------------------------------------------
local fpsWatchers = {}   -- called every 0.5s with the current FPS

do
	sectionLabel(pgBoost, 10, "AUTOMATIC")
	-- Auto Boost: if FPS stays under 25 for ~5s switch to BOOST; still low ~10s later, POTATO
	local on, low, escalated = false, 0, false
	fpsWatchers[#fpsWatchers + 1] = function(fps)
		if not on or boost.busy then return end
		if fps < 25 then low += 1 else low = math.max(low - 1, 0) end
		if low >= 10 and boost.mode == 0 then
			low, escalated = 0, false
			if setMode(1) then refreshModeUI(1) end
			showToast("Auto Boost: BOOST")
		elseif low >= 20 and boost.mode == 1 and not escalated then
			escalated = true
			if setMode(2) then refreshModeUI(2) end
			showToast("Auto Boost: POTATO")
		end
	end
	makeToggle(pgBoost, "Auto Boost when FPS drops", 11, false, function(v)
		on, low, escalated = v, 0, false
		setStatus(v and "Auto Boost armed (acts if FPS stays under 25)." or "Auto Boost off.")
		showToast(v and "Auto Boost: ON" or "Auto Boost: OFF")
	end)

	sectionLabel(pgBoost, 20, "FRAMERATE")
	local CAPS = { 30, 60, 90, 120, 144, 240, 0 }
	local capIdx = 2
	local capBtn = makeButton(pgBoost, "FPS CAP: 60  (tap to change)", 21, C.gray)
	capBtn.MouseButton1Click:Connect(function()
		if not setfpscap then
			setStatus("FPS cap needs an executor with setfpscap.")
			return
		end
		capIdx = capIdx % #CAPS + 1
		local cap = CAPS[capIdx]
		pcall(setfpscap, cap)
		local label = cap == 0 and "UNLIMITED" or tostring(cap)
		capBtn.Text = "FPS CAP: " .. label .. "  (tap to change)"
		setStatus("FPS cap: " .. label)
		showToast("FPS Cap: " .. label)
	end)

	-- 3D OFF: black screen, near-zero GPU use (great for AFK)
	local function set3d(off)
		pcall(function() RunService:Set3dRenderingEnabled(not off) end)
	end
	makeToggle(pgBoost, "3D OFF (AFK black screen)", 22, false, function(v)
		set3d(v)
		setStatus(v and "3D off. Toggle again to see the game." or "3D back on.")
		showToast(v and "3D Rendering: OFF" or "3D Rendering: ON")
	end)
	cleanups[#cleanups + 1] = function() set3d(false) end
end

do
	sectionLabel(pgTools, 1, "UTILITIES")
	-- Anti-AFK
	local afkConn = nil
	makeToggle(pgTools, "Anti-AFK", 2, false, function(v)
		if afkConn then
			afkConn:Disconnect()
			afkConn = nil
		end
		if v then
			afkConn = player.Idled:Connect(function()
				pcall(function()
					local vu = game:GetService("VirtualUser")
					vu:CaptureController()
					vu:ClickButton2(Vector2.new())
				end)
			end)
		end
		setStatus(v and "Anti-AFK on: idling won't kick you." or "Anti-AFK off.")
		showToast(v and "Anti-AFK: ON" or "Anti-AFK: OFF")
	end)
	cleanups[#cleanups + 1] = function()
		if afkConn then afkConn:Disconnect() end
	end

	-- Mute game audio
	local muteSaved = nil
	local function setMute(v)
		return (pcall(function()
			local gs = UserSettings():GetService("UserGameSettings")
			if v then
				muteSaved = gs.MasterVolume
				gs.MasterVolume = 0
			elseif muteSaved ~= nil then
				gs.MasterVolume = muteSaved
				muteSaved = nil
			end
		end))
	end
	local muteToggle = nil
	muteToggle = makeToggle(pgTools, "Mute game audio", 3, false, function(v)
		if setMute(v) then
			showToast(v and "Mute: ON" or "Mute: OFF")
		else
			setStatus("Muting isn't supported by your executor.")
			task.defer(function() muteToggle.set(false) end)
		end
	end)
	cleanups[#cleanups + 1] = function() setMute(false) end

	-- Stretch resolution (camera effect, runs right after the camera scripts)
	local STRETCH = "FrostGlixhtStretch"
	local stretchCF = CFrame.new(0, 0, 0, 1, 0, 0, 0, 0.65, 0, 0, 0, 1)
	local stretchLast = nil
	local function stopStretch()
		pcall(function() RunService:UnbindFromRenderStep(STRETCH) end)
		stretchLast = nil
	end
	makeToggle(pgTools, "Stretch resolution", 4, false, function(v)
		stopStretch()
		if v then
			pcall(function()
				RunService:BindToRenderStep(STRETCH, Enum.RenderPriority.Camera.Value + 1, function()
					local cam = workspace.CurrentCamera
					if not cam then return end
					local cf = cam.CFrame
					if cf == stretchLast then return end
					stretchLast = cf * stretchCF
					cam.CFrame = stretchLast
				end)
			end)
		end
		showToast(v and "Stretch: ON" or "Stretch: OFF")
	end)
	cleanups[#cleanups + 1] = stopStretch


end

------------------------------------------------------------
-- LOOK: brightness, shaders, sky changer, fog (client side)
------------------------------------------------------------
do
	local look = { orig = {}, created = {}, shaderOn = false, tech = nil }
	local fogOn = false

	-- brightness never conflicts with the FPS modes, everything else does
	lookActive = function()
		if look.shaderOn or look.tech ~= nil or fogOn then return true end
		for _, props in pairs(look.orig) do
			for _, box in pairs(props) do
				if box[2] ~= "bright" then return true end
			end
		end
		return false
	end

	local function allowed()
		if boost.mode ~= 0 or boost.busy then
			setStatus("Set the FPS mode to OFF first to use this LOOK effect.")
			showToast("FPS mode must be OFF")
			return false
		end
		return true
	end

	local function lookPut(cat, inst, prop, target)
		local o = look.orig[inst]
		if not o then
			o = {}
			look.orig[inst] = o
		end
		if o[prop] == nil then
			local ok, cur = pcall(getProp, inst, prop)
			if not ok then return end
			o[prop] = { cur, cat }
		end
		pcall(setProp, inst, prop, target)
	end

	local function restoreCat(cat)
		for inst, props in pairs(look.orig) do
			for prop, box in pairs(props) do
				if cat == nil or box[2] == cat then
					pcall(setProp, inst, prop, box[1])
					props[prop] = nil
				end
			end
			if next(props) == nil then look.orig[inst] = nil end
		end
	end

	local function make(class, name)
		local full = "FrostFps_" .. name
		local e = Lighting:FindFirstChild(full)
		if not e then
			e = Instance.new(class)
			e.Name = full
			if e:IsA("PostEffect") then e.Enabled = false end
			e.Parent = Lighting
			look.created[#look.created + 1] = e
		end
		return e
	end

	-- a 2-column grid of preset buttons (one stays highlighted)
	local function presetGrid(order, names, onPick)
		local rows = math.ceil(#names / 2)
		local grid = new("Frame", {
			LayoutOrder = order, Size = UDim2.new(1, -4, 0, rows * 36 - 4), BackgroundTransparency = 1,
		}, pgLook)
		new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -3, 0, 32), CellPadding = UDim2.fromOffset(4, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, grid)
		local btns = {}
		local function select(sel)
			for i, b in ipairs(btns) do
				local on = (i == sel)
				b.BackgroundColor3 = on and C.ice or C.row
				b.BackgroundTransparency = on and 0.05 or 0.25
				b.TextColor3 = on and Color3.fromRGB(6, 10, 20) or C.text
			end
		end
		for i, n in ipairs(names) do
			local b = new("TextButton", {
				LayoutOrder = i, Text = n, Font = Enum.Font.GothamBold, TextSize = 11,
				TextColor3 = C.text, BackgroundColor3 = C.row, BackgroundTransparency = 0.25,
				AutoButtonColor = false,
			}, grid)
			corner(b, 8)
			btns[i] = b
			b.MouseButton1Click:Connect(function() onPick(i) end)
		end
		select(1)
		return { select = select }
	end

	local f1 = function(v) return ("%.1f"):format(v) end
	local f2 = function(v) return ("%.2f"):format(v) end

	-- ---------------------------------------------------- BRIGHTNESS (works with any FPS mode)
	sectionLabel(pgLook, -10, "BRIGHTNESS")
	local fbToggle, brightSlider, expSlider = nil, nil, nil
	fbToggle = makeToggle(pgLook, "Fullbright (see everything)", -9, false, function(on)
		if on then
			lookPut("bright", Lighting, "Ambient", Color3.new(1, 1, 1))
			lookPut("bright", Lighting, "OutdoorAmbient", Color3.new(1, 1, 1))
			lookPut("bright", Lighting, "Brightness", 3)
			if brightSlider then brightSlider.set(3, false) end
		else
			restoreCat("bright")
			if brightSlider then brightSlider.set(Lighting.Brightness, false) end
			if expSlider then expSlider.set(Lighting.ExposureCompensation, false) end
		end
		showToast(on and "Fullbright: ON" or "Fullbright: OFF")
	end)
	brightSlider = makeSlider(pgLook, -8, "World brightness", 0, 10, math.clamp(Lighting.Brightness, 0, 10), 0.1, f1, function(v)
		lookPut("bright", Lighting, "Brightness", v)
	end)
	expSlider = makeSlider(pgLook, -7, "Exposure", -3, 3, math.clamp(Lighting.ExposureCompensation, -3, 3), 0.1, f1, function(v)
		lookPut("bright", Lighting, "ExposureCompensation", v)
	end)

	-- ---------------------------------------------------- SHADERS
	local sh = { bright = 0, contrast = 0, sat = 0, bloom = 0, rays = 0, blur = 0, dof = 0, tint = Color3.new(1, 1, 1) }
	local sliders = {}
	local futureToggle = nil

	local function applyShader()
		local cc = make("ColorCorrectionEffect", "cc")
		cc.Brightness, cc.Contrast, cc.Saturation, cc.TintColor = sh.bright, sh.contrast, sh.sat, sh.tint
		cc.Enabled = true
		local bl = make("BloomEffect", "bloom")
		bl.Intensity, bl.Size, bl.Threshold = sh.bloom, 28, 1.4
		bl.Enabled = sh.bloom > 0
		local sun = make("SunRaysEffect", "sun")
		sun.Intensity, sun.Spread = sh.rays, 0.7
		sun.Enabled = sh.rays > 0
		local blur = make("BlurEffect", "blur")
		blur.Size = sh.blur
		blur.Enabled = sh.blur > 0
		local dof = make("DepthOfFieldEffect", "dof")
		dof.FarIntensity, dof.FocusDistance, dof.InFocusRadius, dof.NearIntensity = sh.dof, 80, 50, 0
		dof.Enabled = sh.dof > 0
		look.shaderOn = true
	end

	local function setFuture(on)
		if on then
			if not (gethiddenproperty and sethiddenproperty) then
				setStatus("Future lighting needs an executor with sethiddenproperty.")
				task.defer(function() if futureToggle then futureToggle.set(false) end end)
				return
			end
			if look.tech == nil then
				local ok, cur = pcall(gethiddenproperty, Lighting, "Technology")
				if ok then look.tech = cur end
			end
			pcall(sethiddenproperty, Lighting, "Technology", Enum.Technology.Future)
			lookPut("shader", Lighting, "GlobalShadows", true)
		else
			if look.tech ~= nil and sethiddenproperty then
				pcall(sethiddenproperty, Lighting, "Technology", look.tech)
			end
			look.tech = nil
			restoreCat("shader")
		end
	end

	local function shaderOff()
		for _, e in ipairs(look.created) do
			if e:IsA("PostEffect") then e.Enabled = false end
		end
		look.shaderOn = false
		sh.bright, sh.contrast, sh.sat, sh.bloom, sh.rays, sh.blur, sh.dof = 0, 0, 0, 0, 0, 0, 0
		sh.tint = Color3.new(1, 1, 1)
		for _, s in pairs(sliders) do s.set(0, false) end
	end

	local SHADERS = {
		{ "OFF" },
		{ "CINEMATIC", bright = 0.02, contrast = 0.25, sat = 0.1, bloom = 0.5, rays = 0.12, blur = 0, dof = 0.15, tint = Color3.fromRGB(235, 238, 255) },
		{ "VIBRANT", bright = 0.03, contrast = 0.15, sat = 0.45, bloom = 0.6, rays = 0.1, blur = 0, dof = 0, tint = Color3.new(1, 1, 1) },
		{ "NOIR", bright = 0, contrast = 0.4, sat = -1, bloom = 0.2, rays = 0, blur = 0, dof = 0.1, tint = Color3.new(1, 1, 1) },
		{ "SUNSET", bright = 0.02, contrast = 0.2, sat = 0.25, bloom = 0.8, rays = 0.3, blur = 0, dof = 0.1, tint = Color3.fromRGB(255, 205, 165) },
		{ "DREAM", bright = 0.05, contrast = 0.05, sat = 0.2, bloom = 1.3, rays = 0.15, blur = 4, dof = 0, tint = Color3.fromRGB(255, 228, 245) },
		{ "RTX", bright = 0.01, contrast = 0.22, sat = 0.22, bloom = 0.7, rays = 0.25, blur = 0, dof = 0.12, tint = Color3.fromRGB(245, 248, 255), future = true },
	}

	sectionLabel(pgLook, 1, "SHADERS")
	local shNames = {}
	for i, p in ipairs(SHADERS) do shNames[i] = p[1] end
	local shGrid = nil
	shGrid = presetGrid(2, shNames, function(i)
		if not allowed() then return end
		local p = SHADERS[i]
		shGrid.select(i)
		if i == 1 then
			shaderOff()
			setFuture(false)
			if futureToggle then futureToggle.set(false) end
			setStatus("Shaders off.")
			showToast("Shaders: OFF")
			return
		end
		sh.bright, sh.contrast, sh.sat, sh.bloom, sh.rays, sh.blur, sh.dof, sh.tint =
			p.bright, p.contrast, p.sat, p.bloom, p.rays, p.blur, p.dof, p.tint
		sliders.bright.set(p.bright, false)
		sliders.contrast.set(p.contrast, false)
		sliders.sat.set(p.sat, false)
		sliders.bloom.set(p.bloom, false)
		sliders.rays.set(p.rays, false)
		sliders.blur.set(p.blur, false)
		applyShader()
		if p.future then
			setFuture(true)
			if futureToggle then futureToggle.set(true) end
		end
		setStatus("Shader preset: " .. p[1])
		showToast("Shader: " .. p[1])
	end)

	local function sliderFor(order, key, label, minV, maxV, step, fmt)
		sliders[key] = makeSlider(pgLook, order, label, minV, maxV, 0, step, fmt, function(v)
			if not allowed() then return end
			sh[key] = v
			applyShader()
		end)
	end
	sliderFor(3, "bright", "Shader brightness", -0.3, 0.3, 0.01, f2)
	sliderFor(4, "contrast", "Contrast", -0.5, 0.8, 0.05, f2)
	sliderFor(5, "sat", "Saturation", -1, 1, 0.05, f2)
	sliderFor(6, "bloom", "Bloom (glow)", 0, 2, 0.05, f2)
	sliderFor(7, "rays", "Sun rays", 0, 1, 0.05, f2)
	sliderFor(8, "blur", "Blur", 0, 20, 1, function(v) return tostring(math.floor(v)) end)
	futureToggle = makeToggle(pgLook, "Future lighting (real shadows)", 9, false, function(on)
		if not allowed() then
			task.defer(function() futureToggle.set(false) end)
			return
		end
		setFuture(on)
		showToast(on and "Future Lighting: ON" or "Future Lighting: OFF")
	end)

	-- ---------------------------------------------------- SKY CHANGER
	local function ensureSky()
		local s = Lighting:FindFirstChildOfClass("Sky")
		if not s then
			s = Instance.new("Sky")
			s.Name = "FrostFpsSky"
			s.Parent = Lighting
			look.created[#look.created + 1] = s
		end
		return s
	end
	local function ensureAtmo()
		local a = Lighting:FindFirstChildOfClass("Atmosphere")
		if not a then
			a = Instance.new("Atmosphere")
			a.Name = "FrostFpsAtmosphere"
			a.Parent = Lighting
			look.created[#look.created + 1] = a
		end
		return a
	end

	local SKIES = {
		{ "DEFAULT" },
		{ "SUNSET", time = 18.2, color = Color3.fromRGB(255, 170, 120), decay = Color3.fromRGB(200, 90, 60), glare = 0.4, offset = 0.25, stars = 0, bodies = true },
		{ "NIGHT", time = 0, color = Color3.fromRGB(20, 25, 60), decay = Color3.fromRGB(10, 10, 35), glare = 0, offset = 0.2, stars = 3000, bodies = true },
		{ "OVERCAST", time = 14, color = Color3.fromRGB(190, 190, 196), decay = Color3.fromRGB(120, 120, 126), glare = 0, offset = 1, stars = 0, bodies = false },
		{ "PINK DREAM", time = 17.5, color = Color3.fromRGB(255, 150, 220), decay = Color3.fromRGB(255, 90, 170), glare = 0.3, offset = 0.25, stars = 0, bodies = true },
		{ "CLEAR DAY", time = 12, color = Color3.fromRGB(199, 170, 107), decay = Color3.fromRGB(92, 60, 13), glare = 0, offset = 0, stars = 0, bodies = true },
		{ "SPACE", time = 0, color = Color3.fromRGB(0, 0, 0), decay = Color3.fromRGB(0, 0, 0), glare = 0, offset = 0, stars = 5000, bodies = false },
		{ "TOXIC", time = 19, color = Color3.fromRGB(120, 255, 90), decay = Color3.fromRGB(40, 120, 30), glare = 0.2, offset = 0.3, stars = 0, bodies = true },
		{ "BLOOD MOON", time = 23, color = Color3.fromRGB(255, 60, 60), decay = Color3.fromRGB(110, 10, 10), glare = 0.3, offset = 0.3, stars = 1500, bodies = true },
	}
	local timeSlider = nil
	sectionLabel(pgLook, 20, "SKY CHANGER")
	local skyNames = {}
	for i, p in ipairs(SKIES) do skyNames[i] = p[1] end
	local skyGrid = nil
	skyGrid = presetGrid(21, skyNames, function(i)
		if not allowed() then return end
		local p = SKIES[i]
		skyGrid.select(i)
		if i == 1 then
			restoreCat("sky")
			setStatus("Sky back to the game's own.")
			showToast("Sky: DEFAULT")
			return
		end
		local sky, atmo = ensureSky(), ensureAtmo()
		lookPut("sky", Lighting, "ClockTime", p.time)
		lookPut("sky", sky, "StarCount", p.stars)
		lookPut("sky", sky, "CelestialBodiesShown", p.bodies)
		lookPut("sky", atmo, "Color", p.color)
		lookPut("sky", atmo, "Decay", p.decay)
		lookPut("sky", atmo, "Glare", p.glare)
		lookPut("sky", atmo, "Offset", p.offset)
		if timeSlider then timeSlider.set(p.time, false) end
		setStatus("Sky: " .. p[1])
		showToast("Sky: " .. p[1])
	end)
	timeSlider = makeSlider(pgLook, 22, "Time of day", 0, 24, 12, 0.25, function(v)
		return ("%d:%02d"):format(math.floor(v) % 24, math.floor((v % 1) * 60 + 0.5) % 60)
	end, function(v)
		if not allowed() then return end
		lookPut("sky", Lighting, "ClockTime", v)
	end)

	local skyBox = makeBox(pgLook, 23, "custom sky ids: 1 id, or 6 (Bk Dn Ft Lf Rt Up)", "", 34, false)
	local skyApply = makeButton(pgLook, "APPLY CUSTOM SKY", 24, C.green)
	skyApply.MouseButton1Click:Connect(function()
		if not allowed() then return end
		local ids = {}
		for n in skyBox.Text:gmatch("%d+") do ids[#ids + 1] = n end
		if #ids ~= 1 and #ids ~= 6 then
			setStatus("Type 1 image id (used on all sides) or 6 ids.")
			return
		end
		local sky = ensureSky()
		local faces = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }
		for i, face in ipairs(faces) do
			lookPut("sky", sky, face, "rbxassetid://" .. (ids[i] or ids[1]))
		end
		setStatus("Custom sky applied.")
		showToast("Custom Sky: ON")
	end)

	-- ---------------------------------------------------- FOG
	local fog = { start = 0, stop = 400, color = Color3.fromRGB(190, 198, 212), density = 0.4, haze = 0 }
	local function applyFog()
		if not fogOn then return end
		lookPut("fog", Lighting, "FogStart", fog.start)
		lookPut("fog", Lighting, "FogEnd", fog.stop)
		lookPut("fog", Lighting, "FogColor", fog.color)
		local atmo = ensureAtmo()
		lookPut("fog", atmo, "Density", fog.density)
		lookPut("fog", atmo, "Haze", fog.haze)
	end

	sectionLabel(pgLook, 40, "FOG")
	local fogToggle = nil
	fogToggle = makeToggle(pgLook, "Custom fog", 41, false, function(on)
		if on and not allowed() then
			task.defer(function() fogToggle.set(false) end)
			return
		end
		fogOn = on
		if on then
			applyFog()
		else
			restoreCat("fog")
		end
		showToast(on and "Fog: ON" or "Fog: OFF")
	end)
	local function fogSlider(order, label, minV, maxV, val, step, key, fmt)
		makeSlider(pgLook, order, label, minV, maxV, val, step, fmt, function(v)
			fog[key] = v
			if not fogOn then
				setStatus("Turn on \"Custom fog\" to see this.")
				return
			end
			applyFog()
		end)
	end
	local fInt = function(v) return tostring(math.floor(v)) end
	fogSlider(42, "Fog start", 0, 1000, 0, 10, "start", fInt)
	fogSlider(43, "Fog end (distance)", 50, 3000, 400, 50, "stop", fInt)
	fogSlider(44, "Atmosphere density", 0, 1, 0.4, 0.02, "density", f2)
	fogSlider(45, "Atmosphere haze", 0, 10, 0, 0.5, "haze", f1)

	local FOG_COLORS = {
		Color3.fromRGB(235, 238, 245), Color3.fromRGB(150, 160, 175), Color3.fromRGB(110, 160, 255),
		Color3.fromRGB(255, 170, 110), Color3.fromRGB(120, 230, 150), Color3.fromRGB(255, 140, 210),
		Color3.fromRGB(255, 90, 100), Color3.fromRGB(20, 24, 34),
	}
	local colorRow = new("Frame", {
		LayoutOrder = 46, Size = UDim2.new(1, -4, 0, 32), BackgroundTransparency = 1,
	}, pgLook)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, colorRow)
	for i, col in ipairs(FOG_COLORS) do
		local b = new("TextButton", {
			LayoutOrder = i, Size = UDim2.new(1 / #FOG_COLORS, -4, 1, 0),
			BackgroundColor3 = col, BorderSizePixel = 0, Text = "", AutoButtonColor = true,
		}, colorRow)
		corner(b, 6)
		b.MouseButton1Click:Connect(function()
			fog.color = col
			if fogOn then
				applyFog()
			else
				setStatus("Turn on \"Custom fog\" to see this.")
			end
		end)
	end

	-- ---------------------------------------------------- RESET
	local resetBtn = makeButton(pgLook, "RESET LOOK (undo everything here)", 60, C.red)
	local function resetAll()
		restoreCat(nil)
		setFuture(false)
		shaderOff()
		for _, inst in ipairs(look.created) do pcall(function() inst:Destroy() end) end
		look.created = {}
		fogOn = false
		shGrid.select(1)
		skyGrid.select(1)
		if fogToggle then fogToggle.set(false) end
		if futureToggle then futureToggle.set(false) end
		if fbToggle then fbToggle.set(false) end
		brightSlider.set(math.clamp(Lighting.Brightness, 0, 10), false)
		expSlider.set(math.clamp(Lighting.ExposureCompensation, -3, 3), false)
	end
	resetBtn.MouseButton1Click:Connect(function()
		resetAll()
		setStatus("LOOK reset: the game looks like itself again.")
		showToast("LOOK: RESET")
	end)
	cleanups[#cleanups + 1] = resetAll
end

------------------------------------------------------------
-- Players tab: hide everyone, or pick who disappears
------------------------------------------------------------
local hideSet, setPlayerHidden
do
local hiddenState = {}   -- instance -> original value
hideSet = {}             -- [Player] = true while hidden
local hideConns = {}     -- [Player] = { connections }
local rows = {}          -- [Player] = toggle row
local hideAllOn = false
local rowOrder = 100

local function hideInst(inst)
	if hiddenState[inst] ~= nil then return end
	if inst:IsA("BasePart") then
		hiddenState[inst] = inst.LocalTransparencyModifier
		inst.LocalTransparencyModifier = 1
	elseif inst:IsA("Decal") then
		hiddenState[inst] = inst.Transparency
		inst.Transparency = 1
	elseif inst:IsA("BillboardGui") then
		hiddenState[inst] = inst.Enabled
		inst.Enabled = false
	end
end

local function restoreInst(inst, orig)
	pcall(function()
		if inst:IsA("BasePart") then
			inst.LocalTransparencyModifier = orig
		elseif inst:IsA("Decal") then
			inst.Transparency = orig
		elseif inst:IsA("BillboardGui") then
			inst.Enabled = orig
		end
	end)
end

function setPlayerHidden(p, on)
	if p == player then return end
	if on then
		if hideSet[p] then return end
		hideSet[p] = true
		local conns = {}
		local function hook(char)
			for _, d in ipairs(char:GetDescendants()) do pcall(hideInst, d) end
			conns[#conns + 1] = char.DescendantAdded:Connect(function(d)
				pcall(hideInst, d)
			end)
		end
		if p.Character then hook(p.Character) end
		conns[#conns + 1] = p.CharacterAdded:Connect(hook)
		hideConns[p] = conns
	else
		if not hideSet[p] then return end
		hideSet[p] = nil
		for _, c in ipairs(hideConns[p] or {}) do c:Disconnect() end
		hideConns[p] = nil
		local char = p.Character
		if char then
			for inst, orig in pairs(hiddenState) do
				if inst:IsDescendantOf(char) then
					restoreInst(inst, orig)
					hiddenState[inst] = nil
				end
			end
		end
	end
end

-- My nametag: change or hide the name above your head (only you see it)
do
	new("TextLabel", {
		LayoutOrder = 1,
		Size = UDim2.new(1, -4, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.ice,
		TextStrokeTransparency = 0.5,
		Text = "MY NAMETAG (only you see it)",
	}, pgPlayers)
	local nameBox = makeBox(pgPlayers, 2, "new name above your head", "", 30, false)
	local nameRow = new("Frame", {
		LayoutOrder = 3,
		Size = UDim2.new(1, -4, 0, 32),
		BackgroundTransparency = 1,
	}, pgPlayers)
	local applyBtn = new("TextButton", {
		Size = UDim2.new(0.5, -3, 1, 0),
		BackgroundColor3 = C.blue,
		BackgroundTransparency = 0.1,
		Text = "APPLY",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = C.text,
	}, nameRow)
	corner(applyBtn, 8)
	local resetBtn = new("TextButton", {
		Position = UDim2.new(0.5, 3, 0, 0),
		Size = UDim2.new(0.5, -3, 1, 0),
		BackgroundColor3 = C.gray,
		BackgroundTransparency = 0.1,
		Text = "RESET",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = C.text,
	}, nameRow)
	corner(resetBtn, 8)

	local st = { text = nil, orig = nil, hooked = {}, conns = {}, guard = false, olds = {} }

	local function esc(s) return (s:gsub("%p", "%%%0")) end
	local function repl(s) return (s:gsub("%%", "%%%%")) end

	local function swap(txt)
		if not st.text or txt:find(st.text, 1, true) then return txt end
		local out = txt
		for _, o in ipairs(st.olds) do
			if o ~= "" then out = out:gsub(esc(o), repl(st.text)) end
		end
		return out
	end

	local function isTagLabel(d)
		return (d:IsA("TextLabel") or d:IsA("TextButton"))
			and (d:FindFirstAncestorOfClass("BillboardGui") ~= nil
				or d:FindFirstAncestorOfClass("SurfaceGui") ~= nil)
	end

	local function hookLabel(lbl)
		if st.hooked[lbl] ~= nil then return end
		st.hooked[lbl] = lbl.Text
		local function fix()
			if st.guard or not st.text then return end
			local nt = swap(lbl.Text)
			if nt ~= lbl.Text then
				st.guard = true
				pcall(function() lbl.Text = nt end)
				st.guard = false
			end
		end
		st.conns[#st.conns + 1] = lbl:GetPropertyChangedSignal("Text"):Connect(fix)
		fix()
	end

	local function applyToCharacter(char)
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
		if hum then
			if st.orig == nil then st.orig = hum.DisplayName end
			pcall(function() hum.DisplayName = st.text end)
		end
		st.olds = { player.Name, player.DisplayName, st.orig or "" }
		for _, d in ipairs(char:GetDescendants()) do
			if isTagLabel(d) then pcall(hookLabel, d) end
		end
		st.conns[#st.conns + 1] = char.DescendantAdded:Connect(function(d)
			task.defer(function()
				if st.text and d.Parent and isTagLabel(d) then pcall(hookLabel, d) end
			end)
		end)
	end

	local function resetName()
		for _, c in ipairs(st.conns) do pcall(function() c:Disconnect() end) end
		st.conns = {}
		st.text = nil
		for lbl, orig in pairs(st.hooked) do
			pcall(function()
				if lbl.Parent then lbl.Text = orig end
			end)
		end
		st.hooked = {}
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and st.orig ~= nil then
			pcall(function() hum.DisplayName = st.orig end)
		end
		st.orig = nil
	end

	applyBtn.MouseButton1Click:Connect(function()
		local n = nameBox.Text:match("^%s*(.-)%s*$")
		if n == "" then
			setStatus("Type a name first.")
			return
		end
		if #n > 40 then n = n:sub(1, 40) end
		resetName()
		st.text = n
		if player.Character then task.spawn(applyToCharacter, player.Character) end
		setStatus("Nametag set to: " .. n .. " (only you see it)")
	end)
	resetBtn.MouseButton1Click:Connect(function()
		resetName()
		setStatus("Nametag reset.")
	end)
	track(player.CharacterAdded:Connect(function(char)
		if st.text then task.spawn(applyToCharacter, char) end
	end))
	cleanups[#cleanups + 1] = resetName

	local tagSaved = nil
	makeToggle(pgPlayers, "Hide My Nametag", 4, false, function(on)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then
			setStatus("Character isn't loaded yet.")
			return
		end
		if on then
			tagSaved = hum.DisplayDistanceType
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		elseif tagSaved ~= nil then
			hum.DisplayDistanceType = tagSaved
			tagSaved = nil
		end
	end)
end

makeToggle(pgPlayers, "Hide All Players", 10, false, function(on)
	hideAllOn = on
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			setPlayerHidden(p, on)
			if rows[p] then rows[p].set(on) end
		end
	end
	setStatus(on and "All other players hidden." or "Other players visible again.")
	showToast(on and "Hide All Players: ON" or "Hide All Players: OFF")
end)

new("TextLabel", {
	LayoutOrder = 11,
	Size = UDim2.new(1, -4, 0, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.ice,
	TextStrokeTransparency = 0.5,
	Text = "PICK WHO DISAPPEARS",
}, pgPlayers)

local function addRow(p)
	if p == player or rows[p] then return end
	rowOrder += 1
	rows[p] = makeToggle(pgPlayers, "• " .. p.DisplayName, rowOrder, hideSet[p] == true, function(on)
		setPlayerHidden(p, on)
		setStatus((on and "Hidden: " or "Visible: ") .. p.DisplayName)
	end)
end

local function removeRow(p)
	setPlayerHidden(p, false)
	if rows[p] then
		rows[p].destroy()
		rows[p] = nil
	end
end

for _, p in ipairs(Players:GetPlayers()) do addRow(p) end
track(Players.PlayerAdded:Connect(function(p)
	addRow(p)
	if hideAllOn then
		setPlayerHidden(p, true)
		if rows[p] then rows[p].set(true) end
	end
end))
track(Players.PlayerRemoving:Connect(removeRow))

end

------------------------------------------------------------
-- SERVER tab: server browser + console (tap JOIN, or type commands)
------------------------------------------------------------
do
	local TeleportService = game:GetService("TeleportService")
	local HttpService = game:GetService("HttpService")
	local servers, rows, logLines = {}, {}, {}
	local rebuild, fetch

	sectionLabel(pgServer, 1, "CONSOLE")
	local logBox = new("ScrollingFrame", {
		LayoutOrder = 2, Size = UDim2.new(1, -4, 0, 110),
		BackgroundColor3 = C.dark, BackgroundTransparency = 0.15, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = C.ice,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, pgServer)
	corner(logBox, 8)
	local logText = new("TextLabel", {
		Position = UDim2.fromOffset(8, 5), Size = UDim2.new(1, -16, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		Font = Enum.Font.Code, TextSize = 11, TextWrapped = true, RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.dim, Text = "",
	}, logBox)
	local function log(msg, color)
		logLines[#logLines + 1] = ('<font color="#6c7a99">%s</font> <font color="%s">%s</font>'):format(
			os.date("%H:%M:%S"), color or "#c8d4ee", msg)
		if #logLines > 80 then table.remove(logLines, 1) end
		logText.Text = table.concat(logLines, "\n")
		task.defer(function()
			logBox.CanvasPosition = Vector2.new(0, math.max(0, logBox.AbsoluteCanvasSize.Y - logBox.AbsoluteSize.Y))
		end)
	end

	local function joinServer(id, label)
		if id == game.JobId then
			log("you are already in that server.", "#ffd35a")
			return
		end
		log("joining " .. label .. " ...", "#8fd8ff")
		showToast("Joining server...")
		local ok, err = pcall(function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, id, player)
		end)
		if not ok then log("teleport failed: " .. tostring(err), "#ff6a7a") end
	end

	function fetch(onDone)
		log("fetching the server list...", "#8fd8ff")
		task.spawn(function()
			local ok, body = pcall(function()
				return game:HttpGet(("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId))
			end)
			if not ok or not body then
				log("could not read the list (your executor needs HttpGet).", "#ff6a7a")
				return
			end
			local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
			if not ok2 or type(data) ~= "table" or type(data.data) ~= "table" then
				log("bad reply (rate limited? wait a few seconds).", "#ff6a7a")
				return
			end
			servers = {}
			for _, s in ipairs(data.data) do
				if s.id and s.playing and s.maxPlayers then servers[#servers + 1] = s end
			end
			table.sort(servers, function(a, b) return (a.ping or 99999) < (b.ping or 99999) end)
			log(("found %d servers (lowest ping first)"):format(#servers), "#6cf0b0")
			rebuild()
			if onDone then onDone() end
		end)
	end

	local function bestServer()
		for _, s in ipairs(servers) do
			if s.id ~= game.JobId and s.playing < s.maxPlayers - 1 then return s end
		end
		return nil
	end

	local function hop()
		local function go()
			local s = bestServer()
			if not s then
				log("no free server found.", "#ff6a7a")
				return
			end
			joinServer(s.id, ("the best server (%s ms)"):format(tostring(s.ping and math.floor(s.ping) or "?")))
		end
		if #servers == 0 then fetch(go) else go() end
	end

	local function rejoin()
		log("rejoining...", "#8fd8ff")
		pcall(function()
			if #Players:GetPlayers() <= 1 then
				TeleportService:Teleport(game.PlaceId, player)
			else
				TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
			end
		end)
	end

	local function run(text)
		text = text:match("^%s*(.-)%s*$")
		if text == "" then return end
		log("> " .. (text:gsub("[<>]", "")), "#ffffff")
		local cmd, arg = text:match("^(%S+)%s*(.-)$")
		cmd = cmd:lower()
		if cmd == "help" then
			log("list | refresh  - load servers", "#c8d4ee")
			log("join <number|jobid>  - join one", "#c8d4ee")
			log("hop  - join the lowest ping server", "#c8d4ee")
			log("rejoin | players | jobid | copyid | clear", "#c8d4ee")
		elseif cmd == "list" or cmd == "refresh" then
			fetch()
		elseif cmd == "join" then
			local n = tonumber(arg)
			if n and servers[n] then
				joinServer(servers[n].id, "#" .. n)
			elseif arg:match("^%x+%-%x+%-%x+%-%x+%-%x+$") then
				joinServer(arg, "that job id")
			else
				log("usage: join <number from the list> or join <jobid>", "#ffd35a")
			end
		elseif cmd == "hop" then
			hop()
		elseif cmd == "rejoin" then
			rejoin()
		elseif cmd == "players" then
			log(("%d / %d players here"):format(#Players:GetPlayers(), Players.MaxPlayers), "#6cf0b0")
		elseif cmd == "jobid" then
			log(game.JobId == "" and "(studio / no job id)" or game.JobId, "#6cf0b0")
		elseif cmd == "copyid" then
			if setclipboard then
				pcall(setclipboard, game.JobId)
				log("job id copied.", "#6cf0b0")
			else
				log("your executor has no clipboard function.", "#ffd35a")
			end
		elseif cmd == "clear" then
			logLines = {}
			logText.Text = ""
		else
			log("unknown command. type help", "#ff6a7a")
		end
	end

	local cmdBox = makeBox(pgServer, 3, "> type a command  (help)", "", 34, false)
	cmdBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			run(cmdBox.Text)
			cmdBox.Text = ""
		end
	end)

	local btnRow = new("Frame", {
		LayoutOrder = 4, Size = UDim2.new(1, -4, 0, 36), BackgroundTransparency = 1,
	}, pgServer)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, btnRow)
	local function rowBtn(order, text, color, fn)
		local b = new("TextButton", {
			LayoutOrder = order, Size = UDim2.new(1 / 3, -3, 1, 0),
			BackgroundColor3 = color, BackgroundTransparency = 0.12,
			Text = text, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.text,
		}, btnRow)
		corner(b, 8)
		b.MouseButton1Click:Connect(fn)
	end
	rowBtn(1, "REFRESH", C.blue, function() fetch() end)
	rowBtn(2, "HOP BEST", C.green, hop)
	rowBtn(3, "REJOIN", C.gray, rejoin)

	sectionLabel(pgServer, 5, "SERVERS (lowest ping first)")

	function rebuild()
		for _, r in ipairs(rows) do pcall(function() r:Destroy() end) end
		rows = {}
		for i = 1, math.min(#servers, 25) do
			local s = servers[i]
			local here = (s.id == game.JobId)
			local row = new("Frame", {
				LayoutOrder = 10 + i, Size = UDim2.new(1, -4, 0, 38),
				BackgroundColor3 = C.row, BackgroundTransparency = 0.2, BorderSizePixel = 0,
			}, pgServer)
			corner(row, 8)
			new("TextLabel", {
				BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -86, 1, 0),
				Font = Enum.Font.Code, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = here and C.ice or C.text,
				Text = ("#%d   %d/%d   %s ms%s"):format(
					i, s.playing, s.maxPlayers, tostring(s.ping and math.floor(s.ping) or "?"), here and "   (you)" or ""),
			}, row)
			local jb = new("TextButton", {
				Position = UDim2.new(1, -70, 0.5, -13), Size = UDim2.fromOffset(60, 26),
				BackgroundColor3 = here and C.gray or C.green, BackgroundTransparency = 0.1,
				Text = here and "HERE" or "JOIN", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.text,
			}, row)
			corner(jb, 8)
			jb.MouseButton1Click:Connect(function() joinServer(s.id, "#" .. i) end)
			rows[#rows + 1] = row
		end
	end

	log("FROST FPS console ready. tap REFRESH or type help", "#6cf0b0")
end

------------------------------------------------------------
-- AURA tab: particle auras (Angel, Flow, Heavenly). One active at a time.
-- Tap an aura button to activate it. Tap it again to remove it.
-- Compatible with the main hub's cleanup.
------------------------------------------------------------
do
	local AURA_DEFS = {
		{
			name = "ANGEL",
			id = "rbxassetid://97658130917593",
			color = Color3.fromRGB(133, 220, 255),
			desc = "Icy-blue angel wings",
		},
		{
			name = "FLOW",
			id = "rbxassetid://119913533725648",
			color = Color3.fromRGB(133, 220, 255),
			desc = "Swirling energy flow",
		},
		{
			name = "HEAVENLY",
			id = "rbxassetid://139300897520961",
			color = Color3.fromRGB(133, 220, 255),
			desc = "Golden heavenly aura",
		},
	}

	-- one shared aura engine (holds the currently active aura)
	local aura = {
		name = nil,
		particles = {},
		template = nil,
		color = Color3.fromRGB(133, 220, 255),
		charConn = nil,
	}

	local activeBtns = {}   -- name -> button, so we can reset the active highlight

	local function clearAura()
		for _, v in ipairs(aura.particles) do
			pcall(function() v:Destroy() end)
		end
		aura.particles = {}
	end

	local function tint(root, color)
		local seq = ColorSequence.new(color)
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("PointLight") then
				d.Color = color
			elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
				d.Color = seq
			end
		end
	end

	local function attachAura()
		clearAura()
		local tmpl = aura.template
		if not tmpl then return end
		local char = player.Character
		if not char then return end
		local clone = tmpl:Clone()
		tint(clone, aura.color)
		for _, group in ipairs(clone:GetChildren()) do
			local part = char:FindFirstChild(group.Name)
			if part then
				for _, obj in ipairs(group:GetChildren()) do
					obj.Parent = part
					aura.particles[#aura.particles + 1] = obj
				end
			end
		end
		clone:Destroy()
	end

	local function setAuraHighlight(name)
		for n, b in pairs(activeBtns) do
			local on = (n == name)
			b.BackgroundColor3 = on and C.ice or C.row
			b.BackgroundTransparency = on and 0.05 or 0.25
			b.TextColor3 = on and Color3.fromRGB(6, 10, 20) or C.text
		end
	end

	local function activateAura(def)
		if aura.charConn then
			aura.charConn:Disconnect()
			aura.charConn = nil
		end
		-- toggling the same aura off
		if aura.name == def.name then
			clearAura()
			aura.name = nil
			aura.template = nil
			setAuraHighlight(nil)
			setStatus("Aura removed.")
			showToast("Aura: OFF")
			return
		end
		-- load the asset (may take a moment)
		setStatus("Loading " .. def.name .. " aura...")
		aura.name = def.name
		aura.color = def.color
		setAuraHighlight(def.name)
		task.spawn(function()
			local ok, tmpl = pcall(function()
				return game:GetObjects(def.id)[1]
			end)
			if not ok or not tmpl then
				setStatus("Failed to load " .. def.name .. " aura (rbxasset may be unavailable here).")
				showToast(def.name .. " aura: failed")
				aura.name = nil
				setAuraHighlight(nil)
				return
			end
			aura.template = tmpl
			aura.charConn = track(player.CharacterAdded:Connect(function()
				task.wait(0.5)
				if aura.name then attachAura() end
			end))
			attachAura()
			setStatus(def.name .. " aura active.")
			showToast("Aura: " .. def.name)
		end)
	end

	-- color picker swatch row
	local AURA_COLORS = {
		{ "ICE",    Color3.fromRGB(133, 220, 255) },
		{ "WHITE",  Color3.new(1, 1, 1) },
		{ "PINK",   Color3.fromRGB(255, 130, 220) },
		{ "GREEN",  Color3.fromRGB(100, 255, 160) },
		{ "GOLD",   Color3.fromRGB(255, 210, 60) },
		{ "RED",    Color3.fromRGB(255, 90, 90) },
		{ "VIOLET", Color3.fromRGB(180, 130, 255) },
		{ "DARK",   Color3.fromRGB(50, 50, 80) },
	}

	new("TextLabel", {
		LayoutOrder = 1, Size = UDim2.new(1, -4, 0, 20),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.ice, Text = "SELECT AURA  (tap to toggle on/off)",
	}, pgAura)

	for i, def in ipairs(AURA_DEFS) do
		local row = new("Frame", {
			LayoutOrder = i + 1, Size = UDim2.new(1, -4, 0, 44),
			BackgroundColor3 = C.row, BackgroundTransparency = 0.25, BorderSizePixel = 0,
		}, pgAura)
		corner(row, 10)
		local icon = new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(32, 44),
			Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = C.ice,
			Text = "✨",
		}, row)
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(48, 6), Size = UDim2.new(1, -120, 0, 18),
			Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.text,
			TextXAlignment = Enum.TextXAlignment.Left, Text = def.name,
		}, row)
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(48, 24), Size = UDim2.new(1, -120, 0, 14),
			Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left, Text = def.desc,
		}, row)
		local toggleBtn = new("TextButton", {
			Position = UDim2.new(1, -78, 0.5, -14), Size = UDim2.fromOffset(68, 28),
			BackgroundColor3 = C.row, BackgroundTransparency = 0.25,
			Text = "EQUIP", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.text,
			AutoButtonColor = false,
		}, row)
		corner(toggleBtn, 8)
		activeBtns[def.name] = toggleBtn
		toggleBtn.MouseButton1Click:Connect(function()
			activateAura(def)
		end)
	end

	-- color row
	new("TextLabel", {
		LayoutOrder = #AURA_DEFS + 2, Size = UDim2.new(1, -4, 0, 18),
		BackgroundTransparency = 1, Font = Enum.Font.Code,
		TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.glitch, Text = "// AURA COLOR",
	}, pgAura)
	local colorRow = new("Frame", {
		LayoutOrder = #AURA_DEFS + 3, Size = UDim2.new(1, -4, 0, 32), BackgroundTransparency = 1,
	}, pgAura)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
	}, colorRow)
	for _, col in ipairs(AURA_COLORS) do
		local b = new("TextButton", {
			Size = UDim2.new(1 / #AURA_COLORS, -4, 1, 0),
			BackgroundColor3 = col[2], BorderSizePixel = 0,
			Text = col[1], Font = Enum.Font.GothamBold, TextSize = 7,
			TextColor3 = Color3.fromRGB(6, 10, 20), AutoButtonColor = true,
		}, colorRow)
		corner(b, 6)
		b.MouseButton1Click:Connect(function()
			aura.color = col[2]
			-- re-tint the live particles
			for _, v in ipairs(aura.particles) do
				if v:IsA("PointLight") then
					v.Color = col[2]
				elseif v:IsA("ParticleEmitter") or v:IsA("Beam") or v:IsA("Trail") then
					v.Color = ColorSequence.new(col[2])
				end
			end
			setStatus("Aura color: " .. col[1])
			showToast("Aura color: " .. col[1])
		end)
	end

	new("TextLabel", {
		LayoutOrder = #AURA_DEFS + 4, Size = UDim2.new(1, -4, 0, 32),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextSize = 11, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.dim,
		Text = "More auras will be added in the next update. Auras use game:GetObjects so your executor needs asset access.",
	}, pgAura)

	cleanups[#cleanups + 1] = function()
		if aura.charConn then aura.charConn:Disconnect() end
		clearAura()
	end
end

------------------------------------------------------------
-- FONT EDITOR (game fonts) + GREY SKY
------------------------------------------------------------
local resetFonts = nil

do
	local weak = function() return setmetatable({}, { __mode = "k" }) end
	local playerGui = player:WaitForChild("PlayerGui")
	local coreGui = nil
	pcall(function() coreGui = game:GetService("CoreGui") end)
	local fs = {
		on = false, family = nil, label = "", saved = {}, seen = weak(), busy = false, gen = 0,
		includeHub = false, includeWorld = false, includeCore = false,
		conns = {}, enforcing = false,
	}

	local function isTextObj(inst)
		local c = inst.ClassName
		return c == "TextLabel" or c == "TextButton" or c == "TextBox"
	end

	local function allowed(inst)
		if inst:IsDescendantOf(gui) then return fs.includeHub end
		if inst:IsDescendantOf(workspace) then return fs.includeWorld end
		if coreGui and inst:IsDescendantOf(coreGui) then return fs.includeCore end
		return true
	end

	-- keeps each label's own bold/italic, only swaps the family
	local function apply(inst)
		if fs.seen[inst] or not fs.family then return end
		if not isTextObj(inst) or not allowed(inst) then return end
		fs.seen[inst] = true
		local okRead, orig = pcall(getProp, inst, "FontFace")
		if not okRead or not orig then return end
		local fam = fs.family
		local okSet = pcall(function()
			inst.FontFace = Font.new(fam, orig.Weight, orig.Style)
		end)
		if okSet then
			local s = fs.saved
			s[#s + 1] = { inst, "FontFace", orig }
		end
	end

	local function alive(gen)
		return function() return fs.on and fs.gen == gen end
	end

	local function roots()
		local r = { playerGui }
		if fs.includeCore and coreGui then r[#r + 1] = coreGui end
		if fs.includeHub and not gui:IsDescendantOf(playerGui) and not (coreGui and gui:IsDescendantOf(coreGui)) then
			r[#r + 1] = gui
		end
		if fs.includeWorld then r[#r + 1] = workspace end
		return r
	end

	local function report()
		if not fs.on then return end
		local n = #fs.saved
		if n == 0 then
			setStatus("Font set, but 0 texts found. Try the world / core UI switches.")
		else
			setStatus(("Font: %s on %d texts"):format(fs.label, n))
		end
	end

	local function scan(gen, onDone)
		runHeavy(function()
			for _, root in ipairs(roots()) do
				if not (fs.on and fs.gen == gen) then return end
				sliceEach(root:GetDescendants(), apply, alive(gen))
			end
		end, onDone)
	end

	local function onAdd(inst)
		if isTextObj(inst) then pcall(apply, inst) end
	end

	-- keep one DescendantAdded watcher per active root (new UI gets the font right away)
	local function syncWatchers()
		local want = {}
		for _, root in ipairs(roots()) do want[root] = true end
		for root, conn in pairs(fs.conns) do
			if not want[root] then
				pcall(function() conn:Disconnect() end)
				fs.conns[root] = nil
			end
		end
		for root in pairs(want) do
			if not fs.conns[root] then
				fs.conns[root] = root.DescendantAdded:Connect(onAdd)
			end
		end
	end

	local function useFont(family, label)
		if fs.busy then
			setStatus("Still restoring fonts, one moment...")
			return
		end
		fs.family = family
		fs.label = label
		if not fs.on then
			fs.on = true
			fs.saved = {}
			fs.seen = weak()
			fs.gen += 1
			syncWatchers()
			setStatus("Applying font...")
			scan(fs.gen, report)
		else
			-- a font is already active: swap the family on everything already touched
			local gen = fs.gen
			runHeavy(function()
				sliceEach(fs.saved, function(rec)
					rec[1].FontFace = Font.new(fs.family, rec[3].Weight, rec[3].Style)
				end, alive(gen))
			end, report)
		end
		showToast("Font: " .. label)
	end

	-- some games re-set their fonts every so often: quietly put ours back (sliced, ~every 1.5s)
	task.spawn(function()
		while gui.Parent do
			task.wait(1.5)
			if fs.on and not fs.busy and not fs.enforcing and fs.family then
				fs.enforcing = true
				local fam, gen = fs.family, fs.gen
				sliceEach(fs.saved, function(rec)
					local inst = rec[1]
					if inst.Parent and inst.FontFace.Family ~= fam then
						inst.FontFace = Font.new(fam, rec[3].Weight, rec[3].Style)
					end
				end, alive(gen))
				fs.enforcing = false
			end
		end
	end)

	function resetFonts()
		if not fs.on then
			setStatus("Fonts are already original.")
			return
		end
		fs.on = false
		fs.gen += 1
		for root, conn in pairs(fs.conns) do
			pcall(function() conn:Disconnect() end)
			fs.conns[root] = nil
		end
		local saved = fs.saved
		fs.saved = {}
		fs.seen = weak()
		fs.family = nil
		fs.busy = true
		restoreRecords(saved, function() fs.busy = false end)
		setStatus("Fonts restored.")
		showToast("Fonts: reset")
	end

	-- scope switches (hub / world / core UI text) while a font is active
	local function syncScope()
		if not fs.on then return end
		for i = #fs.saved, 1, -1 do
			local rec = fs.saved[i]
			if not allowed(rec[1]) then
				pcall(setProp, rec[1], "FontFace", rec[3])
				fs.seen[rec[1]] = nil
				table.remove(fs.saved, i)
			end
		end
		syncWatchers()
		scan(fs.gen, report)
	end

	-- built-in fonts (anything that doesn't exist in this Roblox version is skipped)
	local builtin = {}
	for _, n in ipairs({
		"Arcade", "Fantasy", "Cartoon", "Bangers", "Creepster", "Fondamento", "FredokaOne",
		"IndieFlower", "Jura", "Kalam", "LuckiestGuy", "Nunito", "PatrickHand", "PermanentMarker",
		"SpecialElite", "Oswald", "Ubuntu", "RobotoMono", "Michroma", "SciFi", "Antique",
		"Highway", "Code", "Bodoni", "Garamond",
	}) do
		local ok, e = pcall(function() return Enum.Font[n] end)
		if ok and e then
			local ok2, f = pcall(Font.fromEnum, e)
			if ok2 and f then builtin[#builtin + 1] = { n, f.Family } end
		end
	end

	new("TextLabel", {
		LayoutOrder = 1, Size = UDim2.new(1, -4, 0, 44),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextSize = 11, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.dim,
		Text = "Changes the font of the game's text on your screen only. Pick a built-in font, or load your own .ttf / .otf file. If a game still looks unchanged, turn on the extra switches below.",
	}, pgFonts)

	local idx = 0
	local nextBtn = makeButton(pgFonts, "NEXT BUILT-IN FONT", 2, C.blue)
	nextBtn.MouseButton1Click:Connect(function()
		if #builtin == 0 then
			setStatus("No built-in fonts available here.")
			return
		end
		idx = idx % #builtin + 1
		nextBtn.Text = "FONT: " .. builtin[idx][1] .. "  (tap = next)"
		useFont(builtin[idx][2], builtin[idx][1])
	end)

	local fileBox = makeBox(pgFonts, 3, "your font file name, e.g. myfont.ttf", "", 30, false)
	local loadBtn = makeButton(pgFonts, "LOAD FONT FILE", 4, C.green)
	loadBtn.MouseButton1Click:Connect(function()
		local fileName = fileBox.Text:match("^%s*(.-)%s*$")
		if not (writefile and isfile and getcustomasset) then
			setStatus("Font files need an executor with writefile, isfile and getcustomasset.")
			return
		end
		if fileName == "" then
			setStatus("Type your font file name first.")
			return
		end
		if not isfile(fileName) then
			setStatus("File not found. Put it in your executor's workspace folder.")
			showToast("Font file not found")
			return
		end
		local ok, family = pcall(function()
			local jsonName = "frostglixht_font_" .. (fileName:gsub("[^%w_]", "_")) .. ".json"
			local json = game:GetService("HttpService"):JSONEncode({
				name = "FrostGlixhtFont",
				faces = { { name = "Regular", weight = 400, style = "normal", assetId = getcustomasset(fileName) } },
			})
			writefile(jsonName, json)
			return getcustomasset(jsonName)
		end)
		if not ok or not family then
			setStatus("Couldn't load that font file (try a plain .ttf).")
			showToast("Font load failed")
			return
		end
		useFont(family, fileName)
	end)

	makeToggle(pgFonts, "Include world text (signs/nametags)", 5, false, function(on)
		fs.includeWorld = on
		syncScope()
	end)
	makeToggle(pgFonts, "Include Roblox UI (chat/menu)", 6, false, function(on)
		fs.includeCore = on
		syncScope()
	end)
	makeToggle(pgFonts, "Also change this hub's font", 7, false, function(on)
		fs.includeHub = on
		syncScope()
	end)
	local resetBtn = makeButton(pgFonts, "RESET FONTS", 8, C.red)
	resetBtn.MouseButton1Click:Connect(resetFonts)


end

------------------------------------------------------------
-- MORE page: theme, floating chip, smoothness, hub key, credits
------------------------------------------------------------
local hudOn, hudLbl, hudBox = false, nil, nil

local function executorName()
	local ok, n = pcall(function() return identifyexecutor and identifyexecutor() end)
	if ok and n then return tostring(n) end
	ok, n = pcall(function() return getexecutorname and getexecutorname() end)
	if ok and n then return tostring(n) end
	return "unknown executor"
end

do
	local skipRecolor = {}
	local THEMES = {
		{ "CYBER", Color3.fromRGB(0, 220, 255), Color3.fromRGB(255, 60, 160) },
		{ "ICE", Color3.fromRGB(150, 225, 255), Color3.fromRGB(90, 140, 255) },
		{ "TOXIC", Color3.fromRGB(120, 255, 90), Color3.fromRGB(255, 230, 60) },
		{ "BLOOD", Color3.fromRGB(255, 80, 100), Color3.fromRGB(255, 170, 60) },
		{ "GOLD", Color3.fromRGB(255, 205, 90), Color3.fromRGB(255, 110, 60) },
		{ "VIOLET", Color3.fromRGB(175, 135, 255), Color3.fromRGB(80, 230, 255) },
	}
	-- recolor everything that uses either accent, in one pass
	local function applyTheme(newI, newG)
		local oldI, oldG = C.ice, C.glitch
		if newI == oldI and newG == oldG then return end
		C.ice, C.glitch = newI, newG
		local function swap(c)
			if c == oldI then return newI end
			if c == oldG then return newG end
			return nil
		end
		for _, d in ipairs(gui:GetDescendants()) do
			if not skipRecolor[d] then
				local cls = d.ClassName
				if cls == "TextLabel" or cls == "TextButton" or cls == "TextBox" then
					local n = swap(d.TextColor3)
					if n then d.TextColor3 = n end
					n = swap(d.BackgroundColor3)
					if n then d.BackgroundColor3 = n end
				elseif cls == "Frame" or cls == "ImageLabel" then
					local n = swap(d.BackgroundColor3)
					if n then d.BackgroundColor3 = n end
				elseif cls == "UIStroke" then
					local n = swap(d.Color)
					if n then d.Color = n end
				elseif cls == "ScrollingFrame" then
					local n = swap(d.ScrollBarImageColor3)
					if n then d.ScrollBarImageColor3 = n end
				end
			end
		end
		for _, h in ipairs(themeHooks) do pcall(h) end
		refreshModeUI(boost.mode)
	end

	sectionLabel(pgMore, 1, "THEME")
	local swatchRow = new("Frame", {
		LayoutOrder = 2, Size = UDim2.new(1, -4, 0, 30), BackgroundTransparency = 1,
	}, pgMore)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, swatchRow)
	for i, th in ipairs(THEMES) do
		local b = new("TextButton", {
			LayoutOrder = i, Size = UDim2.new(1 / #THEMES, -5, 1, 0),
			BackgroundColor3 = th[2], BorderSizePixel = 0,
			Text = th[1], Font = Enum.Font.GothamBold, TextSize = 8,
			TextColor3 = Color3.fromRGB(6, 10, 20),
		}, swatchRow)
		corner(b, 6)
		new("UIStroke", { Thickness = 1.5, Color = th[3] }, b)
		skipRecolor[b] = true
		for _, d in ipairs(b:GetChildren()) do skipRecolor[d] = true end
		b.MouseButton1Click:Connect(function()
			applyTheme(th[2], th[3])
			setStatus("Theme: " .. th[1])
			showToast("Theme: " .. th[1])
		end)
	end

	sectionLabel(pgMore, 10, "DISPLAY")
	-- floating FPS / PING / memory chip (stays on screen while the hub is closed)
	makeToggle(pgMore, "Floating FPS/PING chip", 11, false, function(v)
		hudOn = v
		if v and not hudBox then
			hudBox = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(230, 24), Position = UDim2.new(1, -130, 0, 80),
				BackgroundColor3 = C.dark, BackgroundTransparency = 0.25,
				BorderSizePixel = 0, ZIndex = 50, Visible = false,
			}, gui)
			corner(hudBox, 12)
			new("UIStroke", { Thickness = 1, Color = C.ice, Transparency = 0.5 }, hudBox)
			hudLbl = new("TextLabel", {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.text,
				Text = "FPS --  |  -- ms", ZIndex = 51,
			}, hudBox)
			makeDraggable(hudBox, hudBox, function() return 230, 24 end)
		end
		if hudBox then hudBox.Visible = v end
		showToast(v and "Floating Chip: ON" or "Floating Chip: OFF")
	end)
	makeToggle(pgMore, "Show FPS / PING in the header", 12, true, function(v)
		fpsLabel.Visible = v
		pingLabel.Visible = v
	end)

	sectionLabel(pgMore, 20, "PERFORMANCE")
	local presets = { { "SMOOTH", 0.001 }, { "BALANCED", 0.0015 }, { "FAST", 0.004 } }
	local pIdx = 2
	local sBtn = makeButton(pgMore, "SMOOTHNESS: BALANCED", 21, C.blue)
	sBtn.MouseButton1Click:Connect(function()
		pIdx = pIdx % #presets + 1
		SLICE_BUDGET = presets[pIdx][2]
		sBtn.Text = "SMOOTHNESS: " .. presets[pIdx][1]
		setStatus("Big jobs now use " .. presets[pIdx][1] .. " pacing.")
		showToast("Smoothness: " .. presets[pIdx][1])
	end)
	new("TextLabel", {
		LayoutOrder = 22, Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.dim,
		Text = "SMOOTH is easiest on a weak phone (big jobs finish slower). FAST finishes sooner but can hitch.",
	}, pgMore)

	sectionLabel(pgMore, 30, "CONTROLS")
	local HUB_KEYS = {
		{ "RightShift", Enum.KeyCode.RightShift }, { "RightCtrl", Enum.KeyCode.RightControl },
		{ "Insert", Enum.KeyCode.Insert }, { "Home", Enum.KeyCode.Home }, { "K", Enum.KeyCode.K },
	}
	local keyIdx = 1
	local keyBtn = makeButton(pgMore, "HUB KEY (PC): RightShift", 31, C.gray)
	keyBtn.MouseButton1Click:Connect(function()
		keyIdx = keyIdx % #HUB_KEYS + 1
		hubKey.code = HUB_KEYS[keyIdx][2]
		keyBtn.Text = "HUB KEY (PC): " .. HUB_KEYS[keyIdx][1]
		showToast("Hub key: " .. HUB_KEYS[keyIdx][1])
	end)
	local replay = makeButton(pgMore, "REPLAY INTRO", 32, C.gray)
	replay.MouseButton1Click:Connect(function()
		playIntro(function() end)
	end)

	sectionLabel(pgMore, 40, "ABOUT")
	new("TextLabel", {
		LayoutOrder = 41, Size = UDim2.new(1, -4, 0, 16), BackgroundTransparency = 1,
		Font = Enum.Font.Code, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.dim, Text = "FROST FPS  |  " .. executorName(),
	}, pgMore)
	local credits = new("Frame", {
		LayoutOrder = 42, Size = UDim2.new(1, -4, 0, 64),
		BackgroundColor3 = C.row, BackgroundTransparency = 0.3, BorderSizePixel = 0,
	}, pgMore)
	corner(credits, 8)
	new("UIStroke", { Thickness = 1, Color = C.ice, Transparency = 0.5 }, credits)
	new("TextLabel", {
		Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11,
		TextColor3 = C.dim, Text = "CREDITS",
	}, credits)
	new("TextLabel", {
		Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 24,
		TextColor3 = C.ice, Text = "FROST",
	}, credits)
end

------------------------------------------------------------
-- FPS + ping chips (one cheap loop, twice a second)
------------------------------------------------------------
do
	local function readDataPing() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end
	local function readPerfPing() return Stats.PerformanceStats.Ping:GetValue() end
	local function readNetPing() return player:GetNetworkPing() * 2000 end
	local function getPing()
		local ok, v = pcall(readDataPing)
		if ok and type(v) == "number" and v > 0 then return v end
		ok, v = pcall(readPerfPing)
		if ok and type(v) == "number" and v > 0 then return v end
		ok, v = pcall(readNetPing)
		if ok and type(v) == "number" and v > 0 then return v end
		return nil
	end

	local GOOD, OKAY, BAD = Color3.fromRGB(120, 255, 160), Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 100, 110)
	local function colorFor(value, good, ok, lowerBetter)
		if lowerBetter then
			if value <= good then return GOOD end
			if value <= ok then return OKAY end
			return BAD
		end
		if value >= good then return GOOD end
		if value >= ok then return OKAY end
		return BAD
	end

	local frames, lastCount, lastLed = 0, os.clock(), nil
	track(RunService.Heartbeat:Connect(function()
		frames += 1
		local now = os.clock()
		if now - lastCount < 0.5 then return end
		local fps = math.floor(frames / (now - lastCount) + 0.5)
		frames, lastCount = 0, now
		for _, w in ipairs(fpsWatchers) do pcall(w, fps) end

		-- status light: grey = idle, cyan = BOOST, green = POTATO, magenta = ULTRA
		local ledCol = C.gray
		if boost.mode == 1 then ledCol = C.ice elseif boost.mode == 2 then ledCol = C.green elseif boost.mode == 3 then ledCol = C.glitch elseif boost.mode == 4 then ledCol = C.red end
		if ledCol ~= lastLed then
			lastLed = ledCol
			ledDot.BackgroundColor3 = ledCol
		end

		local showChips = main.Visible and fpsLabel.Visible
		if not (showChips or hudOn) then return end
		local ping = getPing()
		local pingTxt, pingCol = "-- ms", C.text
		if ping then
			ping = math.floor(ping + 0.5)
			pingTxt = ping .. " ms"
			pingCol = colorFor(ping, 80, 150, true)
		end
		local fpsCol = colorFor(fps, 50, 30, false)
		if showChips then
			fpsLabel.Text = fps .. " fps"
			fpsLabel.TextColor3 = fpsCol
			pingLabel.Text = pingTxt
			pingLabel.TextColor3 = pingCol
		end
		if hudOn and hudLbl then
			local okm, mem = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
			local memTxt = (okm and type(mem) == "number") and ("  |  " .. math.floor(mem + 0.5) .. " MB") or ""
			hudLbl.Text = "FPS " .. fps .. "  |  " .. pingTxt .. memTxt
			hudLbl.TextColor3 = fpsCol
		end
	end))
end

------------------------------------------------------------
-- Cleanup (runs automatically if the script is executed again)
------------------------------------------------------------
do
	local ok, env = pcall(function() return getgenv() end)
	if ok and type(env) == "table" then
		env.FrostFpsCleanup = function()
			pcall(function() if resetFonts then resetFonts() end end)
			pcall(function()
				for p in pairs(hideSet) do setPlayerHidden(p, false) end
			end)
			for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
			for _, f in ipairs(cleanups) do pcall(f) end
			pcall(function() gui:Destroy() end)
		end
	end
end

------------------------------------------------------------
-- Intro: a clean light-line reveal. Tap to skip.
------------------------------------------------------------
function playIntro(onDone)
	if not CONFIG.ShowIntro then
		onDone()
		return
	end
	introActive = true
	local done = false

	local overlay = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(2, 4, 10),
		BorderSizePixel = 0,
		Active = true,
		ClipsDescendants = true,
		ZIndex = 100,
	}, gui)
	new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(8, 14, 30), Color3.fromRGB(2, 3, 8)),
		Rotation = 90,
	}, overlay)

	local function lineLabel(text, y, font, size, color)
		return new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, y + 8),
			Size = UDim2.fromOffset(460, size + 8),
			BackgroundTransparency = 1,
			Font = font,
			TextSize = size,
			Text = text,
			TextColor3 = color,
			TextTransparency = 1,
			ZIndex = 105,
		}, overlay)
	end
	local title = lineLabel("FROST FPS", -22, Enum.Font.GothamBlack, 38, Color3.new(1, 1, 1))
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, C.ice),
		}),
		Rotation = 0,
	}, title)
	local sub1 = lineLabel("OPTIMIZED BY FROST", 28, Enum.Font.Code, 13, C.ice)
	local sub2 = lineLabel("MADE BY FROST", 48, Enum.Font.Code, 11, C.glitch)

	-- the light line (grows from the middle)
	local line = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.fromOffset(0, 2),
		BackgroundColor3 = C.ice,
		BorderSizePixel = 0,
		ZIndex = 104,
	}, overlay)
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, line)

	-- thin progress bar
	local barBack = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 80),
		Size = UDim2.fromOffset(180, 3),
		BackgroundColor3 = Color3.fromRGB(22, 30, 52),
		BorderSizePixel = 0,
		ZIndex = 104,
	}, overlay)
	corner(barBack, 2)
	local barFill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.ice,
		BorderSizePixel = 0,
		ZIndex = 105,
	}, barBack)
	corner(barFill, 2)

	local skip = new("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 110,
	}, overlay)

	local function finish()
		if done then return end
		done = true
		local fo = TweenInfo.new(0.35)
		for _, d in ipairs(overlay:GetDescendants()) do
			if d:IsA("TextLabel") then
				TweenService:Create(d, fo, { TextTransparency = 1 }):Play()
			elseif d:IsA("Frame") then
				TweenService:Create(d, fo, { BackgroundTransparency = 1 }):Play()
			end
		end
		TweenService:Create(overlay, fo, { BackgroundTransparency = 1 }):Play()
		task.delay(0.12, function()
			introActive = false
			onDone()
		end)
		task.delay(0.45, function() overlay:Destroy() end)
	end
	skip.Activated:Connect(finish)
	task.delay(3.6, finish)   -- safety: the intro can never get stuck

	-- timeline
	TweenService:Create(line, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(300, 2),
	}):Play()
	task.delay(0.3, function()
		if done then return end
		TweenService:Create(title, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			TextTransparency = 0, Position = UDim2.new(0.5, 0, 0.5, -22),
		}):Play()
	end)
	task.delay(0.75, function()
		if done then return end
		TweenService:Create(sub1, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			TextTransparency = 0.05, Position = UDim2.new(0.5, 0, 0.5, 28),
		}):Play()
	end)
	task.delay(1.0, function()
		if done then return end
		TweenService:Create(sub2, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			TextTransparency = 0.1, Position = UDim2.new(0.5, 0, 0.5, 48),
		}):Play()
	end)
	TweenService:Create(barFill, TweenInfo.new(1.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
		Size = UDim2.fromScale(1, 1),
	}):Play()
	task.delay(2.3, finish)
end

------------------------------------------------------------
-- Start
------------------------------------------------------------
selectTab(1)
playIntro(function()
	openHub()
	showToast("Welcome to FROST FPS")
end)
