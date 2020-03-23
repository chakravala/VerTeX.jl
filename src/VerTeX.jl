__precompile__()
module VerTeX

#   This file is part of VerTeX.jl. It is licensed under the MIT license
#   Copyright (C) 2018 Michael Reed

export dict2toml, tex2dict, tex2toml, dict2tex, toml2tex, toml2dict
export zathura, latexmk, pdf, texedit

using Pkg, UUIDs, Dates, REPL, Requires
using Pkg.TOML, REPL.TerminalMenus
VERSION < v"1.4" && (using Pkg.Pkg2)

function drawgraph end

global AUTHOR = "anonymous"

checkhome(path::String) = occursin(r"^~/",path) ? joinpath(homedir(),path[3:end]) : path

function relhome(path::String,home::String=homedir())
    reg = Regex("(?<=^$(replace(home,'/'=>"\\/")))\\/?\\X+")
    return occursin(reg,path) ? '~'*match(reg,path).match : path
end

function preamble(path::String="default.tex",repo::String="julia")
    depos = getdepot()
    !haskey(depos,repo) && throw(error("did not load preamble, $repo depot not found"))
    load = ""
    try
        open(joinpath(checkhome(depos[repo]),path), "r") do f
            load = read(f,String)
        end
    catch
        open(joinpath("..","vtx",path), "r") do f
            load = read(f,String)
        end
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


preview_vertex(title,author,date,doc) = @info "$title by $author ($date)\n$doc"
preview_vertex(data::Dict) = preview_vertex(data["title"],data["author"],data["date"],data["tex"])

function checkmerge(a::DateTime,data,title,author,date,doc,msg="Merge conflict detected, proceed?")
    val = 2
    errors = ["",""]
    if a ≠ DateTime(data["revised"])
        errors[1] = "VerTeX: unable to merge into \"$(data["dir"])\" ($(data["revised"]))"
        errors[2] = "BUFFER: invalid date stamp $a"
    end
    if errors ≠ ["",""]
        @warn "$(errors[1])"
        preview_vertex(data)
        @warn "$(errors[2])"
        preview_vertex(title,author,date,doc)
        val = request(msg,RadioMenu(["skip / discard","merge / replace"]))
    end
    return val
end

checkmerge(a::String,data,title,author,date,doc,msg="Merge conflict detected, proceed?") = checkmerge(DateTime(a),data,title,author,date,doc,msg)

function tex2dict(tex::String,data=nothing,disp=false,sav::Array=[])
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
    prereg = "%vtx:"*regtextag*"\n?"
    occursin(Regex(prereg),pre) && (pre = match(Regex("(?:"*prereg*")\\X+"),pre).match)
    pre = replace(pre,r"\n+$"=>"")
    ## date check
    docre = rsplit(doc,"%rev:";limit=2)
    if (length(docre) == 1)
        docdc = tim
    elseif occursin(r"%vtx:",docre[2])
        docdc = tim
    else
        doc = docre[1]
        docdc = DateTime(match(Regex(regtextag*"(?<=\n)?"),docre[2]).match)
    end
    out = deepcopy(data)
    if (data ≠ nothing)
        cmv = checkmerge(docdc,data,title,author,date,doc)
        if cmv == 0
            throw(error("VerTeX unable to proceed due to merge failure"))
        elseif cmv < 2
            doc = preload(data,true,false)
            author = data["author"]
            date = data["date"]
            title = data["title"]
            pre = data["pre"]
        end
    end
    ## deconstruct VerTeX
    cp = split(doc,r"%extend:((true)|(false))\n?";limit=2)
    choice = match(r"(?<=%extend:)((true)|(false))(?=\n)?",doc)
    extend = choice ≠ nothing ? Meta.parse(choice.match) : true
    compact = !occursin(r"%vtx:",cp[1]) && !((length(cp) > 1) ? extend : true)
    remdoc = ""
    if compact
        doc = cp[1]
    elseif choice ≠ nothing
        remdoc = "$(cp[2])\n"
        if occursin(r"%vtx:",cp[1])
            doc = split(cp[1],r"%vtx:")[1]
        else
            doc = cp[1]
        end
    else
        remdoc = "$doc\n"
        doc = split(doc,Regex(prereg);limit=2)[1]
    end
    occursin(r"%vtx:",cp[1]) && (remdoc = match(Regex(prereg*"\\X+"),docre[1]).match)
    doc = join(chomp(doc))
    if |(([author,date,title] .== unk)...)
        @info "Missing VerTeX metadata for $uid"
        println(disp ? (data ≠ nothing ? data["tex"] : doc) : doc)
        println("%rev:",disp ? (data ≠ nothing ? data["revised"] : tim) : tim)
        print("title: ")
        title == unk ? (title = readline()) : println(title)
        print("author: ")
        author == unk ? (author = readline()) : println(author)
        print("date: ")
        date == unk ? (date = readline()) : println(date)
    end
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
            "compact" => "$compact") #twins
    else
        setval!(out,"editor",AUTHOR)
        setval!(out,"author",author)
        setval!(out,"pre",pre)
        setval!(out,"tex",doc)
        setval!(out,"date",date)
        setval!(out,"title",title)
        setval!(out,"edit","$tim")
        setval!(out,"compact","$compact")
    end
    ## parse additional vertices
    extra = []
    comments = []
    (data ≠ nothing) && haskey(data,"save") && (sav = data["save"]) #push!(sav,data["save"])
    haskey(out,"show") && pop!(out,"show")
    haskey(out,"comments") && pop!(out,"comments")
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
                for s ∈ sav
                    if haskey(s,"depot") && haskey(s,"dir") &&
                            s["depot"] == depo && s["dir"] == file
                        ods = s
                        break
                    end
                end
                ods == nothing && (ods = load(file,depo))
                add2q = DateTime(ods["revised"]) == dc && ods["tex"] ≠ join(chomp(re[1]))
                # check date and compare if opened
                # terminal menu if date is not a mach
            catch
            end
            ds = tex2dict(pre*"\n\\begin{document}\n"*sp[2]*"\n\\end{document}",ods,!add2q,sav)
            push!(extra,repr(!Meta.parse(ds["compact"])))
            addval!(out,"show",[ds["uuid"],depo,file])
            #addkey!(out,"ids",ds["uuid"],[ds["uuid"], depo, file])
            # add to save queue, for when actual save happens
            !haskey(ds,"dir") && setval!(ds,"dir",file)
            !haskey(ds,"depot") && setval!(ds,"depot",depo)
            ins = 0
            haskey(out,"save") && for k ∈ 1:length(out["save"])
                out["save"][k]["uuid"] == ds["uuid"] && (ins = k; break)
            end
            add2q && (ins > 0 ? (out["save"][ins] = ds) : addval!(out,"save",ds))
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
    items = [bins...,"cite","label"] # "refby", "citeby", "depsby"
    # update referral lists
    for item ∈ items
        temp = [(item == "label" ? lbllocate(doc) : []); texlocate(Symbol(item),doc)]
        if temp ≠ ["none"]
            setval!(out,item,temp)
        else
            haskey(out,item) && pop!(out,item)
        end
    end
    return out::Dict
