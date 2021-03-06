#!/bin/julia

###################################
# Garamond search server CLI tool #
###################################

module gars  # The Garamond server

using Pkg
project_root_path = "/" * joinpath(split(@__FILE__, "/")[1:end-4]...)
Pkg.activate(project_root_path)
using Garamond
using Sockets
using Logging
using ArgParse


# Function that parses Garamond's server arguments
function get_server_commandline_arguments(args::Vector{String})
	s = ArgParseSettings()
	@add_arg_table! s begin
        "--data-config", "-d"
            help = "data configuration file"
            arg_type = String
        "--env-cache", "-c"
            help = "search environment cache file"
            arg_type = String
        "--log-level"
            help = "logging level"
            default = "info"
        "--log", "-l"
            help = "logging stream"
            default = "stdout"
        "--unix-socket", "-u"
            help = "UNIX socket for data communication"
            arg_type = String
        "--web-socket-port", "-w"
            help = "WEB socket data communication port"
            arg_type = UInt16
        "--web-socket-ip"
            help = "WEB socket data communication IP"
            default = "127.0.0.1"
        "--http-port", "-p"
            help = "HTTP port for REST services"
            arg_type = Int
        "--http-ip"
            help = "HTTP IP for REST services"
            default = "0.0.0.0"
        "--search-server-port", "-i"
            help = "Internal TCP port for the search server"
            arg_type = Int
            default = 9_000
	end
	return parse_args(args,s)
end


# Tests whether an ip is valid
function isvalidip(ip::AbstractString)
    try
        IPv4(ip), IPv6(ip)
        return true
    catch
        return false
    end
end


########################
# Main module function #
########################
function julia_main()::Cint
    try
        real_main()
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end
    return 0
end


function real_main()
    @info "~ GARAMOND ~ $(Garamond.printable_version())\n"

    # Parse command line arguments
    args = get_server_commandline_arguments(ARGS)

    # Get the argument values
    log_level = args["log-level"]
    logging_stream = args["log"]

    # Logging
    logger = Garamond.build_logger(logging_stream, log_level)
    global_logger(logger)

    # Get IP's
    ws_ip = args["web-socket-ip"]
    http_ip = args["http-ip"]
    if !isvalidip(ws_ip)
        @warn "Web-socket IP $ws_ip is not valid. Exiting..."
        return 0
    elseif !isvalidip(http_ip)
        @warn "HTTP IP $http_ip is not valid. Exiting..."
        return 0
    end

    # Get sockets/ports and check
    unixsocket = args["unix-socket"]
    ws_port = args["web-socket-port"]
    http_port = args["http-port"]
    io_port = args["search-server-port"]

    if unixsocket == nothing && ws_port == nothing && http_port == nothing
        @warn """At least a UNIX-socket, WEB-socket port or HTTP port
                 have to be specified. Use the -u, -w or -p options.
                 Exiting..."""
        return 0
    end

    if io_port < 0
        @warn "Search server I/O port value error. Defaulting to 9000."
        io_port = 9000
    end

    # Check data path and cache
    data_config_path = args["data-config"]
    env_cache_path = args["env-cache"]
    if data_config_path === nothing && env_cache_path === nothing
        @warn "Specify a data configuration or cache file using the -d or -c options. Exiting..."
        return 0
    end

    # Start I/O server(s)
    sserver_ready = Condition()  # search server ready
    unixsocket != nothing && @async unix_socket_server(unixsocket, io_port, sserver_ready)
    ws_port != nothing && @async web_socket_server(ws_port, io_port, sserver_ready, ipaddr=ws_ip)
    http_port != nothing && @async rest_server(http_port, io_port, sserver_ready, ipaddr=http_ip)

    # Start Search server
    Garamond.search_server(data_config_path, io_port, sserver_ready; cache_path=env_cache_path)
    return 0
end


################################
# Start main Garamond function #
################################
if abspath(PROGRAM_FILE) == @__FILE__
    real_main()
end

end  # module
