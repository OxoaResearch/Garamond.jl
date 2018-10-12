#################################################
# Search results objects and associated methods #
#################################################

# Search results from a single corpus
struct CorpusSearchResult
    query_matches::MultiDict{Float64, Int}  # score => document indices
    needle_matches::Dict{String, Int}  # needle => number of matches
    suggestions::MultiDict{String, Tuple{Float64,String}} # needle => tuples of (score,partial match)
end

CorpusSearchResult() = CorpusSearchResult(
    MultiDict{Float64, Int}(),
    Dict{String, Int}(),
    MultiDict{String, Tuple{Float64,String}}()
)



isempty(csr::T) where T<:CorpusSearchResult =
    all(isempty(getfield(csr, field)) for field in fieldnames(T))



# Calculate the length of a MultiDict as the number
# of values considering all keys
valength(md::MultiDict) = begin
    if isempty(md)
        return 0
    else
        return mapreduce(x->length(x[2]), +, md)
    end
end



# Show method
show(io::IO, csr::CorpusSearchResult) = begin
    n = valength(csr.query_matches)
    nm = length(csr.needle_matches)
    ns = length(csr.suggestions)
    printstyled(io, "Search results for a corpus: ")
    printstyled(io, " $n hits, $nm query terms, $ns suggestions.", bold=true)
end



# Pretty printer of results
print_search_results(crps::Corpus, csr::CorpusSearchResult) = begin
    nm = valength(csr.query_matches)
    ns = length(csr.suggestions)
    printstyled("$nm search results")
    ch = ifelse(nm==0, ".", ":"); printstyled("$ch\n")
    for score in sort(collect(keys(csr.query_matches)), rev=true)
        for doc in (crps[i] for i in csr.query_matches[score])
            printstyled("  $score ~ ", color=:normal, bold=true)
            printstyled("$(metadata(doc))\n", color=:normal)
        end
    end
    ns > 0 && printstyled("$ns suggestions:\n")
    for (keyword, suggestions) in csr.suggestions
        printstyled("  \"$keyword\": ", color=:normal, bold=true)
        printstyled("$(join(map(x->x[2], suggestions), ", "))\n", color=:normal)
    end
end


# Search results for multiple corpora
struct CorporaSearchResult{T}
    corpus_results::Dict{T, CorpusSearchResult}  # Dict(score=>metadata)
    suggestions::MultiDict{String, String}
end

CorporaSearchResult{T}() where T<:AbstractId =
    CorporaSearchResult(
        Dict{T, CorpusSearchResult}(),
        MultiDict{String, String}()
)

CorporaSearchResult() = CorporaSearchResult{HashId}()



isempty(csr::T) where T<:CorporaSearchResult =
    all(isempty(getfield(csr, field)) for field in fieldnames(T))



# Show method
show(io::IO, csr::CorporaSearchResult) = begin
    nt = mapreduce(x->valength(x[2].query_matches), +, csr.corpus_results)
    matched_needles = unique(collect(needle for (_, _result) in csr.corpus_results
                                     for needle in keys(_result.needle_matches)))
    nmt = length(matched_needles)
    nst = length(csr.suggestions)
    printstyled(io, "Search results for $(length(csr.corpus_results)) corpora: ")
    printstyled(io, "$nt hits, $nmt query terms, $nst suggestions.\n", bold=true)
    for (_hash, _result) in csr.corpus_results
        n = valength(_result.query_matches)
        nm = length(_result.needle_matches)
        ns = length(_result.suggestions)
        printstyled(io, "`-[$_hash] ", color=:cyan)  # hash
        printstyled(io, "$n hits, $nm query terms, $ns suggestions\n")
    end
end



# Pretty printer of results
print_search_results(corpora::Corpora, csr::CorporaSearchResult) = begin
    nt = mapreduce(x->valength(x[2].query_matches), +, csr.corpus_results)
    printstyled("$nt search results from $(length(csr.corpus_results)) corpora\n")
    ns = length(csr.suggestions)
    for (_hash, _result) in csr.corpus_results
        crps = corpora.corpus[_hash]
        nm = valength(_result.query_matches)
        printstyled("`-[$_hash] ", color=:cyan)  # hash
        printstyled("$(nm) search results")
        ch = ifelse(nm==0, ".", ":"); printstyled("$ch\n")
        for score in sort(collect(keys(_result.query_matches)), rev=true)
            for doc in (crps[i] for i in _result.query_matches[score])
                printstyled("  $score ~ ", color=:normal, bold=true)
                printstyled("$(metadata(doc))\n", color=:normal)
            end
        end
    end
    ns > 0 && printstyled("$ns suggestions:\n")
    for (keyword, suggestions) in csr.suggestions
        printstyled("  \"$keyword\": ", color=:normal, bold=true)
        printstyled("$(join(suggestions, ", "))\n", color=:normal)
    end
end



# Push method (useful for inserting Corpus search results
# into Corpora search results)
function push!(csr::CorporaSearchResult{T},
               sr::Pair{T, CorpusSearchResult}) where T<:AbstractId
    push!(csr.corpus_results, sr)
    return csr
