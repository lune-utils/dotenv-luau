--!strict

-- Required Modules --
local fs = require("@lune/fs")
local process = require("@lune/process")

export type DotenvConfigOptions = {
	path: string | { string }?,
	override: boolean?,
	processEnv: DotenvPopulateInput?,
}

export type DotenvPopulateInput = {
	[string]: string,
}

export type DotenvParseOutput = {
	[string]: string,
}

export type DotenvConfigOutput = {
	parsed: DotenvParseOutput?,
}

--[=[
    @class Dotenv
    Transform node js dotenv to luau
]=]
local Dotenv = {}

-- local LINE = "%s*(%w[%w_]-)%s*=%s*([^#]+)"
local EXPORT_LINE = "^%s*export%s+([%w%._-]+)%s*[:=]%s*(.*)$"
local LINE = "^%s*([%w%._-]+)%s*[:=]%s*(.*)$"

local DEFAULT_OPTIONS = {
	override = false,
	path = nil,
	processEnv = nil,
} :: DotenvConfigOptions

----[=[
--    @within Dotenv
--    @param src string - contents to be parsed.
--    @return DotenvParseOutput - an object with keys and values based on `src`.
--
--    Parses a string in the .env file format into a table.
--
--    ```lua
--    local src = "GITHUB_TOKEN=ABCD"
--    print(Dotenv.parse(src)) -- prints { ['GITHUB_TOKEN'] = "ABCD" }
--    ```
--]=]
--function Dotenv._parse(src: string): DotenvParseOutput
--	local obj = {}
--
--	local lines = tostring(src)
--
--	-- Convert line breaks to same format
--	lines = string.gsub(lines, "\r\n?", "\n")
--
--	for line in string.gmatch(lines, "[^\r\n]+") do
--		local key, value = string.match(line, LINE)
--		-- Default nil to empty string
--		value = value or ""
--
--		-- Remove whitespace
--		value = string.match(value, "^%s*(.-)%s*$") :: any
--
--		-- Remove surrounding quotes
--		value = string.gsub(value, "^(['\"`])([\r\n%s%S]*)(%1)$", "%2")
--
--		-- Add to object
--		obj[key] = value
--	end
--
--	return obj
--end

--[=[
    @within Dotenv
    @param src string - contents to be parsed.
    @return DotenvParseOutput - an object with keys and values based on `src`.

    Parses a string in the .env file format into a table.

    ```lua
    local src = "GITHUB_TOKEN=ABCD"
    print(Dotenv.parse(src)) -- prints { ['GITHUB_TOKEN'] = "ABCD" }
    ```
]=]
function Dotenv.parse(src: string): DotenvParseOutput
	local obj = {}

	local lines = tostring(src):gsub("\r\n?", "\n") .. "\n"
	local key: string, valueBuf: string, quoteChar: string = nil, nil, nil
	local isMultiline = false

	for line in string.gmatch(lines, "[^\n]*\n?") do
		local raw = string.match(line, "^(.-)%s*$") :: string

		-- Multiline mode
		if isMultiline then
			valueBuf ..= "\n" .. raw

			-- End of multiline string
			if string.match(raw, quoteChar .. "%s*$") :: any then
				local fullValue = valueBuf
				fullValue = string.match(fullValue, "^" .. quoteChar .. "(.-)" .. quoteChar .. "%s*$") or fullValue

				if quoteChar == '"' then
					fullValue = fullValue:gsub("\\n", "\n"):gsub("\\r", "\r")
				end

				obj[key] = fullValue
				key, valueBuf, quoteChar = nil, nil, nil
				isMultiline = false
			end
		else
			-- Match single-line or start of multiline
			local k, v = string.match(raw, EXPORT_LINE)
			if not k then
				k, v = string.match(raw, LINE)
			end

			if k and v then
				local quote = string.sub(v, 1, 1)
				local last = string.sub(v, -1)

				if quote == '"' or quote == "'" or quote == "`" then
					if #v < 2 or last ~= quote then
						-- Start of multiline
						key = k
						valueBuf = v
						quoteChar = quote
						isMultiline = true
					else
						-- Single-line quoted
						v = string.match(v, "^" .. quote .. "(.-)" .. quote .. "$") or v
						if quote == '"' then
							v = v:gsub("\\n", "\n"):gsub("\\r", "\r")
						end
						obj[k] = v
					end
				else
					-- Unquoted: remove trailing comment
					v = string.match(v, "^(.-)%s*#") or v
					v = string.match(v, "^%s*(.-)%s*$")
					obj[k] = v
				end
			end
		end
	end

	return obj
end

--[=[
    @within Dotenv
    @param processEnv - the target lua table. in most cases use process.env but you can also pass your own lua table
    @param parsed - the source lua table
    @param options - additional options. 

    Loads `source` lua table into `target` like process.env.
]=]
function Dotenv.populate(processEnv: DotenvPopulateInput, parsed: DotenvPopulateInput, options: DotenvConfigOptions): ()
	for key, value in parsed do
		if processEnv[key] ~= nil then
			if options.override then
				processEnv[key] = value
			end
		else
			processEnv[key] = value
		end
	end
end

--[=[
    @within Dotenv
    @param options - additional options. example: `{ path = "./custom/path", override = false }` 
    @return DotenvConfigOutput - an object with a `parsed` key if successful or `error` key if an error occurred. example: { parsed = { KEY = 'value' } 
    
    Loads `.env` file contents into process.env.
]=]
function Dotenv.configDotenv(options: DotenvConfigOptions?): DotenvConfigOutput
	local opt = options or DEFAULT_OPTIONS
	local dotenvPath = `{process.cwd}/.env`

	local optionPaths = { dotenvPath }
	if opt.path then
		optionPaths = (type(opt.path) == "string" and { opt.path } or opt.path) :: { string }
	end

	local parsedAll = {}
	for _, optionPath in optionPaths do
		local content = fs.readFile(optionPath)
		local parsed = Dotenv.parse(content)
		Dotenv.populate(parsedAll, parsed, opt)
	end

	local processEnv = process.env
	Dotenv.populate(processEnv, parsedAll, opt)

	return { parsed = parsedAll }
end

--[=[
    @within Dotenv
    @param options - additional options. example: `{ path = "./custom/path", override = false }` 
    @return DotenvConfigOutput - an object with a `parsed` key if successful or `error` key if an error occurred. example: { parsed = { KEY = 'value' } 
    
    Loads `.env` file contents into process.env by default.
]=]
function Dotenv.config(options: DotenvConfigOptions?): DotenvConfigOutput
	-- TODO: Support for vault
	return Dotenv.configDotenv(options)
end

return Dotenv
