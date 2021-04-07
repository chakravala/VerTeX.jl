
# This file is adapted from Julia. License is MIT: https://julialang.org/license

function complete_local_path(s, i1, i2)
    cmp = REPL.REPLCompletions.complete_path(s, i2)
    completions = filter!(isdir, [REPL.REPLCompletions.completion_text(p) for p in cmp[1]])
    return completions, cmp[2], !isempty(completions)
end

#=function complete_installed_package(s, i1, i2, project_opt)
    pkgs = project_opt ? API.__installed(PKGMODE_PROJECT) : API.__installed()
    pkgs = sort!(collect(keys(filter((p) -> p[2] != nothing, pkgs))))
    cmp = filter(cmd -> startswith(cmd, s), pkgs)
    return cmp, i1:i2, !isempty(cmp)
end

function complete_remote_package(s, i1, i2)
    cmp = String[]
    julia_version = VERSION
    for reg in Types.registries(;clone_default=false)
        data = Types.read_registry(joinpath(reg, "Registry.toml"))
        for (uuid, pkginfo) in data["packages"]
            name = pkginfo["name"]
            if startswith(name, s)
                compat_data = Operations.load_package_data_raw(
                    VersionSpec, joinpath(reg, pkginfo["path"], "Compat.toml"))
                supported_julia_versions = VersionSpec(VersionRange[])
                for (ver_range, compats) in compat_data
                    for (compat, v) in compats
                        if compat == "julia"
                            union!(supported_julia_versions, VersionSpec(v))
                        end
                    end
                end
                if VERSION in supported_julia_versions
                    push!(cmp, name)
                end
            end
        end
    end
    return cmp, i1:i2, !isempty(cmp)
end=#

function complete_help(options, partial)
    names = String[]
    for cmds in values(super_specs)
         append!(names, [spec.canonical_name for spec in values(cmds)])
    end
    return sort!(unique!(append!(names, collect(keys(super_specs)))))
end

function complete_argument(to_complete, i1, i2, lastcommand, project_opt
                           )::Tuple{Vector{String},UnitRange{Int},Bool}
    if lastcommand == CMD_HELP
        completions = filter(x->startswith(x,to_complete), completion_cache.canonical_names)
        return completions, i1:i2, !isempty(completions)
    #=elseif lastcommand in [CMD_STATUS, CMD_RM, CMD_UP, CMD_TEST, CMD_BUILD, CMD_FREE, CMD_PIN]
        return complete_installed_package(to_complete, i1, i2, project_opt)=#
    elseif lastcommand in [CMD_ADD, CMD_DEVELOP]
        if occursin(Base.Filesystem.path_separator_re, to_complete)
            return complete_local_path(to_complete, i1, i2)
        #=else
            rps = complete_remote_package(to_complete, i1, i2)
            lps = complete_local_path(to_complete, i1, i2)
            return vcat(rps[1], lps[1]), isempty(rps[1]) ? lps[2] : i1:i2, length(rps[1]) + length(lps[1]) > 0=#
        end
    end
    return String[], 0:-1, false
end

function completions(full, index)::Tuple{Vector{String},UnitRange{Int},Bool}
    pre = full[1:index]
    if isempty(pre)
        return completion_cache.commands, 0:-1, false
    end
    x = parse(pre; for_completions=true)
    if x === nothing # failed parse (invalid command name)
        return String[], 0:-1, false
    end
    (key::Symbol, to_complete::String, spec, proj::Bool) = x
    last = split(pre, ' ', keepempty=true)[end]
    offset = isempty(last) ? index+1 : last.offset+1
    if last != to_complete # require a space before completing next field
        return String[], 0:-1, false
    end
    if key == :arg
        return complete_argument(to_complete, offset, index, spec.kind, proj)
    end
    possible::Vector{String} =
        key == :meta ? completion_cache.meta_options :
        key == :cmd ? completion_cache.commands :
        key == :sub ? completion_cache.subcommands[spec] :
        key == :opt ? completion_cache.options[spec.kind] :
        String[]
    completions = filter(x->startswith(x,to_complete), possible)
    return completions, offset:index, !isempty(completions)
end


