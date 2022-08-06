local ffi = require 'ffi'		-- used for OS check and used for verifying that the generated C headers are luajit-ffi compatible
local io = require 'ext.io'
local os = require 'ext.os'
local string = require 'ext.string'
local tolua = require 'ext.tolua'
local timer = require 'ext.timer'.timer

local Preproc = require 'preproc'
local preproc = Preproc()

if ffi.os == 'Windows' then
	-- I guess pick these to match the compiler used to build luajit
	-- TODO this could work if my macro evaluator could handle undef'd comparisons <=> replace with zero
	preproc:setMacros{
		-- don't define this or khrplatform explodes with stdint.h stuff
		--__STDC_VERSION__ = '201710L',	-- c++17
		--__STDCPP_THREADS__ = '0',
		
		_MSC_VER = '1929',
		_MSC_FULL_VER = '192930038',
		_MSVC_LANG = '201402',
		_MSC_BUILD = '1',

	-- choose which apply:
		_M_AMD64 = '100',
		--_M_ARM = '7',
		--_M_ARM_ARMV7VE = '1',
		--_M_ARM64 = '1',
		--_M_IX86 = '600',
		_M_X64 = '100',

		_WIN32 = '1',
		_WIN64 = '1',
	}

	--[[ does this just setup the preproc state?
	-- or is there typedef stuff in here too?
	-- if so then feed it to ffi
	-- it gets into varargs and stringizing ...
	preproc'#include <windows.h>'
	--]]
	-- [[
	preproc:setMacros{
		-- these are used in gl.h, but where are they defined? probably windows.h
		WINGDIAPI = '',
		APIENTRY = '',
	}
	--]]

	-- TODO better way to configure this for everyone ...
	preproc:addIncludeDir(os.getenv'USERPROFILE'..'/include', true)

else	-- assume everything else uses gcc
	assert(os.execute'g++ --version > /dev/null 2>&1', "failed to find gcc")	-- make sure we have gcc
	preproc(io.readproc'g++ -dM -E - < /dev/null 2>&1')

	local results = io.readproc'g++ -xc++ -E -v - < /dev/null 2>&1'
--print('results')
--print(results)
	assert(results:match'include')
	assert(results:match('#include'))	-- why doesn't this match? 
	assert(results:match'#include "%.%.%." search starts here:')
	local userSearchStr, sysSearchStr = results:match'#include "%.%.%." search starts here:(.-)#include <%.%.%.> search starts here:(.-)End of search list%.'
	assert(userSearchStr)
--print('userSearchStr')
--print(userSearchStr)
--print('sysSearchStr')
--print(sysSearchStr)
	local userSearchDirs = string.split(string.trim(userSearchStr), '\n'):mapi(string.trim)
	local sysSearchDirs = string.split(string.trim(sysSearchStr), '\n'):mapi(string.trim)
--print('userSearchDirs')
--print(tolua(userSearchDirs))
--print('sysSearchDirs')
--print(tolua(sysSearchDirs))
	preproc:addIncludeDirs(userSearchDirs, false)
	preproc:addIncludeDirs(sysSearchDirs, true)

	-- how to handle gcc extension macros?
	preproc[[
#define __has_feature(x)		0
#define __has_extension(x)		0
#define __has_attribute(x)		0
#define __has_cpp_attribute(x)	0
#define __has_c_attribute(x)	0
#define __has_builtin(x)		0
#define __has_include(x)		0
#define __asm__(x)
]]
end

--[[ bad idea?
local MakeEnv = require 'make.env'
local makeEnv = MakeEnv()
-- can't do this
-- makeEnv:setupBuild'release'
-- so instead...
local table = require 'ext.table'
function makeEnv:resetMacros() self.macros = table() end
makeEnv:preConfig()
makeEnv.compileGetIncludeFilesFlag = '-M'	-- gcc default is -MM, which skips system files
local file = require 'ext.file'
--]]

--[[
filename = what goes in the rhs of the #include
sysinc = true for #include <...>, false for #include "..."
--]]
local function include(filename, sysinc)
	if sysinc == nil then
		if filename:match'^".*"$' then
			filename = filename:sub(2,-2)
			sysinc = false
		elseif filename:match'^<.*>$' then
			filename = filename:sub(2,-2)
			sysinc = true
		end
	end

	local inccode = '#include '
		..(sysinc and '<' or '"')
		..filename
		..(sysinc and '>' or '"')
		..'\n'

