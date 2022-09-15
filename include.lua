--[[
This is a spin off my preproc/generate.lua file
Once it's flushed out I won't need that file anymore (but maybe will keep for kicks)

ok I think i see where things will be going ...
generating .h files is a bad idea, instead I should generate .lua files that have inline'd cdef header code where the old header code went, and have include()'s where the old #include's went

so in this .lua ...
- i should be inserting manual preproc.macro[k] = v code for when a macro is set
- i should also be (doubly) inserting ffi.cdef' enum { k = v; } ' when a macro is set to a value
- and for all the other lines, i should be ffi.cdef'ing them .. but the ffi.cdef shouldn't split lines ... hmm ...


hmm but what about preprocessor state between includes?

it is seeming more and more like preproc, include, and lua-ffi-bindings should all be merged

--]]
local ffi = require 'ffi'		-- used for OS check and used for verifying that the generated C headers are luajit-ffi compatible
local file = require 'ext.file'
local io = require 'ext.io'
local os = require 'ext.os'
local string = require 'ext.string'
local fromlua = require 'ext.fromlua'
local tolua = require 'ext.tolua'

--[[ can't use this because ext.timer uses ffi.c.sys.time which uses include
local timer = require 'ext.timer'.timer
--]]
-- [[ so inline it here
function timer(name, cb, ...)
	io.stderr:write(name..'...\n')
	io.stderr:flush()
	local startTime = os.clock()
	cb(...)
	local endTime = os.clock()
	io.stderr:write('...done '..name..' ('..(endTime - startTime)..'s)\n')
	io.stderr:flush()
end
--]]

local table = require 'ext.table'
local class = require 'ext.class'
local Preproc = class(require 'preproc')


local cachebasedir = os.getenv'LUAJIT_INCLUDE_CACHE_PATH'
if not cachebasedir then
	local home = os.getenv'HOME' or os.getenv'USERPROFILE'
	assert(home, "Don't know where to store the cache.  maybe set the LUAJIT_INCLUDE_CACHE_PATH environment variable.")
	cachebasedir = home..'/.luajit.include'
end
file(cachebasedir):mkdir(true)


