function test_nt_props(nt, validator)
    propnames = propertynames(nt)
    @assert isempty(symdiff(keys(validator), propnames))
    for (pname, ptype) in validator
        @assert pname in propnames
        @assert getproperty(nt, pname) isa ptype
    end
    true
end

@testset "Config parser: $config" for config in CONFIG_FUNCTIONS
	cfg = mktemp() do path, io  # write and parse config file on-the-fly
               write(io, eval(config)())
			   flush(io)
			   parse_configuration(path)
		   end
    @test cfg isa NamedTuple

    ENVCONFIG_PROPS = Dict(:data_loader => Function,
                           :data_sampler => Function,
                           :id_key => Symbol,
                           :vectors_eltype => Type,
                           :searcher_configs => Vector,
                           :embedder_configs => Vector,
                           :config_path => String)
    @test test_nt_props(cfg, ENVCONFIG_PROPS)

    EMBEDDERSCONFIG_PROPS = Dict(:id =>String,
                                 :description => String,
                                 :language => String,
                                 :stem_words => Bool,
                                 :ngram_complexity => Int,
                                 :vectors => Symbol,
                                 :vectors_transform => Symbol,
                                 :vectors_dimension => Int,
                                 :embeddings_path => Union{Nothing, String},
                                 :embeddings_kind => Symbol,
                                 :doc2vec_method => Symbol,
                                 :glove_vocabulary => Union{Nothing, String},
                                 :oov_policy => Symbol,
                                 :embedder_kwarguments => Dict{Symbol, Any},
                                 :embeddable_fields => Union{Nothing, Vector{Symbol}},
                                 :text_strip_flags => UInt32,
                                 :sif_alpha => cfg.vectors_eltype,
                                 :borep_dimension => Int,
                                 :borep_pooling_function => Symbol,
                                 :disc_ngram => Int)
    for ec in cfg.embedder_configs
        @test test_nt_props(ec, EMBEDDERSCONFIG_PROPS)
    end

    SEARCHERCONFIG_PROPS = Dict(:id => String,
                                :id_aggregation => String,
                                :description => String,
                                :enabled => Vector{Bool},
                                :indexable_fields => Vector{Symbol},
                                :data_embedder => String,
                                :input_embedder => String,
                                :search_index => Symbol,
                                :search_index_arguments => Vector{Any},
                                :search_index_kwarguments => Dict{Symbol, Any},
                                :heuristic => Union{Nothing, Symbol},
                                :score_alpha => cfg.vectors_eltype,
                                :score_weight => cfg.vectors_eltype)
    for sc in cfg.searcher_configs
        @test test_nt_props(sc, SEARCHERCONFIG_PROPS)
    end
end
