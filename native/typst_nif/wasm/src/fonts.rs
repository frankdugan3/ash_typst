//! The fonts of the editor: a list of font metadata (`AshTypst.Wasm.fonts/1`
//! on the server), without font files. The analysis only reads the font
//! book: the completion and the hover of `text(font: "...")`, and the
//! warning on an unknown family.

use std::ops::Range;

use serde::Deserialize;
use typst::layout::Ratio;
use typst::syntax::ast::{self, AstNode};
use typst::syntax::{LinkedNode, Source};
use typst::text::{
    AxisValue, Coverage, FontAxis, FontBook, FontFlags, FontInfo, FontStretch, FontStyle,
    FontVariant, FontWeight, Tag,
};

/// An entry of the list: a family name, or a face with its metadata (the
/// map of `AshTypst.Context.font_face/0`). Only `family` is necessary.
#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub enum FontIn {
    Family(String),
    Face(FaceIn),
}

#[derive(Debug, Deserialize)]
pub struct FaceIn {
    family: String,
    #[serde(default)]
    style: Option<String>,
    #[serde(default)]
    weight: Option<u16>,
    #[serde(default)]
    stretch: Option<f64>,
    #[serde(default)]
    math: bool,
    #[serde(default)]
    variable: bool,
    #[serde(default)]
    axes: Vec<AxisIn>,
}

#[derive(Debug, Deserialize)]
pub struct AxisIn {
    tag: String,
    min: f32,
    max: f32,
    default: f32,
}

impl FontIn {
    /// The font info. The coverage is empty: the analysis does not use it.
    pub fn into_info(self) -> FontInfo {
        let face = match self {
            FontIn::Family(family) => FaceIn {
                family,
                style: None,
                weight: None,
                stretch: None,
                math: false,
                variable: false,
                axes: Vec::new(),
            },
            FontIn::Face(face) => face,
        };

        let style = match face.style.as_deref() {
            Some("italic") => FontStyle::Italic,
            Some("oblique") => FontStyle::Oblique,
            _ => FontStyle::Normal,
        };
        let weight = face
            .weight
            .map_or(FontWeight::REGULAR, FontWeight::from_number);
        let stretch = face.stretch.map_or(FontStretch::NORMAL, |ratio| {
            FontStretch::from_ratio(Ratio::new(ratio))
        });

        let mut flags = FontFlags::empty();
        flags.set(FontFlags::MATH, face.math);
        flags.set(FontFlags::VARIABLE, face.variable);

        FontInfo {
            family: face.family,
            variant: FontVariant::new(style, weight, stretch),
            flags,
            axes: face
                .axes
                .into_iter()
                .filter(|axis| axis.tag.len() == 4)
                .map(|axis| FontAxis {
                    tag: Tag::from_bytes_lossy(axis.tag.as_bytes()),
                    min: AxisValue(axis.min),
                    max: AxisValue(axis.max),
                    default: AxisValue(axis.default),
                })
                .collect(),
            coverage: Coverage::from_vec(Vec::new()),
        }
    }
}

/// The font book of a list.
pub fn book(fonts: Vec<FontIn>) -> FontBook {
    FontBook::from_infos(fonts.into_iter().map(FontIn::into_info))
}

/// The literal family names in the `font` argument of `text` (a call or a
/// set rule) that are not in the book: the byte range of each string and
/// the message of the warning of Typst (`check_font_list`). The family of
/// a variable is unknown without an evaluation, thus it is not checked.
///
/// An empty book means that the editor has no list: nothing is checked.
pub fn unknown(source: &Source, book: &FontBook) -> Vec<(Range<usize>, String)> {
    let mut out = Vec::new();
    if book.families().next().is_some() {
        visit(source, book, &LinkedNode::new(source.root()), &mut out);
    }
    out
}

fn visit(
    source: &Source,
    book: &FontBook,
    node: &LinkedNode,
    out: &mut Vec<(Range<usize>, String)>,
) {
    let args = if let Some(call) = node.cast::<ast::FuncCall>() {
        is_text(call.callee()).then(|| call.args())
    } else if let Some(rule) = node.cast::<ast::SetRule>() {
        is_text(rule.target()).then(|| rule.args())
    } else {
        None
    };

    for arg in args.into_iter().flat_map(|args| args.items()) {
        if let ast::Arg::Named(named) = arg {
            if named.name().as_str() == "font" {
                check_list(source, book, named.expr(), out);
            }
        }
    }

    for child in node.children() {
        visit(source, book, &child, out);
    }
}

