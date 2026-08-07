import charge/fs
import gleam/javascript/array.{type Array}
import gleam/javascript/promise.{type Promise}
import gleam/list

@external(javascript, "./watch_ffi.mjs", "watch")
fn watch_(
  _root: String,
  _ignore: Array(String),
  _on_change: fn(String) -> Promise(a),
) -> Promise(a) {
  panic as "not supported for the given target"
}

/// This function will never actually resolve but this
/// composes well as a drop-in for a non-watched version of a function
pub fn watch(
  root: fs.Path,
  ignore: List(fs.Path),
  on_change: fn() -> Promise(a),
) -> Promise(a) {
  // intial run
  on_change()

  watch_(
    root |> fs.to_abs_string,
    ignore |> list.map(fs.to_abs_string) |> array.from_list,
    // runs on change
    fn(_) { on_change() },
  )
}
