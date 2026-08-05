import charge/error.{type ChargeResult}
import gleam/dict.{type Dict}
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/result
import mellie/element.{type ElementTree, ElementNode, TextNode}

type Visit(a, b) =
  fn(a, ElementTree) -> b

pub type Component(a, b) =
  #(String, Visit(a, b))

/// Updates content depth-first with the given components
fn render_rec(
  data: a,
  components: Dict(String, Visit(a, ChargeResult(ElementTree))),
  el: ElementTree,
) -> ChargeResult(ElementTree) {
  case el {
    TextNode(_) -> el |> Ok
    ElementNode(tag:, attributes: _, children:) -> {
      use inner_children <- result.try(
        children
        |> list.map(render_rec(data, components, _))
        |> error.collate_errors,
      )

      let inner_updated = ElementNode(..el, children: inner_children)

      let visit = components |> dict.get(tag)

      case visit {
        Ok(visit) -> {
          visit(data, inner_updated)
        }
        Error(_) -> {
          inner_updated |> Ok
        }
      }
    }
  }
}

/// Runs components over the given HTML depth-first
pub fn render(
  data: a,
  html: ElementTree,
  components: List(Component(a, ChargeResult(ElementTree))),
) {
  components
  |> dict.from_list
  |> render_rec(data, _, html)
}

fn render_rec_async(
  data,
  tag,
  visit: fn(a, ElementTree) -> Promise(ChargeResult(ElementTree)),
  el: ElementTree,
) -> Promise(ChargeResult(ElementTree)) {
  case el {
    TextNode(_) -> el |> Ok |> promise.resolve
    ElementNode(tag: t, attributes: _, children:) -> {
      let children_task =
        children
        |> list.map(render_rec_async(data, tag, visit, _))
        |> promise.await_list
        |> promise.map(error.collate_errors)

      children_task
      |> promise.try_await(fn(new_children) {
        let new_el = ElementNode(..el, children: new_children)
        case tag == t {
          False -> new_el |> Ok |> promise.resolve
          True -> visit(data, new_el)
        }
      })
    }
  }
}

/// Visits all nodes that a component expects
pub fn render_async(
  data: a,
  html: ElementTree,
  component: Component(a, Promise(ChargeResult(ElementTree))),
) -> Promise(ChargeResult(ElementTree)) {
  let #(tag, visit) = component

  let result = render_rec_async(data, tag, visit, html)

  result
}
