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

function preamble(path::String="default.tex",repo::String="julia")
    depos = getdepot()
    !haskey(depos,repo) && throw(error("did not load preamble, $repo depot not found"))
    load = ""
    open(joinpath(checkhome(depos[repo]),path), "r") do f
        load = read(f,String)
    end
    dep = repo ≠ "julia" ? "$repo:~:" : ""
    return load*"%vtx:$dep$(relhome(path))"
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

function lbllocate(tex::String,neg::String="none")
    out = collect((m.match for m = eachmatch(Regex("(?<=\\\\lbl{)"*regtextag*"(}{)"*regtextag*"(?=})"), tex)))
    return isempty(out) ? [neg] : replace.(join.(out), Ref("}{"=>":"))
end

tomlocate(tag::String,data::Dict,neg::String="none") = haskey(data,tag) ? data[tag] : neg

setval!(d::Dict,key,val) = haskey(d,key) ? (d[key] = val) : push!(d,key=>val)
addval!(d::Dict,key,val) = haskey(d,key) ? (val ∉ d[key] && push!(d[key],val)) : push!(d,key=>Any[val])
addkey!(d::Dict,key,val,pair) = !haskey(d[key],val) && push!(d[key],val=>pair)

function tex2dict(tex::String,data=nothing,disp=false)
    tim = Dates.unix2datetime(time())
    uid = UUIDs.uuid1()
    pd = String.(split(split(tex,"\n\\end{document}")[1],"\n\\begin{document}\n"))
    (pre,doc) = length(pd) == 1 ? ["default",pd] : pd
    ## locate identifying info
    unk = "unknown"
    author = texlocate(:author,pre,data ≠ nothing ? data["author"] : unk)[1]
    date = texlocate(:date,pre,data ≠ nothing ? data["date"] : unk)[1]
    title = texlocate(:title,pre,data ≠ nothing ? data["title"] : unk)[1]
    for item ∈ [:author,:date,:title]
        pre = textagdel(item,pre)
    end
    ## date check
    docre = rsplit(doc,"%rev:";limit=2)
    docdc = if (length(docre) == 1)
        tim
    elseif occursin(r"%vtx:",docre[2])
        tim
    else
        doc = docre[1]
        DateTime(match(Regex(regtextag*"(?<=\n)?"),docre[2]).match)
    end
    if (data ≠ nothing) && (docdc ≠ DateTime(data["revised"]))
        throw(error("VerTeX: unable to merge into \"$(data["dir"])\" (last edited on $(data["revised"])), invalid date stamp $docdc\n\ntitle: $title\nauthor: $author\ndate: $date\n\n$doc"))
    end
    ## deconstruct VerTeX
    prereg = "%vtx:"*regtextag*"\n?"
    occursin(Regex(prereg),pre) && (pre = match(Regex("(?:"*prereg*")\\X+"),pre).match)
    pre = replace(pre,r"\n+$"=>"")
    cp = split(doc,r"%extend:((true)|(false))\n?";limit=2)
    choice = match(r"(?<=%extend:)((true)|(false))(?=\n)?",doc)
    extend = choice ≠ nothing ? Meta.parse(choice.match) : true
    compact = !occursin(r"%vtx:",cp[1]) && !((length(cp) > 1) ? extend : true)
    remdoc = ""
    if compact
        doc = cp[1]
    elseif choice ≠ nothing
        remdoc = "$(cp[2])\n"
        doc = cp[1]
    else
        remdoc = "$doc\n"
        doc = split(doc,Regex(prereg);limit=2)[1]
    end
    occursin(r"%vtx:",cp[1]) && (remdoc = match(Regex(prereg*"\\X+"),pd[end]).match)
    doc = join(chomp(doc))
    if |(([author,date,title] .== unk)...)
        @info "Missing VerTeX metadata for $uid"
        println(disp ? data["tex"] : doc)
        println("%rev:",disp ? data["revised"] : tim)
        print("title: ")
        title == unk ? (title = readline()) : println(title)
        print("author: ")
        author == unk ? (author = readline()) : println(author)
        print("date: ")
        date == unk ? (date = readline()) : println(date)
    end
    out = deepcopy(data)
    if out == nothing
        out = Dict(
            "editor" => AUTHOR,
            "author" => author,
            "pre" => pre,
            "tex" => doc,
            "date" => date,
            "title" => title,
            "created" => "$tim",
            "revised" => "$tim",
            "uuid" => "$uid",
            "version" => ["VerTeX", "v\"0.1.0\""],
            "ids" => Dict(),
            "compact" => "$compact") #twins, show, showby
    else
        setval!(out,"editor",AUTHOR)
        setval!(out,"author",author)
        setval!(out,"pre",pre)
        setval!(out,"tex",doc)
        setval!(out,"date",date)
        setval!(out,"title",title)
        setval!(out,"revised","$tim")
        setval!(out,"compact","$compact")
        !haskey(out,"ids") && push!(out,"ids"=>Dict())
    end
    ## parse additional vertices
    extra = []
    comments = []
    if !compact
        while occursin(Regex(prereg),remdoc)
            ms = join.(collect((m.match for m = eachmatch(Regex(prereg),remdoc))))[1]
            sp = split(remdoc,ms;limit=3)
            push!(comments,compact ? "" : join(chomp(sp[1])))
            re = rsplit(sp[2],"%rev:";limit=2)
            dc = length(re) == 1 ? tim : DateTime(match(Regex(regtextag*"(?<=\n)?"),re[2]).match)
            # try to open it, to see if update
            df = split(join(match(Regex("(?<=%vtx:)"*regtextag*"(?<=\n)?"),ms).match),":~:";limit=2)
            file = join(df[end])
            depo = length(df) > 1 ? join(df[1]) : "julia"
            ods = nothing
            add2q = true
            try
                ods = load(file,depo)
                add2q = DateTime(ods["revised"]) == dc && ods["tex"] ≠ chomp(join(re[1]))
                # check date and compare if opened
                # terminal menu if date is not a mach
            catch
            end
            ds = tex2dict(pre*"\n\\begin{document}\n"*sp[2]*"\n\\end{document}",ods,!add2q)
            push!(extra,repr(!Meta.parse(ds["compact"])))
            addval!(out,"show",ds["uuid"])
            addkey!(out,"ids",ds["uuid"],[ds["uuid"], depo, file])
            # add to save queue, for when actual save happens
            add2q && addval!(out,"save",ds)
            remdoc = join(sp[3])
        end
        push!(comments,join(chomp(remdoc)))
        choice == nothing && popfirst!(comments)
        setval!(out,"comments",comments)
        setval!(out,"extend",extra)
    else
        for item ∈ ["show","comments","extend"]
            haskey(out,item) && pop!(out,item)
        end
    end
    ## double check reference nodes
    bins = ["ref","used","deps"]
    items = [bins...,"cite","label","lbl"] # "refby", "citeby", "depsby"
    for it ∈ items
        temp = it == "lbl" ? lbllocate(doc) : texlocate(Symbol(it),doc)
        item = it == "lbl" ? "label" : it
        if temp ≠ ["none"]
            setval!(out,item,temp)
        else
            haskey(out,item) && pop!(out,item)
        end
    end
    for cat ∈ bins
        haskey(out,cat) && for ref in out[cat]
            if haskey(out["ids"],ref)
                !checkuuid(out["ids"][ref]...,ref) && updateref!(out,ref)
            else
                updateref!(out,ref)
            end
        end
    end
    haskey(out,"label") && for lbl in out["label"]
        for cat ∈ [:ref,:deps,:use]
            result = searchvtx([cat],[lbl])
            for v ∈ result
                updaterefby!(out,v;cat="$(cat)by")
            end
        end
    end
    for cat ∈ ([bins...,"show"] .* "by")
        haskey(out,cat) && isempty(out[cat]) && pop!(out,cat)
    end
    for key in keys(out["ids"])
        found = false
        for item ∈ ["cite","show",bins...]
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
    update = true
    if haskey(out,cat)
        amt = length(out[cat])
        k = 1
        while k ≤ amt
            if out[cat][k][1] == n[1]
                if ((out[cat][k][2] ≠ n[2] | out[cat][k][3] ≠ n[3]) | remove)
                    deleteat!(out[cat],k)
                    amt -= 1
                else
                    update = false
                end
            else
                k += 1
            end
        end
        !remove && update && push!(out[cat],n)
        isempty(out[cat]) && pop!(out,cat)
    else
        !remove && update && push!(out,"refby"=>[n])
    end
    return update
