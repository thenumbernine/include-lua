local table = require 'ext.table'
local string = require 'ext.string'

local util = require 'util'
local safegsub = util.safegsub
local removeEnum = util.removeEnum

-- _VA_LIST_DEFINED and va_list don't appear next to each other like the typical bits_types_builtin do
local function remove_VA_LIST_DEFINED(code)
	return removeEnum(code, '_VA_LIST_DEFINED = 1')
end

local function replace_SEEK(code)
	-- unistd.h stdio.h fcntl.lua all define SEEK_*, so ...
	code = safegsub(code, [[
enum { SEEK_SET = 0 };
enum { SEEK_CUR = 1 };
enum { SEEK_END = 2 };
]],
		"]] require 'ffi.req' 'c.bits.types.SEEK' ffi.cdef[[\n"
	)
	-- fcntl.lua unistd.lua have these:
	code = safegsub(code, [[
enum { R_OK = 4 };
enum { W_OK = 2 };
enum { X_OK = 1 };
enum { F_OK = 0 };
]],
		'')
	-- goes with lockf() which is in unistd.h ... and fcntl.h
	-- man says lockf() goes with unistd.h
	code = safegsub(code, [[
enum { F_ULOCK = 0 };
enum { F_LOCK = 1 };
enum { F_TLOCK = 2 };
enum { F_TEST = 3 };
]],
		'')
	return code
end

