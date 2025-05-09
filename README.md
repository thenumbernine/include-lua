[![Donate via Stripe](https://img.shields.io/badge/Donate-Stripe-green.svg)](https://buy.stripe.com/00gbJZ0OdcNs9zi288)<br>

Useful for LuaJIT FFI cdefs just straight up using the .h files

Used for generating the code in my [Lua FFI bindings](https://github.com/thenumbernine/lua-ffi-bindings) repo.

Depends on:
- [C preproc lib](https://github.com/thenumbernine/preproc-lua) for C preprocessing
- [C H parser lib](https://github.com/thenumbernine/c-h-parser-lua) for C header parsing

Produces content for my
- [Lua FFI bindings](https://github.com/thenumbernine/lua-ffi-bindings)

## `make.lua` ##

To generate all binding files for your current OS:
```
./make.lua all
```

To generate all starting at a specific point:
```
./make.lua 'start=<jpeglib.h>'
```

To generate a single binding file:
```
./make.lua '<jpeglib.h>'
```

It then calls into `generate.lua` to produce the LuaJIT binding file.
The results are stored in `results/ffi/*`.

## `generate.lua` ##

This file returns a single function `generate(inc)` that acts on an entry in the `include-list.lua` file.
It generates the LuaJIT binding file by talking to the system compiler (`cl.exe` or `gcc`),
environment macros, [C preprocessor](https://github.com/thenumbernine/preproc-lua),
and [C header parser](https://github.com/thenumbernine/c-h-parser-lua).

The C preprocessor will generate parsed headers are specific to LuaJIT:
- They have `#define` constants replaced with `enum{}`'s.
- They have function prototypes preserved.

## `include-list.lua` ##

This contains a list of information on converting C to Lua files.
It is used for the generation of the Lua binding files.
Include list entries contain the following properties:
- `inc` = the main `.h` include file , and what the `make.lua` CLI uses to identify what you are trying to generate.  Should be wrapped in `""` or `<>` for user vs system search paths.
- `out` = the `.lua` file generated.
- `os` = which `ffi.os` this file is specific to.
- `moreincs` = A list of any extra `.h` files that should be included in the Lua binding file generation.
- `skipincs` = A list of `.h` files that the preprocessor should skip over when it encounters an `#include` directive.
- `silentincs` = A list of `.h` files that should be parsed for the sake of the preprocessor's state, but whose contents should be suppressed from the final Lua binding file.
- `includedirs` = A list of paths to add to our preprocessor include dir search path.
- `macros` = A list of entries to initially add to our preprocessor's macros.
- `pkgconfig` = The name of the `pkg-config ${name} --cflags` script to invoke.  `-D` flags are collected into `inc.macros` and `-I` flags are collected into `inc.includedirs`.
- `final(code, preproc)` = A final callback on the preprocessor-generated code in case the results need any hand-tuning.
- `forcecode` = For a rare few files, it's not worth parsing at all.  Set this to just override the whole thing.
- `dontGen` = For Linux system include files.  Some of the hoops I have to go through to get around generating the Lua equivalents of the Linux system files that are loaded up with preprocessors that error and say "never include this file directly!"...
- `enumGenUnderscoreMacros` = Used with a small few Linux system include files, I forget exactly why I used this but it was for preventing unnecessary enum output.
- `ffiload` = Planning on eventually using this for inserting entries into `ffi/load.lua`.
- `macroincs` = List of `.h`'s, in addition to `inc` and `moreincs` that the preprocessor should save `#define` numeric values to convert into enums.

Fair warning, the OS-specific include files in there are pretty terse, but the 3rd party library include generation code is near the bottom and it is all very straightforward.

### `makeLibWrapper()`

Some of the `include-list.lua` entries make use of the `makeLibWrapper()` function.
This will produce a moreso organize LuaJIT binding code that is designed to defer loading symbols until they are used.
These files will look like the following:

``` Lua
local ffi = require 'ffi'

-- comments

--[[
# comments and indecypherable macros go here
--]]

-- typedefs

-- C #include to Lua require() calls co here.
require 'ffi.req' 'c.stdio'
require 'ffi.req' 'c.stdlib'
require 'ffi.req' 'c.etc'
...

ffi.cdef[[
// C typedefs, named structs, and named enums go here.
...
]]

local wrapper
wrapper = require 'ffi.libwrapper'{
	defs = {
		-- enums
			-- unnamed enum key/values go here, to be loaded upon their first reference.
		...

		-- functions
			-- symbols (functions and extern-variables) go here, to be loaded upon their first reference.
		...
	},
}

-- macros
...

return wrapper
```
