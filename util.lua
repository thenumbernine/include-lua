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


--[[
args:
	code = code
	lib = `lib = require 'ffi.load' '$lib'`
	headerCode = string that goes beneath the top require'ffi'
	footerCode = string that goes above the last `return wrapper`
	requires = table of strings that goes below the requires picked out of the parsed file.
--]]
local string = require 'ext.string'
local table = require 'ext.table'
local assert = require 'ext.assert'
local path = require 'ext.path'
local function makeLibWrapper(args)
	local code = assert(args.code)
path'~before-makeLibWrapper.h':write(code)

	local lines = string.split(code, '\n')
	assert.eq(lines:remove(1), "local ffi = require 'ffi'")
	assert.eq(lines:remove(1), 'ffi.cdef[[')
	assert.eq(lines:remove(), '')
	assert.eq(lines:remove(), ']]')

	-- undo the #include <-> require()'s, since they will go at the top
	-- but there's none in libjpeg...
	local reqpat = '^'
		..string.patescape"]] "
		.."(require 'ffi%.req' '.*')"
		..string.patescape" ffi.cdef[["
		..'$'
	local requires = table()
	local comments = table()
	-- capture comments.
	-- replace the generate.lua-created `]] require 'ffi.req' '.*' ffi.cdef[[` lines with requires to-be-inserted
	-- strip out all the ++ BEGIN / END ++ ones
	-- strip out the define ones that are degenerate to enum output, i.e. ending in `### string, number` or `string, not number ""`
	-- whatever's left put it at the top in Lua comments.
	for i=1,#lines do
		local line = lines[i]

		-- search for `]] require 'ffi.req' '...' ffi.cdef[[` lines
		local req = line:match(reqpat)
		if req then
			-- keep it there for ~before-c-h-parser.h to show
			-- this way header parse errors lines will match up with
			lines[i] = '// '..line
			requires:insert(req)

		-- comment is a preproc-generated `/* ++... BEGIN/END ... */` lines
		elseif line:match'^/%* %++ BEGIN.* %*/$'
		or line:match'^/%* %++ END.* %*/$'
		then

		-- comment is enum ouptut
		elseif line:match'^/%*.*### including in Lua enums.*%*/$'
		or line:match'^/%* redefining matching value.*%*/$'
		then

		-- what's left, save
		elseif line:match'^/%*.*%*/$'
		or line:match'^//'
		then
			comments:insert(line)
		end
	end

	code = lines:concat'\n'

	local CHeaderParser = require 'c-h-parser'
	local header = CHeaderParser()
path'~before-c-h-parser.h':write(code)
	local success, msg = header(code)
	if not success then
		error("C header parser failed: "..tostring(msg)..'\n'
			..'check your "~before-c-h-parser.h" for the output that the parser choked on.')
	end

	if args.requires then
		requires:append(args.requires)
	end

	code = table{
		"local ffi = require 'ffi'",
	}:append(
		#comments > 0 and {
			'',
			'-- comments',
			'',
			'--[[',
			comments:concat'\n',
			'--]]',
		} or nil
	):append(
		args.headerCode and {string.trim(args.headerCode)} or nil
	):append{
		'',
		'-- typedefs',
		'',
		requires:concat'\n',
		'',
		'ffi.cdef[[',
		header.declTypes:mapi(function(node)
			return node:toC()..';'
		end):concat'\n',
		']]',
		[[

local wrapper
wrapper = require 'ffi.libwrapper'{]],
	}:append(
		args.lib and {[[	lib = require 'ffi.load' ']]..args.lib..[[',]]} or nil
	):append{
[[
	defs = {
		-- enums
]],
		header.anonEnumValues:mapi(function(node)
			return '\t\t'..node:toC()..','
		end):concat'\n',

		'\n\t\t-- functions\n',

		header.symbolsInOrder:mapi(function(node)
			-- assert it is a decl
			assert.is(node, header.ast._decl)
			assert.len(node.subdecls, 1)
			-- get name-most ...
			local name = node.subdecls[1]
			while type(name) ~= 'string' do
				name = name[1]
			end
			-- remove extern qualifier if it's there
			node.stmtQuals.extern = nil
			return '\t\t'
				..name..' = [['
				..node:toC()
				..';]],'
		end)
		:append(args.funcs)
		:concat'\n',
	}:append(
		libDefs and {'\t\t'..libDefs:gsub('\n', '\n\t\t')} or nil
	):append{
		[[
	},
}
]],
	}:append(
		args.footerCode and {string.trim(args.footerCode)..'\n'} or nil
	):append{
		'return wrapper',
	}:concat'\n'..'\n'

	return code
end


return {
	safegsub = safegsub,
	removeEnum = removeEnum,
	commentOutLine = commentOutLine,
	fixEnumsAndDefineMacrosInterleaved = fixEnumsAndDefineMacrosInterleaved,
	makeLibWrapper = makeLibWrapper,
}
