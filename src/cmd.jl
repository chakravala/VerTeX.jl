
#   This file is part of VerTeX.jl. It is licensed under the MIT license
#   Copyright (C) 2019 Michael Reed

command_declarations = [
"package" => CommandDeclaration[
[   :kind => CMD_VIM,
    :name => "vim",
    :short_name => "vi",
    :handler => do_vim!,
    :arg_count => 1 => 1,
    :arg_parser => identity,
    :description => "edit with vim",
    :help => md"""

    vi path

edit with vim
    """
],[ :kind => CMD_HELP,
    :name => "help",
    :short_name => "?",
    :arg_count => 0 => Inf,
    :arg_parser => identity,
    :completions => complete_help,
    :description => "show this message",
    :help => md"""

    help

List available commands along with short descriptions.

    help cmd

If `cmd` is a partial command, display help for all subcommands.
If `cmd` is a full command, display help for `cmd`.
    """,
],[ :kind => CMD_PDF,
    :name => "pdf",
    :short_name => "p",
    :handler => do_pdf!,
    :arg_count => 1 => 2,
    :arg_parser => identity,
    :description => "display as pdf",
    :help => md"""

    pdf path [repo] ...

display as pdf
    """
],[ :kind => CMD_STATUS,
    :name => "status",
    :short_name => "st",
    :handler => do_status!,
    :arg_count => 0 => 1,
    :arg_parser => identity,
    :description => "display manifest",
    :help => md"""

    st [repo]

display manifest
    """
],[ :kind => CMD_DICT,
    :name => "dictionary",
    :short_name => "dict",
    :handler => do_dict!,
    :arg_count => 0 => 0,
    :arg_parser => identity,
    :description => "display dictionary",
    :help => md"""

    dict

display dictionary
    """
],
], #package
] #command_declarations
