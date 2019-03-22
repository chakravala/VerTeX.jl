using VerTeX
using Test

# write your own tests here
@test (x = VerTeX.article("",VerTeX.preamble()*"\\author{x}\n\\date{x}\n\\title{x}\n"); typeof(x) == typeof(VerTeX.dict2tex(VerTeX.tex2dict(x))))
