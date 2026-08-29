local M = {}

local defaults = {
	keys = {
		check = "<Leader>cpc",
		generate = "<Leader>cpg",
		build = "<Leader>cpb",
		run = "<Leader>cpr",
	},
}

local function run_command(cmd, success_msg, fail_msg, term)
	vim.fn.jobstart({ "sh", "-c", cmd }, {
		on_exit = function(_, exit_code)
			if exit_code == 0 then
				vim.notify(success_msg, vim.log.levels.INFO)
			else
				vim.notify(fail_msg, vim.log.levels.ERROR)
			end
		end,
		term = term,
	})
end

local function get_current_cpp_file()
	local current_file = vim.api.nvim_buf_get_name(0)
	if not current_file then
		vim.notify("Can't get current cpp file", vim.log.levels.WARN)
		return
	end
	if vim.fn.fnamemodify(current_file, ":e") ~= "cpp" then
		vim.notify("Active buffer must be a .cpp file", vim.log.levels.WARN)
		return
	end
	return current_file
end

local function bundle_files()
	local current_file = get_current_cpp_file()
	if not current_file then
		return
	end
	local cmd = string.format([[cat *.h "%s" 2>/dev/null | sed -E '/#include *"[^"]+"/d' > submit.cpp]], current_file)
	run_command(cmd, "Generated submit.cpp", "Failed to generate submit.cpp")
end

local function build_cpp()
	local current_file = get_current_cpp_file()
	if not current_file then
		return
	end
	local cmd = string.format([[g++ -o %s.out %s 2>/dev/null]], vim.fn.fnamemodify(current_file, ":r"), current_file)
	run_command(cmd, "Compiled " .. current_file, "Failed to compile " .. current_file)
end

local function run_cpp()
	local current_file = get_current_cpp_file()
	if not current_file then
		return
	end

	local exe = vim.fn.fnamemodify(current_file, ":r") .. ".out"
	if vim.fn.executable(exe) ~= 1 then
		vim.notify("Executable not found. Compile first!", vim.log.levels.ERROR)
		return
	end

	local dir = vim.fn.fnamemodify(current_file, ":h")
	local input_file = dir .. "/input.txt"
	local output_file = dir .. "/output.txt"

	-- Helper to open or focus split
	local function focus_or_open(file_path, split_cmd)
		local bufnr = vim.fn.bufnr(file_path)
		local winnr = vim.fn.bufwinnr(bufnr)
		if winnr ~= -1 then
			vim.cmd(winnr .. "wincmd w")
		else
			vim.cmd(split_cmd .. " " .. vim.fn.fnameescape(file_path))
		end
	end

	-- 1. Ensure splits exist (vsplit input.txt on right, split output.txt below input)
	focus_or_open(input_file, "vsplit")
	focus_or_open(output_file, "split")

	-- 2. Save all open buffers (flushes typed input in input.txt to disk)
	vim.cmd("silent! wa")

	-- 3. Execute background binary redirection (no command bar or terminal window)
	local cmd = string.format(
		"%s < %s > %s",
		vim.fn.shellescape(exe),
		vim.fn.shellescape(input_file),
		vim.fn.shellescape(output_file)
	)
	vim.fn.system(cmd)

	-- 4. Reload output buffer from disk to show updated execution output
	vim.cmd("checktime")
	vim.notify("Ran successfully!", vim.log.levels.INFO)
end

function M.setup(opts)
	opts = vim.tbl_deep_extend("force", defaults, opts or {})

	vim.keymap.set("n", opts.keys.check, function()
		print("file generator is working!!!")
	end, { desc = "Check file generator status" })

	vim.keymap.set("n", opts.keys.generate, bundle_files, {
		desc = "Bundle C++ files into submit.cpp",
		silent = true,
		noremap = true,
	})

	vim.keymap.set("n", opts.keys.build, build_cpp, {
		desc = "Bundle C++ files into submit.cpp",
		silent = true,
		noremap = true,
	})

	vim.keymap.set("n", opts.keys.build, build_cpp, {
		desc = "Build C++ file",
		silent = true,
		noremap = true,
	})

	vim.keymap.set("n", opts.keys.run, run_cpp, {
		desc = "Run C++ file",
		silent = true,
		noremap = true,
	})
end

return M
