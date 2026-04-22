# jumpy_game

[![Package Version](https://img.shields.io/hexpm/v/jumpy_game)](https://hex.pm/packages/jumpy_game)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/jumpy_game/)

## About

A simple game where you hold space bar to charge a cubes jump and try to land on as many platforms in a row as possible without falling.

## Development

```sh
gleam run -m lustre/dev start   # Run the project
gleam test  # Run the tests
```

## Deploying

With `bun` installed, run:

```sh
bun install
gleam run -m lustre/dev build --minify
```

The HTML, JavaScript, and CSS files are placed in the `dist` folder.

Do not open `dist/index.html` directly with `file://...`.
Modern browsers block ES module loading from local file URLs, which causes
errors like "CORS request not http".

Serve the folder with a local HTTP server instead:

```sh
python3 -m http.server 4173 -d dist
```

Then open <http://localhost:4173>.

Or use the npm scripts:

```sh
npm run build:web
npm run preview
```