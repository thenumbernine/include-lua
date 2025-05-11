local table = require 'ext.table'
local string = require 'ext.string'

local util = require 'util'
local safegsub = util.safegsub
local removeEnum = util.removeEnum
local commentOutLine = util.commentOutLine
local fixEnumsAndDefineMacrosInterleaved = util.fixEnumsAndDefineMacrosInterleaved

local function removeAttrAvailability(code)
	-- luajit can't handle these attributes ...
	return safegsub(code, '__attribute__%(%(availability%b()%)%)', '')
		:gsub('%s*\n%s*\n', '\n')
end

return table{

-- [====[ BEGIN INTERNALLY REQUESTED
-- They only exist to replace duplicate-generated ctypes
-- This process of duplication-detection can be automated:
-- 1) generate a binding file
-- 2) search through all previous generated binding files, search the pair of the new file + old file for like included files
-- 2b) if a like included file is found, then add that to our internally-requested list.
-- 2c) build a DAG while you go, keep them in order.
-- 3) once you're finished, any stored internally-requested files not requested this time around should be reported (out with the old).

	-- used by <time.h> <string.h>
	{inc='<Availability.h>', out='OSX/c/Availability.lua'},
	
	-- used by <_types.h> <machine/types.h>
	{inc='<i386/_types.h>', out='OSX/c/i386/_types.lua'},

	-- used by <_types.h> <machine/types.h>
	{inc='<sys/cdefs.h>', out='OSX/c/sys/cdefs.lua'},

	-- used by <machine/types.h> <_types.h>
	{inc='<machine/_types.h>', out='OSX/c/machine/_types.lua'},

	-- used by <sys/_pthread/_pthread_attr_t.h> <sys/_types.h>
	{inc='<sys/_pthread/_pthread_types.h>', out='OSX/c/sys/_pthread/_pthread_types.lua'},

	-- used by <sys/signal.h> <_types.h>
	{inc='<sys/_types.h>', out='OSX/c/sys/_types.lua'},

	-- used by <time.h> <string.h>
	{inc='<_types.h>', out='OSX/c/_types.lua'},

	-- used by <stdint.h> <machine/types.h>
	{inc='<sys/_types/_int8_t.h>', out='OSX/c/sys/_types/_int8_t.lua'},

	-- used by <stdint.h> <machine/types.h>
	{inc='<sys/_types/_int16_t.h>', out='OSX/c/sys/_types/_int16_t.lua'},

	-- used by <stdint.h> <machine/types.h>
	{inc='<sys/_types/_int32_t.h>', out='OSX/c/sys/_types/_int32_t.lua'},

	-- used by <stdint.h> <machine/types.h>
	{inc='<sys/_types/_int64_t.h>', out='OSX/c/sys/_types/_int64_t.lua'},

	-- used by <stdint.h> <machine/types.h>
	{inc='<sys/_types/_intptr_t.h>', out='OSX/c/sys/_types/_intptr_t.lua'},

	-- used by <stdint.h> <machine/types.h>
	{inc='<sys/_types/_uintptr_t.h>', out='OSX/c/sys/_types/_uintptr_t.lua'},

	-- used by <time.h> <string.h>
	{inc='<machine/types.h>', out='OSX/c/machine/types.lua'},

	-- used by <time.h> <string.h>
	{inc='<sys/_types/_size_t.h>', out='OSX/c/sys/_types/_size_t.lua'},

	-- used by <errno.h> <string.h>
	{inc='<sys/_types/_errno_t.h>', out='OSX/c/sys/_types/_errno_t.lua'},

	-- used by <stdio.h> <string.h>
	{inc='<sys/_types/_ssize_t.h>', out='OSX/c/sys/_types/_ssize_t.lua'},

	-- used by <stdlib.h> <sys/signal.h>
	{inc='<sys/_types/_pid_t.h>', out='OSX/c/sys/_types/_pid_t.lua'},

	-- used by <pthread.h> <sys/signal.h>
	{inc='<sys/_pthread/_pthread_attr_t.h>', out='OSX/c/sys/_pthread/_pthread_attr_t.lua'},

	-- used by <pthread.h> <sys/signal.h>
	{inc='<sys/_types/_sigset_t.h>', out='OSX/c/sys/_types/_sigset_t.lua'},
	
	-- used by <unistd.h> <sys/signal.h>
	{inc='<sys/_types/_uid_t.h>', out='OSX/c/sys/_types/_uid_t.lua'},

	-- used by <signal.h> <stdlib.h>
	{inc='<sys/signal.h>', out='OSX/c/sys/signal.lua'},

	-- used by <wchar.h> <stdlib.h>
	{inc='<sys/_types/_ct_rune_t.h>', out='OSX/c/sys/_types/_ct_rune_t.lua'},

	-- used by <wchar.h> <stdlib.h>
	{inc='<sys/_types/_rune_t.h>', out='OSX/c/sys/_types/_rune_t.lua'},

	-- used by <wchar.h> <stdlib.h>
	{inc='<sys/_types/_wchar_t.h>', out='OSX/c/sys/_types/_wchar_t.lua'},

	-- used by <stdint.h> <stdlib.h>
	{inc='<_types/_uint8_t.h>', out='OSX/c/_types/_uint8_t.lua'},

	-- used by <stdint.h> <stdlib.h>
	{inc='<_types/_uint16_t.h>', out='OSX/c/_types/_uint16_t.lua'},

	-- used by <stdint.h> <stdlib.h>
	{inc='<_types/_uint32_t.h>', out='OSX/c/_types/_uint32_t.lua'},

	-- used by <stdint.h> <stdlib.h>
	{inc='<_types/_uint64_t.h>', out='OSX/c/_types/_uint64_t.lua'},

	-- used by <stdint.h> <stdlib.h>
	{inc='<_types/_intmax_t.h>', out='OSX/c/_types/_intmax_t.lua'},

	-- used by <stdint.h> <stdlib.h>
	{inc='<_types/_uintmax_t.h>', out='OSX/c/_types/_uintmax_t.lua'},

	-- used by <fcntl.h> <stdlib.h>
	{inc='<sys/_types/_mode_t.h>', out='OSX/c/sys/_types/_mode_t.lua'},

	-- used by <fcntl.h> <stdio.h>
	{inc='<sys/_types/_off_t.h>', out='OSX/c/sys/_types/_off_t.lua'},

	-- used by <fcntl.h> <time.h>
	{inc='<sys/_types/_timespec.h>', out='OSX/c/sys/_types/_timespec.lua'},

	-- used by <unistd.h> <stdio.h>
	{inc='<_ctermid.h>', out='OSX/c/_ctermid.lua'},

	-- used by <unistd.h> <stdlib.h>
	{inc='<sys/_types/_timeval.h>', out='OSX/c/sys/_types/_timeval.lua'},

	-- used by <unistd.h> <time.h>
	{inc='<sys/_types/_time_t.h>', out='OSX/c/sys/_types/_time_t.lua'},

	-- used by <unistd.h> <stdlib.h>
	{inc='<sys/_types/_dev_t.h>', out='OSX/c/sys/_types/_dev_t.lua'},

	-- used by <sys/select.h> <unistd.h>
	{inc='<sys/_types/_fd_def.h>', out='OSX/c/sys/_types/_fd_def.lua'},

	-- used by <sys/select.h> <unistd.h>
	{inc='<sys/_types/_suseconds_t.h>', out='OSX/c/sys/_types/_suseconds_t.lua'},

	-- used by <sys/select.h> <unistd.h>
	{inc='<sys/_select.h>', out='OSX/c/sys/_select.lua'},

	-- used by <sys/stat.h> <dirent.h>
	{inc='<sys/_types/_ino_t.h>', out='OSX/c/sys/_types/_ino_t.lua'},

	-- used by <sys/stat.h> <unistd.h>
	{inc='<sys/_types/_gid_t.h>', out='OSX/c/sys/_types/_gid_t.lua'},

	-- used by <sys/stat.h> <fcntl.h>
	{inc='<sys/_types/_filesec_t.h>', out='OSX/c/sys/_types/_filesec_t.lua'},

	-- used by <sys/types.h> <stdlib.h>
	{inc='<machine/endian.h>', out='OSX/c/machine/endian.lua'},

	-- used by <sys/types.h> <sys/stat.h>
	{inc='<sys/_types/_blkcnt_t.h>', out='OSX/c/sys/_types/_blkcnt_t.lua'},

	-- used by <sys/types.h> <sys/stat.h>
	{inc='<sys/_types/_blksize_t.h>', out='OSX/c/sys/_types/_blksize_t.lua'},

	-- used by <sys/types.h> <sys/stat.h>
	{inc='<sys/_types/_ino64_t.h>', out='OSX/c/sys/_types/_ino64_t.lua'},

	-- used by <sys/types.h> <sys/stat.h>
	{inc='<sys/_types/_nlink_t.h>', out='OSX/c/sys/_types/_nlink_t.lua'},

	-- used by <sys/types.h> <stdlib.h>
	{inc='<sys/_types/_id_t.h>', out='OSX/c/sys/_types/_id_t.lua'},

	-- used by <sys/types.h> <time.h>
	{inc='<sys/_types/_clock_t.h>', out='OSX/c/sys/_types/_clock_t.lua'},

	-- used by <sys/types.h> <unistd.h>
	{inc='<sys/_types/_useconds_t.h>', out='OSX/c/sys/_types/_useconds_t.lua'},

	-- used by <sys/types.h> <string.h>
	{inc='<sys/_types/_rsize_t.h>', out='OSX/c/sys/_types/_rsize_t.lua'},

	-- used by <pthread.h> <signal.h>
	{inc='<sys/_pthread/_pthread_t.h>', out='OSX/c/sys/_pthread/_pthread_t.lua'},

	-- used by <sched.h> <pthread.h>
	{inc='<pthread/pthread_impl.h>', out='OSX/c/pthread/pthread_impl.lua'},

	-- used by <sys/types.h> <pthread.h>
	{inc='<sys/_pthread/_pthread_cond_t.h>', out='OSX/c/sys/_pthread/_pthread_cond_t.lua'},

	-- used by <sys/types.h> <pthread.h>
	{inc='<sys/_pthread/_pthread_condattr_t.h>', out='OSX/c/sys/_pthread/_pthread_condattr_t.lua'},

	-- used by <sys/types.h> <pthread.h>
	{inc='<sys/_pthread/_pthread_mutex_t.h>', out='OSX/c/sys/_pthread/_pthread_mutex_t.lua'},

	-- used by <sys/types.h> <pthread.h>
	{inc='<sys/_pthread/_pthread_mutexattr_t.h>', out='OSX/c/sys/_pthread/_pthread_mutexattr_t.lua'},

	-- used by <sys/types.h> <pthread.h>
	{inc='<sys/_pthread/_pthread_once_t.h>', out='OSX/c/sys/_pthread/_pthread_once_t.lua'},

	-- used by <sys/types.h> <pthread.h>
	{inc='<sys/_pthread/_pthread_rwlock_t.h>', out='OSX/c/sys/_pthread/_pthread_rwlock_t.lua'},

	-- used by <sys/types.h> <pthread.h>
	{inc='<sys/_pthread/_pthread_rwlockattr_t.h>', out='OSX/c/sys/_pthread/_pthread_rwlockattr_t.lua'},

	-- used by <sys/types.h> <pthread.h>
	{inc='<sys/_pthread/_pthread_key_t.h>', out='OSX/c/sys/_pthread/_pthread_key_t.lua'},


