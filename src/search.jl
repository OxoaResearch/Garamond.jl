##################
# Search methods #
##################

"""
	search(srcher, query [;kwargs])

Searches for query (i.e. key terms) in multiple corpora and returns
information regarding the documents that match best the query.
The function returns the search results in the form of
a `Vector{SearchResult}`.

# Arguments
  * `srcher::Vector{Searcher}` is the corpora searcher
  * `query` the query

# Keyword arguments
  * `search_type::Symbol` is the type of the search; can be `:metadata`,
     `:data` or `:all`; the options specify that the query can be found in
     the metadata of the documents of the corpus, the document content or both
     respectively
  * `search_method::Symbol` controls the type of matching: `:exact`
     searches for the very same string while `:regex` searches for a string
     in the corpus that includes the needle
  * `max_matches::Int` is the maximum number of search results to return from
     each corpus
  * `max_corpus_suggestions::Int` is the maximum number of suggestions to return for
     each missing needle from the search in a corpus
"""
function search(srchers::V,
                query;
                search_type::Symbol=DEFAULT_SEARCH_TYPE,
                search_method::Symbol=DEFAULT_SEARCH_METHOD,
                max_matches::Int=MAX_MATCHES,
                max_corpus_suggestions::Int=MAX_CORPUS_SUGGESTIONS
               ) where {V<:Vector{<:Searcher{D,E,M}
                                  where D<:AbstractDocument
                                  where E
                                  where M<:AbstractSearchModel}}
    # Checks
    @assert search_type in [:data, :metadata, :all]
    @assert search_method in [:exact, :regex]
    @assert max_matches >= 0
    @assert max_corpus_suggestions >=0
    # Initializations
    n = length(srchers)
    enabled_searchers = [i for i in 1:n if isenabled(srchers[i])]
    n_enabled = length(enabled_searchers)
    queries = [prepare_query(query, srcher.config.query_strip_flags)
               for srcher in srchers]
    # Search
    results = Vector{SearchResult}(undef, n_enabled)
    ###################################################################
    # A `Threads.@threads` statement in front of the for loop here
    # idicates the use of multi-threading. If multi-threading is used,
    # OPENBLAS multi-threading support has to be disabled by using:
    #   `export OPENBLAS_NUM_THREADS=1` in the shell
    # or start julia with:
    #   `env OPENBLAS_NUM_THREADS=1 julia`
    #
    # WARNING: Multi-theading support (as of v1.1 is still EXPERIMENTAL)
    #          and floating point operations are not thread-safe!
    #          Do not use with semantic search!!
    ###################################################################
    ### Threads.@threads for i in 1:n_enabled
    for i in 1:n_enabled
        # Get corpus search results
        results[i] = search(srchers[enabled_searchers[i]],
                            queries[enabled_searchers[i]],
                            search_type=search_type,
                            search_method=search_method,
                            max_matches=max_matches,
                            max_suggestions=max_corpus_suggestions)
    end
    # Return vector of tuples, each tuple containing the id and search results
    return results::Vector{SearchResult}  # not necessary without `@threads`
end


"""
	search(srcher, query [;kwargs])

Searches for query (i.e. key terms) in a corpus' metadata, text or both and
returns information regarding the the documents that match best the query.
The function returns an object of type SearchResult and the id of the searcher.

# Arguments
  * `srcher::Searcher` is the corpus searcher
  * `query` the query, can be either a `String` or `Vector{String}`

# Keyword arguments
  * `search_type::Symbol` is the type of the search; can be `:metadata`,
     `:data` or `:all`; the options specify that the query can be found in
     the metadata of the documents of the corpus, the document content or both
     respectively
  * `search_method::Symbol` controls the type of matching: `:exact`
     searches for the very same string while `:regex` searches for a string
     in the corpus that includes the needle
  * `max_matches::Int` is the maximum number of search results to return
  * `max_suggestions::Int` is the maximum number of suggestions to return for
     each missing needle
"""
function search(srcher::Searcher{D,E,M},
                query;  # can be either a string or vector of strings
                search_type::Symbol=:metadata,
                search_method::Symbol=:exact,
                max_matches::Int=10,
                max_suggestions::Int=MAX_CORPUS_SUGGESTIONS  # not used
                ) where
        {D<:AbstractDocument, E, M<:AbstractSearchModel}
    needles = prepare_query(query, srcher.config.query_strip_flags)
    # Initializations
    isregex = (search_method == :regex)
    n = length(srcher.search_data[:data])  # number of embedded documents
    where_to_search = ifelse(search_type==:all, [:data, :metadata], [search_type])
    # Embed query (2 embeddings may be needed, separately for data and metadata)
    T = get_embedding_eltype(srcher.embedder)
    query_embeddings = Dict{Symbol, Vector{T}}()
    if srcher.config.vectors in [:word2vec, :glove, :conceptnet]
        qe = embed_document(srcher.embedder, srcher.corpus.lexicon, needles,
                            embedding_method=srcher.config.doc2vec_method,
                            isregex=isregex)
        push!(query_embeddings, :data=>qe)
        push!(query_embeddings, :metadata=>qe)
    else
        for wts in where_to_search
            qe = embed_document(srcher.embedder[wts], srcher.corpus.lexicon, needles,
                                embedding_method=srcher.config.doc2vec_method,
                                isregex=isregex)
            push!(query_embeddings, wts=>qe)
        end
    end
    # Search for neighbors in embedding space
    k = min(n, max_matches)
    idxs = Int[]
    scores = T[]
    for wts in where_to_search
        # search if vector is not zero
        if !iszero(query_embeddings[wts])
            ### Search
            _idxs, _scores = search(srcher.search_data[wts], query_embeddings[wts], k)
            ###
            idxs = vcat(idxs, _idxs)
            scores = vcat(scores, _scores)
        end
        if search_type == :all
            idxs, scores = merge_indices_and_scores(idxs, scores, k)
        end
    end
    # Construct additional structures
    suggestions = MultiDict{String, Tuple{T, String}}()
    needle_matches = Vector{String}()
    missing_needles = Vector{String}()
    doc_matches = Set(1:n)
    # For certain types of search, check out which documents can be displayed
    # and which needles have and have not been found
    if srcher.config.vectors in [:count, :tf, :tfidf, :bm25] &&
            srcher.config.vectors_transform in [:none, :rp]
        needle_matches, doc_matches =
            find_matching_needles(srcher.corpus.inverse_index, needles, search_method)
        missing_needles = setdiff(needles, needle_matches)
    end
    mask = [i for i in 1:length(idxs) if idxs[i] in doc_matches]
    query_matches = MultiDict(zip(scores[mask], idxs[mask]))
    if max_suggestions > 0 && !isempty(missing_needles)
        # Get suggestions
        for wts in where_to_search
            search_heuristically!(suggestions,
                                  srcher.search_trees[wts],
                                  missing_needles,
                                  max_suggestions=max_suggestions)
        end
    end
    return SearchResult(id(srcher), query_matches, collect(needle_matches), suggestions)
