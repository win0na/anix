local ttt = require("ttt")
local editor = require("ttt.editor")
local sys = require("ttt.system")

local function handoff()
	local path = editor.file_path()
	if not path or path == "" then
		ttt.notify("no file in the active tab", "warn")
		return
	end

	local pos = editor.cursor() or { line = 1, col = 1 }
	sys.exec_async(
		"ttt-handoff",
		{ "vscode", path, tostring(pos.line), tostring(pos.col) },
		function(result)
			if result.exit_code ~= 0 then
				local message = result.stderr
				if not message or message == "" then
					message = "exit " .. result.exit_code
				end
				ttt.notify("handoff failed: " .. message, "error")
			end
		end
	)
end

ttt.register({
	commands = {
		{
			id = "handoff.vscode",
			title = "Open in VS Code (tunnel)",
			handler = function()
				handoff()
			end,
		},
	},
	keybindings = {
		{ key = "ctrl+k v", command = "handoff.vscode" },
	},
})
