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
#include <iostream>
#include <string>
#include <stack>
#include "json/json.h"
#include "utils.hpp"

/* == some workaround hacks. == */
/* The indentation of the current code block. Needed for labeled lines, which suck btw. */
size_t g_current_codeblock_indent = 0;
/* The label to emit along with the next non-indentation related token. */
Json::Value g_previous_label;
/* == end of workaround hacks == */

/* globals to track current indentation */
int g_current_line_indent = 0;   /* indentation of the current line */
std::stack<size_t> g_indent_levels;

/* TODO: error on tabs/spaces mix? */
static const unsigned int TAB_WIDTH = 2;

extern const char* g_current_filename;

/* Don't mangle yylex please! */
#define YY_DECL extern "C" int yylex()
#define YYSTYPE Json::Value
#include "parser.hh"

#define YY_USER_INIT { \
        g_indent_levels.push(0); \
        BEGIN(initial); \
    }

int yycolumn = 1;
void set_yycolumn(int val) {
    yycolumn = val;
    yylloc.first_column = yycolumn;
    yylloc.last_column = yycolumn + yyleng - 1;
}

#define YY_USER_ACTION { \
    yylloc.first_line = yylloc.last_line = yylineno; \
    set_yycolumn(yycolumn); \
    yycolumn += yyleng; \
}

 // Just a short-hand.
Json::Value mkval(const char* yytext, size_t yylen, size_t pre)
{
    if(yylen > pre) {
        return Json::Value(std::string(yytext+pre, yylen-pre));
    } else {
        return Json::Value();
    }
}

Json::Value mklst(const char* yytext, size_t yylen, size_t pre, char delim = ' ')
{
    return split(std::string(yytext+pre, yylen-pre));
}

size_t prev_indent_level()
{
    size_t ret = g_indent_levels.empty() ? 0 : g_indent_levels.top();
    if(g_indent_levels.size() > 1) {
        size_t tmp = g_indent_levels.top();
        g_indent_levels.pop();
        ret = g_indent_levels.top();
        g_indent_levels.push(tmp);
    }
    return ret;
}

%}

 /* This is a sub-parser (state) for indentation-sensitive scoping */
%x initial
%x indent
%s normal

 /* %option 8bit reentrant bison-bridge */
%option warn
%option nodefault
%option yylineno
%option noyywrap

%option debug
%%
    int indent_caller = normal;

 /* This helps to keep track of the column number.
  * Note that it won't work if you have a rule which includes a newline and is
  * longer than one character because in that case that rule will be favored
  * and this one here won't get called.
  * TL;DR: If you have a rule which includes \n and more, you need to reset
  *        yycolumn inside that rule!
  */
<*>\n { set_yycolumn(0); yylineno--; REJECT; }

 /* Everything runs in the <normal> mode and enters the <indent> mode
    when a newline symbol is encountered.
    There is no newline symbol before the first line, so we need to go
    into the <indent> mode by hand there.
 */
<initial>.  { set_yycolumn(yycolumn-1); indent_caller = normal; yyless(0); BEGIN(indent); }
<initial>\n { indent_caller = normal; yyless(0); BEGIN(indent); }

 /* The following are the rules that keep track of indentation. */
<indent>" "     { g_current_line_indent++; }
<indent>\t      { g_current_line_indent = (g_current_line_indent + TAB_WIDTH) & ~(TAB_WIDTH-1); }
<indent>\n      { g_current_line_indent = 0; /* ignoring blank line */ }
<indent><<EOF>> {
                    // When encountering the end of file, we want to emit an
                    // outdent for all indents currently left.
                    if(g_indent_levels.top() != 0) {
                        g_indent_levels.pop();
                        std::cerr << "=== OUTDENT (currline: " << g_current_line_indent << ", level: " << g_indent_levels.top() << ")" << std::endl;

                        // See the same code below (<indent>.) for a rationale.
                        if(g_current_line_indent != g_indent_levels.top()) {
                            unput('\n');
                            for(size_t i = 0 ; i < g_indent_levels.top() ; ++i) {
                                unput(' ');
                            }
                        } else {
                            BEGIN(indent_caller);
                        }

                        return TOK_OUTDENT;
                    } else {
                        yyterminate();
                    }
                }

<indent>.       {
                    unput(*yytext);
                    set_yycolumn(yycolumn-1);

                    // Indentation level has increased. It can only ever
                    // increase by one level at a time. Remember how many
                    // spaces this level has and emit an indentation token.
                    if(g_current_line_indent > g_indent_levels.top()) {
                        std::cerr << "=== INDENT (currline: " << g_current_line_indent << ", level: " << g_indent_levels.top() << ")" << std::endl;
                        g_indent_levels.push(g_current_line_indent);
                        BEGIN(indent_caller);
                        return TOK_INDENT;
                    } else if(g_current_line_indent < g_indent_levels.top()) {
                        // Outdenting is the most difficult, as we might need to
                        // outdent multiple times at once, but flex doesn't allow
                        // emitting multiple tokens at once! So we fake this by
                        // 'unput'ting fake lines which will give us the next
                        // outdent.
                        g_indent_levels.pop();
                        std::cerr << "=== OUTDENT (currline: " << g_current_line_indent << ", level: " << g_indent_levels.top() << ")" << std::endl;

                        if(g_current_line_indent != g_indent_levels.top()) {
                            unput('\n');
                            for(size_t i = 0 ; i < g_indent_levels.top() ; ++i) {
                                unput(' ');
                            }
                        } else {
                            BEGIN(indent_caller);
                        }

                        return TOK_OUTDENT;
                    } else {
                        // No change in indentation, not much to do here...
                        BEGIN(indent_caller);
                    }
                }