end


"""
    search_heuristically!(suggestions, search_tree, needles [;max_suggestions=1])

Searches in the search tree for partial matches of the `needles`.
"""
function search_heuristically!(suggestions::MultiDict{String, Tuple{T, String}},
                               search_tree::BKTree{String},
                               needles::Vector{S};
                               max_suggestions::Int=1
                              ) where {S<:AbstractString, T<:AbstractFloat}
    if isempty(needles)
        return suggestions
    else  # there are terms that have not been found
        # Checks
        @assert !BKTrees.is_empty_node(search_tree.root) "FATAL: empty search tree."
        for needle in needles
            _suggestions = sort!(find(search_tree, String(needle),
                                      MAX_EDIT_DISTANCE,
                                      k=max_suggestions),
                                 by=x->x[1])
            if !isempty(_suggestions)
                n = min(max_suggestions, length(_suggestions))
                push!(suggestions, needle=>_suggestions[1:n])
            end
        end
    end
    return suggestions
end


"""
    get_embedding_eltype(embeddings)

Function that returns the type of the embeddings' elements. The type is useful to
generate score vectors. If the element type is and `Int8` (ConceptNet compressed),
the returned type is the DEFAULT_EMBEDDING_TYPE.
"""
# Get embedding element types
get_embedding_eltype(::Word2Vec.WordVectors{S,T,H}) where
    {S<:AbstractString, T<:Real, H<:Integer} = T

get_embedding_eltype(::Glowe.WordVectors{S,T,H}) where
    {S<:AbstractString, T<:Real, H<:Integer} = T

get_embedding_eltype(::ConceptNet{L,K,E}) where
    {L<:Language, K<:AbstractString, E<:AbstractFloat} = E

get_embedding_eltype(::ConceptNet{L,K,E}) where
    {L<:Language, K<:AbstractString, E<:Integer} = DEFAULT_EMBEDDING_ELEMENT_TYPE

get_embedding_eltype(::RPModel{S,T,A,H}) where
    {S<:AbstractString, T<:AbstractFloat, A<:AbstractMatrix{T}, H<:Integer} = T

get_embedding_eltype(::LSAModel{S,T,A,H}) where
    {S<:AbstractString, T<:AbstractFloat, A<:AbstractMatrix{T}, H<:Integer} = T

get_embedding_eltype(::Dict{Symbol, <:Union{RPModel{S,T,A,H}, LSAModel{S,T,A,H}}}) where
    {S<:AbstractString, T<:AbstractFloat, A<:AbstractMatrix{T}, H<:Integer} = T


"""
    merge_indices_and_scores(idxs, scores, k)

Small function that processes two vectors a and b where
a is assumed to be a vector of document idices (with possible
duplicates and b the corresponding scores)
"""
function merge_indices_and_scores(idxs, scores, k)
    seen = Dict{Int,Int}()  # idx=>i
    removable = Int[]
    for (i, idx) in enumerate(idxs)
        if !(idx in keys(seen))
            push!(seen, idx=>i)
        else
            # Already seen (duplicate)
            scores[[i, seen[idx]]] .= (scores[i] + scores[seen[idx]])/2
            push!(removable, i)
        end
    end
    deleteat!(idxs, removable)
    deleteat!(scores, removable)
    # Precaution for HSNW which may not return
    # an *exact* number of neighbors
    k = min(k, length(idxs))
    # Sort, take first k neighbors and return
    order = sortperm(scores)[1:k]
    return idxs[order], scores[order]
end


function find_matching_needles(iv::Dict{String, Vector{Int}}, needles::Vector{String}, method::Symbol)
    # Initializations
    p = length(needles)
    needle_matches = Set{String}()
    doc_matches = Set{Int}()
    # Search
    if method == :exact
        for (j, needle) in enumerate(needles)
            if haskey(iv, needle)
                push!(needle_matches, needle)
                push!(doc_matches, iv[needle]...)
            end
        end
    end
    if method == :regex
        patterns = map(Regex, needles)
        haystack = keys(iv)
        for (j, pattern) in enumerate(patterns)
            for k in haystack
                if occursin(pattern, k)
                    push!(needle_matches, k)
                    push!(doc_matches, iv[k]...)
                end
            end
        end
    end
    return needle_matches, doc_matches
end