end



# Update suggestions for multiple corpora search results
function update_suggestions!(csr::CorporaSearchResult{T},
                             max_suggestions::Int=1) where T<:AbstractId
    # Quickly exit if no suggestions are sought
    max_suggestions <=0 && return MultiDict{String, String}()
    if length(csr.corpus_results) > 1
        # Results from multiple corpora, suggestions have to
        # be processed somewhat:
        #  - keep only needles not found across all corpora
        #  - remove suggestions that correspond to found needles

        # Get the needles not found across all corpus results
        corpus_results = values(csr.corpus_results)
        matched_needles = (needle for _result in corpus_results
                           for needle in keys(_result.needle_matches))
        missed_needles = intersect((keys(_result.suggestions)
                                    for _result in corpus_results)...)
        # Construct suggestions for the whole Corpora
        for needle in missed_needles
            _tmpvec = Vector{Tuple{Float64,String}}()
            for _result in corpus_results
                if needle in keys(_result.suggestions) &&
                   !(any(suggestion in matched_needles
                         for (_, suggestion) in _result.suggestions[needle]))
                   # Current key was not found and the suggestions
                   # for it are not found in the matched needles
                    _tmpvec = vcat(_tmpvec, _result.suggestions[needle])
                end
            end
            if !isempty(_tmpvec)
                sort!(_tmpvec, by=x->x[1])  # sort vector of tuples by distance
                # Keep results with the same distance even if the number is
                # larger than the maximum
                n = min(max_suggestions, length(_tmpvec))
                nn = 0
                d = -1.0
                for (i, (dist, _)) in enumerate(_tmpvec)
                    if i <= n || d == dist
                        d = dist
                        nn = i
                    end
                end
                push!(csr.suggestions, needle=>map(x->x[2],_tmpvec)[1:nn])
            end
        end
    else
        # Results from one corpus, easy situation, just copy the suggestions
        for (_, _result) in csr.corpus_results
            for (needle, vs) in _result.suggestions
                # vs is a Vector{Tuple{Float64, String}},
                # sorted by distance i.e. the float
                for v in vs
                    push!(csr.suggestions, needle=>v[2])
                end
            end
        end
    end
    return csr
end



##################
# Search methods #
##################

# Remarks:
#  - the configuration searchmethod == :exact with search_type==:metadata is NOT
#  to be used as the metadata contains compound expressions which the exact method cannot match

# Function that searches through several corpora
function search(crpra::AbstractCorpora,
                needles::Vector{String};
                search_type::Symbol=DEFAULT_SEARCH_TYPE,
                search_method::Symbol=DEFAULT_SEARCH_METHOD,
                max_matches::Int=DEFAULT_MAX_MATCHES,
                max_suggestions::Int=DEFAULT_MAX_SUGGESTIONS,
                max_corpus_suggestions::Int=DEFAULT_MAX_CORPUS_SUGGESTIONS)
    result = CorporaSearchResult()
    n = length(crpra.corpus)
    max_corpus_suggestions = min(max_suggestions, max_corpus_suggestions)
    # Search
    for (_hash, crps) in crpra.corpus
        if crpra.enabled[_hash]
            _result = search(crps,
                             needles,
                             index=crpra.index[_hash],
                             search_trees=crpra.search_trees[_hash],
                             search_type=search_type,
                             search_method=search_method,
                             max_matches=max_matches,
                             max_suggestions=max_corpus_suggestions)
            push!(result, _hash=>_result)
        end
    end
    !isempty(result) && update_suggestions!(result, max_suggestions)
    return result
end



