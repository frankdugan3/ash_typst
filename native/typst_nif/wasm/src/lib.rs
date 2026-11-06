//! The editing intelligence of Typst for a browser editor: highlighting,
//! syntax errors, completion, hover, and go to definition. It knows no
//! editor: the input is files (path and text), and the output is plain data.
//! `js/worker.js` runs it in a Web Worker. Refer to `AshTypst.Wasm`.
//!
//! The module does not compile or render. The server makes each preview and
//! each document with the NIF. Thus the browser needs no font files, only
//! the list of the fonts of the server (`set_fonts`, `fonts.rs`).
//!
//! The crate is in the workspace of the NIF, with one lock, so the parser and
//! the analysis are the same as on the server. The world has the structure
//! of the `SystemWorld` of the NIF: the main file is `MARKUP.typ` at the
//! project root, the other files are virtual files at their paths, and the
//! library has the same features.
//!
//! Positions in the API are UTF-16 offsets, as in JavaScript strings.

mod fonts;

use std::collections::HashMap;
use std::sync::LazyLock;

use serde::Serialize;
use typst::diag::{FileError, FileResult};
use typst::foundations::{Bytes, Datetime, Duration, Output};
use typst::syntax::{
    DiagSpan, FileId, LinkedNode, RootedPath, Side, Source, VirtualPath, VirtualRoot,
};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Feature, Features, Library, LibraryExt, World, WorldExt};
use typst_ide::{Completion, CompletionKind, Definition, IdeWorld, Tooltip};
use wasm_bindgen::prelude::*;

static MARKUP_ID: LazyLock<FileId> = LazyLock::new(|| {
    FileId::unique(RootedPath::new(
        VirtualRoot::Project,
        VirtualPath::new("MARKUP.typ").unwrap(),
    ))
});

/// The features of the NIF (`enabled_features/0` in `typst_nif`). They change
/// the standard library that the analysis sees.
fn enabled_features() -> Features {
    Features::from_iter([Feature::Html, Feature::Bundle])
}

/// No document is compiled in the browser. The IDE functions get no output.
const NO_OUTPUT: Option<&dyn Output> = None;

struct EditorWorld {
    library: LazyHash<Library>,
    book: LazyHash<FontBook>,
    entry: String,
    sources: HashMap<String, Source>,
}

impl EditorWorld {
    fn id(&self, path: &str) -> FileId {
        if path == self.entry {
            *MARKUP_ID
        } else {
            FileId::unique(RootedPath::new(
                VirtualRoot::Project,
                VirtualPath::new(path).unwrap_or_else(|_| VirtualPath::new("invalid.typ").unwrap()),
            ))
        }
    }

    fn path_of(&self, id: FileId) -> String {
        if id == *MARKUP_ID {
            self.entry.clone()
        } else {
            id.vpath().get_without_slash().to_string()
        }
    }
}

impl World for EditorWorld {
    fn library(&self) -> &LazyHash<Library> {
        &self.library
    }

    fn book(&self) -> &LazyHash<FontBook> {
        &self.book
    }

    fn main(&self) -> FileId {
        *MARKUP_ID
    }

    fn source(&self, id: FileId) -> FileResult<Source> {
        let path = self.path_of(id);
        self.sources
            .get(&path)
            .cloned()
            .ok_or_else(|| FileError::NotFound(path.into()))
    }

    fn file(&self, id: FileId) -> FileResult<Bytes> {
        let path = self.path_of(id);
        match self.sources.get(&path) {
            Some(source) => Ok(Bytes::from_string(source.text().to_string())),
            None => Err(FileError::NotFound(path.into())),
        }
    }

    fn font(&self, _index: usize) -> Option<Font> {
        None
    }

    fn today(&self, _offset: Option<Duration>) -> Option<Datetime> {
        None
    }
}

impl IdeWorld for EditorWorld {
    fn upcast(&self) -> &dyn World {
        self
    }

    fn files(&self) -> Vec<FileId> {
        self.sources.keys().map(|path| self.id(path)).collect()
    }
}

#[derive(Serialize)]
struct DiagnosticOut {
    severity: &'static str,
    message: String,
    from: usize,
    to: usize,
    hints: Vec<String>,
}

#[derive(Serialize)]
struct CompletionOut {
    from: usize,
    items: Vec<CompletionItem>,
}

#[derive(Serialize)]
struct CompletionItem {
    label: String,
    apply: Option<String>,
    detail: Option<String>,
    kind: &'static str,
}

#[derive(Serialize)]
struct TooltipOut {
    kind: &'static str,
    text: String,
}

