/*
Copyright (C) 2013 Lucas Beyer (http://lucasb.eyer.be)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to
deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.
*/

%{
#include <cstdio>
#include <iostream>
using namespace std;

#include "json/json.h"

#include "utils.hpp"

// stuff from flex that bison needs to know about:
extern "C" int yylex();
extern "C" int yyparse();
extern "C" FILE *yyin;

void yyerror(const char *s);

#define YYSTYPE Json::Value

Json::Value g_file;

/* Makes a new JSON object which contains the line and column ranges. */
Json::Value mkobj(struct YYLTYPE const * const yylp1 = 0, struct YYLTYPE const * const yylp2 = 0);
%}

%token TOK_INDENT
%token TOK_OUTDENT

%token TOK_WS
%token TOK_REST

%token TOK_IDENTIFIER TOK_QUOTED_IDENTIFIER TOK_FULL_IDENTIFIER
%token TOK_CONTAINS

%token TOK_NS TOK_PROCNAME TOK_DASHES

%token TOK_SYMTREE TOK_TYPESPEC TOK_ATTRS TOK_ARGLIST TOK_ARRSPEC TOK_RESULT TOK_VALUE TOK_GENIFACE
%token TOK_COMPONENTS TOK_HASH TOK_PROCBINDINGS TOK_OPBINDINGS

%token TOK_EQUIVALENCE TOK_COMMASPACE

%token TOK_CODE
%token TOK_ENDBLOCK

%debug
%locations

%%
parsetree:
    parsetree namespace_with_children TOK_DASHES { g_file.append($2); }
    |
    namespace_with_children TOK_DASHES { g_file.append($1); }
    |
    namespace_with_children { g_file.append($1); }
    ;

namespace_with_children:
    namespace children { $$ = $1; $$["children"] = $2; }
    |
    namespace { $$ = $1; }
    ;

namespace:
    namespace_head TOK_INDENT namespace_symtable code_section TOK_OUTDENT
    { $$ = merge($1, mkobj(&@1, &@4)); $$["symbols"] = $3; $$["code"] = $4; }
    |
    namespace_head TOK_INDENT namespace_symtable namespace_equivalences code_section TOK_OUTDENT
    { $$ = merge($1, mkobj(&@1, &@5)); $$["symbols"] = $3; $$["equivalences"] = $4; $$["code"] = $5; }
    ;

namespace_head:
    TOK_NS TOK_PROCNAME { $$ = mkobj(&@1, &@2); $$["type"] = "namespace"; $$["rest"] = $1; $$["name"] = $2; }
    ;

namespace_symtable:
    namespace_symtable namespace_symtable_entry
    { $$ = $1; $$.append($2); }
    |
    namespace_symtable_entry
    { $$ = mkobj(); $$.append($1); }
    ;

namespace_symtable_entry:
    TOK_SYMTREE
    { $$ = mkobj(&@1); $$["name"] = $1; }
    |
    TOK_SYMTREE
    TOK_INDENT
        namespace_symtable_entry_attrs
    TOK_OUTDENT
    { $$ = Json::Value(); $$["name"] = $1; $$ = merge(merge($$, $3), mkobj(&@1, &@3)); }
    ;

namespace_symtable_entry_attrs:
    namespace_symtable_entry_attrs namespace_symtable_entry_attr { $$ = merge(merge($1, $2), mkobj(&@1, &@2)); }
    |
    namespace_symtable_entry_attr { $$ = $1; }
    ;

