-- SaveInstance Exporter (Xeno client prototype)
--
-- Usage:
--   1. Open your own experience in a Xeno client session.
--   2. Paste/run this file with Xeno's script runner.
--   3. Wait for the client object list to finish scanning.
--   4. Search the list and check the Model, Folder, Part, or ModuleScript rows
--      you want to export. Selecting a Model or Folder includes its descendants.
--   5. Press "Export .rbxm". USSI writes the file to Xeno's workspace folder.
--   6. Check the actual extension and open the file in Roblox Studio to validate it.
--
-- This is a client-side snapshot of the selected instances only. It does not
-- access server-only data. Xeno and USSI must be available in the executor.
-- The export button runs Xeno.saveinstance(options); merely loading this UI does
-- not export anything. The script does not treat a function return as proof that
-- a valid file was produced. Confirm the file in Xeno's workspace and open it in
-- Studio. USSI has no cancellation API, so closing this UI does not stop a save.

local ENV = (type(getgenv) == "function" and getgenv()) or _G
local XENO = ENV
if type(XENO) ~= "table" or type(XENO.saveinstance) ~= "function" then
	XENO = ENV and ENV.Xeno
end

if type(XENO) ~= "table" or type(XENO.saveinstance) ~= "function" then
	warn("SaveInstance Exporter: Xeno.saveinstance was not found. Run this through Xeno.")
	return
end

local GUI_NAME = "SaveInstanceExporterUI"
local MAX_SCAN_NODES = 30000
local MAX_ITEMS = 5000
local MAX_VISIBLE_ROWS = 250

-- Scan only service roots expected on a client. ServerStorage and
-- ServerScriptService are deliberately excluded.
local SERVICE_ROOTS = {
	"Workspace",
	"Lighting",
	"ReplicatedFirst",
	"ReplicatedStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"Teams",
	"SoundService",
	"MaterialService",
	"Chat",
	"TextChatService",
}

local function getGuiParent()
	if type(XENO.gethui) == "function" then
		local ok, result = pcall(XENO.gethui)
		if ok and result then
			return result
		end
	end

	local ok, playerGui = pcall(function()
		return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	end)
	if ok then
		return playerGui
	end
	return nil
end

local GUI_PARENT = getGuiParent()
if not GUI_PARENT then
	warn("SaveInstance Exporter: Could not find a client GUI parent.")
	return
end

local previousGui = GUI_PARENT:FindFirstChild(GUI_NAME)
if previousGui then
	previousGui:Destroy()
end

local function create(className, properties, parent)
	local object = Instance.new(className)
	for property, value in pairs(properties or {}) do
		object[property] = value
	end
	object.Parent = parent
	return object
end

local function addCorner(parent, radius)
	create("UICorner", { CornerRadius = UDim.new(0, radius or 6) }, parent)
end

local GUI = create("ScreenGui", {
	Name = GUI_NAME,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, GUI_PARENT)

local PANEL = create("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 570, 0, 470),
	BackgroundColor3 = Color3.fromRGB(25, 28, 34),
	BorderSizePixel = 0,
}, GUI)
addCorner(PANEL, 10)

create("UIStroke", {
	Color = Color3.fromRGB(74, 83, 99),
	Thickness = 1,
}, PANEL)

create("TextLabel", {
	Name = "Title",
	Position = UDim2.new(0, 16, 0, 10),
	Size = UDim2.new(1, -72, 0, 28),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Selective Save · Client",
	TextColor3 = Color3.fromRGB(241, 244, 249),
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
}, PANEL)

local CLOSE = create("TextButton", {
	Name = "Close",
	Position = UDim2.new(1, -42, 0, 8),
	Size = UDim2.new(0, 30, 0, 30),
	BackgroundColor3 = Color3.fromRGB(54, 60, 71),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "×",
	TextColor3 = Color3.fromRGB(235, 239, 245),
	TextSize = 20,
}, PANEL)
addCorner(CLOSE, 6)
CLOSE.Activated:Connect(function()
	GUI:Destroy()
end)

create("TextLabel", {
	Name = "Help",
	Position = UDim2.new(0, 16, 0, 40),
	Size = UDim2.new(1, -32, 0, 34),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Pilih objek dari daftar client. Model/Folder membawa seluruh turunannya.",
	TextColor3 = Color3.fromRGB(174, 183, 197),
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
}, PANEL)

local SEARCH = create("TextBox", {
	Name = "Search",
	Position = UDim2.new(0, 16, 0, 80),
	Size = UDim2.new(1, -32, 0, 32),
	BackgroundColor3 = Color3.fromRGB(38, 43, 52),
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = Enum.Font.Gotham,
	PlaceholderText = "Cari nama, class, atau path...",
	PlaceholderColor3 = Color3.fromRGB(135, 145, 160),
	Text = "",
	TextColor3 = Color3.fromRGB(235, 239, 245),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
}, PANEL)
addCorner(SEARCH, 6)

local TOOLBAR = create("Frame", {
	Name = "Toolbar",
	Position = UDim2.new(0, 16, 0, 120),
	Size = UDim2.new(1, -32, 0, 32),
	BackgroundTransparency = 1,
}, PANEL)

