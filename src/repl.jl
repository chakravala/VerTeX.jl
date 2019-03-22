module REPLMode

#   This file is part of VerTeX.jl. It is licensed under the MIT license
#   Copyright (C) 2019 Michael Reed

using Markdown
using UUIDs, Pkg

import REPL
import REPL: LineEdit, REPLCompletions

import Pkg: Types.casesensitive_isdir
using Pkg.Types, Pkg.Display, Pkg.Operations

#########################
# Specification Structs #
#########################

#import Pkg.REPLMode: OptionSpec, OptionSpecs, ArgSpec, CommandSpec, CommandSpecs, SuperSpecs, QString, unwrap, Option, wrap_option, is_opt, parse_option, Statement, lex, tokenize, core_parse, parse, APIOptions, Command, enforce_option, MiniREPL

#---------#
# Options #
#---------#
const OptionDeclaration = Vector{Pair{Symbol,Any}}

#----------#
# Commands #
#----------#
@enum(CommandKind, CMD_VIM)
#=@enum(CommandKind, CMD_HELP, CMD_RM, CMD_ADD, CMD_DEVELOP, CMD_UP,
                   CMD_STATUS, CMD_TEST, CMD_GC, CMD_BUILD, CMD_PIN,
                   CMD_FREE, CMD_GENERATE, CMD_RESOLVE, CMD_PRECOMPILE,
                   CMD_INSTANTIATE, CMD_ACTIVATE, CMD_PREVIEW,
                   CMD_REGISTRY_ADD, CMD_REGISTRY_RM, CMD_REGISTRY_UP, CMD_REGISTRY_STATUS
                   )=#
const CommandDeclaration = Vector{Pair{Symbol,Any}}

include("specs.jl")

#############
# Execution #
#############
function do_cmd(repl::REPL.AbstractREPL, input::String; do_rethrow=false)
    try
        statements = parse(input)
        commands   = map(Command, statements)
        for command in commands
            do_cmd!(command, repl)
        end
    catch err
        do_rethrow && rethrow()
        if err isa PkgError || err isa ResolverError
            Base.display_error(repl.t.err_stream, ErrorException(sprint(showerror, err)), Ptr{Nothing}[])
        else
            Base.display_error(repl.t.err_stream, err, Base.catch_backtrace())
        end
    end
end

function do_cmd!(command::Command, repl)
    context = Dict{Symbol,Any}(:preview => command.preview)

    # REPL specific commands
    #command.spec.kind == CMD_HELP && return Base.invokelatest(do_help!, command, repl)

    # API commands
    # TODO is invokelatest still needed?
    if applicable(command.spec.handler, context, command.arguments, command.options)
        Base.invokelatest(command.spec.handler, context, command.arguments, command.options)
    else
        Base.invokelatest(command.spec.handler, command.arguments, command.options)
    end
end

function parse_command(words::Vector{QString})
    statement, word = core_parse(words; only_cmd=true)
    if statement.super === nothing && statement.spec === nothing
        vtxerror("invalid input: `$word` is not a command")
    end
    return statement.spec === nothing ?  statement.super : statement.spec
end

function do_vim!(a,b)
    texedit(a[1].raw)
end

#=function do_help!(command::Command, repl::REPL.AbstractREPL)
    disp = REPL.REPLDisplay(repl)
    if isempty(command.arguments)
        Base.display(disp, help)
        return
    end
    help_md = md""

    cmd = parse_command(command.arguments)
    if cmd isa String
        # gather all helps for super spec `cmd`
        all_specs = sort!(unique(values(super_specs[cmd]));
                          by=(spec->spec.canonical_name))
        for spec in all_specs
            isempty(help_md.content) || push!(help_md.content, md"---")
            push!(help_md.content, spec.help)
        end
    elseif cmd isa CommandSpec
        push!(help_md.content, cmd.help)
    end
    !isempty(command.arguments) && @warn "More than one command specified, only rendering help for first"
    Base.display(disp, help_md)
end=#

######################
# REPL mode creation #
######################

# Provide a string macro pkg"cmd" that can be used in the same way
# as the REPLMode `pkg> cmd`. Useful for testing and in environments
# where we do not have a REPL, e.g. IJulia.

const minirepl = Ref{MiniREPL}()

__init__() = minirepl[] = MiniREPL()

macro vtx_str(str::String)
    :($(do_cmd)(minirepl[], $str; do_rethrow=true))
end

vtxstr(str::String) = do_cmd(minirepl[], str; do_rethrow=true)

struct VtxCompletionProvider <: LineEdit.CompletionProvider end

function LineEdit.complete_line(c::VtxCompletionProvider, s)
    partial = REPL.beforecursor(s.input_buffer)
    full = LineEdit.input_string(s)
    ret, range, should_complete = completions(full, lastindex(partial))
    return ret, partial[range], should_complete
