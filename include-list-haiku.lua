--[[
built with Termux, arm 32-bit
--]]
local table = require 'ext.table'
local string = require 'ext.string'

local util = require 'include.util'
local safegsub = util.safegsub
local removeEnum = util.removeEnum

local function replace_SEEK(code)
	-- unistd.h stdio.h fcntl.h all define SEEK_*, so ...
	code = safegsub(code, [[
enum { SEEK_SET = 0 };
enum { SEEK_CUR = 1 };
enum { SEEK_END = 2 };
]],
		"]] require 'ffi.req' 'c.SEEK' ffi.cdef[[\n"
	)
	return code
end


return table{

	----------------------- INTERNALLY REQUESTED: -----------------------

	{
		inc = '$notthere_1.h',
		out = 'Haiku/c/SEEK.lua',
		forcecode = [=[
local ffi = require 'ffi'
ffi.cdef[[
enum { SEEK_SET = 0 };
enum { SEEK_CUR = 1 };
enum { SEEK_END = 2 };
]]
]=],
	},

	-- used by a lot
	{inc='<null.h>', out='Haiku/c/null.lua'},

	-- used by <locale.h>
	{inc='<locale_t.h>', out='Haiku/c/locale_t.lua'},

	-- used by config/types.h
	{inc='<config/HaikuConfig.h>', out='Haiku/c/config/HaikuConfig.lua'},

	-- used by <sys/types.h>
	{inc='<config/types.h>', out='Haiku/c/config/types.lua'},

	-- used by string.h
	{inc='<features.h>', out='Haiku/c/features.lua'},

	----------------------- ISO/POSIX STANDARDS: -----------------------

	------------ ISO/IEC 9899:1990 (C89, C90) ------------

	{inc='<ctype.h>', out='Haiku/c/ctype.lua'},

	-- used by <string.h>
	{inc='<locale.h>', out='Haiku/c/locale.lua'},

	-- used by sys/types.h
	{
		inc = '<stdint.h>',
		out = 'Haiku/c/stdint.lua',
	},

	-- used by stdlib.h
	-- used by sys/types.h
	{inc='<stddef.h>', out='Haiku/c/stddef.lua'},

	-- circular dependency with <time.h>
	{
		inc='<sys/types.h>',
		out='Haiku/c/sys/types.lua',
	},

	{inc='<string.h>', out='Haiku/c/string.lua'},

	{
		inc='<limits.h>',
		out='Haiku/c/limits.lua',
		final = function(code)
			code = removeEnum(code, 'DBL_MAX = .*')
			code = removeEnum(code, 'LDBL_MAX = .*')
			code = removeEnum(code, 'DBL_NORM_MAX = .*')
			code = removeEnum(code, 'LDBL_NORM_MAX = .*')
			code = code .. [[
-- add in values that can't be ffi.cdef enum'd
local wrapper = setmetatable({}, {__index=ffi.C})
wrapper.LONG_MAX = 0x7FFFFFFFFFFFFFFFLL
wrapper.LONG_MIN = -wrapper.LONG_MAX - 1LL
wrapper.ULONG_MAX = 0xFFFFFFFFFFFFFFFFULL
wrapper.LLONG_MAX = wrapper.LONG_MAX
wrapper.LLONG_MIN = wrapper.LONG_MIN
return wrapper
]]
			return code
		end,
	},

	-- used by sys/select.h
	{
		inc='<signal.h>',
		out='Haiku/c/signal.lua',
	},

	-- circular dependency with sys/select.h 
	-- this uses time_t, but time.h defines it
	{
		--inc='<sys/time.h>',
		inc='<sys/time.h>',
		out='Haiku/c/sys/time.lua',
	},

	-- uses struct timespec and struct timeval
	-- circular dependency with sys/time.h, but I'll put select first to be like include-list-android.lua
	-- ISO/IEC 9045:2008 (POSIX 2008, Single Unix Specification)
	{
		-- use local to redirect to local sys/time.h, to redirect to local sys/types.h ...
		inc='<sys/select.h>',
		out='Haiku/c/sys/select.lua',
	},

	-- circular dependency with <sys/types.h>
	{
		-- use the local one which moved its typedefs into ./sys/types.h to prevent circular dependencies
		inc='<time.h>',
		out='Haiku/c/time.lua',
	},

	{
		inc = '<errno.h>',
		out = 'Haiku/c/errno.lua',
		final = function(code)
			-- manually add the 'errno' macro at the end:
			code = code .. [[
local wrapper
wrapper = setmetatable({
	errno = function()
		return ffi.C.__errno()[0]
	end,
	str = function()
		require 'ffi.req' 'c.string'	-- strerror
		local sp = ffi.C.strerror(wrapper.errno())
		if sp == nil then return '(null)' end
		return ffi.string(sp)
	end,
}, {
	__index = ffi.C,
})
return wrapper
]]
			return code
		end,
	},

	-- POSIX.1-2024 (IEEE Std 1003.1-2024, The Open Group Base Specifications Issue 8)
	-- not in Haiku?
	--{inc='<endian.h>', out='Haiku/c/endian.lua'},

	{inc='<stdarg.h>', out='Haiku/c/stdarg.lua'},

	{
		inc = '<stdio.h>',
		out = 'Haiku/c/stdio.lua',
		final = function(code)
			code = replace_SEEK(code)
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

	-- used by stdlib.h, uses signal.h
	{inc='<sys/wait.h>', out='Haiku/c/sys/wait.lua'},

	{inc='<stdlib.h>', out = 'Haiku/c/stdlib.lua'},

	{inc='<setjmp.h>', out='Haiku/c/setjmp.lua'},

	{
		inc = '<math.h>',
		out = 'Haiku/c/math.lua',
		final = function(code)
			code = code:gsub('enum { M_', '//%0')
			return code
		end,
	},

		------------ ISO/IEC 9899:1990/Amd.1:1995 ------------

	-- I never needed it in Linux, until I got to SDL
	{
		inc = '<wchar.h>',
		out = 'Haiku/c/wchar.lua',
	},

		------------ ISO/IEC 9899:1999 (C99) ------------

	-- identical in windows linux osx ...
	{
		inc = '<stdbool.h>',
		out = 'Haiku/c/stdbool.lua',
		final = function(code)
			-- luajit has its own bools already defined
			for _,k in ipairs{'true = 1', 'false = 0'} do
				code = removeEnum(code, k)
			end
			return code
		end,
	},


	{inc='<inttypes.h>', out='Haiku/c/inttypes.lua'},

	-- depends on bits/libc-header-start
	-- '<identifier>' expected near '_Complex' at line 2
	-- has to do with enum/define'ing the builtin word _Complex
	{inc='<complex.h>', out='Haiku/c/complex.lua'},

		------------ ISO/IEC 9045:2008 (POSIX 2008, Single Unix Specification) ------------

	-- because lua.ext uses some ffi stuff, it says "attempt to redefine 'dirent' at line 2"  for my load(path(...):read()) but not for require'results....'
	{inc='<dirent.h>', out='Haiku/c/dirent.lua'},

	-- used by fcntl.h
	{
		inc = '<sys/stat.h>',
		out = 'Haiku/c/sys/stat.lua',
		final = function(code)
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

	-- used by fcntl.h
	{
		inc = '<unistd.h>',
		out = 'Haiku/c/unistd.lua',
		final = function(code)
			code = replace_SEEK(code)
			-- but for interchangeability with Windows ...
			code = code .. [[
return ffi.C
]]
			return code
		end,
	},

	{
		inc = '<fcntl.h>',
		out = 'Haiku/c/fcntl.lua',
	},

	{
		inc='<sched.h>',
		out='Haiku/c/sched.lua',
	},

	{
		inc='<bsd_pthread.h>',
		out='Haiku/c/pthread.lua',
		final = function(code)
			code = code .. [[
return ffi.C
]]
			return code
		end,
	},

	{
		inc = '<utime.h>',
		out = 'Haiku/c/utime.lua',
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

	{inc='<sys/mman.h>', out='Haiku/c/sys/mman.lua'},

	----------------------- OS-SPECIFIC & EXTERNALLY REQUESTED BY 3RD PARTY LIBRARIES: -----------------------

	{
		inc = '<sys/socket.h>',
		out = 'Haiku/c/sys/socket.lua',
	},

	{
		inc = '<netinet/in.h>',
		out = 'Haiku/c/netinet/in.lua',
	},

	{
		inc = '<netdb.h>',
		out = 'Haiku/c/netdb.lua',
	},

	{
		inc = '<semaphore.h>',
		out = 'Haiku/c/semaphore.lua',
	},
}:mapi(function(inc)
	inc.os = 'Haiku'

	local oldfinal = inc.final
	inc.final = function(code)
		-- do any final()'s to eveyrthing *here*

		if oldfinal then code = oldfinal(code) end
		return code
	end

	-- system includes want to save all macros
	inc.saveAllMacros = true

	return inc
end)
