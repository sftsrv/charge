import charge
import charge/error.{type ChargeResult, ErrorReadingFrontmatter}
import charge/fs
import charge/internal/markdown
import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/string
import mellie
import mellie/element.{type ElementTree}
import yamleam

/// Represents a parsed markdown file with frontmatter.
///
/// Markdown parsing uses [`marked`](https://marked.js.org/)
pub opaque type MarkdownFile(a) {
  MarkdownFile(
    path: fs.Path,
    site_path: fs.SitePath,
    frontmatter: a,
    content: ElementTree,
  )
}

fn read_file(
  dir: fs.Path,
  file: fs.Path,
  frontmatter_decoder,
) -> ChargeResult(MarkdownFile(a)) {
  use content <- result.try(fs.read_text_file(file))

  let lines = content |> string.trim |> string.split("\n")

  let not_end = fn(str) { !string.starts_with(str, "---") }
  let site_path = to_site_path(dir, file)
  let decode = frontmatter_decoder(site_path)

  case lines {
    ["---", ..rest] -> {
      let #(front, content) = list.split_while(rest, not_end)
      let fm = front |> string.join("\n")

      use frontmatter <- result.try(
        yamleam.parse(fm, decode)
        |> result.replace_error(
          ErrorReadingFrontmatter(fm)
          |> error.error_context(file |> fs.path_to_string),
        ),
      )

      let html =
        content
        |> list.drop(1)
        |> string.join("\n")
        |> render

      html
      |> result.map(MarkdownFile(file, site_path, frontmatter, _))
    }
    _ -> Error(ErrorReadingFrontmatter("No frontmatter present"))
  }
}

fn read_files(dir: fs.Path, decode_frontmatter) {
  use files <- result.try(fs.ls_dir(dir))

  files
  |> list.filter(fs.has_ext(_, [fs.MD, fs.MDX]))
  |> list.map(read_file(dir, _, decode_frontmatter))
  |> error.collate_errors
  |> result.map_error(error.error_context(_, dir |> fs.path_to_string))
}

/// Create a pipeline that loads markdown files as it's initial source with
/// included page rendering, aggregation, and frontmatter parsing
pub fn from_markdown(
  out out_dir: fs.Path,
  dir dir: fs.Path,
  decode decode: fn(fs.SitePath) -> decode.Decoder(a),
  agg agg: fn(List(a)) -> b,
  render render: fn(MarkdownFile(a), b) -> ChargeResult(ElementTree),
) -> charge.Pipeline(b) {
  charge.new(
    out: out_dir,
    load: fn() {
      use pages <- result.map(read_files(dir, decode))

      charge.loaded(pages, pages |> list.map(frontmatter) |> agg)
    },
    render: fn(pages: List(MarkdownFile(a)), agg: b) -> ChargeResult(
      charge.Rendered,
    ) {
      pages
      |> list.map(fn(page) {
        use rendered <- result.map(render(page, agg))

        rendered
        |> to_html_file(page, _)
      })
      |> error.collate_errors
    },
  )
}

/// Get the frontmatter from a markdown file
pub fn frontmatter(file: MarkdownFile(a)) {
  file.frontmatter
}

fn exts() {
  dict.new()
  |> dict.insert(fs.MD, fs.HTML)
  |> dict.insert(fs.MDX, fs.HTML)
}

fn to_site_path(base: fs.Path, file: fs.Path) {
  fs.to_site_path(base, file, exts())
}

/// Convert a markdown file to an HTML asset with fully-rendered HTML content
pub fn to_html_file(file: MarkdownFile(a), rendered: ElementTree) {
  charge.derived_html_file(file.path, file.site_path, rendered)
}

fn replace_body(tree: ElementTree) {
  tree
  |> mellie.get_child_by_tag("body")
  |> result.replace_error(error.ErrorRenderingMarkdown(
    "Failed to find body in rendered markdown",
  ))
  |> result.map(mellie.children)
  |> result.map(mellie.element("div", [], _))
}

fn render(content) -> ChargeResult(ElementTree) {
  content
  |> markdown.parse
  |> mellie.parse
  |> result.replace_error(error.ErrorRenderingMarkdown(
    "Error parsing HTML from markdown",
  ))
  |> result.try(replace_body)
}

pub fn content(file: MarkdownFile(a)) {
  file.content
}
