# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

## [1.0.0] - 2020-07-29
### Added
- GithubActions for CICD
- Documentation using Documenter.jl
- License
- Codecoverage

### Changed
- License is now MIT

## [0.3.1] - 2020-02-04
### Changed
- switched deprecated dependency AstParsers.jl to renamed ExprParsers.jl

## [0.2.1] - 2020-01-11
### Changed
- more stable macros by switching to use AstParsers.jl
- Continuables is now a wrapper type
- we now reuse functions from Base and Iterators instead of defining our own

## [0.1.0] - 2018-10-07
initial sketch
