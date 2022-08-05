## lua-include

If you want to use LuaJIT FFI with typical C `#include` statements.

Depends on my `preproc-lua` project.

Uses the environment variable `$LUAJIT_INCLUDE_CACHE_PATH/cache` for storing, otherwise uses `$HOME/.luajit.include/cache`.
