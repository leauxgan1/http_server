# Zig HTTP server implementation

An http server project for learning the HTTP standard using the new Io implementation which will maintain compatibility with different forms of asynchronicity as they are released by the ZSF.

## About

> This project is still in development and is in need of many features listed below

## Features
[X] Request 
[X] Response 
[X] Router

- [X] Static Routes
- [X] Dynamic Routes
- [_] URL Parameter Parsing

[X] Handler functions
[_] Context
[_] Middleware
[_] Security

- [_] User Input Escaping

[_] Database integration/injection 

## Development

Current development is focusing on using context and middleware to avoid storing data in the main request and response structs and to use little memory for the average case.
Additionally, the security concerns of user input are being analyzed to ensure users' machines won't be compromized by malicious input.

## Alternatives

If you have somehow found out about this project before finding [http.zig]() or [tokamak]() or even [zap](), then please go check out those first while this project is catching up :).