end

prev_project_file = nothing
prev_project_timestamp = nothing
prev_prefix = ""

function promptf()
    #=global prev_project_timestamp, prev_prefix, prev_project_file
    project_file = try
        Types.find_project_file()
    catch
        nothing
    end=#
    prefix = ""
    #=if project_file !== nothing
        if prev_project_file == project_file && prev_project_timestamp == mtime(project_file)
            prefix = prev_prefix
        else
            project = try
                Types.read_project(project_file)
            catch
                nothing
            end
            if project !== nothing
                projname = project.name
                name = projname !== nothing ? projname : basename(dirname(project_file))
                prefix = string("(", name, ") ")
                prev_prefix = prefix
                prev_project_timestamp = mtime(project_file)
                prev_project_file = project_file
            end
        end
    end=#
    return prefix * "vtx> "
end

# Set up the repl Pkg REPLMode
function create_mode(repl, main)
    vtx_mode = LineEdit.Prompt(promptf;
        prompt_prefix = repl.options.hascolor ? Base.text_colors[:white] : "",
        prompt_suffix = "",
        complete = VtxCompletionProvider(),
        sticky = true)

    vtx_mode.repl = repl
    hp = main.hist
    hp.mode_mapping[:pkg] = vtx_mode
    vtx_mode.hist = hp

    search_prompt, skeymap = LineEdit.setup_search_keymap(hp)
    prefix_prompt, prefix_keymap = LineEdit.setup_prefix_keymap(hp, vtx_mode)

    vtx_mode.on_done = (s, buf, ok) -> begin
        ok || return REPL.transition(s, :abort)
        input = String(take!(buf))
        REPL.reset(repl)
        do_cmd(repl, input)
        REPL.prepare_next(repl)
        REPL.reset_state(s)
        s.current_mode.sticky || REPL.transition(s, main)
    end

    mk = REPL.mode_keymap(main)

    shell_mode = nothing
    for mode in Base.active_repl.interface.modes
        if mode isa LineEdit.Prompt
            mode.prompt == "shell> " && (shell_mode = mode)
        end
    end

    repl_keymap = Dict()
    if shell_mode != nothing
        repl_keymap[';'] = function (s,o...)
            if isempty(s) || position(LineEdit.buffer(s)) == 0
                buf = copy(LineEdit.buffer(s))
                LineEdit.transition(s, shell_mode) do
                    LineEdit.state(s, shell_mode).input_buffer = buf
                end
            else
                LineEdit.edit_insert(s, ';')
            end
        end
    end

    b = Dict{Any,Any}[
        skeymap, repl_keymap, mk, prefix_keymap, LineEdit.history_keymap,
        LineEdit.default_keymap, LineEdit.escape_defaults
    ]
    vtx_mode.keymap_dict = LineEdit.keymap(b)
    return vtx_mode
end

function repl_init(repl)
    main_mode = repl.interface.modes[1]
    vtx_mode = create_mode(repl, main_mode)
    push!(repl.interface.modes, vtx_mode)
    keymap = Dict{Any,Any}(
        ',' => function (s,args...)
            if isempty(s) || position(LineEdit.buffer(s)) == 0
                buf = copy(LineEdit.buffer(s))
                LineEdit.transition(s, vtx_mode) do
                    LineEdit.state(s, vtx_mode).input_buffer = buf
                end
            else
                LineEdit.edit_insert(s, ',')
            end
        end
    )
    main_mode.keymap_dict = LineEdit.keymap_merge(main_mode.keymap_dict, keymap)
    return
end

########
# SPEC #
########
include("completions.jl")
include("args.jl")
include("cmd.jl")
super_specs = SuperSpecs(command_declarations)

########
# HELP #
########
function canonical_names()
    # add "package" commands
    xs = [(spec.canonical_name => spec) for spec in unique(values(super_specs["package"]))]
    sort!(xs, by=first)
    # add other super commands, e.g. "registry"
    for (super, specs) in super_specs
        super != "package" || continue # skip "package"
        temp = [(join([super, spec.canonical_name], " ") => spec) for spec in unique(values(specs))]
        append!(xs, sort!(temp, by=first))
    end
    return xs
end

function gen_help()
    help = md"""
**Welcome to the Pkg REPL-mode**. To return to the `julia>` prompt, either press
backspace when the input line is empty or press Ctrl+C.
**Synopsis**
    pkg> cmd [opts] [args]
Multiple commands can be given on the same line by interleaving a `;` between the commands.
**Commands**
"""
    for (command, spec) in canonical_names()
        push!(help.content, Markdown.parse("`$command`: $(spec.description)"))
    end
    return help
end

#const help = gen_help()

end #module
