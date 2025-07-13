#!/usr/bin/env luajit
local ffi = require 'ffi'		-- used for OS check and used for verifying that the generated C headers are luajit-ffi compatible
local table = require 'ext.table'
local string = require 'ext.string'
local assert = require 'ext.assert'
local path = require 'ext.path'
local io = require 'ext.io'
local os = require 'ext.os'
local tolua = require 'ext.tolua'
local Preproc = require 'preproc'

local includeList = table(require 'include.include-list')


local ThisPreproc = Preproc:subclass()

function ThisPreproc:init(...)
	ThisPreproc.super.init(self, ...)

	-- here's where #define-generated enums will go
	self.luaGenerateEnums = {}
	-- ... same populated in-order with {[k] = v}
	self.luaGenerateEnumsInOrder = table()

	-- this is assigned when args are processed
	self.luaBindingIncFiles = table()
end

-- [===============[ begin the code for injecting require()'s to previously-generated luajit files

local cNumberSuffixes = table{'', 'u', 'l', 'z', 'ul', 'lu', 'uz', 'll', 'ull'}

function ThisPreproc:getDefineCode(k, v, l)
	ThisPreproc.super.getDefineCode(self, k, v, l)
--DEBUG:print('//', tolua(k), tolua(v), tolua(l))

	-- handle our enums

	if type(v) == 'string' 	-- exclude the arg-based macros from this -- they will have table values
	-- ok in luajit you only have so many enums you can use
	-- an I'm hitting that limit
	-- so here's a shot in the dark:
	-- exclude any macros that begin with _ for enum-generation, and assume they are only for internal use
	and (self.enumGenUnderscoreMacros or k:sub(1,1) ~= '_')
	then

		-- try to evaluate the value
		-- TODO will this mess with incomplete macros
		--v = self:replaceMacros(v)

		-- ok if it's a preprocessor expression then we need it evaluated
		-- but it could be a non-preproc expression as well, in which case maybe it's a float?
		local origv = v
		pcall(function()
			v = ''..self:parseCondInt(v)
			-- parseCondExpr returns bool
		end)

		local vnumstr, vnum
		for _,suffix in ipairs(cNumberSuffixes) do
			vnumstr = v:lower():match('(.*)'..suffix..'$')
			-- TODO optional 's for digit separtors
			vnum = tonumber(vnumstr)
--[[ this fills up the ffi cdef ...
			if vnum then
-- ... extra check to verify that this is in fact an enum?
				LASTENUMCHECK = (LASTENUMCHECK or 0) + 1
				-- sometimes it will still fail ... like if it's a 64-bit value ... but I don't want to throw out u ul ull etc suffixes immediately, in case the value associated can still fit inside 32 bits ...
				if has_ffi and not pcall(ffi.cdef, "enum { ENUMCHECK"..LASTENUMCHECK.." = "..vnum.." }") then
					vnum = nil
					vnumstr = nil
				end
				break
			end
--]]
		end

		-- if the value string is a number define
		local isnumber = vnum
		local reason = 'UNDEFINED'
		if isnumber then
			-- ok Lua tonumber hack ...
			-- tonumber'0x10' converts from base 16 ..
			-- tonumber'010' converts from base 10 *NOT* base 8 ...
--DEBUG(Preproc:getDefineCode): print('line was', l)

			local oldv = self.luaGenerateEnums[k]
			if oldv then
				if oldv == v then
					return '/* redefining matching value: '..l..' */'
				else
					print('/* WARNING: redefining '..k..' from '..tostring(oldv)..' to '..tostring(v).. ' (originally '..tostring(origv)..') */')
					-- redefine the enum value as well?
					-- I think in the macro world doing a #define a 1 #define a 2 will get a == 2, albeit with a warning.
				end
			end

--DEBUG:assert.type(v, 'string')
			if self:luaWithinAGenerateFile() then
				self.luaGenerateEnums[k] = v
				self.luaGenerateEnumsInOrder:insert{[k] = v}
				reason = 'including in Lua enums'
			else
				reason = 'skipping, not a specified file: '..self.includeStack:last()
			end
		else
			-- string but not number ...
			if v ~= '' then
				reason = 'skipping, macro is not a number'
			elseif not self:luaWithinAGenerateFile() then
				reason = 'skipping, not a specified file: '..self.includeStack:last()
			else
				-- is it just '#define SOMETHING' ? then pretend that is '#define SOMETHING 1' and make an enum out of it:
				self.luaGenerateEnums[k] = 1
				self.luaGenerateEnumsInOrder:insert{[k] = '1'}
				reason = 'including in Lua enums'
			end
		end

		return '/* '..l..' ### '..reason..' '..tolua(v)..' */'
	-- otherwise if not a string then it's a macro with args or nil
	else
-- non-strings are most likely nil for undef or tables for arg macros
--		return '/* '..l..' ### '..tolua(v, {indent=false})..' */'
	end

--DEBUG(ThisPreproc:getDefineCode):do return '/* '..l..' ### '..tolua(v, {indent=false})..' */' end
	return ''
end

-- Returns true if the current file we're in is one of the ones we wanted to spit out bindigns for.
-- Used to determine what files to save and output enum-macros for, versus which to just save and only use for preprocessing.
function ThisPreproc:luaWithinAGenerateFile()
	if self.saveAllMacros then return true end
	if not self.luaIncMacroFiles then return true end	--  when defining builtins, luaIncMacroFiles isn't defined yet
	local cur = self.includeStack:last()
	for _,toInc in ipairs(self.luaIncMacroFiles) do
		-- TODO cache this search result?
		local toIncLoc =
			toInc:sub(1,1) == '/'
			and toInc
			or self:searchForInclude(toInc:sub(2,-2), toInc:sub(1,1) == '<')
--DEBUG:print('searching for', toInc, 'found', toIncLoc)
		if toIncLoc == cur then
			-- then we're in a file to output
			return true
		end
	end
end

-- 1) store the search => found include names, then
function ThisPreproc:getIncludeFileCode(fn, search, sys)
	self.mapFromIncludeToSearchFile
		= self.mapFromIncludeToSearchFile
		or {}
	if sys then
		self.mapFromIncludeToSearchFile[fn] = '<'..search..'>'
	else
		self.mapFromIncludeToSearchFile[fn] = '"'..search..'"'
	end
	return ThisPreproc.super.getIncludeFileCode(self, fn, search, sys)
end

-- 2) do a final pass replacing the BEGIN/END's of the found names
function ThisPreproc:__call(...)
	local code = ThisPreproc.super.__call(self, ...)
	local lines = string.split(code, '\n')

	local currentfile
	local currentluainc
	local newlines = table()