-- This is where you include Lua files from
-- Can it be auto-determined?  Search through all LUA_PATH / package.path, 
--  see if there is some value we can replace the ? with such that the path resolves to our LUAJIT_INCLUDE_CACHE_PATH
local cachebaserequire = os.getenv'LUAJIT_INCLUDE_REQUIRE_BASE'	-- = 'ffi.include-cache'
-- cheap trick until then, just find a substring
if not cachebaserequire then
	local paths = string.split(package.path, ';')
	for _,path in ipairs(paths) do
		-- remove up to first ?
		local i = path:find('?', 1, true)
		if i then
			path = path:sub(1, i-1)
		-- else ... how can there be a LUA_PATH option without any ?'s in it?
		end
		if path:sub(#path,#path) == '/' then	-- this has to be true, right?  unless there are LUA_PATH entries that insert the require() field midway through a file name
			if #path < #cachebasedir
			and path == cachebasedir:sub(1, #path)
			then
				local rest = cachebasedir:sub(#path+1)
				cachebaserequire = rest:gsub('/', '.') .. '.'
				print('found cachebaserequire '..cachebaserequire)
			end
		end
	end
end
if not cachebaserequire	then
	error[[
Couldn't determine the root require() associated with your cache base dir.
If you haven't set LUAJIT_INCLUDE_CACHE_PATH then try setting that.
Otherwise it could be true that no LUA_PATH matches as a prefix of LUAJIT_INCLUDE_CACHE_PATH.
In that case, try setting LUAJIT_INCLUDE_REQUIRE_BASE.]]
end


function Preproc:getDefineCode(k, v, ...)
	Preproc.super.getDefineCode(self, k, v, ...)
	-- TODO if we are mid-defining a struct then I need to push this to the next line
	-- why so much shitty C in linux standard headers?
	-- [[
	return table{
		']]',
		"preproc.macros["..tolua(k).."] = "..tolua(v),
		'ffi.cdef[[',
	}:concat'\n'
	--]]
end

--[[
ok here's our dilemma ...
	#include <GL/gl.h>
	#include <GL/glext.h>
to use glext.h , you must include gl.h first
because glext.h needs the state from gl.h
...
so if we are including system headers, like
	#include <stdio.h>
then we want our state cleared for the sake of caching (for the most part, right?)
but in other cases, like our glext.h example, we don't
--]]
-- [=[
function Preproc:getIncludeFileCode(found, search)
	if search == 'stdc-predef' then return '' end

	print('#include', self, search, found)

	-- ok here ...
	-- (only for certain #include's ?)
	-- push the macros?
	-- then do the include on this file (how?  I'd say pass it 'search' and assert the lookup matches 'found' ...  or pass it the contents of 'found'?)
	-- then cache it same as always
	-- then restore macros

	-- [[ ok first attempt without the push/pop of macros
	require 'include' (search)
	--return code
	--[==[ I could use include here
	return table{
		']]',
		"include('"..search.."')",
		'ffi.cdef[[',
	}:concat'\n'
	--]==]
	-- [==[ or I could use require
	local incdir, incbasename = file('./'..search):getdir()
	local savedir = incdir
	local incbasenamewoext = file(incbasename):getext()
print("savedir..'/'..incbasenamewoext", savedir..'/'..incbasenamewoext)
	local requirefilename = (savedir..'/'..incbasenamewoext)
		:gsub('/%./', '/')
		:gsub('//', '/')
		:gsub('^/', '')
		:gsub('^%./', '')
		:gsub('/', '.')
	requirefilename = cachebaserequire..requirefilename
print('requirefilename', requirefilename)
	return table{
		"]]",
		"require '"..requirefilename.."'",
		"ffi.cdef[[",
	}:concat'\n'
	--]==]
	--]] -- inf loop
	--[[ try again
	local sub = Preproc()
	sub.macros = table(self.macros)
	sub.sysIncludeDirs = table(self.sysIncludeDirs)
	sub.userIncludeDirs = table(self.userIncludeDirs)
	-- but this wont cache correctly...
	local code = sub((assert(file(found):read())))
	-- TODO at this point the .h will be cached ... how about reading the cache instead of handling it a second time?
	-- now forward the state
	for k,v in pairs(table(sub.macros)) do self.macros[k] = v end
	--return code	-- TODO don't -- because enum's lhs names will be re-evaluated
	return ''
	--]]
end
--]=]

-- TODO how about some scope?
-- TODO TODO we really need to turn our `#include <...>`'s into `require 'include' '...'`'s
local preproc = Preproc()

-- don't do this or it'll mess up our inserted lua code
preproc.joinNonSemicolonLines = false

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
print('results')
print(results)
	assert(results:match'include')
	assert(results:match('#include'))	-- why doesn't this match?
	assert(results:match'#include "%.%.%." search starts here:')
	local userSearchStr, sysSearchStr = results:match'#include "%.%.%." search starts here:(.-)#include <%.%.%.> search starts here:(.-)End of search list%.'
	assert(userSearchStr)
print('userSearchStr')
print(userSearchStr)
print('sysSearchStr')
print(sysSearchStr)
	local userSearchDirs = string.split(string.trim(userSearchStr), '\n'):mapi(string.trim)
	local sysSearchDirs = string.split(string.trim(sysSearchStr), '\n'):mapi(string.trim)
print('userSearchDirs')
print(tolua(userSearchDirs))
print('sysSearchDirs')
print(tolua(sysSearchDirs))
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
#define __has_warning(x)		0
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

--[[
	local inccode = '#include '
		..(sysinc and '<' or '"')
		..filename
		..(sysinc and '>' or '"')
		..'\n'
-- search through headers and process them before processing this header?
-- sounds nice, but gcc -M will only give you back the resolved include filenames
-- I think for caching's sake I will want the original #include names
-- and this means that I most likely want an #include callback in preproc

	local tmpbasefn = 'tmp'
	local tmpsrcfn = tmpbasefn..'.cpp'
	local tmpobjfn = './'..tmpbasefn..'.o'	-- TODO getDependentHeaders and paths and objs ...
	file(tmpsrcfn):write(table{
		inccode,
		'int tmp() {}',
	}:concat'\n')
	local deps = makeEnv:getDependentHeaders(tmpsrcfn, tmpobjfn)
	assert(deps:remove(1) == '/usr/include/stdc-predef.h')	-- hmm ... ?
print('inc deps:\n\t'..deps:concat'\n\t')
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

	local incdir, incbasename = file('./'..filename):getdir()
	local incbasenamewoext = file(incbasename):getext()
print('incdir', incdir)
print('incbasename', incbasename)

--[[ use the resolved #include path
	-- TODO another option - just use the gcc -m option to search include dependency graph
	-- use require 'make'.getDependentHeaders(src, obj)

	-- TODO since there's a macro for "get the next most file in the include search path"
	-- then maybe instead I should be storing these by their original file path
	-- and in that case ... use preproc:searchForInclude
	local searchfn = preproc:searchForInclude(filename, sysinc)
print('search', searchfn)
	if ffi.os == 'Windows' then
		-- Windows is stuck in the last century
		-- I guess the path separator has been changed to / by now?
		-- should I pattern match for LETTER:/ ... or is there some special-char like : that I can't ever use and should just always search for?
		local drive, rest = searchfn:match'^(%a):/(.*)$'
		if drive then
			searchfn = drive..'/'..rest
		end
print('search Windows fixed', searchfn)
	end
	local savedir = file(searchfn):getdir()
--]]
-- [[ or use the path in the #include lookup
-- (doesn't require a build environment / preproc to be present ... this way you can save the cache and do the #includes without preproc)
	local savedir = incdir
--]]

	--[[
	local cachedir = 'cache/'
		..(sysinc and 'sys/' or 'local/')
		..incdir
	--]]
	-- [[
	local cachedir = cachebasedir..'/'..savedir
	--]]
print('cachedir', cachedir)
	file(cachedir):mkdir(true)

	local code
	local cachefilename = cachedir..'/'..incbasenamewoext..'.lua'
print('cachefilename', cachefilename)
	if file(cachefilename):exists() then
print('file exists')
	else
print'preprocessing...'
		timer('preprocessing '..filename, function()
			--[[ let the preproc find the file
			local inccode = '#include '
				..(sysinc and '<' or '"')
				..filename
				..(sysinc and '>' or '"')
				..'\n'
			code = preproc(inccode)
			--]]
			-- [[ use the preproc search and load it ourselves
			-- this way the includeCallback doesn't get stuck on repeat
			local searchfn = assert(preproc:searchForInclude(filename, sysinc))
			code = preproc((assert(file(searchfn):read())))
			--]]
		end)
print'writing...'
		
		local luacode = table{
			"local ffi = require 'ffi'",
			"local include = require 'include'",
			"local preproc = include.preproc",
			'ffi.cdef[[',
			-- TODO replace define's with lua statements that insert into include.preproc.macros[k] = v
			code,
			']]',
			'lib = ffi.C',	-- TODO don't do this, and instead do lib = ffi.load if it's needed
			'return lib',
		}:concat'\n'

		luacode = luacode
			:gsub('ffi%.cdef%[%[\n%]%]', '')
			:gsub('\n\n*', '\n')

		-- TODO remove any single-line cdefs of C comments and replace with Lua comments
		-- or just override the Preproc function for generating C comments, and instead generate a lua comment?

		file(cachefilename):write(luacode)
	end


	-- assume cachedir is also in LUA_PATH?
print("savedir..'/'..incbasenamewoext", savedir..'/'..incbasenamewoext)
	local requirefilename = (savedir..'/'..incbasenamewoext)
		:gsub('/%./', '/')
		:gsub('//', '/')
		:gsub('^/', '')
		:gsub('^%./', '')
		:gsub('/', '.')
	requirefilename = cachebaserequire..requirefilename
print('requirefilename', requirefilename)

	return require(requirefilename)
end

return setmetatable({
	preproc = preproc,
}, {
	__call = function(self, ...)
		return include(...)
	end,
})
