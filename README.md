[![Donate via Stripe](https://img.shields.io/badge/Donate-Stripe-green.svg)](https://buy.stripe.com/00gbJZ0OdcNs9zi288)<br>

## lua-include

This started as an attempt to do a drop-in of C `#include`'s in Lua.

But from some experience I found that the resulting code always needed some hand-tuning.

Then for some reason I built up the hand-tuned section inside of my [preproc](https://github.com/thenumbernine/preproc-lua) project.

Then I realized that I wanted a [C header parser](https://github.com/thenumbernine/c-h-parser-lua) as well as a C preprocessor.

And now I'm realizing that the Lua binding generator should be separate of the two of them.

All this to put the results in the [Lua FFI bindings](https://github.com/thenumbernine/lua-ffi-bindings) repo.

So I think I will scrap the old attempt here (which tried automating too much) and replace it with the tried-and-true method that's been built up in preproc, and leave preproc to be dedicated to C preprocessor only.

