import charge/fs
import gleam/option
import mellie/element.{type ElementTree}

type Visit(a) =
  fn(RenderData, ElementTree) -> a

pub type Component(a) =
  #(String, Visit(a))

/// Create a new component given a `tag` and `visit` method.
/// Thie type of `visit` will depend on the context in which the component is being used
pub fn new(tag tag, visit visit: Visit(a)) {
  #(tag, visit)
}

/// Data to be passed when rendering a component
pub type RenderData {
  RenderData(
    /// The path of the source file that the HTML comes from
    source_path: option.Option(fs.Path),
    /// The path of the HTML file being rendered
    site_path: fs.SitePath,
    /// The output directory for the pipeline
    out_dir: fs.Path,
  )
}