--]====] -- END INTERNALLY REQUESTED

	----------------------- ISO/POSIX STANDARDS: -----------------------

		------------ ISO/IEC 9899:1990 (C89, C90) ------------

	-- in list: Windows Linux OSX
	{inc='<stddef.h>', out='OSX/c/stddef.lua'},

	-- in list: Windows Linux OSX
	{inc='<string.h>', out='OSX/c/string.lua'},

	-- in list: Windows Linux OSX
	{
		inc = '<time.h>',
		out = 'OSX/c/time.lua',
		final = function(code)
			code = removeAttrAvailability(code)
			return code
		end,
	},

	-- in list: Windows Linux OSX
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

	-- ISO/IEC 9899:1999 (C99)
	-- ... but it has to go above <stdlib.h>
	-- in list: Windows Linux OSX
	{inc='<stdint.h>', out='OSX/c/stdint.lua'},

	-- in list: Windows Linux OSX
	{
		inc = '<stdlib.h>',
		out = 'OSX/c/stdlib.lua',
		final = function(code)
			code = removeAttrAvailability(code)
			return code
		end,
	},

	-- in list: Windows Linux OSX
	{inc='<limits.h>', out='OSX/c/limits.lua', final=function(code)
		--[[ these ones are converting int64->double and failing
		-- but i switched preprocessor methods to builtin gcc and now it's just not substituting at all ...
		code = removeEnum(code, string.patescape"LONG_MAX = 9.2233720368548e+18")
		code = removeEnum(code, string.patescape"LONG_MIN = -9.2233720368548e+18")
		code = removeEnum(code, string.patescape"ULONG_MAX = 1.844674407371e+19")
		code = removeEnum(code, string.patescape"LLONG_MAX = 9.2233720368548e+18")
		code = removeEnum(code, string.patescape"LLONG_MIN = -9.2233720368548e+18")
		code = removeEnum(code, string.patescape"LONG_LONG_MAX = 9.2233720368548e+18")
		code = removeEnum(code, string.patescape"LONG_LONG_MIN = -9.2233720368548e+18")
		--]]
		code = table{
			code,
			[[
-- add in values that can't be ffi.cdef enum'd
local wrapper = setmetatable({}, {__index=ffi.C})
wrapper.LONG_MAX = 0x7FFFFFFFFFFFFFFFLL
wrapper.LONG_MIN = -wrapper.LONG_MAX - 1LL
wrapper.ULONG_MAX = 0xFFFFFFFFFFFFFFFFULL
wrapper.LLONG_MAX = wrapper.LONG_MAX
wrapper.LONG_LONG_MIN = wrapper.LONG_MIN
wrapper.LONG_LONG_MAX = wrapper.LONG_MAX
wrapper.LLONG_MIN = wrapper.LONG_MIN
return wrapper
]],
		}:concat'\n'
		return code
	end},

	-- in list: Windows Linux OSX
	{inc='<setjmp.h>', out='OSX/c/setjmp.lua'},

	-- in list: Windows Linux OSX
	{inc='<stdarg.h>', out='OSX/c/stdarg.lua'},

	-- in list: Windows Linux OSX
	{
		inc = '<stdio.h>',
		out = 'OSX/c/stdio.lua',
		final = function(code)
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
		out = 'OSX/c/math.lua',
		final = function(code)
			-- idk how to handle luajit and _Float16 for now so ...
			code = string.split(code, '\n'):filter(function(l)
				return not l:find'_Float16'
			end):concat'\n'
			-- [[ remove defines of floats
			code = removeEnum(code, string.patescape'M_E = 2.71828182845904523536028747135266250')
			code = removeEnum(code, string.patescape'M_LOG2E = 1.44269504088896340735992468100189214')
			code = removeEnum(code, string.patescape'M_LOG10E = 0.434294481903251827651128918916605082')
			code = removeEnum(code, string.patescape'M_LN2 = 0.693147180559945309417232121458176568')
			code = removeEnum(code, string.patescape'M_LN10 = 2.30258509299404568401799145468436421')
			code = removeEnum(code, string.patescape'M_PI = 3.14159265358979323846264338327950288')
			code = removeEnum(code, string.patescape'M_PI_2 = 1.57079632679489661923132169163975144')
			code = removeEnum(code, string.patescape'M_PI_4 = 0.785398163397448309615660845819875721')
			code = removeEnum(code, string.patescape'M_1_PI = 0.318309886183790671537767526745028724')
			code = removeEnum(code, string.patescape'M_2_PI = 0.636619772367581343075535053490057448')
			code = removeEnum(code, string.patescape'M_2_SQRTPI = 1.12837916709551257389615890312154517')
			code = removeEnum(code, string.patescape'M_SQRT2 = 1.41421356237309504880168872420969808')
			code = removeEnum(code, string.patescape'M_SQRT1_2 = 0.707106781186547524400844362104849039')
			code = removeEnum(code, string.patescape'X_TLOSS = 1.41484755040568800000e+16')
			code = table{
				code,
				[[
-- add in values that can't be ffi.cdef enum'd
local wrapper = setmetatable({}, {__index=ffi.C})
wrapper.M_E = 2.71828182845904523536028747135266250
wrapper.M_LOG2E = 1.44269504088896340735992468100189214
wrapper.M_LOG10E = 0.434294481903251827651128918916605082
wrapper.M_LN2 = 0.693147180559945309417232121458176568
wrapper.M_LN10 = 2.30258509299404568401799145468436421
wrapper.M_PI = 3.14159265358979323846264338327950288
wrapper.M_PI_2 = 1.57079632679489661923132169163975144
wrapper.M_PI_4 = 0.785398163397448309615660845819875721
wrapper.M_1_PI = 0.318309886183790671537767526745028724
wrapper.M_2_PI = 0.636619772367581343075535053490057448
wrapper.M_2_SQRTPI = 1.12837916709551257389615890312154517
wrapper.M_SQRT2 = 1.41421356237309504880168872420969808
wrapper.M_SQRT1_2 = 0.707106781186547524400844362104849039
wrapper.X_TLOSS = 1.41484755040568800000e+16
return wrapper
]],
			}:concat'\n'
			--]]
			return code
		end,
	},

	-- in list: Linux OSX
	{
		inc = '<signal.h>',
		out = 'OSX/c/signal.lua',
		final = function(code)
			code = fixEnumsAndDefineMacrosInterleaved(code)
			return code
		end,
	},

		------------ ISO/IEC 9899:1990/Amd.1:1995 ------------

	-- in list: Windows Linux OSX
	-- depends on <stdio.h> <machine/_types.h>
	{inc='<wchar.h>', out='OSX/c/wchar.lua'},

		------------ ISO/IEC 9899:1999 (C99) ------------

	-- in list: Windows Linux OSX
	-- identical in windows linux osx ...
	{
		inc = '<stdbool.h>',
		out = 'OSX/c/stdbool.lua',
		final = function(code)
			-- luajit has its own bools already defined
			for _,k in ipairs{'true = 1', 'false = 0'} do
				code = removeEnum(code, k)
			end
			return code
		end,
	},

	-- in list: Linux OSX
	-- depends on <machine/_types.h>
	{inc='<inttypes.h>', out='OSX/c/inttypes.lua'},

	-- in list: Windows Linux OSX
	-- used by CBLAS
	{
		inc = '<complex.h>',
		out = 'OSX/c/complex.lua',
		enumGenUnderscoreMacros = true,
		final = function(code)
			code = commentOutLine(code, 'enum { complex = 0 };')
			return code
		end,
	},

		------------ ISO/IEC 9045:2008 (POSIX 2008, Single Unix Specification) ------------

	-- in list: Linux OSX
	-- depends on <_types.h>
	{
		inc = '<dirent.h>',
		out = 'OSX/c/dirent.lua',
		final = function(code)
			-- how come __BLOCKS__ is defined ...
			-- TODO disable __BLOCKS__ to omit these:
			code = string.split(code, '\n'):filter(function(l)
				return not l:find'_b%('
			end):concat'\n'
			return code
		end,
	},

	-- in list: Windows Linux OSX
	{inc='<fcntl.h>', out='OSX/c/fcntl.lua'},

	-- in list: Linux OSX
	{
		inc = '<pthread.h>',
		out = 'OSX/c/pthread.lua',
		final = function(code)
			code = removeAttrAvailability(code)
			code = fixEnumsAndDefineMacrosInterleaved(code)
			return code
		end,
	},

	-- in list: Linux OSX
	{inc='<sched.h>', out='OSX/c/sched.lua'},

	-- in list: Linux OSX
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

	-- in list: Windows Linux OSX
	{inc='<sys/mman.h>', out='OSX/c/sys/mman.lua'},

	-- in list: Linux OSX
	-- has to go above <unistd.h>
	{inc='<sys/select.h>', out='OSX/c/sys/select.lua'},

	-- in list: Windows Linux OSX
	{
		inc = '<unistd.h>',
		out = 'OSX/c/unistd.lua',
		final = function(code)
			-- for interchangeability with Windows ...
			code = code .. [[
return ffi.C
]]
			return code
		end,
	},
	
	-- depends on <_types.h> <sys/_types/_timespec.h> <machine/_types.h>
	-- in list: Windows Linux OSX
	{
		inc = '<sys/stat.h>',
		out = 'OSX/c/sys/stat.lua',
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
	-- depends on <sys/_types/_timespec.h> <sys/_types/_fd_def.h> <machine/_types.h>
	{
		inc = '<sys/time.h>',
		out = 'OSX/c/sys/time.lua',
		final = function(code)
			code = fixEnumsAndDefineMacrosInterleaved(code)
			return code
		end,
	},

	-- in list: Windows Linux OSX
	-- depends on <_types.h> <sys/_types/_fd_def.h> <machine/_types.h> <machine/endian.h>
	{inc='<sys/types.h>', out='OSX/c/sys/types.lua'},

	----------------------- OS-SPECIFIC & EXTERNALLY REQUESTED BY 3RD PARTY LIBRARIES: -----------------------

}:mapi(function(inc)
	inc.os = 'OSX'
	return inc
end)
