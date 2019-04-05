"""
    search_server(data_config_paths, io_channel)

Search server for Garamond. It is a finite-state-machine that
when called, creates the searchers i.e. search objects using the
`data_config_paths` and the proceeds to looping continuously
in order to:
    • update the searchers regularly;
    • receive requests from clients on the I/O channel
    • call search and route responses back to the clients
      through the I/O channel

Both searcher update and I/O communication are performed asynchronously.
"""
function search_server(data_config_paths, io_channel)
    # Load data
    srchers = load_searchers(data_config_paths)

    # Start updater
    srchers_channel = Channel{typeof(srchers)}(0)
    @async updater(srchers, channels=srchers_channel)

    # Main loop
    @info "Search server: Entering query wait loop..."
    while true
        if isready(srchers_channel)
            srchers = take!(srchers_channel)
            @debug "Search server: Searchers updated."
        else
            # Read and deconstruct request
            request = take!(io_channel)
            @debug "Search server: Received request=$request"
            (operation, query, max_matches, search_method,
             max_suggestions, what_to_return) = deconstruct_request(request)
            if operation == "search"
                ### Search ###
                @debug "Search server: Performing search operation query='$query'..."
                t_init = time()
                # Get search results
                results = search(srchers, query,
                                 search_method=search_method,
                                 max_matches=max_matches,
                                 max_corpus_suggestions=max_suggestions)
                t_finish = time()

                # Aggregate results as needed
                #aggregate!(results, method=RESULT_AGGREGATION_STRATEGY)

                # Select the data (if any) that will be reuturned
                if what_to_return == "json-index"
                    corpora = nothing
                elseif what_to_return == "json-data"
                    idx_corpora = Int[]
                    for result in results
                        for (idx, srcher) in enumerate(srchers)
                            if result.id == srcher.config.id_aggregation
                                push!(idx_corpora, idx)
                                break
                            end
                        end
                    end
                    corpora = (srchers[idx].corpus for idx in idx_corpora)
                else
                    @warn "Search server: Unknown return option \"$what_to_return\", "*
                          "defaulting to \"json-index\"..."
                    corpora = nothing
                end

                # Construct response for client
                response = construct_response(results, corpora,
                                              max_suggestions=max_suggestions,
                                              elapsed_time=t_finish-t_init)
                #Write response to I/O server
                put!(io_channel, response)
            elseif operation == "kill"
                ### Kill the search server ###
                @debug "Search server: Exiting..."
                exit()
            elseif operation == "request_error"
                @debug "Search server: Malformed request. Ignoring..."
                put!(io_channel, "")
            end
        end
    end
end
