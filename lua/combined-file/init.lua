local M = {}

local defaults = {
	keys = {
		check = "<Leader>cpc",
		generate = "<Leader>cpg",
		build = "<Leader>cpb",
		run = "<Leader>cpr",
	},
}

-- Short notify; always scheduled so it's safe to call from job callbacks.
local function notify(msg, level)
	vim.schedule(function()
		vim.notify(msg, level or vim.log.levels.INFO)
	end)
end

-- Turn an exit code into something human readable.
local function explain_exit(code)
	local signals = {
		[134] = "SIGABRT (abort)",
		[136] = "SIGFPE (arithmetic error)",
		[139] = "SIGSEGV (segfault)",
		[143] = "SIGTERM (terminated)",
	}
	if code == 0 then
		return "exit 0"
	end
	if signals[code] then
		return signals[code] .. " [exit " .. code .. "]"
	end
	if code > 128 then
		return "signal " .. (code - 128) .. " [exit " .. code .. "]"
	end
	return "exit " .. code
end

--- Collects raw job chunks into buffer-safe lines.
--- Job callbacks may hand us strings with embedded "\n", "\r" or NULs,
--- all of which `nvim_buf_set_lines` / quickfix reject.
local Output = {}
Output.__index = Output

function Output.new()
	return setmetatable({ items = {} }, Output)
end

function Output:add(data)
	for _, chunk in ipairs(data or {}) do
		for _, part in ipairs(vim.split(chunk, "\n", { plain = true })) do
			part = part:gsub("\r", ""):gsub("%z", "")
			if part ~= "" then
				table.insert(self.items, part)
			end
		end
	end
end

function Output:lines()
	return self.items
end

function Output:is_empty()
	return #self.items == 0
end

