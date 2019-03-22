
#   This file is part of VerTeX.jl. It is licensed under the MIT license
#   Copyright (C) 2019 Michael Reed

import ..load, ..save, ..checkmerge, ..writetex, ..tex2dict, ..save, ..article

export zathura, latexmk, pdf, texedit

zathura(f::String,o=stdout) = run(`zathura $f`,(devnull,o,stderr),wait=false)
latexmk(f::String,o=stdout) = run(`latexmk -silent -pdf -cd $f`)

function showpdf(str::String)
    try
        latexmk(str,devnull)
    catch
    end
    zathura(replace(str,r".tex$"=>".pdf"))
end

function pdf(str::String,file::String="doc")
    open("/tmp/$file.tex", "w") do f
        write(f, article(str))
    end
    showpdf("/tmp/$file.tex")
end

pdf(data::Dict) = showpdf(VerTeX.writetex(data))

function texedit(data::Dict,file::String="/tmp/doc.tex")
    haskey(data,"dir") && (file == "/tmp/doc.tex") && (file = data["dir"])
    try
        old = load(file,haskey(data,"depot") ? data["depot"] : "julia")
        if (old ≠ nothing)
            cmv = checkmerge(data["revised"],old,data["title"],data["author"],data["date"],data["tex"],"Memory buffer out of sync with vertex, proceed?")
            if cmv == 0
                throw(error("VerTeX unable to proceed due to merge failure"))
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
            ret = tex2dict(VerTeX.readtex(load),data)
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
        v = save(tex2dict(article(str)),file)
    end
    return texedit(v,file)
end