--DEBUG(require-replace):newlines:insert('/* self.luaBindingIncFiles: '..tolua(self.luaBindingIncFiles)..' */')
	for i,l in ipairs(lines) do
		-- skip the first BEGIN, cuz this is the BEGIN for the include we are currently generating.
		-- dont wanna swap out the whole thing
		if not currentfile then
			local beginfile = l:match'^/%* %+* BEGIN (.*) %*/$'
			if beginfile then
				local search = self.mapFromIncludeToSearchFile[beginfile]
				if search then
--DEBUG(require-replace):newlines:insert('/* search: '..tostring(search)..' */')
--DEBUG(require-replace):newlines:insert('/* ... checking self.luaBindingIncFiles: '..tolua(self.luaBindingIncFiles)..' */')
					-- if beginfile is one of the manually-included files then don't replace it here.
					if self.luaBindingIncFiles:find(nil, function(o)
						-- TODO if one is user then dont search for the other in sys, idk which way tho
						return search:sub(2,-2) == o:sub(2,-2)
					end) then
--DEBUG(require-replace):newlines:insert('/* ... is already in the generate.lua args */')
					else
						-- if it's found in includeList then ...
						local _, replinc = includeList:find(nil, function(o)
							-- if we're including a system file then it could be <> or ""
							if search:sub(1,1) == '"' then
								return o.inc:sub(2,-2) == search:sub(2,-2)
							else
								return o.inc == search
							end
						end)
						if not replinc then
--DEBUG(require-replace):newlines:insert("/* didn't find */")
						else
--DEBUG(require-replace):newlines:insert('/*  ... found: '..replinc.inc..' */')
							currentfile = beginfile
							currentluainc = replinc.out:match'^(.*)%.lua$':gsub('/', '.')
						end
					end
				end
			end
			newlines:insert(l)
		else
			-- find the end
			local endfile = l:match'^/%* %+* END   (.*) %*/$'
			if endfile and endfile == currentfile then
				-- hmm dilemma here
				-- currentluainc says where to write the file, which is in $os/$path or $os/$arch/$path or just $path depending on the level of overriding ...
				-- but the ffi.req *here* needs to just be $path
				-- but no promises of what the name scheme will be
				-- (TODO unless I include this info in the include-list.lua ... .specificdir or whatever...)
				-- so for now i'll just match
				currentluainc = currentluainc:match('^'..string.patescape(ffi.os)..'%.(.*)$') or currentluainc
				currentluainc = currentluainc:match('^'..string.patescape(ffi.arch)..'%.(.*)$') or currentluainc
				newlines:insert("]] require 'ffi.req' '"..currentluainc.."' ffi.cdef[[")
				-- clear state
				currentfile = nil
				currentluainc = nil
				newlines:insert(l)
			end
		end
	end

	-- [[
	-- split off all {'s into newlines?
	lines = newlines
	newlines = table()
	for _,l in ipairs(lines) do
		if l:match'^/%*.*%*/$' then
			newlines:insert(l)
		else
			l = string.trim(l)
			local i = 1
			i = l:find('{', i)
			if not i then
				newlines:insert(l)
			else
				local j = l:find('}', i+1)
				if j then
					newlines:insert(l)
				else
					newlines:insert(l:sub(1,i))
					l = string.trim(l:sub(i+1))
					--i = l:find('{', i+1)
					if l ~= '' then
						newlines:insert(l)
					end
				end
			end
		end
	end
	-- add the tab
	lines = newlines
	newlines = table()
	local intab
	for _,l in ipairs(lines) do
		if l:match'^/%*.*%*/$' then
			newlines:insert(l)
		else
			if l:sub(1,1) == '}' then intab = false end
			newlines:insert(intab and '\t'..l or l)
			if l:sub(-1) == '{' then intab = true end
		end
	end
	--]]

	return newlines:concat'\n'
end


--]===============] end the code for injecting require()'s to previously-generated luajit files



