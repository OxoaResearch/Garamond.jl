#################################################################
# Utils for interfacing with StringAnalysis.jl and Languages.jl #
#################################################################

# Printer for StringAnalysis metadata
titleize(str::AbstractString) = begin
    join(map(uppercasefirst, strip.(split(str, "."))), ". ","")
end


show(io::IO, md::StringAnalysis.DocumentMetadata) = begin
    printstyled(io, "$(md.id)-[", color=:light_black)
    printstyled(io, "\"$(titleize(md.name))\"",
                    " by $(titlecase(md.author)),",
                    " $(md.edition_year)",
                    " ($(md.published_year))]")
end


# Converts a String to Languages.Language (using STR_TO_LANG)
convert(::Type{L}, lang::S) where {L<:Languages.Language, S<:AbstractString} =
    get(STR_TO_LANG, strip(lower(lang)), Languages.English())

# Converts Languages.Language to String (using LANG_TO_STR)
convert(::Type{S}, lang::L) where {L<:Languages.Language, S<:AbstractString} =
	get(LANG_TO_STR, lang, "unknown")

# Convert a StringAnalysis metadata structure to a Dict
convert(::Type{Dict}, md::StringAnalysis.DocumentMetadata) =
    Dict{String,String}((String(field) => getfield(md, field))
                         for field in fieldnames(StringAnalysis.DocumentMetadata))


# Medatadata getter for documents
metadata(document::D) where {D<:AbstractDocument} =
    document.metadata


metadata(crps::C) where {C<:StringAnalysis.Corpus} =
    [doc.metadata for doc in crps]


# Turn the document metadata into a vector of strings
function meta2sv(md::T, fields=fieldnames(T)
                ) where T<:StringAnalysis.DocumentMetadata
    msv = ["" for _ in 1:length(fields)]
    for (i, field) in enumerate(fields)
        if field in fieldnames(T)
            if field != :language
                msv[i] = getfield(md, field)
            else
                msv[i] = LANG_TO_STR[getfield(md, field)]
            end
        end
    end
    filter!(!isempty, msv)
    return msv
end



##########################################
# String utilities: constants, functions #
##########################################

# Overload ismatch to work matching any value within a vector
occursin(r::Regex, strings::T) where T<:AbstractArray{<:AbstractString} = 
    any(occursin(r, si) for si in sv);


# Overload lowervase function to work with vectors of strings
lowercase(v::T) where T<:AbstractArray{S} where S<:AbstractString =
    Base.lowercase.(v)



"""
    prepare(text, flags [;kwargs...])

Processes a string according to the `flags` which are an `UInt32` of
the form used in `StringAnalysis.jl` ie `strip_numbers | strip_articles` etc.
and the keyword arguments are thos of the `Unicode.normalize` function.
"""
# TODO TODO TODO! Improve this crap
function prepare(text::AbstractString, flags::UInt32;
                 compat=true,
                 casefold=true,
                 stripmark=true,
                 stripignore=true,
                 stripcc=true,
                 stable=true,
                 kwargs...
                )
    sd = StringDocument(Unicode.normalize(text, compat=compat,
                                          casefold=casefold, stripmark=stripmark,
                                          stripignore=stripignore, stripcc=stripcc,
                                          stable=stable,kwargs...))
    sdc = Base.deepcopy(sd)
    prepare!(sdc, flags)
    return sdc.text
end



"""
    stem(text, flags [;kwargs...])

"""
function stem(text::AbstractString)
    sd = StringDocument(text)
    stem!(sd)
    return sd.text
end



"""
    preprocess(sentence, flags [;isprepared=false, isstemmed=true])

Applies preprocessing to one sentence considered to be an
AbstractString.
"""
function preprocess(sentence::AbstractString,
                    flags::UInt32;
                    isprepared::Bool=false,
                    isstemmed::Bool=true)
    # Prepare
    if !isprepared
        sentence = prepare(sentence, flags)
    end
    # Stemming
    if !isstemmed
        sentence = stem(sentence)
    end
    return sentence
end

function preprocess(document::Vector{S},
                    flags::UInt32;
                    isprepared::Bool=false,
                    isstemmed::Bool=true
                   ) where S<:AbstractString
    return [preprocess.(sentence, flags, isprepared=isprepared,
                        isstemmed=isstemmed)
            for sentence in document]
