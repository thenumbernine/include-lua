#! /usr/bin/env luajit
local ffi = require 'ffi'
local include = require 'include'
local stdio = include '<stdio.h>'
stdio.printf("testing %d %.50f %s\n", 
	ffi.cast('int64_t', 42),		-- who determines the size/type conversion of vararg printf arguments?
	ffi.cast('double', math.pi),
	"Foo")
