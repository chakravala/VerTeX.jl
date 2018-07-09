export searchvtx

# recursive function for applying search criteria
function keycheck(data::Dict{<:Any,<:Any},str::Array{String,1},mode::Array{Symbol,1})
    found = false
    for key in keys(data)
        if :deps in mode
            for s in str
                (key == s) && (found = true)
            end
        end
        if ((:search in mode) || (Symbol(key) in mode)) && (typeof(data[key]) == String)
            for s in lowercase.(str)
                occursin(s,lowercase(data[key])) && (found = true)
            end
        end
        if (((key == "label") && (:label in mode)) ||
            ((key == "ref") && (:ref in mode)))
            for s in str
                for g in data[key]
                    (g == s) && (found = true)
                end
            end
        end
        if (key ≠ "ids" ) && (typeof(data[key]) <: Dict{<:Any,<:Any})
            keycheck(data[key],str,mode) && (found = true)
        end
    end
    return found
end

# directory search for VerTeX toml
function searchvtx(mode::Array{Symbol,1},str::Array{String,1})
    list = Dict[]
    depos = getdepot()
    for depot in keys(depos)
        for (root, dirs, files) in walkdir(checkhome(depos[depot]))
            for dir in dirs
                for file in readdir(joinpath(root,dir))
                    found = false
                    data = nothing
                    if endswith(file, ".vtx")
                        data = TOML.parsefile(joinpath(root,dir,file))
                        if keycheck(data,str,mode)
                            found = true
                        end
                    end
                    found && push!(list,data)
                end
            end
        end
    end
    return list
end
searchvtx(mode::Symbol,str::String...) = searchvtx([mode],collect(str))
searchvtx(str::String,mode::Symbol...) = searchvtx(collect(mode),[str])
