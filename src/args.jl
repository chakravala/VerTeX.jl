
#   This file is part of VerTeX.jl. It is licensed under the MIT license
#   Copyright (C) 2019 Michael Reed

import ..load, ..save, ..checkmerge, ..readtex, ..writetex, ..tex2dict, ..save, ..article, ..manifest, ..readmanifest, ..getdepot, ..readdictionary, ..dictionary

using TerminalMenus

export zathura, latexmk, pdf, texedit

zathura(f::String,o=stdout) = run(`zathura $f`,(devnull,o,stderr),wait=false)
latexmk(f::String,o=stdout) = run(`latexmk -silent -pdf -cd $f`)

function showpdf(str::String,o=stdout)
    try
        latexmk(str,o)
    catch
    end
    zathura(replace(str,r".tex$"=>".pdf"),o)
end

function pdf(str::String,file::String="doc")
    open("/tmp/$file.tex", "w") do f
        write(f, article(str))
    end
    showpdf("/tmp/$file.tex")
end

pdf(data::Dict,o=stdout) = showpdf(writetex(data),o)

function texedit(data::Dict,file::String="/tmp/doc.tex")
    haskey(data,"dir") && (file == "/tmp/doc.tex") && (file = data["dir"])
    try
        old = load(file,haskey(data,"depot") ? data["depot"] : "julia")
        if (old ≠ nothing)
            cmv = checkmerge(data["revised"],old,data["title"],data["author"],data["date"],data["tex"],"Memory buffer out of sync with vertex, proceed?")
            if cmv == 0
                vtxerror("VerTeX unable to proceed due to merge failure")
            elseif cmv < 2
                @warn "merged into buffer from $path"
                data = old
            end
        end
    catch err
        throw(err)
    end
    try
        load = writetex(data,file)
        run(`vim --servername julia $load`)
        try
            ret = tex2dict(readtex(load),data)
            return load == file ? ret : save(ret,file)
        catch
            return save(data,file)
        end
    catch err
        throw(err)
    end
end

function texedit(file::String="/tmp/doc.tex")
    v = nothing
    try
        v = load(file)
    catch
        r = request("$file not found, create?",RadioMenu(["cancel","save"]))
        r == 1 && (return nothing)
        v = save(tex2dict(article("")),file)
    end
    return texedit(v,file)
end

function display_manifest(repo)
    readmanifest()
    for x ∈ manifest["julia"]
        data = x[2]
        @info "$(data["dir"])"
    end
end

function display_manifest()
    readmanifest()
    g = getdepot()
    for key ∈ keys(g)
        @info "$key ∈ $(g[key])"
    end
end

function display_dictionary()
    readdictionary()
    for key ∈ keys(dictionary)
        x = dictionary[key]
        @info "$key => $(join(["$(x[k][3]) ∈ $(x[k][2])" for k ∈ keys(x)],", "))"
    end
end
