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
  * `query` the query, can be either a `String` or `Vector{String}`

# Keyword arguments
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
                search_method::Symbol=DEFAULT_SEARCH_METHOD,
                max_matches::Int=MAX_MATCHES,
                max_corpus_suggestions::Int=MAX_CORPUS_SUGGESTIONS
               ) where {V<:Vector{<:Searcher{T,D,E,M}
                                  where T<:AbstractFloat
                                  where D<:AbstractDocument
                                  where E
                                  where M<:AbstractSearchModel}}
    # Checks
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
  * `search_method::Symbol` controls the type of matching: `:exact`
     searches for the very same string while `:regex` searches for a string
     in the corpus that includes the needle
  * `max_matches::Int` is the maximum number of search results to return
  * `max_suggestions::Int` is the maximum number of suggestions to return for
     each missing needle
"""
function search(srcher::Searcher{T,D,E,M},
                query;  # can be either a string or vector of strings
                search_method::Symbol=DEFAULT_SEARCH_METHOD,
                max_matches::Int=MAX_MATCHES,
                max_suggestions::Int=MAX_CORPUS_SUGGESTIONS  # not used
                ) where {T<:AbstractFloat, D<:AbstractDocument, E, M<:AbstractSearchModel}
    needles = prepare_query(query, srcher.config.query_strip_flags)
    # Initializations
    isregex = (search_method == :regex)
    n = length(srcher.search_data)  # number of embedded documents
    query_embedding = embed_document(srcher.embedder, srcher.corpus.lexicon, needles,
                                     embedding_method=srcher.config.doc2vec_method,
                                     sif_alpha=srcher.config.sif_alpha,
                                     isregex=isregex)
    # Search for neighbors in embedding space
    k = min(n, max_matches)
    idxs = Int[]
    scores = T[]
    # First, find documents with matching needles
    needle_matches = Vector{String}()
    missing_needles = Vector{String}()
    doc_matches = Vector(1:n)
    # For certain types of search, check out which documents can be displayed
    # and which needles have and have not been found
    if srcher.config.vectors in [:count, :tf, :tfidf, :bm25] &&
            srcher.config.vectors_transform in [:none, :rp]
        needle_matches, doc_matches = find_matching(srcher.corpus.inverse_index,
                                        needles, search_method, n)
        missing_needles = setdiff(needles, needle_matches)
    end
    # Search (if document vector is not zero)
    if !iszero(query_embedding)
        ### Search
        idxs, scores = search(srcher.search_data, query_embedding, k, doc_matches)
        ###
        score_transform!(scores, alpha=srcher.config.score_alpha)
    end
    mask = [i for (i,idx) in enumerate(idxs) if idx in doc_matches]
    query_matches = MultiDict(zip(scores[mask], idxs[mask]))
    # Get suggestions
    suggestions = MultiDict{String, Tuple{T, String}}()
    if max_suggestions > 0 && !isempty(missing_needles)
        search_heuristically!(suggestions,
                              srcher.search_trees,
                              missing_needles,
                              max_suggestions=max_suggestions)
    end
    return SearchResult(id(srcher), query_matches, collect(needle_matches),
                        suggestions, T(srcher.config.score_weight))
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
    elseif BKTrees.is_empty_node(search_tree.root)
        @debug "Suggestion tree is empty, no suggestions will be added."
        return suggestions
    else  # there are terms that have not been found
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


function find_matching(iv::OrderedDict{String, Vector{Int}},
                       needles::Vector{String},
                       method::Symbol,
                       ndocs::Int)
    # Initializations
    p = length(needles)
    needle_matches = Vector{String}()
    doc_matches = falses(ndocs)
    # Search
    if method == :exact
        for (j, needle) in enumerate(needles)
            if haskey(iv, needle)
                push!(needle_matches, needle)
                doc_matches[iv[needle]].= true
            end
        end
    end
    if method == :regex
        patterns = map(Regex, needles)
        haystack = keys(iv)
        for (j, pattern) in enumerate(patterns)
            for k in haystack
                if occursin(pattern, k)
                    needle = needles[j]
                    !(needle in needle_matches) &&
                        push!(needle_matches, needles[j])
                    doc_matches[iv[k]] .= true
                end
            end
        end
    end
    return needle_matches, findall(doc_matches)
end


# Post-processing score function:
#   - map distances [0, Inf) --> [-1, 1]
#TODO(Corneliu) Analylically/empirically adapt alpha do vector dimensionality
function score_transform!(x::AbstractVector{T}; alpha::Float64=DEFAULT_SCORE_ALPHA) where T<:AbstractFloat
    n = length(x)
    α = T(alpha)
    @inbounds @simd for i in 1:n
        x[i] = 1 - 2.0*tanh(α * x[i])
    end
    return x
end
