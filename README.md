[![Donate via Stripe](https://img.shields.io/badge/Donate-Stripe-green.svg)](https://buy.stripe.com/00gbJZ0OdcNs9zi288)<br>

## lua-include

If you want to use LuaJIT FFI with typical C `#include` statements.

Depends on:
- [preproc-lua](https://github.com/thenumbernine/preproc-lua)
- [lua-ext](https://github.com/thenumbernine/lua-ext)
- [lua-template](https://github.com/thenumbernine/lua-template)
- LuaJIT

Uses the environment variable `$LUAJIT_INCLUDE_CACHE_PATH` for storing, otherwise uses `$HOME/.luajit.include`.

# Example:
``` lua
local ffi = require 'ffi'
local include = require 'include'
local stdio = include '<stdio.h>'
stdio.printf("testing %d\n", ffi.cast('int64_t', 42))
```

# TODO:

- The cache stores by searched filename, but it would be nice if it could also first store by included filename, so that subsequent include's could get the correct file without doing a search (in case it's on a system where the C includes/compile is missing)
