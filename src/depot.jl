
#   This file is part of VerTeX.jl. It is licensed under the MIT license
#   Copyright (C) 2018 Michael Reed

repos = Dict("julia"=>"~/.julia/vtx/")

manifest = Dict("julia"=>Dict())
dictionary = Dict()

function lookup(ref)
    s = split(ref,':';limit=2)
    if haskey(dictionary,s[1])
        key = length(s) > 1 ? s[2] : ""
        return haskey(dictionary[s[1]],key) ? dictionary[s[1]][key] : [nothing]
    else
        return [nothing]
    end
end

function getdepot()
    repodat = Dict()
    try
        open(joinpath(homedir(),".julia/vtx/Depot.toml"), "r") do f
            repodat = TOML.parse(read(f,String))
        end
    catch
    end
    for key in keys(repos)
        push!(repodat,key=>repos[key])
    end
    return repodat
end

function regdepot(depot,location)
    dep = getdepot()
    if haskey(dep,depot)
        dep[depot] = location
    else
        push!(dep,depot=>location)
    end
    try
        open(joinpath(homedir(),".julia/vtx/Depot.toml"), "w") do f
            write(f, dict2toml(dep))
        end
    catch
    end
end

regpkg(depot,location) = regdepot(string(depot),joinpath(dirname(location),"vtx"))

regcmd = :(println(joinpath(dirname(@__DIR__),"vtx")))

function updateref!(data)
    depot = haskey(data,"depot") ? data["depot"] : "julia"
    !haskey(manifest[depot],data["uuid"]) && push!(manifest[depot],data["uuid"]=>Dict())
    setval!(manifest[depot][data["uuid"]],"dir",data["dir"])
    # update manifest and dictionary
    for cat in ["label","cite"]
        if haskey(data,cat)
            setval!(manifest[depot][data["uuid"]],cat,data[cat])
            cat ≠ "cite" && for ref in data[cat]
                if cat == "label"
                    give = [data["uuid"],haskey(data,"depot") ? data["depot"] : "julia",data["dir"]]
                    s = split(ref,':';limit=2)
                    key = length(s) > 1 ? join(s[2]) : ""
                    haskey(dictionary,s[1]) ? push!(dictionary[s[1]],key=>give) : push!(dictionary,join(s[1])=>Dict(key=>give))
                end
            end
        end
    end
    for item in ["ref","used","deps","show"]
        if haskey(data,item)
            setval!(manifest[depot][data["uuid"]],item,data[item])
        else
            haskey(manifest[depot][data["uuid"]],item) && pop!(manifest[depot][data["uuid"]],item)
        end
    end
    return nothing
end

function updaterefby!(depot,key)
    for cat ∈ ["ref","used","deps","show"]
        # identify cross-references
        if haskey(manifest[depot][key],cat)
            for ref in manifest[depot][key][cat]
                if cat ≠ "show"
                    s = split(ref,':';limit=2)
                    s2 = length(s) > 2 ? s[2] : ""
                    if haskey(dictionary,s[1]) && haskey(dictionary[s[1]],s2)
                        addval!(manifest[dictionary[s[1]][s2][2]][dictionary[s[1]][s2][1]],cat*"by",[key,depot,manifest[depot][key]["dir"]])
                    end
                else
                    if haskey(manifest,ref[2]) && haskey(manifest[ref[2]],ref[1])
                        addval!(manifest[ref[2]][ref[1]],cat*"by",[key,depot,manifest[depot][key]["dir"]])
                    end
                end
            end
        end
        # remove surplus edges
        if haskey(manifest[depot][key],cat*"by")
            amt = length(manifest[depot][key][cat*"by"])
            k = 1
            while k ≤ amt
                ref = manifest[depot][key][cat*"by"][k]
                if haskey(manifest[ref[2]][ref[1]],cat) &&
                        ref ∉ manifest[ref[2]][ref[1]][cat]
                    deleteat!(manifest[depot][key][cat*"by"],k)
                    amt -= 1
                else
                    k += 1
                end
            end
            isempty(manifest[depot][key][cat*"by"]) && pop!(manifest[depot][key],cat*"by")
        end
    end
    return nothing
end

function scan(depot)
    depos = getdepot()
    !haskey(manifest,depot) && push!(manifest,depot=>Dict())
    for (root, dirs, files) in walkdir(checkhome(depos[depot]))
        for dir in dirs
            for file in readdir(joinpath(root,dir))
                data = nothing
                if endswith(file, ".vtx")
                    data = TOML.parsefile(joinpath(root,dir,file))
                    updateref!(data)
                end
            end
        end
    end
end

function scan()
    for depot ∈ keys(manifest)
        for key ∈ keys(manifest[depot])
            updaterefby!(depot,key)
        end
    end
end

resolve(depot) = haskey(getdepot(),depot) && (scan(depot); scan())

function resolve()
    for depot in keys(getdepot())
        scan(depot)
    end
    scan()
end

