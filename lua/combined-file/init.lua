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

-- Show full output in quickfix, open it on failure.
local function to_quickfix(lines, title)
	vim.fn.setqflist({}, " ", { lines = lines, title = title })
	vim.cmd("copen")
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

-- Run a shell command, capture stderr, notify + quickfix on failure.
local function run_command(cmd, opts)
	local err = {}
	vim.fn.jobstart({ "sh", "-c", cmd }, {
		stderr_buffered = true,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(err, line)
				end
			end
		end,
		on_exit = function(_, code)
			if code == 0 then
				notify(opts.success, vim.log.levels.INFO)
			else
				if #err == 0 then
					err = { "(no output, " .. explain_exit(code) .. ")" }
				end
				notify(opts.title .. " failed (" .. explain_exit(code) .. "):\n" .. preview(err), vim.log.levels.ERROR)
				vim.schedule(function()
					to_quickfix(err, opts.title)
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

-- Focus existing split for {file} or open it with {cmd} (vsplit/split).
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
	local output_file = dir .. "/output.txt"

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

		local stdout, stderr = {}, {}
		local start = vim.loop.hrtime()
		local jobid = vim.fn.jobstart({ exe }, {
			stdout_buffered = true,
			stderr_buffered = true,
			on_stdout = function(_, data)
				for _, line in ipairs(data) do
					if line ~= "" then
						table.insert(stdout, line)
					end
				end
			end,
			on_stderr = function(_, data)
				for _, line in ipairs(data) do
					if line ~= "" then
						table.insert(stderr, line)
					end
				end
			end,
			on_exit = function(_, code)
				local ms = (vim.loop.hrtime() - start) / 1e6
				local time = string.format("%.0fms", ms)
				vim.schedule(function()
					local out_bufnr = goto_output(output_file, "split")
					vim.api.nvim_buf_set_lines(out_bufnr, 0, -1, false, stdout)
					vim.api.nvim_buf_call(out_bufnr, function()
						vim.cmd("silent! w")
					end)

					if code == 0 and #stderr == 0 then
						notify("Ran " .. vim.fn.fnamemodify(exe, ":t") .. " (" .. time .. ")", vim.log.levels.INFO)
					else
						local reason = explain_exit(code)
						local detail = #stderr > 0 and ("\n" .. preview(stderr)) or ""
						notify("Ran with " .. reason .. " in " .. time .. detail, vim.log.levels.ERROR)
						if #stderr > 0 then
							to_quickfix(stderr, "run " .. vim.fn.fnamemodify(exe, ":t"))
						end
					end
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