end

function preload(data::Dict,extend::Bool,rev::Bool=true)
    doc = tomlocate("tex",data)*"\n"
    if extend && haskey(data,"comments") && length(data["comments"]) > 0
        shift = 0
        ls = haskey(data,"show") ? length(data["show"]) : 0
        if length(data["comments"]) ≠ ls
            if data["comments"][1] ≠ ""
                doc *= "%extend:true\n$(data["comments"][1])\n"
            else
            end
            shift += 1
        end
        if ls > 0
            for k ∈ 1:ls
                key = data["show"][k]
                ta = ""
                try
                    da = nothing
                    haskey(data,"save") && for s ∈ data["save"]
                        s["uuid"] == key[1] && (da = s; break)
                    end
                    da == nothing && (da = load(key[3],key[2]))
                    ta = preload(da,Meta.parse(data["extend"][k]))
                catch
                    @warn "could not load $(key[3]) from $(key[2])"
                end
                dep = data["depot"] ≠ "julia" ? "$(data["depot"]):~:" : ""
                vtx = "%vtx:$dep$(key[3])\n"
                doc *= join([vtx,ta,"\n",vtx,data["comments"][k+shift]])
            end
        end
    end
    return rev ? "$doc%rev:$(data["revised"])" : join(chomp(doc))
end

function dict2tex(data::Dict)
    unk = "unknown"
    pre = tomlocate("pre",data)
    author = tomlocate("author",data,unk)
    date = tomlocate("date",data,unk)
    title = tomlocate("title",data,unk)
    dep = (haskey(data,"depot") && (data["depot"] ≠ "julia")) ? "$(data["depot"]):~:" : ""
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
include("repl.jl")

function __init__()
    haskey(ENV,"AUTHOR") && (global AUTHOR = ENV["AUTHOR"])
    # load manifest and dictionary at ini
    readmanifest()
    readdictionary()
    # save manifest and dictionary at end
    atexit(() -> (writemanifest(); writedictionary()))
    if isdefined(Base, :active_repl)
        REPLMode.repl_init(Base.active_repl)
    else
        atreplinit() do repl
            if isinteractive() && repl isa REPL.LineEditREPL
                isdefined(repl, :interface) || (repl.interface = REPL.setup_interface(repl))
                REPLMode.repl_init(repl)
            end
        end
    end
    @require LightGraphs="093fc24a-ae57-5d10-9952-331d41423f4d" begin
        import LightGraphs
        function makegraph(manifest=manifest,dictionary=dictionary,index=collect(keys(dictionary)))
            readmanifest()
            readdictionary()
            g = LightGraphs.SimpleDiGraph(length(index))
            for i ∈ 1:length(index)
                key = collect(values(dictionary[index[i]]))[1]
                more = manifest[key[2]][key[1]]
                if haskey(more,"deps")
                    for dep ∈ more["deps"]
                        f = findall(index .== split(dep,':')[1])
                        !isempty(f) && LightGraphs.add_edge!(g,f[1],i)
                    end
                end
            end
            return g
        end
    end
    #@require GraphPlot="a2cc645c-3eea-5389-862e-a155d0052231"
    @require Compose="a81c6b42-2e10-5240-aca2-a61377ecd94b" begin
        import LightGraphs, Cairo, GraphPlot
        function drawgraph(name="/tmp/vtx-data.pdf",manifest=manifest,dictionary=dictionary,index=collect(keys(dictionary)))
            Compose.draw(Compose.PDF(name,32Compose.cm,32Compose.cm),GraphPlot.gplot(makegraph(manifest,dictionary,index),nodelabel=index,layout=GraphPlot.circular_layout))
        end
    end
end

end # module