<normal>\n[0-9]*      { g_current_line_indent = 0; indent_caller = YY_START; BEGIN(indent); }

 /* The "Namespace:" part, so that it isn't matched by the "identifier" below. */
<normal>"Namespace: ".*          { yylval = mkval(yytext, yyleng, 11); return TOK_NS; }
<normal>"procedure name = ".*    { yylval = mkval(yytext, yyleng, 17); return TOK_PROCNAME; }
<normal>"type spec : ".*         { yylval = mkval(yytext, yyleng-1, 13); return TOK_TYPESPEC; }
<normal>"attributes: ".*         { yylval = mklst(yytext, yyleng-1, 13); return TOK_ATTRS; }
<normal>"Array spec:".*          { yylval = mkval(yytext, yyleng, 11); return TOK_ARRSPEC; }
<normal>"result: ".*             { yylval = mkval(yytext, yyleng,  8); return TOK_RESULT; }
<normal>"value: ".*              { yylval = mkval(yytext, yyleng,  7); return TOK_VALUE; }
<normal>"Formal arglist: ".*     { yylval = mklst(yytext, yyleng, 16); return TOK_ARGLIST; }
<normal>"components: ".*         { yylval = mkval(yytext, yyleng, 12); return TOK_COMPONENTS; }
<normal>"hash: "[0-9]+           { yylval = mkval(yytext, yyleng,  6); return TOK_HASH; }
<normal>"Procedure bindings:".*  { yylval = mkval(yytext, yyleng, 20); return TOK_PROCBINDINGS; }
<normal>"Operator bindings:".*   { yylval = mkval(yytext, yyleng, 19); return TOK_OPBINDINGS; }
<normal>"Generic interfaces: ".* { yylval = mkval(yytext, yyleng, 21); return TOK_GENIFACE; }
<normal>"symtree: '"[a-zA-Z0-9_@]*"'".* {
    size_t len = std::string(yytext).find_first_of('\'', 10);
    yylval = mkval(yytext, std::min(len, yyleng), 10);
    return TOK_SYMTREE;
}

 /* Here we need to keep track of the indentation level of the following code,
    since we'll often times have to fake it. Thank you, labelled lines. */
<normal>"code:" { g_current_codeblock_indent = g_indent_levels.top(); return TOK_CODE; }

<normal>CONTAINS { return TOK_CONTAINS; }

 /* The labelled ones are _really_ ugly.
    This rule tries to eat up the label only and put the rest back into the
    input at the correct indentation level.

    The label always begins at the first column and takes 6 characters.
    (left-aligned, filled with whitespace on the right; 7 including the \n)
    What follows these 6 characters is a sometimes correctly and sometimes
    incorrectly indented line. This line is always missing the 'baseline
    indentation', i.e. the indentation of the current code block.

    I couldn't further specify the "sometimes", so this rule tries to detect
    these cases and 'fix' them by placing the rest of the line back such that
    it will create one OUTDENT token at most.
  */
<normal>\n[0-9]+" "+.* {
    // Keep track of the label we need to attach to the next identifier.
    // TODO: Make use of this :)
    g_previous_label = Json::Value(Json::Int64(strtol(yytext, 0, 10)));

    // The amount of spaces present after the label's 6 characters.
    // This is the indentation at which the rest would be placed.
    const size_t present_spaces = std::string(yytext + 7).find_first_not_of(' ', 0);

    // Figure out the indentation one level before the current one.
    const size_t prev_indent = prev_indent_level();
    size_t where_to_put = g_current_codeblock_indent;
    if(where_to_put + present_spaces < prev_indent) {
        // If the suggested placement would produce more than one outdent token,
        // disregard the suggested placement and place it so as to generate only one.
        where_to_put = prev_indent - present_spaces;
    }
    // Put back everything but the newline and the 6 fields for the label.
    yyless(7);
    // And put the "right" amount of whitespaces to get the correct indentation.
    for(size_t i = 0 ; i < where_to_put ; ++i) {
        unput(' ');
    }
    unput('\n');
}

 /* Any identifier */
<normal>[a-zA-Z][a-zA-Z_0-9]*   { yylval = mkval(yytext, yyleng, 0); return TOK_IDENTIFIER; }
<normal>'[a-zA-Z][a-zA-Z_0-9]*' { yylval = mkval(yytext, yyleng-1, 1); return TOK_QUOTED_IDENTIFIER; }
 /* Interestingly, RETURN is always followed by a whitespace. */
<normal>"RETURN"" "? { yylval = Json::Value("RETURN"); return TOK_IDENTIFIER; }

<normal>\d+     { yylval = Json::Value(Json::Int(strtol(yytext, 0, 10))); return TOK_NUMBER; }

<normal>" "+    { return TOK_WS; }

 /* Unfortunately, gcc prints the ELSE command on the same line as the */
 /* statement preceding it. We need to split it to its own line. */
 /* TODO: sometimes this is ELSE IF FOO BAR BAZ! */
<normal>" ".*" "+"ELSE" {
    yylval = mkval(yytext, yyleng-4, 1);

    // Put the ELSE statement on its own line with the current indent.
    unput('E'); unput('S'); unput('L'); unput('E');
    for(size_t i = 0 ; i < g_current_line_indent ; ++i) { unput(' '); }
    unput('\n');

    return TOK_REST;
}

 /* Sometimes appears at the end of a toplevel namespace. */
<normal>"------------------------------------------" { return TOK_DASHES; }

 /* A space (not included) and then everything up to (and not including) the end of the line. */
<normal>" ".*   { yylval = mkval(yytext, yyleng, 1); return TOK_REST; }

(.|\n)  { std::cerr << g_current_filename << ":" << yylineno << ":" << yycolumn << ": Unexpected character: " << yytext << std::endl; exit(1); }

%%
