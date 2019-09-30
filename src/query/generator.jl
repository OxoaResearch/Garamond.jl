function parse_query_generation_string(req::AbstractString,
                                       schema;
                                       id_key=DEFAULT_DB_ID_KEY)
    # Initializations
    (_target_id, _target_id_type, fields) = ("", String, Symbol[])

    # Get target id and fields from request string
    strs = split(req)
    try
        _target_id = string(strs[1])
        fields = Symbol.(strs[2:end])
    catch
        @warn "Could not parse target id, fields"
    end

    # Get target id type
    for dse in schema
        dse.column === id_key && (_target_id_type = dse.coltype)
    end

    # Parse target id
    target_id = __parse(_target_id, _target_id_type)
    return target_id, fields
end


function generate_query(req::AbstractString, dbdata::NDSparse; id_key=DEFAULT_DB_ID_KEY)
    # Initializations
    target_id, fields = parse_query_generation_string(req, db_schema(dbdata), id_key=id_key)
    data_columns = colnames(dbdata.data)
    index_columns = colnames(dbdata.index)

    # Filter on id, find record
    selector = Any[Colon() for _ in 1:length(index_columns)]
    selector[findfirst(isequal(id_key), index_columns)] = target_id
    target_record = dbdata[selector...]
    #target_record = filter(row->getproperty(row, id_key)==target_id, dbdata)  # if id is data column, not index column

    # Extract all values using fields (if empty, use all default query generation fields)
    query = ""
    if !isempty(target_record)
        for field in fields
            if field in data_columns
                query*="$field:$(getproperty(target_record.data, field)[1])" * " "
            elseif field in index_columns
                query*="$field:$(getproperty(target_record.index, field)[1])" * " "
            end
        end
    end
    # Construct and return simple query
    return (query=query, id=target_id)
end


function generate_query(req::AbstractString, dbdata::IndexedTable; id_key=DEFAULT_DB_ID_KEY)
    # Initializations
    target_id, fields = parse_query_generation_string(req, db_schema(dbdata), id_key=id_key)
    columns = colnames(dbdata)

    # Filter on id, find record
    target_record = filter(x -> getproperty(x, id_key)==target_id, dbdata)

    # Extract all values using fields (if empty, use all default query generation fields)
    query = ""
    if !isempty(target_record)
        for field in fields
            if field in columns
                query*="$field:$(select(target_record, field)[1])" * " "
            end
        end
    end
    # Construct and return simple query
    return (query=query, id=target_id)
end
