mutable struct ImportBinding
    loc::Location
    si::SIndex
    val
    refs::Vector{Reference}
end
ImportBinding(loc, si, val, refs = Reference[]) = ImportBinding(loc, si, val, refs)

mutable struct Binding
    loc::Location
    si::SIndex
    val::Union{CSTParser.AbstractEXPR,Dict}
    t
    refs::Vector{Reference}
end
Binding(loc, si, val, t= nothing, refs = Reference[]) = Binding(loc, si, val, t, refs)
Base.display(b::Binding) = println(b.si," @ ",  basename(b.loc.file), ":", b.loc.offset)
Base.display(B::Array{Binding}) = for b in B display(b) end

function add_binding(name, x, state, s, t = nothing)
    # global bindinglist
    s.bindings += 1
    val = Binding(StaticLint.Location(state), SIndex(s.index, s.bindings), x, t)
    
    add_binding(name, val, state.bindings, s.index)
end

function add_binding(name, binding::Binding, bindings::Dict, index::Tuple)
    if haskey(bindings, index)
        if haskey(bindings[index], name)
            # Don't repeat bindings (occurs with for/generator loops)
            if last(bindings[index][name]).loc.offset == binding.loc.offset && last(bindings[index][name]).loc.file == binding.loc.file
                return
            end
            push!(bindings[index][name], binding)
        else
            bindings[index][name] = Binding[binding]
        end
    else
        bindings[index] = Dict(name => Binding[binding])
    end
end
    

# Gets bindings added to the current scope which an expression is in: modules, functions, macros, datatype declarations, variables and imported bindings.
function ext_binding(x, state, s)
    if CSTParser.defines_module(x)
        name = CSTParser.str_value(CSTParser.get_name(x))
        add_binding(name, x, state, s, CSTParser.ModuleH)
    elseif CSTParser.defines_function(x)
        name = CSTParser.str_value(CSTParser.get_name(x))
        add_binding(name, x, state, s, CSTParser.FunctionDef)
    elseif CSTParser.defines_macro(x)
        name = string("@", CSTParser.str_value(CSTParser.get_name(x)))
        add_binding(name, x, state, s, CSTParser.Macro)
    elseif CSTParser.defines_datatype(x)
        t = CSTParser.defines_abstract(x) ? CSTParser.Abstract :
            CSTParser.defines_primitive(x) ? CSTParser.Primitive :
            CSTParser.defines_mutable(x) ? CSTParser.Mutable :
            CSTParser.Struct             
        name = CSTParser.str_value(CSTParser.get_name(x))
        add_binding(name, x, state, s, t)
    elseif CSTParser.is_assignment(x)
        ass = x.arg1
        ass = CSTParser.rem_decl(ass)
        ass = CSTParser.rem_curly(ass)
        assign_to_tuple(ass, x.arg2, state.loc.offset, state, s)
    elseif x isa CSTParser.EXPR{CSTParser.Using} || x isa CSTParser.EXPR{CSTParser.Import} || x isa CSTParser.EXPR{CSTParser.ImportAll}
        get_imports(x, state, s)
    elseif x isa CSTParser.EXPR{CSTParser.Export}
        add_export_bindings(x, state, s)
    elseif x isa CSTParser.EXPR{CSTParser.MacroCall} && x.args[1] isa CSTParser.EXPR{CSTParser.MacroName} && length(x.args[1].args) > 1 &&  CSTParser.str_value(x.args[1].args[2]) == "enum"
        # Special case for enums.
        if length(x.args) > 3 && x.args[3] isa CSTParser.IDENTIFIER
            add_binding(CSTParser.str_value(x.args[3]), x, state, s)
        end
        for i = 4:length(x.args)
            if x.args[i] isa CSTParser.IDENTIFIER
                name = CSTParser.str_value(x.args[i])
                add_binding(name, x, state, s)
            end
        end
    elseif x isa CSTParser.WhereOpCall
        for arg in x.args
            arg isa CSTParser.PUNCTUATION && continue
            add_binding(CSTParser.str_value(CSTParser.rem_curly(CSTParser.rem_subtype(arg))), x, state, s)
        end 
    end
end

function add_export_bindings(x, state, s)
    if !haskey(state.exports, s.index)
        state.exports[s.index] = []
    end
    for i = 2:length(x.args)
        arg = x.args[i]
        !(arg isa CSTParser.IDENTIFIER) && continue
        push!(state.exports[s.index], CSTParser.str_value(arg))
    end
