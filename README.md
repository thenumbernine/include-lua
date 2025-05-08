[![Donate via Stripe](https://img.shields.io/badge/Donate-Stripe-green.svg)](https://buy.stripe.com/00gbJZ0OdcNs9zi288)<br>

Useful for LuaJIT FFI cdefs just straight up using the .h files

Used for generating the code in my [Lua FFI bindings](https://github.com/thenumbernine/lua-ffi-bindings) repo.

Depends on:
- [C preproc lib](https://github.com/thenumbernine/preproc-lua) for C preprocessing
- [C H parser lib](https://github.com/thenumbernine/c-h-parser-lua) for C header parsing

Produces content for my
- [Lua FFI bindings](https://github.com/thenumbernine/lua-ffi-bindings)

## `make.lua` ##

This generates a LuaJIT loader file for a requested C include file. e.g.
```
./make.lua '<jpeglib.h>'
```

It accepts either a specific header listed in the `include-list`, or `al` will generate all in the list in one go.
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

Fair warning, the OS-specific include files in there are pretty terse, but the 3rd party library include generation code is near the bottom and it is all very straightforward.

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