fn is_text(callee: ast::Expr) -> bool {
    matches!(callee, ast::Expr::Ident(ident) if ident.as_str() == "text")
}

/// A `FontList`: a family, or an array of families.
fn check_list(
    source: &Source,
    book: &FontBook,
    expr: ast::Expr,
    out: &mut Vec<(Range<usize>, String)>,
) {
    match expr {
        ast::Expr::Array(array) => {
            for item in array.items() {
                if let ast::ArrayItem::Pos(expr) = item {
                    check_family(source, book, expr, out);
                }
            }
        }
        expr => check_family(source, book, expr, out),
    }
}

/// A `FontFamily`: a string, or a dictionary with the string `name`.
fn check_family(
    source: &Source,
    book: &FontBook,
    expr: ast::Expr,
    out: &mut Vec<(Range<usize>, String)>,
) {
    let name = match expr {
        ast::Expr::Str(string) => Some(string),
        ast::Expr::Dict(dict) => dict.items().find_map(|item| match item {
            ast::DictItem::Named(named) if named.name().as_str() == "name" => match named.expr() {
                ast::Expr::Str(string) => Some(string),
                _ => None,
            },
            _ => None,
        }),
        _ => None,
    };

    if let Some(string) = name {
        let family = string.get();
        if book
            .select_family(family.to_lowercase().as_str())
            .next()
            .is_none()
        {
            if let Some(range) = source.find(string.span()).map(|node| node.range()) {
                out.push((range, format!("unknown font family: {family}")));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fonts(json: &str) -> Vec<FontIn> {
        serde_json::from_str(json).unwrap()
    }

    fn messages(text: &str, book: &FontBook) -> Vec<(String, String)> {
        let source = Source::detached(text);
        unknown(&source, book)
            .into_iter()
            .map(|(range, message)| (text[range].to_string(), message))
            .collect()
    }

    #[test]
    fn a_face_has_its_metadata() {
        let info = fonts(
            r#"[{"family": "Inter", "style": "italic", "weight": 700, "stretch": 0.75,
                 "math": true, "variable": true,
                 "axes": [{"tag": "wght", "min": 100, "max": 900, "default": 400}]}]"#,
        )
        .pop()
        .unwrap()
        .into_info();

        assert_eq!(info.family, "Inter");
        assert_eq!(info.variant.style, FontStyle::Italic);
        assert_eq!(info.variant.weight, FontWeight::BOLD);
        assert_eq!(info.variant.stretch, FontStretch::CONDENSED);
        assert!(info.flags.contains(FontFlags::MATH | FontFlags::VARIABLE));
        assert_eq!(info.axes.len(), 1);
        assert_eq!(info.axes[0].tag, Tag::from_bytes(b"wght"));
        assert_eq!(info.axes[0].max, AxisValue(900.0));
    }

    #[test]
    fn a_string_is_a_family_with_the_defaults() {
        let info = fonts(r#"["Fira Math"]"#).pop().unwrap().into_info();

        assert_eq!(info.family, "Fira Math");
        assert_eq!(info.variant, FontVariant::default());
        assert!(info.flags.is_empty());
        assert!(info.axes.is_empty());
    }

    #[test]
    fn the_book_has_the_families() {
        let book = book(fonts(
            r#"["Inter", {"family": "Inter", "weight": 700}, "Fira Math"]"#,
        ));

        assert_eq!(book.families().count(), 2);
        assert_eq!(book.select_family("inter").count(), 2);
    }

    #[test]
    fn unknown_families_of_text_are_warnings() {
        let book = book(fonts(r#"["Inter", "Fira Math"]"#));

        let text = r#"
#set text(font: "Nope")
#text(font: ("inter", "Gone", (name: "Missing", covers: "latin-in-cjk")))[x]
#show heading: set text(font: "FIRA MATH")
#let f = "Variable"
#text(font: f)[y]
#box(font: "Other")
"#;

        assert_eq!(
            messages(text, &book),
            vec![
                (
                    "\"Nope\"".to_string(),
                    "unknown font family: Nope".to_string()
                ),
                (
                    "\"Gone\"".to_string(),
                    "unknown font family: Gone".to_string()
                ),
                (
                    "\"Missing\"".to_string(),
                    "unknown font family: Missing".to_string()
                ),
            ]
        );
    }

    #[test]
    fn nothing_is_checked_without_a_list() {
        assert!(messages(r#"#text(font: "Nope")[x]"#, &FontBook::new()).is_empty());
    }
}
