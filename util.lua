--[[
set of utility functions used by the include-lists for their final() processing.
--]]
local string = require 'ext.string'

-- for all these .final() functions,
-- wrap them in a function that detects if the modification took place, and writes a warning to stderr if it didn't.
-- that way as versions increment I can know which filters are no longer needed.
local function safegsub(s, from, to, ...)
	local n
	s, n = string.gsub(s, from, to, ...)
	if n == 0 then
		-- TODO use the calling function from stack trace ... but will it always exist?
		io.stderr:write('UNNECESSARY: ', tostring(from), '\n')
	end
	return s
end

local function remove_GLIBC_INTERNAL_STARTING_HEADER_IMPLEMENTATION(code)
	return safegsub(
		code,
		'enum { __GLIBC_INTERNAL_STARTING_HEADER_IMPLEMENTATION = 1 };\n',
		'')
end

local function removeEnum(code, enumstr)
	return safegsub(
		code,
		'enum { '..enumstr..' };\n',
		''
	)
end

local function remove_need_macro(code)
	return safegsub(
		code,
		'enum { __need_[_%w]* = 1 };\n',
		''
	)
end

local function replace_va_list_require(code)
	return safegsub(
		code,
		'typedef __gnuc_va_list va_list;',
		[=[]] require 'ffi.req' 'c.va_list' ffi.cdef[[]=]
	)
end

-- TODO keeping warnings as comments seems nice
--  but they insert at the first line
--  which runs the risk of bumping the first line skip of BEGIN ...
--  which could replcae the whole file with a require()
local function removeWarnings(code)
	return safegsub(
		code,
		'warning:[^\n]*\n',
		''
	)
end

local function commentOutLine(code, line)
	return safegsub(
		code,
		string.patescape(line),
		'/* manually commented out: '..line..' */'
	)
end

-- ok with {.-} it fails on funcntions that have {}'s in their body, like wmemset
-- so lets try %b{}
-- TODO name might have a * before it instead of a space...
local function removeStaticFunction(code, name)
	return safegsub(
		code,
		'static%s[^(]-%s'..name..'%s*%(.-%)%s*%b{}',
		''
	)
end

local function removeStaticInlineFunction(code, name)
	return safegsub(
		code,
		'static%sinline%s[^(]-%s'..name..'%s*%(.-%)%s*%b{}',
		''
	)
end

local function remove__inlineFunction(code, name)
	return safegsub(
		code,
		'__inline%s[^(]-%s'..name..'%s*%(.-%)%s*%b{}',
		''
	)
end

local function removeDeclSpecNoInlineFunction(code, name)
	return safegsub(
		code,
		'__declspec%(noinline%)%s*__inline%s[^(]-%s'..name..'%s*%(.-%)%s*%b{}',
		''
	)
end

-- these all have some inlined enum errors:
--  caused from #define spitting out an enum intermingled in the lines of an enum { already present
local function fixEnumsAndDefineMacrosInterleaved(code)
	local lines = string.split(code, '\n')
	lines = lines:mapi(function(l)
		local a,b = l:match'^(.*) enum { (.*) = 0 };$'
		if a then
			-- there will be a trailing comma in all but the last of an enum
			-- there may or may not be an "= value" in 'a' also
			local comma = ''
			if a:sub(-1) == ',' then
				comma = ','
				a = a:sub(1,-2)
			end
			-- TODO this might match even if a and b are different, even if b is a suffix of a
			-- but honestly why even constraint a and b to be equal, since
			-- at this point there's two enums on the same line, which i'm trying to avoid
			if a:match(string.patescape(b)) then
				return a..comma..'/* enum { '..b..' = 0 }; */'
			end
		end
		return l
	end)
	return lines:concat'\n'
end


return {
	safegsub = safegsub,
	removeEnum = removeEnum,
	commentOutLine = commentOutLine,
	fixEnumsAndDefineMacrosInterleaved = fixEnumsAndDefineMacrosInterleaved,
}
