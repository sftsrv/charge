import charge
import charge/error
import gleam/list
import gleam/regexp
import gleam/result
import mellie/attr
import mellie/element.{ElementNode, TextNode}
import mellie/html

// Gleam's regex.split will retain the captured content
const footnote_re = "\\[\\^(.+?)\\]"

fn reference_re() {
  let assert Ok(re) = regexp.from_string(footnote_re)
  re
}

fn target_re() {
  let assert Ok(re) = regexp.from_string(footnote_re <> ":")
  re
}

fn reference(label) {
  html.sup(
    [
      attr.id("footnote-reference-" <> label),
      attr.class("footnote-reference"),
    ],
    [
      html.a(
        [
          attr.href("#footnote-target-" <> label),
        ],
        [html.text(label)],
      ),
    ],
  )
}

fn target(label) {
  html.span([], [
    html.a(
      [
        attr.id("footnote-target-" <> label),
        attr.href("#footnote-reference-" <> label),
        attr.class("footnote-target"),
      ],
      [html.text(label)],
    ),
    html.text(":"),
  ])
}

// Splits look like: ["text", "id", "text", "id", "text" ... ]
fn join(splits: List(String), make) {
  case splits {
    [] -> []
    [last] -> [html.text(last)]
    [text, id, ..rst] -> [html.text(text), make(id), ..join(rst, make)]
  }
}

fn replace_text(str, re, make) {
  let parts = re |> regexp.split(str)

  join(parts, make)
}

fn update_rec(html, updater) {
  case html {
    TextNode(text) -> {
      text |> updater
    }
    ElementNode(tag, _, children) -> {
      case tag {
        // don't recurse into weird tags
        "head" | "script" | "style" | "pre" -> [html]
        _ ->
          ElementNode(
            ..html,
            children: children
              |> list.map(update_rec(_, updater))
              |> list.flatten,
          )
          |> list.wrap
      }
    }
  }
}

fn update(html, updater) {
  update_rec(html, updater)
  |> list.first
  |> result.replace_error(error.FootnoteError(
    "Error replacing footnotes in HTML",
  ))
}

/// Parse markdown footnote in the structure of `[^123]` or `[^Some words here]`
/// And link it to any collected footnote references as `[^123]: Some description like this`
pub fn with_footnotes(from) {
  from
  |> charge.map_asset(fn(_, a) {
    use file <- charge.if_html(a, a |> Ok)

    file.html
    |> update(replace_text(_, target_re(), target))
    |> result.try(update(_, replace_text(_, reference_re(), reference)))
    |> result.map(charge.update_html(file, _))
  })
}
