local table = require 'ext.table'

-- TODO this is most likely going to be come Windows/x64/ files in the future
return table{
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

	-- depends: corecrt_wdirect.h
	-- was a Windows programmer trying to type "dirent.h" and got mixed up?
	-- looks like a few of these functions are usually in POSIX unistd.h
	{
		inc = '<direct.h>',
		out = 'Windows/c/direct.lua',
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
	-- in list: Windows (internal include file)
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

	----------------------- ISO/POSIX STANDARDS: -----------------------

		------------ ISO/IEC 9899:1990 (C89, C90) ------------

	-- in list: Windows Linux OSX
	{inc='<errno.h>', out = 'Windows/c/errno.lua'},

	-- in list: Windows Linux OSX
	{inc='<stddef.h>', out='Windows/c/stddef.lua'},

	-- in list: Windows Linux OSX
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

	-- in list: Windows Linux OSX
	-- depends on: errno.h corecrt_wstring.h vcruntime_string.h
	{inc = '<string.h>', out = 'Windows/c/string.lua'},


	-- in list: Windows Linux OSX
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

	-- in list: Windows Linux OSX
	{
		inc = '<stdarg.h>',
		out = 'Windows/c/stdarg.lua',
	},

	-- in list: Windows Linux OSX
	{
		inc = '<limits.h>',
		out = 'Windows/c/limits.lua',
	},

	-- in list: Windows Linux OSX
	-- depends: corecrt_wstdlib.h limits.h
	{
		inc = '<stdlib.h>',
		out = 'Windows/c/stdlib.lua',
	},

	-- in list: Windows Linux OSX
	-- needed by png.h
	{inc='<setjmp.h>', out='Windows/c/setjmp.lua'},

		------------ ISO/IEC 9899:1990/Amd.1:1995 ------------

	-- in list: Windows Linux OSX
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


		------------ ISO/IEC 9899:1999 (C99) ------------

	-- in list: Windows Linux OSX
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

	-- in list: Windows Linux OSX
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

	-- in list: Windows Linux OSX
	-- used by CBLAS
	{
		inc = '<complex.h>',
		out = 'Windows/c/complex.lua',
	},

		------------ ISO/IEC 9045:2008 (POSIX 2008, Single Unix Specification) ------------

	-- in list: Windows Linux OSX
	{inc='<fcntl.h>', out='Windows/c/fcntl.lua'},

	-- in list: Windows Linux OSX
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

	-- in list: Windows Linux OSX
	{inc='<sys/mman.h>', out='Windows/c/sys/mman.lua'},

	-- depends: sys/types.h
	-- in list: Windows Linux OSX
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

	-- in list: Windows Linux OSX
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

	----------------------- OS-SPECIFIC & EXTERNALLY REQUESTED BY 3RD PARTY LIBRARIES: -----------------------

	-- used by SDL
	-- in list: Windows
	{
		inc = '<process.h>',
		out = 'Windows/c/process.lua',
	},

}:mapi(function(inc)
	inc.os = 'Windows'

	-- system includes want to save all macros
	inc.saveAllMacros = true

	return inc
end)
