#!/usr/bin/env luajit
local ffi = require 'ffi'
-- test that all requires play well together

-- maybe just the system-level ones ...
local includeList = require('include-list-'..ffi.os:lower())

package.path='results/?.lua;'..package.path 

for _,inc in ipairs(includeList) do
	require 'ffi.req' (assert((inc.out:match'(.*)%.lua')):gsub('/', '.'))
end
