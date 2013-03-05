gfpt2json
=========

Transform the output of `gfortran -fdump-parse-tree` to json, which is more handy to work with.

(TODO: README is in the works)

Installation
============
TODO: describe compile&install through CMake.

Usage
=====

First, run gfortran the same way you usually do to compile your program, but
add the `-fdump-parse-tree` flag and redirect the standard output (which is the
parsetree) to a file. For example:

```
$ gfortran -fdump-parse-tree -c myfile.f > myfile.pt
```

Now, feed that parsetree file to `gfpt2json` and redirect its output to
whatever file you want to store the json in:

```
$ gfpt2json < myfile.pt > myfile.json
```

Now, have fun processing that JSON!

JSON format
===========
TODO

Examples
========
TODO

License: MIT
============

Copyright (C) 2013 Lucas Beyer

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Credits
=======
This program makes use of [JsonCpp](http://jsoncpp.sourceforge.net/) which is
released under MIT license by Baptiste Lepilleur.