-- First N lines for the notify preview.
local function preview(lines, n)
	n = n or 10
	local out = {}
	for i = 1, math.min(n, #lines) do
		table.insert(out, lines[i])
	end
	if #lines > n then
		table.insert(out, string.format("... (%d more, :copen to see all)", #lines - n))
	end
	return table.concat(out, "\n")
end

-- Show full output in quickfix, open it on failure.
local function to_quickfix(lines, title)
	vim.fn.setqflist({}, " ", { lines = lines, title = title })
	vim.cmd("copen")
end

-- Focus existing split for {file} or open it with {split_cmd}.
local function goto_output(output_file, split_cmd)
	local bufnr = vim.fn.bufnr(output_file)
	if vim.fn.bufwinnr(bufnr) ~= -1 then
		vim.cmd(vim.fn.bufwinnr(bufnr) .. "wincmd w")
	else
		vim.cmd(split_cmd .. " " .. vim.fn.fnameescape(output_file))
		bufnr = vim.fn.bufnr(output_file)
	end
	return bufnr
end

-- Write lines to a file buffer. Never passes newlines / empty list to the API.
local function write_output(output_file, split_cmd, lines)
	local bufnr = goto_output(output_file, split_cmd)
	local safe = #lines > 0 and lines or { "" }
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, safe)
	vim.api.nvim_buf_call(bufnr, function()
		vim.cmd("silent! w")
	end)
end

-- Run a shell command, capture stderr, notify + quickfix on failure.
local function run_command(cmd, opts)
	local err = Output.new()
	vim.fn.jobstart({ "sh", "-c", cmd }, {
		stderr_buffered = true,
		on_stderr = function(_, data)
			err:add(data)
		end,
		on_exit = function(_, code)
			if code == 0 then
				notify(opts.success, vim.log.levels.INFO)
			else
				local lines = err:lines()
				if #lines == 0 then
					lines = { "(no output, " .. explain_exit(code) .. ")" }
				end
				notify(
					opts.title .. " failed (" .. explain_exit(code) .. "):\n" .. preview(lines),
					vim.log.levels.ERROR
				)
				vim.schedule(function()
					to_quickfix(lines, opts.title)
				end)
			end
		end,
	})
end

local function get_current_cpp_file()
	local current_file = vim.api.nvim_buf_get_name(0)
	if current_file == "" then
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
	local cmd = string.format(
		[[cat *.h %s 2>&1 | sed -E '/#include *"[^"]+"/d' > submit.cpp]],
		vim.fn.shellescape(current_file)
	)
	run_command(cmd, { success = "Generated submit.cpp", title = "Bundle" })
end

local function build_cpp()
	local current_file = get_current_cpp_file()
	if not current_file then
		return
	end
	local out = vim.fn.fnamemodify(current_file, ":r") .. ".out"
	local cmd = string.format(
		"g++ -std=c++20 -Wall -Wextra -o %s %s",
		vim.fn.shellescape(out),
		vim.fn.shellescape(current_file)
	)
	run_command(
		cmd,
		{ success = "Compiled " .. current_file, title = "g++ " .. vim.fn.fnamemodify(current_file, ":t") }
	)
end

local function report_run(exe, code, elapsed, stdout_lines, stderr_lines)
	write_output(vim.fn.fnamemodify(exe, ":h") .. "/output.txt", "split", stdout_lines)

	if code == 0 and #stderr_lines == 0 then
		notify("Ran " .. vim.fn.fnamemodify(exe, ":t") .. " (" .. elapsed .. ")", vim.log.levels.INFO)
	else
		local detail = #stderr_lines > 0 and ("\n" .. preview(stderr_lines)) or ""
		notify("Ran with " .. explain_exit(code) .. " in " .. elapsed .. detail, vim.log.levels.ERROR)
		if #stderr_lines > 0 then
			to_quickfix(stderr_lines, "run " .. vim.fn.fnamemodify(exe, ":t"))
		end
	end
end

local function run_cpp()
	local current_file = get_current_cpp_file()
	if not current_file then
		return
	end

	local exe = vim.fn.fnamemodify(current_file, ":r") .. ".out"
	if vim.fn.filereadable(exe) ~= 1 then
		vim.notify("Executable not found. Compile first!", vim.log.levels.ERROR)
		return
	end

	local dir = vim.fn.fnamemodify(current_file, ":h")
	local input_file = dir .. "/input.txt"

	-- Open input.txt in a vertical split.
	local input_bufnr = vim.fn.bufnr(input_file)
	if vim.fn.bufwinnr(input_bufnr) ~= -1 then
		vim.cmd(vim.fn.bufwinnr(input_bufnr) .. "wincmd w")
	else
		vim.cmd("vsplit " .. vim.fn.fnameescape(input_file))
		input_bufnr = vim.fn.bufnr(input_file)
	end

	local function execute_cpp()
		local input_lines = vim.api.nvim_buf_get_lines(input_bufnr, 0, -1, false)
		local input_data = table.concat(input_lines, "\n") .. "\n"

		local stdout, stderr = Output.new(), Output.new()
		local start = vim.loop.hrtime()
		local jobid = vim.fn.jobstart({ exe }, {
			stdout_buffered = true,
			stderr_buffered = true,
			on_stdout = function(_, data)
				stdout:add(data)
			end,
			on_stderr = function(_, data)
				stderr:add(data)
			end,
			on_exit = function(_, code)
				local elapsed = string.format("%.0fms", (vim.loop.hrtime() - start) / 1e6)
				vim.schedule(function()
					report_run(exe, code, elapsed, stdout:lines(), stderr:lines())
				end)
			end,
		})

		if jobid <= 0 then
			vim.notify("Failed to start " .. exe, vim.log.levels.ERROR)
			return
		end
		vim.fn.chansend(jobid, input_data)
		vim.fn.chanclose(jobid, "stdin")
	end

	-- One-time autocmd: save input.txt to run.
	local group = vim.api.nvim_create_augroup("RunCppOnSave_" .. input_bufnr, { clear = true })
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		buffer = input_bufnr,
		once = true,
		callback = execute_cpp,
	})

	vim.notify("Edit input.txt and save (:w) to run.", vim.log.levels.INFO)
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
