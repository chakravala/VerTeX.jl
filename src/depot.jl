
#   This file is part of JuliaTeX.jl. It is licensed under the MIT license
#   Copyright (C) 2018 Michael Reed

repos = Dict("julia"=>"~/.julia/vtx/")

function save(dat::Dict,path::String)
    repo = haskey(dat,"depot") ? dat["depot"] : "julia"
    !haskey(repos,repo) && (@warn "did not save, repo not found"; return dat)
    way = joinpath(checkhome(repos[repo]),path)
    !isdir(dirname(way)) && mkpath(dirname(way))
    out = dat
    if haskey(dat,"dir") && (dat["dir"] ≠ path)
        rm(joinpath(checkhome(repos[repo]),dat["dir"]))
        out["dir"] = path
    else
        push!(out,"dir"=>path)
    end
    open(way, "w") do f
        write(f, dict2toml(out))
    end
    return out
end

function save(dat::Dict)
    save(dat, haskey(dat,"dir") ? dat["dir"] : dat["uuid"])
end

function save(dat::Dict,path::String,repo::String)
    out = dat
    if haskey(dat["depot"])
        rm(joinpath(checkhome(repos[dat["depot"]]),dat["dir"]))
        out["depot"] = repo
        out["dir"] = path
    else
        push!(out,"depot"=>repo,"dir"=>path)
    end
    save(out,path)
end

function load(path::String,repo="julia")
    !haskey(repos,repo) && (@warn "did not load, repo not found"; return path)
    dat = ""
    open(joinpath(checkhome(repos[repo]),path), "r") do f
        dat = read(f, String)
    end
    return TOML.parse(dat)
end
