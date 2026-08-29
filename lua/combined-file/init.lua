local M = {}

local defaults = {
	keys = {
		check = "<Leader>gc",
		generate = "<Leader>gg",
	},
}

local function bundle_files()
	local current_file = vim.api.nvim_buf_get_name(0)
	if vim.fn.fnamemodify(current_file, ":e") ~= "cpp" then
		vim.notify("Active buffer must be a .cpp file", vim.log.levels.WARN)
		return
	end

	-- 1. Cat all local .h files + current .cpp file
	-- 2. Strip lines matching #include "..." for local headers
	-- 3. Output to submit.cpp
	local cmd = string.format([[cat *.h "%s" 2>/dev/null | sed -E '/#include *"[^"]+"/d' > submit.cpp]], current_file)

	vim.fn.jobstart({ "sh", "-c", cmd }, {
		on_exit = function(_, exit_code)
			if exit_code == 0 then
				vim.notify("Generated submit.cpp", vim.log.levels.INFO)
			else
				vim.notify("Failed to generate submit.cpp", vim.log.levels.ERROR)
			end
		end,
	})
end

function M.setup(opts)
	opts = vim.tbl_deep_extend("force", defaults, opts or {})

	vim.keymap.set("n", opts.keys.check, function()
		print("file generator is working!!!")
	end, { desc = "Check File Generator status" })

	vim.keymap.set("n", opts.keys.generate, bundle_files, { desc = "Bundle into submit.cpp" })
end

return M
