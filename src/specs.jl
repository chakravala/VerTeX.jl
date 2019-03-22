
#   This file is part of VerTeX.jl. It is licensed under the MIT license
#   Copyright (C) 2019 Michael Reed

#---------#
# Options #
#---------#

struct OptionSpec
    name::String
    short_name::Union{Nothing,String}
    api::Pair{Symbol, Any}
    takes_arg::Bool
end

# TODO assert names matching lex regex
# assert now so that you don't fail at user time
# see function `REPLMode.APIOptions`
function OptionSpec(;name::String,
                    short_name::Union{Nothing,String}=nothing,
                    takes_arg::Bool=false,
                    api::Pair{Symbol,<:Any})::OptionSpec
    takes_arg && @assert hasmethod(api.second, Tuple{String})
    return OptionSpec(name, short_name, api, takes_arg)
end

function OptionSpecs(decs::Vector{OptionDeclaration})::Dict{String, OptionSpec}
    specs = Dict()
    for x in decs
        opt_spec = OptionSpec(;x...)
        @assert get(specs, opt_spec.name, nothing) === nothing # don't overwrite
        specs[opt_spec.name] = opt_spec
        if opt_spec.short_name !== nothing
            @assert get(specs, opt_spec.short_name, nothing) === nothing # don't overwrite
            specs[opt_spec.short_name] = opt_spec
        end
    end
    return specs
end

#-----------#
# Arguments #
#-----------#
struct ArgSpec
    count::Pair
    parser::Function
end

struct CommandSpec
    kind::CommandKind
    canonical_name::String
    short_name::Union{Nothing,String}
    handler::Union{Nothing,Function}
    argument_spec::ArgSpec
    option_specs::Dict{String,OptionSpec}
    completions::Union{Nothing,Function}
    description::String
    help::Union{Nothing,Markdown.MD}
end

function CommandSpec(;kind::Union{Nothing,CommandKind}      = nothing,
                     name::Union{Nothing,String}            = nothing,
                     short_name::Union{Nothing,String}      = nothing,
                     handler::Union{Nothing,Function}       = nothing,
                     option_spec::Vector{OptionDeclaration} = OptionDeclaration[],
                     help::Union{Nothing,Markdown.MD}       = nothing,
                     description::Union{Nothing,String}     = nothing,
                     completions::Union{Nothing,Function}   = nothing,
                     arg_count::Pair                        = (0=>0),
                     arg_parser::Function                   = unwrap,
                     )::CommandSpec
    @assert kind !== nothing "Register and specify a `CommandKind`"
    @assert name !== nothing "Supply a canonical name"
    @assert description !== nothing "Supply a description"
    # TODO assert isapplicable completions dict, string
    return CommandSpec(kind, name, short_name, handler, ArgSpec(arg_count, arg_parser),
                       OptionSpecs(option_spec), completions, description, help)
end

function CommandSpecs(declarations::Vector{CommandDeclaration})::Dict{String,CommandSpec}
    specs = Dict()
    for dec in declarations
        spec = CommandSpec(;dec...)
        @assert !haskey(specs, spec.canonical_name) "duplicate spec entry"
        specs[spec.canonical_name] = spec
        if spec.short_name !== nothing
            @assert !haskey(specs, spec.short_name) "duplicate spec entry"
            specs[spec.short_name] = spec
        end
    end
    return specs
end

function SuperSpecs(compound_commands)::Dict{String,Dict{String,CommandSpec}}
    super_specs = Dict()
    for x in compound_commands
        name = x.first
        spec = CommandSpecs(x.second)
        @assert !haskey(super_specs, name) "duplicate super spec entry"
        super_specs[name] = spec
    end
    return super_specs
end

###########
# Parsing #
###########

# QString: helper struct for retaining quote information
struct QString
    raw::String
    isquoted::Bool
end
unwrap(xs::Vector{QString}) = map(x -> x.raw, xs)

#---------#
# Options #
#---------#
struct Option
    val::String
    argument::Union{Nothing,String}
    Option(val::AbstractString) = new(val, nothing)
    Option(val::AbstractString, arg::Union{Nothing,String}) = new(val, arg)
