use chrono::{DateTime, Datelike, FixedOffset, Local, Utc};
use ecow::EcoVec;
use parking_lot::Mutex;
use rustler::{Atom, Binary, Decoder, Encoder, Env, NewBinary, NifStruct, ResourceArc, Term};
use std::collections::HashMap;
use std::fmt::Display;
use std::num::NonZeroUsize;
use std::panic::{RefUnwindSafe, UnwindSafe};
use std::path::{Path, PathBuf};
use std::sync::LazyLock;
use std::sync::OnceLock;
use std::{fs, mem};
use typst::diag::{FileError, FileResult, Severity, SourceDiagnostic};
use typst::foundations::{Bytes, Datetime, Dict, Smart, Str, Value};
use typst::layout::PageRanges;
use typst::layout::PagedDocument;
use typst::syntax::{FileId, Source, VirtualPath};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Feature, Features, Library, LibraryExt, World};
use typst_html::HtmlDocument;
use typst_kit::download::{DownloadState, Downloader, Progress};
use typst_kit::fonts::{FontSlot, Fonts};
use typst_kit::package::PackageStorage;
use typst_pdf::{PdfOptions, PdfStandard, PdfStandards};
use typst_timing::{timed, TimingScope};

static MARKUP_ID: LazyLock<FileId> =
    LazyLock::new(|| FileId::new_fake(VirtualPath::new("MARKUP.typ")));

rustler::atoms! {
    ok,
    pdf_1_7,
    pdf_a_2b,
    pdf_a_3b,
    error,
    warning
}

#[derive(NifStruct)]
#[module = "AshTypst.Context.Options"]
pub struct ContextOptionsNif {
    pub root: String,
    pub font_paths: Vec<String>,
    pub ignore_system_fonts: bool,
}

#[derive(NifStruct)]
#[module = "AshTypst.PDFOptions"]
pub struct PdfOptionsNif {
    pub pages: Option<String>,
    pub pdf_standards: Vec<PdfStandardNif>,
    pub document_id: Option<String>,
}

#[derive(NifStruct)]
#[module = "AshTypst.FontOptions"]
pub struct FontOptionsNif {
    pub font_paths: Vec<String>,
    pub ignore_system_fonts: bool,
}

#[derive(NifStruct)]
#[module = "AshTypst.CompileResult"]
pub struct CompileResultNif {
    pub page_count: usize,
    pub warnings: Vec<DiagnosticNif>,
}

#[derive(NifStruct)]
#[module = "AshTypst.CompileError"]
pub struct CompileErrorNif {
    pub diagnostics: Vec<DiagnosticNif>,
}

#[derive(NifStruct)]
#[module = "AshTypst.Diagnostic"]
pub struct DiagnosticNif {
    pub severity: SeverityNif,
    pub message: String,
    pub span: Option<SpanNif>,
    pub trace: Vec<TraceItemNif>,
    pub hints: Vec<String>,
}

#[derive(NifStruct)]
#[module = "AshTypst.Span"]
pub struct SpanNif {
    pub start: usize,
    pub end: usize,
    pub line: Option<usize>,
    pub column: Option<usize>,
}

#[derive(NifStruct)]
#[module = "AshTypst.TraceItem"]
pub struct TraceItemNif {
    pub span: Option<SpanNif>,
    pub message: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SeverityNif {
    Error,
    Warning,
}

impl Decoder<'_> for SeverityNif {
    fn decode(term: Term) -> Result<Self, rustler::Error> {
        let atom: Atom = term.decode()?;
        if atom == error() {
            Ok(SeverityNif::Error)
        } else if atom == warning() {
            Ok(SeverityNif::Warning)
        } else {
            Err(rustler::Error::BadArg)
        }
    }
}

impl Encoder for SeverityNif {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match self {
            SeverityNif::Error => error().encode(env),
            SeverityNif::Warning => warning().encode(env),
        }
    }
}

