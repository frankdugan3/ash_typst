use chrono::{DateTime, Datelike, FixedOffset, Local, Utc};
use ecow::EcoVec;
use parking_lot::Mutex;
use rustler::{Atom, Decoder, Encoder, Env, Error, NifStruct, Term};
use std::collections::HashMap;
use std::fmt::Display;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;
use std::sync::OnceLock;
use std::{fs, mem};
use typst::diag::{FileError, FileResult, Severity, SourceDiagnostic};
use typst::foundations::Smart;
use typst::foundations::{Bytes, Datetime};
use typst::layout::PagedDocument;
use typst::syntax::{FileId, Source, VirtualPath};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt, World};
use typst_kit::download::{DownloadState, Downloader, Progress};
use typst_kit::fonts::{FontSlot, Fonts};
use typst_kit::package::PackageStorage;
use typst_pdf::{PdfOptions, PdfStandard, PdfStandards};
use typst_timing::{timed, TimingScope};

static MARKUP_ID: LazyLock<FileId> =
    LazyLock::new(|| FileId::new_fake(VirtualPath::new("MARKUP.tsp")));

#[derive(NifStruct)]
#[module = "AshTypst.PreviewOptions"]
pub struct PreviewOptionsNif {
    pub font_paths: Vec<String>,
    pub ignore_system_fonts: bool,
}

#[derive(NifStruct)]
#[module = "AshTypst.PDFOptions"]
pub struct PdfOptionsNif {
    pub pages: Option<String>,
    pub pdf_standards: Vec<PdfStandardNif>,
    pub document_id: Option<String>,
    pub font_paths: Vec<String>,
    pub ignore_system_fonts: bool,
}

#[derive(NifStruct)]
#[module = "AshTypst.FontOptions"]
pub struct FontOptionsNif {
    pub font_paths: Vec<String>,
    pub ignore_system_fonts: bool,
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
}

#[derive(NifStruct)]
#[module = "AshTypst.TraceItem"]
pub struct TraceItemNif {
    pub span: Option<SpanNif>,
    pub message: String,
}

#[derive(NifStruct)]
#[module = "AshTypst.CompileError"]
pub struct CompileErrorNif {
    pub diagnostics: Vec<DiagnosticNif>,
}

impl From<&SourceDiagnostic> for DiagnosticNif {
    fn from(diagnostic: &SourceDiagnostic) -> Self {
        Self {
            severity: diagnostic.severity.into(),
            message: diagnostic.message.to_string(),
            span: diagnostic.span.range().map(|range| SpanNif {
                start: range.start,
                end: range.end,
            }),
            trace: diagnostic
                .trace
                .iter()
                .map(|item| {
                    let span = item.span.range().map(|range| SpanNif {
                        start: range.start,
                        end: range.end,
                    });
                    TraceItemNif {
                        span,
                        message: item.v.to_string(),
                    }
                })
                .collect(),
            hints: diagnostic
                .hints
                .iter()
                .map(|hint| hint.to_string())
                .collect(),
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
    fn to_pdf_options(&self) -> Result<PdfOptions<'_>, Error> {
        let mut opts = PdfOptions::default();

        if let Some(ref document_id) = self.document_id {
            opts.ident = Smart::Custom(document_id.as_str());
        }

        if !self.pdf_standards.is_empty() {
            let standards: Vec<PdfStandard> =
                self.pdf_standards.iter().map(|&s| s.into()).collect();
            opts.standards = PdfStandards::new(&standards)
                .map_err(|e| Error::Term(Box::new(format!("Invalid PDF standards: {}", e))))?;
        }

        Ok(opts)
    }
}

impl PreviewOptionsNif {
    fn get_font_paths(&self) -> &Vec<String> {
        &self.font_paths
    }

    fn should_ignore_system_fonts(&self) -> bool {
        self.ignore_system_fonts
    }
}

impl FontOptionsNif {
    fn get_font_paths(&self) -> &Vec<String> {
        &self.font_paths
    }

    fn should_ignore_system_fonts(&self) -> bool {
        self.ignore_system_fonts
    }
}

impl PdfOptionsNif {
    fn get_font_paths(&self) -> &Vec<String> {
        &self.font_paths
    }

    fn should_ignore_system_fonts(&self) -> bool {
        self.ignore_system_fonts
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
}

impl SystemWorld {
    pub fn new(root: PathBuf, markup: String) -> Self {
        Self::with_font_options(root, markup, Vec::<String>::new(), false)
    }

    pub fn with_font_paths<I, P>(root: PathBuf, markup: String, font_paths: I) -> Self
    where
        I: IntoIterator<Item = P>,
        P: AsRef<Path>,
    {
        Self::with_font_options(root, markup, font_paths, false)
    }

    pub fn with_font_options<I, P>(
        root: PathBuf,
        markup: String,
        font_paths: I,
        ignore_system_fonts: bool,
    ) -> Self
    where
        I: IntoIterator<Item = P>,
        P: AsRef<Path>,
    {
        let font_paths_vec: Vec<PathBuf> = font_paths
            .into_iter()
            .map(|p| p.as_ref().to_path_buf())
            .filter(|p| p.exists() && p.is_dir())
            .collect();

        let include_system_fonts = !ignore_system_fonts;

        let fonts = if font_paths_vec.is_empty() {
            Fonts::searcher()
                .include_system_fonts(include_system_fonts)
                .search()
        } else {
            Fonts::searcher()
                .include_system_fonts(include_system_fonts)
                .search_with(font_paths_vec)
        };

        let user_agent = concat!("typst/", env!("CARGO_PKG_VERSION"));
        Self {
            root,
            main: *MARKUP_ID,
            markup,
            library: LazyHash::new(Library::builder().build()),
            book: LazyHash::new(fonts.book),
            fonts: fonts.fonts,
            slots: Mutex::new(HashMap::new()),
            package_storage: PackageStorage::new(None, None, Downloader::new(user_agent)),
            now: Now::System(OnceLock::new()),
        }
    }

