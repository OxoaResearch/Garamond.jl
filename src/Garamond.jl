module Garamond

VERSION >= v"0.6.0" && __precompile__(true)

	# Using section
	using TextAnalysis, Languages					# - for index creation
	using Word2Vec, LightGraphs, NearestNeighbors, MLKernels	# - for word discovery
	using HttpServer, WebSockets, JSON				# - for HTTP/WebSocket/JSON communication with the http server
	using ArgParse							# - for command line argument parsing

	# Import section
	import Base: show, contains, convert, lowercase, search

	# Export section
	export  #HTTP server
		start_http_server,
		
		# String processing
		searchquery_preprocess,

		# Search related 
		search,
		contains,
		match_exactly_by_field,
		matcher,
		query_process, 
		fuzzysort,
		levsort,
		
		# Command line (application) related
		get_commandline_arguments,

		# Data related
		metadata, metastring, dict, 

		# Word embeddings
		find_cluster_mean,
		get_cluster_matrix, 
		get_cluster_matrix!,
		find_close_clusters, 
		path 
		

	# Includes
	include("data.jl")
	include("server.jl")
	include("string.jl")
	include("search.jl")
	include("search_heuristics.jl")
	include("cmdline.jl")
	include("word_model_utils.jl")

end # module
