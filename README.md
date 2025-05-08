[![Donate via Stripe](https://img.shields.io/badge/Donate-Stripe-green.svg)](https://buy.stripe.com/00gbJZ0OdcNs9zi288)<br>

Useful for LuaJIT FFI cdefs just straight up using the .h files

Used for generating the code in my [`lua-ffi-bindings`](https://github.com/thenumbernine/lua-ffi-bindings) repo.

Depends on:
- [C preproc lib](https://github.com/thenumbernine/preproc-lua) for C preprocessing
- [C H parser lib](https://github.com/thenumbernine/c-h-parser-lua) for C header parsing

Produces content for my
- [Lua FFI bindings](https://github.com/thenumbernine/lua-ffi-bindings)

## `make.lua` ##

This generates a specific LuaJIT loader file for a specific C include file.
It accepts either a specific header listed in the `include-list`, or it can generate all provided at once.
This is separate of `generate.lua` because I need to use separate LuaJIT FFI cdef states, so I just use separate processes.

This is close to becoming what the `include-lua` project intended to be.
However if you look inside the `include-list` you will see the amount of hand-tuning still required for this to work.
Until that can all be automated, `include-lua` will be on the shelf for a while.

## `include-list.lua` ##

This contains a list of C to Lua files.
It is used for automatic generation of all files.
It is also used for determining when to replace an included file with a previously-generated file.

## `generate.lua` ##

This file generates stripped header files from C header files.
The stripped headers are specific to LuaJIT:
- They have `#define` constants replaced with `enum{}`'s.
- They have function prototypes preserved.

`luajit generate.lua <optional-args> <include-file1> <include-file2> ...`

optional-args:
- `-I<include-dir>` = add extra include directory search path
- `-M<macro-name>[=<macro-value>]` = add extra macro
- `-silent <include-file>` = include the specified file, but do not include its contents in the header generation.
- `-skip <include-file>` = don't include the specified file.

## History

This started as an attempt to do a drop-in of C `#include`'s in Lua.

But from some experience I found that the resulting code always needed some hand-tuning.

Then for some reason I built up the hand-tuned section inside of my [preproc](https://github.com/thenumbernine/preproc-lua) project.

Then I realized that I wanted a [C header parser](https://github.com/thenumbernine/c-h-parser-lua) as well as a C preprocessor.

And now I'm realizing that the Lua binding generator should be separate of the two of them.

All this to put the results in the [Lua FFI bindings](https://github.com/thenumbernine/lua-ffi-bindings) repo.

So I think I will scrap the old attempt here (which tried automating too much) and replace it with the tried-and-true method that's been built up in preproc, and leave preproc to be dedicated to C preprocessor only.

## TODO / Things I'm Considering

- Should `.code` hold the last file processed, or the total files processed?

- If I'm in the middle of a typedef or `enum` or something with `{}`'s, I should wait to insert the `#define` => `enum{}` code.  (`pthread.h`)

- Hitting the table upper limit of `ffi.C` is easy to do with all the symbols generated.
To get around this I've created [`libwrapper.lua`](https://github.com/thenumbernine/lua-ffi-bindings/blob/master/libwrapper.lua) in my [lua-ffi-bindings](https://github.com/thenumbernine/lua-ffi-bindings) project.
`libwrapper` gives each library its own unique table and defers loading of enums or functions until after they are referenced.
This gets around the LuaJIT table limit.  Now you can export every symbol in your header without LuaJIT giving an error.
But for now the headers are manually ported from `preproc` output to `libwrapper` output.  In the future I might autogen `libwrapper` output.
- ... but not for long!  I made a [c-h-parser](https://github.com/thenumbernine/c-h-parser-lua) as a subclass of my [parser](https://github.com/thenumbernine/lua-parser) library, and now I can use it to auto-generate the libwrappers instead of by hand.
- ... but now its one big problem is inserting `#define` enums versus inserting enum-enums ... TODO FIXME ...
