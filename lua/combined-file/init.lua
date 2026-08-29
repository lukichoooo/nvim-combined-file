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

	-- Helper function to focus or open a split window
	local function focus_or_open(file_path, split_cmd)
		local bufnr = vim.fn.bufnr(file_path)
		local winnr = vim.fn.bufwinnr(bufnr)
		if winnr ~= -1 then
			vim.cmd(winnr .. "wincmd w")
		else
			vim.cmd(split_cmd .. " " .. vim.fn.fnameescape(file_path))
		end
	end

	-- 1. Open splits for input and output files
	focus_or_open(input_file, "vsplit")
	focus_or_open(output_file, "split")

	-- 2. Force-save all buffers so changes in input.txt write to disk
	vim.cmd("silent! wa")

	-- 3. Read input text directly from input.txt file
	local input_bufnr = vim.fn.bufnr(input_file)
	local input_lines = vim.api.nvim_buf_get_lines(input_bufnr, 0, -1, false)
	local input_data = table.concat(input_lines, "\n") .. "\n"

	-- 4. Run binary synchronously passing input via standard stdin
	local res = vim.fn.system(vim.fn.shellescape(exe), input_data)

	-- 5. Write binary output directly into the output.txt buffer
	local output_bufnr = vim.fn.bufnr(output_file)
	local output_lines = vim.split(res, "\n", { trimempty = false })

	-- If output ends with trailing newline, strip the trailing empty string line
	if output_lines[#output_lines] == "" then
		table.remove(output_lines)
	end

	vim.api.nvim_buf_set_lines(output_bufnr, 0, -1, false, output_lines)

	-- Write the output buffer back to disk
	vim.api.nvim_buf_call(output_bufnr, function()
		vim.cmd("silent! w")
	end)

	vim.notify("Executed successfully!", vim.log.levels.INFO)
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
