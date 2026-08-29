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

	local exe = string.format("./%s.out", vim.fn.fnamemodify(current_file, ":r"))

	vim.ui.input({ prompt = "Input: " }, function(input)
		local cmd = string.format("printf '%%s\\n' %s | %s", vim.fn.shellescape(input), exe)
		run_command(cmd, "Ran " .. current_file, "Failed to run " .. current_file, true)
	end)
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
