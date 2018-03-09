
#   This file is part of JuliaTeX.jl. It is licensed under the MIT license
#   Copyright (C) 2018 Michael Reed

repos = Dict("julia"=>"~/.julia/vtx/")

function getdepot()
    repodat = Dict()
    try
        open(joinpath(homedir(),".julia/vtx-depot.toml"), "r") do f
            repodat = TOML.parse(read(f,String))
        end
    end
    for key in keys(repos)
        push!(repodat,key=>repos[key])
    end
    return repodat
end

function save(dat::Dict,path::String)
    out = deepcopy(dat)
    !haskey(out,"depo") && push!(out,"depot"=>"julia")
    repo = out["depot"]
    depos = getdepot()
    !haskey(depos,repo) && (@warn "did not save, $repo depot not found"; return dat)
    way = joinpath(checkhome(depos[repo]),path)
    !isdir(dirname(way)) && mkpath(dirname(way))
    if haskey(dat,"dir") && (dat["dir"] ≠ path)
        rm(joinpath(checkhome(depos[repo]),dat["dir"]))
        out["dir"] = path
    else
        push!(out,"dir"=>path)
    end
    infotxt = "saving VerTeX: $(out["title"])\n"
    old = load(dat["dir"],dat["depot"])
    for cat ∈ ["ref","deps"]
        list = haskey(old,cat) ? copy(old[cat]) : String[]
        if haskey(out,cat)
            for ref ∈ out[cat]
                if haskey(out["ids"],ref)
                    h = out["ids"][ref]
                    s = load(h[3],h[2])
                    updaterefby!(s,out;cat="$(cat)by")
                    save(s)
                    infotxt *= "updated \\$cat{$ref}\n at $(h[3]) in $(h[2])"
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
            if haskey(old["ids"],ref)
                h = old["ids"][ref]
                s = load(h[3],h[2])
                updaterefby!(s,out;remove=true,cat="$(cat)by")
                save(s)
                infotxt *= "removed \\$cat{$ref}\n at $(h[3]) in $(h[2])"
            end
        end
    end
    open(way, "w") do f
        write(f, dict2toml(out))
    end
    @info infotxt*"$path saved in $(dat["depot"])"
    return out
end

function save(dat::Dict)
    save(dat, haskey(dat,"dir") ? dat["dir"] : dat["uuid"])
end

function save(dat::Dict,path::String,repo::String)
    out = deepcopy(dat)
    if haskey(dat["depot"])
        rm(joinpath(checkhome(getdepot()[dat["depot"]]),dat["dir"]))
        out["depot"] = repo
        out["dir"] = path
    else
        push!(out,"depot"=>repo,"dir"=>path)
    end
    save(out,path)
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