return table{

	----------------------- INTERNALLY REQUESTED: -----------------------

	-- fake file
	-- SEEK_* is used by <stdio.h> <unistd.h> <fcntl.h>
	-- *_OK is used by <unistd.h> <fcntl.h>
	-- they all hvae the same macros so they're going here:
	{
		inc = '$notthere.h',
		out = 'Linux/c/bits/types/SEEK.lua',
		forcecode = [=[
local ffi = require 'ffi'
ffi.cdef[[
enum { SEEK_SET = 0 };
enum { SEEK_CUR = 1 };
enum { SEEK_END = 2 };
enum { R_OK = 4 };
enum { W_OK = 2 };
enum { X_OK = 1 };
enum { F_OK = 0 };
enum { F_ULOCK = 0 };
enum { F_LOCK = 1 };
enum { F_TLOCK = 2 };
enum { F_TEST = 3 };
]]
]=],
	},

	-- used by <bits/types.h> <features.h>
	-- yes, bits/types.h does include this out of its way, even though features.h already did
	{inc='<bits/timesize.h>', out='Linux/c/bits/timesize.lua'},

	-- used by everyone
	{inc='<features.h>', out='Linux/c/features.lua'},

-- TODO all these internal files need silentincs={'<features.h>'}
-- because they all expect <features.h> to be alreayd included
-- but silentincs is messing up ...

	-- used by <time.h> <ctype.h>
	{inc='<bits/types.h>', out='Linux/c/bits/types.lua'},

	-- used by <string.h> <ctype.h>
	{inc='<bits/types/locale_t.h>', out='Linux/c/bits/types/locale_t.lua', silentincs={'<features.h>'}},

	-- used by <stdlib.h> <time.h>
	{inc='<bits/types/clock_t.h>', out='Linux/c/bits/types/clock_t.lua', silentincs={'<features.h>'}},

	-- used by <stdlib.h> <time.h>
	{inc='<bits/types/clockid_t.h>', out='Linux/c/bits/types/clockid_t.lua', silentincs={'<features.h>'}},

	-- used by <stdlib.h> <time.h>
	{inc='<bits/types/time_t.h>', out='Linux/c/bits/types/time_t.lua', silentincs={'<features.h>'}},

	-- used by <stdlib.h> <time.h>
	{inc='<bits/types/timer_t.h>', out='Linux/c/bits/types/timer_t.lua', silentincs={'<features.h>'}},

	-- used by <ctype.h> <bits/types/struct_timespec.h>
	{inc='<bits/endian.h>', out='Linux/c/bits/endian.lua', silentincs={'<features.h>'}},

	-- used by <stdlib.h> <time.h>
	{inc='<bits/types/struct_timespec.h>', out='Linux/c/bits/types/struct_timespec.lua', silentincs={'<features.h>'}},

	-- used by <setjmp.h> <stdlib.h>
	{inc='<bits/types/__sigset_t.h>', out='Linux/c/bits/types/__sigset_t.lua', silentincs={'<features.h>'}},

	-- used by <signal.h> <stdlib.h>
	{inc='<bits/types/sigset_t.h>', out='Linux/c/bits/types/sigset_t.lua', silentincs={'<features.h>'}},

	-- used by <signal.h> <stdlib.h>
	{inc='<bits/pthreadtypes.h>', out='Linux/c/bits/pthreadtypes.lua', silentincs={'<features.h>'}},

	-- used by <wchar.h> <stdio.h>
	{inc='<bits/types/__mbstate_t.h>', out='Linux/c/bits/types/__mbstate_t.lua', silentincs={'<features.h>'}},

	-- used by <wchar.h> <stdio.h>
	{inc='<bits/types/__FILE.h>', out='Linux/c/bits/types/__FILE.lua', silentincs={'<features.h>'}},

	-- used by <wchar.h> <stdio.h>
	{inc='<bits/types/FILE.h>', out='Linux/c/bits/types/FILE.lua', silentincs={'<features.h>'}},

	-- used by <inttypes.h> <stdlib.h>
	{inc='<bits/stdint-intn.h>', out='Linux/c/bits/stdint-intn.lua', silentincs={'<features.h>'}},

	-- used by <stdint.h> <inttypes.h>
	{inc='<bits/stdint-uintn.h>', out='Linux/c/bits/stdint-uintn.lua', silentincs={'<features.h>'}},

	-- used by <stdint.h> <inttypes.h>
	{inc='<bits/stdint-least.h>', out='Linux/c/bits/stdint-least.lua', silentincs={'<features.h>'}},

	-- used by <sys/select.h> <stdlib.h>
	{inc='<bits/types/struct_timeval.h>', out='Linux/c/bits/types/struct_timeval.lua', silentincs={'<features.h>'}},

	-- used by <stdio.h> <stdlib.h>
	{inc='<bits/floatn.h>', out='Linux/c/bits/floatn.lua', silentincs={'<features.h>'}},

	-- used by <pthread.h> <bits/posix1_lim.h>
	{inc='<bits/pthread_stack_min-dynamic.h>', out='Linux/c/bits/pthread_stack_min-dynamic.lua', silentincs={'<features.h>'}},

	-- used by <dirent.h> <limits.h>
	{inc='<bits/posix1_lim.h>', out='Linux/c/bits/posix1_lim.lua', silentincs={'<features.h>'}},

	-- used by <stdlib.h> <string.h>
	-- never include dirctly
	{
		inc = '<bits/libc-header-start.h>',
		out = 'Linux/c/bits/libc-header-start.lua',
		silentincs = {'<features.h>'},
		forcecode = [=[
local ffi = require 'ffi'
ffi.cdef[[
/* ++ BEGIN <bits/libc-header-start.h> /usr/include/x86_64-linux-gnu/bits/libc-header-start.h */
/* +++ BEGIN <features.h> /usr/include/features.h */
]] require 'ffi.req' 'c.features' ffi.cdef[[
/* +++ END <features.h> /usr/include/features.h */
/* ++ END <bits/libc-header-start.h> /usr/include/x86_64-linux-gnu/bits/libc-header-start.h */
]]
]=],
	},

	-- used by <sys/stat.h> <fcntl.h>
	-- never include directly
	{
		inc='<bits/stat.h>',
		out='Linux/c/bits/stat.lua',
		silentincs = {'<features.h>'},
		forcecode = [=[
local ffi = require 'ffi'
ffi.cdef[[
/* + BEGIN <bits/stat.h> /usr/include/x86_64-linux-gnu/bits/stat.h */
/* ++ BEGIN <bits/types.h> /usr/include/x86_64-linux-gnu/bits/types.h */
]] require 'ffi.req' 'c.bits.types' ffi.cdef[[
/* ++ END <bits/types.h> /usr/include/x86_64-linux-gnu/bits/types.h */
/* ++ BEGIN <bits/types/struct_timespec.h> /usr/include/x86_64-linux-gnu/bits/types/struct_timespec.h */
]] require 'ffi.req' 'c.bits.types.struct_timespec' ffi.cdef[[
/* ++ END <bits/types/struct_timespec.h> /usr/include/x86_64-linux-gnu/bits/types/struct_timespec.h */
/* ++ BEGIN <bits/struct_stat.h> /usr/include/x86_64-linux-gnu/bits/struct_stat.h */
struct stat
  {
    __dev_t st_dev;
    __ino_t st_ino;
    __nlink_t st_nlink;
    __mode_t st_mode;
    __uid_t st_uid;
    __gid_t st_gid;
    int __pad0;
    __dev_t st_rdev;
    __off_t st_size;
    __blksize_t st_blksize;
    __blkcnt_t st_blocks;
    struct timespec st_atim;
    struct timespec st_mtim;
    struct timespec st_ctim;
    __syscall_slong_t __glibc_reserved[3];
  };
/* ++ END <bits/struct_stat.h> /usr/include/x86_64-linux-gnu/bits/struct_stat.h */
/* + END <bits/stat.h> /usr/include/x86_64-linux-gnu/bits/stat.h */
]]
]=],
	},

	-- used by <pthread.h> <setjmp.h> <bits/types/struct___jmp_buf_tag.h>
	-- error: #error "Never include <bits/setjmp.h> directly; use <setjmp.h> instead."
	-- that means you gotta pick out the common section manually ...
	{
		inc='<bits/setjmp.h>',
		out='Linux/c/bits/setjmp.lua',
		silentincs = {'<features.h>'},
		forcecode = [=[
local ffi = require 'ffi'
ffi.cdef[[
/* + BEGIN <bits/setjmp.h> /usr/include/x86_64-linux-gnu/bits/setjmp.h */
typedef long int __jmp_buf[8];
/* + END <bits/setjmp.h> /usr/include/x86_64-linux-gnu/bits/setjmp.h */
]]
]=],
	},

	-- used by <pthread.h> <setjmp.h>
	-- errors same as above, as if i'm including bits/setjmp.h, but i'm not ...
	-- so force this one's output too
	-- but in its cut-out code I don't see bits/setjmp.h ...
	-- ... and i'm getting missing typedefs ...
	-- ... so maybe i'll manually add it?
	{
		inc='<bits/types/struct___jmp_buf_tag.h>',
		out='Linux/c/bits/types/struct___jmp_buf_tag.lua',
		silentincs = {'<features.h>'},
		forcecode = [=[
local ffi = require 'ffi'
ffi.cdef[[
/* + BEGIN <bits/types/struct___jmp_buf_tag.h> /usr/include/x86_64-linux-gnu/bits/types/struct___jmp_buf_tag.h */
/* ++ BEGIN <bits/setjmp.h> /usr/include/x86_64-linux-gnu/bits/setjmp.h */
]] require 'ffi.req' 'c.bits.setjmp' ffi.cdef[[
/* ++ END <bits/setjmp.h> /usr/include/x86_64-linux-gnu/bits/setjmp.h */
/* ++ BEGIN <bits/types/__sigset_t.h> /usr/include/x86_64-linux-gnu/bits/types/__sigset_t.h */
]] require 'ffi.req' 'c.bits.types.__sigset_t' ffi.cdef[[
/* ++ END <bits/types/__sigset_t.h> /usr/include/x86_64-linux-gnu/bits/types/__sigset_t.h */
struct __jmp_buf_tag
  {
    __jmp_buf __jmpbuf;
    int __mask_was_saved;
    __sigset_t __saved_mask;
  };
/* + END <bits/types/struct___jmp_buf_tag.h> /usr/include/x86_64-linux-gnu/bits/types/struct___jmp_buf_tag.h */
]]
]=],
	},

	-- used by <math.h> in multiple places
	{
		inc='<bits/mathcalls-helper-functions.h>',
		out='Linux/c/bits/mathcalls-helper-functions.lua',
		silentincs = {'<features.h>'},
		-- this has a bunch of __MATHDECL_ALIAS macros that expand into function defs ...
		-- if I macro it to be nothing  i.e. macros={'__MATHDECL_ALIAS(...)='}
		--  then the __attribute__'s are left.
		-- if I remove those too then its just an empty file.
		-- honestly I was trying to get .silentincs to work with this in <math.h> output
		-- but I haven't got it working with the new gcc-E-based method
		-- so here's an empty file.
		--forcecode='',
		-- BUUUTTT the #include->replace() codegen needs this to specify itself or something, for the sake of regsitering itself in the include path search tree or something idk
		--macros={
			--'__MATHDECL_ALIAS(...)=',
			--'__attribute__(...)=',
		--},
		final = function(code)
			code = code
				--:gsub(' *;\n', '\n')
				--:gsub(' *\n', '\n')
				--:gsub('\n\n*', '\n')
				-- oh and it can't be empty or the thing throws it away so ...
				:gsub('__MATH', '//%0')
				:gsub('__attr', '//%0')
			return code
		end,
	},

	----------------------- ISO/POSIX STANDARDS: -----------------------

		------------ ISO/IEC 9899:1990 (C89, C90) ------------

	-- in list: Linux OSX
	-- included by SDL/SDL_stdinc.h
	{inc='<ctype.h>', out='Linux/c/ctype.lua'},

	-- in list: Windows Linux OSX
	{inc='<stddef.h>', out='Linux/c/stddef.lua'},

	-- in list: Windows Linux OSX
	-- depends: features.h stddef.h bits/libc-header-start.h
	{inc='<string.h>', out='Linux/c/string.lua'},

	-- in list: Windows Linux OSX
	-- depends: features.h stddef.h bits/types.h and too many really
	-- this and any other file that requires stddef might have these lines which will have to be removed:
	{inc='<time.h>', out='Linux/c/time.lua'},

	-- in list: Windows Linux OSX
	-- depends on <features.h>
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

	-- in list: Linux OSX
	-- ISO/IEC 9045:2008 (POSIX 2008, Single Unix Specification)
	-- used by <stdlib.h>
	{inc='<sys/select.h>', out='Linux/c/sys/select.lua'},

	-- used by <sys/types.h> <stdlib.h>
	-- POSIX.1-2024 (IEEE Std 1003.1-2024, The Open Group Base Specifications Issue 8)
	{inc='<endian.h>', out='Linux/c/endian.lua'},

	-- in list: Windows Linux OSX
	-- used by <stdlib.h>
	{inc='<sys/types.h>', out='Linux/c/sys/types.lua'},

	-- in list: Windows Linux OSX
	-- depends: features.h sys/types.h
	{inc = '<stdlib.h>', out = 'Linux/c/stdlib.lua'},

	-- in list: Windows Linux OSX
	-- depends: bits/libc-header-start.h linux/limits.h bits/posix1_lim.h
	-- with this the preproc gets a warning:
	--  warning: redefining LLONG_MIN from -1 to -9.2233720368548e+18 (originally (-LLONG_MAX - 1LL))
	-- and that comes with a giant can of worms of how i'm handling cdef numbers vs macro defs vs lua numbers ...
	-- mind you I could just make the warning: output into a comment
	--  and there would be no need for manual manipulation here
	{inc='<limits.h>', out='Linux/c/limits.lua'},

	-- in list: Windows Linux OSX
	-- depends: features.h, bits/types/__sigset_t.h
	{inc='<setjmp.h>', out='Linux/c/setjmp.lua'},

	-- in list: Windows Linux OSX
	-- depends on too much
	{inc='<stdarg.h>', out='Linux/c/stdarg.lua'},

	-- in list: Windows Linux OSX
	-- depends on too much
	-- moving to Linux-only block since now it is ...
	-- it used to be just after stdarg.h ...
	-- maybe I have to move everything up to that file into the Linux-only block too ...
	{
		inc = '<stdio.h>',
		out = 'Linux/c/stdio.lua',
		final = function(code)
			code = replace_SEEK(code)
			code = remove_VA_LIST_DEFINED(code)
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

	-- in list: Linux OSX
	{
		inc = '<math.h>',
		out = 'Linux/c/math.lua',
		final = function(code)
			-- ok so before final() is called,
			-- #defines are spit out at the end of the file
			-- but here in <math.h> they are alreayd outputted as enums ... welp most are at least ...
			-- so we remove them:
			code = code:gsub('enum { M_', '//%0')
			code = removeEnum(code, 'FP_NORMAL = 4')
			code = removeEnum(code, 'FP_SUBNORMAL = 3')
			code = removeEnum(code, 'FP_ZERO = 2')
			code = removeEnum(code, 'FP_INFINITE = 1')
			code = removeEnum(code, 'FP_NAN = 0')
			return code
		end,
	},

	-- in list: Linux OSX
	{inc='<signal.h>', out='Linux/c/signal.lua'},

		------------ ISO/IEC 9899:1990/Amd.1:1995 ------------

	-- in list: Windows Linux OSX
	-- I never needed it in Linux, until I got to SDL
	{
		inc = '<wchar.h>',
		out = 'Linux/c/wchar.lua',
		final = function(code)
			code = remove_VA_LIST_DEFINED(code)
			return code
		end,
	},

		------------ ISO/IEC 9899:1999 (C99) ------------

	-- in list: Windows Linux OSX
	-- identical in windows linux osx ...
	{
		inc = '<stdbool.h>',
		out = 'Linux/c/stdbool.lua',
		final = function(code)
			-- luajit has its own bools already defined
			for _,k in ipairs{'true = 1', 'false = 0'} do
				code = removeEnum(code, k)
			end
			return code
		end,
	},


	-- in list: Windows Linux OSX
	-- used by <inttypes.h>
	{
		inc = '<stdint.h>',
		out = 'Linux/c/stdint.lua',
		final = function(code)
			return code
		end,
	},

	-- in list: Linux OSX
	{inc='<inttypes.h>', out='Linux/c/inttypes.lua'},

	-- in list: Windows Linux OSX
	-- used by CBLAS
	-- depends on bits/libc-header-start
	-- '<identifier>' expected near '_Complex' at line 2
	-- has to do with enum/define'ing the builtin word _Complex
	{inc='<complex.h>', out='Linux/c/complex.lua'},

		------------ ISO/IEC 9045:2008 (POSIX 2008, Single Unix Specification) ------------

	-- in list: Linux OSX
	-- because lua.ext uses some ffi stuff, it says "attempt to redefine 'dirent' at line 2"  for my load(path(...):read()) but not for require'results....'
	{inc='<dirent.h>', out='Linux/c/dirent.lua'},

	-- in list: Windows Linux OSX
	{
		inc = '<fcntl.h>',
		out = 'Linux/c/fcntl.lua',
		final = function(code)
			code = replace_SEEK(code)
			return code
		end,
	},

	-- in list: Linux OSX
	-- depends: stddef.h
	-- used by <pthread.h>
	{inc='<sched.h>', out='Linux/c/sched.lua'},

	-- in list: Linux OSX
	-- depends: time.h
	{inc='<pthread.h>', out='Linux/c/pthread.lua'},

	-- in list: Windows Linux OSX
	-- depends: features.h bits/types.h
	{
		inc = '<unistd.h>',
		out = 'Linux/c/unistd.lua',
		final = function(code)
			code = replace_SEEK(code)
			-- but for interchangeability with Windows ...
			code = code .. [[
return ffi.C
]]
			return code
		end,
	},

	-- depends: bits/types.h etc
	-- in list: Windows Linux OSX
	{
		inc = '<sys/stat.h>',
		out = 'Linux/c/sys/stat.lua',
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

	-- in list: Linux OSX
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

	-- in list: Windows Linux OSX
	{inc='<sys/mman.h>', out='Linux/c/sys/mman.lua'},

	-- in list: Linux OSX
	{inc='<sys/time.h>', out='Linux/c/sys/time.lua'},

	----------------------- OS-SPECIFIC & EXTERNALLY REQUESTED BY 3RD PARTY LIBRARIES: -----------------------

}:mapi(function(inc)
	inc.os = 'Linux' -- meh?  just have all these default for -nix systems?

	-- rule of thumb for linux gcc
	-- to get rid of the __*_defined = 1 defines => enums
	-- maybe a better fix would be to cull macros before enum-generation ...
	local oldfinal = inc.final
	inc.final = function(code)
		code = removeEnum(code, '__[_%w]*_defined = 1')
		if oldfinal then code = oldfinal(code) end
		return code
	end

	-- system includes want to save all macros
	-- but then we still have the same duplicate-macro problem ...
	--inc.saveAllMacros = true

	return inc
end)