impl From<Severity> for SeverityNif {
    fn from(severity: Severity) -> Self {
        match severity {
            Severity::Error => SeverityNif::Error,
            Severity::Warning => SeverityNif::Warning,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PdfStandardNif {
    Pdf17,
    PdfA2b,
    PdfA3b,
}

impl Decoder<'_> for PdfStandardNif {
    fn decode(term: Term) -> Result<Self, rustler::Error> {
        let atom: Atom = term.decode()?;
        if atom == pdf_1_7() {
            Ok(PdfStandardNif::Pdf17)
        } else if atom == pdf_a_2b() {
            Ok(PdfStandardNif::PdfA2b)
        } else if atom == pdf_a_3b() {
            Ok(PdfStandardNif::PdfA3b)
        } else {
            Err(rustler::Error::BadArg)
        }
    }
}

impl Encoder for PdfStandardNif {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match self {
            PdfStandardNif::Pdf17 => pdf_1_7().encode(env),
            PdfStandardNif::PdfA2b => pdf_a_2b().encode(env),
            PdfStandardNif::PdfA3b => pdf_a_3b().encode(env),
        }
    }
}

impl From<PdfStandardNif> for PdfStandard {
    fn from(standard: PdfStandardNif) -> Self {
        match standard {
            PdfStandardNif::Pdf17 => PdfStandard::V_1_7,
            PdfStandardNif::PdfA2b => PdfStandard::A_2b,
            PdfStandardNif::PdfA3b => PdfStandard::A_3b,
        }
    }
}

impl PdfOptionsNif {
    fn to_pdf_options(&self) -> Result<PdfOptions<'_>, String> {
        let mut opts = PdfOptions::default();

        if let Some(ref document_id) = self.document_id {
            opts.ident = Smart::Custom(document_id.as_str());
        }

        if !self.pdf_standards.is_empty() {
            let standards: Vec<PdfStandard> =
                self.pdf_standards.iter().map(|&s| s.into()).collect();
            opts.standards = PdfStandards::new(&standards)
                .map_err(|e| format!("Invalid PDF standards: {}", e))?;
        }

        Ok(opts)
    }
}

pub struct SystemWorld {
    root: PathBuf,
    main: FileId,
    markup: String,
    library: LazyHash<Library>,
    book: LazyHash<FontBook>,
    fonts: Vec<FontSlot>,
    slots: Mutex<HashMap<FileId, FileSlot>>,
    package_storage: PackageStorage,
    now: Now,
    virtual_files: HashMap<String, Vec<u8>>,
    inputs: HashMap<String, String>,
}

impl SystemWorld {
    pub fn new(root: PathBuf, font_paths: Vec<PathBuf>, ignore_system_fonts: bool) -> Self {
        let filtered_paths: Vec<PathBuf> = font_paths
            .into_iter()
            .filter(|p| p.exists() && p.is_dir())
            .collect();

        let include_system_fonts = !ignore_system_fonts;

        let fonts = if filtered_paths.is_empty() {
            Fonts::searcher()
                .include_system_fonts(include_system_fonts)
                .search()
        } else {
            Fonts::searcher()
                .include_system_fonts(include_system_fonts)
                .search_with(filtered_paths)
        };

        let user_agent = concat!("typst/", env!("CARGO_PKG_VERSION"));
        Self {
            root,
            main: *MARKUP_ID,
            markup: String::new(),
            library: LazyHash::new(
                Library::builder()
                    .with_features(Features::from_iter([Feature::Html]))
                    .build(),
            ),
            book: LazyHash::new(fonts.book),
            fonts: fonts.fonts,
            slots: Mutex::new(HashMap::new()),
            package_storage: PackageStorage::new(None, None, Downloader::new(user_agent)),
            now: Now::System(OnceLock::new()),
            virtual_files: HashMap::new(),
            inputs: HashMap::new(),
        }
    }

    pub fn reset(&mut self) {
        for slot in self.slots.get_mut().values_mut() {
            slot.reset();
        }
        if let Now::System(time_lock) = &mut self.now {
            time_lock.take();
        }
    }

    fn rebuild_library(&mut self) {
        let mut dict = Dict::new();
        for (key, value) in &self.inputs {
            dict.insert(
                Str::from(key.as_str()),
                Value::Str(Str::from(value.as_str())),
            );
        }
        self.library = LazyHash::new(
            Library::builder()
                .with_inputs(dict)
                .with_features(Features::from_iter([Feature::Html]))
                .build(),
        );
    }
}

