-- TODO chop this file up into per-OS files for system including , and per-lib files
-- mapping from c includes to luajit ffi/ includes
-- this is used for automated generation
-- this is also used during generation for swapping out #includes with require()'s of already-generated files

--[[
TODO an exhaustive way to generate all with the least # of intermediate files could be
- go down the list
- for each file, generate
- as you reach includes, see if any previous have requested the same include.
- if so then generate that include, and restart the process.
--]]

local ffi = require 'ffi'
local template = require 'template'
local path = require 'ext.path'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local io = require 'ext.io'
local os = require 'ext.os'
local tolua = require 'ext.tolua'

local util = require 'include.util'
local safegsub = util.safegsub
local removeEnum = util.removeEnum

local includeList = table()

-- files found in multiple OS's will go in [os]/[path]
-- and then in just [path] will be a file that determines the file based on os (and arch?)

--[[
OS-specific bindings
each should have:
1) internal includes that vary per OS
2) external includes that make up the API of requests for `require 'ffi.req' 'c.whatever'` <=> `#include <whatever.h>`
https://stackoverflow.com/a/2029106/2714073
--]]
includeList:append(require 'include.include-list-windows')
includeList:append(require 'include.include-list-linux')
includeList:append(require 'include.include-list-osx')

includeList:append(table{

-- these come from external libraries (so I don't put them in the c/ subfolder)

	-- apt install libarchive-dev
	{
		inc='<archive.h>',
		moreincs = {
			'<archive_entry.h>',
		},
		out='archive.lua',
		final = function(code)
			code = code .. [[
return require 'ffi.load' 'archive'
]]
			return code
		end,
	},

	{
		-- ok I either need to have my macros smart-detect when their value is only used for types
		-- or someone needs to rewrite the zlib.h and zconf.h to use `typedef` instead of `#define` when specifying types.
		-- until either happens, I'm copying the zlib locally and changing its `#define` types to `typedef`.
		inc = '"zlib/zlib.h"',
		out = 'zlib.lua',
		includedirs = {'.'},
		final = function(code, preproc)
			local code = makeLibWrapper{
				code = code,
				lib = 'z',
				-- add this beneath this top "local ffi = require 'ffi'"
				headerCode = [[
local assert = require 'ext.assert'
]],
				-- add extra type stuff here
				requires = table{
					[=[

if ffi.os == 'Linux' then
	require 'ffi.req' 'c.unistd'
	ffi.cdef[[
typedef long z_off_t;
typedef off_t z_off64_t;
]]
elseif ffi.os == 'OSX' then
	require 'ffi.req' 'c.unistd'
	ffi.cdef[[
typedef off_t z_off_t;
typedef z_off_t z_off64_t;
]]
elseif ffi.os == 'Windows' then
	ffi.cdef[[
typedef long z_off_t;
typedef int64_t z_off64_t;
]]
end]=],
				},
				-- Then add our windows-only symbol if we're not on windows ...
				funcs = ffi.os ~= 'Window' and {
					[=[		gzopen_w = [[gzFile gzopen_w(wchar_t const *path, char const *mode);]], -- Windows-only]=],
				},
				-- ... then add some macros onto the end manually
				footerCode = [=[
-- macros

wrapper.ZLIB_VERSION = ]=]
	..assert.type(preproc.macros.ZLIB_VERSION, 'string') -- macro has quotes in it.
..[=[


function wrapper.zlib_version(...)
	return wrapper.zlibVersion(...)
end

function wrapper.deflateInit(strm)
	return wrapper.deflateInit_(strm, wrapper.ZLIB_VERSION, ffi.sizeof'z_stream')
end

function wrapper.inflateInit(strm)
	return wrapper.inflateInit_(strm, wrapper.ZLIB_VERSION, ffi.sizeof'z_stream')
end

function wrapper.deflateInit2(strm, level, method, windowBits, memLevel, strategy)
	return wrapper.deflateInit2_(strm, level, method, windowBits, memLevel, strategy, wrapper.ZLIB_VERSION, ffi.sizeof'z_stream')
end

function wrapper.inflateInit2(strm, windowBits)
	return wrapper.inflateInit2_(strm, windowBits, wrapper.ZLIB_VERSION, ffi.sizeof'z_stream')
end

function wrapper.inflateBackInit(strm, windowBits, window)
	return wrapper.inflateBackInit_(strm, windowBits, window, wrapper.ZLIB_VERSION, ffi.sizeof'z_stream')
end

-- safe-call wrapper:
function wrapper.pcall(fn, ...)
	local f = assert.index(wrapper, fn)
	local result = f(...)
	if result == wrapper.Z_OK then return true end
	local errs = require 'ext.table'{
		'Z_ERRNO',
		'Z_STREAM_ERROR',
		'Z_DATA_ERROR',
		'Z_MEM_ERROR',
		'Z_BUF_ERROR',
		'Z_VERSION_ERROR',
	}:mapi(function(v) return v, (assert.index(wrapper, v)) end):setmetatable(nil)
	local name = errs[result]
	return false, fn.." failed with error "..result..(name and (' ('..name..')') or ''), result
end

--[[
zlib doesn't provide any mechanism for determining the required size of an uncompressed buffer.
First I thought I'd try-and-fail and look for Z_MEM_ERROR's ... but sometimes you also get other errors like Z_BUF_ERROR.
A solution would be to save the decompressed length alongside the buffer.
From there I could require the caller to save it themselves.  But nah.
Or - what I will do - to keep this a one-stop-shop function -
I will write the decompressed length to the first 8 bytes.
So for C compatability with the resulting data, just skip the first 8 bytes.
--]]
function wrapper.compressLua(src)
	assert.type(src, 'string')
	local srcLen = ffi.new'uint64_t[1]'
	srcLen[0] = #src
	if ffi.sizeof'uLongf' <= 4 and srcLen[0] >= 4294967296ULL then
		error("overflow")
	end
	local dstLen = ffi.new('uLongf[1]', wrapper.compressBound(ffi.cast('uLongf', srcLen[0])))
	local dst = ffi.new('Bytef[?]', dstLen[0])
	assert(wrapper.pcall('compress', dst, dstLen, src, ffi.cast('uLongf', srcLen[0])))

	local srcLenP = ffi.cast('uint8_t*', srcLen)
	local dstAndLen = ''
	for i=0,7 do
		dstAndLen=dstAndLen..string.char(srcLenP[i])
	end
	dstAndLen=dstAndLen..ffi.string(dst, dstLen[0])
	return dstAndLen
end

function wrapper.uncompressLua(srcAndLen)
	assert.type(srcAndLen, 'string')
	-- there's no good way in the zlib api to tell how big this will need to be
	-- so I'm saving it as the first 8 bytes of the data
	local dstLenP = ffi.cast('uint8_t*', srcAndLen)
	local src = dstLenP + 8
	local srcLen = #srcAndLen - 8
	local dstLen = ffi.new'uint64_t[1]'
	dstLen[0] = 0
	for i=7,0,-1 do
		dstLen[0] = bit.bor(bit.lshift(dstLen[0], 8), dstLenP[i])
	end
	if ffi.sizeof'uLongf' <= 4 and dstLen[0] >= 4294967296ULL then
		error("overflow")
	end

	local dst = ffi.new('Bytef[?]', dstLen[0])
	assert(wrapper.pcall('uncompress', dst, ffi.cast('uLongf*', dstLen), src, srcLen))
	return ffi.string(dst, dstLen[0])
end
]=],
			}
			-- zlib libtiff libpng EGL
			code = code:gsub(string.patescape'(void)', '()')
			return code
		end,
	},

	-- apt install libffi-dev
	{
		inc = '<ffi.h>',
		out = 'libffi.lua',
		pkgconfig = 'libffi',	-- points to /System stuff, not homebrew...
		final = function(code)
			code = removeEnum(code, 'FFI_64_BIT_MAX = 9223372036854775807')
			code = [[
-- WARNING, this is libffi, not luajit ffi
-- will that make my stupid ?/?.lua LUA_PATH rule screw things up?  if so then move this file ... or rename it to libffi.lua or something
]] .. code .. [[
return require 'ffi.load' 'ffi'
]]
			return code
		end,
	},

	-- depends: stdbool.h
	-- apt install libgif-dev
	-- brew install giflib
	{
		inc = '<gif_lib.h>',
		out = 'gif.lua',
		-- no brew pkgconfig file for giflib...
		includedirs = ffi.osx == 'OSX' and {
			'/usr/local/opt/giflib/include/',
		} or nil,
		final = function(code)
			code = [[
]] .. code .. [[
return require 'ffi.load' 'gif'
]]
			return code
		end,
	},

	{
		inc='<fitsio.h>',
		out='fitsio.lua',
		macroincs = {
			'<longnam.h>',
		},
		final=function(code, preproc)
			code = removeEnum(code, string.patescape'DOUBLENULLVALUE = -9.1191291391491e-36')

			local funcMacros = table()
			-- [[
			local lines = string.split(code, '\n')
			for i=#lines,1,-1 do
				-- TODO if we had symbol access (header() processor within makeLibWrapper)
				--  then I could compare #define targets to symbols and capture accordingly...
				local line = lines[i]
				local to, from = line:match'^/%* #define (fits%S+)%s+(%S+) ###'
				if to then
					funcMacros:insert{to, from}
					lines:remove(i)
				else
					-- the one that doesn't fit the rule
					local to, from = line:match'^/%* #define (ffcpimg)%s+(%S+) ###'
					if to then
						funcMacros:insert{to, from}
						lines:remove(i)
					end
				end
			end
			code = lines:concat'\n'

			for _,kv in ipairs(funcMacros) do
				local new, old = table.unpack(kv)
				code = removeEnum(code, new..' = 0')
			end

			-- TODO autogen this from /usr/include/longnam.h
			-- TODO TODO autogen all macro function mappings, not just this one
			code = makeLibWrapper{
				code = code,
				preproc = preproc,
				lib = 'cfitsio',
-- [===[ adding as funcs means upon first reference, it'll defer-load the target and replace it with the source
				funcs = table{
					'',
				}:append(funcMacros:mapi(function(kv)
					local new, old = table.unpack(kv)
					return '\t\t' .. new .. ' = function() return wrapper.' .. old .. ' end,'
				end)),
--]===]
				footerCode = table{
					'-- macros',
					'',
				}
--[===[ adding as macros is a bad idea cuz the redirect will be permanent
				:append(
					funcMacros:mapi(function(kv)
						local new, old = table.unpack(kv)
						return 'wrapper.'..new .. ' = function(...) return wrapper.' .. old .. '(...) end'
					end)
				)
--]===]
				:append{
					'wrapper.CFITSIO_VERSION = "'..preproc.macros.CFITSIO_VERSION..'"',
					--[[ using limits' def won't work until it gets its enums fixed...
					'wrapper.LONGLONG_MAX = ffi.C.LLONG_MAX',
					'wrapper.LONGLONG_MIN = ffi.C.LLONG_MIN',
					--]]
					-- [[ until then
					'wrapper.LONGLONG_MAX = 0x7fffffffffffffffLL',
					'wrapper.LONGLONG_MIN = -0x7fffffffffffffffLL-1',
					--]]
					'wrapper.FLOATNULLVALUE = -9.11912e-36',
					'wrapper.DOUBLENULLVALUE = -9.1191291391491e-36',
					"wrapper.fits_open_file = function(...) return wrapper.ffopentest(wrapper.CFITSIO_SONAME, ...) end",
				}:concat'\n',
			}
			-- zlib libtiff libpng EGL fitsio
			code = code:gsub(string.patescape'(void)', '()')
			return code
		end,
	},

	-- apt install libnetcdf-dev
	{
		inc = '<netcdf.h>',
		out = 'netcdf.lua',
		pkgconfig = 'netcdf',
		final = function(code)
			code = removeEnum(code, string.patescape"NC_MAX_DOUBLE = 1.7976931348623157e+308")
			code = code .. [[
local wrapper = setmetatable({}, {__index = require 'ffi.load' 'netcdf'})
wrapper.NC_MAX_DOUBLE = 1.7976931348623157e+308
wrapper.NC_MAX_INT64 = 9.2233720368548e+18
wrapper.NC_MIN_INT64 = -9.2233720368548e+18
return wrapper
]]
			return code
		end,
	},

	-- apt install libhdf5-dev
	-- depends: inttypes.h
	{
		inc = '<hdf5.h>',
		out = 'hdf5.lua',
		pkgconfig = 'hdf5',
		final = function(code)
			-- old header comment:
				-- for gcc / ubuntu looks like off_t is defined in either unistd.h or stdio.h, and either are set via testing/setting __off_t_defined
				-- in other words, the defs in here are getting more and more conditional ...
				-- pretty soon a full set of headers + full preprocessor might be necessary
				-- TODO regen this on Windows and compare?
			code = code .. [[
return require 'ffi.load' 'hdf5'	-- pkg-config --libs hdf5
]]
			return code
		end,
		-- ffi.load override information
		-- TODO somehow insert this into ffi/load.lua without destroying the file
		-- don't modify require 'ffi.load' within 'ffi.hdf5', since the whole point of fif.load is for the user to provide overrides to the lib loc that the header needs.
		ffiload = {
			hdf5 = {Linux = '/usr/lib/x86_64-linux-gnu/hdf5/serial/libhdf5.so'},
		},
	},

-- these external files are per-OS
-- maybe eventually all .h's will be?


	-- apt install libtiff-dev
	-- also per-OS
	-- depends: stddef.h stdint.h inttypes.h stdio.h stdarg.h
	{
		inc = '<tiffio.h>',
		out = 'tiff.lua',
		pkgconfig = 'libtiff-4',
		--[[ someone somewhere is getting mixed up because of symlinks so ...
		macroincs = {
			'/usr/local/opt/libtiff/include/tiff.h',
			'/usr/local/opt/libtiff/include/tiffconf.h',
			'/usr/local/opt/libtiff/include/tiffvers.h',
		},
		--]]
		--[[ can we fix it with include search paths? no...
		macroincs = {
			'<tiffconf.h>',
		},
		--]]
		final = function(code, preproc)
			for _,k in ipairs{'int8', 'uint8', 'int16', 'uint16', 'int32', 'uint32', 'int64', 'uint64'} do
				code = safegsub(code, string.patescape('typedef '..k..'_t '..k..' __attribute__((deprecated));'), '')
			end
			for _,k in ipairs{
				'U_NEU', 'V_NEU', 'UVSCALE'
				-- unnecessary:
				--'D65_X0', 'D65_Y0', 'D65_Z0', 'D50_X0', 'D50_Y0', 'D50_Z0',
			} do
				code = removeEnum(code, k..' = %S+')
			end
			local code = makeLibWrapper{
				code = code,
				preproc = preproc,
				lib = 'tiff',
				funcs = ffi.os ~= 'Windows' and {
[=[

		-- Windows-only ...
		TIFFOpenW = [[TIFF *TIFFOpenW(wchar_t const *, char const *);]],
		TIFFOpenWExt = [[TIFF *TIFFOpenWExt(wchar_t const *, char const *, TIFFOpenOptions *opts);]],]=]
				} or nil,
				footerCode = table{
					'-- macros',
					'',
					}:append(table{
							'TIFFLIB_VERSION_STR', 'TIFFLIB_VERSION_STR_MAJ_MIN_MIC', 'D65_X0', 'D65_Y0', 'D65_Z0', 'D50_X0', 'D50_Y0', 'D50_Z0', 'U_NEU', 'V_NEU', 'UVSCALE',
						}:mapi(function(k,_,t)
							local v = preproc.macros[k]
							if v then
								v = v:match'^%((.*)F%)$' or v	-- get rid of those ( ... F) floats
								return 'wrapper.'..k..' = '..v, #t+1
							end
						end)
					):concat'\n'..'\n',
			}
			-- zlib libtiff libpng EGL
			code = code:gsub(string.patescape'(void)', '()')
			return code
		end,
	},

	-- apt install libjpeg-turbo-dev
	-- linux is using 2.1.2 which generates no different than 2.0.3
	--  based on apt package libturbojpeg0-dev
	-- windows is using 2.0.4 just because 2.0.3 and cmake is breaking for msvc
	{
		inc = '<jpeglib.h>',
		pkgconfig = 'libjpeg',
		-- [[ TODO
		macroincs = {
			-- these are for the macro preprocessor to know what macros to keep for emitting into enums, vs which to throw out
			'<jconfig.h>',
			'<jmorecfg.h>',
		},
		--]]
		out = 'jpeg.lua',
		final = function(code, preproc)
			return makeLibWrapper{
				code = code,
				lib = 'jpeg',
				requires = {
					"require 'ffi.req' 'c.stdio'	-- for FILE, even though jpeglib.h itself never includes <stdio.h> ... hmm ...",

					-- I guess I have to hard-code the OS-specific typedef stuff that goes in the header ...
					-- and then later gsub out these typedefs in each OS that generates it...
					[=[

-- TODO does this discrepency still exist in Windows' LibJPEG Turbo 3.0.4 ?
if ffi.os == 'Windows' then
	ffi.cdef[[
typedef unsigned char boolean;
typedef signed int INT32;
]]
else
	ffi.cdef[[
typedef long INT32;
typedef int boolean;
]]
end]=]
				},
				footerCode = [[

-- these are #define's in jpeglib.h

wrapper.LIBJPEG_TURBO_VERSION = ']]
	..assert.type(preproc.macros.LIBJPEG_TURBO_VERSION, 'string')
	..[['

function wrapper.jpeg_create_compress(cinfo)
	return wrapper.jpeg_CreateCompress(cinfo, wrapper.JPEG_LIB_VERSION, ffi.sizeof'struct jpeg_compress_struct')
end

function wrapper.jpeg_create_decompress(cinfo)
	return wrapper.jpeg_CreateDecompress(cinfo, wrapper.JPEG_LIB_VERSION, ffi.sizeof'struct jpeg_decompress_struct')
end
]]
			}
		end,
		ffiload = {
			jpeg = {
				-- For Windows msvc turbojpeg 2.0.3 cmake wouldn't build, so i used 2.0.4 instead
				-- I wonder if this is the reason for the few subtle differences
				-- TODO rebuild linux with 2.0.4 and see if they go away?
				Windows = 'jpeg8',
				-- for Linux, libturbojpeg 2.1.2 (which is not libjpeg-turbo *smh* who named this)
				-- the header generated matches libturbojpeg 2.0.3 for Ubuntu ... except the version macros
			},
		},
	},

	{
		inc = '<lua.h>',
		moreincs = {'<lualib.h>', '<lauxlib.h>'},
		out = 'lua.lua',
		pkgconfig = 'lua',
		final = function(code)
			code = [[
]] .. code .. [[
return require 'ffi.load' 'lua'
]]
			return code
		end,
	},

	-- depends on complex.h
	{inc='<cblas.h>', out='cblas.lua', final=function(code)
		code = [[
]] .. code .. [[
return require 'ffi.load' 'openblas'
]]
		return code
	end},

	{
		inc = '<lapack.h>',
		out = 'lapack.lua',
		pkgconfig = 'lapack',
		final = function(code)
			-- needs lapack_int replaced with int, except the enum def line
			-- the def is conditional, but i think this is the right eval ...
			code = safegsub(code, 'enum { lapack_int = 0 };', 'typedef int32_t lapack_int;')
--[[
#if defined(LAPACK_ILP64)
#define lapack_int		int64_t
#else
#define lapack_int		int32_t
#endif
--]]

			-- preproc on this generate a *LOT* of `enum { LAPACK_lsame_base = 0 };`
			-- they are generated from macro calls to LAPACK_GLOBAL
			-- which is defined as
			-- #define LAPACK_GLOBAL(lcname,UCNAME)  lcname##_
			-- ... soo ... I need to not gen enums for macros that do string manipulation or whatever
			code = safegsub(code, 'enum { LAPACK_[_%w]+ = 0 };', '')
			code = safegsub(code, '\n\n', '\n')

			code = code .. [[
return require 'ffi.load' 'lapack'
]]
			return code
		end,
	},

	{
		inc = '<lapacke.h>',
		out = 'lapacke.lua',
		pkgconfig = 'lapacke',
		final = function(code)
			code = code .. [[
return require 'ffi.load' 'lapacke'
]]
		return code
		end,
	},

	-- libzip-dev
	-- TODO #define ZIP_OPSYS_* is hex values, should be enums, but they are being commented out ...
	-- because they have 'u' suffixes
	-- same with some other windows #defines
	-- any that have u i etc i32 i64 etc are being failed by my parser.
	{
		inc = '<zip.h>',
		macroincs = {
			-- these are for the macro preprocessor to know what macros to keep for emitting into enums, vs which to throw out
			'<zipconf.h>'
		},
		out = 'zip.lua',
		final = function(code, preproc)
			-- I'll just put these in the macros since they don't fit in luajit enums ...
			code = removeEnum(code, 'ZIP_INT64_MAX = [^\n]*')
			code = removeEnum(code, 'ZIP_UINT64_MAX = [^\n]*')
			-- TODO get ZIP_UINT32_MAX working
			return makeLibWrapper{
				code = code,
				preproc = preproc,
				lib = 'zip',
				footerCode = [[
-- macros

wrapper.LIBZIP_VERSION = ]]..preproc.macros.LIBZIP_VERSION..'\n'..[[
wrapper.ZIP_INT64_MAX = ]]..preproc.macros.ZIP_INT64_MAX..'\n'..[[
wrapper.ZIP_UINT64_MAX = ]]..preproc.macros.ZIP_UINT64_MAX..'\n'..[[
]]
			}
		end,
	},

	-- produces an "int void" because macro arg-expansion covers already-expanded macro-args
	{
		inc = '<png.h>',
		out = 'png.lua',
		macroincs = {
			'<pngconf.h>',
			'<pnglibconf.h>',
		},
		final = function(code, preproc)
			-- TODO remove contents of pnglibconf.h, or at least the PNG_*_SUPPORTED macros

			-- still working out macro bugs ... if macro expands arg A then I don't want it to expand arg B
			--code = safegsub(code, 'int void', 'int type');

			local code = makeLibWrapper{
				code = code,
				preproc = preproc,
				lib = 'png',
				footerCode = [[
-- macros

wrapper.PNG_LIBPNG_VER_STRING = ]]..preproc.macros.PNG_LIBPNG_VER_STRING..'\n'..[[
wrapper.PNG_HEADER_VERSION_STRING =  ' libpng version '..wrapper.PNG_LIBPNG_VER_STRING..'\n'

-- this is a value in C but a function in Lua
function wrapper.png_libpng_ver() return wrapper.png_get_header_ver(nil) end

wrapper.PNG_GAMMA_THRESHOLD = wrapper.PNG_GAMMA_THRESHOLD_FIXED * .00001

]],
			}
			-- zlib libtiff libpng EGL
			code = code:gsub(string.patescape'(void)', '()')
			return code
		end,
	},

	{
		inc = '<ogg/ogg.h>',
		-- build this separately for each OS.
		-- generate the os splitter file
		out = ffi.os..'/ogg.lua',
		os = ffi.os,
	},

	{
		inc = '<vorbis/codec.h>',
		out = 'vorbis/codec.lua',
	},
	{
		inc = '<vorbis/vorbisfile.h>',
		out = 'vorbis/vorbisfile.lua',
		includedirs = {
			'/usr/include/vorbis',
			'/usr/local/include/vorbis',
		},
		final = function(code)
			-- the result contains some inline static functions and some static struct initializers which ffi cdef can't handle
			-- ... I need to comment it out *HERE*.
			code = safegsub(code, 'static int _ov_header_fseek_wrap%b()%b{}', '')
			code = safegsub(code, 'static ov_callbacks OV_CALLBACKS_[_%w]+ = %b{};', '')

			code = code .. [[
local lib = require 'ffi.load' 'vorbisfile'

-- don't use stdio, use ffi.C
-- stdio risks browser shimming open and returning a Lua function
-- but what that means is, for browser to work with vorbisfile,
-- browser will have to shim each of he OV_CALLBACKs
-- ... or browser should/will have to return ffi closures of ffi.open
-- ... then we can use stdio here
local stdio = require 'ffi.req' 'c.stdio'	-- fopen, fseek, fclose, ftell

-- i'd free the closure but meh
-- who puts a function as a static in a header anyways?
local _ov_header_fseek_wrap = ffi.cast('int (*)(void *, ogg_int64_t, int)', function(f,off,whence)
	if f == nil then return -1 end
	return stdio.fseek(f,off,whence)
end)

local OV_CALLBACKS_DEFAULT = ffi.new'ov_callbacks'
OV_CALLBACKS_DEFAULT.read_func = stdio.fread
OV_CALLBACKS_DEFAULT.seek_func = _ov_header_fseek_wrap
OV_CALLBACKS_DEFAULT.close_func = stdio.fclose
OV_CALLBACKS_DEFAULT.tell_func = stdio.ftell

local OV_CALLBACKS_NOCLOSE = ffi.new'ov_callbacks'
OV_CALLBACKS_NOCLOSE.read_func = stdio.fread
OV_CALLBACKS_NOCLOSE.seek_func = _ov_header_fseek_wrap
OV_CALLBACKS_NOCLOSE.close_func = nil
OV_CALLBACKS_NOCLOSE.tell_func = stdio.ftell

local OV_CALLBACKS_STREAMONLY = ffi.new'ov_callbacks'
OV_CALLBACKS_STREAMONLY.read_func = stdio.fread
OV_CALLBACKS_STREAMONLY.seek_func = nil
OV_CALLBACKS_STREAMONLY.close_func = stdio.fclose
OV_CALLBACKS_STREAMONLY.tell_func = nil

local OV_CALLBACKS_STREAMONLY_NOCLOSE = ffi.new'ov_callbacks'
OV_CALLBACKS_STREAMONLY_NOCLOSE.read_func = stdio.fread
OV_CALLBACKS_STREAMONLY_NOCLOSE.seek_func = nil
OV_CALLBACKS_STREAMONLY_NOCLOSE.close_func = nil
OV_CALLBACKS_STREAMONLY_NOCLOSE.tell_func = nil

return setmetatable({
	OV_CALLBACKS_DEFAULT = OV_CALLBACKS_DEFAULT,
	OV_CALLBACKS_NOCLOSE = OV_CALLBACKS_NOCLOSE,
	OV_CALLBACKS_STREAMONLY = OV_CALLBACKS_STREAMONLY,
	OV_CALLBACKS_STREAMONLY_NOCLOSE = OV_CALLBACKS_STREAMONLY_NOCLOSE,
}, {
	__index = lib,
})
]]
			return code
		end,
	},

	{
		-- brew install openal-soft
		inc = '<AL/al.h>',
		moreincs = {
			'<AL/alc.h>',
		},
		includedirs = ffi.os == 'OSX' and {
			'/usr/local/opt/openal-soft/include',
		} or nil,
		out = 'OpenAL.lua',
		final = function(code)
			return code .. [[
return require 'ffi.load' 'openal'
]]
		end,
		ffiload = {
			openal = {Windows = 'OpenAL32'},
		},
	},

	{
		inc = '<pulse/pulseaudio.h>',
		out = 'pulse.lua',
		final = function(code)
			-- so this spits out enums for both enums and #define's
			-- that runs us into trouble sometimes ...
			local lines = string.split(code, '\n')
			local definedEnums = {}
			for i=1,#lines do
				local line = lines[i]
				if line:match'^typedef enum' then
					for w in line:gmatch'%S+' do
						if w:match'^PA_' then
							if w:match',$' then w = w:sub(1,-2) end
--io.stderr:write('defining typedef enum '..w..'\n')
							definedEnums[w] = true
						end
					end
				end
				local prefix, enumName = line:match'^(.*)enum { (.*) = 0 };$'
				if enumName then
--io.stderr:write('found enum=0 name '..enumName..'\n')
					if definedEnums[enumName] then
--io.stderr:write('...removing\n')
						lines[i] = prefix
					end
				end
			end
			code = lines:concat'\n'
			-- undefs of static inline functions ...
			for f in ([[PA_CONTEXT_IS_GOOD PA_STREAM_IS_GOOD PA_SINK_IS_OPENED PA_SOURCE_IS_OPENED]]):gmatch'%S+' do
				code = removeStaticInlineFunction(code, f)
				code = safegsub(code, 'enum { '..f..' = 0 };', '')
			end
			return code
		end,
	},

	{	-- libelf
		inc = '<gelf.h>',		-- gelf.h -> libelf.h -> elf.h
		moreincs = {
			'<elfutils/version.h>',
			'<elfutils/elf-knowledge.h>',
		},
		-- there's also elfutils/elf-knowledge.h and elfutils/version.h ...
		out = 'elf.lua',
		final = function(code)
			-- #define ELF_F_DIRTY ELF_F_DIRTY before enum ELF_F_DIRTY causes this:
			code = removeEnum(code, 'ELF_F_DIRTY = 0')
			code = removeEnum(code, 'ELF_F_LAYOUT = 0')
			code = removeEnum(code, 'ELF_F_PERMISSIVE = 0')
			code = removeEnum(code, 'ELF_CHF_FORCE = 0')
			code = code .. '\n'
				.."return require 'ffi.load' 'elf'\n"
			return code
		end,
	},

	{
		inc = '<tensorflow/c/c_api.h>',
		out = 'tensorflow.lua',
		-- tensorflow is failing when it includes <string.h>, which is funny because I already generate <string.h> above
		-- something in it is pointing to <secure/_string.h>, which is redefining memcpy ... which is breaking my parser (tho it shouldnt break, but i don't want to fix it)
		skipincs = (ffi.os == 'OSX') and {'<string.h>'} or {},
		final = function(code)
			code = code .. [[
return require 'ffi.load' 'tensorflow'
]]
			return code
		end,
	},
})

-- now detect any duplicate #include paths and make sure they are going to distinct os-specific destination file names
-- and in those cases, add in a splitting file that redirects to the specific OS
local detectDups = {}
for _,inc in ipairs(includeList) do
	detectDups[inc.inc] = detectDups[inc.inc] or {}
	local det = detectDups[inc.inc][inc.os or 'all']
	if det then
		print("got two entries that have matching include name, and at least one is not os-specific: "..tolua{
			det,
			inc,
		})
	end
	detectDups[inc.inc][inc.os or 'all'] = inc
end
for incname, det in pairs(detectDups) do
	if type(det) == 'table' then
		local keys = table.keys(det)
		-- if we had more than 1 key
		if #keys > 1
		then
			local base
			for os,inc in pairs(det) do
				assert(inc.os, "have a split file and one entry doesn't have an os... "..tolua(inc))
				local incbase = inc.out:match('^'..inc.os..'/(.*)$')
				if not incbase then
					error("expected os "..tolua(inc.os).." prefix, bad formatted out for "..tolua(inc))
				end
				if base == nil then
					base = incbase
				else
					assert(incbase == base, "for split file, assumed output is [os]/[path] ,but didn't get it for "..tolua(inc))
				end
			end
--[=[ add in the split file
			includeList:insert{
				inc = incname,
				out = base,
				-- TODO this assumes it is Windows vs all, and 'all' is stored in Linux ...
				-- TODO autogen by keys.  non-all <-> if os == $key, all <-> else, no 'all' present <-> else error "idk your os" unless you wanna have Linux the default
				forcecode = template([[
local ffi = require 'ffi'
if ffi.os == 'Windows' then
	return require 'ffi.Windows.<?=req?>'
else
	return require 'ffi.Linux.<?=req?>'
end
]], 			{
					req = (assert(base:match'(.*)%.lua', 'expcted inc.out to be ext .lua')
						:gsub('/', '.')),
				})
			}
--]=]
		end
	end
end


-- remove all those that pertain to other os/arch
includeList = includeList:filter(function(inc)
	if inc.os ~= nil and inc.os ~= ffi.os then return end
	if inc.arch ~= nil and inc.arch ~= ffi.arch then return end
	return true
end)


local class = require 'ext.class'
local IncludeFile = class()
function IncludeFile:setupPkgConfig()
	if self.hasSetupPkgConfig then return end
	self.hasSetupPkgConfig = true

	if self.pkgconfig
	-- pkgconfig doesn't work on windows so rather than try and fail a lot ...
	and ffi.os ~= 'Windows'
	then
		local out = string.trim(io.readproc('pkg-config --cflags '..self.pkgconfig))
		local flags = string.split(out, '%s+')

		-- HERE process -I -D flags
		for _,f in ipairs(flags) do
			if f:sub(1,2) == '-D' then
				assert.gt(#f, 2, 'TODO handle -D <macro>')
				self.macros = self.macros or table()
				self.macros:insert(f:sub(3))
			elseif f:sub(1,2) == '-I' then
				assert.gt(#f, 2, 'TODO handle -I <incdir>')
				self.includedirs = table(self.includedirs)
				self.includedirs:insert(f:sub(3))
			else
				error("pkg-config '"..self.pkgconfig.."' has unknown flag "..tostring(f)..'\n'
					..'pkg-config output: '..out)
			end
		end
	end
end

for i,inc in ipairs(includeList) do
	assert(not getmetatable(inc), 'index='..i..' inc='..tostring(inc.inc))
	setmetatable(inc, IncludeFile)
end

return includeList
