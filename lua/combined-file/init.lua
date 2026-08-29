local M = {}

local defaults = {
	keys = {
		check = "<Leader>gc",
		generate = "<Leader>gg",
	},
}

local function bundle_files()
	-- Get current buffer's full file path and stem (e.g., "hey")
	local current_file = vim.api.nvim_buf_get_name(0)
	if current_file == "" then
		vim.notify("Buffer has no file name", vim.log.levels.ERROR)
		return
	end

	local stem = vim.fn.fnamemodify(current_file, ":r")

	-- Determine target files (supports invoking from either .cpp or .h)
	local header_file = stem .. ".h"
	local source_file = stem .. ".cpp"

	local files_to_cat = {}
	if vim.fn.filereadable(header_file) == 1 then
		table.insert(files_to_cat, header_file)
	end
	if vim.fn.filereadable(source_file) == 1 then
		table.insert(files_to_cat, source_file)
	end

	if #files_to_cat == 0 then
		vim.notify("No matching source/header files found for " .. stem, vim.log.levels.WARN)
		return
	end

	-- Extract basic header file name for regex matching (e.g., "helper.h")
	local header_name = vim.fn.fnamemodify(header_file, ":t")

	-- Construct command: cat header.h source.cpp | sed '/#include "header.h"/d' > submit.cpp
	local input_files_str = table.concat(files_to_cat, " ")
	local cmd = string.format("cat %s | sed '/#include \"%s\"/d' > submit.cpp", input_files_str, header_name)

	vim.fn.jobstart({ "sh", "-c", cmd }, {
		on_exit = function(_, exit_code)
			if exit_code == 0 then
				vim.notify("Successfully generated submit.cpp", vim.log.levels.INFO)
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

	vim.keymap.set("n", opts.keys.generate, bundle_files, { desc = "Bundle C++ files into submit.cpp" })
end

return M
