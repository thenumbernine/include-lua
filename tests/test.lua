#! /usr/bin/env luajit
local include = require 'include'

local stdio = include '<stdio.h>'

stdio.printf("testing %d\n", 42)