--[[
'inc' is one of the entries in the includeList
--]]
local function preprocessWithLuaPreprocessor(inc)

	local preproc = ThisPreproc()

	-- start out saving all (builtin & system) macros
	preproc.saveAllMacros = true

	-- don't even include these
	local skipincs = table()

	if ffi.os == 'Windows' then
		-- I guess pick these to match the compiler used to build luajit
		preproc[[
//#define __STDC_VERSION__	201710L	// c++17
//#define __STDCPP_THREADS__	0
#define _MSC_VER	1929
#define _MSC_FULL_VER	192930038
#define _MSVC_LANG	201402
#define _MSC_BUILD	1

// choose which apply:
#define _M_AMD64	100
//#define _M_ARM	7
//#define _M_ARM_ARMV7VE	1
//#define _M_ARM64	1
//#define _M_IX86	600
#define _M_X64	100

#define _WIN32	1
#define _WIN64	1

// used in the following to prevent inline functions ...
//	ucrt/corecrt_stdio_config.h
//	ucrt/corecrt_wstdio.h
//	ucrt/stdio.h
//	ucrt/corecrt_wconio.h
//	ucrt/conio.h
#define _NO_CRT_STDIO_INLINE 1

// This one is linked to inline functions (and other stuff maybe?)
// in a few more files...
//	ucrt/corecrt.h
//	ucrt/corecrt_io.h
//	ucrt/corecrt_math.h
//	ucrt/corecrt_startup.h
//	ucrt/corecrt_stdio_config.h
//	ucrt/corecrt_wprocess.h
//	ucrt/corecrt_wstdio.h
//	ucrt/corecrt_wstdlib.h
//	ucrt/direct.h
//	ucrt/dos.h
//	ucrt/errno.h
//	ucrt/fenv.h
//	ucrt/locale.h
//	ucrt/mbctype.h
//	ucrt/mbstring.h
//	ucrt/process.h
//	ucrt/stddef.h
//	ucrt/stdio.h
//	ucrt/stdlib.h
//	ucrt/wchar.h
// For now I'm only going to rebuild stdio.h and its dependencies with this set to 0
// maybe it'll break other headers? idk?
//#define _CRT_FUNCTIONS_REQUIRED 0
// hmm, nope, this gets rid of all the stdio stuff

// hmm this is used in vcruntime_string.h
// but it's defined in corecrt.h
// and vcruntime_string.h doesn't include corecrt.h .......
#define _CONST_RETURN const

// <vcruntime.h> has these: (I'm skipping it for now)
#define _VCRTIMP
#define _CRT_BEGIN_C_HEADER
#define _CRT_END_C_HEADER
#define _CRT_SECURE_NO_WARNINGS
#define _CRT_INSECURE_DEPRECATE(Replacement)
#define _CRT_INSECURE_DEPRECATE_MEMORY(Replacement)
#define _HAS_NODISCARD 0
#define _NODISCARD
#define __CLRCALL_PURE_OR_CDECL __cdecl
#define __CRTDECL __CLRCALL_PURE_OR_CDECL
#define _CRT_DEPRECATE_TEXT(_Text)
#define _VCRT_ALIGN(x) __declspec(align(x))

// used by stdint.h to produce some macros (which are all using non-standard MS-specific suffixes so my preproc comments them out anyways)
// these suffixes also appearn in limits.h
// not sure where else _VCRT_COMPILER_PREPROCESSOR appears tho
#define _VCRT_COMPILER_PREPROCESSOR 1

// in corecrt.h but can be overridden
// hopefully this will help:
//#define _CRT_FUNCTIONS_REQUIRED 0

// needed for stdint.h ... ?
//#define _VCRT_COMPILER_PREPROCESSOR 1

// correct me if I'm wrong but this macro says no inlines?
//#define __midl
// hmm, nope, it just disabled everything
// this one seems to lose some inlines:
#define __STDC_WANT_SECURE_LIB__ 0
// how about this one?
//#define RC_INVOKED
// ...sort of but in corecrt.h if you do set it then you have to set these as well:
// too much of a mess ...

// annoying macro.  needed at all?
#define __declspec(x)
]]

		-- I'm sure there's a proper way to query this ...
		local MSVCDir = [[C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.43.34808]]

		-- [=[ <sal.h> has these:  (included by <vcruntime.h>)
		for l in io.lines(MSVCDir..[[\include\sal.h]]) do
			local rest = l:match'^#define%s+(.*)$'
			if rest then
				local k, params, paramdef = rest:match'^(%S+)%(([^)]*)%)%s*(.-)$'
				if k then
					preproc('#define '..k..'('..params..')')
				else
					local k, v = rest:match'^(%S+)%s+(.-)$'
					if k then
						preproc('#define '..k)
					end
				end
			end
		end
		--]=]

		skipincs:insert'<sal.h>'
		skipincs:insert'<vcruntime.h>'
		--skipincs:insert'<vcruntime_string.h>'	-- has memcpy ... wonder why did I remove this?
		--skipincs:insert'<corecrt_memcpy_s.h>'	-- contains inline functions

		-- how to know where these are?
		preproc:addIncludeDirs({
			-- what's in my VS 2022 Project -> VC++ Directories -> General -> Include Directories
			MSVCDir..[[\include]],
			MSVCDir..[[\atlmfc\include]],
			[[C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\VS\include]],
			[[C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\ucrt]],
			[[C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\um]],
			[[C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\shared]],
			[[C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\winrt]],
			[[C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\cppwinrt]],
			[[C:\Program Files (x86)\Windows Kits\NETFXSDK\4.8\Include\um]],
		}, true)
	else	-- assume everything else uses gcc
		assert(os.execute'gcc --version > /dev/null 2>&1', "failed to find gcc")	-- make sure we have gcc
		preproc(io.readproc'gcc -dM -E - < /dev/null 2>&1')

		local results = io.readproc'gcc -E -v - < /dev/null 2>&1'
