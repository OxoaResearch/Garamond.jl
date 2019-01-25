"""
    recursive_glob(pattern, path)

Globs recursively all the files matching the pattern, at the given path.
"""
function recursive_glob(pattern="*", path=".")
    contents = glob(pattern, path)
    mask_files = isfile.(contents)
    mask_dirs = isdir.(contents)
    files = contents[mask_files]
    directories = contents[mask_dirs]
    if all(mask_files)
    # Stop condition
        return contents
    elseif isempty(contents)
        # Empty directory, stop
        return String[]
    else
        # There are directories, recurse into them
        for dir in directories
            new_files = recursive_glob(pattern, dir)
            push!(files, new_files...)
        end
    end
    return files
end


# Parser for "directory_format_1"
# Logical to physical mapping:
#   - sentence -> sentence
#   - file -> document
#   - directory contents -> corpus
# The function returns a tuple (documents, metadata_vector):
#   Documents are a Vector{Vector{String}}:
#       - the String is the sentence
#       - the inner vector is for a the document: vector of sentences
#       - the outer vector is for the corpus: a vector of documents
#   The metadata vector is a Vector{DocumentMetadata}
function __parser_directory_format_1(directory::AbstractString,
                                     config=nothing;  # not used
                                     globbing_pattern::String=DEFAULT_GLOBBING_PATTERN,
                                     language::String=DEFAULT_LANGUAGE_STR,
                                     build_summary::Bool=DEFAULT_BUILD_SUMMARY,
                                     summary_ns::Int=DEFAULT_SUMMARY_NS,
                                     summarization_strip_flags::UInt32=
                                        DEFAULT_SUMMARIZATION_STRIP_FLAGS,
                                     show_progress::Bool=DEFAULT_SHOW_PROGRESS,
                                     kwargs...  # unused kw arguments (used in other parsers)
                                    ) where T<:AbstractDocument
    # Initializations
    files = recursive_glob(globbing_pattern, expanduser(directory))
    n = length(files)
    n==0 && @error "No files found in $directory with glob: $globbing_pattern."
    # Initialize outputs
    documents = Vector{Vector{String}}(undef, n)
    metadata_vector = Vector{DocumentMetadata}(undef, n)
    # Progressbar
    progressbar = Progress(n,
                    desc="Parsing $(split(directory,"/")[end])...",
                    color=:normal)
    ################################################################
    # Any logic about how to process metadata, data should go into #
    # the `config`; for now it is not used.                        #
    ################################################################
    # Check if there are pdf's in the documents and if the pdf to text
    # converter is available
    can_read_pdfs = false
    if isfile(PDFTOTEXT_PROGRAM)
        can_read_pdfs = true
    end
    if !can_read_pdfs && any(map(file->endswith(file, ".pdf"), files))
        @warn """PDF files will be ignored, reader program missing.
                 To read PDF files, define a program (i.e. pdftotext)
                 using the PDFTOTEXT_PROGRAM engine variable."""
    end
    for (i, file) in enumerate(files)
        # Read data
        sentences, meta = _read_file_data(file,
                                          language,
                                          can_read_pdfs,
                                          build_summary,
                                          summary_ns,
                                          summarization_strip_flags)
        # Update document and metadata vectors
        documents[i] = sentences
        metadata_vector[i] = meta
        # Update progressbar
        show_progress && next!(progressbar)
    end
    return documents, metadata_vector
end

function _read_file_data(file::AbstractString,
                         language::String,
                         can_read_pdfs::Bool=false,
                         build_summary::Bool=false,
                         summary_ns::Int=1,
                         summarization_strip_flags::UInt32=0)
    if endswith(file, ".pdf")
        if can_read_pdfs
            raw_data = read(`$PDFTOTEXT_PROGRAM $file -`, String)
        else
            raw_data = ""
        end
    else
        raw_data = open(fid->read(fid, String), file)
    end
    # Split into sentences
    sentences = sentence_tokenize(raw_data)
    # Create summary if the case
    if build_summary
        # TODO(Corneliu): Optimize this bit for performance
        #                 i.e. investigate PageRank parameters
        sentences = summarize(sentences, ns=summary_ns,
                              flags=summarization_strip_flags)
    end
    # Language detection (from 3 sentences max)
    if language == "auto"
        some_text = join(sentences[1:min(3, length(sentences))], " ")
        lang = detect_language(some_text)
    else
        lang = get(STR_TO_LANG, language, DEFAULT_LANGUAGE)()  # instantiate as well
    end
    # Add some real metadata
    meta = DocumentMetadata(lang, ("" for _ in 1:9)...)
    setfield!(meta, :name, readuntil(file,"\n"))  # set name the first line
    setfield!(meta, :id, file)  # set id the filename
    return sentences, meta
end