impl World for SystemWorld {
    fn library(&self) -> &LazyHash<Library> {
        &self.library
    }

    fn book(&self) -> &LazyHash<FontBook> {
        &self.book
    }

    fn main(&self) -> FileId {
        self.main
    }

    fn source(&self, id: FileId) -> FileResult<Source> {
        if id == *MARKUP_ID {
            return Ok(Source::new(id, self.markup.clone()));
        }

        if let Some(path) = id.vpath().as_rootless_path().to_str() {
            if let Some(content) = self.virtual_files.get(path) {
                let text = decode_utf8(content)?;
                return Ok(Source::new(id, text.into()));
            }
        }

        self.slot(id, |slot| slot.source(&self.root, &self.package_storage))
    }

    fn file(&self, id: FileId) -> FileResult<Bytes> {
        if let Some(path) = id.vpath().as_rootless_path().to_str() {
            if let Some(content) = self.virtual_files.get(path) {
                return Ok(Bytes::new(content.clone()));
            }
        }

        self.slot(id, |slot| slot.file(&self.root, &self.package_storage))
    }

    fn font(&self, index: usize) -> Option<Font> {
        self.fonts.get(index)?.get()
    }

    fn today(&self, offset: Option<i64>) -> Option<Datetime> {
        let now = match &self.now {
            Now::Fixed(time) => time,
            Now::System(time) => time.get_or_init(Utc::now),
        };

        let with_offset = match offset {
            None => now.with_timezone(&Local).fixed_offset(),
            Some(hours) => {
                let seconds = i32::try_from(hours).ok()?.checked_mul(3600)?;
                now.with_timezone(&FixedOffset::east_opt(seconds)?)
            }
        };

        Datetime::from_ymd(
            with_offset.year(),
            with_offset.month().try_into().ok()?,
            with_offset.day().try_into().ok()?,
        )
    }
}

impl SystemWorld {
    fn slot<F, T>(&self, id: FileId, f: F) -> T
    where
        F: FnOnce(&mut FileSlot) -> T,
    {
        let mut map = self.slots.lock();
        f(map.entry(id).or_insert_with(|| FileSlot::new(id)))
    }
}

struct FileSlot {
    id: FileId,
    source: SlotCell<Source>,
    file: SlotCell<Bytes>,
}

impl FileSlot {
    fn new(id: FileId) -> Self {
        Self {
            id,
            file: SlotCell::new(),
            source: SlotCell::new(),
        }
    }

    fn reset(&mut self) {
        self.source.reset();
        self.file.reset();
    }

    fn source(
        &mut self,
        project_root: &Path,
        package_storage: &PackageStorage,
    ) -> FileResult<Source> {
        self.source.get_or_init(
            || read(self.id, project_root, package_storage),
            |data, prev| {
                let name = if prev.is_some() {
                    "reparsing file"
                } else {
                    "parsing file"
                };
                let _scope = TimingScope::new(name);
                let text = decode_utf8(&data)?;
                if let Some(mut prev) = prev {
                    prev.replace(text);
                    Ok(prev)
                } else {
                    Ok(Source::new(self.id, text.into()))
                }
            },
        )
    }

    fn file(&mut self, project_root: &Path, package_storage: &PackageStorage) -> FileResult<Bytes> {
        self.file.get_or_init(
            || read(self.id, project_root, package_storage),
            |data, _| Ok(Bytes::new(data)),
        )
    }
}

struct SlotCell<T> {
    data: Option<FileResult<T>>,
    fingerprint: u128,
    accessed: bool,
}

impl<T: Clone> SlotCell<T> {
    fn new() -> Self {
        Self {
            data: None,
            fingerprint: 0,
            accessed: false,
        }
    }

    fn reset(&mut self) {
        self.accessed = false;
    }

    fn get_or_init(
        &mut self,
        load: impl FnOnce() -> FileResult<Vec<u8>>,
        f: impl FnOnce(Vec<u8>, Option<T>) -> FileResult<T>,
    ) -> FileResult<T> {
        if mem::replace(&mut self.accessed, true) {
            if let Some(data) = &self.data {
                return data.clone();
            }
        }

        let result = timed!("loading file", load());
        let fingerprint = timed!("hashing file", typst::utils::hash128(&result));

        if mem::replace(&mut self.fingerprint, fingerprint) == fingerprint {
            if let Some(data) = &self.data {
                return data.clone();
            }
        }

        let prev = self.data.take().and_then(Result::ok);
        let value = result.and_then(|data| f(data, prev));
        self.data = Some(value.clone());

        value
    }
}

