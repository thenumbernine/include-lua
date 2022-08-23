#!/usr/bin/env luajit
local include = require 'include'

-- [[ OpenGL.lua
include "<GL/gl.h>" 
include.preproc:setMacros{GL_GLEXT_PROTOTYPES=1}
include "<GL/glext.h>"
--]]
