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
int g_is_fake_outdent_symbol = 0;

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

 /*%option debug*/
%%
    int indent_caller = normal;

 /* Everything runs in the <normal> mode and enters the <indent> mode
    when a newline symbol is encountered.
    There is no newline symbol before the first line, so we need to go
    into the <indent> mode by hand there.
 */
<initial>.  { set_yycolumn(yycolumn-1); indent_caller = normal; yyless(0); BEGIN(indent); }
<initial>\n { set_yycolumn(0); indent_caller = normal; yyless(0); BEGIN(indent); }

 /* The following are the rules that keep track of indentation. */
<indent>" "     { g_current_line_indent++; }
<indent>\t      { g_current_line_indent = (g_current_line_indent + TAB_WIDTH) & ~(TAB_WIDTH-1); }
<indent>\n      { set_yycolumn(0); g_current_line_indent = 0; /* ignoring blank line */ }
<indent><<EOF>> {
                    // When encountering the end of file, we want to emit an
                    // outdent for all indents currently left.
                    if(g_indent_levels.top() != 0) {
                        g_indent_levels.pop();

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
                    if(!g_is_fake_outdent_symbol) {
                        unput(*yytext);
                    }
                    g_is_fake_outdent_symbol = 0;
                    set_yycolumn(yycolumn-1);

                    // Indentation level has increased. It can only ever
                    // increase by one level at a time. Remember how many
                    // spaces this level has and emit an indentation token.
                    if(g_current_line_indent > g_indent_levels.top()) {
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

                        if(g_current_line_indent != g_indent_levels.top()) {
                            // Unput the rest of the current line, including the newline.
                            // We want to keep it untouched.
                            for(size_t i = 0 ; i < g_current_line_indent ; ++i) {
                                unput(' ');
                            }
                            unput('\n');
                            // Now, insert a fake character indented just so
                            // that we get a correct outdent the next time.
                            unput('.');
                            // Though we need to remember that it's a fake one
                            // so we can ignore the symbol.
                            g_is_fake_outdent_symbol = 1;
                            for(size_t i = 0 ; i < g_indent_levels.top() ; ++i) {
                                unput(' ');
                            }
                            unput('\n');
                        } else {
                            BEGIN(indent_caller);
                        }

                        return TOK_OUTDENT;
                    } else {
                        // No change in indentation, not much to do here...
                        BEGIN(indent_caller);
                    }
                }

 /* Whenever we encounter a newline, we need to adapt the column number and go
    into indentation mode to figure out the new line's indentation.
  */
<normal>\n {
    set_yycolumn(0);
    g_current_line_indent = 0;
    indent_caller = YY_START;
    BEGIN(indent);
}

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

<normal>"Equivalence: " { return TOK_EQUIVALENCE; }
 /* Separator of two equivalences in the TOK_EQUIVALENCE case. */
<normal>", " { return TOK_COMMASPACE; }

 /* Here we need to keep track of the indentation level of the following code,
    since we'll often times have to fake it. Thank you, labelled lines. */
<normal>"code:" { g_current_codeblock_indent = g_indent_levels.top(); return TOK_CODE; }

<normal>CONTAINS { return TOK_CONTAINS; }

 /* The labelled ones are _really_ ugly.

    The label always begins at the first column and takes up 6 characters.
    (left-aligned, filled with whitespace on the right; 7 including the \n)
    What follows these 6 characters is a sometimes correctly and sometimes
    incorrectly indented line. This line is always missing the 'baseline
    indentation', i.e. the indentation of the current code block.

    Examples:

        GOTO 270
    10    CONTINUE
        DO ...

    Here, clearly, the CONTINUE is on the same line as the GOTO and DO, the
    apparent indentation comes only from the 6-chars wide label.

        IF foo
          ASSIGN bar
    99    CONTINUE
          CLOSE
        ENDIF

    Here, the CONTINUE clearly is on the same line as the ASSIGN and CLOSE,
    suggesting we cannot trust the spaces behind the label.

        IF foo
    120   IF bar
            ASSIGN baz

    Here, from the scanner's POV, the situation is exactly the same as in the
    first example. But clearly the labelled IF is at the correct indentation...
    what do?

        DO 210 foo
          ASSIGN bar
    210     NOP
        ASSIGN baz

    Here, NOP could either be inside the DO (same level as ASSIGN bar) or the
    end of the DO (same level as ASSIGN baz).

    The easy-and-correct-99%-of-the-cases way out is to just eat up the label
    and ALL of the following spaces, skipping indentation detection, such that
    the statement is always at the same level as the previous statement.
    That's what this does. The edge-cases will be parsed in the wrong
    indentation-level.
  */
<normal>\n[0-9]+" "+ {
    // Keep track of the label we need to attach to the next identifier.
    // TODO: Make use of this :)
    g_previous_label = Json::Value(Json::Int64(strtol(yytext, 0, 10)));
    set_yycolumn(yyleng-1);
}

 /* Any identifier */
<normal>[a-zA-Z][a-zA-Z_0-9]*   { yylval = mkval(yytext, yyleng, 0); return TOK_IDENTIFIER; }
<normal>'[a-zA-Z][a-zA-Z_0-9]*' { yylval = mkval(yytext, yyleng-1, 1); return TOK_QUOTED_IDENTIFIER; }
 /* Interestingly, RETURN is always followed by a whitespace. */
<normal>"RETURN"" "? { yylval = Json::Value("RETURN"); return TOK_IDENTIFIER; }
<normal>[a-zA-Z][a-zA-Z_0-9():]* { yylval = mkval(yytext, yyleng, 0); return TOK_FULL_IDENTIFIER; }

<normal>" "+    { return TOK_WS; }

 /* Unfortunately, gcc prints the ELSE command on the same line as the */
 /* statement preceding it. We need to split it to its own line. */
<normal>.+("ELSE"|"ELSE IF".*)$ {
    // This one is everything in front of the last ELSE, including spaces.
    std::string before_else = std::string(yytext, std::string(yytext).rfind("ELSE"));
    // Now we want to push spaces over to belong to the ELSE part.
    // Nice thing is string::npos + 1 == 0 :)
    const size_t else_spaces = before_else.find_last_not_of(' ') + 1;
    before_else = before_else.substr(0, else_spaces);
    // So this one is the ELSE part including the spaces right in front of ELSE.
    std::string else_ = std::string(yytext + else_spaces, yyleng - else_spaces);

    // Of course, RETURN aka "RETURN " makes our life harder, see its rule.
    if(before_else.find("RETURN") != std::string::npos) {
        before_else += " ";
        else_ = " " + else_;
    }

    // Put the ELSE (or ELSE IF ...) statement on its own line
    for(std::string::const_reverse_iterator i = else_.rbegin() ; i != else_.rend() ; ++i) {
        unput(*i);
    }
    unput('\n');
    for(std::string::const_reverse_iterator i = before_else.rbegin() ; i != before_else.rend() ; ++i) {
        unput(*i);
    }
}

 /* Sometimes appears at the end of a toplevel namespace. */
<normal>"------------------------------------------" { return TOK_DASHES; }

 /* A space (not included) and then everything up to (and not including) the end of the line. */
<normal>" ".*   { yylval = mkval(yytext, yyleng, 1); return TOK_REST; }

(.|\n)  { std::cerr << g_current_filename << ":" << yylineno << ":" << yycolumn << ": Unexpected character: " << yytext << std::endl; exit(1); }

%%
