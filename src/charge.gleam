import charge/async
import charge/component
import charge/error.{type ChargeResult}
import charge/fs
import charge/internal/component as internal_component
import charge/internal/watch
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import mellie
import mellie/element.{type ElementTree}

/// Represents the current collection of data in the pipeline
pub opaque type Loaded(pages, aggregate) {
  Loaded(pages: pages, aggregated: aggregate)
}

pub type Renderer(aggregate) =
  fn() -> Promise(ChargeResult(Loaded(List(Asset), aggregate)))

/// Represents the list of assets rendered in a pipeline so far
pub type Rendered =
  List(Asset)

/// Represents an HTML file that will be comitted to disk when assets are written
pub type HTMLFile {
  HTMLFile(source: Option(fs.Path), path: fs.SitePath, html: ElementTree)
}

/// Types of assets within a pipeline
pub opaque type Asset {
  /// Represents a directory that will be copied
  CopyDirAsset(from: fs.Path, to: fs.SitePath)
  /// Represents an HTML file that will be written to disk
  HTMLFileAsset(HTMLFile)
  /// Represents a generic text file that will be written to disk
  TextFile(path: fs.SitePath, content: String)

  /// Represents a list of files that would have been written as a result of a task
  TaskResult(fs.SitePath)
}

/// Represents a composable pipeline with `state` and `aggregate` data that is
/// passed between stages
pub opaque type Pipeline(aggregate) {
  Pipeline(
    out_dir: fs.Path,
    // load: Loader(state, aggregate),
    /// Loads all data in so that any non-render output
    /// can be shared with other pages and pipelines
    /// Process a single page - receives aggregated data
    render: Renderer(aggregate),
  )
}

/// Createa a new pipeline from scratch
pub fn new(
  out out_dir: fs.Path,
  load load: fn() -> ChargeResult(Loaded(List(a), b)),
  render render: fn(List(a), b) -> ChargeResult(List(Asset)),
) -> Pipeline(b) {
  Pipeline(out_dir, fn() {
    use loaded <- async.try_resolve(load())
    use rendered <- async.try_resolve(render(loaded.pages, loaded.aggregated))

    Loaded(pages: rendered, aggregated: loaded.aggregated)
    |> Ok
    |> promise.resolve
  })
}

/// Create the loaded data to be returned from a pipeline
pub fn loaded(
  pages pages: page,
  aggregate aggregate: aggregate,
) -> Loaded(page, aggregate) {
  Loaded(pages, aggregate)
}

/// Switches a pipelines data context using a transform
pub fn switch(
  from: Pipeline(a),
  transform: fn(a) -> Result(b, error.ChargeError),
) -> Pipeline(b) {
  switch_async(from, async.to_async1(transform))
}

/// Switches a pipelines data context using an async transform
pub fn switch_async(
  from: Pipeline(a),
  transform: fn(a) -> Promise(Result(b, error.ChargeError)),
) -> Pipeline(b) {
  Pipeline(..from, render: fn() {
    use rendered <- promise.try_await(from.render())
    use aggregated <- promise.try_await(transform(rendered.aggregated))

    Loaded(..rendered, aggregated:) |> Ok |> promise.resolve
  })
}

/// The raw unit creating assets asnychronously
pub fn with_async(
  from: Pipeline(aggregate),
  render: fn(aggregate) -> Promise(ChargeResult(Rendered)),
) -> Pipeline(aggregate) {
  Pipeline(..from, render: fn() {
    use prev_result <- promise.try_await(from.render())

    use rendered <- promise.try_await(render(prev_result.aggregated))

    Loaded(..prev_result, pages: merge_rendered(prev_result.pages, rendered))
    |> Ok
    |> promise.resolve
  })
}

/// The raw unit for creating assets
pub fn with(
  from: Pipeline(aggregate),
  render: fn(aggregate) -> ChargeResult(Rendered),
) -> Pipeline(aggregate) {
  with_async(from, async.to_async1(render))
}

/// Run a transformation over each rendered asset
pub fn map_asset(
  from: Pipeline(aggregate),
  update: fn(aggregate, Asset) -> ChargeResult(Asset),
) -> Pipeline(aggregate) {
  map_asset_async(from, async.to_async2(update))
}

/// Run an async transformation over each rendered asset
pub fn map_asset_async(
  from: Pipeline(aggregate),
  update: fn(aggregate, Asset) -> Promise(ChargeResult(Asset)),
) -> Pipeline(aggregate) {
  Pipeline(..from, render: fn() {
    use prev_result <- promise.try_await(from.render())

    prev_result.pages
    |> list.map(update(prev_result.aggregated, _))
    |> promise.await_list
    |> promise.map(error.collate_errors)
    |> promise.map_try(fn(rendered) {
      Loaded(..prev_result, pages: rendered)
      |> Ok
    })
  })
}

