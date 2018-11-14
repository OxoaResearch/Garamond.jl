########################################################
# Corpus Id's i.e. keys that uniquely identify corpora #
########################################################

struct HashId <: AbstractId
    id::UInt
end


struct StringId <: AbstractId
    id::String
end


show(io::IO, id::StringId) = print(io, "id=\"$(id.id)\"")
show(io::IO, id::HashId) = print(io, "id=0x$(string(id.id, base=16))")


random_id(::Type{HashId}) = HashId(hash(rand()))
random_id(::Type{StringId}) = StringId(randstring())


# Construct IDs
make_id(::Type{HashId}, id::String) = HashId(parse(UInt, id))  # the id has to be parsable to UInt
make_id(::Type{HashId}, id::T) where T<:Number = HashId(UInt(abs(id)))  # may fail for floats!
make_id(::Type{StringId}, id::T) where T<:AbstractString = StringId(String(id))
make_id(::Type{StringId}, id::T) where T<:Number = StringId(string(id))

const DEFAULT_ID_TYPE = StringId



################
# SearchConfig #
################
# SearchConfigs can be built from a data configuration file or manually
mutable struct SearchConfig{I<:AbstractId}
    # general
    id::I                           # searcher/corpus id
    search::Symbol                  # search type i.e. :classic, :semantic
    name::String                    # name of the searcher.corpus
    enabled::Bool                   # whether to use the corpus in search or not
    data_path::String               # file/directory path for the data (depends on what the parser accepts)
    parser::Function                # parser function used to obtain corpus
    build_summary::Bool             # whether to summarize or not the documents
    summary_ns::Int                 # the number of sentences in the summary
    # classic search
    count_type::Symbol              # search term counting type i.e. :tf, :tfidf etc (classic search)
    heuristic::Symbol               # search heuristic for recommendtations (classic search)
    # semantic search
    embeddings_path::String         # path to the embeddings file
    embeddings_type::Symbol         # type of the embeddings i.e. :conceptnet, :word2vec (semantic search)
    embedding_method::Symbol        # How to arrive at a single embedding from multiple i.e. :bow, :arora (semantic search)
    embedding_search_model::Symbol  # type of the search model i.e. :naive, :kdtree, :hnsw (semantic search)
    embedding_element_type::Symbol  # Type of the embedding elements
end


SearchConfig{I}() where I<:AbstractId =
    SearchConfig{I}(
        random_id(I), DEFAULT_SEARCH, "", false, "",
        get_parsing_function(DEFAULT_PARSER,
                             false,
                             DEFAULT_DELIMITER,
                             DEFAULT_GLOBBING_PATTERN,
                             DEFAULT_BUILD_SUMMARY,
                             DEFAULT_SUMMARY_NS),
        DEFAULT_BUILD_SUMMARY, DEFAULT_SUMMARY_NS,
        DEFAULT_COUNT_TYPE, DEFAULT_HEURISTIC,
        "", DEFAULT_EMBEDDINGS_TYPE, DEFAULT_EMBEDDING_METHOD,
        DEFAULT_EMBEDDING_SEARCH_MODEL, DEFAULT_EMBEDDING_ELEMENT_TYPE)

# Keyword argument constructor; all arguments sho
SearchConfig(;
          id=random_id(DEFAULT_ID_TYPE),
          search=DEFAULT_SEARCH,
          name="",
          enabled=false,
          data_path="",
          parser=get_parsing_function(DEFAULT_PARSER,
                                      false,
                                      DEFAULT_DELIMITER,
                                      DEFAULT_GLOBBING_PATTERN,
                                      DEFAULT_BUILD_SUMMARY,
                                      DEFAULT_SUMMARY_NS),
          build_summary=DEFAULT_BUILD_SUMMARY,
          summary_ns=DEFAULT_SUMMARY_NS,
          count_type=DEFAULT_COUNT_TYPE,
          heuristic=DEFAULT_HEURISTIC,
          embeddings_path="",
          embeddings_type=DEFAULT_EMBEDDINGS_TYPE,
          embedding_method=DEFAULT_EMBEDDING_METHOD,
          embedding_search_model=DEFAULT_EMBEDDING_SEARCH_MODEL,
          embedding_element_type=DEFAULT_EMBEDDING_ELEMENT_TYPE) =
    # Call normal constructor
    SearchConfig(id, search, name, enabled, data_path, parser,
                 build_summary, summary_ns,
                 count_type, heuristic,
                 embeddings_path, embeddings_type,
                 embedding_method, embedding_search_model,
                 embedding_element_type)


