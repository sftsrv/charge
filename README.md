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
pnpm add @gleam-lang/highlight dom-serializer@3 htmlparser2@12 marked@18 marked-katex-extension@5 sharp@0 shiki@4
```

## Usage

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

HTML is defined using `mellie`, a simple page would look a bit like this:

```gleam
fn index(path, title, tags, entries) {
  html.body([], [
    header(title, tags),
    html.main([], [html.ul([], entries |> list.map(item))]),
  ])
  |> shared.page(title, css_path)
  |> charge.generated_html_file(path, _)
}
```

There are a few other plugins and composition functions that are useful for more complex site pipelines. Further documentation can be found at <https://hexdocs.pm/charge>.

For a complete example of a pipeline with all rendering included, take a look at `src/charge/preset/default.gleam`

## Development

Commands needed for development are outlined in [`maskfile.md`](/maskfile.md)
