#!/usr/bin/env luajit
local ffi = require 'ffi'
local path = require 'ext.path'
local table = require 'ext.table'
local os = require 'ext.os'
local includeList = table(require 'include-list')

local req = assert(..., "`make.lua all` for all, or `make.lua <sourceIncludeFile.h>`")

local start = req:match'^start=(.*)$'
if start then
	for i=assert(includeList:find(nil, function(inc) return inc.inc == start end), "couldn't find starting point: "..start)-1,1,-1 do
		includeList:remove(i)
	end
elseif req ~= 'all' then
	-- TODO seems using <> or "" now is essential for excluding recursive require's
	if req:sub(1,1) ~= '<' and req:sub(1,1) ~= '"' then
		error('must be system (<...>) or user ("...") include space')
	end
	print('searching for '..req)
	includeList = includeList:filter(function(inc) return inc.inc == req end)
	if #includeList == 0 then
		error("couldn't find "..req)
	end
end

local outdirbase = path'results'	-- also in generate.lua
for _,inc in ipairs(includeList) do
	if not inc.dontGen then
		local outpath = outdirbase/'ffi'/inc.out
		outpath:getdir():mkdir(true)

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
		assert(os.exec([[luajit -e "package.path=']]..outdirbase..[[/?.lua;'..package.path require 'ffi.req' ']]..assert((inc.out:match'(.*)%.lua')):gsub('/', '.')..[['"]]))
		--]=]
	end
end
