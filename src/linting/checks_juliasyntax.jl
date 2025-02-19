@enum(
    LintCodes,

    MissingRef,
    IncorrectCallArgs,
    IncorrectIterSpec,
    NothingEquality,
    NothingNotEq,
    ConstIfCondition,
    EqInIfConditional,
    PointlessOR,
    PointlessAND,
    UnusedBinding,
    InvalidTypeDeclaration,
    UnusedTypeParameter,
    IncludeLoop,
    MissingFile,
    InvalidModuleName,
    TypePiracy,
    UnusedFunctionArgument,
    CannotDeclareConst,
    InvalidRedefofConst,
    NotEqDef,
    KwDefaultMismatch,
    InappropriateUseOfLiteral,
    ShouldBeInALoop,
    TypeDeclOnGlobalVariable,
    UnsupportedConstLocalVariable,
    UnassignedKeywordArgument,
    CannotDefineFuncAlreadyHasValue,
    DuplicateFuncArgName,
    IncludePathContainsNULL,
    IndexFromLength,
    FileTooBig,
    FileNotAvailable,
)

const LintCodeDescriptions = Dict{LintCodes,String}(
    IncorrectCallArgs => "Possible method call error.",
    IncorrectIterSpec => "A loop iterator has been used that will likely error.",
    NothingEquality => "Compare against `nothing` using `isnothing` or `===`",
    NothingNotEq => "Compare against `nothing` using `!isnothing` or `!==`",
    ConstIfCondition => "A boolean literal has been used as the conditional of an if statement - it will either always or never run.",
    EqInIfConditional => "Unbracketed assignment in if conditional statements is not allowed, did you mean to use ==?",
    PointlessOR => "The first argument of a `||` call is a boolean literal.",
    PointlessAND => "The first argument of a `&&` call is a boolean literal.",
    UnusedBinding => "Variable has been assigned but not used.",
    InvalidTypeDeclaration => "A non-DataType has been used in a type declaration statement.",
    UnusedTypeParameter => "A DataType parameter has been specified but not used.",
    IncludeLoop => "Loop detected, this file has already been included.",
    MissingFile => "The included file can not be found.",
    InvalidModuleName => "Module name matches that of its parent.",
    TypePiracy => "An imported function has been extended without using module defined typed arguments.",
    UnusedFunctionArgument => "An argument is included in a function signature but not used within its body.",
    CannotDeclareConst => "Cannot declare constant; it already has a value.",
    InvalidRedefofConst => "Invalid redefinition of constant.",
    NotEqDef => "`!=` is defined as `const != = !(==)` and should not be overloaded. Overload `==` instead.",
    KwDefaultMismatch => "The default value provided does not match the specified argument type.",
    InappropriateUseOfLiteral => "You really shouldn't be using a literal value here.",
    ShouldBeInALoop => "`break` or `continue` used outside loop.",
    TypeDeclOnGlobalVariable => "Type declarations on global variables are not yet supported.",
    UnsupportedConstLocalVariable => "Unsupported `const` declaration on local variable.",
    UnassignedKeywordArgument => "Keyword argument not assigned.",
    CannotDefineFuncAlreadyHasValue => "Cannot define function ; it already has a value.",
    DuplicateFuncArgName => "Function argument name not unique.",
    IncludePathContainsNULL => "Cannot include file, path contains NULL characters.",
    IndexFromLength => "Indexing with indices obtained from `length`, `size` etc is discouraged. Use `eachindex` or `axes` instead.",
    FileTooBig => "File too big, not following include.",
    FileNotAvailable => "File not available."
)


include("checks_utils.jl")

const default_options = (true, true, true, true, true, true, true, true, true, true)

struct LintOptions
    call::Bool
    iter::Bool
    nothingcomp::Bool
    constif::Bool
    lazy::Bool
    datadecl::Bool
    typeparam::Bool
    modname::Bool
    pirates::Bool
    useoffuncargs::Bool
end
LintOptions() = LintOptions(default_options...)
LintOptions(::Colon) = LintOptions(fill(true, length(default_options))...)

LintOptions(options::Vararg{Union{Bool,Nothing},length(default_options)}) =
    LintOptions(something.(options, default_options)...)