end

# Gets bindings that are created inside the scope generated by an expression.
function int_binding(x, state, s)
    if CSTParser.defines_module(x)
        name = CSTParser.str_value(CSTParser.get_name(x))
        add_binding(name, x, state, s, CSTParser.ModuleH)
    elseif CSTParser.defines_function(x) || CSTParser.defines_macro(x)
        get_fcall_bindings(CSTParser.get_sig(x), state, s)
    elseif CSTParser.defines_datatype(x)
        if x isa CSTParser.EXPR{CSTParser.Struct} || x isa CSTParser.EXPR{CSTParser.Mutable}
            get_struct_bindings(x, state, s)
        elseif x isa CSTParser.EXPR{CSTParser.Abstract}
            sig = CSTParser.get_sig(x)
            sig = CSTParser.rem_subtype(sig)
            sig = CSTParser.rem_where(sig)
            for arg in CSTParser.get_curly_params(sig)
                add_binding(arg, x, state, s, DataType)
            end
        end
    elseif x isa CSTParser.EXPR{CSTParser.For}
        if is_for_iter(x.args[2])
            assign_to_tuple(x.args[2].arg1, x.args[2].arg2, state.loc.offset +x.args[1].fullspan, state, s)
        else
            offset = state.loc.offset
            for i = 1:length(x.args[2].args)
                if is_for_iter(x.args[2].args[i])
                    assign_to_tuple(x.args[2].args[i].arg1, x.args[2].args[i].arg2, offset, state, s)
                end
                offset += x.args[2].args[i].fullspan
            end
        end
    elseif x isa CSTParser.EXPR{CSTParser.Do}
        for arg in CSTParser.flatten_tuple(x.args[3])
            name = CSTParser.str_value(CSTParser.get_name(arg))
            add_binding(name, x, state, s)
        end
    elseif x isa CSTParser.EXPR{CSTParser.Generator}
        if is_for_iter(x.args[3])
            offset = state.loc.offset
            for i = 3:length(x.args)
                if is_for_iter(x.args[i])
                    assign_to_tuple(x.args[i].arg1, x.args[i].arg2, offset, state, s)
                end
                offset += x.args[i].fullspan
            end
        elseif x.args[3] isa CSTParser.EXPR{CSTParser.Filter}
            offset = state.loc.offset
            for i = 1:length(x.args[3].args)
                if is_for_iter(x.args[3].args[i])
                    assign_to_tuple(x.args[3].args[i].arg1, x.args[3].args[i].arg2, offset, state, s)
                end
                offset += x.args[3].args[i].fullspan
            end
        end
    elseif CSTParser.defines_anon_function(x)
        for arg in CSTParser.flatten_tuple(x.arg1)
            name = CSTParser.str_value(CSTParser.get_name(arg))
            add_binding(name, x, state, s)
        end
    end
end

function assign_to_tuple(x::CSTParser.EXPR{CSTParser.InvisBrackets}, val, offset, state, s)
    assign_to_tuple(x.args[2], val, offset + x.args[1].fullspan, state)
    return offset + x.fullspan
end

function assign_to_tuple(x, val, offset, state, s)
    if x isa CSTParser.EXPR{CSTParser.TupleH}
        for arg in x
            if !(arg isa CSTParser.PUNCTUATION)
                offset = assign_to_tuple(arg, val, offset, state, s)
            else
                offset += arg.fullspan
            end
        end
    else
        name = CSTParser.str_value(CSTParser.rem_decl(x))
        s.bindings += 1
        b = Binding(Location(state.loc.file, offset), SIndex(s.index, s.bindings), val, nothing)
        add_binding(name, b, state.bindings, s.index)
        
        offset += x.fullspan
    end
    return offset
end


function is_for_iter(x)
    (x isa CSTParser.BinarySyntaxOpCall || x isa CSTParser.BinaryOpCall) && x.op.kind in (CSTParser.Tokens.IN, CSTParser.Tokens.ELEMENT_OF, CSTParser.Tokens.EQ)
end

function get_iter_args(x::CSTParser.BinarySyntaxOpCall, state, s)
    name = CSTParser.str_value(CSTParser.get_name(x.args[3].args[i].arg1))
    add_binding(name, x, state, s)
end

