# StringID
show(io::IO, id::StringId) = print(io, "id=\"$(id.id)\"")


# SearchConfig
Base.show(io::IO, sconfig::SearchConfig) = begin
    printstyled(io, "SearchConfig for $(sconfig.id) "*
                "(aggregation $(sconfig.id_aggregation))\n")
    printstyled(io, "`-enabled = ")
    printstyled(io, "$(sconfig.enabled)\n", bold=true)
    _tf = ""
    if sconfig.vectors in [:count, :tf, :tfidf, :b25]
        if sconfig.vectors_transform == :lsa
            _tf = " + LSA"
        elseif sconfig.vectors_transform == :rp
            _tf = " + random projection"
        end
    end
    printstyled(io, "  vectors = ")
    printstyled(io, "$(sconfig.vectors)$_tf", bold=true)
    printstyled(io, ", ")
    printstyled(io, "$(sconfig.vectors_eltype)\n", bold=true)
    printstyled(io, "  search_model = ")
    printstyled(io, "$(sconfig.search_model)\n", bold=true)
    printstyled(io, "  data_path = ")
    printstyled(io, "\"$(sconfig.data_path)\"\n", bold=true)
    if sconfig.embeddings_path != nothing
        printstyled(io, "  embeddings_path = ")
        printstyled(io, "\"$(sconfig.embeddings_path)\"\n", bold=true)
    end
end


# Searcher
show(io::IO, srcher::Searcher{T,D,E,M}) where {T,D,E,M} = begin
    printstyled(io, "Searcher for $(id(srcher)) "*
                "(aggregation $(srcher.config.id_aggregation)), ")
    _status = ifelse(isenabled(srcher), "enabled", "disabled")
    _status_color = ifelse(isenabled(srcher), :light_green, :light_black)
    printstyled(io, "$_status", color=_status_color, bold=true)
    printstyled(io, ", ")
    # Get embeddings type string
    if E <: Word2Vec.WordVectors
        _embedder = "Word2Vec"
    elseif E <: Glowe.WordVectors
        _embedder = "GloVe"
    elseif E <: ConceptnetNumberbatch.ConceptNet
        _embedder = "Conceptnet"
    elseif E <: StringAnalysis.LSAModel
        _embedder = "DTV+LSA"
    elseif E <: StringAnalysis.RPModel
        _embedder = "DTV"
        if srcher.config.vectors_transform==:rp
            _embedder *= "+RP"
        end
    else
        _embedder = "<Unknown>"
    end
    printstyled(io, "$_embedder", bold=true)
    printstyled(io, ", ")
    # Get model type string
    if M <: NaiveEmbeddingModel
        _model_type = "Naive"
    elseif M <: BruteTreeEmbeddingModel
        _model_type = "Brute-Tree"
    elseif M<: KDTreeEmbeddingModel
        _model_type = "KD-Tree"
    elseif M <: HNSWEmbeddingModel
        _model_type = "HNSW"
    else
        _model_type = "<Unknown>"
    end
    printstyled(io, "$_model_type", bold=true)
    #printstyled(io, "$(description(srcher))", color=:normal)
    printstyled(io, ", $(length(srcher.search_data)) $T embedded documents")
end


# SearchResult
show(io::IO, result::SearchResult) = begin
    n = valength(result.query_matches)
    nm = length(result.needle_matches)
    ns = length(result.suggestions)
    printstyled(io, "Search results for $(result.id): ")
    printstyled(io, " $n hits, $nm query terms, $ns suggestions.", bold=true)
end