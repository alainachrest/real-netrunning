-- The cyberdeck window (CET ImGui). CET 1.38+ only gives ImGui keyboard and mouse
-- input while the CET overlay is open, so the deck is used with the overlay open.

local Shell = require("modules/shell")

local Terminal = {
	visible = true,
	input = "",
	lastLineCount = 0,
	refocus = true,
}

local colors = {
	out  = { 0.85, 0.85, 0.80, 1.0 },
	cmd  = { 0.35, 0.95, 0.90, 1.0 },
	ok   = { 0.45, 0.95, 0.45, 1.0 },
	warn = { 1.00, 0.80, 0.30, 1.0 },
	err  = { 1.00, 0.35, 0.35, 1.0 },
}

function Terminal.draw()
	if not Terminal.visible then return end

	ImGui.SetNextWindowSize(720, 460, ImGuiCond.FirstUseEver)
	-- With a close button, CET's Begin returns (open, shouldDraw).
	local open, shouldDraw = ImGui.Begin("Real Netrunning - Cyberdeck", true)
	if open == false then
		Terminal.visible = false
	end
	if shouldDraw == false then
		ImGui.End()
		return
	end

	-- trace bar while connected
	if Shell.connected then
		ImGui.ProgressBar(Shell.trace / 100, -1, 0, string.format("Trace %d%%", math.floor(Shell.trace)))
	end

	local footer = ImGui.GetFrameHeightWithSpacing()
	ImGui.BeginChild("rn_output", 0, -footer, true)
	for _, line in ipairs(Shell.lines) do
		local c = colors[line.kind] or colors.out
		ImGui.PushStyleColor(ImGuiCol.Text, c[1], c[2], c[3], c[4])
		ImGui.TextWrapped(line.text)
		ImGui.PopStyleColor(1)
	end
	if #Shell.lines ~= Terminal.lastLineCount then
		ImGui.SetScrollHereY(1.0)
		Terminal.lastLineCount = #Shell.lines
	end
	ImGui.EndChild()

	ImGui.Text(Shell.prompt())
	ImGui.SameLine()
	ImGui.PushItemWidth(-1)
	if Terminal.refocus then
		ImGui.SetKeyboardFocusHere(0)
		Terminal.refocus = false
	end
	local text, submitted = ImGui.InputText("##rn_input", Terminal.input, 256, ImGuiInputTextFlags.EnterReturnsTrue)
	ImGui.PopItemWidth()
	Terminal.input = text or ""
	if submitted then
		Shell.run(Terminal.input)
		Terminal.input = ""
		Terminal.refocus = true
	end

	ImGui.End()
end

return Terminal