--DEBUG:print('results')
--DEBUG:print(results)
		assert(results:match'include')
		assert(results:match('#include'))	-- why doesn't this match?
		assert(results:match'#include "%.%.%." search starts here:')
		local userSearchStr, sysSearchStr = results:match'#include "%.%.%." search starts here:(.-)#include <%.%.%.> search starts here:(.-)End of search list%.'
		assert(userSearchStr)
--DEBUG:print('userSearchStr')
--DEBUG:print(userSearchStr)
--DEBUG:print('sysSearchStr')
--DEBUG:print(sysSearchStr)
		local userSearchDirs = string.split(string.trim(userSearchStr), '\n'):mapi(string.trim)
		local sysSearchDirs = string.split(string.trim(sysSearchStr), '\n'):mapi(string.trim)
--DEBUG:print('userSearchDirs')
--DEBUG:print(tolua(userSearchDirs))
--DEBUG:print('sysSearchDirs')
--DEBUG:print(tolua(sysSearchDirs))
		preproc:addIncludeDirs(userSearchDirs, false)
		preproc:addIncludeDirs(sysSearchDirs, true)

		-- how to handle gcc extension macros?
		preproc[[
#define __has_feature(x)			0
#define __building_module(x)		0
#define __has_extension(x)			0
#define __has_attribute(x)			0
#define __has_cpp_attribute(x)		0
#define __has_c_attribute(x)		0
#define __has_builtin(x)			0
#define __has_include(x)			0
#define __has_warning(x)			0
#define __asm(x)					// let the C preprocessor eliminate the __asm__ attributes
#define __asm__(x)					// let the C preprocessor eliminate the __asm__ attributes
#define __has_unique_object_representations(x) 0
#define _GLIBCXX_HAS_BUILTIN(x)		0
#define _Static_assert(a,b)		// this is in <sys/cdefs.h> ... why isn't it working in <SDL2/SDL.h> ?
#define __is_target_os(x)			0		// clang-specific builtin
#define __is_target_environment(x)	0
]]
	end

	-- where I keep my glext.h and khr/khrplatform.h
	-- TODO move this into gl.sh?
	preproc:addIncludeDir(os.home()..'/include', ffi.os == 'Windows')

	-- cwd? no, this just risks the generated file geeting included mid-generation.
	-- but for testing I enable it ... with -I.
	--preproc:addIncludeDir('.', false)

	-- before reading inc's properties, make sure we get the pkgconfig ones
	inc:setupPkgConfig()

	for _,f in ipairs(inc.includedirs or {}) do
		preproc:addIncludeDir(f, true)	-- if 'f' is a path ... tostring() or escape()? which does proper Windows slashes?
	end

	for _,kv in ipairs(inc.macros or {}) do
		local k,v = kv:match'^([^=]*)=(.-)$'
		if not k then
			k, v = kv, '1'
		end
		preproc:setMacros{[k]=v}
	end

	skipincs:append(inc.skipincs)

	-- don't ignore underscore enums
	-- needed by complex.h since there are some _ enums its post-processing depends on
	preproc.enumGenUnderscoreMacros = inc.enumGenUnderscoreMacros

	-- TODO handle inc.flags ...

	preproc.luaBindingIncFiles = table{inc.inc}:append(inc.moreincs)
	preproc.luaIncMacroFiles = table(preproc.luaBindingIncFiles):append(inc.macroincs)
	preproc.saveAllMacros = inc.saveAllMacros

	for _,rest in ipairs(skipincs) do
		-- TODO this code is also in preproc.lua in #include filename resolution ...
		local sys = true
		local fn = rest:match'^<(.*)>$'
		if not fn then
			sys = false
			fn = rest:match'^"(.*)"$'
		end
		if not fn then
			error("skip couldn't find include file: "..rest)
		end
		local search = fn
		fn = preproc:searchForInclude(fn, sys)
		if not fn then
			error("skip: couldn't find "..(sys and "system" or "user").." include file "..search..'\n')
		end

--DEBUG:print('skipping ', fn)
		-- treat it like we do #pragma once files
		preproc.alreadyIncludedFiles[fn] = true
	end

--DEBUG:print('starting preprocessor with initial macros:', tolua(preproc.macros))

	-- include these files but don't output the results
	for _,fn in ipairs(inc.silentincs or {}) do
		preproc("#include "..fn)
	end

	-- create our list of #include's from inc.inc and inc.moreincs
	local code = preproc(preproc.luaBindingIncFiles:mapi(function(fn)
		return '#include '..fn
	end):concat'\n'..'\n')

	--print('macros: '..tolua(preproc.macros)..'\n')
	--io.stderr:write('macros: '..tolua(preproc.macros)..'\n')

	-- [[ append enums / define's
	local lines = table()
	for _,kv in ipairs(preproc.luaGenerateEnumsInOrder) do
		local k, v = next(kv)

		-- remove any C number formatting that doesn't work in luajit
		-- TODO are luajit enums only 32-bit? signed vs unsigned?
		-- when will removing this get us in trouble?
		for _,suffix in ipairs(cNumberSuffixes) do
			vnumstr = v:lower():match('(.*)'..suffix..'$')
			if vnumstr then
				--v = tostring((assert(tonumber(vnumstr))))	-- use it as is
				v = vnumstr	-- use as is but truncated ... this messes up int64's outside the range of double ...
			end
		end

		lines:insert('enum { '..k..' = '..v..' };')
	end
	code = code .. '\n' .. lines:concat'\n' .. '\n'
	--]]

	-- here wrap our code with ffi stuff:
	local code = table{
		"local ffi = require 'ffi'",
		"ffi.cdef[[",
		code,
		"]]"
	}:concat'\n'..'\n'