function save(dat::Dict,path::String;warn=true)
    out = deepcopy(dat)
    !haskey(out,"depot") && push!(out,"depot"=>"julia")
    repo = out["depot"]
    depos = getdepot()
    !haskey(depos,repo) && (@warn "did not save, $repo depot not found"; return dat)
    data = nothing
    try
        data = load(path,repo)
        if (data ≠ nothing)
            cmv = checkmerge(dat["revised"],data,dat["title"],dat["author"],dat["date"],dat["tex"],"Save/Overwrite?")
            if cmv == 0
                throw(error("VerTeX unable to proceed due to merge failure"))
            elseif cmv < 2
                @warn "skipped saving $path"
                return dat
            end
        end
    catch
    end
    way = joinpath(checkhome(depos[repo]),path)
    !isdir(dirname(way)) && mkpath(dirname(way))
    if haskey(dat,"dir") && (dat["dir"] ≠ path)
        #rm(joinpath(checkhome(depos[repo]),dat["dir"]))
        out["dir"] = path
    else
        push!(out,"dir"=>path)
    end
    infotxt = "saving VerTeX: $(out["title"])\n"
    old = data ≠ nothing ? data : dat
    # go through save queue from show list
    if haskey(out,"save")
        for it ∈ out["save"]
            save(it,out["ids"][it["uuid"]][3];warn=warn)
        end
        pop!(out,"save")
    end
    haskey(out,"compact") && pop!(out,"compact")
    updateref!(out)
    updaterefby!(repo,out["uuid"])
    if haskey(out,"edit")
        setval!(out,"revised",out["edit"])
        pop!(out,"edit")
    end
    if data ≠ nothing
        haskey(data,"revised") && pop!(data,"revised")
        compare = deepcopy(out)
        haskey(compare,"revised") && pop!(compare,"revised")
        data == compare && (return out)
    end
    open(way, "w") do f
        write(f, dict2toml(out))
    end
    warn && (@info infotxt*"saved at $path in $(out["depot"])")
    return out
end

function save(dat::Dict;warn=true)
    save(dat, haskey(dat,"dir") ? dat["dir"] : dat["uuid"];warn=warn)
end

function save(dat::Dict,path::String,repo::String;warn=true)
    out = deepcopy(dat)
    if haskey(dat["depot"])
        #rm(joinpath(checkhome(getdepot()[dat["depot"]]),dat["dir"]))
        out["depot"] = repo
        out["dir"] = path
    else
        push!(out,"depot"=>repo,"dir"=>path)
    end
    save(out,path;warn=warn)
end

function load(path::String,repo="julia")
    depos = getdepot()
    !haskey(depos,repo) && (@warn "did not load, $repo depot not found"; return path)
    dat = ""
    open(joinpath(checkhome(depos[repo]),path), "r") do f
        dat = read(f, String)
    end
    return TOML.parse(dat)
end

function loadpath(data::Dict,file::String="/tmp/doc.tex")
    load = ""
    g = getdepot()
    if haskey(data,"dir") && (data["depot"] ∈ keys(g))
        load = joinpath(checkhome(g[data["depot"]]),data["dir"])
        load = replace(load,r".vtx$"=>".tex")
        !occursin(r".tex$",load) && (load = load*".tex")
    else
        load = file
    end
    return load
end

function writetex(data::Dict,file::String="/tmp/doc.tex")
    load = loadpath(data,file)
    # check if file actually exists yet, if not create it.
    open(load, "w") do f
        # check if tex file actually needs to be updated?
        write(f, VerTeX.dict2tex(data))
    end
    return load
end

function readtex(load::String)
    out = ""
    open(load, "r") do f
        out = read(f,String)
    end
    return out
end

function update(data::Dict)
    save(tex2dict(readtex(loadpath(data)),data))
end

function writemanifest(depot)
    depos = getdepot()
    if haskey(manifest,depot) && haskey(depos,depot)
        open(joinpath(checkhome(depos[depot]),"Manifest.toml"), "w") do f
            write(f, dict2toml(manifest[depot]))
        end
    else
        @warn "no $depot manifest found in memory"
    end
    return nothing
end

function writemanifest()
    for key ∈ keys(manifest)
        writemanifest(key)
    end
    return nothing
end

function writedictionary()
    depos = getdepot()
    open(joinpath(checkhome(depos["julia"]),"Dictionary.toml"), "w") do f
        write(f, dict2toml(dictionary))
    end
    return nothing
end

function readmanifest(depot)
    depos = getdepot()
    if haskey(depos,depot)
        dat = ""
        try
            open(joinpath(checkhome(depos[depot]),"Manifest.toml"), "r") do f
                dat = read(f, String)
            end
            setval!(manifest,depot,TOML.parse(dat))
        catch
        end
    else
        @warn "did not load, $depot depot not found"
    end
    return nothing
end

function readmanifest()
    depos = getdepot()
    for depot ∈ keys(depos)
        readmanifest(depot)
    end
    return nothing
end

function readdictionary()
    depos = getdepot()
    dat = ""
    try
        open(joinpath(checkhome(depos["julia"]),"Dictionary.toml"), "r") do f
            dat = read(f, String)
        end
        global dictionary
        dictionary = TOML.parse(dat)
    catch
    end
    return nothing
end
