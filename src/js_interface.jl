# expressions

# !!! Not sure if this is equivalent to [`CSTParser.isunarycall`](https://github.com/julia-vscode/CSTParser.jl/blob/99e12c903f237394addfd3817bc9920e5afe3d61/src/interface.jl#L21C1-L21C115)
js_isunarycall(x::JuliaSyntax.SyntaxNode) =
    JuliaSyntax.kind(x) === K"call" && length(x.children) == 2 && any(JuliaSyntax.is_operator, x.children)
js_isbinarysyntax(x::JuliaSyntax.SyntaxNode) =
    JuliaSyntax.is_operator(JuliaSyntax.head(x)) && length(x.children) == 2
js_iswhere(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"where"

js_isassignment(x::JuliaSyntax.SyntaxNode) =
    js_isbinarysyntax(x) && JuliaSyntax.kind(x) === K"="
js_isdeclaration(x::JuliaSyntax.SyntaxNode) =
    js_isbinarysyntax(x) && JuliaSyntax.kind(x) === K"::"

# literals

js_issubtypedecl(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"<:"

js_is_some_call(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"call" || js_isunarycall(x)
js_is_eventually_some_call(x::JuliaSyntax.SyntaxNode) =
    js_is_some_call(x) || ((js_isdeclaration(x) || js_iswhere(x)) && js_is_eventually_some_call(x.children[1]))

js_defines_function(x::JuliaSyntax.SyntaxNode) =
    JuliaSyntax.kind(x) === K"function" || (js_isassignment(x) && js_is_eventually_some_call(x.children[1]))
js_defines_macro(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"macro"
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
        expr = js_get_expr(x)                   # TODO
        expr = js_rem_wheres(expr)
        expr = js_rem_decl(expr)                # TODO
        expr = js_rem_call(expr)                # TODO
        expr = js_rem_curly(expr)
        expr = js_rem_invis(expr)               # TODO
        # if isbinarysyntax(expr) && is_dot(expr.head)
        if js_is_getfield_w_quotenode(expr)     # TODO
            expr = expr.args[2].args[1]         # TODO
        end
        return expr
    end
end
