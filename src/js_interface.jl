# expressions

# js_isunarycall(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"call" && 
js_isbinarysyntax(x::JuliaSyntax.SyntaxNode) =
    JuliaSyntax.is_operator(JuliaSyntax.head(x)) && length(x.children) == 2
js_iswhere(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"where"

js_isassignment(x::JuliaSyntax.SyntaxNode) =
    js_isbinarysyntax(x) && JuliaSyntax.kind(x) === K"="

# literals

js_issubtypedecl(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"<:"

# js_is_some_call(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"call" || js_isunarycall(x)
js_is_eventually_some_call(x::JuliaSyntax.SyntaxNode) =
    js_is_some_call(x) || ((js_isdeclaration(x) || js_iswhere(x)) && js_is_eventually_some_call(x.children[1]))

js_defines_function(x::JuliaSyntax.SyntaxNode) =
    JuliaSyntax.kind(x) === K"function" || (js_isassignment(x))
js_defines_datatype(x::JuliaSyntax.SyntaxNode) =
    js_defines_struct(x) || js_defines_abstract(x) || js_defines_primitive(x)
js_defines_struct(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"struct"
js_defines_abstract(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"abstract"
js_defines_primitive(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"primitive"
js_defines_module(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"module"

js_rem_subtype(x::JuliaSyntax.SyntaxNode) = js_issubtypedecl(x) ? x.children[1] : x
js_rem_wheres(x::JuliaSyntax.SyntaxNode) = js_iswhere(x) ? js_rem_wheres(x.children[1]) : x
js_rem_curly(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"curly" ? x.children[1] : x

js_get_sig(x::JuliaSyntax.SyntaxNode) = x.children[1]

function js_get_name(x::JuliaSyntax.SyntaxNode)
    if js_defines_datatype(x)
        expr = js_get_expr(x)
        expr = js_rem_subtype(expr)
        expr = js_rem_wheres(expr)
        expr = js_rem_subtype(expr)
        expr = js_rem_curly(expr)
    elseif js_defines_module(x)
        return x.children[1]
    elseif js_defines_function(x) || js_defines_macro(x)
        expr = js_get_expr(x)
        expr = js_rem_wheres(expr)
        expr = js_rem_decl(expr)
        expr = js_rem_call(expr)
        expr = js_rem_curly(expr)
        expr = js_rem_invis(expr)
        # if isbinarysyntax(expr) && is_dot(expr.head)
        if js_is_getfield_w_quotenode(expr)
            expr = expr.args[2].args[1]
        end
        return expr
    end
end
