// Copyright (C) 2013 Lucas Beyer (http://lucasb.eyer.be)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.

#include "utils.hpp"

#include "json/json.h"

template<>
std::string to_s(const std::string& v)
{
    return v;
}

Json::Value split(const std::string& s, char delim, bool keepempty)
{
    Json::Value ret;

    std::stringstream ss(s);
    std::string item;
    while(std::getline(ss, item, delim)) {
        if(keepempty || !s.empty()) {
            ret.append(item);
        }
    }
    return ret;
}

Json::Value merge(Json::Value v1, const Json::Value& v2)
{
    if(v1.isArray() && v2.isArray()) {
        for(Json::Value::const_iterator i = v2.begin() ; i != v2.end() ; ++i) {
            v1[i.index()] = *i;
        }
    } else if(v1.isObject() && v2.isObject()) {
        for(Json::Value::const_iterator i = v2.begin() ; i != v2.end() ; ++i) {
            v1[i.key().asString()] = *i;
        }
    }
    return v1;
}