--[[
	local tmpbasefn = 'tmp'
	local tmpsrcfn = tmpbasefn..'.cpp'
	local tmpobjfn = './'..tmpbasefn..'.o'	-- TODO getDependentHeaders and paths and objs ...
	file[tmpsrcfn] = table{
		inccode,
		'int tmp() {}',
	}:concat'\n'
	local deps = makeEnv:getDependentHeaders(tmpsrcfn, tmpobjfn)
	assert(deps:remove(1) == '/usr/include/stdc-predef.h')	-- hmm ... ?
--print('inc deps:\n\t'..deps:concat'\n\t')
--]]
--[[
<stdio.h> dependencies (minus /usr/include/stdc-predef.h which is on all of them)
	/usr/include/stdio.h
	/usr/include/x86_64-linux-gnu/bits/libc-header-start.h
	/usr/include/features.h
	/usr/include/x86_64-linux-gnu/sys/cdefs.h
	/usr/include/x86_64-linux-gnu/bits/wordsize.h
	/usr/include/x86_64-linux-gnu/bits/long-double.h
	/usr/include/x86_64-linux-gnu/gnu/stubs.h
	/usr/include/x86_64-linux-gnu/gnu/stubs-64.h
	/usr/lib/gcc/x86_64-linux-gnu/9/include/stddef.h
	/usr/lib/gcc/x86_64-linux-gnu/9/include/stdarg.h
	/usr/include/x86_64-linux-gnu/bits/types.h
	/usr/include/x86_64-linux-gnu/bits/timesize.h
	/usr/include/x86_64-linux-gnu/bits/typesizes.h
	/usr/include/x86_64-linux-gnu/bits/time64.h
	/usr/include/x86_64-linux-gnu/bits/types/__fpos_t.h
	/usr/include/x86_64-linux-gnu/bits/types/__mbstate_t.h
	/usr/include/x86_64-linux-gnu/bits/types/__fpos64_t.h
	/usr/include/x86_64-linux-gnu/bits/types/__FILE.h
	/usr/include/x86_64-linux-gnu/bits/types/FILE.h
	/usr/include/x86_64-linux-gnu/bits/types/struct_FILE.h
	/usr/include/x86_64-linux-gnu/bits/types/cookie_io_functions_t.h
	/usr/include/x86_64-linux-gnu/bits/stdio_lim.h
	/usr/include/x86_64-linux-gnu/bits/sys_errlist.h

so I should go through this list and search and include stuff, one by one?
yeah?

stdc-predef.h is probably always there ... and for generating <stdio.h> it contributes nothing ... I think just macros?
	for that matter, I will have to cache more than just the file results ... like the preproc state as well ...
	macros etc
--]]

--[[ hmm TODO eventually, separately include dependencies, only when the dependency doesn't need macros provided from the current file
-- but establishing that is tough
	for i=2,#deps do
		include(deps[i], true)	-- true for sys?  hmm, inc vs abs filename 
	end
--]]

	local incdir, incbasename = io.getfiledir('./'..filename)
--print('incdir', incdir)
--print('incbasename', incbasename) 

--[[ use the resolved #include path 
	-- TODO another option - just use the gcc -m option to search include dependency graph
	-- use require 'make'.getDependentHeaders(src, obj)

	-- TODO since there's a macro for "get the next most file in the include search path" 
	-- then maybe instead I should be storing these by their original file path
	-- and in that case ... use preproc:searchForInclude
	local searchfn = preproc:searchForInclude(filename, sysinc)
--print('search', searchfn)
	if ffi.os == 'Windows' then
		-- Windows is stuck in the last century
		-- I guess the path separator has been changed to / by now?
		-- should I pattern match for LETTER:/ ... or is there some special-char like : that I can't ever use and should just always search for?
		local drive, rest = searchfn:match'^(%a):/(.*)$'
		if drive then
			searchfn = drive..'/'..rest
		end
--print('search Windows fixed', searchfn)
	end
	local savedir = io.getfiledir(searchfn)
--]]
-- [[ or use the path in the #include lookup 
-- (doesn't require a build environment / preproc to be present ... this way you can save the cache and do the #includes without preproc)
	local savedir = incdir
--]]

	local cachebasedir = os.getenv'LUAJIT_INCLUDE_CACHE_PATH'
	if not cachebasedir then
		local home = os.getenv'HOME' or os.getenv'USERPROFILE'
		assert(home, "Don't know where to store the cache.  maybe set the LUAJIT_INCLUDE_CACHE_PATH environment variable.")
		cachebasedir = home..'/.luajit.include'
	end
	os.mkdir(cachebasedir, true)
	
	--[[
	local cachedir = 'cache/'
		..(sysinc and 'sys/' or 'local/')
		..incdir
	--]]
	-- [[
	local cachedir = cachebasedir..'/'..savedir
	--]]
--print('cachedir', cachedir)	
	os.mkdir(cachedir, true)

	local code
	local cachefilename = cachedir..'/'..incbasename
--print('cachefilename', cachefilename)	
	if os.fileexists(cachefilename) then
--print'reading code...'
		code = assert(io.readfile(cachefilename))
	else
--print'preprocessing...'		
		timer('preprocessing '..filename, function()
			code = preproc(inccode)
		end)
--print'writing...'	
		io.writefile(cachefilename, code)

		-- NOTICE if I'm saving macros, i can't load them without an interruption to the preproc() at the #include point ...
		local cachestatefn = io.getfileext(cachefilename)..'.state.lua'
--print('saving macros to '..cachestatefn)
		
		-- NOTICE right now I'm not doing anything with this ...
		io.writefile(cachestatefn, tolua{
			macros = preproc.macros,
			alreadyIncludedFiles = preproc.alreadyIncludedFiles,
		})
	end

	local throwme
	xpcall(function()
--print"cdef'ing code:"
		ffi.cdef(code)
--print'success!'
	end, function(err)
--print"error:"
		throwme = 
--			'macros: '..tolua(preproc.macros)..'\n'..
			require 'template.showcode'(code)..'\n'
			..err..'\n'..debug.traceback()
	end)
	if throwme then
		error(throwme)
	end

	-- TODO return any 'ffi.load' ? or does that just return ffi.C itself?
	-- also TODO, doesn't the luajit ffi documentation say not to do this?
	-- but then ... is this the same as ffi.load()?  if it is ... isn't returning ffi.load() just as bad?
	-- how is ffi.load() different than ffi.C ?
	return code, ffi.C
end

return include