namespace_symtable_entry_attr:
    TOK_TYPESPEC { $$ = mkobj(&@1); $$["type"] = $1; }
    |
    TOK_ATTRS { $$ = mkobj(&@1); $$["attrs"] = $1; }
    |
    TOK_ARGLIST { $$ = mkobj(&@1); $$["args"] = $1; }
    |
    TOK_ARRSPEC { $$ = mkobj(&@1); $$["arrayspec"] = $1; }
    |
    TOK_RESULT  { $$ = mkobj(&@1); $$["result"] = $1; }
    |
    TOK_VALUE   { $$ = mkobj(&@1); $$["value"] = $1; }
    |
    TOK_GENIFACE { $$ = mkobj(&@1); $$["interface"] = $1; }
    |
    TOK_COMPONENTS { $$ = mkobj(&@1); $$["components"] = $1; }
    |
    TOK_HASH { $$ = mkobj(&@1); $$["hash"] = $1;}
    |
    TOK_PROCBINDINGS { $$ = mkobj(&@1); $$["procbindings"] = $1; }
    |
    TOK_OPBINDINGS { $$ = mkobj(&@1); $$["opbindings"] = $1;}
    ;

namespace_equivalences:
    namespace_equivalences namespace_equivalence { $$ = $1; $$.append($2); }
    |
    namespace_equivalence { $$ = mkobj(); $$.append($1); }
    ;

namespace_equivalence:
    TOK_EQUIVALENCE TOK_FULL_IDENTIFIER TOK_COMMASPACE TOK_FULL_IDENTIFIER
    { $$ = mkobj(&@1, &@4); $$["lhs"] = $2; $$["rhs"] = $4; }
    ;

code_section:
    TOK_CODE code_lines { $$ = merge($2, mkobj(&@1, &@2)); }
    |
    TOK_CODE { $$ = mkobj(&@1); }
    ;

code_lines:
    code_lines code_line
    { $$ = $1; $$.append($2); }
    |
    code_line
    { $$ = mkobj(); $$.append($1); }
    ;

code_line:
    TOK_IDENTIFIER TOK_REST TOK_INDENT code_lines TOK_OUTDENT
    { $$ = mkobj(&@1, &@4); $$["op"] = $1; $$["args"] = $2; $$["children"] = $4; }
    |
    TOK_IDENTIFIER TOK_INDENT code_lines TOK_OUTDENT
    { $$ = mkobj(&@1, &@3); $$["op"] = $1; $$["args"] = ""; $$["children"] = $3; }
    |
    TOK_IDENTIFIER TOK_REST
    { $$ = mkobj(&@1, &@2); $$["op"] = $1; $$["args"] = $2; }
    |
    TOK_IDENTIFIER
    { $$ = mkobj(&@1); $$["op"] = $1; $$["args"] = ""; }
    ;

children:
    children child
    { $$ = $1; $$.append($2); }
    |
    child
    { $$ = mkobj(); $$.append($1); }
    ;

child:
    TOK_CONTAINS
    TOK_INDENT namespace TOK_OUTDENT
    { $$ = $3; }
    ;

%%

const char* g_current_filename = "stdin";

Json::Value mkobj(struct YYLTYPE const * const yylp1, struct YYLTYPE const * const yylp2) {
    Json::Value ret;
    if(yylp1) {
        ret["line"] = yylp1->first_line;
        ret["lastline"] = (yylp2 ? yylp2 : yylp1)->last_line;
        ret["col"] = yylp1->first_column;
        ret["lastcol"] = (yylp2 ? yylp2 : yylp1)->last_column;
    }
    return ret;
}

int main(int argc, char* argv[]) {
    yyin = stdin;
    yydebug = 1;

    if(argc == 2) {
        yyin = fopen(argv[1], "r");
        g_current_filename = argv[1];
        if(!yyin) {
            perror(argv[1]);
            return 1;
        }
    }

    // parse through the input until there is no more:
    do {
        yyparse();
    } while (!feof(yyin));

    // Show us the JSON!
    std::cout << Json::StyledWriter().write(g_file);
}

void yyerror(const char *s) {
    cerr << g_current_filename << ":" << yylloc.first_line << ":" << yylloc.first_column << "-" << yylloc.last_column << ": Parse error: " << s << endl;
    // Might as well halt now.
    exit(-1);
}

