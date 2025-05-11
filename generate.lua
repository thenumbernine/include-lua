#!/usr/bin/env luajit
local ffi = require 'ffi'		-- used for OS check and used for verifying that the generated C headers are luajit-ffi compatible
local table = require 'ext.table'
local string = require 'ext.string'
local assert = require 'ext.assert'
local path = require 'ext.path'
local io = require 'ext.io'
local os = require 'ext.os'
local tolua = require 'ext.tolua'


local includeList = table(require 'include-list')


local Preproc = require 'preproc'

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

	return ''
end

-- Returns true if the current file we're in is one of the ones we wanted to spit out bindigns for.
-- Used to determine what files to save and output enum-macros for, versus which to just save and only use for preprocessing.
function ThisPreproc:luaWithinAGenerateFile()
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
return function(inc)

	local preproc = ThisPreproc()

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

	-- [[ prepend enums / define's to the beginning
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
