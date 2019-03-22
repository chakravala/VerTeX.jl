
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

    vi [-p|--project] pkg[=uuid] ...

edit with vim
    """
],
], #package
] #command_declarations
