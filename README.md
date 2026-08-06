# charge

[![Package Version](https://img.shields.io/hexpm/v/charge)](https://hex.pm/packages/charge)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/charge/)

A composable, component-based, static site generator for Gleam

> _charge_ because, you know - "static"

## Installation

```sh
gleam add charge@1 mellie@2
```

`charge` targets JavaScript and depends on a few packages for important functionality, you'll also need to install the following dependencies from npm using your JavaScript package manager:

```sh
# using pnpm for example
pnpm add @gleam-lang/highlight.js-gleam@1 dom-serializer@3 htmlparser2@12 marked@18 marked-katex-extension@5 sharp@0 shiki@4
```

## Features

> Take a look at the [Getting Started Guide](https://charge.hexdocs.pm/getting-started.html) to - ya know, get started

`charge` uses a rendering pipeline that's defined in terms of data loading and asset transformation. Complex behavior can be composed from smaller parts that operate on previously rendered assets.

Some of the functionality that's provided out of the box is:

- Generation of pages from Markdown
- Sync and Async rendering of server-side components
- Image optimization
- Syntax highlighting
- RSS Feed generation

Due to the composability of pipelines, you can add in additional functionality with minimal overhead

## Getting Started

> Complete documentation can be found at <https://hexdocs.pm/charge>.

`charge` works by defining a processing pipeline for files and provides utilities to help simplify and manage dependent and asynchronous tasks for doing this

A basic pipeline can be defined in terms of the provided functions as such:

```gleam
import charge
import charge/fs
import chage/image

let assert Ok(out_dir) = fs.from_cwd("./dist")
let assert Ok(public_dir) = fs.from_cwd("./public")
let assert Ok(content_dir) = fs.from_cwd("./pages")

let pipeline =
  // loads markdown files and parses frontmatter
  markdown.from_markdown(
    out: out_dir,
    dir: content_dir,
    // decoder for frontmatter
    decode: frontmatter_decoder,
    // function to aggregate initial content
    agg: group_by_tag,
    // renderer for each page associated with a given markdown file
    render: render_page,
  )
  // create custom page assets
  |> charge.with_assets(tag_pages)
  |> charge.with_asset(index_page)
  //
  |> charge.with_components([my_custom_tag_renderer])
  // copy over some static files
  |> charge.with_static_dir(public_dir)
  // optimize images using sharp
  |> image.with_image_optimization(public_dir)

pipeline
|> charge.run
|> promise.await(todo as "handle result")
```

HTML is defined using [`mellie`](https://mellie.hexdocs.pm), a simple page would look a bit like this:

```gleam
import mellie/html

fn index(path, title, tags, entries) {
  html.body([], [
    header(title, tags),
    html.main([], [html.ul([], entries |> list.map(item))]),
  ])
  |> shared.page(title, css_path)
  |> charge.generated_html_file(path, _)
}
```

For a complete example of a pipeline with all rendering included, take a look at `src/charge/preset/default.gleam`

## Development

Commands needed for development are outlined in [`maskfile.md`](/maskfile.md)