end

function preprocess(documents::Vector{Vector{S}},
                    flags::UInt32;
                    isprepared::Bool=false,
                    isstemmed::Bool=true
                   ) where S<:AbstractString
    return [preprocess(doc, flags, isprepared=isprepared, isstemmed=isstemmed)
            for doc in documents]
end

function preprocess_query(query::AbstractString)
    needles = extract_tokens(Unicode.normalize(query,
                                               casefold=true,
                                               stripcc=true,
                                               stripmark=true))
    return needles
end

function preprocess_query(query::Vector{S}) where S<:AbstractString
    return Unicode.normalize.(query, casefold=true, stripcc=true, stripmark=true)
end



"""
    extract_tokens(doc)

Tokenizes various types of documents. Works for `AbstractString`,
Vector{AbstractString} and `StringAnalysis.jl` documents.
"""
extract_tokens(doc::NGramDocument) = String.(collect(keys(doc.ngrams)))
extract_tokens(doc::StringDocument) = String.(tokenize_for_conceptnet(doc.text))
extract_tokens(doc::AbstractString) = String.(tokenize_for_conceptnet(doc))
extract_tokens(doc::Vector{S}) where S<:AbstractString = String.(doc)



"""
    detect_language(text)

Detects the language of a piece of text.
"""
# TODO(Corneliu) Find a use for this or remove
function detect_language(text::AbstractString)
    detector = LanguageDetector()
    l::Language = detector(text)[1]  # returns (language, script, confidence)
    return l
end



"""
    summarize(sentences [;ns=1, flags=SUMMARIZATION_FLAGS]

Build a summary of the text's `sentences`. The resulting summary will be
a `ns` sentence document; each sentence is pre-procesed using the
`flags` option.
"""
function summarize(sentences::Vector{S};
                   ns::Int=1,
                   flags::UInt32=SUMMARIZATION_FLAGS
                  ) where S<:AbstractString
    # Get document term matrix
    s = StringDocument.(sentences)
    c = Corpus(s)
    prepare!(c, flags)
    update_lexicon!(c)
    t = tf_idf(dtm(c))
    # Page rank
    α = 0.85  # damping factor
    n = 100  # number of iterations
    ϵ = 1.0e-6  # convergence threhshold
    G = Graph(t * t')
    try
        p = pagerank(G, α, n, ϵ)
        # Sort sentences and return
        text_summary = sentences[sort(sortperm(p, rev=true)[1:min(ns, length(p))])]
        return text_summary
    catch
        @warn "Summarization failed during TextRank. No summarization done."
        return sentences
    end
end



"""
    build_corpus(documents, doctype, metadata_vector)

Builds a corpus of documents of type `doctype` using the data in `documents`
and metadata from `metadata_vector`.
"""
function build_corpus(documents::Vector{Vector{S}},
                      doctype::Type{T},
                      metadata_vector::Vector{StringAnalysis.DocumentMetadata}
                     ) where {S<:AbstractString, T<:AbstractDocument}
    @assert length(documents) == length(metadata_vector)
    n = length(documents)
    v = Vector{T}(undef, n)
    @inbounds for i in 1:n
        v[i] = T(join(documents[i]," "))
        v[i].metadata = metadata_vector[i]
    end
    return Corpus(v)
end



### # Useful regular expressions
### replace.(select(tt2,2),r"([A-Z]\s|[A-Z]\.\s)","")  # replace middle initial
### replace.(select(tt2,2),r"[\s]+$","")  # replace end spaces
###
### # Define base filtering functions
###
### remove_punctuation(s) = filter(x->!ispunct(x), s)
###
### remove_singlechars(s) = filter(x->length(x) > 1, s)
###
### split_space_tab(s) = split(s, r"(\s|\t|-)")
###
### normalizer(s) = normalize_string(s, decompose=true, compat=true, casefold=true,
### 				    stripmark=true, stripignore=true)
###
### function searchquery_preprocess(s)
### String.(
###     remove_singlechars(
### 	split_space_tab(
### 		remove_punctuation(
### 			normalizer(s)
### 		)
### 	)
### ))
### end