#[derive(Serialize)]
struct DefinitionOut {
    path: String,
    from: Option<usize>,
    to: Option<usize>,
}

#[derive(Serialize)]
struct BuildInfo {
    version: &'static str,
    typst: &'static str,
}

/// The analysis of one editor session.
#[wasm_bindgen]
pub struct Analyzer {
    world: EditorWorld,
}

impl Default for Analyzer {
    fn default() -> Self {
        Self::new()
    }
}

#[wasm_bindgen]
impl Analyzer {
    #[wasm_bindgen(constructor)]
    pub fn new() -> Analyzer {
        Analyzer {
            world: EditorWorld {
                library: LazyHash::new(
                    Library::builder().with_features(enabled_features()).build(),
                ),
                book: LazyHash::new(FontBook::new()),
                entry: "main.typ".to_string(),
                sources: HashMap::new(),
            },
        }
    }

    /// Sets the main file. A relative import in it resolves from the root.
    pub fn set_entry(&mut self, path: String) {
        if path == self.world.entry {
            return;
        }
        let old = std::mem::replace(&mut self.world.entry, path);
        // The IDs depend on the entry. Make the two sources again.
        for p in [old, self.world.entry.clone()] {
            if let Some(text) = self.world.sources.get(&p).map(|s| s.text().to_string()) {
                let id = self.world.id(&p);
                self.world.sources.insert(p, Source::new(id, text));
            }
        }
    }

    /// Sets the text of a file. A file that exists is reparsed incrementally.
    pub fn set_file(&mut self, path: String, text: String) {
        match self.world.sources.get_mut(&path) {
            Some(source) => {
                source.replace(&text);
            }
            None => {
                let id = self.world.id(&path);
                self.world.sources.insert(path, Source::new(id, text));
            }
        }
    }

    /// Removes a file.
    pub fn remove(&mut self, path: String) {
        self.world.sources.remove(&path);
    }

    /// Replaces the list of the fonts (`AshTypst.Wasm.fonts/1`): an array of
    /// family names or face metadata. The completion, the hover, and the
    /// unknown font warnings use it.
    pub fn set_fonts(&mut self, fonts: JsValue) -> Result<(), JsValue> {
        let fonts: Vec<fonts::FontIn> =
            serde_wasm_bindgen::from_value(fonts).map_err(|e| JsValue::from_str(&e.to_string()))?;
        self.world.book = LazyHash::new(fonts::book(fonts));
        Ok(())
    }

    /// Returns `[from, to, class, ...]` for the highlighted nodes of a file.
    /// The class is the CSS class of the tag (for example `typ-key`).
    pub fn highlight(&self, path: String) -> Vec<JsValue> {
        let Some(source) = self.world.sources.get(&path) else {
            return vec![];
        };
        let mut out = Vec::new();
        highlight_node(source, &LinkedNode::new(source.root()), &mut out);
        out
    }

    /// Returns the syntax errors and warnings of a file. The parser finds
    /// them without a compile. With a font list (`set_fonts`), a literal
    /// family of `text` that is not in the list is a warning too.
    pub fn syntax_errors(&self, path: String) -> Result<JsValue, JsValue> {
        let Some(source) = self.world.sources.get(&path) else {
            return to_js(&Vec::<DiagnosticOut>::new());
        };
        let (errors, warnings) = source.root().errors_and_warnings();
        let lines = source.lines();

        let unknown_fonts = fonts::unknown(source, &self.world.book)
            .into_iter()
            .filter_map(|(range, message)| {
                Some(DiagnosticOut {
                    severity: "warning",
                    message,
                    from: lines.byte_to_utf16(range.start)?,
                    to: lines.byte_to_utf16(range.end)?,
                    hints: vec![],
                })
            });

        let out: Vec<DiagnosticOut> = errors
            .iter()
            .chain(warnings.iter())
            .filter_map(|d| {
                let range = self.world.range(d.span)?;
                Some(DiagnosticOut {
                    severity: if d.is_error { "error" } else { "warning" },
                    message: d.message.to_string(),
                    from: lines.byte_to_utf16(range.start)?,
                    to: lines.byte_to_utf16(range.end)?,
                    hints: d.hints.iter().map(|h| h.v.to_string()).collect(),
                })
            })
            .chain(unknown_fonts)
            .collect();

        to_js(&out)
    }

