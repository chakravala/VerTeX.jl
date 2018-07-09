__precompile__()
module VerTeX

#   This file is part of VerTeX.jl. It is licensed under the MIT license
#   Copyright (C) 2018 Michael Reed

export dict2toml, tex2dict, tex2toml, dict2tex, toml2tex, toml2dict

using Pkg, UUIDs, Dates
using Pkg.TOML, Pkg.Pkg2

AUTHOR = "anonymous"
try global AUTHOR = ENV["AUTHOR"] finally end

checkhome(path::String) = occursin(r"^~/",path) ? joinpath(homedir(),path[3:end]) : path

function relhome(path::String,home::String=homedir())
    reg = Regex("(?<=^$(replace(home,'/'=>"\\/")))\\/?\\X+")
    return occursin(reg,path) ? '~'*match(reg,path).match : path
end

function preamble(path::String=joinpath(Pkg2.dir("VerTeX"),"vtx/default.tex"))
    load = ""
    open(checkhome(path), "r") do f
        load = read(f,String)
    end
    return load*"%vtx:$(relhome(path))"
end

function article(str::String,pre::String=preamble()*"\n")
    return pre*"\n\\begin{document}\n"*str*"\n\\end{document}"
end

function dict2toml(data::Dict)
    io = IOBuffer()
    TOML.print(io,data)
    return String(take!(io))
end

toml2dict(toml::String) = TOML.parse(toml)

const regtextag = "[[:alnum:] !\"#\$%&'()*+,\\-.\\/:;<=>?@\\[\\]^_`|~]+"

function textagdel(tag::Symbol,tex::String)
    join(split(tex,Regex("\n?(\\\\$tag{)"*regtextag*"(})")))
end

function texlocate(tag::Symbol,tex::String,neg::String="none")
    out = collect((m.match for m = eachmatch(Regex("(?<=\\\\$tag{)"*regtextag*"(?=})"), tex)))
    return isempty(out) ? [neg] : join.(out)
end

tomlocate(tag::String,data::Dict,neg::String="none") = haskey(data,tag) ? data[tag] : neg

function tex2dict(tex::String,data=nothing)
    tim = Dates.unix2datetime(time())
    (pre,doc) = String.(split(split(tex,"\n\\end{document}")[1],"\n\\begin{document}\n"))
    author = texlocate(:author,pre,"unknown")[1]
    date = texlocate(:date,pre,"unknown")[1]
    title = texlocate(:title,pre,"unknown")[1]
    for item ∈ [:author,:date,:title]
        pre = textagdel(item,pre)
    end
    prereg = "%vtx:"*regtextag*"\n?"
    occursin(Regex(prereg),pre) && (pre = match(Regex("(?:"*prereg*")\\X+"),pre).match)
    pre = replace(pre,r"\n+$"=>"")
    out = deepcopy(data)
    if data == nothing
        out = Dict(
            "editor" => AUTHOR,
            "author" => author,
            "pre" => pre,
            "tex" => doc,
            "date" => date,
            "title" => title,
            "created" => "$tim",
            "revised" => "$tim",
            "uuid" => "$(UUIDs.uuid1())",
            "version" => ["VerTeX", "v\"0.1.0\""],
            "ids" => Dict())
    else
        out["editor"] = AUTHOR
        out["author"] = author
        out["pre"] = pre
        out["tex"] = doc
        out["date"] = date
        out["title"] = title
        out["revised"] = "$tim"
    end
    items = ["ref","cite","label","deps"] # "refby", "citeby", "depsby"
    for item ∈ items
        temp = texlocate(Symbol(item),doc)
        if temp ≠ ["none"]
            haskey(out,item) ? (out[item] = temp) : push!(out,item=>temp)
        else
            haskey(out,item) && pop!(out,item)
        end
    end
    for cat ∈ ["ref","deps"]
        haskey(out,cat) && for ref in out[cat]
            if haskey(out["ids"],ref)
                !checkuuid(out["ids"][ref]...,ref) && updateref!(out,ref)
            else
                updateref!(out,ref)
            end
        end
    end
    haskey(out,"label") && for lbl in out["label"]
        for cat ∈ [:ref,:deps]
            result = searchvtx([cat],[lbl])
            for v ∈ result
                updaterefby!(out,v;cat="$(cat)by")
            end
        end
    end
    for cat ∈ ["refby","depsby"]
        haskey(out,cat) && isempty(out[cat]) && pop!(out,cat)
    end
    for key in keys(out["ids"])
        found = false
        for item ∈ ["cite","deps","ref"]
            haskey(out,item) && (key ∈ out[item]) && (found = true)
        end
        (key == out["author"]) && (found = true)
        !found && pop!(out["ids"],key)
    end
    return out::Dict
end

function checkuuid(uuid::String,depot::String,dir::String,label::String)
    repodat = getdepot()
    !haskey(repodat,depot) && (return false)
    !isfile(joinpath(checkhome(repodat[depot]),dir)) && (return false)
    dat = load(dir,depot)
    uuid ≠ dat["uuid"] && (return false)
    return haskey(dat,"label") && (label in dat["label"])
end

function updateref!(out,ref,cat::Symbol=:label)
    result = searchvtx([cat],[ref])
    length(result) ≠ 1 && (@warn "could not find label $ref"; return out)
    give = ref => [result[1]["uuid"],result[1]["depot"],result[1]["dir"]]
    haskey(out["ids"],ref) ? (out["ids"][ref] = give) : push!(out["ids"],give)
    return out
end

function updaterefby!(out,v;remove=false,cat::String="refby")
    n = [v["uuid"],v["depot"],v["dir"]]
    if haskey(out,cat)
        amt = length(out[cat])
        k = 1
        while k ≤ amt
            if out[cat][k][1] == v["uuid"]
                deleteat!(out[cat],k)
                amt -= 1
            else
                k += 1
            end
        end
        !remove && push!(out[cat],n)
        isempty(out[cat]) && pop!(out,cat)
    else
        !remove && push!(out,"refby"=>[n])
    end
    
end

function dict2tex(data::Dict)
    pre = tomlocate("pre",data)
    doc = tomlocate("tex",data)
    author = tomlocate("author",data,"unknown")
    date = tomlocate("date",data,"unknown")
    title = tomlocate("title",data,"unknown")
    reg = "^%vtx:"*regtextag
    if occursin(Regex(reg*"\n?"),pre)
        file = match(Regex("(?<=%vtx:)"*regtextag*"(?<=\n)?"),pre).match
        pre = preamble(join(file))*replace(pre,Regex(reg)=>"")
    end
    tex = pre*"\n"
    author ≠ "unknown" && (tex *= "\n\\author{$author}")
    date ≠ "unknown" && (tex *= "\n\\date{$date}")
    title ≠ "unknown" && (tex *= "\n\\title{$title}")
    return article(doc,tex)
end

toml2tex(toml::String) = dict2tex(TOML.parse(toml))
tex2toml(tex::String) = dict2toml(tex2dict(tex))

include("depot.jl")
include("search.jl")

end # module
