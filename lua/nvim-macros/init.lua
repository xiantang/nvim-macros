local base64 = require("nvim-macros.base64")
local util = require("nvim-macros.util")
local json = require("nvim-macros.json")

-- Default configuration
---@class Config
---@field json_file_path string
---@field default_macro_register string
---@field json_formatter "none" | "jq" | "yq"
local config = {
	json_file_path = vim.fs.normalize(vim.fn.stdpath("config") .. "/macros.json"),
	default_macro_register = "q",
	json_formatter = "none",
}

local M = {}

-- Initialize with user config
---@param user_config? Config
M.setup = function(user_config)
	if user_config ~= nil then
		for key, value in pairs(user_config) do
			if config[key] ~= nil then
				config[key] = value
			else
				util.print_error("Invalid config key: " .. key)
			end
		end
	end
end

-- Yank macro from register to default register
M.yank = function(register)
	local valid_registers = "[a-z0-9]"
	if not register or register == "" then
		register = util.get_register_input("Specify a register to yank from: ", config.default_macro_register)
	end

	while not (register:match("^" .. valid_registers .. "$")) do
		util.print_error(
			"Invalid register: `" .. register .. "`. Register must be a single lowercase letter or number 1-9."
		)

		register = util.get_register_input("Specify a register to yank from: ", config.default_macro_register)
	end

	local register_content = vim.fn.getreg(register)
	if not register_content or register_content == "" then
		util.print_error("Register `" .. register .. "` is empty or invalid!")
		return
	end

	register_content = register_content:gsub("\128\253a", "")
	local macro = vim.fn.keytrans(register_content)
	util.set_macro_to_register(macro)
	util.print_message("Yanked macro from `" .. register .. "` to clipboard.")
end

-- Execute macro (for key mappings)
M.run = function(macro)
	if not macro then
		util.print_error("Macro is empty. Cannot run.")
		return
	end

	vim.cmd.normal(vim.api.nvim_replace_termcodes(macro, true, true, true))
end

-- Save macro to JSON (Raw and Escaped)
M.save_macro = function(register)
	local valid_registers = "[a-z0-9]"
	if not register or register == "" then
		register = util.get_register_input("Specify a register to save from: ", config.default_macro_register)
	end

	while not (register:match("^" .. valid_registers .. "$")) do
		util.print_error(
			"Invalid register: `" .. register .. "`. Register must be a single lowercase letter or number 1-9."
		)

		register = util.get_register_input("Specify a register to save from: ", config.default_macro_register)
	end

	local register_content = vim.fn.getreg(register)
	if not register_content or register_content == "" then
		util.print_error("Register `" .. register .. "` is empty or invalid!")
		return
	end
	local name = vim.fn.input("Name your macro: ")
	if not name or name == "" then
		util.print_error("Invalid or empty macro name.")
		return
	end

	register_content = register_content:gsub("\128\253a", "")
	local macro = vim.fn.keytrans(register_content)
	local macro_raw = base64.enc(register_content)

	local macros = json.handle_json_file(config.json_formatter, config.json_file_path, "r")
	if macros then
		table.insert(macros.macros, { name = name, content = macro, raw = macro_raw })
		json.handle_json_file(config.json_formatter, config.json_file_path, "w", macros)
		util.print_message("Macro `" .. name .. "` saved.")
	end
end

-- Delete macro from JSON file
M.delete_macro = function()
	local macros = json.handle_json_file(config.json_formatter, config.json_file_path, "r")
	if not macros or not macros.macros or #macros.macros == 0 then
		util.print_error("No macros to delete.")
		return
	end

	local choices = {}
	local name_to_index_map = {}
	for index, macro in ipairs(macros.macros) do
		if macro.name then
			local display_text = macro.name .. " | " .. string.sub(macro.content, 1, 150)
			table.insert(choices, display_text)
			name_to_index_map[display_text] = index
		end
	end

	if next(choices) == nil then
		util.print_error("No valid macros for deletion.")
		return
	end

	vim.ui.select(choices, { prompt = "Select a macro to delete:" }, function(choice)
		if not choice then
			util.print_error("Macro deletion cancelled.")
			return
		end

		local macro_index = name_to_index_map[choice]
		local macro_name = macros.macros[macro_index].name
		if not macro_index then
			util.print_error("Selected macro `" .. choice .. "` is invalid.")
			return
		end

		table.remove(macros.macros, macro_index)
		json.handle_json_file(config.json_formatter, config.json_file_path, "w", macros)
		util.print_message("Macro `" .. macro_name .. "` deleted.")
	end)
end

