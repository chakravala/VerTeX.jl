
#   This file is part of JuliaTeX.jl. It is licensed under the MIT license
#   Copyright (C) 2018 Michael Reed

repos = Dict("julia"=>"~/.julia/vtx/")

function getdepot()
    repodat = Dict()
    try
        open(joinpath(homedir(),".julia/vtx-depot.toml"), "r") do f
            repodat = TOML.parse(read(f,String))
        end
    catch
    end
    for key in keys(repos)
        push!(repodat,key=>repos[key])
    end
    return repodat
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
        data ≠ nothing && checkmerge(dat["revised"],data,dat["title"],dat["author"],dat["date"],dat["tex"],"Save/Overwrite?") &&
            (@warn "skipped saving $path"; return dat)
    catch
    end
    way = joinpath(checkhome(depos[repo]),path)
    !isdir(dirname(way)) && mkpath(dirname(way))
    if haskey(dat,"dir") && (dat["dir"] ≠ path)
        rm(joinpath(checkhome(depos[repo]),dat["dir"]))
        out["dir"] = path
    else
        push!(out,"dir"=>path)
    end
    infotxt = "saving VerTeX: $(out["title"])\n"
    old = haskey(dat,"dir") ? load(dat["dir"],dat["depot"]) : dat
    # go through save queue from show list
    if haskey(out,"save")
        for it ∈ out["save"]
            save(it,out["ids"][it["uuid"]][3];warn=warn)
        end
        pop!(out,"save")
    end
    haskey(out,"compact") && pop!(out,"compact")
    for cat ∈ ["ref","deps","used","show"]
        list = haskey(old,cat) ? copy(old[cat]) : String[]
        if haskey(out,cat)
            for ref ∈ out[cat]
                if haskey(out,"ids") && haskey(out["ids"],ref)
                    h = out["ids"][ref]
                    if (h[2] ≠ repo) && (h[3] ≠ path)
                        s = load(h[3],h[2])
                        if updaterefby!(s,out;cat="$(cat)by")
                            save(s,warn=false)
                            infotxt *= "updated \\$cat{$ref} at $(h[3]) in $(h[2])\n"
                        end
                    end
                end
                amt = length(list)
                k = 1
                while k ≤ amt
                    if list[k] == ref
                        deleteat!(list,k)
                        amt -= 1
                    else
                        k += 1
                    end
                end
            end
        end
        for ref ∈ list
            if haskey(old,"ids") && haskey(old["ids"],ref)
                h = old["ids"][ref]
                if (h[2] ≠ repo) && (h[3] ≠ path)
                    s = load(h[3],h[2])
                    if updaterefby!(s,out;remove=true,cat="$(cat)by")
                        save(s,warn=false)
                        infotxt *= "removed \\$cat{$ref} at $(h[3]) in $(h[2])\n"
                    end
                end
            end
        end
    end
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
