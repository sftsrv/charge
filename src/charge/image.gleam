import charge
import charge/async
import charge/component
import charge/error.{type ChargeResult}
import charge/fs
import charge/internal/sharp
import gleam/dict
import gleam/float
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import gleam/string
import gleam/uri
import glexif
import mellie
import mellie/attr

pub type ExifMetadata {
  ExifMetadata(
    iso: Option(String),
    shutter_speed: Option(String),
    aperture: Option(String),
    camera_make: Option(String),
    camera_model: Option(String),
    lens_make: Option(String),
    lens_model: Option(String),
    focal_length: Option(String),
  )
}

pub type Metadata {
  Metadata(width: Int, height: Int, exif: ExifMetadata)
}

fn optimized_images_path() {
  let assert Ok(path) = fs.site_path_from_string("/optimized-images")

  path
}

/// Optimize all images that can be resolved within the HTML using [sharp](https://sharp.pixelplumbing.com/).
/// Images are converted to WEBP
///
/// Images are resolved with respect to the `static_images_dir` provided or the current HTML file's source
/// and put into the `/optimized-images` path in the pipeline's output
/// 
/// Additionally it will append the following attributes to the element:
/// 
/// - `orientation` of `horizontal` or `vertical`
/// - `aspect-ratio`
pub fn with_image_optimization(pipeline, static_images_dir: fs.Path) {
  let optimized_dir = optimized_images_path()

  pipeline
  |> charge.with_async_component(
    component.new("img", fn(data, el) {
      let task =
        case mellie.attr(el, "src") {
          Error(_) -> None
          Ok(src) -> {
            // If we can't optimize an image then we just skip it
            let resolved =
              result.unwrap(
                resolve(static_images_dir, data.source_path, src),
                None,
              )
            {
              use input_path <- option.map(resolved)
              case can_optimize(input_path) {
                False -> None
                True -> {
                  let output = get_output_path(optimized_dir, input_path)

                  optimize_image_task(data.out_dir, input_path, output)
                  |> promise.await(fn(_) {
                    render_image(el, input_path, output)
                  })
                  |> Some
                }
              }
            }
          }
        }
        |> option.flatten

      case task {
        Some(t) -> t
        None -> promise.resolve(Ok(el))
      }
    }),
  )
}

fn can_optimize(input_path: fs.Path) -> Bool {
  fs.has_ext(input_path, optimized_exts())
}

fn optimize_image_task(out_dir, input_path, site_path) {
  use output_path <- async.try_resolve(fs.site_path_to_path(out_dir, site_path))

  sharp.optimize_image(input_path, output_path)
  |> promise.map_try(fn(_) { Ok([site_path]) })
}

fn from_uri_path(src) {
  uri.percent_decode(src)
  |> result.replace_error(error.InvalidImageSrc(src))
}

pub fn percent_encode(p) {
  p
  |> string.split("/")
  |> list.map(uri.percent_encode)
  |> string.join("/")
}

/// Resolves a file path if it exists
fn resolve(static_dir: fs.Path, source: Option(fs.Path), src: String) {
  case src {
    "https://" <> _ | "http://" <> _ -> Ok(None)

    // relative to static dir
    "/" <> src -> {
      from_uri_path(src)
      |> result.try(fs.resolve(static_dir, _))
      |> result.map(fn(p) {
        case fs.is_file(p) {
          True -> Some(p)
          False -> None
        }
      })
    }

    // otherwise must be relative to source file
    _ ->
      case source {
        None -> Error(error.ImageNotFound(src))
        Some(file) -> {
          let src =
            from_uri_path(src)
            |> result.unwrap(src)

          let dir = fs.parent(file)

          dir
          |> result.try(fs.resolve(_, src))
          |> result.map(fn(p) {
            case fs.is_file(p) {
              True -> Some(p)
              False -> None
            }
          })
        }
      }
  }
}

fn optimized_exts() {
  [fs.JPG, fs.JPEG, fs.PNG]
}

fn optimized_ext_mapping() {
  optimized_exts()
  |> list.map(pair.new(_, fs.WEBP))
  |> dict.from_list
}

fn get_output_path(optimized_images_path: fs.SitePath, input: fs.Path) {
  fs.to_site_path(fs.cwd(), input, optimized_ext_mapping())
  |> fs.concat_site_path(optimized_images_path, _)
}

pub fn read_metadata(input_file: fs.Path) -> Promise(ChargeResult(Metadata)) {
  let path = input_file |> fs.to_abs_string
  // using sharp for the height and width sincce this correctly accounts for rotation
  // and supports all image formats (not just jpeg)
  use sharp_meta <- promise.try_await(sharp.meta(input_file))

  let glexif_meta = glexif.get_exif_data_for_file(path)
  case glexif_meta {
    Error(_) ->
      Metadata(
        sharp_meta.width,
        sharp_meta.height,
        exif: ExifMetadata(None, None, None, None, None, None, None, None),
      )
    Ok(meta) -> {
      Metadata(
        sharp_meta.width,
        sharp_meta.height,
        exif: ExifMetadata(
          camera_make: meta.make,
          camera_model: meta.model,
          lens_make: meta.lens_make,
          lens_model: meta.lens_model,
          focal_length: meta.focal_length
            |> option.map(fn(f) {
              case f {
                f if f <. 10.0 -> f |> float.to_precision(1) |> float.to_string
                _ -> f |> float.round |> int.to_string
              }
            }),
          iso: meta.iso |> option.map(int.to_string),
          shutter_speed: meta.exposure_time
            |> option.map(fn(f) {
              case f.denominator {
                1 -> f.numerator |> int.to_string <> "\""
                _ ->
                  f.numerator |> int.to_string
                  <> "/"
                  <> f.denominator |> int.to_string
                  <> "s"
              }
            }),
          aperture: meta.f_number
            |> option.or(meta.aperture_value)
            |> option.map(fn(a) {
              let is_zero_decimal =
                float.absolute_value(a -. float.to_precision(a, 1)) <. 0.01

              case is_zero_decimal {
                True -> a |> float.round |> int.to_string
                False -> a |> float.to_precision(1) |> float.to_string
              }
            }),
        ),
      )
    }
  }
  |> Ok
  |> promise.resolve
}

fn render_image(img, input: fs.Path, output: fs.SitePath) {
  use meta <- promise.try_await(sharp.meta(input))

  let aspect_ratio =
    meta
    |> sharp.aspect_ratio
    |> float.to_string
    |> mellie.attribute("aspect-ratio", _)

  let orientation =
    case sharp.orientation(meta) {
      sharp.Vertical -> "vertical"
      sharp.Horizontal -> "horizontal"
    }
    |> mellie.attribute("orientation", _)

  let alt = mellie.attr(img, "img") |> option.from_result

  let src = output |> fs.site_path_to_string |> percent_encode |> attr.src
  let alt =
    attr.alt(
      alt
      |> option.unwrap(fs.file_name_only(input)),
    )

  let result =
    img
    |> mellie.set_attributes([src, alt, aspect_ratio, orientation])

  result |> Ok |> promise.resolve
}