pub struct SilentDownloadProgress<T>(pub T);

impl<T: Display> Progress for SilentDownloadProgress<T> {
    fn print_start(&mut self) {}
    fn print_progress(&mut self, _state: &DownloadState) {}
    fn print_finish(&mut self, _state: &DownloadState) {}
}

fn system_path(
    project_root: &Path,
    id: FileId,
    package_storage: &PackageStorage,
) -> FileResult<PathBuf> {
    let buf;
    let mut root = project_root;
    if let Some(spec) = id.package() {
        buf = package_storage.prepare_package(spec, &mut SilentDownloadProgress(&spec))?;
        root = &buf;
    }

    id.vpath().resolve(root).ok_or(FileError::AccessDenied)
}

fn read(id: FileId, project_root: &Path, package_storage: &PackageStorage) -> FileResult<Vec<u8>> {
    read_from_disk(&system_path(project_root, id, package_storage)?)
}

fn read_from_disk(path: &Path) -> FileResult<Vec<u8>> {
    let f = |e| FileError::from_io(e, path);
    if fs::metadata(path).map_err(f)?.is_dir() {
        Err(FileError::IsDirectory)
    } else {
        fs::read(path).map_err(f)
    }
}

fn decode_utf8(buf: &[u8]) -> FileResult<&str> {
    Ok(std::str::from_utf8(
        buf.strip_prefix(b"\xef\xbb\xbf").unwrap_or(buf),
    )?)
}

enum Now {
    #[allow(dead_code)]
    Fixed(DateTime<Utc>),
    System(OnceLock<DateTime<Utc>>),
}

pub struct TypstContext {
    world: Mutex<SystemWorld>,
    document: Mutex<Option<PagedDocument>>,
}

impl UnwindSafe for TypstContext {}
impl RefUnwindSafe for TypstContext {}

#[rustler::resource_impl]
impl rustler::Resource for TypstContext {}

fn resolve_line_column(
    span: typst::syntax::Span,
    byte_offset: usize,
    world: &SystemWorld,
) -> (Option<usize>, Option<usize>) {
    span.id()
        .and_then(|id| world.source(id).ok())
        .map(|source| {
            let lines = source.lines();
            let line = lines.byte_to_line(byte_offset).map(|l| l + 1);
            let column = lines.byte_to_column(byte_offset).map(|c| c + 1);
            (line, column)
        })
        .unwrap_or((None, None))
}

fn span_to_nif(span: typst::syntax::Span, world: &SystemWorld) -> Option<SpanNif> {
    span.range().map(|range| {
        let (line, column) = resolve_line_column(span, range.start, world);
        SpanNif {
            start: range.start,
            end: range.end,
            line,
            column,
        }
    })
}

fn span_to_nif_simple(span: typst::syntax::Span) -> Option<SpanNif> {
    span.range().map(|range| SpanNif {
        start: range.start,
        end: range.end,
        line: None,
        column: None,
    })
}

fn diagnostic_to_nif(d: &SourceDiagnostic, world: &SystemWorld) -> DiagnosticNif {
    DiagnosticNif {
        severity: d.severity.into(),
        message: d.message.to_string(),
        span: span_to_nif(d.span, world),
        trace: d
            .trace
            .iter()
            .map(|item| TraceItemNif {
                span: span_to_nif(item.span, world),
                message: item.v.to_string(),
            })
            .collect(),
        hints: d.hints.iter().map(|h| h.to_string()).collect(),
    }
}

fn diagnostics_to_vec(
    diagnostics: EcoVec<SourceDiagnostic>,
    world: &SystemWorld,
) -> Vec<DiagnosticNif> {
    diagnostics
        .iter()
        .map(|d| diagnostic_to_nif(d, world))
        .collect()
}