Base.show(io::IO, sconfig::SearchConfig) = begin
    printstyled(io, "SearchConfig for $(sconfig.name)\n")
    _status = ifelse(sconfig.enabled, "enabled", "disabled")
    _status_color = ifelse(sconfig.enabled, :light_green, :light_black)
    printstyled(io, "`-[$_status]", color=_status_color)
    _search_color = ifelse(sconfig.search==:classic, :cyan, :light_cyan)
    printstyled(io, "-[$(sconfig.search)] ", color=_search_color)
    printstyled(io, "$(sconfig.data_path)\n")
end



"""
    load_search_configs(filename)

Function that creates search configurations from a data configuration file
specified by `filename`. It returns a `Vector{SearchConfig}` that is used
to build the `Searcher` objects with which search is performed.
"""
function load_search_configs(filename::AbstractString)
    # Read config (this should fail if config not found)
    dict_configs = JSON.parse(open(fid->read(fid, String), filename))
    n = length(dict_configs)
    # Create search configurations
    search_configs = [SearchConfig{DEFAULT_ID_TYPE}() for _ in 1:n]
    removable = Int[]  # search configs that have problems
    for (i, (sconfig, dconfig)) in enumerate(zip(search_configs, dict_configs))
        # Get search parameters accounting for missing values
        # by using default parameters where the case
        header = get(dconfig, "header", false)
        id = get(dconfig, "id", missing)
        if !ismissing(id)
            sconfig.id = make_id(DEFAULT_ID_TYPE, id)
        end
        globbing_pattern = get(dconfig, "globbing_pattern",
                               DEFAULT_GLOBBING_PATTERN)
        delimiter = get(dconfig, "delimiter", DEFAULT_DELIMITER)
        sconfig.search = Symbol(get(dconfig, "search", DEFAULT_SEARCH))
        sconfig.name = get(dconfig, "name", "")
        sconfig.enabled = get(dconfig, "enabled", false)
        sconfig.data_path = get(dconfig, "data_path", "")
        sconfig.build_summary = get(dconfig, "build_summary", DEFAULT_BUILD_SUMMARY)
        sconfig.summary_ns = get(dconfig, "summary_ns", DEFAULT_SUMMARY_NS)
        sconfig.parser = get_parsing_function(Symbol(dconfig["parser"]),
                                              header,
                                              delimiter,
                                              globbing_pattern,
                                              sconfig.build_summary,
                                              sconfig.summary_ns)
        sconfig.count_type = Symbol(get(dconfig, "count_type", DEFAULT_COUNT_TYPE))
        sconfig.heuristic = Symbol(get(dconfig, "heuristic", DEFAULT_HEURISTIC))
        sconfig.embeddings_path = get(dconfig, "embeddings_path", "")
        sconfig.embeddings_type = Symbol(get(dconfig, "embeddings_type",
                                             DEFAULT_EMBEDDINGS_TYPE))
        sconfig.embedding_method = Symbol(get(dconfig, "embedding_method",
                                              DEFAULT_EMBEDDING_METHOD))
        sconfig.embedding_search_model = Symbol(get(dconfig,
                                                "embedding_search_model",
                                                DEFAULT_EMBEDDING_SEARCH_MODEL))
        sconfig.embedding_element_type = Symbol(get(dconfig,
                                                "embedding_element_type",
                                                DEFAULT_EMBEDDING_SEARCH_MODEL))
        # Checks of the configuration parameter values; no checks
        # for:
        # - id (always works)
        # - name (always works)
        # - enabled (must fail if wrong)
        # - parser (must fail if wrong)
        # - globbing_pattern (must fail if wrong)
        # - build_summary (should fail if wrong)
        ###
        # search
        if !(sconfig.search in [:classic, :semantic])
            @warn "$(sconfig.id) Forcing search=$DEFAULT_SEARCH."
            sconfig.search = DEFAULT_SEARCH
        end
        # data path
        if !isfile(sconfig.data_path) && !isdir(sconfig.data_path)
            @show isfile(sconfig.data_path)
            @show isdir(sconfig.data_path)
            @warn "$(sconfig.id) Missing data, ignoring search configuration..."
            push!(removable, i)  # if there is no data file, cannot search
            continue
        end
        # summary_ns i.e. the number of sentences in a summary
        if !(typeof(sconfig.summary_ns) <: Integer) || sconfig.summary_ns <= 0
            @warn "$(sconfig.id) Forcing summary_ns=$DEFAULT_SUMMARY_NS."
            sconfig.summary_ns = DEFAULT_SUMMARY_NS
        end
        # delimiter
        if !(typeof(delimiter) <: AbstractString) || length(delimiter) == 0
            @warn "$(sconfig.id) Forcing delimiter=$DEFAULT_DELIMITER."
            sconfig.delimiter = DEFAULT_DELIMITER
        end
        # Classic search specific options
        if sconfig.search == :classic
            # count type
            if !(sconfig.count_type in [:tf, :tfidf])
                @warn "$(sconfig.id) Forcing count_type=$DEFAULT_COUNT_TYPE."
                sconfig.count_type = DEFAULT_COUNT_TYPE
            end
            # heuristic
            if !(sconfig.heuristic in keys(HEURISTIC_TO_DISTANCE))
                @warn "$(sconfig.id) Forcing heuristic=$DEFAULT_HEURISTIC."
                sconfig.heuristic = DEFAULT_HEURISTIC
            end
        end
        # Semantic search specific options
        if sconfig.search == :semantic
            # word embeddings library path
            if !isfile(sconfig.embeddings_path)
                @warn "$(sconfig.id) Missing embeddings, ignoring search configuration..."
                push!(removable, i)  # if there is are no word embeddings, cannot search
                continue
            end
            # type of embeddings
            if !(sconfig.embeddings_type in [:word2vec, :conceptnet])
                @warn "$(sconfig.id) Forcing embeddings_type=$DEFAULT_EMBEDDINGS_TYPE."
                sconfig.embeddings_type = DEFAULT_EMBEDDINGS_TYPE
            end
            # embedding method
            if !(sconfig.embedding_method in [:bow, :arora])
                @warn "$(sconfig.id) Forcing embedding_method=$DEFAULT_EMBEDDING_METHOD."
                sconfig.embedding_method = DEFAULT_EMBEDDING_METHOD
            end
            # type of search model
            if !(sconfig.embedding_search_model in [:naive, :brutetree, :kdtree, :hnsw])
                @warn "$(sconfig.id) Forcing embedding_search_model=$DEFAULT_EMBEDDING_SEARCH_MODEL."
                sconfig.embedding_search_model = DEFAULT_EMBEDDING_SEARCH_MODEL
            end
            # type of the embedding elements
            if !(sconfig.embedding_element_type in [:Float32, :Float64])
                @warn "$(sconfig.id) Forcing embedding_element_type=$DEFAULT_EMBEDDING_ELEMENT_TYPE."
                sconfig.embedding_element_type = DEFAULT_EMBEDDING_ELEMENT_TYPE
            end
        end
    end
    # Remove search configs that have missing files
    deleteat!(search_configs, removable)
    return search_configs
