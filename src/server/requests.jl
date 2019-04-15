"""
Standard deconstructed request corresponding to an error request.
"""
const ERRORED_REQUEST = ("request_error", "", 0, :nothing, :nothing, 0, "")


"""
    deconstruct_request(request)

Function that deconstructs a Garamond request received from a client into
individual search engine operations and search parameters.
"""
function deconstruct_request(request::String)
    try
        # Parse JSON request
        req = JSON.parse(request)
        # Read fields
        op = req["operation"]
        query = req["query"]
        max_matches = req["max_matches"]
        search_method = Symbol(req["search_method"])
        max_suggestions = req["max_suggestions"]
        what_to_return = req["what_to_return"]
        return op, query, max_matches, search_method,
               max_suggestions, what_to_return
    catch
        return ERRORED_REQUEST
    end
end


"""
    construct_response(srchers, results, what [; kwargs...])

Function that constructs a response for a Garamond client using
the search `results`, data from `srchers` and specifier `what`.
"""
function construct_response(results, corpora;
                            max_suggestions::Int=0,
                            elapsed_time::Float64=0) where C<:Corpus
    local result_data
    if corpora == nothing
        # Get basic response data
        result_data = get_basic_result_data(results,
                        max_suggestions, elapsed_time)
    else
        # Get extended response data
        result_data = get_extended_result_data(results, corpora,
                        max_suggestions, elapsed_time)
    end
    return JSON.json(result_data)
end


# Get basic results data
function get_basic_result_data(results::T,
                               max_suggestions::Int,
                               elapsed_time::Float64
                              ) where T<:AbstractVector{<:SearchResult}
    # TODO: Decide on a final format
    return results
end


# Get extended results data
# Note: This should only be used for internal testing
#       by using the `garc` and `garw` clients
function get_extended_result_data(results::T,
                                  corpora,
                                  max_suggestions::Int,
                                  elapsed_time::Float64
                                 ) where T<:AbstractVector{<:SearchResult}
    # Count the total number of results
    if !isempty(results)
        nt = mapreduce(x->valength(x.query_matches), +, results)
    else
        nt = 0
    end

    r = Dict("etime"=>elapsed_time,
             "matches" => Dict{String, Vector{Tuple{Float64, Dict{String,String}}}}(),
             "n_matches" => nt,
             "n_corpora" => length(results),
             "n_corpora_match" => mapreduce(r->!isempty(r.query_matches), +, results),
             "suggestions" => squash_suggestions(results, max_suggestions))

    # Populate the "matches" field
    for (i, (_result, crps)) in enumerate(zip(results, corpora))
        push!(r["matches"], _result.id.id => Vector{Dict{String,String}}())
        if !isempty(crps)
            for score in sort(collect(keys(_result.query_matches)), rev=true)
                for doc in (crps[i] for i in _result.query_matches[score])
                    dictdoc = convert(Dict, metadata(doc))
                    push!(r["matches"][_result.id.id], (score, dictdoc))
                end
            end
        end
    end
    return r
end