"""
	search(crps, needles [;kwargs])

Searches for needles (i.e. key terms) in a corpus' metadata, text or both and 
returns the documents that match best the query. The function returns a 
vector of dictionaries representing the metadata of the best matching
documents.

# Arguments
  * `crps::Corpus{T}` is the text corpus
  * `needles::Vector{String}` is a vector of key terms representing the query

# Keyword arguments
  * `index::Dict{Symbol, Dict{String, Vector{Int}}}` document ans metadata reverse index
  * `search_trees::Dict{Symbol, BKTree{String}}` search trees used for approximate
     string matching i.e. for suggestion generation
  * `search_type::Symbol` is the type of the search; can be `:metadata` (default),
     `:index` or `:all`; the options specify that the needles can be found in
     the metadata of the documents of the corpus, their inverse index or both 
     respectively
  * `search_method::Symbol` controls the type of matching: `:exact` (default)
     searches for the very same string while `:regex` searches for a string
     in the corpus that includes the needle
  * `max_matches::Int` is the maximum number of search results to return
  * `max_suggestions::Int` is the maximum number of suggestions to return for
     each missing needle

# Examples
```
	...
```
"""
# Function that searches in a corpus'a metdata or metadata + content for needles (i.e. keyterms) 
function search(crps::Corpus{D},
                needles::Vector{String};
                index::Dict{Symbol, Dict{String, Vector{Int}}}=
                    Dict{Symbol, Dict{String, Vector{Int}}}(),
                search_trees::Dict{Symbol,BKTree{String}}=Dict{Symbol,BKTree{String}}(),
                search_type::Symbol=:metadata,
                search_method::Symbol=:exact,
                max_matches::Int=10,
                max_suggestions::Int=DEFAULT_MAX_CORPUS_SUGGESTIONS
               ) where {D<:AbstractDocument}
    # Checks
    @assert search_type in [:index, :metadata, :all]
    @assert search_method in [:exact, :regex]
    # Initializations
    n = length(crps)		# Number of documents
    p = length(needles)		# Number of search terms
    local dtm::SparseMatrixCSC{Float64, Int64}
	# Search
    if search_type != :all
        dtm = search_index(index[search_type], needles, n_docs=n, search_method=search_method)
    else
        dtm = search_index(index[:index], needles, n_docs=n, search_method=search_method) +
              search_index(index[:metadata], needles, n_docs=n, search_method=search_method)
    end
    # Process finds
    document_scores = zeros(Float64, n)
    needle_popularity = zeros(Float64, p)
    @inbounds @simd for j in 1:p
         for i in 1:n
            if dtm[i,j] != 0
                document_scores[i]+= dtm[i,j]
                needle_popularity[j]+= dtm[i,j]
            end
        end
    end
    # Sort result by score
    ordered_docs::Vector{Tuple{Float64, Int}} =
        [(score, i) for (i, score) in enumerate(document_scores) if score > 0]
    sort!(ordered_docs, by=x->x[1], rev=true)
    needle_matches = Dict(needle=>needle_popularity[i]
                          for (i, needle) in enumerate(needles)
                          if needle_popularity[i] > 0)
    query_matches = MultiDict{Float64, Int}()
    @inbounds for i in 1:min(max_matches, length(ordered_docs))
        push!(query_matches, document_scores[ordered_docs[i][2]]=>ordered_docs[i][2])
    end
    # Try to partially match needles that were not found
    needles_not_found = needles[needle_popularity.== 0]
    if search_type != :all
        suggestions = search_heuristically(search_trees[search_type],
                                           needles_not_found,
                                           max_suggestions=max_suggestions)
    else
        # Get suggestions from both index and metadata
        suggestions = MultiDict{String, Tuple{Float64,String}}(
            search_heuristically(search_trees[:index],
                                 needles_not_found,
                                 max_suggestions=max_suggestions)...,
            search_heuristically(search_trees[:metadata],
                                 needles_not_found,
                                 max_suggestions=max_suggestions)...
        )
    end
    return CorpusSearchResult(query_matches, needle_matches, suggestions)
end



"""
	Search function for searching an inverse index associated to a corpus.
"""
function search_index(index::Dict{String, Vector{Int}},
                      needles::Vector{String};
                      n_docs::Int=0,
                      search_method::Symbol=:exact,
                     ) where {T<:AbstractDocument}
    # Initializations
    @assert n_docs > 0 "Number of documents has to be > 0."
    p = length(needles)
    matches = spzeros(Float64, n_docs, p)
    # Get needle mutating and string matching functions
    if search_method == :exact
        needle_mutator = identity
        matching_function = isequal
    else  # search_method == :regex
        needle_mutator = (arg::String)->Regex(arg)
        matching_function = occursin
    end
    # Mutate needles 
    patterns = needle_mutator.(needles)
    # Check that inverse index exists
    @assert !isempty(index) "FATAL: The index is empty."
    # Search
    haystack = (k for k in keys(index))
    empty_vector = Int[]
    for (j, pattern) in enumerate(patterns)
        if search_method == :exact
            idxs = get(index, pattern, empty_vector) # fast!!
            @inbounds @simd for i in idxs
                matches[i,j]+= 1.0
            end
        else
            # search_method==:regex
            for k in haystack
                if matching_function(pattern, k)
                    @inbounds @simd for i in index[k]
                        matches[i,j]+= 1.0
                    end
                end
            end
        end
    end
    return matches 
end



"""
    Search in the search tree for matches.
"""
function search_heuristically(search_tree::BKTree{String},
                              needles::Vector{String};
                              max_suggestions::Int=1)
    # Initializations
    suggestions = MultiDict{String, Tuple{Float64, String}}()
    use_heuristic = max_suggestions > 0
    # Search
    if use_heuristic
        if isempty(needles)
            return suggestions
        else  # there are terms that have not been found
            # Checks
            @assert !BKTrees.is_empty_node(search_tree.root) "FATAL: empty search tree."
            for needle in needles
                _suggestions = sort!(find(search_tree, needle,
                                          MAX_EDIT_DISTANCE,
                                          k=max_suggestions),
                                     by=x->x[1])
                if !isempty(_suggestions)
                    n = min(max_suggestions, length(_suggestions))
                    push!(suggestions, needle=>_suggestions[1:n])
                end
            end
        end
    end
    return suggestions
end