local COUNT = create("TextLabel", {
	Name = "Count",
	Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(1, -210, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Belum dipindai",
	TextColor3 = Color3.fromRGB(174, 183, 197),
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
}, TOOLBAR)

local function toolbarButton(name, text, x, width)
	local button = create("TextButton", {
		Name = name,
		Position = UDim2.new(1, x, 0, 0),
		Size = UDim2.new(0, width, 1, 0),
		BackgroundColor3 = Color3.fromRGB(54, 64, 79),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextColor3 = Color3.fromRGB(235, 239, 245),
		TextSize = 11,
	}, TOOLBAR)
	addCorner(button, 5)
	return button
end

local REFRESH = toolbarButton("Refresh", "Refresh", -200, 88)
local SELECT_VISIBLE = toolbarButton("SelectVisible", "Pilih tampil", -104, 96)

local LIST = create("ScrollingFrame", {
	Name = "ObjectList",
	Position = UDim2.new(0, 16, 0, 160),
	Size = UDim2.new(1, -32, 0, 250),
	BackgroundColor3 = Color3.fromRGB(32, 36, 44),
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = Color3.fromRGB(105, 119, 139),
}, PANEL)
addCorner(LIST, 6)

local LIST_LAYOUT = create("UIListLayout", {
	Padding = UDim.new(0, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, LIST)
LIST_LAYOUT:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	LIST.CanvasSize = UDim2.new(0, 0, 0, LIST_LAYOUT.AbsoluteContentSize.Y + 6)
end)

local STATUS = create("TextLabel", {
	Name = "Status",
	Position = UDim2.new(0, 16, 0, 418),
	Size = UDim2.new(1, -32, 0, 22),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Siap. Tekan Refresh untuk memindai objek client.",
	TextColor3 = Color3.fromRGB(174, 183, 197),
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, PANEL)

local EXPORT = create("TextButton", {
	Name = "Export",
	Position = UDim2.new(0, 16, 1, -42),
	Size = UDim2.new(1, -32, 0, 32),
	BackgroundColor3 = Color3.fromRGB(53, 125, 94),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "Export .rbxm",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 13,
}, PANEL)
addCorner(EXPORT, 6)

local OBJECTS = {}
local SELECTED = {}
local SCANNING = false
local EXPORTING = false
local RENDER_TOKEN = 0

local function objectPath(instance)
	local ok, value = pcall(function()
		return instance:GetFullName()
	end)
	return ok and value or instance.Name
end

local function isExportable(instance)
	return instance:IsA("Model")
		or instance:IsA("Folder")
		or instance:IsA("BasePart")
		or instance:IsA("ModuleScript")
end

local function clearRows()
	for _, child in ipairs(LIST:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function filteredObjects()
	local query = string.lower(SEARCH.Text or "")
	local matches = {}
	for _, instance in ipairs(OBJECTS) do
		local className = instance.ClassName
		local path = objectPath(instance)
		local haystack = string.lower(className .. " " .. path)
		if query == "" or string.find(haystack, query, 1, true) then
			matches[#matches + 1] = instance
		end
	end
	return matches
end

local function updateCount(visibleMatches)
	local selectedCount = 0
	for instance in pairs(SELECTED) do
		if SELECTED[instance] then
			selectedCount += 1
		end
	end
	COUNT.Text = string.format("%d objek · %d dipilih", #OBJECTS, selectedCount)
	if visibleMatches and #visibleMatches > MAX_VISIBLE_ROWS then
		STATUS.Text = string.format(
			"Menampilkan %d dari %d hasil; persempit pencarian untuk objek lain.",
			MAX_VISIBLE_ROWS,
			#visibleMatches
		)
	end
end

local function renderList()
	RENDER_TOKEN += 1
	local token = RENDER_TOKEN
	clearRows()

	local matches = filteredObjects()
	local amount = math.min(#matches, MAX_VISIBLE_ROWS)
	for index = 1, amount do
		if token ~= RENDER_TOKEN or not GUI.Parent then
			return
		end
		local instance = matches[index]
		local isSelected = SELECTED[instance] == true
		local row = create("TextButton", {
			Name = "ObjectRow",
			LayoutOrder = index,
			Size = UDim2.new(1, -8, 0, 27),
			Position = UDim2.new(0, 4, 0, 0),
			BackgroundColor3 = isSelected and Color3.fromRGB(44, 76, 67) or Color3.fromRGB(40, 45, 54),
			BorderSizePixel = 0,
			Font = Enum.Font.Gotham,
			Text = string.format("%s  [%s]  %s", isSelected and "[x]" or "[ ]", instance.ClassName, objectPath(instance)),
			TextColor3 = Color3.fromRGB(225, 231, 239),
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, LIST)
		row.Activated:Connect(function()
			if SELECTED[instance] then
				SELECTED[instance] = nil
			else
				SELECTED[instance] = true
			end
			updateCount()
			renderList()
		end)
		if index % 50 == 0 then
			task.wait()
		end
	end

	LIST.CanvasPosition = Vector2.new(0, 0)
	updateCount(matches)
	if #matches == 0 then
		STATUS.Text = "Tidak ada objek yang cocok dengan pencarian."
	elseif #matches <= MAX_VISIBLE_ROWS and not SCANNING then
		STATUS.Text = "Daftar siap. Pilih objek lalu tekan Export .rbxm."
	end
end

local function refreshObjects()
	if SCANNING or EXPORTING then
		return
	end

	SCANNING = true
	REFRESH.Active = false
	REFRESH.AutoButtonColor = false
	STATUS.Text = "Memindai service dan objek client..."
	COUNT.Text = "Memindai..."
	OBJECTS = {}
	SELECTED = {}
	clearRows()

	task.spawn(function()
		local seen = {}
		local stack = {}
		for _, serviceName in ipairs(SERVICE_ROOTS) do
			local ok, service = pcall(function()
				return game:GetService(serviceName)
			end)
			if ok and service then
				local childrenOk, children = pcall(function()
					return service:GetChildren()
				end)
				if childrenOk then
					for _, child in ipairs(children) do
						stack[#stack + 1] = child
					end
				end
			end
		end

		local scanned = 0
		local truncated = false
		while #stack > 0 do
			local instance = table.remove(stack)
			if instance and not seen[instance] then
				seen[instance] = true
				scanned += 1

				local ok, exportable = pcall(isExportable, instance)
				if ok and exportable then
					OBJECTS[#OBJECTS + 1] = instance
					if #OBJECTS >= MAX_ITEMS then
						truncated = true
						break
					end
				end

				local childrenOk, children = pcall(function()
					return instance:GetChildren()
				end)
				if childrenOk then
					for _, child in ipairs(children) do
						stack[#stack + 1] = child
					end
				end

				if scanned >= MAX_SCAN_NODES then
					truncated = true
					break
				end
				if scanned % 100 == 0 then
					STATUS.Text = string.format("Memindai... %d instance diperiksa", scanned)
					task.wait()
				end
			end
		end

		table.sort(OBJECTS, function(a, b)
			return string.lower(objectPath(a)) < string.lower(objectPath(b))
		end)
		SCANNING = false
		REFRESH.Active = true
		REFRESH.AutoButtonColor = true
		renderList()
		if truncated then
			STATUS.Text = string.format(
				"Pemindaian dibatasi (%d objek maksimum); gunakan pencarian untuk mempersempit daftar.",
			#OBJECTS
			)
		end
	end)
end

local function selectedRoots()
	local roots = {}
	for _, instance in ipairs(OBJECTS) do
		if SELECTED[instance] and instance.Parent then
			local hasSelectedAncestor = false
			local ancestor = instance.Parent
			while ancestor and ancestor ~= game do
				if SELECTED[ancestor] then
					hasSelectedAncestor = true
					break
				end
				ancestor = ancestor.Parent
			end
			if not hasSelectedAncestor then
				roots[#roots + 1] = instance
			end
		end
	end
	return roots
end

SEARCH:GetPropertyChangedSignal("Text"):Connect(function()
	if not SCANNING then
		renderList()
	end
end)

REFRESH.Activated:Connect(refreshObjects)

SELECT_VISIBLE.Activated:Connect(function()
	if SCANNING or EXPORTING then
		return
	end
	local matches = filteredObjects()
	local amount = math.min(#matches, MAX_VISIBLE_ROWS)
	for index = 1, amount do
		SELECTED[matches[index]] = true
	end
	updateCount(matches)
	renderList()
end)

EXPORT.Activated:Connect(function()
	if SCANNING or EXPORTING then
		return
	end

	local roots = selectedRoots()
	if #roots == 0 then
		STATUS.Text = "Pilih minimal satu objek sebelum export."
		return
	end

	EXPORTING = true
	EXPORT.Active = false
	EXPORT.AutoButtonColor = false
	REFRESH.Active = false
	SELECT_VISIBLE.Active = false
	STATUS.Text = string.format("Memulai USSI untuk %d root terpilih...", #roots)

	local timestamp = os.date("!%Y%m%d_%H%M%S")
	local basePath = "XenoSelectiveSave_" .. timestamp -- deliberately no extension

	task.spawn(function()
		local ok, err = pcall(function()
			XENO.saveinstance({
				mode = "__selective_export__", -- invalid USSI mode: only ExtraInstances
				ExtraInstances = roots,
				IsModel = true,
				Binary = true,
				ShowStatus = true,
				FilePath = basePath,
			})
		end)

		EXPORTING = false
		EXPORT.Active = true
		EXPORT.AutoButtonColor = true
		REFRESH.Active = true
		SELECT_VISIBLE.Active = true

		if ok then
			STATUS.Text = "Xeno.saveinstance kembali. File belum diverifikasi; cek workspace Xeno dan buka di Studio."
			warn("SaveInstance Exporter: saveinstance kembali; periksa file " .. basePath .. " (.rbxm atau fallback XML) dan validasi dengan Roblox Studio.")
		else
			STATUS.Text = "Export berhenti dengan error; cek console Xeno."
			warn("SaveInstance Exporter: Xeno.saveinstance error: " .. tostring(err))
		end
	end)
end)

refreshObjects()
