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
		out = 'Android/c/SEEK.lua',
		forcecode = [=[
local ffi = require 'ffi'
ffi.cdef[[
enum { SEEK_SET = 0 };
enum { SEEK_CUR = 1 };
enum { SEEK_END = 2 };
]]
]=],
	},

	{
		inc = '$notthere_2.h',
		out = 'Android/c/PAGE_SIZE.lua',
		forcecode = [=[
local ffi = require 'ffi'
ffi.cdef[[
enum { PAGE_SIZE = 4096 };
]]
]=],
	},


	-- used by <locale.h>
	{inc='<xlocale.h>', out='Android/c/xlocale.lua'},

	----------------------- ISO/POSIX STANDARDS: -----------------------

		------------ ISO/IEC 9899:1990 (C89, C90) ------------

	-- in list: Linux OSX
	{inc='<ctype.h>', out='Android/c/ctype.lua'},

	-- in list: Windows Linux OSX
	{inc='<stddef.h>', out='Android/c/stddef.lua'},

	-- used by <string.h>
	{inc='<locale.h>', out='Android/c/locale.lua'},

	-- in list: Windows Linux OSX
	-- used by sys/types.h
	{
		inc = '<stdint.h>',
		out = 'Android/c/stdint.lua',
		final = function(code)
			--code = removeEnum(code, 'WCHAR_MAX = 0x7fffffff')
			--code = removeEnum(code, '__WCHAR_MAX = 0x7fffffff')
			return code
		end,
	},


	-- in list: Windows Linux OSX
	-- used by <time.h>
	{inc='<sys/types.h>', out='Android/c/sys/types.lua'},

	-- used by sys/time.h sys/select.h
	{inc='<linux/time.h>', out='Android/c/linux/time.lua'},

	-- in list: Windows Linux OSX
	{inc='<string.h>', out='Android/c/string.lua'},

	-- in list: Windows Linux OSX
	{
		inc='<limits.h>',
		out='Android/c/limits.lua',
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

	-- in list: Linux OSX
	-- used by sys/select.h
	{
		inc='<signal.h>',
		out='Android/c/signal.lua',
		final = function(code)
			-- signal.h and pthread.h
			code = safegsub(code,
				string.patescape'enum { PAGE_SIZE = 4096 };',
				"]] require 'ffi.req' 'c.PAGE_SIZE' ffi.cdef[["
			)
			code = code .. [[
return ffi.C
]]
			return code
		end,
	},

	-- in list: Linux OSX
	-- used by sys/time.h
	-- uses struct timespec and struct timeval
	-- ISO/IEC 9045:2008 (POSIX 2008, Single Unix Specification)
	{inc='<sys/select.h>', out='Android/c/sys/select.lua'},

	-- in list: Linux OSX
	-- uses limits.h I think ?
	{inc='<sys/time.h>', out='Android/c/sys/time.lua'},

	-- in list: Windows Linux OSX
	-- this and any other file that requires stddef might have these lines which will have to be removed:
	-- uses sys/time.h
	{inc='<time.h>', out='Android/c/time.lua'},

	-- in list: Windows Linux OSX
	{
		inc = '<errno.h>',
		out = 'Android/c/errno.lua',
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
	-- not in Android?
	--{inc='<endian.h>', out='Android/c/endian.lua'},

	-- in list: Windows Linux OSX
	{inc='<stdarg.h>', out='Android/c/stdarg.lua'},

	-- in list: Windows Linux OSX
	{
		inc = '<stdio.h>',
		out = 'Android/c/stdio.lua',
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

	-- in list: Windows Linux OSX
	{inc = '<stdlib.h>', out = 'Android/c/stdlib.lua'},

	-- in list: Windows Linux OSX
	{inc='<setjmp.h>', out='Android/c/setjmp.lua'},

	-- in list: Linux OSX
	{
		inc = '<math.h>',
		out = 'Android/c/math.lua',
		final = function(code)
			code = code:gsub('enum { M_', '//%0')
			--code = removeEnum(code, 'FP_NORMAL = 4')
			--code = removeEnum(code, 'FP_SUBNORMAL = 3')
			--code = removeEnum(code, 'FP_ZERO = 2')
			--code = removeEnum(code, 'FP_INFINITE = 1')
			--code = removeEnum(code, 'FP_NAN = 0')
			return code
		end,
	},

		------------ ISO/IEC 9899:1990/Amd.1:1995 ------------

	-- in list: Windows Linux OSX
	-- I never needed it in Linux, until I got to SDL
	{
		inc = '<wchar.h>',
		out = 'Android/c/wchar.lua',
		final = function(code)
			-- C23 standard that ffi.cdef has yet to catch up with
			code = safegsub(code, 'enum : size_t', 'enum') 

			--code = removeEnum(code, 'WCHAR_MAX = 0x7fffffff')
			--code = removeEnum(code, '__WCHAR_MAX = 0x7fffffff')
			return code
		end,
	},

		------------ ISO/IEC 9899:1999 (C99) ------------

	-- in list: Windows Linux OSX
	-- identical in windows linux osx ...
	{
		inc = '<stdbool.h>',
		out = 'Android/c/stdbool.lua',
		final = function(code)
			-- luajit has its own bools already defined
			for _,k in ipairs{'true = 1', 'false = 0'} do
				code = removeEnum(code, k)
			end
			return code
		end,
	},


	-- in list: Linux OSX
	{inc='<inttypes.h>', out='Android/c/inttypes.lua'},

	-- in list: Windows Linux OSX
	-- depends on bits/libc-header-start
	-- '<identifier>' expected near '_Complex' at line 2
	-- has to do with enum/define'ing the builtin word _Complex
	{inc='<complex.h>', out='Android/c/complex.lua'},

		------------ ISO/IEC 9045:2008 (POSIX 2008, Single Unix Specification) ------------

	-- in list: Linux OSX
	-- because lua.ext uses some ffi stuff, it says "attempt to redefine 'dirent' at line 2"  for my load(path(...):read()) but not for require'results....'
	{inc='<dirent.h>', out='Android/c/dirent.lua'},

	-- in list: Windows Linux OSX
	{
		inc = '<fcntl.h>',
		out = 'Android/c/fcntl.lua',
		final = function(code)
			code = replace_SEEK(code)
			-- abstraction used by lfs_ffi
			code = code .. [[
return ffi.C
]]
			return code
		end,
	},

	-- in list: Linux OSX
	{
		inc='<sched.h>',
		out='Android/c/sched.lua',
		final = function(code)
			-- this includes linux/types.h, which has some __u64 types that are specific to endian-ness and for use of compiling by the kernel
			-- and it doesn't seem to insert the include for linux/types.h
			-- so instead of deal with it, I'll just gsub that myself
			code = safegsub(code, '__u32', 'uint32_t')
			code = safegsub(code, '__s32', 'int32_t')
			code = safegsub(code, '__u64', 'uint64_t')
			
			-- sched.h uses pid_t though it isn't getting an include (tho some includes seem to be skipped)
			code = safegsub(
				code,
				string.patescape"local ffi = require 'ffi'\n",
				"%0require 'ffi.req' 'c.sys.types'\n"
			)
			-- these are too big for enum which is 32-bit
			code = removeEnum(code, 'CLONE_CLEAR_SIGHAND = .*')
			code = removeEnum(code, 'CLONE_INTO_CGROUP = .*')
			return code
		end,
	},

	-- in list: Linux OSX
	{
		inc='<pthread.h>',
		out='Android/c/pthread.lua',
		final = function(code)
			-- signal.h and pthread.h
			code = safegsub(code,
				string.patescape'enum { PAGE_SIZE = 4096 };',
				"]] require 'ffi.req' 'c.PAGE_SIZE' ffi.cdef[["
			)
			code = code .. [[
return ffi.C
]]
			return code
		end,
	},

	-- in list: Windows Linux OSX
	{
		inc = '<unistd.h>',
		out = 'Android/c/unistd.lua',
		final = function(code)
			code = replace_SEEK(code)
			-- but for interchangeability with Windows ...
			code = code .. [[
return ffi.C
]]
			return code
		end,
	},

	-- in list: Windows Linux OSX
	{
		inc = '<sys/stat.h>',
		out = 'Android/c/sys/stat.lua',
		final = function(code)
			-- needs sys/types.h but isn't generating the include for it
			code = safegsub(
				code,
				string.patescape"local ffi = require 'ffi'\n",
				"%0"
				.."require 'ffi.req' 'c.linux.time'\n"	-- struct timespec
				.."require 'ffi.req' 'c.sys.types'\n"	-- nlink_t
			)

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

	-- in list: Linux OSX
	{
		inc = '<utime.h>',
		out = 'Android/c/utime.lua',
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

	-- in list: Windows Linux OSX
	{inc='<sys/mman.h>', out='Android/c/sys/mman.lua'},

	----------------------- OS-SPECIFIC & EXTERNALLY REQUESTED BY 3RD PARTY LIBRARIES: -----------------------

	{
		inc = '<sys/socket.h>',
		out = 'Android/c/sys/socket.lua',
		--[=[
		final = function(code)
			code = safegsub(
				code,
				'enum { __FD_SETSIZE = 1024 };',
				"]] require 'ffi.req' 'c.bits.types.__FD_SETSIZE' ffi.cdef[["
			)
			return code
		end,
		--]=]
	},

	{
		inc = '<netinet/in.h>',
		out = 'Android/c/netinet/in.lua',
		final = function(code)
			code = safegsub(code, '__u8', 'uint8_t')
			code = safegsub(code, '__u16', 'uint16_t')
			code = safegsub(code, '__u32', 'uint32_t')
			code = safegsub(code, '__u64', 'uint64_t')
			code = safegsub(code, '__be16', 'uint16_t')
			code = safegsub(code, '__be32', 'uint32_t')
			return code
		end,
	},

	{
		inc = '<netdb.h>',
		out = 'Android/c/netdb.lua',
		final = function(code)
			code = safegsub(
				code,
				'enum { IPPORT_RESERVED = 1024 };',
				''
			)
			return code
		end,
	},

	{
		inc = '<semaphore.h>',
		out = 'Android/c/semaphore.lua',
		final = function(code)
			code = code .. [[
return ffi.C
]]
			return code
		end,
	},
}:mapi(function(inc)
	inc.os = 'Android'

	local oldfinal = inc.final
	inc.final = function(code)
		--code = removeEnum(code, '__[_%w]* = [01]')
		code = removeEnum(code, '__[_%w]*_defined = 1')
		code = removeEnum(code, '__have_[_%w]* = 1')
		--code = removeEnum(code, '_[_%w]*_H = 1')
		if oldfinal then code = oldfinal(code) end
		return code
	end

	-- system includes want to save all macros
	inc.saveAllMacros = true

	return inc
end)
