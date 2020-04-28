mutable struct Scope
    parent::Union{Scope,Nothing}
    expr::EXPR
    names::Dict{String,Binding}
    modules::Union{Nothing,Dict{Symbol,Any}}
    ismodule::Bool
end
Scope(expr) = Scope(nothing, expr, Dict{Symbol,Binding}(), nothing, typof(expr) === CSTParser.ModuleH || typof(expr) === CSTParser.BareModule)
function Base.show(io::IO, s::Scope)
    printstyled(io, typof(s.expr))
    printstyled(io, " ", join(keys(s.names), ","), color = :yellow)
    s.modules isa Dict && printstyled(io, " ", join(keys(s.modules), ","), color = :blue)
    println(io)
end

scopehasmodule(s::Scope, mname::Symbol) = s.modules !== nothing && haskey(s.modules, mname)
function addmoduletoscope!(s::Scope, m, mname::Symbol)
    if s.modules === nothing
        s.modules = Dict{Symbol,Any}()
    end
    s.modules[m.name.name] = m
end
addmoduletoscope!(s::Scope, m::SymbolServer.ModuleStore) = addmoduletoscope!(s, m, m.name.name)
addmoduletoscope!(s::Scope, m::EXPR) = addmoduletoscope!(s, scopeof(m), Symbol(valof(CSTParser.get_name(m))))
getscopemodule(s::Scope, m::Symbol) = s.modules[m]

scopehasbinding(s::Scope, n::String) = haskey(s.names, n)


function introduces_scope(x::EXPR, state)
    if typof(x) === CSTParser.BinaryOpCall
        if kindof(x[2]) === CSTParser.Tokens.EQ && CSTParser.is_func_call(x[1])
            return true
        elseif kindof(x[2]) === CSTParser.Tokens.EQ && typof(x[1]) === CSTParser.Curly
            return true
        elseif kindof(x[2]) === CSTParser.Tokens.ANON_FUNC
            return true
        else
            return false
        end
    elseif typof(x) === CSTParser.WhereOpCall
        # unless in func def signature
        return !_in_func_def(x)
    elseif typof(x) === CSTParser.TupleH && length(x) > 2 && typof(x[1]) === CSTParser.PUNCTUATION && is_assignment(x[2])
        return true
    elseif typof(x) === CSTParser.FunctionDef ||
            typof(x) === CSTParser.Macro ||
            typof(x) === CSTParser.For ||
            typof(x) === CSTParser.While ||
            typof(x) === CSTParser.Let ||
            typof(x) === CSTParser.Generator || # and Flatten? 
            typof(x) === CSTParser.Try ||
            typof(x) === CSTParser.Do ||
            typof(x) === CSTParser.ModuleH ||
            typof(x) === CSTParser.BareModule ||
            typof(x) === CSTParser.Abstract ||
            typof(x) === CSTParser.Primitive ||
            typof(x) === CSTParser.Mutable ||
            typof(x) === CSTParser.Struct
        return true
    end
    return false
end


hasscope(x::EXPR) = hasmeta(x) && hasscope(x.meta)
scopeof(x) = nothing
scopeof(x::EXPR) = scopeof(x.meta)
CSTParser.parentof(s::Scope) = s.parent

function setscope!(x::EXPR, s)
    if !hasmeta(x)
        x.meta = Meta()
    end
    x.meta.scope = s
end

function scopes(x::EXPR, state)
    clear_scope(x)
    if scopeof(x) === nothing && introduces_scope(x, state)
        setscope!(x, Scope(x))
    end
    s0 = state.scope
    if typof(x) === FileH
        setscope!(x, state.scope)
    elseif scopeof(x) isa Scope
        if CSTParser.defines_function(x) || CSTParser.defines_macro(x)
            state.delayed = true # Allow delayed resolution
        end
        scopeof(x) != s0 && setparent!(scopeof(x), s0)
        state.scope = scopeof(x)
        if typof(x) === ModuleH # Add default modules to a new module
            state.scope.modules = Dict{Symbol,Any}()
            state.scope.modules[:Base] = getsymbolserver(state.server)[:Base]
            state.scope.modules[:Core] = getsymbolserver(state.server)[:Core]
        elseif typof(x) === BareModule
            state.scope.modules = Dict{String,Any}()
            state.scope.modules[:Core] = getsymbolserver(state.server)[:Core]
        end
        if (typof(x) === CSTParser.ModuleH || typof(x) === CSTParser.BareModule) && bindingof(x) !== nothing # Add reference to out of scope binding (i.e. itself)
            # state.scope.names[bindingof(x).name] = bindingof(x)
            add_binding(x, state)
        elseif typof(x) === CSTParser.Flatten && typof(x[1]) === CSTParser.Generator && length(x[1]) > 0 && typof(x[1][1]) === CSTParser.Generator
            setscope!(x[1][1], nothing)
        end
    end
    return s0
end