    /// Returns the completions at the cursor (UTF-16 offset).
    pub fn autocomplete(
        &self,
        path: String,
        cursor: usize,
        explicit: bool,
    ) -> Result<JsValue, JsValue> {
        let Some((source, byte)) = self.at(&path, cursor) else {
            return Ok(JsValue::NULL);
        };

        match typst_ide::autocomplete(&self.world, NO_OUTPUT, source, byte, explicit) {
            Some((from, items)) => to_js(&CompletionOut {
                from: source.lines().byte_to_utf16(from).unwrap_or(cursor),
                items: items.into_iter().map(completion).collect(),
            }),
            None => Ok(JsValue::NULL),
        }
    }

    /// Returns the tooltip at the cursor (UTF-16 offset).
    pub fn tooltip(&self, path: String, cursor: usize) -> Result<JsValue, JsValue> {
        let Some((source, byte)) = self.at(&path, cursor) else {
            return Ok(JsValue::NULL);
        };

        match typst_ide::tooltip(&self.world, NO_OUTPUT, source, byte, Side::After) {
            Some(Tooltip::Text(text)) => to_js(&TooltipOut {
                kind: "text",
                text: text.to_string(),
            }),
            Some(Tooltip::Code(text)) => to_js(&TooltipOut {
                kind: "code",
                text: text.to_string(),
            }),
            None => Ok(JsValue::NULL),
        }
    }

    /// Returns the definition of the item at the cursor (UTF-16 offset).
    pub fn definition(&self, path: String, cursor: usize) -> Result<JsValue, JsValue> {
        let Some((source, byte)) = self.at(&path, cursor) else {
            return Ok(JsValue::NULL);
        };

        match typst_ide::definition(&self.world, NO_OUTPUT, source, byte, Side::After) {
            Some(Definition::Span(span)) => match self.span(span) {
                Some(out) => to_js(&out),
                None => Ok(JsValue::NULL),
            },
            Some(Definition::File(id)) => to_js(&DefinitionOut {
                path: self.world.path_of(id),
                from: None,
                to: None,
            }),
            Some(Definition::Std(_)) | None => Ok(JsValue::NULL),
        }
    }

    /// The identity of this build: the `ash_typst` version and the version
    /// of the compiled Typst crates. `AshTypst.Wasm.identity/0` gives the
    /// values of the server (the NIF).
    pub fn build_info() -> Result<JsValue, JsValue> {
        to_js(&BuildInfo {
            version: env!("ASH_TYPST_VERSION"),
            typst: typst::utils::version().raw(),
        })
    }
}

impl Analyzer {
    fn at(&self, path: &str, cursor: usize) -> Option<(&Source, usize)> {
        let source = self.world.sources.get(path)?;
        let byte = source.lines().utf16_to_byte(cursor)?;
        Some((source, byte))
    }

    fn span(&self, span: impl Into<DiagSpan>) -> Option<DefinitionOut> {
        let span = span.into();
        let id = span.id()?;
        let range = self.world.range(span)?;
        let source = self.world.source(id).ok()?;
        let lines = source.lines();

        Some(DefinitionOut {
            path: self.world.path_of(id),
            from: lines.byte_to_utf16(range.start),
            to: lines.byte_to_utf16(range.end),
        })
    }
}

fn highlight_node(source: &Source, node: &LinkedNode, out: &mut Vec<JsValue>) {
    if let Some(tag) = typst::syntax::highlight(node) {
        let range = node.range();
        let lines = source.lines();
        if let (Some(from), Some(to)) = (
            lines.byte_to_utf16(range.start),
            lines.byte_to_utf16(range.end),
        ) {
            if from < to {
                out.push(JsValue::from(from as u32));
                out.push(JsValue::from(to as u32));
                out.push(JsValue::from_str(tag.css_class()));
            }
        }
    }
    for child in node.children() {
        highlight_node(source, &child, out);
    }
}

fn completion(item: Completion) -> CompletionItem {
    CompletionItem {
        label: item.label.to_string(),
        apply: item.apply.map(|s| s.to_string()),
        detail: item.detail.map(|s| s.to_string()),
        kind: match item.kind {
            CompletionKind::Syntax => "keyword",
            CompletionKind::Func => "function",
            CompletionKind::Type => "type",
            CompletionKind::Param => "variable",
            CompletionKind::Constant => "constant",
            CompletionKind::Path => "text",
            CompletionKind::Package => "namespace",
            CompletionKind::Label => "property",
            CompletionKind::Font => "text",
            CompletionKind::Symbol(_) => "text",
        },
    }
}

fn to_js<T: Serialize>(value: &T) -> Result<JsValue, JsValue> {
    serde_wasm_bindgen::to_value(value).map_err(|e| JsValue::from_str(&e.to_string()))
}
