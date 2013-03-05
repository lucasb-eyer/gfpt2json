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
/* Don't mangle yylex please! */
#define YY_DECL extern "C" int yylex()

/* globals to track current indentation */
int g_current_line_indent = 0;   /* indentation of the current line */
int g_indent_level = 0;          /* indentation level passed to the parser */

/* globals to track current cursor position */
unsigned long g_line = 1;
unsigned long g_col = 0;

/* TODO: error on tabs/spaces? */
static const unsigned int TAB_WIDTH = 2;

#include <iostream>
#include <sstream>
#include <string>

#include "json/json.h"

#define YYSTYPE Json::Value
#include "parser.hh"

#include "utils.hpp"

// Just a short-hand.
Json::Value mkval(const char* yytext, size_t yylen, size_t pre)
{
    return Json::Value(std::string(yytext+pre, yylen-pre));
}

Json::Value mklst(const char* yytext, size_t yylen, size_t pre, char delim = ' ')
{
    return split(std::string(yytext+pre, yylen-pre));
}

%}

 /* This is a sub-parser (state) for indentation-sensitive scoping */
%x indent
%s normal

 /* %option 8bit reentrant bison-bridge */
%option warn
%option nodefault
%option yylineno
%option noyywrap

%option debug
%%
    BEGIN(normal);
    int indent_caller;

<*>.  { g_col++; REJECT; }
<*>\n { g_col = 0; g_line++; REJECT; }
<*><<EOF>>      {
                    if(g_current_line_indent < g_indent_level) {
                        g_indent_level = g_current_line_indent;
                        std::cerr << "=== OUTDENT (currline: " << g_current_line_indent << ", level: " << g_indent_level << ")" << std::endl;
                        return TOK_OUTDENT;
                    }
                    return 0;
                }

<indent>" "     { g_current_line_indent++; }
<indent>\t      { g_current_line_indent = (g_current_line_indent + TAB_WIDTH) & ~(TAB_WIDTH-1); }
<indent>\n      { g_current_line_indent = 0; /* ignoring blank line */ }
<indent>.       {
                    std::cerr << "=== currline: " << g_current_line_indent << ", level: " << g_indent_level << std::endl;
                    /* g_col--; */
                    unput(*yytext);
                    if(g_current_line_indent > g_indent_level) {
                        //g_indent_level++;
                        g_indent_level = g_current_line_indent;
                        std::cerr << "=== INDENT (currline: " << g_current_line_indent << ", level: " << g_indent_level << ")" << std::endl;
                        return TOK_INDENT;
                    } else if(g_current_line_indent < g_indent_level) {
                        //g_indent_level--;
                        g_indent_level = g_current_line_indent;
                        std::cerr << "=== OUTDENT (currline: " << g_current_line_indent << ", level: " << g_indent_level << ")" << std::endl;
                        return TOK_OUTDENT;
                    } else {
                        std::cerr << "=== LEAVING (currline: " << g_current_line_indent << ", level: " << g_indent_level << ")" << std::endl;
                        BEGIN(indent_caller);
                    }
                }

<normal>\n[0-9]*      { g_current_line_indent = 0; indent_caller = normal; BEGIN(indent); }

 /* A type and its size of the form (REAL 8) */
<normal>\([A-Z]+\ [0-9]+(\ [0-9]*)?\)  { yylval = mkval(yytext, yyleng-1, 1); return TOK_TYPE; }

 /* The "Namespace:" part, so that it isn't matched by the "identifier" below. */
<normal>"Namespace: ".*                { yylval = mkval(yytext, yyleng, 11); return TOK_NS; }
<normal>"procedure name = ".*          { yylval = mkval(yytext, yyleng, 17); return TOK_PROCNAME; }
<normal>"attributes: ".*               { yylval = mklst(yytext, yyleng-1, 13); return TOK_ATTRS; }
<normal>"Array spec:".*                { yylval = mkval(yytext, yyleng, 11); return TOK_ARRSPEC; }
<normal>"result: ".*                   { yylval = mkval(yytext, yyleng,  8); return TOK_RESULT; }
<normal>"value: ".*                    { yylval = mkval(yytext, yyleng,  7); return TOK_VALUE; }
<normal>"Formal arglist: ".*           { yylval = mklst(yytext, yyleng, 16); return TOK_ARGLIST; }
<normal>"symtree: '"[a-zA-Z0-9_]*"'".* {
    size_t len = std::string(yytext).find_first_of('\'', 10);
    yylval = mkval(yytext, std::min(len, yyleng), 10);
    return TOK_SYMTREE;
}
<normal>"type spec : "      { return TOK_TYPESPEC; }

<normal>"code:" { return TOK_CODE; }

<normal>CONTAINS { return TOK_CONTAINS; }

 /* Tokens for finding labelled statements. They suck! */
<normal>\n[0-9]+" "+"CONTINUE"  { yylval = mkval(yytext+1, yyleng-1, 0); return TOK_LABELLED; }
 /* This one is ugly, we need its indentation! (It's the end block of a DO.) */
 /* So what we do is to "remove" the number and scan again. */
<normal>\n[0-9]+" "+"NOP" {
    size_t lennumber = std::string(yytext).find_first_of(' ', 0);
    yyless(lennumber);
    // Unfortunately, GCC seems to overwrite the indentation spaces
    // if the number is longer than 2 digits and thus in that case,
    // there would be missing spaces for the indentation. Add them!
    for(size_t i = 3 ; i < lennumber ; ++i) {
        unput(' ');
    }
    unput('\n');
}

 /* End of block tokens (if, do, and friends). */
<normal>"ENDIF"       { return TOK_ENDBLOCK; }
<normal>"END DO"      { return TOK_ENDBLOCK; }
<normal>"NOP"         { return TOK_ENDBLOCK; }
<normal>"NOP"" "+"ELSE" { yyless(3); unput(' '); unput(' '); unput('\n'); return TOK_ENDBLOCK; }

 /* Any identifier */
<normal>[a-zA-Z][a-zA-Z_0-9]*   { yylval = mkval(yytext, yyleng, 0); return TOK_IDENTIFIER; }
<normal>'[a-zA-Z][a-zA-Z_0-9]*' { yylval = mkval(yytext, yyleng-1, 1); return TOK_QUOTED_IDENTIFIER; }

<normal>\d+     { yylval = Json::Value(Json::Int(strtol(yytext, 0, 10))); return TOK_NUMBER; }

<normal>" "+    { return TOK_WS; }

 /* Unfortunately, gcc prints the ELSE command on the same line as the */
 /* statement preceding it. We need to split it to its own line. */
<normal>" ".*" "+"ELSE" {
    yylval = mkval(yytext, yyleng-4, 1);

    // Put the ELSE statement on its own line with the current indent.
    unput('E'); unput('S'); unput('L'); unput('E');
    for(size_t i = 0 ; i < g_current_line_indent ; ++i) { unput(' '); }
    unput('\n');

    return TOK_REST;
}

 /* A space (not included) and then everything up to (and not including) the end of the line. */
<normal>" ".*   { yylval = mkval(yytext, yyleng, 1); return TOK_REST; }

(.|\n)  { std::cerr << "filename:" << g_line << ":" << g_col << ": Unexpected character: " << yytext << std::endl; exit(1); }

%%
