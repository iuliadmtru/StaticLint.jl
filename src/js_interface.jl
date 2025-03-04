# expressions

#=
!!! Not sure if this is really equivalent to [`CSTParser.isunarycall`](https://github.com/julia-vscode/CSTParser.jl/blob/99e12c903f237394addfd3817bc9920e5afe3d61/src/interface.jl#L21C1-L21C115)
=#
js_iscall(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"call"
js_isunarycall(x::JuliaSyntax.SyntaxNode) =
    js_iscall(x) && length(x.children) == 2 && any(JuliaSyntax.is_operator, x.children)
#=
!!! Not sure if this is really equivalent to [`CSTParser.isbinarycall`](https://github.com/julia-vscode/CSTParser.jl/blob/99e12c903f237394addfd3817bc9920e5afe3d61/src/interface.jl#L23)
=#
js_isbinarycall(x::JuliaSyntax.SyntaxNode) =
    js_iscall(x) && length(x.children) == 3 && JuliaSyntax.is_operator(x.children[2])
js_isbinarysyntax(x::JuliaSyntax.SyntaxNode) =
    JuliaSyntax.is_operator(JuliaSyntax.head(x)) && length(x.children) == 2
js_iswhere(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"where"

js_iscurly(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"curly"
#=
TODO: update when JuliaSyntax has `brackets` node
=#
js_isbracketed(x::JuliaSyntax.SyntaxNode) = false  # TODO: JuliaSyntax.kind(x) === K"brackets"

js_isassignment(x::JuliaSyntax.SyntaxNode) =
    js_isbinarysyntax(x) && JuliaSyntax.kind(x) === K"="
js_isdeclaration(x::JuliaSyntax.SyntaxNode) =
    js_isbinarysyntax(x) && JuliaSyntax.kind(x) === K"::"

#=
!!! Not sure if this is really equivalent to [`CSTParser.is_getfield`](https://github.com/julia-vscode/CSTParser.jl/blob/99e12c903f237394addfd3817bc9920e5afe3d61/src/interface.jl#L52)
TODO: rename to `is_getproperty`? https://docs.julialang.org/en/v1/base/base/#Base.getproperty
=#
js_is_getfield(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"."
js_is_getfield_w_quotenode(x::JuliaSyntax.SyntaxNodex) =
    js_is_getfield(x) && JuliaSyntax.kind(x.children[2]) === K"quote" && length(x.children[2].children) > 0  # how can it have 0 children?

# literals

js_issubtypedecl(x::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(x) === K"<:"

#=
TODO: useless ||; keep only `js_iscall`?
=#
js_is_some_call(x::JuliaSyntax.SyntaxNode) = js_iscall(x) || js_isunarycall(x)
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
js_rem_decl(x::JuliaSyntax.SyntaxNode) = js_isdeclaration(x) ? x.children[1] : x
js_rem_call(x::JuliaSyntax.SyntaxNode) = js_iscall(x) ? x.children[1] : x
js_rem_wheres(x::JuliaSyntax.SyntaxNode) = js_iswhere(x) ? js_rem_wheres(x.children[1]) : x
js_rem_curly(x::JuliaSyntax.SyntaxNode) = js_iscurly(x) ? x.children[1] : x
#=
TODO: update when JuliaSyntax has `brackets` node
=#
js_rem_invis(x::JuliaSyntax.SyntaxNode) = x # TODO: js_isbracketed(x) ? js_rem_invis(x.children[1]) : x

js_get_sig(x::JuliaSyntax.SyntaxNode) = x.children[1]

function js_get_name(x::JuliaSyntax.SyntaxNode)
    if js_defines_datatype(x)
        expr = js_get_sig(x)
        expr = js_rem_subtype(expr)
        expr = js_rem_wheres(expr)
        expr = js_rem_subtype(expr)
        expr = js_rem_curly(expr)
    elseif js_defines_module(x)
        return x.children[1]
    elseif js_defines_function(x) || js_defines_macro(x)
        #=
        TODO: example where all steps are necessary?
        =#
        expr = js_get_sig(x)
        expr = js_rem_wheres(expr)
        expr = js_rem_decl(expr)
        expr = js_rem_call(expr)
        expr = js_rem_curly(expr)
        expr = js_rem_invis(expr)
        # if isbinarysyntax(expr) && is_dot(expr.head)
        if js_is_getfield_w_quotenode(expr)
            expr = expr.children[2].children[1]
        end
        return expr
    elseif js_is_getfield_w_quotenode(expr)
        expr = expr.children[2].children[1]
    elseif js_isbinarycall(x)
        #=
        What does this do?!
        =#
        expr = x.children[2]  # The operator?
        if js_isunarycall(expr)  # If `expr` is now the operator in the binary call, how can it be a unary call? I am missing something.
            return js_get_name(expr.children[1])
        end
        expr = js_rem_wheres(expr)
        expr = js_rem_decl(expr)
        expr = js_rem_call(expr)
        expr = js_rem_curly(expr)
        expr = js_rem_invis(expr)
        return js_get_name(expr)
    end
end
