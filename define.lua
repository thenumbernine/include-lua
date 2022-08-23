--[[
ok starting to think I should just call these files "preproc.include" and "preproc.define"

I'm not going to handle preproc stuff / macro expansions here.
If I did then maybe this would go inside Preproc itself.

Instead this will be 'include'-centric, so It'll inject preproc.macros and it'll cdef

Such that this function can be inserted into the include-generated files.

So this is close to what Preproc:getDefineCode was doing or was going to do.
--]]
local function(...)
	local n = select('#', ...)
	if n == 0 then
		error("expected <line> or <key> <value>")
	end
	local preproc = require 'include'.preproc

	if n == 1 then
		-- TODO maybe later
		--local l = ...
		--preproc:getDefineCode(
		error("expected <key> <value>")
	end
	
	local k, v = ...
	-- TODO I think include's preproc overrides this functionality ... and that should be moved into here (and replaced with define() calls in include.lua)
	preproc:getDefineCode(k, v)
end