/// Derive some assets from the pipeline aggregate
pub fn with_assets(
  from: Pipeline(aggregate),
  render: fn(aggregate) -> ChargeResult(List(Asset)),
) -> Pipeline(aggregate) {
  Pipeline(..from, render: fn() {
    use prev_result <- promise.try_await(from.render())

    render(prev_result.aggregated)
    |> result.map(fn(rendered) {
      Loaded(..prev_result, pages: merge_rendered(prev_result.pages, rendered))
    })
    |> promise.resolve
  })
}

/// Derive an asset from the pipeline aggregate
pub fn with_asset(
  from: Pipeline(aggregate),
  render: fn(aggregate) -> ChargeResult(Asset),
) -> Pipeline(aggregate) {
  use agg <- with(from)
  use out <- result.map(render(agg))

  out |> list.wrap
}

/// Add a static directory to be copied as part of the pipeline
pub fn with_static_dir(
  pipeline: Pipeline(aggregate),
  dir: fs.Path,
) -> Pipeline(aggregate) {
  use _ <- with(pipeline)
  use to <- result.map(fs.site_path_from_string("/"))

  CopyDirAsset(dir, to) |> list.wrap
}

/// Add server-side components to the pipeline
/// Components can be defined using `component.new`.
///
/// Async components can be defined using `with_async_component`
pub fn with_components(
  from: Pipeline(aggregate),
  comps: List(component.Component(aggregate, ChargeResult(ElementTree))),
) -> Pipeline(aggregate) {
  from
  |> map_asset(fn(agg, a) {
    use file <- if_html(a, a |> Ok)
    let data =
      component.RenderData(
        out_dir: from.out_dir,
        site_path: file.path,
        source_path: file.source,
        data: agg,
      )
    internal_component.render(data, file.html, comps)
    |> result.map(fn(html) { HTMLFile(..file, html:) |> HTMLFileAsset })
  })
}

/// Add a server-side component to the pipeline
/// Components can be defined using `component.new`.
///
/// Async components can be defined using `with_async_component`
pub fn with_component(
  from: Pipeline(aggregate),
  component: component.Component(aggregate, ChargeResult(ElementTree)),
) -> Pipeline(aggregate) {
  with_components(from, [component])
}

/// Add a server-side component to the pipeline
/// Components can be defined using `component.new`.
///
/// Sync components can be defined using `with_component` or `with_components`
pub fn with_async_component(
  from: Pipeline(aggregate),
  comp: component.Component(
    aggregate,
    Promise(Result(ElementTree, error.ChargeError)),
  ),
) -> Pipeline(aggregate) {
  from
  |> map_asset_async(fn(agg, a) {
    use file <- if_html(a, promise.resolve(Ok(a)))

    let data =
      component.RenderData(
        out_dir: from.out_dir,
        site_path: file.path,
        source_path: file.source,
        data: agg,
      )

    internal_component.render_async(data, file.html, comp)
    |> promise.map_try(fn(html) {
      HTMLFile(..file, html: html)
      |> HTMLFileAsset
      |> Ok
    })
  })
}

/// Add assets that are derived from an existing asset, e.g. providing an alternate of each page
pub fn with_derived_assets(
  from: Pipeline(aggregate),
  extract: fn(Asset) -> ChargeResult(List(Asset)),
) -> Pipeline(aggregate) {
  Pipeline(..from, render: fn() {
    use prev_result <- promise.try_await(from.render())

    prev_result.pages
    |> list.map(extract)
    |> error.collate_errors
    |> result.map(list.flatten)
    |> result.map(fn(rendered) {
      Loaded(..prev_result, pages: merge_rendered(prev_result.pages, rendered))
    })
    |> promise.resolve
  })
}

/// Add some generic tasks into the pipeline given all the assets rendered till this point as well as the relevant aggregate
/// e.g. running creating an accessibility report on all generated html pages, creating an RSS Feed, etc.
///
/// This receives all previously processed assets so it should likely only be used once all other assets
/// are fully processed
pub fn with_summary(
  from: Pipeline(aggregate),
  summarize: fn(List(Asset), aggregate) ->
    Result(List(Asset), error.ChargeError),
) -> Pipeline(aggregate) {
  Pipeline(..from, render: fn() {
    use prev_result <- promise.try_await(from.render())

    summarize(prev_result.pages, prev_result.aggregated)
    |> result.map(fn(rendered) {
      Loaded(..prev_result, pages: merge_rendered(prev_result.pages, rendered))
    })
    |> promise.resolve
  })
}

/// Cleans the output directory and runs the pipeline
pub fn run(
  pipeline: Pipeline(aggregate),
) -> Promise(ChargeResult(List(Asset))) {
  pipeline |> run_(True)
}