    pub fn main(&self) -> FileId {
        self.main
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn dependencies(&mut self) -> impl Iterator<Item = PathBuf> + '_ {
        self.slots
            .get_mut()
            .values()
            .filter(|slot| slot.accessed())
            .filter_map(|slot| system_path(&self.root, slot.id, &self.package_storage).ok())
    }

    pub fn reset(&mut self) {
        for slot in self.slots.get_mut().values_mut() {
            slot.reset();
        }
        if let Now::System(time_lock) = &mut self.now {
            time_lock.take();
        }
    }

    pub fn lookup(&self, id: FileId) -> Source {
        self.source(id)
            .expect("file id does not point to any source file")
    }
    pub fn preview(&mut self) -> Result<(String, Vec<DiagnosticNif>), CompileErrorNif> {
        let result = typst::compile::<PagedDocument>(self);
        match result.output {
            Ok(document) => Ok((
                typst_svg::svg(&document.pages[0]),
                diagnostics_to_vec(result.warnings),
            )),
            Err(e) => Err(CompileErrorNif {
                diagnostics: diagnostics_to_vec(e),
            }),
        }
    }

    pub fn export_pdf(
        &mut self,
        pdf_opts: &PdfOptionsNif,
    ) -> Result<(String, Vec<DiagnosticNif>), CompileErrorNif> {
        let result = typst::compile::<PagedDocument>(self);
        match result.output {
            Ok(document) => {
                let opts = pdf_opts.to_pdf_options().map_err(|_| CompileErrorNif {
                    diagnostics: vec![],
                })?;
                match typst_pdf::pdf(&document, &opts) {
                    Ok(pdf_bytes) => {
                        // PDF bytes are not valid UTF-8, so we use Latin-1 encoding for binary data
                        let pdf_string = pdf_bytes.iter().map(|&b| b as char).collect::<String>();
                        Ok((pdf_string, diagnostics_to_vec(result.warnings)))
                    }
                    Err(e) => Err(CompileErrorNif {
                        diagnostics: diagnostics_to_vec(e),
                    }),
                }
            }
            Err(e) => Err(CompileErrorNif {
                diagnostics: diagnostics_to_vec(e),
            }),
        }
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
        // TODO: This is a stupid and inefficient hack. Also, does file need an implementation too?
        if id == *MARKUP_ID {
            let source = Source::new(id, self.markup.clone());
            return Ok(source);
        }
        self.slot(id, |slot| slot.source(&self.root, &self.package_storage))
    }

    fn file(&self, id: FileId) -> FileResult<Bytes> {
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

    fn accessed(&self) -> bool {
        self.source.accessed() || self.file.accessed()
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

    fn accessed(&self) -> bool {
        self.accessed
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

pub fn diagnostics_to_vec(diagnostics: EcoVec<SourceDiagnostic>) -> Vec<DiagnosticNif> {
    diagnostics.iter().map(DiagnosticNif::from).collect()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn preview(
    markup: String,
    opts: PreviewOptionsNif,
) -> Result<(String, Vec<DiagnosticNif>), CompileErrorNif> {
    let font_paths = opts.get_font_paths().clone();
    let mut world = SystemWorld::with_font_options(
        ".".into(),
        markup,
        font_paths,
        opts.should_ignore_system_fonts(),
    );
    world.preview()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn export_pdf(
    markup: String,
    opts: PdfOptionsNif,
) -> Result<(String, Vec<DiagnosticNif>), CompileErrorNif> {
    let font_paths = opts.get_font_paths().clone();
    let mut world = SystemWorld::with_font_options(
        ".".into(),
        markup,
        font_paths,
        opts.should_ignore_system_fonts(),
    );
    world.export_pdf(&opts)
}

#[rustler::nif(schedule = "DirtyIo")]
fn font_families(opts: FontOptionsNif) -> Vec<String> {
    let include_system_fonts = !opts.should_ignore_system_fonts();

    let fonts = if !opts.get_font_paths().is_empty() {
        let font_paths_vec: Vec<PathBuf> = opts
            .get_font_paths()
            .iter()
            .map(PathBuf::from)
            .filter(|p| p.exists() && p.is_dir())
            .collect();

        if font_paths_vec.is_empty() {
            Fonts::searcher()
                .include_system_fonts(include_system_fonts)
                .search()
        } else {
            Fonts::searcher()
                .include_system_fonts(include_system_fonts)
                .search_with(font_paths_vec)
        }
    } else {
        Fonts::searcher()
            .include_system_fonts(include_system_fonts)
            .search()
    };

    fonts
        .book
        .families()
        .map(|(name, _info)| name.to_string())
        .collect()
}

rustler::atoms! {
    pdf_1_7,
    pdf_a_2b,
    pdf_a_3b,
    error,
    warning
}

rustler::init!("Elixir.AshTypst.NIF");
