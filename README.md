## lua-include

If you want to use LuaJIT FFI with typical C `#include` statements.

Depends on:
- [preproc-lua](https://github.com/thenumbernine/preproc-lua)
- [lua-ext](https://github.com/thenumbernine/lua-ext)
- LuaJIT

Uses the environment variable `$LUAJIT_INCLUDE_CACHE_PATH/cache` for storing, otherwise uses `$HOME/.luajit.include/cache`.

# Example:
```
local ffi = require 'ffi'
local include = require 'include'
local stdio = include '<stdio.h>'
stdio.printf("testing %d\n", ffi.cast('int64_t', 42))
```