function check_all(x::JuliaSyntax.SyntaxNode, opts::LintOptions)
    # Do checks
    opts.nothingcomp && check_nothing_equality(x)
    opts.constif && check_if_conds(x)
    opts.lazy && check_lazy(x)
    check_break_continue(x)
    check_const(x)
    # opts.call && check_call(x, env)
    # opts.iter && check_loop_iter(x, env)
    # opts.datadecl && check_datatype_decl(x, env)
    # opts.typeparam && check_typeparams(x)
    # opts.modname && check_modulename(x)
    # opts.pirates && check_for_pirates(x)
    # opts.useoffuncargs && check_farg_unused(x)
    # check_kw_default(x, env)
    # check_use_of_literal(x)

    propagate_check(x, check_all, opts)
end


function check_nothing_equality(x::JuliaSyntax.SyntaxNode)
    if is_binary_call(x)
        if JuliaSyntax.head(x.children[2]).kind === K"==" && (
            x.children[1].data.val === :nothing ||
            x.children[3].data.val === :nothing
            )
            set_error!(x, NothingEquality)
        elseif JuliaSyntax.head(x.children[2]).kind === K"!=" && (
            x.children[1].data.val === :nothing ||
            x.children[3].data.val === :nothing
            )
            set_error!(x, NothingNotEq)
        end
    end
end

function check_if_conds(x::JuliaSyntax.SyntaxNode)
    if JuliaSyntax.head(x).kind === K"if" || JuliaSyntax.head(x).kind === K"elseif"
        cond = x.children[1]
        if head(cond).kind === K"true" || head(cond).kind === K"false"
            set_error!(cond, ConstIfCondition)  # should this be set in the condition?
        # elseif isassignment(cond)
        #     set_error!(cond, EqInIfConditional)  # is this intended?
        end
    end
end

function check_lazy(x::JuliaSyntax.SyntaxNode)
    if is_binary_syntax(x)
        if JuliaSyntax.head(x).kind === K"||"
            if is_bool_literal(x.children[1])
                set_error!(x, PointlessOR)
            end
        elseif JuliaSyntax.head(x).kind === K"&&"
            if is_bool_literal(x.children[1]) || is_bool_literal(x.children[2])
                set_error!(x, PointlessAND)
            end
        end
    end
end

function check_break_continue(x::JuliaSyntax.SyntaxNode)
    if JuliaSyntax.is_keyword(x) &&
       (JuliaSyntax.head(x).kind === K"continue" || JuliaSyntax.head(x).kind === K"break") &&
       !is_in_fexpr(x, x -> JuliaSyntax.head(x).kind in (K"for", K"while"))
        set_error!(x, ShouldBeInALoop)
    end
end

function check_const(x::JuliaSyntax.SyntaxNode)
    if JuliaSyntax.head(x).kind === K"const"
        if VERSION < v"1.8.0-DEV.1500" && is_assignment(x.args[1]) && is_declaration(x.children[1].children[1])
            set_error!(x, TypeDeclOnGlobalVariable)
        elseif JuliaSyntax.head(x.children[1]).kind === K"local"
            set_error!(x, UnsupportedConstLocalVariable)
        end
    end
end

# function check_typeparams(x::JuliaSyntax.SyntaxNode)
#     # if iswhere(x)  -- why?
#     if JuliaSyntax.head(x.children[1]).kind === K"where"

#         for i in 2:length(x.args)
#             a = x.args[i]
#             if hasbinding(a) && (bindingof(a).refs === nothing || length(bindingof(a).refs) < 2)
#                 seterror!(a, UnusedTypeParameter)
#             end
#         end
#     end
# end

# function check_modulename(x::JuliaSyntax.SyntaxNode)
#     # !! Needs scope information => JuliaLowering

#     # if defines_module(x) &&  # x is a module
#     #     scopeof(x) isa Scope && parentof(scopeof(x)) isa Scope && # it has a scope and a parent scope
#     #     CSTParser.defines_module(parentof(scopeof(x)).expr) && # the parent scope is a module
#     #     valof(CSTParser.get_name(x)) == valof(CSTParser.get_name(parentof(scopeof(x)).expr)) # their names match
#     #     seterror!(CSTParser.get_name(x), InvalidModuleName)
#     # end
# end