end

function preload(data::Dict,extend::Bool)
    doc = tomlocate("tex",data)
    if extend && haskey(data,"comments") && length(data["comments"]) > 0
        shift = 0
        ls = haskey(data,"show") ? length(data["show"]) : 0
        if length(data["comments"]) ≠ ls
            doc *= "\n%extend:true\n$(data["comments"][1])"
            shift += 1
        end
        if ls > 0
            for k ∈ 1:ls
                key = data["show"][k]
                d = data["ids"][key]
                ta = ""
                try
                    ta = preload(load(d[3],d[2]),parse(data["extend"][k]))
                catch
                    @warn "could not load $(d[3]) from $(d[2])"
                end
                dep = data["depot"] ≠ "julia" ? "$(data["depot"]):~:" : ""
                vtx = "\n%vtx:$dep$(d[3])\n"
                doc *= join([vtx,ta,vtx,data["comments"][k+shift]])
            end
        end
    end
    return "$doc\n%rev:$(data["revised"])"
end

function dict2tex(data::Dict)
    unk = "unknown"
    pre = tomlocate("pre",data)
    author = tomlocate("author",data,unk)
    date = tomlocate("date",data,unk)
    title = tomlocate("title",data,unk)
    dep = data["depot"] ≠ "julia" ? "$(data["depot"]):~:" : ""
    reg = "^%vtx:"*regtextag
    if occursin(Regex(reg*"\n?"),pre)
        prereg = "(?<=%vtx:)"*regtextag*"(?<=\n)?"
        df = split(join(match(Regex(prereg),pre).match),":~:";limit=2)
        file = join(df[end])
        depo = length(df) > 1 ? join(df[1]) : "julia"
        pre = preamble(file,depo)*replace(pre,Regex(reg)=>"")
    end
    tex = pre*"\n"
    author ≠ unk && (tex *= "\n\\author{$author}")
    date ≠ unk && (tex *= "\n\\date{$date}")
    title ≠ unk && (tex *= "\n\\title{$title}")
    return article(join(chomp(preload(data,true))),tex)
end

toml2tex(toml::String) = dict2tex(TOML.parse(toml))
tex2toml(tex::String) = dict2toml(tex2dict(tex))

include("depot.jl")
include("search.jl")

end # module