end
Base.show(io::IO, opt::Option) = print(io, "--$(opt.val)", opt.argument == nothing ? "" : "=$(opt.argument)")
wrap_option(option::String)  = length(option) == 1 ? "-$option" : "--$option"
is_opt(word::AbstractString) = first(word) == '-' && word != "-"

function parse_option(word::AbstractString)::Option
    m = match(r"^(?: -([a-z]) | --([a-z]{2,})(?:\s*=\s*(\S*))? )$"ix, word)
    m === nothing && vtxerror("malformed option: ", repr(word))
    option_name = m.captures[1] !== nothing ? m.captures[1] : m.captures[2]
    option_arg  = m.captures[3] === nothing ? nothing : String(m.captures[3])
    return Option(option_name, option_arg)
end

#-----------#
# Statement #
#-----------#
# Statement: text-based representation of a command
Base.@kwdef mutable struct Statement
    super::Union{Nothing,String}                  = nothing
    spec::Union{Nothing,CommandSpec}              = nothing
    options::Union{Vector{Option},Vector{String}} = String[]
    arguments::Vector{QString}                    = QString[]
    preview::Bool                                 = false
end

function lex(cmd::String)::Vector{QString}
    in_doublequote = false
    in_singlequote = false
    qstrings = QString[]
    token_in_progress = Char[]

    push_token!(is_quoted) = begin
        push!(qstrings, QString(String(token_in_progress), is_quoted))
        empty!(token_in_progress)
    end

    for c in cmd
        if c == '"'
            if in_singlequote # raw char
                push!(token_in_progress, c)
            else # delimiter
                in_doublequote ? push_token!(true) : push_token!(false)
                in_doublequote = !in_doublequote
            end
        elseif c == '\''
            if in_doublequote # raw char
                push!(token_in_progress, c)
            else # delimiter
                in_singlequote ? push_token!(true) : push_token!(false)
                in_singlequote = !in_singlequote
            end
        elseif c == ' '
            if in_doublequote || in_singlequote # raw char
                push!(token_in_progress, c)
            else # delimiter
                push_token!(false)
            end
        elseif c == ';'
            if in_doublequote || in_singlequote # raw char
                push!(token_in_progress, c)
            else # special delimiter
                push_token!(false)
                push!(qstrings, QString(";", false))
            end
        else
            push!(token_in_progress, c)
        end
    end
    (in_doublequote || in_singlequote) ? vtxerror("unterminated quote") : push_token!(false)
    # to avoid complexity in the main loop, empty tokens are allowed above and
    # filtered out before returning
    return filter(x->!isempty(x.raw), qstrings)
end

function tokenize(cmd::String)
    cmd = replace(replace(cmd, "\r\n" => "; "), "\n" => "; ") # for multiline commands
    qstrings = lex(cmd)
    statements = foldl(qstrings; init=[QString[]]) do collection, next
        (next.raw == ";" && !next.isquoted) ?
            push!(collection, QString[]) :
            push!(collection[end], next)
        return collection
    end
    return statements
end

function core_parse(words::Vector{QString}; only_cmd=false)
    statement = Statement()
    word = nothing
    function next_word!()
        isempty(words) && return false
        word = popfirst!(words)
        return true
    end

    # begin parsing
    next_word!() || return statement, ((word === nothing) ? nothing : word.raw)
    if word.raw == "preview"
        statement.preview = true
        next_word!() || return statement, word.raw
    end
    # handle `?` alias for help
    # It is special in that it requires no space between command and args
    if word.raw[1]=='?' && !word.isquoted
        length(word.raw) > 1 && pushfirst!(words, QString(word.raw[2:end],false))
        word = QString("?", false)
    end
    # determine command
    super = get(super_specs, word.raw, nothing)
    if super !== nothing # explicit
        statement.super = word.raw
        next_word!() || return statement, word.raw
        command = get(super, word.raw, nothing)
        command !== nothing || return statement, word.raw
    else # try implicit package
        super = super_specs["package"]
        command = get(super, word.raw, nothing)
        command !== nothing || return statement, word.raw
    end
    statement.spec = command

    only_cmd && return statement, word.raw # hack to hook in `help` command

    next_word!() || return statement, word.raw

    # full option parsing is delayed so that the completions parser can use the raw string
    while is_opt(word.raw)
        push!(statement.options, word.raw)
        next_word!() || return statement, word.raw
    end

    pushfirst!(words, word)
    statement.arguments = words
    return statement, words[end].raw
