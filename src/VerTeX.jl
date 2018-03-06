module VerTeX

#   This file is part of VerTeX.jl. It is licensed under the MIT license
#   Copyright (C) 2018 Michael Reed

export dict2toml, tex2dict, tex2toml, dict2tex, toml2tex, toml2dict

using Pkg3.TOML, UUIDs, Dates

AUTHOR = "anonymous"
try
    global AUTHOR = ENV["AUTHOR"]
end

checkhome(path::String) = ismatch(r"^~/",path) ? joinpath(homedir(),path[3:end]) : path

function relhome(path::String,home::String=homedir())
    reg = Regex("(?<=^$(replace(home,'/',"\\/")))\\/?\\X+")
    return ismatch(reg,path) ? '~'*match(reg,path).match : path
end

function preamble(path::String=joinpath(Pkg.dir("JuliaTeX"),"vtx/default.tex"))
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
    out = match(Regex("(?<=\\\\$tag{)"*regtextag*"(?=})"),tex)
    return typeof(out) == Nothing ? neg : out.match
end

tomlocate(tag::String,data::Dict,neg::String="none") = haskey(data,tag) ? data[tag] : neg

function tex2dict(tex::String,data=nothing)
    tim = Dates.unix2datetime(time())
    texs = split(split(tex,"\n\\end{document}")[1],"\n\\begin{document}\n")
    pre = String(texs[1])
    doc = String(texs[2])
    println(pre)
    author = texlocate(:author,pre,"unknown")
    date = texlocate(:date,pre,"unknown")
    title = texlocate(:title,pre,"unknown")
    pre = textagdel(:author,pre)
    pre = textagdel(:date,pre)
    pre = textagdel(:title,pre)
    prereg = "%vtx:"*regtextag*"\n?"
    ismatch(Regex(prereg),pre) && (pre = match(Regex("(?:"*prereg*")\\X+"),pre).match)
    pre = replace(pre,r"\n+$","")
    out = data
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
            "uuid" => "$(UUIDs.uuid1())",
            "version" => ["VerTeX", "v\"0.1.0\""])
    else
        out["editor"] = AUTHOR
        out["author"] = author
        out["pre"] = pre
        out["tex"] = doc
        out["date"] = date
        out["title"] = title
        out["revised"] = "$tim"
    end
    return out::Dict
end

function dict2tex(data::Dict)
    pre = tomlocate("pre",data)
    doc = tomlocate("tex",data)
    author = tomlocate("author",data,"unknown")
    date = tomlocate("date",data,"unknown")
    title = tomlocate("title",data,"unknown")
    reg = "^%vtx:"*regtextag
    if ismatch(Regex(reg*"\n?"),pre)
        file = match(Regex("(?<=%vtx:)"*regtextag*"(?<=\n)?"),pre).match
        pre = preamble(join(file))*replace(pre,Regex(reg),"")
    end
    tex = pre*"\n"
    author ≠ "unknown" && (tex *= "\n\\author{$author}")
    date ≠ "unknown" && (tex *= "\n\\date{$date}")
    title ≠ "unknown" && (tex *= "\n\\title{$title}")
    return article(doc,tex)
end

toml2tex(toml::String) = dict2tex(TOML.parse(toml))
tex2toml(tex::String) = dict2toml(tex2dict(tex))

end # module
