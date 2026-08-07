# Tasks

Tasks are runnable using [Mask](https://github.com/jacobdeichert/mask) or by copying and running them in your terminal
 
## install

```sh
gleam deps download
pnpm i
```

## build

```sh
gleam build
```

## test

```sh
gleam test
```

## snap

Update snapshots

```sh
gleam run -m birdie
```

## run-default

Runs the static site generator using the default preset and outputs it to .test-out

```sh
gleam run -m charge/preset/default -- --pages test/workspace/pages --static test/workspace/static --out .test-out
```

## dev-default

Runs the static site generator using the default preset and outputs it to .test-out with the --dev flag

```sh
gleam run -m charge/preset/default -- --pages test/workspace/pages --static test/workspace/static --out .test-out --dev
```

## docs

Preview the documentation

```sh
gleam docs build --open
```

## format

```sh
gleam format
```

## serve

```sh
pnpm serve .test-out
```
