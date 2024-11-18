using JuliaSyntax

function is_binary_call(x::JuliaSyntax.SyntaxNode)
    JuliaSyntax.head(x).kind === K"call" &&
    length(x.children) == 3 &&
    JuliaSyntax.is_operator(x.children[2])
end

function set_error!(x::JuliaSyntax.SyntaxNode, err)
    x.data = isnothing(x.val) ?
        JuliaSyntax.SyntaxData(x.data.source, x.data.raw, x.data.position, err) :
        JuliaSyntax.SyntaxData(x.data.source, x.data.raw, x.data.position, [x.val, err])
end
has_error(x::JuliaSyntax.SyntaxNode) = x.val isa LintCodes || (x.val isa AbstractVector && x.val[2] isa LintCodes)
error_of(x::JuliaSyntax.SyntaxNode) = has_error(x) ? (x.val isa AbstractVector ? x.val[2] : x.val) : nothing
