using StaticLint, JuliaSyntax
using Test
using StaticLint: LintOptions, check_all, propagate_check

#####################################################################
##                              UTILS                              ##
#####################################################################

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

const _IMPLEMENTED = [
    :nothingcomp,
    :constif,
    :lazy
]

function open_and_parse(filename)::JuliaSyntax.SyntaxNode
    tree = open(filename, "r") do io
        JuliaSyntax.parse!(JuliaSyntax.SyntaxNode, io)
    end

    return tree[1]
end


#####################################################################
##                         CHECK FUNCTIONS                         ##
#####################################################################

function _check(x::JuliaSyntax.SyntaxNode, opts::LintOptions; individual_checks=true, kwargs...)
    check_all(x, opts)

    if !individual_checks
        return nothing
    end

    pass = true

    opts.nothingcomp && (_check_nothing_comparison(x; kwargs...) || (pass = false))
    opts.constif && (_check_const_if_cond(x; kwargs...) || (pass = false))

    return pass
end
function _check(x::JuliaSyntax.SyntaxNode, opts::AbstractVector{Symbol}; kwargs...)
    lint_opts = LintOptions(
        :call in opts,
        :iter in opts,
        :nothingcomp in opts,
        :constif in opts,
        :lazy in opts,
        :datadecl in opts,
        :typeparam in opts,
        :modname in opts,
        :pirates in opts,
        :useoffuncargs in opts
    )
    _check(x, lint_opts; kwargs...)
end
_check(x::JuliaSyntax.SyntaxNode; opts::Symbol=:all, kwargs...) =
    opts === :all ? _check(x, _IMPLEMENTED; kwargs...) : _check(x, [opts]; kwargs...)

_check(filename::AbstractString, opts::AbstractVector{Symbol}; kwargs...) = _check(open_and_parse(filename), opts; kwargs...)
_check(filename::AbstractString; opts::Symbol=:all, kwargs...) = _check(open_and_parse(filename); opts, kwargs...)


# Individual checks

function _check_nothing_comparison(x::JuliaSyntax.SyntaxNode; annotated=true, propagate=false)
    if !annotated
        _check(x; opts=:nothingcomp, individual_checks=false)
    end

    val = x.data.val
    # TODO: extract in function?
    err = isa(val, AbstractArray) ? val[1] : val
    if propagate && isnothing(err)
        propagate_check(x, _check_nothing_comparison)
    end

    @info "Checking for `nothing` comparison" x err

    ret = err === StaticLint.NothingEquality || err === StaticLint.NothingNotEq
    if ret
        @info "Found `nothing` comparison"
    end

    return ret
end

function _check_const_if_cond(x::JuliaSyntax.SyntaxNode; annotated=true, propagate=false)
    if !annotated
        _check(x; opts=:constif, individual_checks=false)
    end

    val = x.children[1].data.val
    err = isa(val, AbstractArray) ? val[1] : val
    if propagate && isnothing(err)
        propagate_check(x, _check_const_if_cond)
    end

    @info "Checking for constant in `if` condition" x err

    return err === StaticLint.ConstIfCondition
end


#####################################################################
##                              TESTS                              ##
#####################################################################

@testset "Nothing comparison" begin
    expr = "a == nothing"
    @test _check_nothing_comparison(JuliaSyntax.parsestmt(JuliaSyntax.SyntaxNode, expr); annotated=false)

    expr = "nothing != (2 + 3)"
    @test _check_nothing_comparison(JuliaSyntax.parsestmt(JuliaSyntax.SyntaxNode, expr); annotated=false)

    expr = "nothing !== true"
    @test !_check_nothing_comparison(JuliaSyntax.parsestmt(JuliaSyntax.SyntaxNode, expr); annotated=false)
end

@testset "Const if condition" begin
    expr = "if true 1 end"
    @test _check_const_if_cond(JuliaSyntax.parsestmt(JuliaSyntax.SyntaxNode, expr); annotated=false)

    expr = "if true == true 1 end"
    @test !_check_const_if_cond(JuliaSyntax.parsestmt(JuliaSyntax.SyntaxNode, expr); annotated=false)
end