fn diagnostics_to_vec_simple(diagnostics: EcoVec<SourceDiagnostic>) -> Vec<DiagnosticNif> {
    diagnostics
        .iter()
        .map(|d| DiagnosticNif {
            severity: d.severity.into(),
            message: d.message.to_string(),
            span: span_to_nif_simple(d.span),
            trace: d
                .trace
                .iter()
                .map(|item| TraceItemNif {
                    span: span_to_nif_simple(item.span),
                    message: item.v.to_string(),
                })
                .collect(),
            hints: d.hints.iter().map(|h| h.to_string()).collect(),
        })
        .collect()
}

fn simple_error(message: &str) -> CompileErrorNif {
    CompileErrorNif {
        diagnostics: vec![DiagnosticNif {
            severity: SeverityNif::Error,
            message: message.to_string(),
            span: None,
            trace: vec![],
            hints: vec![],
        }],
    }
}

/// Parse "1-3,5,7-9" into PageRanges (1-indexed inclusive ranges using NonZeroUsize).
fn parse_page_ranges(pages: &str, total: usize) -> Result<PageRanges, String> {
    use std::ops::RangeInclusive;

    let mut ranges: Vec<RangeInclusive<Option<NonZeroUsize>>> = Vec::new();
    for part in pages.split(',') {
        let part = part.trim();
        if part.contains('-') {
            let mut iter = part.splitn(2, '-');
            let start: usize = iter
                .next()
                .unwrap()
                .trim()
                .parse()
                .map_err(|_| format!("Invalid page number in range: {}", part))?;
            let end: usize = iter
                .next()
                .unwrap()
                .trim()
                .parse()
                .map_err(|_| format!("Invalid page number in range: {}", part))?;
            if start < 1 || end < 1 || start > total || end > total || start > end {
                return Err(format!("Page range out of bounds: {}", part));
            }
            ranges.push(NonZeroUsize::new(start)..=NonZeroUsize::new(end));
        } else {
            let page: usize = part
                .parse()
                .map_err(|_| format!("Invalid page number: {}", part))?;
            if page < 1 || page > total {
                return Err(format!("Page number out of bounds: {}", page));
            }
            let nz = NonZeroUsize::new(page);
            ranges.push(nz..=nz);
        }
    }
    Ok(PageRanges::new(ranges))
}

#[rustler::nif(schedule = "DirtyIo")]
fn context_new(opts: ContextOptionsNif) -> ResourceArc<TypstContext> {
    let root = PathBuf::from(&opts.root);
    let font_paths: Vec<PathBuf> = opts.font_paths.iter().map(PathBuf::from).collect();
    let world = SystemWorld::new(root, font_paths, opts.ignore_system_fonts);
    ResourceArc::new(TypstContext {
        world: Mutex::new(world),
        document: Mutex::new(None),
    })
}

