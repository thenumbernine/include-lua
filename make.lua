#!/usr/bin/env luajit
local ffi = require 'ffi'
local path = require 'ext.path'
local table = require 'ext.table'
local os = require 'ext.os'

local includeList = require 'include-list'

local req = ...
if not req then error("`make.lua all` for all, or `make.lua <sourceIncludeFile.h>`") end
if req ~= 'all' then
	-- TODO seems using <> or "" now is essential for excluding recursive require's
	if req:sub(1,1) ~= '<' and req:sub(1,1) ~= '"' then
		error('must be system (<...>) or user ("...") include space')
	end
	print('searching for '..req)
	includeList = table.filter(includeList, function(inc)
		--return inc.inc:match(req)
		return inc.inc == req
	end):setmetatable(nil)
	if #includeList == 0 then
		error("couldn't find "..req)
	end
end

local outdirbase = path'results'	-- outdir without ffi/
local outdir = outdirbase/'ffi'
for _,inc in ipairs(includeList) do
	if not inc.dontGen then
		local outpath = outdir/inc.out
		local dir, outfn = outpath:getdir()
		dir:mkdir(true)

		if inc.forcecode then
			-- just write it , proly a split between dif os versions
			outpath:write(inc.forcecode)
		else
			outpath:write(require 'generate'(inc))
		end

		if ffi.os == 'Windows' then
			-- in windows, the linux code writes \n's, but the windows >> writes \r\n's,
			-- so unify them all here, pick whichever format you want
			outpath:write((
				outpath:read()
					:gsub('\r\n', '\n')
			))
		end

		-- verify it works
		-- can't use -lext because that will load ffi/c stuff which could cause clashes in cdefs
		-- luajit has loadfile, nice.
		--[=[ use loadfile ... and all the old/original ffi locations
		assert(os.exec([[luajit -e "assert(loadfile(']]..outpath..[['))()"]]))
		--]=]
		-- [=[ use require, and base it in the output folder
		assert(os.exec([[luajit -e "package.path=']]..outdirbase..[[/?.lua;'..package.path require 'ffi.req' ']]..assert((inc.out:match('(.*)%.lua'))):gsub('/', '.')..[['"]]))
		--]=]
	end
end