end

function load_search_configs(filenames::Vector{S}) where S<:AbstractString
    return vcat((load_search_configs(file) for file in filenames)...)
end



"""
    get_parsing_function(args...)

Function that generates a parsing function from its input arguments and
returns it.

# Arguments
  * `parser::Symbol` is the name of the parser
  * `header::Bool` whether the file has a header or not (for delimited files only)
  * `delimiter::String` the delimiting character (for delimited files only)
  * `globbing_pattern::String` globbing pattern for gathering file lists
    from directories (for directory parsers only)
  * `build_summary::Bool` whether to use a summary instead of the full document
    (for directory parsers only)
  * `summary_ns::Int` how many sentences to use in the summary (for directory
    parsers only)

Note: `parser` must be in the keys of the `PARSER_CONFIGS` constant. The name
      of the data parsing function is created as: `:__parser_<parser>` so,
      the function name `:__parser_delimited_format_1` corresponds to the
      parser `:delimited_format_1`. The function must be defined apriori.
"""
function get_parsing_function(parser::Symbol,
                              header::Bool,
                              delimiter::String,
                              globbing_pattern::String,
                              build_summary::Bool,
                              summary_ns::Int) where T<:AbstractId
    PREFIX = :__parser_
    # Construct the actual basic parsing function from parser name
    parsing_function  = eval(Symbol(PREFIX, parser))
    # Get parser config
    parser_config = get(PARSER_CONFIGS, parser, Dict())
    # Build and return parsing function (a nice closure)
    function parsing_closure(filename::String)
        return parsing_function(# Compulsory arguments for all parsers
                                filename,
                                parser_config,
                                # keyword arguments (not used by all parsers)
                                header=header,
                                delimiter=delimiter,
                                globbing_pattern=globbing_pattern,
                                build_summary=build_summary,
                                summary_ns=summary_ns)
    end
    return parsing_closure
end
