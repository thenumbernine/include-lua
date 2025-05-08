-- TODO chop this file up into per-OS files for system including , and per-lib files
-- mapping from c includes to luajit ffi/ includes
-- this is used for automated generation
-- this is also used during generation for swapping out #includes with require()'s of already-generated files

--[[
TODO an exhaustive way to generate all with the least # of intermediate files could be
- go down the list
- for each file, generate
- as you reach includes, see if any previous have requested the same include.
- if so then generate that include, and restart the process.
--]]

local ffi = require 'ffi'
local template = require 'template'
local path = require 'ext.path'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local io = require 'ext.io'
local os = require 'ext.os'
local tolua = require 'ext.tolua'

-- needs to match generate.lua or make.lua or wherever i'm setting it.
local enumGenUnderscoreMacros = true

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

-- TODO maybe ffi.Linux.c.bits.types instead
-- pid_t and pid_t_defined are manually inserted into lots of dif files
-- i've separated it into its own file myself, so it has to be manually replaced
-- same is true for a few other types
local function replace_bits_types_builtin(code, ctype)
	-- if we're excluing underscore macros this then the enum line won't be there.
	-- if we're including underscore macros then the enum will be multiply defined and need to b removed
	-- one way to unify these is just remove the enum regardless (in the filter() function) and then gsub the typedef with the require
	if enumGenUnderscoreMacros then
		return safegsub(
			code,
			string.patescape(
				[[typedef __]]..ctype..[[ ]]..ctype..[[;]]
			),
			[=[]] require 'ffi.req' 'c.bits.types.]=]..ctype..[=[' ffi.cdef[[]=]
		)
	else
		return safegsub(
			code,
			string.patescape([[
typedef __]]..ctype..[[ ]]..ctype..[[;
enum { __]]..ctype..[[_defined = 1 };]]
			),
			[=[]] require 'ffi.req' 'c.bits.types.]=]..ctype..[=[' ffi.cdef[[]=]
		)
	end
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

-- _VA_LIST_DEFINED and va_list don't appear next to each other like the typical bits_types_builtin do
local function remove_VA_LIST_DEFINED(code)
	return safegsub(
		code,
		'enum { _VA_LIST_DEFINED = 1 };\n',
		'')
end

local function replace_va_list_require(code)
	return safegsub(
		code,
		'typedef __gnuc_va_list va_list;',
		[=[]] require 'ffi.req' 'c.va_list' ffi.cdef[[]=]
	)
end

