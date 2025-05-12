local table = require 'ext.table'

return table{

--[====[ BEGIN INTERNALLY REQUESTED
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

	-- used by <sys/stat.h>, <fcntl.h>
	{
		dontGen = true,	-- I hate the "don't include this directly" error messages ...
		inc = '<bits/stat.h>',
		out = 'Linux/c/bits/stat.lua',
	},

	-- depends: bits/wordsize.h
	{
		inc = '<bits/posix1_lim.h>',
		out = 'Linux/c/bits/posix1_lim.lua',
	},

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

	{inc='<sys/param.h>', out='Linux/c/sys/param.lua', final=function(code)
		code = fixEnumsAndDefineMacrosInterleaved(code)
		return code
	end},

	{inc='<sys/sysinfo.h>', out='Linux/c/sys/sysinfo.lua'},
--]====] -- END INTERNALLY REQUESTED

	-- used by <string.h> <ctype.h>
	{inc='<bits/types/locale_t.h>', out='Linux/c/bits/types/locale_t.lua'},

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
	{
		inc = '<time.h>',
		out = 'Linux/c/time.lua',
		final = function(code)
			code = replace_bits_types_builtin(code, 'pid_t')
			return code
		end,
	},

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
	{inc='<stdarg.h>', out='Linux/c/stdarg.lua', final=function(code)
		code = replace_va_list_require(code)
		return code
	end},

	-- in list: Windows Linux OSX
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

	-- in list: Linux OSX
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

	-- in list: Linux OSX
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

		------------ ISO/IEC 9899:1990/Amd.1:1995 ------------

	-- in list: Windows Linux OSX
	-- depends on: bits/types/__mbstate_t.h
	-- I never needed it in Linux, until I got to SDL
	{inc = '<wchar.h>', out = 'Linux/c/wchar.lua'},

		------------ ISO/IEC 9899:1999 (C99) ------------

	-- in list: Windows Linux OSX
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

	-- in list: Linux OSX
	-- depends: features.h stdint.h
	{inc='<inttypes.h>', out='Linux/c/inttypes.lua'},

	-- in list: Windows Linux OSX
	-- used by CBLAS
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

	-- in list: Windows Linux OSX
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

		------------ ISO/IEC 9045:2008 (POSIX 2008, Single Unix Specification) ------------

	-- in list: Linux OSX
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

	-- in list: Windows Linux OSX
	{inc='<fcntl.h>', out='Linux/c/fcntl.lua'},

	-- in list: Linux OSX
	-- depends: sched.h time.h
	{inc='<pthread.h>', out='Linux/c/pthread.lua', final=function(code)
			code = fixEnumsAndDefineMacrosInterleaved(code)
			return code
	end},

	-- in list: Linux OSX
	-- depends: stddef.h bits/types/time_t.h bits/types/struct_timespec.h
	{inc='<sched.h>', out='Linux/c/sched.lua', final=function(code)
		code = replace_bits_types_builtin(code, 'pid_t')
		return code
	end},

	-- in list: Windows Linux OSX
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

	-- depends: bits/types.h etc
	-- in list: Windows Linux OSX
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
	{inc='<sys/select.h>', out='Linux/c/sys/select.lua', final=function(code)
		code = replace_bits_types_builtin(code, 'suseconds_t')
		return code
	end},

	-- in list: Linux OSX
	{inc='<sys/time.h>', out='Linux/c/sys/time.lua', final=function(code)
		code = replace_bits_types_builtin(code, 'suseconds_t')
		code = fixEnumsAndDefineMacrosInterleaved(code)
		return code
	end},

	-- in list: Windows Linux OSX
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

	----------------------- OS-SPECIFIC & EXTERNALLY REQUESTED BY 3RD PARTY LIBRARIES: -----------------------

}:mapi(function(inc)
	inc.os = 'Linux' -- meh?  just have all these default for -nix systems?
	return inc
end)