/// Runs a pipeline without cleaning the directory first.
/// In future this will retain any cached data as well
///
/// This is currently only reactive to content changes and
/// will not re-run if the Gleam source changes. Not sure
/// if there's a way to make that work
pub fn run_dev(
  pipeline: Pipeline(aggregate),
) -> Promise(Result(List(Asset), error.ChargeError)) {
  watch.watch(fs.cwd(), [pipeline.out_dir], fn() { run_(pipeline, False) })
}

/// Cleans the output directory and runs the pipeline
fn run_(
  pipeline: Pipeline(aggregate),
  clean: Bool,
) -> Promise(ChargeResult(List(Asset))) {
  use _ <- async.try_resolve(case clean {
    False -> Ok(Nil)
    True ->
      fs.delete_dir_if_exists(pipeline.out_dir)
      |> result.replace(Nil)
  })

  use rendered <- promise.try_await(pipeline.render())

  write_all(pipeline.out_dir, rendered.pages)
  |> result.replace(rendered.pages)
  |> promise.resolve
}

fn write_one(out_dir: fs.Path, output: Asset) -> ChargeResult(Nil) {
  case output {
    HTMLFileAsset(file) -> {
      fs.write_site_file(
        out_dir,
        file.path,
        file.html |> mellie.to_document_string,
      )
    }
    CopyDirAsset(from:, to:) -> fs.copy_site_dir(out_dir, from, to)
    TextFile(path, content) -> fs.write_site_file(out_dir, path, content)
    _ -> Ok(Nil)
  }
}

fn write_all(out_dir: fs.Path, assets: List(Asset)) -> ChargeResult(Nil) {
  // handle async asset rendering before comitting file
  assets
  |> list.map(write_one(out_dir, _))
  |> error.collate_errors
  |> result.replace(Nil)
}

/// Create an HTML File asset that is marked as `generated` - i.e. it is not based on another file on disk
pub fn generated_html_file(path: fs.SitePath, rendered: ElementTree) -> Asset {
  HTMLFile(None, path, rendered) |> HTMLFileAsset
}

/// Create an HTML File asset that is marked as `derived` - i.e. it is based on another source file on disk
/// such as a markdown file on disk
pub fn derived_html_file(
  source: fs.Path,
  path: fs.SitePath,
  rendered: ElementTree,
) -> Asset {
  HTMLFile(Some(source), path, rendered) |> HTMLFileAsset
}

fn sort_assets(assets: List(Asset)) -> List(Asset) {
  assets
  |> list.sort(fn(a, b) {
    string.compare(
      a |> asset_path |> fs.site_path_to_string,
      b |> asset_path |> fs.site_path_to_string,
    )
  })
}

fn asset_path(asset: Asset) -> fs.SitePath {
  case asset {
    HTMLFileAsset(file) -> file.path
    CopyDirAsset(from: _, to:) -> to
    TaskResult(path) -> path
    TextFile(path, _) -> path
  }
}

/// Converts an asset to a string - useful for snapshot testing.
pub fn asset_to_readable_string(asset: Asset) -> String {
  case asset {
    HTMLFileAsset(file) ->
      "HTMLFile: "
      <> file.source
      |> option.map(fs.path_to_string)
      |> option.unwrap("[no source]")
      <> ":"
      <> file.path |> fs.site_path_to_string
      <> "\n"
      <> file.html |> mellie.element_to_string_pretty
    CopyDirAsset(from, to) ->
      "CopyDir: \n  from: "
      <> from |> fs.path_to_string
      <> "\n  to: "
      <> to |> fs.site_path_to_string
    TaskResult(path) -> "Task Result: " <> path |> fs.site_path_to_string
    TextFile(path, content) ->
      "Text File : " <> path |> fs.site_path_to_string <> ":\n" <> content
  }
}

/// Find an asset given a `SitePath`
pub fn find_asset(
  assets: List(Asset),
  path: fs.SitePath,
) -> Result(Asset, Nil) {
  assets |> list.find(fn(a) { path == a |> asset_path })
}

/// Converts an asset to a string - useful for snapshot testing.
/// Assets are ordered by path and can be used for snapshot testing
pub fn assets_to_readable_string(assets: List(Asset)) -> String {
  assets
  |> sort_assets
  |> list.map(asset_to_readable_string)
  |> string.join("\n\n")
}

fn merge_rendered(a: Rendered, b: Rendered) -> Rendered {
  list.append(a, b)
}

/// Guard to be used for running transformations on HTML assets
pub fn if_html(asset: Asset, or_else: a, f: fn(HTMLFile) -> a) -> a {
  case asset {
    HTMLFileAsset(file) -> f(file)
    _ -> or_else
  }
}

/// Update the contents of an HTML file and convert it to an asset
pub fn update_html(file: HTMLFile, html: ElementTree) -> Asset {
  HTMLFile(..file, html:) |> HTMLFileAsset
}

/// Create a `TextFile` asset that will be written to disk
pub fn text_file(path: fs.SitePath, content: String) -> Asset {
  TextFile(path:, content:)
}