function get_fcall_args(sig, getparams = true)
    args = Pair[]
    while sig isa CSTParser.WhereOpCall
        for arg in sig.args
            arg isa CSTParser.PUNCTUATION && continue
            push!(args, CSTParser.rem_curly(CSTParser.rem_subtype(arg))=>DataType)
        end 
        sig = sig.arg1
    end
    if sig isa CSTParser.BinarySyntaxOpCall && CSTParser.is_decl(sig.op)
        sig = sig.arg1
    end
    sig isa CSTParser.IDENTIFIER && return args
    if sig isa CSTParser.EXPR{CSTParser.Call} && sig.args[1] isa CSTParser.EXPR{CSTParser.Curly}
        for i = 2:length(sig.args[1].args)
            arg = sig.args[1].args[i]
            arg isa CSTParser.PUNCTUATION && continue
            push!(args, CSTParser.rem_subtype(arg)=>DataType)
        end
    end
    !getparams && empty!(args)
    !(sig isa CSTParser.EXPR) && return args
    for i = 3:length(sig.args)-1
        arg = sig.args[i]
        arg isa CSTParser.PUNCTUATION && continue
        get_arg_type(arg, args)
    end
    return args
end
function get_fcall_bindings(sig, state, s)
    args = get_fcall_args(sig)
    for (arg, t) in args
        add_binding(CSTParser.str_value(arg), sig, state, s, t)
    end
end

function get_struct_bindings(x, state, s)
    isstruct = x isa CSTParser.EXPR{CSTParser.Struct}
    sig = CSTParser.get_sig(x)
    sig = CSTParser.rem_subtype(sig)
    sig = CSTParser.rem_where(sig)
    for arg in CSTParser.get_curly_params(sig)
        add_binding(arg, x, state, s, DataType)
    end
    for arg in x.args[isstruct ? 3 : 4]
        if !CSTParser.defines_function(arg)
            if arg isa CSTParser.BinarySyntaxOpCall && CSTParser.is_decl(arg.op)
                name = CSTParser.str_value(arg.arg1)
                t = arg.arg2
            else
                name = CSTParser.str_value(arg)
                t = nothing
            end
            add_binding(name, x, state, s, t)
        end
    end
end

function get_arg_type(arg, args)
    if arg isa CSTParser.UnarySyntaxOpCall && CSTParser.is_dddot(arg.arg2)
        arg = arg.arg1
    end
    if arg isa CSTParser.IDENTIFIER
        push!(args, arg=>nothing)
    elseif arg isa CSTParser.BinarySyntaxOpCall && CSTParser.is_decl(arg.op)
        push!(args, arg.arg1=>arg.arg2)
    elseif arg isa CSTParser.EXPR{CSTParser.Kw}
        if arg.args[1] isa CSTParser.BinarySyntaxOpCall && CSTParser.is_decl(arg.args[1].op)
            push!(args, arg.args[1].arg1=>arg.args[1].arg2)
        elseif arg.args[3] isa CSTParser.LITERAL
            push!(args, arg.args[1]=>arg.args[3].kind)
        else
            push!(args, arg.args[1]=>nothing)
        end
    end
end
function get_arg_type(arg::CSTParser.EXPR{CSTParser.Parameters}, args)
    for a in arg.args
        get_arg_type(a, args)
    end
end

function _store_search(strs, store, i = 1, bs = [])
    if haskey(store, strs[i])
        push!(bs, store[strs[i]])
        if i == length(strs)
            return bs
        else
            return _store_search(strs, store[strs[i]], i+1, bs)
        end
    else
        return nothing
    end
end

function get_imports(x, state, s)
    push!(state.imports, ImportBinding(Location(state), SIndex(s.index, s.bindings), x))
    # ensure we add (at least) enough binding slots
    s.bindings += length(x.args)
end

function cat_bindings(server, file, vars = State())
    for (ind, d) in file.state.bindings
        if !haskey(vars.bindings, ind)
            vars.bindings[ind] = Dict()
        end
        for (n, bs) in file.state.bindings[ind]
            if !haskey(vars.bindings[ind], n)
                vars.bindings[ind][n] = Binding[]
            end
            append!(vars.bindings[ind][n], file.state.bindings[ind][n])
        end
    end
    
    append!(vars.modules, file.state.modules)
    append!(vars.imports, file.state.imports)
    
    for (name,bs) in file.state.exports
        if !haskey(vars.exports, name)
            vars.exports[name] = []
        end
        append!(vars.exports[name], bs)
    end
    for (name,bs) in file.state.used_modules
        vars.used_modules[name] = bs
    end
    
    
    for incl in file.state.includes
        cat_bindings(server, getfile(server, incl.file), vars)
    end
    return vars