#[rustler::nif]
fn context_set_markup(ctx: ResourceArc<TypstContext>, markup: String) -> Atom {
    let mut world = ctx.world.lock();
    world.markup = markup;
    world.reset();
    *ctx.document.lock() = None;
    ok()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn context_compile(ctx: ResourceArc<TypstContext>) -> Result<CompileResultNif, CompileErrorNif> {
    let mut world_guard = ctx.world.lock();
    world_guard.reset();
    let result = typst::compile::<PagedDocument>(&*world_guard);
    match result.output {
        Ok(document) => {
            let page_count = document.pages.len();
            let warnings = diagnostics_to_vec(result.warnings, &*world_guard);
            *ctx.document.lock() = Some(document);
            Ok(CompileResultNif {
                page_count,
                warnings,
            })
        }
        Err(errors) => {
            let diagnostics = diagnostics_to_vec(errors, &*world_guard);
            *ctx.document.lock() = None;
            Err(CompileErrorNif { diagnostics })
        }
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn context_render_svg(
    ctx: ResourceArc<TypstContext>,
    page: usize,
) -> Result<String, CompileErrorNif> {
    let doc_guard = ctx.document.lock();
    let document = doc_guard
        .as_ref()
        .ok_or_else(|| simple_error("No compiled document. Call compile() first."))?;

    if page >= document.pages.len() {
        return Err(simple_error(&format!(
            "Page index {} out of bounds (document has {} pages)",
            page,
            document.pages.len()
        )));
    }

    Ok(typst_svg::svg(&document.pages[page]))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn context_export_pdf<'a>(
    env: Env<'a>,
    ctx: ResourceArc<TypstContext>,
    opts: PdfOptionsNif,
) -> Result<Binary<'a>, CompileErrorNif> {
    let doc_guard = ctx.document.lock();
    let document = doc_guard
        .as_ref()
        .ok_or_else(|| simple_error("No compiled document. Call compile() first."))?;

    let mut pdf_opts = opts.to_pdf_options().map_err(|e| simple_error(&e))?;

    if let Some(ref pages_str) = opts.pages {
        pdf_opts.page_ranges =
            Some(parse_page_ranges(pages_str, document.pages.len()).map_err(|e| simple_error(&e))?);
    }

    let pdf_bytes = typst_pdf::pdf(document, &pdf_opts).map_err(|e| CompileErrorNif {
        diagnostics: diagnostics_to_vec_simple(e),
    })?;

    let mut binary = NewBinary::new(env, pdf_bytes.len());
    binary.as_mut_slice().copy_from_slice(&pdf_bytes);
    Ok(binary.into())
}

#[rustler::nif]
fn context_font_families(ctx: ResourceArc<TypstContext>) -> Vec<String> {
    let world = ctx.world.lock();
    world
        .book
        .families()
        .map(|(name, _)| name.to_string())
        .collect()
}

#[rustler::nif]
fn context_set_virtual_file(ctx: ResourceArc<TypstContext>, path: String, content: String) -> Atom {
    let mut world = ctx.world.lock();
    world.virtual_files.insert(path, content.into_bytes());
    *ctx.document.lock() = None;
    ok()
}

#[rustler::nif]
fn context_append_virtual_file(
    ctx: ResourceArc<TypstContext>,
    path: String,
    chunk: String,
) -> Atom {
    let mut world = ctx.world.lock();
    world
        .virtual_files
        .entry(path)
        .or_default()
        .extend_from_slice(chunk.as_bytes());
    ok()
}

#[rustler::nif]
fn context_clear_virtual_file(ctx: ResourceArc<TypstContext>, path: String) -> Atom {
    let mut world = ctx.world.lock();
    world.virtual_files.remove(&path);
    *ctx.document.lock() = None;
    ok()
}

#[rustler::nif]
fn context_set_input(ctx: ResourceArc<TypstContext>, key: String, value: String) -> Atom {
    let mut world = ctx.world.lock();
    world.inputs.insert(key, value);
    world.rebuild_library();
    ok()
}

#[rustler::nif]
fn context_set_inputs(ctx: ResourceArc<TypstContext>, inputs: HashMap<String, String>) -> Atom {
    let mut world = ctx.world.lock();
    world.inputs = inputs;
    world.rebuild_library();
    ok()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn context_export_html(ctx: ResourceArc<TypstContext>) -> Result<String, CompileErrorNif> {
    let mut world_guard = ctx.world.lock();
    world_guard.reset();
    let result = typst::compile::<HtmlDocument>(&*world_guard);
    match result.output {
        Ok(html_doc) => match typst_html::html(&html_doc) {
            Ok(html_string) => Ok(html_string),
            Err(errors) => Err(CompileErrorNif {
                diagnostics: diagnostics_to_vec(errors, &*world_guard),
            }),
        },
        Err(errors) => Err(CompileErrorNif {
            diagnostics: diagnostics_to_vec(errors, &*world_guard),
        }),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn font_families(opts: FontOptionsNif) -> Vec<String> {
    let include_system_fonts = !opts.ignore_system_fonts;

    let font_paths_vec: Vec<PathBuf> = opts
        .font_paths
        .iter()
        .map(PathBuf::from)
        .filter(|p| p.exists() && p.is_dir())
        .collect();

    let fonts = if font_paths_vec.is_empty() {
        Fonts::searcher()
            .include_system_fonts(include_system_fonts)
            .search()
    } else {
        Fonts::searcher()
            .include_system_fonts(include_system_fonts)
            .search_with(font_paths_vec)
    };

    fonts
        .book
        .families()
        .map(|(name, _info)| name.to_string())
        .collect()
}

rustler::init!("Elixir.AshTypst.NIF");
