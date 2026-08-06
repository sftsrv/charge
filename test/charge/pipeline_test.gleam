import birdie
import charge
import charge/component
import charge/error
import charge/footnote
import charge/fs
import charge/highlight
import charge/image
import charge/markdown
import charge/preset/default
import gleam/dict
import gleam/javascript/promise
import gleam/list
import gleam/result
import gleam/string
import mellie
import mellie/attr
import mellie/html

fn dir_to_string(dir) {
  let assert Ok(files) = fs.ls_dir(dir)

  files
  |> list.map(fs.path_to_string)
  |> list.sort(string.compare)
  |> string.join("\n")
}

pub fn ls_dir_test() {
  let assert Ok(dir) = fs.from_cwd("./test/workspace")

  dir_to_string(dir)
  |> birdie.snap("internal ls_dir")
}

pub fn default_pipeline_test() {
  let assert Ok(pages) = fs.from_cwd("./test/workspace/pages")
  let assert Ok(static) = fs.from_cwd("./test/workspace/static")
  let assert Ok(out) = fs.from_cwd("./test/.test-out")

  let pipeline = default.create_pipeline(out, pages, static)
  use rendered <- promise.await(pipeline |> charge.run)

  let assert Ok(assets) = rendered

  assets
  |> charge.assets_to_readable_string
  |> birdie.snap("default pipeline assets")
  |> promise.resolve
}

pub fn pipeline_with_components_test() {
  let assert Ok(pages) = fs.from_cwd("./test/workspace/pages")
  let assert Ok(static) = fs.from_cwd("./test/workspace/static")
  let assert Ok(out) = fs.from_cwd("./test/.test-out")

  let assert Ok(custom_tag_page_path) =
    fs.site_path_from_string("/blog/second_post.html")

  let assert Ok(text_output_file_path) =
    fs.site_path_from_string("/blog/second_post_text.html")

  let assert Ok(switched_data_path) =
    fs.site_path_from_string("/frontmatter-keys.txt")

  let with_my_custom_tag_extractor = charge.with_derived_assets(_, fn(a) {
    use file <- charge.if_html(a, Ok([]))

    let children = mellie.get_children_by_tag(file.html, "my-custom-tag")
    list.map(children, fn(child) {
      let text = child |> mellie.inner_text

      text
      |> html.text
      |> charge.generated_html_file(text_output_file_path, _)
    })
    |> Ok
  })

  let with_my_async_tag_updater = charge.with_async_component(
    _,
    component.new("my-async-tag", fn(_, child) {
      let text =
        child
        |> mellie.attrs
        |> dict.from_list
        |> dict.get("data")
        |> result.unwrap("data not found")
        |> mellie.text

      let new_el =
        mellie.element("my-updated-async-tag", child |> mellie.attrs, [
          mellie.text("Extracted text: "),
          text,
        ])

      new_el |> Ok |> promise.resolve
    }),
  )

  let my_custom_tag =
    component.new("my-custom-tag", fn(_, el) {
      let text =
        el
        |> mellie.inner_text

      let new_el =
        html.data(
          [
            attr.value(
              text
              |> string.replace("\n", " + "),
            ),
          ],
          [html.text("My Updated Tag")],
        )

      new_el |> Ok
    })

  let my_custom_image =
    component.new("my-custom-image", fn(_, el) {
      html.img(el |> mellie.attrs) |> Ok
    })

  let pipeline =
    markdown.from_markdown(
      out: out,
      dir: pages,
      decode: default.frontmatter_decoder,
      agg: default.group_by_tag,
      render: default.render_page,
    )
    |> footnote.with_footnotes
    // extracts custom tag before rendering
    |> with_my_custom_tag_extractor
    // creates task from async tag
    |> with_my_async_tag_updater
    // renders custom tag before rendering
    |> charge.with_components([my_custom_tag, my_custom_image])
    // image optimization should run after custom_image runs
    |> image.with_image_optimization(static)
    // shiki syntax highlighting
    |> highlight.with_syntax_highlighting
    |> charge.switch(fn(fm) { dict.keys(fm) |> string.join("\n") |> Ok })
    |> charge.with_asset(fn(keys) {
      charge.text_file(switched_data_path, keys) |> Ok
    })

  use rendered <- promise.await(pipeline |> charge.run)
  let assert Ok(assets) = rendered

  let assert Ok(custom_tag_page) =
    assets |> charge.find_asset(custom_tag_page_path)

  let assert Ok(text_output_page) =
    assets |> charge.find_asset(text_output_file_path)

  let assert Ok(switched_data_page) =
    assets |> charge.find_asset(switched_data_path)

  [custom_tag_page, text_output_page, switched_data_page]
  |> charge.assets_to_readable_string
  |> birdie.snap("custom component assets")
  |> promise.resolve
}

pub fn print_error_test() {
  let err =
    error.Collated([
      error.Context(
        "my/file1.md",
        error.Collated([
          error.Context("2021-1212", error.DateParseError("Invalid date")),
          error.ErrorReadingFrontmatter("Invalid frontmatter"),
        ]),
      ),
      error.Context(
        "my/file2.md",
        error.Collated([
          error.DirNotFound("/my/example/dir"),
        ]),
      ),
    ])

  err |> error.error_to_string |> birdie.snap("nested error formatting")
}