-- unistd.h and stdio.h both define SEEK_*, so ...
local function replace_SEEK(code)
	return safegsub(
		code,
		[[
enum { SEEK_SET = 0 };
enum { SEEK_CUR = 1 };
enum { SEEK_END = 2 };
]],
		"]] require 'ffi.req' 'c.bits.types.SEEK' ffi.cdef[[\n"
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

-- some _asm directives have #sym instead of "sym" and also need their quotes merged ...
local function fixasm(code)
	return (code:gsub('__asm(%b())', function(s)
		s = assert((s:match'^%((.*)%)$'))
		-- at this point osx is nice enough to space-separate tokens
		-- however I should account for non-space-separated.  TODO.
		s = string.trim(s)
		s = string.split(s, '%s+'):mapi(function(w)
			local inside = w:match('^"(.*)"$')
			if inside then return inside end	-- TODO string escape chars?
			if w:sub(1,1) == '#' then return w:sub(2) end
			error("idk "..tostring(w))
		end):concat()

		-- here's another weird thing
		s = assert(s:match'^_(.*)$')

		return '__asm("' .. s .. '")'
	end))
end

--[[
args:
	code = code
	lib = `lib = require 'ffi.load' '$lib'`
	headerCode = string that goes beneath the top require'ffi'
	footerCode = string that goes above the last `return wrapper`
	requires = table of strings that goes below the requires picked out of the parsed file.
--]]
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

local includeList = table()

-- files found in multiple OS's will go in [os]/[path]
-- and then in just [path] will be a file that determines the file based on os (and arch?)

-- [====[ Begin Windows-specific:
-- TODO this is most likely going to be come Windows/x64/ files in the future
includeList:append(table{
-- Windows-only:
	{inc='<vcruntime_string.h>', out='Windows/c/vcruntime_string.lua'},

	{inc='<corecrt.h>', out='Windows/c/corecrt.lua'},

	{inc='<corecrt_share.h>', out='Windows/c/corecrt_share.lua'},

	{inc='<corecrt_wdirect.h>', out='Windows/c/corecrt_wdirect.lua'},

	{
		inc = '<corecrt_stdio_config.h>',
		out = 'Windows/c/corecrt_stdio_config.lua',
		final = function(code)
			for _,f in ipairs{
				'__local_stdio_printf_options',
				'__local_stdio_scanf_options',
			} do
				code = remove__inlineFunction(code, f)
			end
			return code
		end,
	},

	-- depends: corecrt_stdio_config.h
	{inc='<corecrt_wstdio.h>', out='Windows/c/corecrt_wstdio.lua'},

	-- depends: corecrt_share.h
	{inc = '<corecrt_wio.h>', out = 'Windows/c/corecrt_wio.lua'},

	-- depends: vcruntime_string.h
	{inc='<corecrt_wstring.h>', out='Windows/c/corecrt_wstring.lua'},

	{inc='<corecrt_wstdlib.h>', out='Windows/c/corecrt_wstdlib.lua'},
	{inc='<corecrt_wtime.h>', out='Windows/c/corecrt_wtime.lua'},

-- cross support (so an intermediate ffi.c.stddef is needed for redirecting based on OS
	{inc='<stddef.h>', out='Windows/c/stddef.lua'},

	-- depends on: corecrt_wtime.h
	{
		inc = '<time.h>',
		out = 'Windows/c/time.lua',
		final = function(code)
			for _,f in ipairs{
				'ctime',
				'difftime',
				'gmtime',
				'localtime',
				'_mkgmtime',
				'mktime',
				'time',
				'timespec_get',
			} do
				code = removeStaticFunction(code, f)
			end
			-- add these static inline wrappers as lua wrappers
			-- TODO pick between 32 and 64 based on arch
			code = code .. [[
local lib = ffi.C
if ffi.arch == 'x86' then
	return setmetatable({
		_wctime = lib._wctime32,		-- in corecrt_wtime.h
		_wctime_s = lib._wctime32_s,		-- in corecrt_wtime.h
		ctime = _ctime32,
		difftime = _difftime32,
		gmtime = _gmtime32,
		localtime = _localtime32,
		_mkgmtime = _mkgmtime32,
		mktime = _mktime32,
		time = _time32,
		timespec_get = _timespec32_get,
	}, {
		__index = lib,
	})
elseif ffi.arch == 'x64' then
	return setmetatable({
		_wctime = lib._wctime64,		-- in corecrt_wtime.h
		_wctime_s = lib._wctime64_s,		-- in corecrt_wtime.h
		ctime = _ctime64,
		difftime = _difftime64,
		gmtime = _gmtime64,
		localtime = _localtime64,
		_mkgmtime = _mkgmtime64,
		mktime = _mktime64,
		time = _time64,
		timespec_get = _timespec64_get,
	}, {
		__index = lib,
	})
end
]]
			return code
		end,
	},

	{
		inc = '<sys/types.h>',
		out = 'Windows/c/sys/types.lua',
		final = function(code)
			code = code .. [=[

-- this isn't in Windows at all I guess, but for cross-platform's sake, I'll put in some common POSIX defs I need
-- gcc x64 defines ssize_t = __ssize_t, __ssize_t = long int
-- I'm guessing in gcc 'long int' is 8 bytes
-- msvc x64 'long int' is just 4 bytes ...
-- TODO proly arch-specific too

ffi.cdef[[
typedef intptr_t ssize_t;
]]
]=]
			return code
		end,
	},

	{
		inc = '<errno.h>',
		out = 'Windows/c/errno.lua',
	},

	-- depends on: errno.h corecrt_wstring.h vcruntime_string.h
	{inc = '<string.h>', out = 'Windows/c/string.lua'},

	-- depends on: corecrt_wio.h, corecrt_share.h
	-- really it just includes corecrt_io.h
	{
		inc = '<io.h>',
		out = 'Windows/c/io.lua',
		final = function(code)
			-- same as in corecrt_wio.h
			code = code .. [=[
ffi.cdef[[
/* #ifdef _USE_32BIT_TIME_T
	typedef _finddata32_t _finddata_t;
	typedef _finddata32i64_t _finddatai64_t;
#else */
	typedef struct _finddata64i32_t _finddata_t;
	typedef struct _finddata64_t _finddatai64_t;
/* #endif */
]]

local lib = ffi.C
return setmetatable({
--[[
#ifdef _USE_32BIT_TIME_T
	_findfirst = lib._findfirst32,
	_findnext = lib._findnext32,
	_findfirsti64 = lib._findfirst32i64,
	_findnexti64 = lib._findnext32i64,
#else
--]]
	_findfirst = lib._findfirst64i32,
	_findnext = lib._findnext64i32,
	_findfirsti64 = lib._findfirst64,
	_findnexti64 = lib._findnext64,
--[[
#endif
--]]
}, {
	__index = ffi.C,
})
]=]
			return code
		end,
	},

	-- depends on: errno.h corecrt_wio.h corecrt_wstring.h corecrt_wdirect.h corecrt_stdio_config.h corecrt_wtime.h vcruntime_string.h
	{
		inc = '<wchar.h>',
		out = 'Windows/c/wchar.lua',
		final = function(code)
			for _,f in ipairs{
				'fwide',
				'mbsinit',
				'wmemchr',
				'wmemcmp',
				'wmemcpy',
				'wmemmove',
				'wmemset',
			} do
				code = remove__inlineFunction(code, f)
			end

			-- corecrt_wio.h #define's types that I need, so typedef them here instead
			-- TODO pick according to the current macros
			-- but make.lua and generate.lua run in  separate processes, so ....
			code = code .. [=[
ffi.cdef[[
/* #ifdef _USE_32BIT_TIME_T
	typedef _wfinddata32_t _wfinddata_t;
	typedef _wfinddata32i64_t _wfinddatai64_t;
#else */
	typedef struct _wfinddata64i32_t _wfinddata_t;
	typedef struct _wfinddata64_t _wfinddatai64_t;
/* #endif */
]]

local lib = ffi.C
return setmetatable({
--[[
#ifdef _USE_32BIT_TIME_T
	_wfindfirst = lib._wfindfirst32,
	_wfindnext = lib._wfindnext32,
	_wfindfirsti64 = lib._wfindfirst32i64,
	_wfindnexti64 = lib._wfindnext32i64,
#else
--]]
	_wfindfirst = lib._wfindfirst64i32,
	_wfindnext = lib._wfindnext64i32,
	_wfindfirsti64 = lib._wfindfirst64,
	_wfindnexti64 = lib._wfindnext64,
--[[
#endif
--]]
}, {
	__index = ffi.C,
})
]=]
			return code
		end,
	},

	-- depends: corecrt_wdirect.h
	-- was a Windows programmer trying to type "dirent.h" and got mixed up?
	-- looks like a few of these functions are usually in POSIX unistd.h
	{
		inc = '<direct.h>',
		out = 'Windows/c/direct.lua',
	},

	-- [[ TODO verify these work
	{inc = '<fcntl.h>', out = 'Windows/c/fcntl.lua'},
	{inc = '<sys/mman.h>', out = 'Windows/c/sys/mman.lua'},
	--]]

	-- depends: corecrt_stdio_config.h
	{
		inc = '<stdio.h>',
		out = 'Windows/c/stdio.lua',
		final = function(code)
			-- return ffi.C so it has the same return behavior as Linux/c/stdio
			code = code .. [[
local lib = ffi.C
return setmetatable({
	fileno = lib._fileno,
}, {
	__index = ffi.C,
})
]]
			return code
		end,
	},

	-- depends: sys/types.h
	{
		inc = '<sys/stat.h>',
		out = 'Windows/c/sys/stat.lua',
		final = function(code)
			code = removeStaticFunction(code, 'fstat')	-- _fstat64i32
			code = removeStaticFunction(code, 'stat')	-- _stat64i32

			-- windows help says "always include sys/types.h first"
			-- ... smh why couldn't they just include it themselves?
			code = [[
require 'ffi.req' 'c.sys.types'
]] .. code
			code = code .. [=[
ffi.cdef[[
typedef struct _stat64 __stat64;
]]

-- for linux mkdir compat
require 'ffi.Windows.c.direct'

local lib = ffi.C
return setmetatable({
--[[
#ifdef _USE_32BIT_TIME_T
	_fstat = lib._fstat32,
	_fstati64 = lib._fstat32i64,

	_wstat = lib._wstat32,
	_wstati64 = lib._wstat32i64,
	-- header inline function Lua alias:
	--fstat = lib._fstat32,
	--stat = lib._stat32,

	--_stat = lib._stat32,
	--struct_stat = 'struct _stat32',
	--_stati64 = lib._stat32i64,
	--struct_stat64 = 'struct _stat32i64',

	-- for lfs compat:
	fstat = lib._fstat32,
	stat = lib._stat32,
	stat_struct = 'struct _stat32',
#else
--]]
	_fstat = lib._fstat64i32,
	_fstati64 = lib._fstat64,

	_wstat = lib._wstat64i32,
	_wstati64 = lib._wstat64,
	-- header inline function Lua alias:
	--fstat = lib._fstat64i32,
	--stat = lib._stat64i32,
	--_stat = lib._stat64i32,
	--struct_stat = 'struct _stat64i32', -- this is the 'struct' that goes with the 'stat' function ...
	--_stati64 = lib._stat64,
	--struct_stat64 = 'struct _stat64',

	-- but I think I want 'stat' to point to '_stat64'
	-- and 'struct_stat' to point to 'struct _stat64'
	-- for lfs_ffi compat between Linux and Windows
	fstat = lib._fstat64,
	stat = lib._stat64,
	struct_stat = 'struct _stat64',
--[[
#endif
--]]
}, {
	__index = ffi.C,
})
]=]
			return code
		end,
	},

	-- windows says ...
	-- _utime, _utime32, _utime64 is in sys/utime.h
	-- _wutime is in utime.h or wchar.h (everything is in wchar.h ...)
	-- posix says ...
	-- utime is in utime.h
	-- utimes is in sys/time.h
	-- ... could windows play ball and let utime.h redirect to sys/utime.h?
	-- ... nope. just sys/utime.h
	-- so let me check posix for sys/utime.h, if it doesn't exist then maybe I'll consider renaming this to utime.h instead of sys/utime.h
	-- nope it doesn't
	-- so instead I think I'll have ffi.c.utime and ffi.c.sys.utime point to windows' ffi.windows.c.sys.utime or linux' ffi.linux.c.utime
	{
		inc = '<sys/utime.h>',
		out = 'Windows/c/sys/utime.lua',
		-- TODO custom split file that redirects to Windows -> sys.utime, Linux -> utime
		final = function(code)
			for _,f in ipairs{
				'_utime',
				'_futime',
				'_wutime',
				'utime',
			} do
				code = removeStaticFunction(code, f)
			end
			code = code .. [=[
local lib = ffi.C
return setmetatable(
ffi.arch == 'x86' and {
	utime = lib._utime32,
	struct_utimbuf = 'struct __utimbuf32',
} or {
	utime = lib._utime64,
	struct_utimbuf = 'struct __utimbuf64'
}, {
	__index = lib,
})
]=]
			return code
		end,
	},

	-- unless I enable _VCRT_COMPILER_PREPROCESSOR , this file is empty
	-- maybe it shows up elsewhere?
	-- hmm but if I do, my preproc misses almost all the number defs
	-- because they use suffixes i8, i16, i32, i64, ui8, ui16, ui32, ui64
	-- (hmm similar but different set of macros are in limits.h)
	-- but the types it added ... int8_t ... etc ... are alrady buitin to luajit?
	-- no they are microsoft-specific:
	-- https://stackoverflow.com/questions/33659846/microsoft-integer-literal-extensions-where-documented
	-- so this means replace them wherever possible.
	{
		inc = '<stdint.h>',
		out = 'Windows/c/stdint.lua',
	},

	{
		inc = '<stdarg.h>',
		out = 'Windows/c/stdarg.lua',
	},

	-- identical in windows linux osx ...
	{
		inc = '<stdbool.h>',
		out = 'Windows/c/stdbool.lua',
		final = function(code)
			-- luajit has its own bools already defined
			for _,k in ipairs{'bool = 0', 'true = 1', 'false = 0'} do
				code = removeEnum(code, k)
			end
			return code
		end,
	},

	{
		inc = '<limits.h>',
		out = 'Windows/c/limits.lua',
	},

	-- depends: corecrt_wstdlib.h limits.h
	{
		inc = '<stdlib.h>',
		out = 'Windows/c/stdlib.lua',
	},

	-- needed by png.h
	{inc='<setjmp.h>', out='Windows/c/setjmp.lua'},

	-- not in windows, but I have a fake for aliasing, so meh
	{
		inc = '<unistd.h>',
		out = 'Windows/c/unistd.lua',
		forcecode = [=[
local ffi = require 'ffi'
require 'ffi.Windows.c.direct'  -- get our windows defs
local lib = ffi.C
-- TODO I see the orig name prototypes in direct.h ...
-- ... so do I even need the Lua alias anymore?
return setmetatable({
	chdir = lib._chdir,
	getcwd = lib._getcwd,
	rmdir = lib._rmdir,
}, {
	__index = lib,
})
]=]
	},

	-- used by GL, GLES1, GLES2 ...
	{
		inc = '<KHR/khrplatform.h>',
		out = 'Windows/KHR/khrplatform.lua',
	},

	-- used by SDL
	{
		inc = '<process.h>',
		out = 'Windows/c/process.lua',
	},

}:mapi(function(inc)
	inc.os = 'Windows'
	return inc
end))
--]====] End Windows-specifc:

-- [====[ Begin Linux-specific:
includeList:append(table{

	{inc='<stddef.h>', out='Linux/c/stddef.lua'},

	{inc='<bits/wordsize.h>', out='Linux/c/bits/wordsize.lua'},

	-- depends: bits/wordsize.h
	{inc='<features.h>', out='Linux/c/features.lua'},

	{inc='<bits/endian.h>', out='Linux/c/bits/endian.lua'},
	{inc='<bits/types/locale_t.h>', out='Linux/c/bits/types/locale_t.lua'},
	{inc='<bits/types/__sigset_t.h>', out='Linux/c/bits/types/__sigset_t.lua'},

	{inc='<bits/wchar.h>', out='Linux/c/bits/wchar.lua'},

	-- depends: features.h
	{
		inc = '<bits/floatn.h>',
		out = 'Linux/c/bits/floatn.lua',
		final = function(code)
			-- luajit doesn't handle float128 ...
			--code = safegsub(code, '(128[_%w]*) = 1', '%1 = 0')
			return code
		end,
	},

	{inc='<bits/types.h>', out='Linux/c/bits/types.lua'},

	-- depends: bits/types.h
	{inc='<bits/stdint-intn.h>', out='Linux/c/bits/stdint-intn.lua'},
	{inc='<bits/types/clockid_t.h>', out='Linux/c/bits/types/clockid_t.lua'},
	{inc='<bits/types/clock_t.h>', out='Linux/c/bits/types/clock_t.lua'},
	{inc='<bits/types/struct_timeval.h>', out='Linux/c/bits/types/struct_timeval.lua'},
	{inc='<bits/types/timer_t.h>', out='Linux/c/bits/types/timer_t.lua'},
	{inc='<bits/types/time_t.h>', out='Linux/c/bits/types/time_t.lua'},

	-- depends: bits/types.h bits/endian.h
	{inc='<bits/types/struct_timespec.h>', out='Linux/c/bits/types/struct_timespec.lua'},

	{inc='<sys/ioctl.h>', out='Linux/c/sys/ioctl.lua'},

	{inc='<sys/select.h>', out='Linux/c/sys/select.lua', final=function(code)
		code = replace_bits_types_builtin(code, 'suseconds_t')
		return code
	end},

	-- depends: features.h bits/types.h
	-- mind you i found in the orig where it shouldve require'd features it was requiring itself ... hmm ...
	{
		inc = '<sys/termios.h>',
		out = 'Linux/c/sys/termios.lua',
		final = function(code)
			code = replace_bits_types_builtin(code, 'pid_t')
			code = removeEnum(code, 'USE_CLANG_%w* = 0')
			return code
		end,
	},

	-- used by c/pthread, c/sys/types, c/signal
	{
		inc = '<bits/pthreadtypes.h>',
		silentincs = {
			'<features.h>',
		},
		out = 'Linux/c/bits/pthreadtypes.lua',
	},

	-- depends: features.h bits/types.h sys/select.h
	{inc='<sys/types.h>', out='Linux/c/sys/types.lua', final=function(code)
		for _,t in ipairs{
			'dev_t',
			'ino_t',
			'mode_t',
			'nlink_t',
			'gid_t',
			'uid_t',
			'off_t',
			'pid_t',
			'ssize_t',
		} do
			code = replace_bits_types_builtin(code, t)
		end
		return code
	end},

	{inc='<linux/limits.h>', out='Linux/c/linux/limits.lua'},

-- requires manual manipulation:
	-- depends: features.h
	-- this is here for require() insertion but cannot be used for generation
	-- it must be manually created
	--
	-- they run into the "never include this file directly" preproc error
	-- so you'll have to manually cut out the generated macros from another file
	--  and insert the code into a file in the results folder
	-- also anything that includes this will have the line before it:
	--  `enum { __GLIBC_INTERNAL_STARTING_HEADER_IMPLEMENTATION = 1 };`
	-- and that will have to be removed
	{
		dontGen = true,
		inc = '<bits/libc-header-start.h>',
		out = 'Linux/c/bits/libc-header-start.lua',
		final = function(code)
			return remove_GLIBC_INTERNAL_STARTING_HEADER_IMPLEMENTATION(code)
		end,
	},

	-- depends: features.h stddef.h bits/libc-header-start.h
	{inc='<string.h>', out='Linux/c/string.lua'},

	-- depends: features.h stddef.h bits/types.h and too many really
	-- this and any other file that requires stddef might have these lines which will have to be removed:
	{
		inc = '<time.h>',
		out = 'Linux/c/time.lua',
		final = function(code)
			code = replace_bits_types_builtin(code, 'pid_t')
			return code
		end,
	},

	-- depends on features.h
	{
		inc = '<errno.h>',
		out = 'Linux/c/errno.lua',
		final = function(code)
			-- manually add the 'errno' macro at the end:
			code = code .. [[
return setmetatable({
	errno = function()
		return ffi.C.__errno_location()[0]
	end,
}, {
	__index = ffi.C,
})
]]
			return code
		end,
	},

	{
		inc = '<utime.h>',
		out = 'Linux/c/utime.lua',
		final = function(code)
			code = code .. [[
return setmetatable({
	struct_utimbuf = 'struct utimbuf',
}, {
	__index = ffi.C,
})
]]
			return code
		end,
	},

	-- used by <sys/stat.h>, <fcntl.h>
	{
		dontGen = true,	-- I hate the "don't include this directly" error messages ...
		inc = '<bits/stat.h>',
		out = 'Linux/c/bits/stat.lua',
	},

	-- depends: bits/types.h etc
	{
		inc = '<sys/stat.h>',
		out = 'Linux/c/sys/stat.lua',
		final = function(code)
			for _,t in ipairs{
				'dev_t',
				'ino_t',
				'mode_t',
				'nlink_t',
				'gid_t',
				'uid_t',
				'off_t',
			} do
				code = replace_bits_types_builtin(code, t)
			end
			code = code .. [[
local lib = ffi.C
local statlib = setmetatable({
	struct_stat = 'struct stat',
}, {
	__index = lib,
})
-- allow nils instead of errors if we access fields not present (for the sake of lfs_ffi)
ffi.metatype(statlib.struct_stat, {
	__index = function(t,k)
		return nil
	end,
})
return statlib
]]
			return code
		end,
	},

	-- depends: bits/types.h
	{
		inc = '<stdint.h>',
		out = 'Linux/c/stdint.lua',
		final = function(code)
			--code = replace_bits_types_builtin(code, 'intptr_t')
			-- not the same def ...
			code = safegsub(
				code,
				[[
typedef long int intptr_t;
]],
				[=[]] require 'ffi.req' 'c.bits.types.intptr_t' ffi.cdef[[]=]
			)


			-- error: `attempt to redefine 'WCHAR_MIN' at line 75
			-- because it's already in <wchar.h>
			-- comment in stdint.h:
			-- "These constants might also be defined in <wchar.h>."
			-- yes. yes they are.
			-- so how to fix this ...
			-- looks like wchar.h doesn't include stdint.h...
			-- and stdint.h includes bits/wchar.h but not wchar.h
			-- and yeah the macros are in wchar.h, not bits/whcar.h
			-- hmm ...
			code = safegsub(
				code,
				string.patescape[[
enum { WCHAR_MIN = -2147483648 };
enum { WCHAR_MAX = 2147483647 };
]],
				[=[]] require 'ffi.req' 'c.wchar' ffi.cdef[[]=]
			)

			return code
		end,
	},

	-- depends: features.h sys/types.h
	{inc = '<stdlib.h>', out = 'Linux/c/stdlib.lua'},

	{
		inc = '<bits/types/__mbstate_t.h>',
		out = 'Linux/c/bits/types/__mbstate_t.lua',
	},
	{
		inc = '<bits/types/__FILE.h>',
		out = 'Linux/c/bits/types/__FILE.lua',
	},
	{
		inc = '<bits/types/FILE.h>',
		out = 'Linux/c/bits/types/FILE.lua',
	},

	-- depends on: bits/types/__mbstate_t.h
	-- I never needed it in Linux, until I got to SDL
	{inc = '<wchar.h>', out = 'Linux/c/wchar.lua'},

	-- depends: bits/wordsize.h
	{
		inc = '<bits/posix1_lim.h>',
		out = 'Linux/c/bits/posix1_lim.lua',
	},

	-- depends: bits/libc-header-start.h linux/limits.h bits/posix1_lim.h
	-- with this the preproc gets a warning:
	--  warning: redefining LLONG_MIN from -1 to -9.2233720368548e+18 (originally (-LLONG_MAX - 1LL))
	-- and that comes with a giant can of worms of how i'm handling cdef numbers vs macro defs vs lua numbers ...
	-- mind you I could just make the warning: output into a comment
	--  and there would be no need for manual manipulation here
	{inc='<limits.h>', out='Linux/c/limits.lua'},

	-- depends: features.h, bits/types/__sigset_t.h
	{inc='<setjmp.h>', out='Linux/c/setjmp.lua'},

	-- depends: features.h bits/types.h
	{
		inc = '<unistd.h>',
		out = 'Linux/c/unistd.lua',
		final = function(code)
			for _,t in ipairs{
				'gid_t',
				'uid_t',
				'off_t',
				'pid_t',
				'ssize_t',
				'intptr_t',
			} do
				code = replace_bits_types_builtin(code, t)
			end

			-- both unistd.h and stdio.h have SEEK_* defined, so ...
			-- you'll have to manually create this file
			code = replace_SEEK(code)

			--[=[
			code = safegsub(
				code,
				-- TODO i'm sure this dir will change in the future ...
				string.patescape('/* ++ BEGIN /usr/include/x86_64-linux-gnu/bits/confname.h */')
				..'.*'
				..string.patescape('/* ++ END /usr/include/x86_64-linux-gnu/bits/confname.h */'),
				[[

/* TODO here I skipped conframe because it was too many mixed enums and ddefines => enums  .... but do I still need to, because it seems to be sorted out. */
]]
			)
			--]=]
--[=[ TODO this goes in the manually-created split file in ffi.c.unistd
			code = code .. [[
-- I can't change ffi.C.getcwd to ffi.C._getcwd in the case of Windows
local lib = ffi.C
if ffi.os == 'Windows' then
	require 'ffi.req' 'c.direct'	-- get our windows defs
	return setmetatable({
		chdir = lib._chdir,
		getcwd = lib._getcwd,
		rmdir = lib._rmdir,
	}, {
		__index = lib,
	})
else
	return lib
end
]]
--]=]
			-- but for interchangeability with Windows ...
			code = code .. [[
return ffi.C
]]
			return code
		end,
	},

	-- depends: stddef.h bits/types/time_t.h bits/types/struct_timespec.h
	{inc='<sched.h>', out='Linux/c/sched.lua', final=function(code)
		code = replace_bits_types_builtin(code, 'pid_t')
		return code
	end},

	-- depends on too much
	{inc='<stdarg.h>', out='Linux/c/stdarg.lua', final=function(code)
		code = replace_va_list_require(code)
		return code
	end},

	-- identical in windows linux osx ...
	{
		inc = '<stdbool.h>',
		out = 'Linux/c/stdbool.lua',
		final = function(code)
			-- luajit has its own bools already defined
			for _,k in ipairs{'bool = 0', 'true = 1', 'false = 0'} do
				code = removeEnum(code, k)
			end
			return code
		end,
	},

	-- depends: features.h stdint.h
	{inc='<inttypes.h>', out='Linux/c/inttypes.lua'},

	-- [[ TODO verify these work
	{inc = '<fcntl.h>', out = 'Linux/c/fcntl.lua'},
	{inc = '<sys/mman.h>', out = 'Linux/c/sys/mman.lua'},
	--]]

	-- depends on too much
	-- moving to Linux-only block since now it is ...
	-- it used to be just after stdarg.h ...
	-- maybe I have to move everything up to that file into the Linux-only block too ...
	{
		inc = '<stdio.h>',
		out = 'Linux/c/stdio.lua',
		final = function(code)
			code = replace_bits_types_builtin(code, 'off_t')
			code = replace_bits_types_builtin(code, 'ssize_t')
			code = replace_va_list_require(code)
			-- this is in stdio.h and unistd.h
			code = replace_SEEK(code)
			-- this all stems from #define stdin stdin etc
			-- which itself is just for C99/C89 compat
			code = removeEnum(code, 'stdin = 0')
			code = removeEnum(code, 'stdout = 0')
			code = removeEnum(code, 'stderr = 0')
			-- for fopen overloading
			code = code .. [[
-- special case since in the browser app where I'm capturing fopen for remote requests and caching
-- feel free to not use the returend table and just use ffi.C for faster access
-- but know you'll be losing compatability with browser
return setmetatable({}, {
	__index = ffi.C,
})
]]
			return code
		end,
	},

	{
		inc = '<math.h>',
		out = 'Linux/c/math.lua',
		final = function(code)
			-- [[ enums and #defines intermixed ... smh
			code = safegsub(code, ' ([_%a][_%w]*) = enum { ([_%a][_%w]*) = %d+ };', function(a,b)
				if a == b then return ' '..a..' = ' end
				return '%0'
			end)
			--]]

			-- gcc thinks we have float128 support, but luajit doesn't support it
			code = safegsub(code, '[^\n]*_Float128[^\n]*', '')

			return code
		end,
	},

-- requires manual manipulation:

	{
		dontGen = true,
		inc = '<bits/dirent.h>',
		out = 'Linux/c/bits/dirent.lua',
		final = function(code)
			code = commentOutLine(code, 'enum { __undef_ARG_MAX = 1 };')
			return code
		end,
	},

	-- this is here for require() insertion but cannot be used for generation
	-- it must be manually extracted from c/setjmp.lua
	{
		dontGen = true,
		inc = '<bits/setjmp.h>',
		out = 'Linux/c/bits/setjmp.lua',
	},

	-- this file doesn't exist. stdio.h and stdarg.h both define va_list, so I put it here
	-- but i guess it doesn't even have to be here.
	--{dontGen = true, inc='<va_list.h>', out='Linux/c/va_list.lua'},

	-- same with just.  just a placeholder:
	--{dontGen = true, inc='<__FD_SETSIZE.h>', out='Linux/c/__FD_SETSIZE.lua'},


	-- depends on limits.h bits/posix1_lim.h
	-- because lua.ext uses some ffi stuff, it says "attempt to redefine 'dirent' at line 2"  for my load(path(...):read()) but not for require'results....'
	{
		inc = '<dirent.h>',
		out = 'Linux/c/dirent.lua',
		final = function(code)
			code = fixEnumsAndDefineMacrosInterleaved(code)
			return code
		end,
	},

	-- depends: sched.h time.h
	{inc='<pthread.h>', out='Linux/c/pthread.lua', final=function(code)
			code = fixEnumsAndDefineMacrosInterleaved(code)
			return code
	end},

	{
		inc = '<signal.h>',
		out = 'Linux/c/signal.lua',
		final = function(code)
			-- i think all these stem from #define A B when the value is a string and not numeric
			--  but my #define to enum inserter forces something to be produced
			for _,k in ipairs{'SIGIO', 'SIGCLD', 'SI_DETHREAD', 'SI_TKILL', 'SI_SIGIO', 'SI_ASYNCIO', 'SI_ASYNCNL', 'SI_MESGQ', 'SI_TIMER', 'SI_QUEUE', 'SI_USER', 'SI_KERNEL', 'ILL_ILLOPC', 'ILL_ILLOPN', 'ILL_ILLADR', 'ILL_ILLTRP', 'ILL_PRVOPC', 'ILL_PRVREG', 'ILL_COPROC', 'ILL_BADSTK', 'ILL_BADIADDR', 'FPE_INTDIV', 'FPE_INTOVF', 'FPE_FLTDIV', 'FPE_FLTOVF', 'FPE_FLTUND', 'FPE_FLTRES', 'FPE_FLTINV', 'FPE_FLTSUB', 'FPE_FLTUNK', 'FPE_CONDTRAP', 'SEGV_MAPERR', 'SEGV_ACCERR', 'SEGV_BNDERR', 'SEGV_PKUERR', 'SEGV_ACCADI', 'SEGV_ADIDERR', 'SEGV_ADIPERR', 'SEGV_MTEAERR', 'SEGV_MTESERR', 'SEGV_CPERR', 'BUS_ADRALN', 'BUS_ADRERR', 'BUS_OBJERR', 'BUS_MCEERR_AR', 'BUS_MCEERR_AO', 'CLD_EXITED', 'CLD_KILLED', 'CLD_DUMPED', 'CLD_TRAPPED', 'CLD_STOPPED', 'CLD_CONTINUED', 'POLL_IN', 'POLL_OUT', 'POLL_MSG', 'POLL_ERR', 'POLL_PRI', 'POLL_HUP', 'SIGEV_SIGNAL', 'SIGEV_NONE', 'SIGEV_THREAD', 'SIGEV_THREAD_ID', 'SS_ONSTACK', 'SS_DISABLE'} do
				code = removeEnum(code, k..' = 0')
			end
			--code = removeEnum(code, 'ILL_%w+ = 0')
			--code = removeEnum(code, '__undef_ARG_MAX = 1')
			return code
		end,
	},

	{inc='<sys/param.h>', out='Linux/c/sys/param.lua', final=function(code)
		code = fixEnumsAndDefineMacrosInterleaved(code)
		return code
	end},

	{inc='<sys/time.h>', out='Linux/c/sys/time.lua', final=function(code)
		code = replace_bits_types_builtin(code, 'suseconds_t')
		code = fixEnumsAndDefineMacrosInterleaved(code)
		return code
	end},


	-- TODO
	-- uses a vararg macro which I don't support yet
--	{inc='<sys/sysinfo.h>', out='Linux/c/sys/sysinfo.lua'},

	-- depends on bits/libc-header-start
	-- '<identifier>' expected near '_Complex' at line 2
	-- has to do with enum/define'ing the builtin word _Complex
	{
		inc = '<complex.h>',
		out = 'Linux/c/complex.lua',
		enumGenUnderscoreMacros = true,
		final = function(code)
			code = remove_GLIBC_INTERNAL_STARTING_HEADER_IMPLEMENTATION(code)
			code = commentOutLine(code, 'enum { complex = 0 };')
			code = commentOutLine(code, 'enum { _Mdouble_ = 0 };')

			-- this uses define<=>typedef which always has some trouble
			-- and this uses redefines which luajit ffi cant do so...
			-- TODO from
			--  /* # define _Mdouble_complex_ _Mdouble_ _Complex ### string, not number "_Mdouble_ _Complex" */
			-- to
			--  /* redefining matching value: #define _Mdouble_\t\tfloat */
			-- replace 	_Mdouble_complex_ with double _Complex
			-- from there to
			--  /* # define _Mdouble_		long double ### string, not number "long double" */
			-- replace _Mdouble_complex_ with float _Complex
			-- and from there until then end
			-- replace _Mdouble_complex_ with long double _Complex
			local a = code:find'_Mdouble_complex_ _Mdouble_ _Complex'
			local b = code:find'define _Mdouble_%s*float'
			local c = code:find'define _Mdouble_%s*long double'
			local parts = table{
				code:sub(1,a),
				code:sub(a+1,b),
				code:sub(b+1,c),
				code:sub(c+1),
			}
			parts[2] = parts[2]:gsub('_Mdouble_complex_', 'double _Complex')
			parts[3] = parts[3]:gsub('_Mdouble_complex_', 'float _Complex')
			parts[4] = parts[4]:gsub('_Mdouble_complex_', 'long double _Complex')
			code = parts:concat()

			return code
		end,
	},

	-- apt install libarchive-dev
	{
		inc='<archive.h>',
		moreincs = {
			'<archive_entry.h>',
		},
		out='archive.lua',
		final = function(code)
			code = code .. [[
return require 'ffi.load' 'archive'
]]
			return code
		end,
	},

	-- used by GL, GLES1, GLES2 ...
	{
		inc = '<KHR/khrplatform.h>',
		out = 'Linux/KHR/khrplatform.lua',
	},

	-- included by SDL/SDL_stdinc.h
	-- I'm surprised it's not used more often, has stuff like 'tolower'
	{
		inc = '<ctype.h>',
		out = 'Linux/c/ctype.lua',
	},

}:mapi(function(inc)
	inc.os = 'Linux' -- meh?  just have all these default for -nix systems?
	return inc
end))
-- ]====] End Linux-specific:

-- [====[ Begin OSX-specific:
includeList:append(table{
	{inc='<AvailabilityVersions.h>', out='OSX/c/AvailabilityVersions.lua'},

	-- depends on <AvailabilityVersions.h>
	-- ... SDL.h on OSX separately includes AvailabilityMacros.h without Availability.h
	-- ... and both Availability.h and AvailabilityMacros.h points to AvailabilityVersions.h
	-- (so maybe I could avoid this one file and just let its contents embed into sdl.lua ...)
	{inc='<AvailabilityMacros.h>', out='OSX/c/AvailabilityMacros.lua'},

	-- depends on <AvailabilityMacros.h> and <AvailabilityVersions.h>
	{inc='<Availability.h>', out='OSX/c/Availability.lua'},

	-- used by machine/_types.h and machine/types.h
	-- probably just for i386 processors
	{inc='<i386/_types.h>', out='OSX/c/i386/_types.lua', final=function(code)
		code = removeEnum(code, 'USE_CLANG_%w* = 0')
		return code
	end},

	{inc='<machine/_types.h>', out='OSX/c/machine/_types.lua'},

	{inc='<machine/endian.h>', out='OSX/c/machine/endian.lua', final=function(code)
		code = removeEnum(code, 'USE_CLANG_%w* = 0')
		return code
	end},

	{inc='<sys/_pthread/_pthread_types.h>', out='OSX/c/sys/_pthread/_pthread_types.lua'},

	-- depends on <sys/_pthread/_pthread_types.h> <machine/_types.h>
	{inc='<_types.h>', out='OSX/c/_types.lua', final=function(code)
		code = removeEnum(code, 'USE_CLANG_%w* = 0')
		return code
	end},

	{inc='<sys/_types/_seek_set.h>', out='OSX/c/sys/_types/_seek_set.lua'},

	{inc='<sys/_types/_timespec.h>', out='OSX/c/sys/_types/_timespec.lua'},

	-- depends on <machine/_types.h>
	{inc='<sys/_types/_timeval.h>', out='OSX/c/sys/_types/_timeval.lua', final=function(code)
		code = removeEnum(code, 'USE_CLANG_%w* = 0')
		return code
	end},

	{inc='<sys/_types/_fd_def.h>', out='OSX/c/sys/_types/_fd_def.lua'},

	{inc='<sys/_types/_fd_setsize.h>', out='OSX/c/sys/_types/_fd_setsize.lua'},

	-- used by <sys/stat.h> and <fcntl.h>
	{inc='<sys/_types/_s_ifmt.h>', out='OSX/c/sys/_types/_s_ifmt.lua'},

	-- used by <sys/types.h>, <string.h>, <errno.h>
	{inc='<sys/_types/_errno_t.h>', out='OSX/c/sys/_types/_errno_t.lua'},

	-- depends on <sys/_types/_fd_def.h> <sys/_types/_timeval.h>
	{
		inc = '<sys/_select.h>',
		out = 'OSX/c/sys/_select.lua',
		final = function(code)
			code = fixasm(code)
			return code
		end,
	},

	-- TODO might end up adding sys/_types.h ...
	-- it depends on machine/_types.h

	{inc='<stddef.h>', out='OSX/c/stddef.lua'},

	-- depends on <_types.h> <machine/_types.h>
	{inc='<sys/ioctl.h>', out='OSX/c/sys/ioctl.lua', final=function(code)
		code = fixasm(code)
		code = removeEnum(code, 'USE_CLANG_%w* = 0')
		return code
	end},

	-- depends on <_types.h> <sys/_types/_timespec.h> <sys/_types/_fd_def.h> <machine/_types.h>
	{
		inc='<sys/select.h>',
		out='OSX/c/sys/select.lua',
		final = function(code)
			code = fixasm(code)
			code = removeEnum(code, 'USE_CLANG_%w* = 0')
			return code
		end,
	},

	-- depends on <_types.h> <machine/_types.h>
	{
		inc = '<sys/termios.h>',
		out = 'OSX/c/sys/termios.lua',
		final = function(code)
			code = fixasm(code)
			return code
		end,
	},

	-- depends on <_types.h> <sys/_types/_fd_def.h> <machine/_types.h> <machine/endian.h>
	{inc='<sys/types.h>', out='OSX/c/sys/types.lua', final=function(code)
		code = removeEnum(code, 'USE_CLANG_%w* = 0')
		return code
	end},

	-- depends on <_types.h> <machine/_types.h>
	{
		inc='<string.h>',
		out='OSX/c/string.lua',
		final = function(code)
			code = fixasm(code)
			code = removeEnum(code, 'USE_CLANG_%w* = 0')
			return code
		end,
	},

	-- depends on <_types.h> <sys/_types/_timespec.h> <machine/_types.h>
	{
		inc = '<time.h>',
		out = 'OSX/c/time.lua',
		final = function(code)
			code = fixasm(code)
			code = fixEnumsAndDefineMacrosInterleaved(code)
			code = removeEnum(code, 'USE_CLANG_%w* = 0')
			return code
		end,
	},

	-- depends on <sys/_types/_errno_t.h>
	{
		inc = '<errno.h>',
		out = 'OSX/c/errno.lua',
		final = function(code)
			-- manually add the 'errno' macro at the end:
			code = code .. [[
return setmetatable({
	errno = function()
		return ffi.C.__errno_location()[0]
	end,
}, {
	__index = ffi.C,
})
]]
			return code
		end,
	},

	-- depends on <_types.h>
	{
		inc = '<utime.h>',
		out = 'OSX/c/utime.lua',
		final = function(code)
			code = code .. [[
return setmetatable({
	struct_utimbuf = 'struct utimbuf',
}, {
	__index = ffi.C,
})
]]
			return code
		end,
	},

	-- depends on <_types.h> <sys/_types/_timespec.h> <machine/_types.h>
	{
		inc = '<sys/stat.h>',
		out = 'OSX/c/sys/stat.lua',
		final = function(code)
			code = fixasm(code)
			code = removeEnum(code, 'USE_CLANG_%w* = 0')
			code = code .. [[
local lib = ffi.C
local statlib = setmetatable({
	struct_stat = 'struct stat',
}, {
	__index = lib,
})
-- allow nils instead of errors if we access fields not present (for the sake of lfs_ffi)
ffi.metatype(statlib.struct_stat, {
	__index = function(t,k)
		return nil
	end,
})
return statlib
]]
			return code
		end,
	},

	-- depends on <_types.h> <machine/_types.h>
	{inc='<stdint.h>', out='OSX/c/stdint.lua', final=function(code)
		code = removeEnum(code, 'USE_CLANG_%w* = 0')
		return code
	end},

	-- depends on <machine/_types.h>
	{
		inc = '<sys/signal.h>',
		out='OSX/c/sys/signal.lua',
		final = function(code)
			code = removeEnum(code, 'USE_CLANG_%w* = 0')
			-- [[ #defines within structs ...
			for _,k in ipairs{
				'FP_PREC_24B = 0',
				'FP_PREC_53B = 2',
				'FP_PREC_64B = 3',
				'FP_RND_NEAR = 0',
				'FP_RND_DOWN = 1',
				'FP_RND_UP = 2',
				'FP_CHOP = 3',
			} do
				code = removeEnum(code, k)
			end
			--]]
			return code
		end,
	},

	-- depends on <sys/signal.h>, <_types.h> <machine/_types.h> <machine/endian.h>
	{
		inc = '<stdlib.h>',
		out = 'OSX/c/stdlib.lua',
		final = function(code)
			code = fixasm(code)
			code = removeEnum(code, 'USE_CLANG_%w* = 0')

			-- how come __BLOCKS__ is defined ...
			-- TODO disable __BLOCKS__ to omit these:
			code = string.split(code, '\n'):filter(function(l)
				return not l:find'_b%('
			end):concat'\n'

			return code
		end,
	},

	{inc='<sys/syslimits.h>', out='OSX/c/sys/syslimits.lua'},

	-- depends on <sys/syslimits.h>
	{inc='<limits.h>', out='OSX/c/limits.lua', final=function(code)
		code = removeEnum(code, 'USE_CLANG_%w* = 0')
		return code
	end},

	{inc='<setjmp.h>', out='OSX/c/setjmp.lua'},

	-- depends: <features.h> <machine/_types.h> <sys/_types/_seek_set.h>
	{
		inc = '<unistd.h>',
		out = 'OSX/c/unistd.lua',
		final = function(code)
			code = fixasm(code)
			code = removeEnum(code, 'USE_CLANG_%w* = 0')
			-- for interchangeability with Windows ...
			code = code .. [[
return ffi.C
]]
			return code
		end,
	},

	{inc='<sched.h>', out='OSX/c/sched.lua'},

	{inc='<stdarg.h>', out='OSX/c/stdarg.lua'},

	-- identical in windows linux osx ...
	{
		inc = '<stdbool.h>',
		out = 'OSX/c/stdbool.lua',
		final = function(code)
			-- luajit has its own bools already defined
			for _,k in ipairs{'bool = 0', 'true = 1', 'false = 0'} do
				code = removeEnum(code, k)
			end
			return code
		end,
	},

	-- depends on <machine/_types.h>
	{inc='<inttypes.h>', out='OSX/c/inttypes.lua', final=function(code)
		code = removeEnum(code, 'USE_CLANG_%w* = 0')
		return code
	end},

	{inc='<fcntl.h>', out='OSX/c/fcntl.lua', final=function(code)
		code = fixasm(code)
		code = removeEnum(code, 'USE_CLANG_%w* = 0')
		return code
	end},

	{inc='<sys/mman.h>', out='OSX/c/sys/mman.lua', final=function(code)
		code = fixasm(code)
		code = removeEnum(code, 'USE_CLANG_%w* = 0')
		return code
	end},

	-- depends on <machine/_types.h> <sys/_types/_seek_set.h>
	{
		inc = '<stdio.h>',
		out = 'OSX/c/stdio.lua',
		final = function(code)
			code = fixasm(code)
			code = removeEnum(code, 'USE_CLANG_%w* = 0')
			code = code .. [[
-- special case since in the browser app where I'm capturing fopen for remote requests and caching
-- feel free to not use the returend table and just use ffi.C for faster access
-- but know you'll be losing compatability with browser
return setmetatable({}, {
	__index = ffi.C,
})
]]
			return code
		end,
	},

	-- depends on <stdio.h> <machine/_types.h>
	{
		inc = '<wchar.h>',
		out = 'OSX/c/wchar.lua',
		final = function(code)
			code = fixasm(code)
			code = removeEnum(code, 'USE_CLANG_%w* = 0')
			-- these are duplicated in <wchar.h> and in <stdint.h>
			code = commentOutLine(code, 'enum { WCHAR_MIN = -2147483648 };')
			code = commentOutLine(code, 'enum { WCHAR_MAX = 2147483647 };')
			return code
		end,
	},

	{
		inc = '<math.h>',
		out = 'OSX/c/math.lua',
		final = function(code)
			-- idk how to handle luajit and _Float16 for now so ...
			code = string.split(code, '\n'):filter(function(l)
				return not l:find'_Float16'
			end):concat'\n'
			return code
		end,
	},

	-- depends on <_types.h>
	{
		inc = '<dirent.h>',
		out = 'OSX/c/dirent.lua',
		final = function(code)
			code = fixasm(code)

			-- how come __BLOCKS__ is defined ...
			-- TODO disable __BLOCKS__ to omit these:
			code = string.split(code, '\n'):filter(function(l)
				return not l:find'_b%('
			end):concat'\n'

			return code
		end,
	},

	-- depends on <_types.h> <sys/signal.h>
	{
		inc = '<signal.h>',
		out = 'OSX/c/signal.lua',
		final = function(code)
			code = fixasm(code)
			code = fixEnumsAndDefineMacrosInterleaved(code)
			return code
		end,
	},

	-- depends on <sys/syslimits.h> <machine/_types.h>
	{inc='<sys/param.h>', out='OSX/c/sys/param.lua', final=function(code)
		code = fixEnumsAndDefineMacrosInterleaved(code)
		return code
	end},

	-- depends on <sys/_types/_timespec.h> <sys/_types/_fd_def.h> <machine/_types.h>
	{
		inc = '<sys/time.h>',
		out = 'OSX/c/sys/time.lua',
		final = function(code)
			code = fixasm(code)
			code = fixEnumsAndDefineMacrosInterleaved(code)
			return code
		end,
	},

	{
		inc = '<complex.h>',
		out = 'OSX/c/complex.lua',
		enumGenUnderscoreMacros = true,
		final = function(code)
			for _,k in ipairs{
				'__BEGIN_DECLS = 1',
				'__END_DECLS = 1',
				'__const = 0',
				'__signed = 0',
				'__volatile = 0',
				'__restrict = 0',
				'complex = 0',
			} do
				code = commentOutLine(code, 'enum { '..k..' };')
			end
			return code
		end,
	},

	--[[ TODO vararg problem
	{
		inc = '<pthread.h>',
		out = 'OSX/c/pthread.lua',
		final = function(code)
			code = fixEnumsAndDefineMacrosInterleaved(code)
			return code
		end,
	},
	--]]

	-- used by GL, GLES1, GLES2 ...
	{
		inc = '"KHR/khrplatform.h"',
		out = 'OSX/KHR/khrplatform.lua',
	},
}:mapi(function(inc)
	inc.os = 'OSX'
	return inc
end))
--]====] End OSX-specific:

includeList:append(table{

-- these come from external libraries (so I don't put them in the c/ subfolder)

	{
		-- ok I either need to have my macros smart-detect when their value is only used for types
		-- or someone needs to rewrite the zlib.h and zconf.h to use `typedef` instead of `#define` when specifying types.
		-- until either happens, I'm copying the zlib locally and changing its `#define` types to `typedef`.
		inc = '"zlib/zlib.h"',
		out = 'zlib.lua',
		includedirs = {'.'},
		final = function(code, preproc)
			local code = makeLibWrapper{
				code = code,
				lib = 'z',
				-- add this beneath this top "local ffi = require 'ffi'"
				headerCode = [[
local assert = require 'ext.assert'
]],
				-- add extra type stuff here
				requires = table{
					[=[

if ffi.os == 'Linux' then
	require 'ffi.req' 'c.unistd'
	ffi.cdef[[
typedef long z_off_t;
typedef off_t z_off64_t;
]]
elseif ffi.os == 'OSX' then
	require 'ffi.req' 'c.unistd'
	ffi.cdef[[
typedef off_t z_off_t;
typedef z_off_t z_off64_t;
]]
elseif ffi.os == 'Windows' then
	ffi.cdef[[
typedef long z_off_t;
typedef int64_t z_off64_t;
]]
end]=],
				},
				-- Then add our windows-only symbol if we're not on windows ...
				funcs = ffi.os ~= 'Window' and {
					[=[		gzopen_w = [[gzFile gzopen_w(wchar_t const *path, char const *mode);]], -- Windows-only]=],
				},
				-- ... then add some macros onto the end manually
				footerCode = [=[
-- macros

wrapper.ZLIB_VERSION = ]=]
	..assert.type(preproc.macros.ZLIB_VERSION, 'string') -- macro has quotes in it.
..[=[


function wrapper.zlib_version(...)
	return wrapper.zlibVersion(...)
end

function wrapper.deflateInit(strm)
	return wrapper.deflateInit_(strm, wrapper.ZLIB_VERSION, ffi.sizeof'z_stream')
end

function wrapper.inflateInit(strm)
	return wrapper.inflateInit_(strm, wrapper.ZLIB_VERSION, ffi.sizeof'z_stream')
end

function wrapper.deflateInit2(strm, level, method, windowBits, memLevel, strategy)
	return wrapper.deflateInit2_(strm, level, method, windowBits, memLevel, strategy, wrapper.ZLIB_VERSION, ffi.sizeof'z_stream')
end

function wrapper.inflateInit2(strm, windowBits)
	return wrapper.inflateInit2_(strm, windowBits, wrapper.ZLIB_VERSION, ffi.sizeof'z_stream')
end

function wrapper.inflateBackInit(strm, windowBits, window)
	return wrapper.inflateBackInit_(strm, windowBits, window, wrapper.ZLIB_VERSION, ffi.sizeof'z_stream')
end

-- safe-call wrapper:
function wrapper.pcall(fn, ...)
	local f = assert.index(wrapper, fn)
	local result = f(...)
	if result == wrapper.Z_OK then return true end
	local errs = require 'ext.table'{
		'Z_ERRNO',
		'Z_STREAM_ERROR',
		'Z_DATA_ERROR',
		'Z_MEM_ERROR',
		'Z_BUF_ERROR',
		'Z_VERSION_ERROR',
	}:mapi(function(v) return v, (assert.index(wrapper, v)) end):setmetatable(nil)
	local name = errs[result]
	return false, fn.." failed with error "..result..(name and (' ('..name..')') or ''), result
end

--[[
zlib doesn't provide any mechanism for determining the required size of an uncompressed buffer.
First I thought I'd try-and-fail and look for Z_MEM_ERROR's ... but sometimes you also get other errors like Z_BUF_ERROR.
A solution would be to save the decompressed length alongside the buffer.
From there I could require the caller to save it themselves.  But nah.
Or - what I will do - to keep this a one-stop-shop function -
I will write the decompressed length to the first 8 bytes.
So for C compatability with the resulting data, just skip the first 8 bytes.
--]]
function wrapper.compressLua(src)
	assert.type(src, 'string')
	local srcLen = ffi.new'uint64_t[1]'
	srcLen[0] = #src
	if ffi.sizeof'uLongf' <= 4 and srcLen[0] >= 4294967296ULL then
		error("overflow")
	end
	local dstLen = ffi.new('uLongf[1]', wrapper.compressBound(ffi.cast('uLongf', srcLen[0])))
	local dst = ffi.new('Bytef[?]', dstLen[0])
	assert(wrapper.pcall('compress', dst, dstLen, src, ffi.cast('uLongf', srcLen[0])))

	local srcLenP = ffi.cast('uint8_t*', srcLen)
	local dstAndLen = ''
	for i=0,7 do
		dstAndLen=dstAndLen..string.char(srcLenP[i])
	end
	dstAndLen=dstAndLen..ffi.string(dst, dstLen[0])
	return dstAndLen
end

function wrapper.uncompressLua(srcAndLen)
	assert.type(srcAndLen, 'string')
	-- there's no good way in the zlib api to tell how big this will need to be
	-- so I'm saving it as the first 8 bytes of the data
	local dstLenP = ffi.cast('uint8_t*', srcAndLen)
	local src = dstLenP + 8
	local srcLen = #srcAndLen - 8
	local dstLen = ffi.new'uint64_t[1]'
	dstLen[0] = 0
	for i=7,0,-1 do
		dstLen[0] = bit.bor(bit.lshift(dstLen[0], 8), dstLenP[i])
	end
	if ffi.sizeof'uLongf' <= 4 and dstLen[0] >= 4294967296ULL then
		error("overflow")
	end

	local dst = ffi.new('Bytef[?]', dstLen[0])
	assert(wrapper.pcall('uncompress', dst, ffi.cast('uLongf*', dstLen), src, srcLen))
	return ffi.string(dst, dstLen[0])
end
]=],
			}
			-- zlib libtiff libpng EGL
			code = code:gsub(string.patescape'(void)', '()')
			return code
		end,
	},

	-- apt install libffi-dev
	{inc='<ffi.h>', out='libffi.lua', final=function(code)
		code = [[
-- WARNING, this is libffi, not luajit ffi
-- will that make my stupid ?/?.lua LUA_PATH rule screw things up?  if so then move this file ... or rename it to libffi.lua or something
]] .. code .. [[
return require 'ffi.load' 'ffi'
]]
		return code
	end},

	-- depends: stdbool.h
	-- apt install libgif-dev
	{inc='<gif_lib.h>', out='gif.lua', final=function(code)
		code = [[
]] .. code .. [[
return require 'ffi.load' 'gif'
]]
		return code
	end},

	{
		inc='<fitsio.h>',
		out='fitsio.lua',
		macroincs = {
			'<longnam.h>',
		},
		final=function(code, preproc)
			-- OFF_T is define'd to off_t soo ...
			code = removeEnum(code, 'OFF_T = 0')

			-- I guess this is LLONG_MAX converted from an int64_t into a double...
			-- might wanna FIXME eventually...
			code = removeEnum(code, string.patescape'LONGLONG_MAX = 9.2233720368548e+18')
			code = removeEnum(code, string.patescape'LONGLONG_MIN = -9.2233720368548e+18')
			--FLOATNULLVALUE = -9.11912e-36F	-- don't need because the F at the end makes it fail the enum test....
			code = removeEnum(code, string.patescape'DOUBLENULLVALUE = -9.1191291391491e-36')

			local funcMacros = table()
			-- [[
			local lines = string.split(code, '\n')
			for i=#lines,1,-1 do
				-- TODO if we had symbol access (header() processor within makeLibWrapper)
				--  then I could compare #define targets to symbols and capture accordingly...
				local line = lines[i]
				local to, from = line:match'^/%* #define (fits%S+)%s+(%S+) ###'
				if to then
					funcMacros:insert{to, from}
					lines:remove(i)
				else
					-- the one that doesn't fit the rule
					local to, from = line:match'^/%* #define (ffcpimg)%s+(%S+) ###'
					if to then
						funcMacros:insert{to, from}
						lines:remove(i)
					end
				end
			end
			code = lines:concat'\n'

			for _,kv in ipairs(funcMacros) do
				local new, old = table.unpack(kv)
				code = removeEnum(code, new..' = 0')
			end

			-- TODO autogen this from /usr/include/longnam.h
			-- TODO TODO autogen all macro function mappings, not just this one
			code = makeLibWrapper{
				code = code,
				preproc = preproc,
				lib = 'cfitsio',
-- [===[ adding as funcs means upon first reference, it'll defer-load the target and replace it with the source
				funcs = table{
					'',
				}:append(funcMacros:mapi(function(kv)
					local new, old = table.unpack(kv)
					return '\t\t' .. new .. ' = function() return wrapper.' .. old .. ' end,'
				end)),
--]===]
				footerCode = table{
					'-- macros',
					'',
				}
--[===[ adding as macros is a bad idea cuz the redirect will be permanent
				:append(
					funcMacros:mapi(function(kv)
						local new, old = table.unpack(kv)
						return 'wrapper.'..new .. ' = function(...) return wrapper.' .. old .. '(...) end'
					end)
				)
--]===]
				:append{
					'wrapper.CFITSIO_VERSION = "'..preproc.macros.CFITSIO_VERSION..'"',
					--[[ using limits' def won't work until it gets its enums fixed...
					'wrapper.LONGLONG_MAX = ffi.C.LLONG_MAX',
					'wrapper.LONGLONG_MIN = ffi.C.LLONG_MIN',
					--]]
					-- [[ until then
					'wrapper.LONGLONG_MAX = 0x7fffffffffffffffLL',
					'wrapper.LONGLONG_MIN = -0x7fffffffffffffffLL-1',
					--]]
					'wrapper.FLOATNULLVALUE = -9.11912e-36',
					'wrapper.DOUBLENULLVALUE = -9.1191291391491e-36',
					"wrapper.fits_open_file = function(...) return wrapper.ffopentest(wrapper.CFITSIO_SONAME, ...) end",
				}:concat'\n',
			}
			-- zlib libtiff libpng EGL fitsio
			code = code:gsub(string.patescape'(void)', '()')
			return code
		end,
	},

	-- apt install libnetcdf-dev
	{
		inc = '<netcdf.h>',
		out = 'netcdf.lua',
		pkgconfig = 'netcdf',
		final = function(code)
			code = code .. [[
return require 'ffi.load' 'netcdf'
]]
			return code
		end,
	},

	-- apt install libhdf5-dev
	-- depends: inttypes.h
	{
		inc = '<hdf5.h>',
		out = 'hdf5.lua',
		pkgconfig = 'hdf5',
		final = function(code)
			-- old header comment:
				-- for gcc / ubuntu looks like off_t is defined in either unistd.h or stdio.h, and either are set via testing/setting __off_t_defined
				-- in other words, the defs in here are getting more and more conditional ...
				-- pretty soon a full set of headers + full preprocessor might be necessary
				-- TODO regen this on Windows and compare?
			code = code .. [[
return require 'ffi.load' 'hdf5'	-- pkg-config --libs hdf5
]]
			return code
		end,
		-- ffi.load override information
		-- TODO somehow insert this into ffi/load.lua without destroying the file
		-- don't modify require 'ffi.load' within 'ffi.hdf5', since the whole point of fif.load is for the user to provide overrides to the lib loc that the header needs.
		ffiload = {
			hdf5 = {Linux = '/usr/lib/x86_64-linux-gnu/hdf5/serial/libhdf5.so'},
		},
	},

	-- depends on: stdio.h stdint.h stdarg.h stdbool.h
	{
		-- cimgui has these 3 files together:
		-- OpenGL i had to separate them
		-- and OpenGL i put them in OS-specific place
		inc = '"cimgui.h"',
		out = 'cimgui.lua',
		moreincs = {
			'"imgui_impl_sdl2.h"',
			'"imgui_impl_opengl3.h"',
		},
		silentincs = {'"imgui.h"'},	-- full of C++ so don't include it
		includedirs = {
			'/usr/local/include/imgui-1.90.5dock',
		},
		macros = {
			'CIMGUI_DEFINE_ENUMS_AND_STRUCTS',
		},
		final = function(code)
			-- this is already in SDL
			code = safegsub(code,
				string.patescape'struct SDL_Window;'..'\n'
				..string.patescape'struct SDL_Renderer;'..'\n'
				..string.patescape'struct _SDL_GameController;'..'\n'
				..string.patescape'typedef union SDL_Event SDL_Event;',

				-- simultaneously insert require to ffi/sdl.lua
				"]] require 'ffi.req' 'sdl2' ffi.cdef[["
			)

			-- looks like in the backend file there's one default parameter value ...
			code = safegsub(code, 'glsl_version = nullptr', 'glsl_version')

			code = safegsub(code, 'enum ImGui_ImplSDL2_GamepadMode {([^}]-)};', 'typedef enum {%1} ImGui_ImplSDL2_GamepadMode;')
			code = safegsub(code, string.patescape'manual_gamepads_array = ((void *)0)', 'manual_gamepads_array')
			code = safegsub(code, string.patescape'manual_gamepads_count = -1', 'manual_gamepads_count')

			code = code .. [[
return require 'ffi.load' 'cimgui_sdl'
]]
			return code
		end,
	},

	{
		inc = '<CL/opencl.h>',
		out = 'OpenCL.lua',
		final = function(code)
			code = commentOutLine(code, 'warning: Need to implement some method to align data here')

			-- ok because I have more than one inc, the second inc points back to the first, and so we do create a self-reference
			-- so fix it here:
			--code = safegsub(code, string.patescape"]] require 'ffi.req' 'OpenCL' ffi.cdef[[\n", "")

			code = code .. [[
return require 'ffi.load' 'OpenCL'
]]
			return code
		end,
	},

-- these external files are per-OS
-- maybe eventually all .h's will be?


	-- apt install libtiff-dev
	-- also per-OS
	-- depends: stddef.h stdint.h inttypes.h stdio.h stdarg.h
	{
		inc = '<tiffio.h>',
		out = 'tiff.lua',
		pkgconfig = 'libtiff-4',
		includedirs = ffi.os == 'OSX' and {
			'/usr/local/opt/libtiff/include',
		} or nil,
		-- [[ someone somewhere is getting mixed up because of symlinks so ...
		macroincs = {
			'/usr/local/opt/libtiff/include/tiff.h',
			'/usr/local/opt/libtiff/include/tiffconf.h',
			'/usr/local/opt/libtiff/include/tiffvers.h',
		},
		--]]
		--[[ can we fix it with include search paths? no...
		macroincs = {
			'<tiffconf.h>',
		},
		--]]
		final = function(code, preproc)
			for _,k in ipairs{'int8', 'uint8', 'int16', 'uint16', 'int32', 'uint32', 'int64', 'uint64'} do
				code = safegsub(code, string.patescape('typedef '..k..'_t '..k..' __attribute__((deprecated));'), '')
			end
			for _,k in ipairs{
				'U_NEU', 'V_NEU', 'UVSCALE'
				-- unnecessary:
				--'D65_X0', 'D65_Y0', 'D65_Z0', 'D50_X0', 'D50_Y0', 'D50_Z0',
			} do
				code = removeEnum(code, k..' = %S+')
			end
			local code = makeLibWrapper{
				code = code,
				preproc = preproc,
				lib = 'tiff',
				funcs = ffi.os ~= 'Windows' and {
[=[

		-- Windows-only ...
		TIFFOpenW = [[TIFF *TIFFOpenW(wchar_t const *, char const *);]],
		TIFFOpenWExt = [[TIFF *TIFFOpenWExt(wchar_t const *, char const *, TIFFOpenOptions *opts);]],]=]
				} or nil,
				footerCode = table{
					'-- macros',
					'',
					}:append(table{
							'TIFFLIB_VERSION_STR', 'TIFFLIB_VERSION_STR_MAJ_MIN_MIC', 'D65_X0', 'D65_Y0', 'D65_Z0', 'D50_X0', 'D50_Y0', 'D50_Z0', 'U_NEU', 'V_NEU', 'UVSCALE',
						}:mapi(function(k)
							local v = preproc.macros[k]
							v = v:match'^%((.*)F%)$' or v	-- get rid of those ( ... F) floats
							return 'wrapper.'..k..' = '..v
						end)
					):concat'\n'..'\n',
			}
			-- zlib libtiff libpng EGL
			code = code:gsub(string.patescape'(void)', '()')
			return code
		end,
	},

	-- apt install libjpeg-turbo-dev
	-- linux is using 2.1.2 which generates no different than 2.0.3
	--  based on apt package libturbojpeg0-dev
	-- windows is using 2.0.4 just because 2.0.3 and cmake is breaking for msvc
	{
		inc = '<jpeglib.h>',
		macroincs = {
			-- these are for the macro preprocessor to know what macros to keep for emitting into enums, vs which to throw out
			'<jconfig.h>',
			'<jmorecfg.h>',
		},
		out = 'jpeg.lua',
		final = function(code, preproc)
			return makeLibWrapper{
				code = code,
				lib = 'jpeg',
				requires = {
					"require 'ffi.req' 'c.stdio'	-- for FILE, even though jpeglib.h itself never includes <stdio.h> ... hmm ...",

					-- I guess I have to hard-code the OS-specific typedef stuff that goes in the header ...
					-- and then later gsub out these typedefs in each OS that generates it...
					[=[

-- TODO does this discrepency still exist in Windows' LibJPEG Turbo 3.0.4 ?
if ffi.os == 'Windows' then
	ffi.cdef[[
typedef unsigned char boolean;
typedef signed int INT32;
]]
else
	ffi.cdef[[
typedef long INT32;
typedef int boolean;
]]
end]=]
				},
				footerCode = [[

-- these are #define's in jpeglib.h

wrapper.LIBJPEG_TURBO_VERSION = ']]
	..assert.type(preproc.macros.LIBJPEG_TURBO_VERSION, 'string')
	..[['

function wrapper.jpeg_create_compress(cinfo)
	return wrapper.jpeg_CreateCompress(cinfo, wrapper.JPEG_LIB_VERSION, ffi.sizeof'struct jpeg_compress_struct')
end

function wrapper.jpeg_create_decompress(cinfo)
	return wrapper.jpeg_CreateDecompress(cinfo, wrapper.JPEG_LIB_VERSION, ffi.sizeof'struct jpeg_decompress_struct')
end
]]
			}
		end,
		ffiload = {
			jpeg = {
				-- For Windows msvc turbojpeg 2.0.3 cmake wouldn't build, so i used 2.0.4 instead
				-- I wonder if this is the reason for the few subtle differences
				-- TODO rebuild linux with 2.0.4 and see if they go away?
				Windows = 'jpeg8',
				-- for Linux, libturbojpeg 2.1.2 (which is not libjpeg-turbo *smh* who named this)
				-- the header generated matches libturbojpeg 2.0.3 for Ubuntu ... except the version macros
			},
		},
	},

	-- inc is put last before flags
	-- but inc is what the make.lua uses
	-- so this has to be built make.lua GL/glext.h
	-- but that wont work either cuz that will make the include to GL/glext.h into a split out file (maybe it should be?)
	-- for Windows I've got my glext.h outside the system paths, so you have to add that to the system path location.
	-- notice that GL/glext.h depends on GLenum to be defined.  but gl.h include glext.h.  why.
	{
		inc =
		--[[ OSX ... but I'm putting it in local space cuz bleh framework namespace resolution means include pattern-matching, not appending like typical search paths use ... so until fixing the include resolution ...
			ffi.os == 'OSX' and '"OpenGL/gl.h"' or
		--]] -- osx brew mesa usees GL/gl.h instead of the crappy builtin OSX GL
			'<GL/gl.h>',
		moreincs =
		--[[
			ffi.os == 'OSX' and {'"OpenGL/glext.h"'} or
		--]]
			{'<GL/glext.h>'},
		--[[
		includedirs = ffi.os == 'OSX' and {'.'} or nil,
		--]]
		out = ffi.os..'/OpenGL.lua',
		os = ffi.os,
		--[[ TODO -framework equivalent ...
		includeDirMapping = ffi.os == 'OSX' and {
			{['^OpenGL/(.*)$'] = '/Library/Developer/CommandLineTools/SDKs/MacOSX13.3.sdk/System/Library/Frameworks/OpenGL.framework/Versions/A/Headers/%1'},
		} or nil,
		--]]	-- or not now that I'm using osx brew mesa instead of builtin crappy GL
		skipincs = ffi.os == 'Windows' and {
		-- trying to find out why my gl.h is blowing up on windows
			'<winapifamily.h>',	-- verify please
			'<sdkddkver.h>',
			'<excpt.h>',
			--'<windef.h>',
			--'<minwindef.h>',
			--'<winbase.h>',
			'<windows.h>',
			--'<minwindef.h>',
			'<winnt.h>',
			'<winerror.h>',
			'<stdarg.h>',
			'<specstrings.h>',
			'<apiset.h>',
			'<debugapi.h>',
		} or nil,
		macros = table{
			'GL_GLEXT_PROTOTYPES',
		}:append(ffi.os == 'Windows' and {
			'WINGDIAPI=',
			'APIENTRY=',
		} or nil),
		final = function(code)
			if ffi.os == 'Windows' then
				-- TODO this won't work now that I'm separating out KHRplatform.h ...
				local oldcode = code
				code = "local code = ''\n"
				code = code .. safegsub(oldcode,
					string.patescape'ffi.cdef',
					'code = code .. '
				)
				code = code .. [[
ffi.cdef(code)
local gl = require 'ffi.load' 'GL'
return setmetatable({
	code = code,	-- Windows GLApp needs to be able to read the ffi.cdef string for parsing out wglGetProcAddress's
}, {__index=gl})
]]
			else
				code = code .. [[
return require 'ffi.load' 'GL'
]]
			end
			return code
		end,
	},

	{
		inc = '<lua.h>',
		moreincs = {'<lualib.h>', '<lauxlib.h>'},
		out = 'lua.lua',
		pkgconfig = 'lua',
		final = function(code)
			code = [[
]] .. code .. [[
return require 'ffi.load' 'lua'
]]
			return code
		end,
	},

	-- depends on complex.h
	{inc='<cblas.h>', out='cblas.lua', final=function(code)
		code = [[
]] .. code .. [[
return require 'ffi.load' 'openblas'
]]
		return code
	end},

	{
		inc = '<lapack.h>',
		out = 'lapack.lua',
		pkgconfig = 'lapack',
		final = function(code)
			-- needs lapack_int replaced with int, except the enum def line
			-- the def is conditional, but i think this is the right eval ...
			code = safegsub(code, 'enum { lapack_int = 0 };', 'typedef int32_t lapack_int;')
--[[
#if defined(LAPACK_ILP64)
#define lapack_int		int64_t
#else
#define lapack_int		int32_t
#endif
--]]

			-- preproc on this generate a *LOT* of `enum { LAPACK_lsame_base = 0 };`
			-- they are generated from macro calls to LAPACK_GLOBAL
			-- which is defined as
			-- #define LAPACK_GLOBAL(lcname,UCNAME)  lcname##_
			-- ... soo ... I need to not gen enums for macros that do string manipulation or whatever
			code = safegsub(code, 'enum { LAPACK_[_%w]+ = 0 };', '')
			code = safegsub(code, '\n\n', '\n')

			code = code .. [[
return require 'ffi.load' 'lapack'
]]
			return code
		end,
	},

	{
		inc = '<lapacke.h>',
		out = 'lapacke.lua',
		pkgconfig = 'lapacke',
		final = function(code)
			code = code .. [[
return require 'ffi.load' 'lapacke'
]]
		return code
		end,
	},

	-- libzip-dev
	-- TODO #define ZIP_OPSYS_* is hex values, should be enums, but they are being commented out ...
	-- because they have 'u' suffixes
	-- same with some other windows #defines
	-- any that have u i etc i32 i64 etc are being failed by my parser.
	{
		inc = '<zip.h>',
		macroincs = {
			-- these are for the macro preprocessor to know what macros to keep for emitting into enums, vs which to throw out
			'<zipconf.h>'
		},
		out = 'zip.lua',
		final = function(code, preproc)
			-- I'll just put these in the macros since they don't fit in luajit enums ...
			code = removeEnum(code, 'ZIP_INT64_MAX = [^\n]*')
			code = removeEnum(code, 'ZIP_UINT64_MAX = [^\n]*')
			-- TODO get ZIP_UINT32_MAX working
			return makeLibWrapper{
				code = code,
				preproc = preproc,
				lib = 'zip',
				footerCode = [[
-- macros

wrapper.LIBZIP_VERSION = ]]..preproc.macros.LIBZIP_VERSION..'\n'..[[
wrapper.ZIP_INT64_MAX = ]]..preproc.macros.ZIP_INT64_MAX..'\n'..[[
wrapper.ZIP_UINT64_MAX = ]]..preproc.macros.ZIP_UINT64_MAX..'\n'..[[
]]
			}
		end,
	},

	-- produces an "int void" because macro arg-expansion covers already-expanded macro-args
	{
		inc = '<png.h>',
		out = 'png.lua',
		macroincs = {
			'<pngconf.h>',
			'<pnglibconf.h>',
		},
		final = function(code, preproc)
			-- TODO remove contents of pnglibconf.h, or at least the PNG_*_SUPPORTED macros

			-- still working out macro bugs ... if macro expands arg A then I don't want it to expand arg B
			--code = safegsub(code, 'int void', 'int type');

			local code = makeLibWrapper{
				code = code,
				preproc = preproc,
				lib = 'png',
				footerCode = [[
-- macros

wrapper.PNG_LIBPNG_VER_STRING = ]]..preproc.macros.PNG_LIBPNG_VER_STRING..'\n'..[[
wrapper.PNG_HEADER_VERSION_STRING =  ' libpng version '..wrapper.PNG_LIBPNG_VER_STRING..'\n'

-- this is a value in C but a function in Lua
function wrapper.png_libpng_ver() return wrapper.png_get_header_ver(nil) end

wrapper.PNG_GAMMA_THRESHOLD = wrapper.PNG_GAMMA_THRESHOLD_FIXED * .00001

]],
			}
			-- zlib libtiff libpng EGL
			code = code:gsub(string.patescape'(void)', '()')
			return code
		end,
	},

	-- TODO STILL
	-- looks like atm i'm using a hand-rolled sdl anyways
	--[[
TODO:
sdl.h
- comment out: 'enum { SDLCALL = 1 };'
- comment out: 'enum { SDL_INLINE = 0 };'
- comment out: 'enum { SDL_HAS_FALLTHROUGH = 0 };'
- comment out: 'enum { SIZEOF_VOIDP = 8 };'
- comment out: 'enum { STDC_HEADERS = 1 };'
- comment out: 'enum { HAVE_.* = 1 };'
- comment out: 'enum { SDL_.*_h_ = 1 };'
- comment out: ... just do everything in SDL_config.h
- comment out: ... everything in float.h
	SDL_PRINTF_FORMAT_STRING
	SDL_SCANF_FORMAT_STRING
	DUMMY_ENUM_VALUE
	SDLMAIN_DECLSPEC
	SDL_FUNCTION
	SDL_FILE
	SDL_LINE
	SDL_NULL_WHILE_LOOP_CONDITION
	SDL_assert_state
	SDL_assert_data
	SDL_LIL_ENDIAN
	SDL_BIG_ENDIAN
	SDL_BYTEORDER
	SDL_FLOATWORDORDER
	HAS_BUILTIN_*
	HAS_BROKEN_.*
	SDL_SwapFloat function
	SDL_MUTEX_TIMEOUT
	SDL_RWOPS_*
	RW_SEEK_*
	AUDIO_*
	SDL_Colour
	SDL_BlitSurface
	SDL_BlitScaled
... can't use blanket comment of *_h because of sdl keycode enum define
but you can in i think all other files ...
also HDF5 has a lot of unused enums ...
	--]]
	{
		inc = '<SDL2/SDL.h>',
		out = 'sdl2.lua',
		pkgconfig = 'sdl2',
		includedirs = ffi.os == 'Windows' and {os.home()..'/SDL2'} or nil,
		skipincs = (ffi.os == 'Windows' or ffi.os == 'OSX') and {'<immintrin.h>'} or {},
		silentincs = (ffi.os == 'Windows' or ffi.os == 'OSX') and {} or {'<immintrin.h>'},
		final = function(code)
			code = commentOutLine(code, 'enum { SDL_begin_code_h = 1 };')

			-- TODO comment out SDL2/SDL_config.h ... or just put it in silentincs ?
			-- same with float.h

			-- TODO evaluate this and insert it correctly?
			code = code .. [=[
ffi.cdef[[
// these aren't being generated correctly so here they are:
enum { SDL_WINDOWPOS_UNDEFINED = 0x1FFF0000u };
enum { SDL_WINDOWPOS_CENTERED = 0x2FFF0000u };
]]
]=]

			code = code .. [[
return require 'ffi.load' 'SDL2'
]]
			return code
		end,
	},

	{
		inc = '<SDL3/SDL.h>',
		out = 'sdl3.lua',
		pkgconfig = 'sdl3',
		includedirs = ffi.os == 'Windows' and {os.home()..'/SDL2'} or nil,
		skipincs = (ffi.os == 'Windows' or ffi.os == 'OSX') and {'<immintrin.h>'} or {},
		silentincs = (ffi.os == 'Windows' or ffi.os == 'OSX') and {} or {'<immintrin.h>'},
		final = function(code)
			code = commentOutLine(code, 'enum { SDL_begin_code_h = 1 };')

			-- TODO comment out SDL3/SDL_config.h ... or just put it in silentincs ?
			-- same with float.h

			-- TODO evaluate this and insert it correctly?
			code = code .. [=[
ffi.cdef[[
// these aren't being generated correctly so here they are:
enum { SDL_WINDOWPOS_UNDEFINED = 0x1FFF0000u };
enum { SDL_WINDOWPOS_CENTERED = 0x2FFF0000u };
]]
]=]

			code = code .. [[
return require 'ffi.load' 'SDL3'
]]
			return code
		end,
	},
	{
		inc = '<ogg/ogg.h>',
		-- build this separately for each OS.
		-- generate the os splitter file
		out = ffi.os..'/ogg.lua',
		os = ffi.os,
	},

	{
		inc = '<vorbis/codec.h>',
		out = 'vorbis/codec.lua',
	},
	{
		inc = '<vorbis/vorbisfile.h>',
		out = 'vorbis/vorbisfile.lua',
		includedirs = {
			'/usr/include/vorbis',
			'/usr/local/include/vorbis',
		},
		final = function(code)
			-- the result contains some inline static functions and some static struct initializers which ffi cdef can't handle
			-- ... I need to comment it out *HERE*.
			code = safegsub(code, 'static int _ov_header_fseek_wrap%b()%b{}', '')
			code = safegsub(code, 'static ov_callbacks OV_CALLBACKS_[_%w]+ = %b{};', '')

			code = code .. [[
local lib = require 'ffi.load' 'vorbisfile'

-- don't use stdio, use ffi.C
-- stdio risks browser shimming open and returning a Lua function
-- but what that means is, for browser to work with vorbisfile,
-- browser will have to shim each of he OV_CALLBACKs
-- ... or browser should/will have to return ffi closures of ffi.open
-- ... then we can use stdio here
local stdio = require 'ffi.req' 'c.stdio'	-- fopen, fseek, fclose, ftell

-- i'd free the closure but meh
-- who puts a function as a static in a header anyways?
local _ov_header_fseek_wrap = ffi.cast('int (*)(void *, ogg_int64_t, int)', function(f,off,whence)
	if f == nil then return -1 end
	return stdio.fseek(f,off,whence)
end)

local OV_CALLBACKS_DEFAULT = ffi.new'ov_callbacks'
OV_CALLBACKS_DEFAULT.read_func = stdio.fread
OV_CALLBACKS_DEFAULT.seek_func = _ov_header_fseek_wrap
OV_CALLBACKS_DEFAULT.close_func = stdio.fclose
OV_CALLBACKS_DEFAULT.tell_func = stdio.ftell

local OV_CALLBACKS_NOCLOSE = ffi.new'ov_callbacks'
OV_CALLBACKS_NOCLOSE.read_func = stdio.fread
OV_CALLBACKS_NOCLOSE.seek_func = _ov_header_fseek_wrap
OV_CALLBACKS_NOCLOSE.close_func = nil
OV_CALLBACKS_NOCLOSE.tell_func = stdio.ftell

local OV_CALLBACKS_STREAMONLY = ffi.new'ov_callbacks'
OV_CALLBACKS_STREAMONLY.read_func = stdio.fread
OV_CALLBACKS_STREAMONLY.seek_func = nil
OV_CALLBACKS_STREAMONLY.close_func = stdio.fclose
OV_CALLBACKS_STREAMONLY.tell_func = nil

local OV_CALLBACKS_STREAMONLY_NOCLOSE = ffi.new'ov_callbacks'
OV_CALLBACKS_STREAMONLY_NOCLOSE.read_func = stdio.fread
OV_CALLBACKS_STREAMONLY_NOCLOSE.seek_func = nil
OV_CALLBACKS_STREAMONLY_NOCLOSE.close_func = nil
OV_CALLBACKS_STREAMONLY_NOCLOSE.tell_func = nil

return setmetatable({
	OV_CALLBACKS_DEFAULT = OV_CALLBACKS_DEFAULT,
	OV_CALLBACKS_NOCLOSE = OV_CALLBACKS_NOCLOSE,
	OV_CALLBACKS_STREAMONLY = OV_CALLBACKS_STREAMONLY,
	OV_CALLBACKS_STREAMONLY_NOCLOSE = OV_CALLBACKS_STREAMONLY_NOCLOSE,
}, {
	__index = lib,
})
]]
			return code
		end,
	},

	{
		inc = '<EGL/egl.h>',
		out = 'EGL.lua',
		--[[ TODO I'm trying hard to get KHR/khrplatform.h to be substituted by the preprocessor as a lua-require ...
		includedirs = ffi.os == 'OSX' and {
			'/usr/local/include',
		} or nil,
		--]]
		final = function(code, preproc)
			code = removeEnum(code, 'EGL_FOREVER = 0xffffffffffffffff')
			code = makeLibWrapper{
				code = code,
				preproc = preproc,
				lib = 'EGL',
				requires = {
[===[

-- I'm guessing this is a difference of OS's and not a difference of EGL versions because the header version says it is the same, but the Linux build did void* while the OSX build did int ...
if ffi.os == 'OSX' then
	ffi.cdef[[
typedef int EGLNativeDisplayType;
typedef void *EGLNativePixmapType;
typedef void *EGLNativeWindowType;
]]
else
	ffi.cdef[[
typedef void *EGLNativeDisplayType;
typedef khronos_uintptr_t EGLNativePixmapType;
typedef khronos_uintptr_t EGLNativeWindowType;
]]
end]===]
				},
				footerCode = [[
-- macros

wrapper.EGL_DONT_CARE = ffi.cast('EGLint', -1)
wrapper.EGL_NO_CONTEXT = ffi.cast('EGLDisplay', 0)
wrapper.EGL_NO_DISPLAY = ffi.cast('EGLDisplay', 0)
wrapper.EGL_NO_SURFACE = ffi.cast('EGLSurface', 0)
wrapper.EGL_UNKNOWN = ffi.cast('EGLint', -1)
wrapper.EGL_DEFAULT_DISPLAY = ffi.cast('EGLNativeDisplayType', 0)
wrapper.EGL_NO_SYNC = ffi.cast('EGLSync', 0)
wrapper.EGL_NO_IMAGE = ffi.cast('EGLImage', 0)
wrapper.EGL_FOREVER = 0xFFFFFFFFFFFFFFFFULL
]],
			}
			code = code:gsub(string.patescape'(void)', '()')
			return code
		end,
	},
	{
		inc = '<GLES/gl.h>',
		out = 'OpenGLES1.lua',
		final = function(code)
			return code .. [[
return require 'ffi.load' 'GLESv1_CM'
]]
		end,
	},
	{
		inc = '<GLES2/gl2.h>',
		out = 'OpenGLES2.lua',
		final = function(code)
			return code .. [[
return require 'ffi.load' 'GLESv2'
]]
		end,
	},
	{
		inc = '<GLES3/gl3.h>',
		out = 'OpenGLES3.lua',
		final = function(code)
			-- why don't I have a GLES3 library when I have GLES3 headers?
			return code .. [[
return require 'ffi.load' 'GLESv2'
]]
		end,
	},
	{
		inc = ffi.os ~= 'OSX'
			and '<AL/al.h>'
			or '"OpenAL/OpenAL.h"',	-- bleh too tired to go through the same struggles as with OpenGL on OSX ...
		moreincs = {
			'<AL/alc.h>',
		},
		out = 'OpenAL.lua',
		final = function(code)
			return code .. [[
return require 'ffi.load' 'openal'
]]
		end,
		ffiload = {
			openal = {Windows = 'OpenAL32'},
		},
	},

	{
		inc = '<Python.h>',
		out = 'python.lua',
		pkgconfig = 'python3',
		--[[
		includedirs = {
			'/usr/include/python3.11',
			'/usr/include/x86_64-linux-gnu/python3.11',
		},
		--]]
		macros = {
			'__NO_INLINE__',
			'PIL_NO_INLINE',
		},
	},

--[=[	TODO how about a flag for skipping a package in `make.lua all` ?
	{
		inc = '<mono/jit/jit.h>',
		out = 'mono.lua',
		pkgconfig = 'mono-2',
		final = function(code)
			-- enums are ints right ... ?
			code = safegsub(code, 'typedef (enum %b{})%s*([_%a][_%w]*);', '%1; typedef int %2;')
			-- these are interleaved in another enum ...
			code = safegsub(code, 'enum { MONO_TABLE_LAST = 0 };', ' ')
			code = safegsub(code, 'enum { MONO_TABLE_NUM = 1 };', ' ')
			-- pkg-config --libs mono-2
			-- -L/usr/lib/pkgconfig/../../lib -lmono-2.0 -lm -lrt -ldl -lpthread
			-- return require 'ffi.load' 'mono-2.0' ... failed to find it
			-- return require 'ffi.load' '/usr/lib/libmono-2.0.so' ... /usr/lib/libmono-2.0.so: undefined symbol: _ZTIPi
			code = code .. [[
ffi.load('/usr/lib/x86_64-linux-gnu/libstdc++.so.6', true)
return ffi.load '/usr/lib/libmono-2.0.so'
]]
			return code
		end,
	},
--]=]

	{
		inc = '<pulse/pulseaudio.h>',
		out = 'pulse.lua',
		final = function(code)
			-- so this spits out enums for both enums and #define's
			-- that runs us into trouble sometimes ...
			local lines = string.split(code, '\n')
			local definedEnums = {}
			for i=1,#lines do
				local line = lines[i]
				if line:match'^typedef enum' then
					for w in line:gmatch'%S+' do
						if w:match'^PA_' then
							if w:match',$' then w = w:sub(1,-2) end
--io.stderr:write('defining typedef enum '..w..'\n')
							definedEnums[w] = true
						end
					end
				end
				local prefix, enumName = line:match'^(.*)enum { (.*) = 0 };$'
				if enumName then
--io.stderr:write('found enum=0 name '..enumName..'\n')
					if definedEnums[enumName] then
--io.stderr:write('...removing\n')
						lines[i] = prefix
					end
				end
			end
			code = lines:concat'\n'
			-- undefs of static inline functions ...
			for f in ([[PA_CONTEXT_IS_GOOD PA_STREAM_IS_GOOD PA_SINK_IS_OPENED PA_SOURCE_IS_OPENED]]):gmatch'%S+' do
				code = removeStaticInlineFunction(code, f)
				code = safegsub(code, 'enum { '..f..' = 0 };', '')
			end
			return code
		end,
	},

	{
		inc = '<vulkan/vulkan_core.h>',
		out = 'vulkan.lua',
		includedirs = {
			'/usr/include/vulkan',
			'/usr/include/vk_video',
		},
		final = function(code)
			local postdefs = table()
			code = code:gsub('static const (%S+) (%S+) = ([0-9x]+)ULL;\n',
				-- some of these rae 64bit numbers ... I should put them in lua tables as uint64_t's
				--'enum { %2 = %3 };'
				function(ctype, name, value)
					postdefs:insert(name.." = ffi.new('"..ctype.."', "..value..")")
					return ''
				end
			)
			code = code .. '\n'
				.."local lib = require 'ffi.load' 'vulkan'\n"
				.."return setmetatable({\n"
				..postdefs:mapi(function(l) return '\t'..l..',' end):concat'\n'..'\n'
				.."}, {__index=lib})\n"
			return code
		end,
	},

	-- based on some c bindings I wrote for https://github.com/dacap/clip
	-- which maybe I should also put on github ...
	{
		inc = '<cclip.h>',
		out = 'cclip.lua',
		final = function(code)
			code = code .. '\n'
				.."return require 'ffi.load' 'clip'\n"
			return code
		end,
	},

	{	-- libelf
		inc = '<gelf.h>',		-- gelf.h -> libelf.h -> elf.h
		moreincs = {
			'<elfutils/version.h>',
			'<elfutils/elf-knowledge.h>',
		},
		-- there's also elfutils/elf-knowledge.h and elfutils/version.h ...
		out = 'elf.lua',
		final = function(code)
			-- #define ELF_F_DIRTY ELF_F_DIRTY before enum ELF_F_DIRTY causes this:
			code = removeEnum(code, 'ELF_F_DIRTY = 0')
			code = removeEnum(code, 'ELF_F_LAYOUT = 0')
			code = removeEnum(code, 'ELF_F_PERMISSIVE = 0')
			code = removeEnum(code, 'ELF_CHF_FORCE = 0')
			code = code .. '\n'
				.."return require 'ffi.load' 'elf'\n"
			return code
		end,
	},

	{
		inc = '<tensorflow/c/c_api.h>',
		out = 'tensorflow.lua',
		-- tensorflow is failing when it includes <string.h>, which is funny because I already generate <string.h> above
		-- something in it is pointing to <secure/_string.h>, which is redefining memcpy ... which is breaking my parser (tho it shouldnt break, but i don't want to fix it)
		skipincs = (ffi.os == 'OSX') and {'<string.h>'} or {},
		final = function(code)
			code = code .. [[
return require 'ffi.load' 'tensorflow'
]]
			return code
		end,
	},
})

-- now detect any duplicate #include paths and make sure they are going to distinct os-specific destination file names
-- and in those cases, add in a splitting file that redirects to the specific OS
local detectDups = {}
for _,inc in ipairs(includeList) do
	detectDups[inc.inc] = detectDups[inc.inc] or {}
	local det = detectDups[inc.inc][inc.os or 'all']
	if det then
		print("got two entries that have matching include name, and at least one is not os-specific: "..tolua{
			det,
			inc,
		})
	end
	detectDups[inc.inc][inc.os or 'all'] = inc
end
for incname, det in pairs(detectDups) do
	if type(det) == 'table' then
		local keys = table.keys(det)
		-- if we had more than 1 key
		if #keys > 1
		then
			local base
			for os,inc in pairs(det) do
				assert(inc.os, "have a split file and one entry doesn't have an os... "..tolua(inc))
				local incbase = inc.out:match('^'..inc.os..'/(.*)$')
				if not incbase then
					error("expected os "..tolua(inc.os).." prefix, bad formatted out for "..tolua(inc))
				end
				if base == nil then
					base = incbase
				else
					assert(incbase == base, "for split file, assumed output is [os]/[path] ,but didn't get it for "..tolua(inc))
				end
			end
--[=[ add in the split file
			includeList:insert{
				inc = incname,
				out = base,
				-- TODO this assumes it is Windows vs all, and 'all' is stored in Linux ...
				-- TODO autogen by keys.  non-all <-> if os == $key, all <-> else, no 'all' present <-> else error "idk your os" unless you wanna have Linux the default
				forcecode = template([[
local ffi = require 'ffi'
if ffi.os == 'Windows' then
	return require 'ffi.Windows.<?=req?>'
else
	return require 'ffi.Linux.<?=req?>'
end
]], 			{
					req = (assert(base:match'(.*)%.lua', 'expcted inc.out to be ext .lua')
						:gsub('/', '.')),
				})
			}
--]=]
		end
	end
end


-- remove all those that pertain to other os/arch
includeList = includeList:filter(function(inc)
	if inc.os ~= nil and inc.os ~= ffi.os then return end
	if inc.arch ~= nil and inc.arch ~= ffi.arch then return end
	return true
end)


local class = require 'ext.class'
local IncludeFile = class()
function IncludeFile:setupPkgConfig()
	if self.hasSetupPkgConfig then return end
	self.hasSetupPkgConfig = true

	if self.pkgconfig
	-- pkgconfig doesn't work on windows so rather than try and fail a lot ...
	and ffi.os ~= 'Windows'
	then
		local out = string.trim(io.readproc('pkg-config --cflags '..self.pkgconfig))
		local flags = string.split(out, '%s+')

		-- HERE process -I -D flags
		for _,f in ipairs(flags) do
			if f:sub(1,2) == '-D' then
				assert.gt(#f, 2, 'TODO handle -D <macro>')
				self.macros = self.macros or table()
				self.macros:insret(f:sub(3))
			elseif f:sub(1,2) == '-I' then
				assert.gt(#f, 2, 'TODO handle -I <incdir>')
				self.includedirs = table(self.includedirs)
				self.includedirs:insert(f:sub(3))
			else
				error("pkg-config '"..self.pkgconfig.."' has unknown flag "..tostring(f)..'\n'
					..'pkg-config output: '..out)
			end
		end
	end
end

for _,inc in ipairs(includeList) do
	assert(not getmetatable(inc))
	setmetatable(inc, IncludeFile)
end

return includeList