end



function build_bindings(server, file)
    state = cat_bindings(server, file)
    # add imports
    state.used_modules = Dict{String,Any}("Base" => Binding(Location(file.state), SIndex(file.index, file.nb), store["Base"], store["Core"]["Module"]),
    "Core" => Binding(Location(file.state), SIndex(file.index, file.nb), store["Core"], store["Core"]["Module"]))
    resolve_imports(state)
    return state
end

function find_binding(bindings, name, ind, st::Function = x->true)
    out = Binding[]
    if haskey(bindings, ind) && haskey(bindings[ind], name)
        for b in bindings[ind][name]
            if st(b)
                push!(out, b)
            end
        end
    end
    return out
end

function _get_field(par, arg, state)
    if par isa Dict
        if haskey(par, CSTParser.str_value(arg))
            par = par[CSTParser.str_value(arg)]
            return par
        else
            return
        end
    elseif par isa Tuple
        ret = StaticLint.find_binding(state.bindings, CSTParser.str_value(arg), par, b-> b.val isa CSTParser.EXPR{T} where T <: Union{CSTParser.ModuleH,CSTParser.BareModule}) 
        if isempty(ret)
            return
        else
            par = last(ret)
            return par
        end
    else
        ind = StaticLint.add_to_tuple(par.si.i, par.si.n + 1)
        ret = StaticLint.find_binding(state.bindings, CSTParser.str_value(arg), b->b.si.i == ind) 
        if isempty(ret)
            return
        else
            par = last(ret)
            return par
        end
    end
    return
end



function resolve_import(imprt, state)
    x = imprt.val
    u = x isa CSTParser.EXPR{CSTParser.Using}
    i = 2
    n = length(x.args)
    argname = ""
    predots = 0
    
    root = par = store
    bindings = []
    while i <= length(x.args)
        arg = x.args[i]
        if arg isa CSTParser.IDENTIFIER     
            par = _get_field(par,arg, state)
            argname = CSTParser.str_value(x.args[i])
            if par == nothing
                return
            end
        elseif arg isa CSTParser.PUNCTUATION && arg.kind == CSTParser.Tokens.COMMA
            push!(bindings, (true, argname, par))
            par = root
        elseif arg isa CSTParser.OPERATOR && arg.kind == CSTParser.Tokens.COLON
            root = par
            push!(bindings, (false, argname, par))
        elseif arg isa CSTParser.PUNCTUATION && arg.kind == CSTParser.Tokens.DOT
            #dot between identifiers
            push!(bindings, (false, argname, par))
        elseif arg isa CSTParser.OPERATOR && arg.kind == CSTParser.Tokens.DOT
            #dot prexceding identifier
            if par == root == store
                par = imprt.si.i
            elseif par isa Tuple
                if length(par) > 0
                    par = shrink_tuple(par)
                else
                    return
                end
            else
                return
            end
        else
            return
        end
        if i == n
            push!(bindings, (true, CSTParser.str_value(arg), par))
        end
        i += 1
    end
    for b in bindings
        # b = (doimport, name, val)
        !b[1] && continue
        if b[3] isa Binding
            binding = Binding(imprt.loc, imprt.si, b[3].val, b[3].t)
        else
            binding = Binding(imprt.loc, imprt.si, b[3], nothing)
        end
        add_binding(b[2], binding, state.bindings, imprt.si.i)
        
        if u 
            if b[3] isa Dict && get(b[3],".type", "") == "module"
                state.used_modules[b[2]] = binding
            elseif b[3] isa Binding
                ind = add_to_tuple(b[3].si.i, b[3].si.n + 1)                
                if haskey(state.exports, ind)
                    for n in state.exports[ind]
                        ret = find_binding(state.bindings, n, b->b.si.i == ind)
                        isempty(ret) && continue
                        eb = last(ret)
                        if eb isa Binding
                            binding = Binding(imprt.loc, imprt.si, eb.val, eb.t)
                        else
                            binding = Binding(imprt.loc, imprt.si, eb, nothing)
                        end
                        add_binding(n, binding, state.bindings, imprt.si.i)
                    end
                end
            end
        end
    end
end

function resolve_imports(state)
    for imprt in state.imports
        resolve_import(imprt, state)
    end
end