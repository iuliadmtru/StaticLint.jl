using StaticLint, JuliaSyntax
using Test
using StaticLint: LintOptions, check_all

const IMPLEMENTED = LintOptions(
    false,  # call
    false,  # iter
    true,   # nothingcomp
    true,   # constif
    true,   # lazy
    false,  # datadecl
    false,  # typeparam
    false,  # modname
    false,  # pirates
    false   # useoffuncargs
)

function open_and_parse(filename)::JuliaSyntax.SyntaxNode
    tree = open(filename, "r") do io
        JuliaSyntax.parse!(JuliaSyntax.SyntaxNode, io)
    end

    return tree
end

_check(filename::AbstractString; opts::LintOptions=IMPLEMENTED) = _check(open_and_parse(filename), opts)

function _check(x::JuliaSyntax.SyntaxNode; opts::LintOptions=IMPLEMENTED)
    check_all(x, opts)

    opts.nothingcomp && _check_nothing_equality(x)
end

function _check(x::JuliaSyntax.SyntaxNode, opts::Symbol...)
    # TODO: better than this.......

    call = false
    iter = false
    nothingcomp = false
    constif = false
    lazy = false
    datadecl = false
    typeparam = false
    modname = false
    pirates = false
    useoffuncargs = false

    for opt in opts
        if opt === :call call = true end
        if opt === :iter iter = true end
        if opt === :nothingcomp nothingcomp = true end
        if opt === :constif constif = true end
        if opt === :lazy lazy = true end
        if opt === :datadecl datadecl = true end
        if opt === :typeparam typeparam = true end
        if opt === :modname modname = true end
        if opt === :pirates pirates = true end
        if opt === :useoffuncargs useoffuncargs = true end
    end

    lint_opts = LintOptions(
        call,
        iter,
        nothingcomp,
        constif,
        lazy,
        datadecl,
        typeparam,
        modname,
        pirates,
        useoffuncargs
    )
    _check(x; opts=lint_opts)
end


function _check_nothing_equality(x::JuliaSyntax.SyntaxNode)
    val = isa(x.data.val, AbstractArray) ? x.data.val[1] : x.data.val

    @info val

    return val === StaticLint.NothingEquality || val === StaticLint.NothingNotEq
end


@testset "Nothing equality" begin
    expr = "a == nothing"
    @test _check(JuliaSyntax.parsestmt(JuliaSyntax.SyntaxNode, expr), :nothingcomp)
end