M.select = function(opts)
	local macros = json.handle_json_file(config.json_formatter, config.json_file_path, "r")
	if not macros or not macros.macros or #macros.macros == 0 then
		util.print_error("No macros to select.")
		return
	end
	local choices = {}
	local name_to_content_map = {}
	local name_to_encoded_content_map = {}
	local name_to_index_map = {}
	for index, macro in ipairs(macros.macros) do
		if macro.name and macro.content and macro.raw then
			local display_text = macro.name .. " | " .. string.sub(macro.content, 1, 150)
			table.insert(choices, display_text)
			name_to_index_map[display_text] = index
			name_to_content_map[display_text] = macro.content
			name_to_encoded_content_map[display_text] = macro.raw
		end
	end
	if next(choices) == nil then
		util.print_error("No valid macros to yank.")
		return
	end
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local conf = require("telescope.config").values
	pickers
		.new(opts, {
			prompt_title = "Yank a macro to your register, Run a macro using <C-R>",
			finder = finders.new_table({
				results = choices,
			}),
			sorter = conf.generic_sorter(opts),
			attach_mappings = function(prompt_bufnr, map)
				map({ "i", "n" }, "<C-r>", function(_prompt_bufnr)
					actions.close(prompt_bufnr)
					-- change to nomarl mode
					local keys = vim.api.nvim_replace_termcodes("<ESC>", true, false, true)
					vim.api.nvim_feedkeys(keys, "n", true)
					local selection = action_state.get_selected_entry()
					local choice = selection[1]
					local macro_index = name_to_index_map[choice]
					local macro_name = macros.macros[macro_index].name
					local macro_content = name_to_content_map[choice]
					local encoded_content = name_to_encoded_content_map[choice]
					if not macro_content or not encoded_content then
						util.print_error("Selected macro `" .. choice .. "` has missing content.")
						return
					end
					local target_register = config.default_macro_register
					util.set_decoded_macro_to_register(encoded_content, target_register)
					vim.cmd.norm("@a")
					return true
				end, { desc = "desc for which key" })
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					local choice = selection[1]
					local macro_index = name_to_index_map[choice]
					local macro_name = macros.macros[macro_index].name
					local macro_content = name_to_content_map[choice]
					local encoded_content = name_to_encoded_content_map[choice]
					if not macro_content or not encoded_content then
						util.print_error("Selected macro `" .. choice .. "` has missing content.")
						return
					end
					local target_register = config.default_macro_register
					util.set_decoded_macro_to_register(encoded_content, target_register)
				end)
				return true
			end,
		})
		:find()
end

-- Select and yank macro from JSON (Raw or Escaped)
M.select_and_yank_macro = function()
	local macros = json.handle_json_file(config.json_formatter, config.json_file_path, "r")
	if not macros or not macros.macros or #macros.macros == 0 then
		util.print_error("No macros to select.")
		return
	end

	local choices = {}
	local name_to_content_map = {}
	local name_to_encoded_content_map = {}
	local name_to_index_map = {}
	for index, macro in ipairs(macros.macros) do
		if macro.name and macro.content and macro.raw then
			local display_text = macro.name .. " | " .. string.sub(macro.content, 1, 150)
			table.insert(choices, display_text)
			name_to_index_map[display_text] = index
			name_to_content_map[display_text] = macro.content
			name_to_encoded_content_map[display_text] = macro.raw
		end
	end

	if next(choices) == nil then
		util.print_error("No valid macros to yank.")
		return
	end

	vim.ui.select(choices, { prompt = "Select a macro:" }, function(choice)
		if not choice then
			util.print_error("Macro selection canceled.")
			return
		end

		local macro_index = name_to_index_map[choice]
		local macro_name = macros.macros[macro_index].name
		local macro_content = name_to_content_map[choice]
		local encoded_content = name_to_encoded_content_map[choice]
		if not macro_content or not encoded_content then
			util.print_error("Selected macro `" .. choice .. "` has missing content.")
			return
		end

		local yank_option = vim.fn.input("Yank as (1) Escaped, (2) Raw Macro: ")

		if yank_option == "1" then
			util.set_macro_to_register(macro_content)
			util.print_message("Yanked macro `" .. macro_name .. "` to clipboard.")
		elseif yank_option == "2" then
			local valid_registers = "[a-z0-9]"
			local target_register =
				util.get_register_input("Specify a register to yank the raw macro to: ", config.default_macro_register)

			while not (target_register:match("^" .. valid_registers .. "$")) do
				util.print_error(
					"Invalid register: `"
						.. target_register
						.. "`. Register must be a single lowercase letter or number 1-9."
				)

				target_register = util.get_register_input(
					"Specify a register to yank the raw macro to: ",
					config.default_macro_register
				)
			end

			util.set_decoded_macro_to_register(encoded_content, target_register)
			util.print_message("Yanked raw macro `" .. macro_name .. "` into register `" .. target_register .. "`.")
		else
			util.print_error("Invalid yank option selected.")
		end
	end)
end

return M
