![Alt text](https://github.com/zgornel/Garamond.jl/blob/master/docs/src/assets/logo.png)

[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://zgornel.github.io/Garamond.jl/dev)
[![Build Status (master)](https://travis-ci.com/zgornel/Garamond.jl.svg?token=8HcgFtAjpxwpdXiu8Fon&branch=master)](https://travis-ci.com/zgornel/Garamond.jl)
[![Coverage Status](https://coveralls.io/repos/github/zgornel/Garamond.jl/badge.svg?branch=master)](https://coveralls.io/github/zgornel/Garamond.jl?branch=master)

![Alt text](https://github.com/zgornel/Garamond.jl/blob/master/docs/src/assets/schematic.png)

## Installation

Installation can be performed by:
 - first cloning with `git clone https://github.com/zgornel/Garamond.jl`
 - then running `julia -e 'using Pkg; Pkg.activate("."); Pkg.instantiate()'` from the project root directory

Binary executables of the search server and clients can be built by running `./make.jl` from the `build/` directory.


## Usage
For information and examples over the usage of the search engine, visit the [documentation](https://zgornel.github.io/Garamond.jl/dev).


## License
This code has an MIT license.


## References
[Search engines on Wikipedia](https://en.wikipedia.org/wiki/Web_search_engine)

[Semantic search on Wikipedia](https://en.wikipedia.org/wiki/Semantic_search)

[Word embeddings](http://www.offconvex.org/2015/12/12/word-embeddings-1/)


## Acknowledgements
This work could not have been possible without the great work of the people developing all the Julia packages and other technologies Garamond is based upon.


## Citing
`
@misc{cofaru2019garamond,
      title={Garamond},
      author={Corneliu, Cofaru and others},
      year={2019},
      publisher={GitHub},
      howpublished={\url{https://github.com/zgornel/Garamond.jl}},
}
`
## Reporting Bugs
Garamond is at the moment under heavy development and much of the API and features are subject to change ¯\\_(ツ)_/¯. Please [file an issue](https://github.com/zgornel/Garamond.jl/issues/new) to report a bug or request a feature.