path'~before-final.h':write(code)

	-- if there's a final-pass on the code then do it
	-- TODO inc.final() before lua code wrapping?
	-- or make lua code wrapping part of a default inc.final?
	if inc.final then
		code = inc.final(code, preproc)
		assert.type(code, 'string', "expected final() to return a string")
	end

	return code
end

--[[
Ok C standards, esp typeof(), might have done my preprocessor in.
Now it has to track variable types in order to evaluate.
So here's my attempt to just use gcc -E and transform the output into my preprocessor's output
--]]
local function preprocessWithCompiler(inc)

	print()
	print('GENERATING '..inc.out)

	-- fair warning, I'm testing this on clang
	assert(os.execute'gcc --version > /dev/null 2>&1', "failed to find gcc")	-- make sure we have gcc



	-- also in make.lua
	local outdir = path'results/ffi'


-- TODO TODO TODO
-- if I'm testing these one at a time
-- then how about not running O(n^2) over them all to find duplicate include trees
-- how about instead I generate each without trees
-- then I run one single analysis that collects all duplicate trees


	-- TODO you can do this during the first pass
	local prevIncludeInfos = {}

	local function parseIncludeBeginComment(l, l2)
		local plus, includeInfo = l:match'^/%* (%++) BEGIN (.*) %*/$'
		if includeInfo then
			local isEmpty
			if l2 then
				if l2:match('^/%* %++ END '..string.patescape(includeInfo)..' %*/$') then
					isEmpty = true
				elseif l2:match('^'..string.patescape("]] require 'ffi.req' '")..'.*'..string.patescape("' ffi.cdef[[")..'$') then
					isEmpty = true
				end
			end
			if not isEmpty then
				-- this is the search and the includePath
				-- match both? or just the 2nd?
				-- match 2nd and complain if 2nd matches but both don't match
				local search = includeInfo:match'^(<[^>]*>)'
					or includeInfo:match'^(".-[^\\]")'
					or error("couldn't pick out <> or \"\" argument from #include command: "..l)
				local includePath = includeInfo:sub(#search+2)
				return plus, search, includePath
			end
		end
	end

	local function reportDups(newIncInfo, prevIncInfo, includePath)
		if newIncInfo.search:match'%$include_next>$' then return end

		print("!!!!! FOUND REDUNDANT INCLUDE FILE !!!!!")
		print(newIncInfo.search..' '..includePath)
		print('***** 1st:', newIncInfo.lua..':'..newIncInfo.line)
		print('***** 2nd:', prevIncInfo.lua..':'..prevIncInfo.line)
		assert.eq(newIncInfo.search, prevIncInfo.search, "and their #include arguments don't match!")
		print("Insert this into your include-list-"..ffi.os:lower()..".lua:")
		print()
		print('\t-- used by '.. newIncInfo.inc.inc..' '..prevIncInfo.inc.inc)
		print("\t{inc='"..newIncInfo.search.."', out='"..ffi.os..'/c/'..newIncInfo.search:sub(2,-2):gsub('%.h$', '.lua').."'},")
		print()
		print"TODO Automatically put in a request to generate this internal #include file and then re-run everything."
		print"Or if one of those two dependencies is the same as the source then change your generation order."
--[[
TODO last step for full automation ...
run the full list every time,
then upon encounterin this error,
insert the lines above into a table auto-serialized as 'include-list-osx-internal.lua'
make sure to insert it as high as possible but beneath both dependencies
then re-run it
--]]
		error'here'
	end

	-- fp = current file path (used to report errors, not for file IO)
	-- line = same
	-- l = current line
	-- l2 = optional next line for testing empty lines
	local function processIncludeBeginComment(pinc, fp, line, l, l2, skipOwnInc)
		local plus, search, includePath = parseIncludeBeginComment(l, l2)
		if not search then return end
--		if skipOwnInc and plus == '+' then return end
		local prevIncInfo = prevIncludeInfos[includePath]
		local newIncInfo = {
			inc = pinc,
			search = search,
			lua = fp,
			line = line,
		}
		if not prevIncInfo then
			prevIncludeInfos[includePath] = newIncInfo
--DEBUG:print("adding prevIncludeInfos for ", pinc.inc)
			return
		end

		if prevIncInfo.lua == fp then
			--[[ NOTICE this is a good indicator of an error, however
			-- some files like math.h will change macros and re-include the same file again and again ...
			print('***** 1st:', tolua(newIncInfo))
			print('***** 2nd:', tolua(prevIncInfo))
			print"somehow we included the same path twice!"
			--]]
			return
		end

		reportDups(newIncInfo, prevIncInfo, includePath)
	end

	local function checkIncludeComments(pinc, fp, skipOwnInc)
		local data = outdir(fp):read()
		local lines = string.split(data, '\n')
		for i,l in ipairs(lines) do
			processIncludeBeginComment(pinc, fp, i, l, lines[i+1], skipOwnInc)
		end
	end

	-- collect #include's and make sure they are unique as we go ...
	-- FOR EVERY SINGLE FILE, THAT'S O(N^2)
	-- how about doing this as we go too?
	-- but that'd screw up for one-off files...
	local incIndex = assert(includeList:find(inc))
	for i=1,incIndex-1 do
		local pinc = includeList[i]
		local fp = path(pinc.out)
		if not outdir(fp):exists() then
			print('!!! '..fp.." doesn't exist - can't compare like include trees")
		else
--DEBUG:print("checkIncludeComments", pinc.inc)
			checkIncludeComments(pinc, fp, false)
		end
	end



	local luaBindingIncFiles = table{inc.inc}:append(inc.moreincs)
	local luaIncMacroFiles = table(luaBindingIncFiles):append(inc.macroincs)

	local function cflagsForInc(inc)
		local cflags = table()
		:append(
			({
				OSX = {
					'-fno-blocks',	-- disable __BLOCKS__ and those stupid ^ pointers
					"-D_Nonnull=",	-- somehow the builtin define missed this one ...
					"-D_Nullable=",	-- this and _Nonnull, should I collect them and add them to all osx clang runs?
				},
				Windows = {
					-- I put all my 3rd party include files in windows in $HOME/include... where else would they go?
					'-I '..(path(os.home())/'include'):escape(),	-- bad idea?
				},
			})[ffi.os],
			-- * add `pkg-config ${name} --cflags` if it's there
			inc.pkgconfig and {string.trim(io.readproc('pkg-config --cflags '..inc.pkgconfig))} or nil,
			-- * add `inc.includedirs`
			table(inc.includedirs):mapi(function(inc) return '-I '..path(inc):escape() end),
			-- * set `inc.macros` with `-D`
			table(inc.macros):mapi(function(macro) return '"-D'..macro..'"' end)
		)
		:concat' '
		return cflags
	end

	-- for all the includes we want to keep macros for, get a mapping from the include directive to the absolute path
	-- this way we can find the path in the preprocessor output
	local searchForPath = {}
	local pathForSearch = {}
	for _,search in ipairs(luaBindingIncFiles) do
		-- TODO best way to get include lookup
		-- This outputs the include graph ... but all I need is the first result.
		local pinc = select(2, includeList:find(nil, function(o) return o.inc == search end))
		-- warn if not there? "failed to find include-list entry for "..search

		-- how to find the request? which incldue paths to use?
		-- first see if it is there by itself in our include-list
		-- then try with the currently-generating file
		local cflags = (pinc or inc) and cflagsForInc(pinc or inc) or ''

		local cmd = "echo '#include "..search.."' | (gcc -H -MM -E -x c "..cflags.." - 2>&1)"
		local out = io.readproc(cmd)
		local lines = string.split(out, '\n')
		local line = lines[1]
		if not line:match'^%. ' then
			error("searchForPath got a bad line: "..tostring(line)
				..'\nsearch: '..search
				..'\noutput: '..out
				..'\ncmd: '..cmd)
		end
		local fn = line:sub(3)
		searchForPath[fn] = search
		pathForSearch[search] = fn
	end

	if ffi.os == 'Linux'
	and table(inc.silentincs):find'<features.h'
	and #string.trim(io.readproc('grep features.h "'..pathForSearch[inc.inc]'"')) > 0
	then
		print'!!!!!! DANGER !!!!!!'
		print'you both silentinc and regular-#include <features.h>'
		print'!!!!!! DANGER !!!!!!'
	end

	-- 2) run preprocessor on source file
	-- https://gcc.gnu.org/onlinedocs/gcc/Directory-Options.html
	-- * `inc.skipincs` was a list of include files that the preprocessor was to return empty content for ... do I still need this?
	-- * `inc.silentincs` is a list of include files to include but not collect results of.
	-- * `inc.inc + inc.moreincs` is our list of include files to generate.
	-- * ... + `inc.macroincs` is the list of include files to collect macros from (can we tell with gcc -E?)
	local tmpfn = path'gcc-preproc-results.h'
	local cmd = table{
		"echo '"	-- echo is handed to system wrapped in 's
			..table():append(
				-- TODO TODO TODO get silentincs working, cuz its not working!
				inc.silentincs,
				{inc.inc},
				inc.moreincs
			)
			:mapi(function(inc)
				return '#include '..inc..'\\n'
			end):concat()
			.."'",
		'|',
		'gcc',
		-- https://gcc.gnu.org/onlinedocs/gcc/Preprocessor-Options.html
		'-dI',	-- keep #include too, so I can map from #include directive to absolute filename
		'-dD',	-- keep #define / #undef *AND* preprocessor-output
		'-E',	-- do the preprocessor output
		'-x c',
		cflagsForInc(inc),
		'- > '..tmpfn:escape(),
	}:concat' '

	assert(os.exec(cmd))
	local code = assert(tmpfn:read())
	local lines = string.split(string.trim(code), '\n')

	-- 3) transform to my format
	local lastSearch
	local incstack = table()	-- .path, .search
	local macros = {}
	local allMacrosEvenSuppressedOnes = {}
	local macrosInOrder = table()
	do
		local newlines = table()
		local saveline
		assert(xpcall(function()
			for i,l in ipairs(lines) do
				saveline = i

				if l == '' then
				elseif l:find'^#define' then

					-- we actually do need to do macro-evaluation
					do
						local k,v = l:match'^#define%s+([_%a][_%w]*)%s*(.-)$'
						allMacrosEvenSuppressedOnes[k] = v
					end

					local top = incstack:last()

					if not top	-- gcc linux doesn't specify the 'enter' include flag, i.e. no `# 0 "<stdin>" 1` like clang does.
					or top.path == '<built-in>'
					or top.path == '<command line>'	-- clang
					or top.path == '<command-line>'	-- gcc
					-- don't save include macros because they should be in the included file already
					or top.suppress
					-- if the file isn't in our list of requested files to generate content for ...
					-- TODO on jpeg this is filtering out too many macros ...
					or not (
						-- system includes want all macros, 3rd party includes only want their own macros
						-- so this is a cheap fix for now:
						inc.saveAllMacros
						or luaIncMacroFiles:find(top.search)
					) then
						-- don't save builtins
						-- in fact TODO only save inc.inc + inc.moreincs + inc.macroincs
					else
						local k,v = l:match'^#define%s+([_%a][_%w]*)%s*(.-)$'
						for j=#macrosInOrder,1,-1 do
							if next(macrosInOrder[j]) == k then
								macrosInOrder:remove(j)
							end
						end
--DEBUG:print(tolua(incstack))
--DEBUG:print('top', top.search, top.suppress, 'defining', k, v)
						macros[k] = v
						macrosInOrder:insert{[k] = v}
					end
				elseif l:find'^#undef' then
					local k = l:match'^#undef%s+([_%a][_%w]*)$'
					macros[k] = nil
					allMacrosEvenSuppressedOnes[k] = nil
					for j=#macrosInOrder,1,-1 do
						if next(macrosInOrder[j]) == k then
							macrosInOrder:remove(j)
						end
					end
				elseif l:find'^#include'
				or l:find'^#include_next'
				then
					-- -dI inserts the #include directive ...
					-- ... and then a preprocessor markup for the current include file
					-- ... and then a preprocessor markup for the included file.
					-- so save this for our mapping from abs path to include directive
					local lastSearchIncludeNext = nil
					local rest = l:match'^#include (.*)$'
					if not rest then
						rest = l:match'^#include_next (.*)$'
						lastSearchIncludeNext = true
					end
					if not rest then
						error("couldn't pick out the #include argument from: "..l)
					end

					lastSearch = rest:match'^(<[^>]*>)'
						or rest:match'^(".-[^\\]")'
						or error("couldn't pick out <> or \"\" argument from #include command: "..l)
					if lastSearchIncludeNext then
						lastSearch = string.trim(lastSearch)
						lastSearch =
							lastSearch:sub(1,1)
							..lastSearch:sub(2,-2)
								-- ..'$include_next'	-- suffix still appearing on the END of the first include comment ...
							..lastSearch:sub(-1)
					end
				elseif l:find'^#pragma' then
					-- keep it
					if not incstack:last().suppress then
						newlines:insert(l)
					end
				elseif l:find'^#' then
					-- handle preprocessor include results
					-- https://gcc.gnu.org/onlinedocs/gcc-4.3.4/cpp/Preprocessor-Output.html#:~:text=The%20output%20from%20the%20C,of%20blank%20lines%20are%20discarded.
					local lineno, includePath, flags = l:match'^# (%d+) (".-[^\\]")(.*)$'
					if not lineno then
						error("got unknown preprocessor output line: "..l)
					end

					includePath = includePath:match'^"(.*)"$':gsub('\\"', '"')

					-- on linux gcc, we are getting `# line file flags` lines for builtin includes always at the top
					-- long before any `#include` lines
					-- and that means `lastSearch` is not yet defined ...
					-- especially "/usr/include/stdc-predef.h" ...
					if lastSearch == nil
					and includePath == '/usr/include/stdc-predef.h'
					then
					else
						flags = string.split(string.trim(flags), ' '):mapi(function(flag)
							if flag == '' then return end	-- for empty strings
							return true, assert(tonumber(flag))
						end):setmetatable(nil)
						if flags[1] then
							-- begin file
							local wasSuppressed = (incstack:last() or {}).suppress
							local top = {
								path = includePath,
								search = lastSearch or '<no search, so it better be some kind of builtin>',
								suppress = wasSuppressed,
							}
							incstack:insert(top)
							if includePath == '<built-in>'
							or includePath == '<command line>'	-- clang
							or includePath == '<command-line>'	-- gcc
							then
							else
								if not lastSearch then
									error("got an include preprocessor output before an #include statement: "..includePath)
								end

								searchForPath[includePath] = lastSearch
								if incstack:last().suppress then
								else
									newlines:insert('/* '..('+'):rep(#incstack)..' BEGIN '..lastSearch..' '..includePath..' */')
								end

								-- if the #include file has already been defined ...
								-- then just insert it here
								local prevIncInfo = prevIncludeInfos[includePath]
--DEBUG:print('CHECKING PREVIOUS INCLUDE FOR ', includePath, prevIncInfo , wasSuppressed )
								if prevIncInfo
								and not (
									-- don't use ourselves
									#incstack == 1 and incstack[1].search == inc.inc
								)
								then
									if not wasSuppressed then
										-- prevIncInfo.filename = the duplicated tree
										-- prevIncInfo.search = what is #include'd to generate that
										-- ... then we have to find in all includeList for prevIncInfo.search
										-- ... then we put its .out here
										local previnc = select(2, includeList:find(nil, function(o) return o.inc == prevIncInfo.search end))
--DEBUG:print('previous includeList entry?',previnc)
										if not previnc then
											--[[ TODO redunant? don't do this here and at the end ?
											-- or do I need the prevIncludeInfos[] entries?
											local newIncInfo = {
												search = lastSearch,
												line = i,
												lua = path(inc.out),
												inc = inc,
											}
											reportDups(newIncInfo, prevIncInfo, includePath)
											--]]
										else
											local reqpath = previnc.out:match'^(.*)%.lua$':gsub('/', '.')
											-- ... but now this has the fif.os in it!
											-- But this shouldn't be including the ffi.os in it!
											-- That's the whole point of `require 'ffi.req'`!
											-- But at the end of *only* the os-specific include-lists I am adding in the `OS/` prefix to the path ... because thats where the binding files get written ...
											-- so *HERE* I should be removing it again...
											if reqpath:sub(1,#ffi.os+1) == ffi.os..'.' then
												reqpath = reqpath:sub(#ffi.os+2)
											end

											newlines:insert("]] require 'ffi.req' '"
												..reqpath
												.."' ffi.cdef[["
--..'\n...from: '..tolua(prevIncInfo)
											)
											--incstack:last().suppress = true
										end
										--incstack:last().suppress  = true
									end
									-- hopefully not suppressing require()'d #define's too much ...
									incstack:last().suppress  = true
								end
								-- too far
								--incstack:last().suppress  = true
							end
						elseif flags[2] then
							-- returning *to* a file (so the last file on the stack is now closed)
							local top = incstack:last()
							if top then	-- gcc
								if top.path == '<built-in>'
								or top.path == '<command line>'	-- clang
								or top.path == '<command-line>'	-- gcc
								then
								else
									local search = searchForPath[top.path]
									if (incstack[#incstack-1] or {}).suppress then
									else
										-- ok for osx and linux
										-- sometimes we get empty files
										-- and I already have the include-tree checker ignoring them
										-- but it'd be better to just not spit them out at all
										-- so if our END matches the prev line's BEGIN then remove both
										local beginLine = '/* '..('+'):rep(#incstack)..' BEGIN '..search..' '..top.path..' */'
										--if newlines:last() == beginLine then
										-- maybe it's a bad idea since
										-- it is screwing up on files that have only macros,
										-- because their macros go after their END,
										-- so they look empty to this test ...
										-- or I can just put the macros inside the END block ...
										-- but for that reason I still need to keep the single-line END around, to find where to insert the  macros ...
										if false then
											newlines[#newlines] = nil
										else
											newlines:insert('/* '..('+'):rep(#incstack)..' END '..search..' '..top.path..' */')
										end
									end
								end
								incstack:remove()
							end
						end
					end
				else
					-- regular line
					if not incstack:last().suppress then
						newlines:insert(l)
					end
				end
			end
			assert.len(incstack, 0)
		end, function(err)
			return err..'\non line '..tostring(saveline)..'\n'..debug.traceback()
		end))
		lines = newlines
	end

	-- [[ append define's
	-- TODO make sure they go inside the END of the file!
	do
		local endLine = '/* + END '..inc.inc..' '..pathForSearch[inc.inc]..' */'
		local insertLoc = #lines
--assert.eq(lines[insertLoc], endLine)
		for _,kv in ipairs(macrosInOrder) do
			local k, origv = next(kv)

			-- sometimes a macro is defined as another
			-- and expects the preprocessor to resolve all definitions ...
			-- TODO smh maybe I do need my C-preprocessor after all ...
			-- TODO smh now I need to save suppressed macros also ...
			while true do
				local newv = allMacrosEvenSuppressedOnes[origv]
				if newv == origv then break end
				if not newv then break end
				origv = newv
			end

			local v
			if origv == '' then
				v = '1'
			else
				vnumstr = tonumber(v)
				if vnumstr then
					v = origv
				else
					for _,suffix in ipairs(cNumberSuffixes) do
						vnumstr = origv:lower():match('(.*)'..suffix..'$')
						if vnumstr
						and tonumber(vnumstr)
						then
							--v = tostring((assert(tonumber(vnumstr))))	-- use it as is
							v = vnumstr	-- use as is but truncated ... this messes up int64's outside the range of double ...
						end
					end
				end
			end
			if v then
				lines:insert(insertLoc, 'enum { '..k..' = '..v..' };')
			else
				lines:insert(insertLoc, '/* #define '..k..' '..origv..' ### define is not number */')
			end
			-- keep insertions in-order
			insertLoc = insertLoc + 1
		end
	end
	--]]

	code = lines:concat'\n'..'\n'	-- remove blank newlines

	-- TODO
	-- 4) run again, this time collecting macros, subtract out builtin, and use the rest as macros for this file.
	--		NOTICE that means we will get in the .h file any macros defined by its included files.
	-- 		With my preprocessor I was able to strip these out based on where they were defined.  can GCC give me this info?
	-- * output the macros as `enum { k = v };`

	code = [=[
local ffi = require 'ffi'
ffi.cdef[[
]=]..code..[=[
]]
]=]
path'~before-final.h':write(code)

	-- if there's a final-pass on the code then do it
	-- TODO inc.final() before lua code wrapping?
	-- or make lua code wrapping part of a default inc.final?
	if inc.final then
		local fakePreproc = {
			macros = macros,
		}
		code = inc.final(code, fakePreproc)
		assert.type(code, 'string', "expected final() to return a string")
	end

	-- now for all previously included files ...
	-- search that file output and search this file output and see if there are any common include subsets
	-- NOTICE this is a job for make.lua sort of
	do
		-- WRITE CODE HERE - BEFORE CHECKING DUPLICATE INCLUDE TREES
		-- that means we're writing it twice
		-- TODO move the write out of make.lua
		local fp = path(inc.out)
		outdir(fp):write(code)

		-- in fact, if I'm handling this in #include handling
		-- then this will return nothing, right?
		checkIncludeComments(inc, fp, true)
	end

	return code
end

if ffi.os == 'Windows' then
	-- use the old way with my pure-lua preprocessor
	return preprocessWithLuaPreprocessor
else
	-- new way, just parse gcc -E
	return preprocessWithCompiler
end