end

parse(input::String) =
    map(Base.Iterators.filter(!isempty, tokenize(input))) do words
        statement, _ = core_parse(words)
        statement.spec === nothing && vtxerror("Could not determine command")
        statement.options = map(parse_option, statement.options)
        statement
    end

#------------#
# APIOptions #
#------------#
const APIOptions = Dict{Symbol, Any}
function APIOptions(options::Vector{Option},
                    specs::Dict{String, OptionSpec},
                    )::APIOptions
    api_options = Dict{Symbol, Any}()
    for option in options
        spec = specs[option.val]
        api_options[spec.api.first] = spec.takes_arg ?
            spec.api.second(option.argument) :
            spec.api.second
    end
    return api_options
end
Context!(ctx::APIOptions)::Context = Types.Context!(collect(ctx))

#---------#
# Command #
#---------#
Base.@kwdef struct Command
    spec::Union{Nothing,CommandSpec} = nothing
    options::APIOptions              = APIOptions()
    arguments::Vector                = []
    preview::Bool                    = false
end

function enforce_option(option::Option, specs::Dict{String,OptionSpec})
    spec = get(specs, option.val, nothing)
    spec !== nothing || vtxerror("option '$(option.val)' is not a valid option")
    if spec.takes_arg
        option.argument !== nothing ||
            vtxerror("option '$(option.val)' expects an argument, but no argument given")
    else # option is a switch
        option.argument === nothing ||
            vtxerror("option '$(option.val)' does not take an argument, but '$(option.argument)' given")
    end
end

"""
checks:
- options are understood by the given command
- options do not conflict (e.g. `rm --project --manifest`)
- options which take an argument are given arguments
- options which do not take arguments are not given arguments
"""
function enforce_option(options::Vector{Option}, specs::Dict{String,OptionSpec})
    unique_keys = Symbol[]
    get_key(opt::Option) = specs[opt.val].api.first

    # per option checking
    foreach(x->enforce_option(x,specs), options)
    # checking for compatible options
    for opt in options
        key = get_key(opt)
        if key in unique_keys
            conflicting = filter(opt->get_key(opt) == key, options)
            vtxerror("Conflicting options: $conflicting")
        else
            push!(unique_keys, key)
        end
    end
end

"""
Final parsing (and checking) step.
This step is distinct from `parse` in that it relies on the command specifications.
"""
function Command(statement::Statement)::Command
    # arguments
    arg_spec = statement.spec.argument_spec
    arguments = arg_spec.parser(statement.arguments)
    if !(arg_spec.count.first <= length(arguments) <= arg_spec.count.second)
        vtxerror("Wrong number of arguments")
    end
    # options
    opt_spec = statement.spec.option_specs
    enforce_option(statement.options, opt_spec)
    options = APIOptions(statement.options, opt_spec)
    return Command(statement.spec, options, arguments, statement.preview)
end

######################
# REPL mode creation #
######################

# Provide a string macro pkg"cmd" that can be used in the same way
# as the REPLMode `pkg> cmd`. Useful for testing and in environments
# where we do not have a REPL, e.g. IJulia.
struct MiniREPL <: REPL.AbstractREPL
    display::TextDisplay
    t::REPL.Terminals.TTYTerminal
end
function MiniREPL()
    MiniREPL(TextDisplay(stdout), REPL.Terminals.TTYTerminal(get(ENV, "TERM", Sys.iswindows() ? "" : "dumb"), stdin, stdout, stderr))
end
REPL.REPLDisplay(repl::MiniREPL) = repl.display

