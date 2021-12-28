# hammerspoon-bear

A Spoon (module) for using [Hammerspoon](https://www.hammerspoon.org)
to enhancle the functionality of [Bear.app](https://bear.app/).

## Introduction

This module wraps some of the [Bear "x-callback-url"
API](https://bear.app/faq/X-callback-url%20Scheme%20documentation/) with
convenience Lua functions. The wrapping is done using the xcall command-line
tool which implements the x-callback-url in a synchronous fashion. The bottom
line is that you can automate Bear from Hammerspoon.

## Templates

In addition to implementing the Bear API, this module also implements a simple
templating system, using the "etlua" template engine
(https://github.com/leafo/etlua). To use the templates, just create a Bear note
that containes template text, and then call the `createFromTemplate` method.
(You likely want to bind this to a hotkey). The template text can access
any Hammerspoon / Lua function -- so be careful.

For example, if your note looks like this:

```
# A simple bear note template

Today is <%= os.date("%A, %B %d, %Y") %>. Have a nice day.
```

When you call `createFromTemplate` the new note will look something like:

```
# A simple bear note template

Today is Monday, December 31, 2019. Have a nice day.
```

See the [etlua](https://github.com/leafo/etlua) documentation for more details.
The template is evaluated with access to additional symbols defined in the
`template_env` table. Some convenience functions are pre-defined -- see the
[source](https://github.com/dcreemer/hammerspoon-bear/blob/main/init.lua) for
details.

The author [uses this
tool](https://github.com/dcreemer/dotfiles/blob/main/dot_hammerspoon/bearapp.lua)
to create daily journal notes in Bear, as well as to automate a simple backlinks
feature.

Copyright (c) 2021 D. Creemer. MIT License.

Some original code, and many bits and pieces of code adapted from:

* https://github.com/leafo/etlua
* https://github.com/cdzombak/bear-backlinks
* https://github.com/martinfinke/xcall
