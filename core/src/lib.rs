//! MBGA browser core. Owns all browser state and the tab sleep policy; the
//! native shell only renders snapshots and forwards engine events.

uniffi::setup_scaffolding!();

pub mod history;
pub mod import;
pub mod model;

use model::{Container, Id, Node, Pressure, State, Tab};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{SystemTime, UNIX_EPOCH};

// ------------------------------------------------------------------ records

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct TabInfo {
    pub id: u64,
    pub url: String,
    pub title: String,
    pub favicon_path: Option<String>,
    pub pinned_url: Option<String>,
    pub live: bool,
    pub audible: bool,
    pub frozen: bool,
    /// The tab's site is exempt from sleeping and freezing.
    pub keep_awake: bool,
}

/// One visible row of a space's pinned tree. Folders and tabs are flattened
/// depth-first; children of collapsed folders are omitted.
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct PinnedRow {
    pub id: u64,
    pub depth: u32,
    pub parent_id: Option<u64>,
    /// Position within the parent folder (or the pinned root).
    pub index: u32,
    pub tab: Option<TabInfo>,
    pub folder_name: Option<String>,
    pub expanded: bool,
    pub child_count: u32,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SpaceInfo {
    pub id: u64,
    pub name: String,
    pub icon: String,
    pub color: u32,
    pub profile_id: u64,
    pub favorites: Vec<TabInfo>,
    pub pinned: Vec<PinnedRow>,
    pub today: Vec<TabInfo>,
    pub active_tab: Option<u64>,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ProfileInfo {
    pub id: u64,
    pub name: String,
    pub space_count: u32,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct Snapshot {
    pub revision: u64,
    pub active_space: u64,
    pub spaces: Vec<SpaceInfo>,
    pub profiles: Vec<ProfileInfo>,
    pub sleep_after_secs: u64,
    pub max_live_tabs: u32,
    pub strict_site_isolation: bool,
    /// Something closed this session can be reopened.
    pub can_reopen: bool,
    /// Today tabs untouched this long are archived; 0 is off.
    pub archive_after_hours: u32,
    pub cleanup_answered: bool,
}

/// A page from history for the command bar.
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct HistoryItem {
    pub url: String,
    pub title: String,
    /// The query is the start of the page's site ("git" for github.com).
    pub site_prefix: bool,
}

/// Tabs brought back by undoing a close, and the space they are in.
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ReopenOutcome {
    pub space_id: u64,
    pub tabs: Vec<u64>,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CloseOutcome {
    /// False for pinned tabs and favorites, which stay in the sidebar asleep.
    pub removed: bool,
    /// Tab to show next, if the closed tab was on screen.
    pub next_tab: Option<u64>,
}

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum MemoryPressure {
    Normal,
    Warning,
    Critical,
}

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum DropTarget {
    Favorites { profile_id: u64 },
    Pinned { space_id: u64, folder_id: Option<u64> },
    Today { space_id: u64 },
}

impl From<DropTarget> for Container {
    fn from(t: DropTarget) -> Container {
        match t {
            DropTarget::Favorites { profile_id } => Container::Favorites { profile_id },
            DropTarget::Pinned {
                space_id,
                folder_id,
            } => Container::Pinned {
                space_id,
                folder_id,
            },
            DropTarget::Today { space_id } => Container::Today { space_id },
        }
    }
}

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum BrowserKind {
    Arc,
    Chromium,
    Firefox,
    Safari,
}

/// A profile of another browser and what importing it would bring.
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ImportProfileInfo {
    pub id: String,
    pub name: String,
    pub spaces: u32,
    pub pinned: u32,
    pub favorites: u32,
    pub today: u32,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ImportSourceInfo {
    pub id: String,
    pub name: String,
    pub kind: BrowserKind,
    /// For showing the browser's app icon.
    pub bundle_id: Option<String>,
    pub profiles: Vec<ImportProfileInfo>,
    /// Why the browser's data could not be read.
    pub error: Option<String>,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ImportChoice {
    pub source_id: String,
    pub profile_ids: Vec<String>,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ImportSummary {
    pub spaces: u32,
    pub pinned: u32,
    pub favorites: u32,
    pub today: u32,
}

fn import_counts(c: import::Counts) -> ImportSummary {
    ImportSummary {
        spaces: c.spaces,
        pinned: c.pinned,
        favorites: c.favorites,
        today: c.today,
    }
}

// --------------------------------------------------------------------- core

struct Inner {
    state: State,
    dirty: bool,
    history: history::History,
    history_dirty: bool,
    revision: u64,
    data_dir: PathBuf,
    /// Browsers found by the last `detect_browsers`, ready to import.
    detected: Vec<import::Source>,
}

#[derive(uniffi::Object)]
pub struct BrowserCore {
    inner: Mutex<Inner>,
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

const STATE_FILE: &str = "state.json";
const HISTORY_FILE: &str = "history.json";

fn load_history(dir: &Path) -> history::History {
    fs::read(dir.join(HISTORY_FILE))
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_default()
}

/// Writes `value` as JSON next to its final path, then renames it into place.
fn write_atomic(dir: &Path, name: &str, value: &impl serde::Serialize) -> bool {
    let Ok(json) = serde_json::to_vec(value) else {
        return false;
    };
    let tmp = dir.join(format!("{name}.tmp"));
    fs::write(&tmp, json).is_ok() && fs::rename(&tmp, dir.join(name)).is_ok()
}

fn load_state(dir: &Path) -> State {
    let path = dir.join(STATE_FILE);
    let Ok(bytes) = fs::read(&path) else {
        return State::new_default();
    };
    match serde_json::from_slice::<State>(&bytes) {
        Ok(s) if !s.spaces.is_empty() && !s.profiles.is_empty() => s,
        _ => {
            // Keep the unreadable file for inspection instead of losing it.
            let backup = dir.join(format!("{STATE_FILE}.corrupt-{}", now_ms()));
            let _ = fs::rename(&path, backup);
            State::new_default()
        }
    }
}

/// The engine only accepts profile directories that are direct children of
/// its root directory.
fn profile_dir_in(data_dir: &Path, profile_id: Id) -> PathBuf {
    data_dir.join("engine").join(format!("Profile {profile_id}"))
}

fn tab_info(s: &State, t: &Tab) -> TabInfo {
    TabInfo {
        id: t.id,
        url: t.url.clone(),
        title: t.title.clone(),
        favicon_path: t.favicon.clone(),
        pinned_url: t.pinned_url.clone(),
        live: t.live,
        audible: t.audible,
        frozen: t.frozen,
        keep_awake: s.keeps_awake(&t.url),
    }
}

fn flatten(state: &State, nodes: &[Node], depth: u32, parent: Option<Id>, out: &mut Vec<PinnedRow>) {
    for (index, node) in nodes.iter().enumerate() {
        match node {
            Node::Tab { id } => {
                if let Some(t) = state.tabs.get(id) {
                    out.push(PinnedRow {
                        id: *id,
                        depth,
                        parent_id: parent,
                        index: index as u32,
                        tab: Some(tab_info(state, t)),
                        folder_name: None,
                        expanded: false,
                        child_count: 0,
                    });
                }
            }
            Node::Folder {
                id,
                name,
                expanded,
                children,
            } => {
                out.push(PinnedRow {
                    id: *id,
                    depth,
                    parent_id: parent,
                    index: index as u32,
                    tab: None,
                    folder_name: Some(name.clone()),
                    expanded: *expanded,
                    child_count: children.len() as u32,
                });
                if *expanded {
                    flatten(state, children, depth + 1, Some(*id), out);
                }
            }
        }
    }
}

fn fnv1a(s: &str) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in s.bytes() {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

fn host_of(url: &str) -> &str {
    let rest = url.split_once("://").map_or(url, |(_, r)| r);
    rest.split(['/', '?', '#']).next().unwrap_or(rest)
}

impl BrowserCore {
    fn lock(&self) -> MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Runs a mutation and marks the state changed.
    fn mutate<R>(&self, f: impl FnOnce(&mut State, u64) -> R) -> R {
        let mut inner = self.lock();
        let r = f(&mut inner.state, now_ms());
        inner.dirty = true;
        inner.revision += 1;
        r
    }
}

#[uniffi::export]
impl BrowserCore {
    /// Loads state from `data_dir` (created if missing) or starts fresh.
    #[uniffi::constructor]
    pub fn new(data_dir: String) -> Arc<Self> {
        let data_dir = PathBuf::from(data_dir);
        let _ = fs::create_dir_all(&data_dir);
        // The engine rejects profile directories reached through a symlink
        // (e.g. /tmp -> /private/tmp) and silently falls back to in-memory
        // storage, so always hand it the resolved path.
        let data_dir = fs::canonicalize(&data_dir).unwrap_or(data_dir);
        let mut state = load_state(&data_dir);
        let history = load_history(&data_dir);
        // The engine is not running yet, so deleted profiles' storage is free.
        for id in std::mem::take(&mut state.doomed_profiles) {
            let _ = fs::remove_dir_all(profile_dir_in(&data_dir, id));
        }
        Arc::new(BrowserCore {
            inner: Mutex::new(Inner {
                state,
                dirty: true,
                history,
                history_dirty: false,
                revision: 1,
                data_dir,
                detected: Vec::new(),
            }),
        })
    }

    pub fn revision(&self) -> u64 {
        self.lock().revision
    }

    pub fn snapshot(&self) -> Snapshot {
        let inner = self.lock();
        let s = &inner.state;
        let spaces = s
            .spaces
            .iter()
            .map(|space| {
                let mut pinned = Vec::new();
                flatten(s, &space.pinned, 0, None, &mut pinned);
                SpaceInfo {
                    id: space.id,
                    name: space.name.clone(),
                    icon: space.icon.clone(),
                    color: space.color,
                    profile_id: space.profile_id,
                    favorites: s
                        .favorites
                        .get(&space.profile_id)
                        .into_iter()
                        .flatten()
                        .filter_map(|id| s.tabs.get(id).map(|t| tab_info(s, t)))
                        .collect(),
                    pinned,
                    today: space
                        .today
                        .iter()
                        .filter_map(|id| s.tabs.get(id).map(|t| tab_info(s, t)))
                        .collect(),
                    active_tab: space.active_tab,
                }
            })
            .collect();
        let profiles = s
            .profiles
            .iter()
            .map(|p| ProfileInfo {
                id: p.id,
                name: p.name.clone(),
                space_count: s.spaces.iter().filter(|sp| sp.profile_id == p.id).count() as u32,
            })
            .collect();
        Snapshot {
            revision: inner.revision,
            active_space: s.active_space,
            spaces,
            profiles,
            sleep_after_secs: s.policy.sleep_after_secs,
            max_live_tabs: s.policy.max_live_tabs,
            strict_site_isolation: s.policy.strict_site_isolation,
            can_reopen: !s.closed.is_empty(),
            archive_after_hours: s.policy.archive_after_hours,
            cleanup_answered: s.cleanup_answered,
        }
    }

    pub fn tab(&self, id: u64) -> Option<TabInfo> {
        let inner = self.lock();
        inner.state.tabs.get(&id).map(|t| tab_info(&inner.state, t))
    }

    pub fn visible_tab(&self) -> Option<u64> {
        self.lock().state.visible_tab()
    }

    // ---------------------------------------------------------- engine paths

    /// Root directory for engine data; every profile directory lives inside.
    pub fn engine_root_dir(&self) -> String {
        self.lock().data_dir.join("engine").to_string_lossy().into_owned()
    }

    pub fn profile_dir(&self, profile_id: u64) -> String {
        profile_dir_in(&self.lock().data_dir, profile_id)
            .to_string_lossy()
            .into_owned()
    }

    pub fn profile_of_tab(&self, tab_id: u64) -> Option<u64> {
        self.lock().state.profile_of_tab(tab_id)
    }

    // -------------------------------------------------------------- profiles

    pub fn create_profile(&self, name: String) -> u64 {
        self.mutate(|s, _| s.create_profile(&name))
    }

    pub fn rename_profile(&self, id: u64, name: String) {
        self.mutate(|s, _| s.rename_profile(id, &name))
    }

    /// Returns the closed favorites, or None if it is the last profile or a
    /// space still uses it.
    pub fn delete_profile(&self, id: u64) -> Option<Vec<u64>> {
        self.mutate(|s, _| s.delete_profile(id))
    }

    // ---------------------------------------------------------------- spaces

    pub fn create_space(&self, name: String, icon: String, color: u32, profile_id: u64) -> u64 {
        self.mutate(|s, _| s.create_space(&name, &icon, color, profile_id))
    }

    pub fn update_space(&self, id: u64, name: String, icon: String, color: u32) {
        self.mutate(|s, _| s.update_space(id, &name, &icon, color))
    }

    /// Returns the live tabs that must be reloaded under the new profile.
    pub fn set_space_profile(&self, id: u64, profile_id: u64) -> Vec<u64> {
        self.mutate(|s, _| s.set_space_profile(id, profile_id))
    }

    /// Returns the closed tabs, or None if this is the last space.
    pub fn delete_space(&self, id: u64) -> Option<Vec<u64>> {
        self.mutate(|s, _| s.delete_space(id))
    }

    pub fn move_space(&self, id: u64, index: u32) {
        self.mutate(|s, _| s.move_space(id, index as usize))
    }

    pub fn set_active_space(&self, id: u64) {
        self.mutate(|s, now| s.set_active_space(id, now))
    }

    // ------------------------------------------------------------------ tabs

    pub fn open_tab(&self, space_id: u64, url: String, activate: bool) -> Option<u64> {
        let id = self.mutate(|s, now| s.open_tab(space_id, &url, activate, now))?;
        // The engine reports the first page's address unchanged, so the
        // visit is counted here.
        let mut inner = self.lock();
        inner.history.record(&url, now_ms());
        inner.history_dirty = true;
        Some(id)
    }

    pub fn activate_tab(&self, space_id: u64, tab_id: u64) {
        self.mutate(|s, now| s.activate_tab(space_id, tab_id, now))
    }

    pub fn update_tab(&self, id: u64, url: Option<String>, title: Option<String>) {
        let mut inner = self.lock();
        let Some(t) = inner.state.tabs.get(&id) else {
            return;
        };
        // Engines repeat the same title/URL often; skip no-op updates.
        let changed = url.as_ref().is_some_and(|u| *u != t.url)
            || title.as_ref().is_some_and(|x| *x != t.title);
        if changed {
            let url_changed = url.as_ref().is_some_and(|u| *u != t.url);
            inner.state.update_tab(id, url.as_deref(), title.as_deref());
            inner.dirty = true;
            inner.revision += 1;
            // Every navigation the engine reports is a visit; the title
            // follows a moment later and belongs to the tab's current page.
            let page = inner.state.tabs[&id].url.clone();
            if url_changed {
                inner.history.record(&page, now_ms());
            }
            if let Some(title) = title.filter(|t| !t.is_empty()) {
                inner.history.set_title(&page, &title);
            }
            inner.history_dirty = true;
        }
    }

    /// Pages from history matching `query`, best first.
    pub fn suggest_history(&self, query: String, limit: u32) -> Vec<HistoryItem> {
        self.lock()
            .history
            .suggest(&query, limit as usize, now_ms())
            .into_iter()
            .map(|m| HistoryItem { url: m.url, title: m.title, site_prefix: m.site_prefix })
            .collect()
    }

    pub fn clear_history(&self) {
        let mut inner = self.lock();
        inner.history.clear();
        inner.history_dirty = true;
    }

    pub fn close_tab(&self, id: u64) -> CloseOutcome {
        let (removed, next_tab) = self.mutate(|s, now| s.close_tab(id, now));
        CloseOutcome { removed, next_tab }
    }

    pub fn clear_today(&self, space_id: u64) -> Vec<u64> {
        self.mutate(|s, _| s.clear_today(space_id))
    }

    /// Undoes the most recent close, clear, tidy-up or folder deletion.
    pub fn undo_close(&self) -> Option<ReopenOutcome> {
        self.mutate(|s, _| s.reopen_last())
            .map(|(space_id, tabs)| ReopenOutcome { space_id, tabs })
    }

    /// Reopens one closed tab at the top of Today. Returns its space.
    pub fn reopen_tab(&self, id: u64) -> Option<u64> {
        self.mutate(|s, _| s.reopen_tab(id))
    }

    /// Tabs closed this session, most recent first.
    pub fn closed_tabs(&self, limit: u32) -> Vec<TabInfo> {
        let inner = self.lock();
        let s = &inner.state;
        s.closed_tabs().take(limit as usize).map(|t| tab_info(s, t)).collect()
    }

    // --------------------------------------------------------------- tidying

    /// How many Today tabs of a space nobody has looked at for `hours`.
    pub fn idle_today_count(&self, space_id: u64, hours: u32) -> u32 {
        self.lock().state.idle_today(space_id, hours, now_ms()).len() as u32
    }

    /// Archives a space's Today tabs untouched for `hours`, as one undoable
    /// step. Returns them; the shell must destroy their web views.
    pub fn archive_idle(&self, space_id: u64, hours: u32) -> Vec<u64> {
        self.mutate(|s, now| s.archive_idle(space_id, hours, now))
    }

    /// Applies the archive policy. Cheap when there is nothing to archive.
    pub fn archive_by_policy(&self) -> Vec<u64> {
        let mut inner = self.lock();
        let archived = inner.state.archive_by_policy(now_ms());
        if !archived.is_empty() {
            inner.dirty = true;
            inner.revision += 1;
        }
        archived
    }

    pub fn set_archive_after_hours(&self, hours: u32) {
        self.mutate(|s, _| s.policy.archive_after_hours = hours)
    }

    /// Remembers that the person answered the offer to tidy up.
    pub fn answer_cleanup(&self) {
        self.mutate(|s, _| s.cleanup_answered = true)
    }

    /// Stores a favicon (PNG) for the tab's host and attaches it to the tab.
    pub fn set_favicon(&self, tab_id: u64, png: Vec<u8>) {
        let mut inner = self.lock();
        let Some(tab) = inner.state.tabs.get(&tab_id) else {
            return;
        };
        let dir = inner.data_dir.join("favicons");
        let path = dir.join(format!("{:016x}.png", fnv1a(host_of(&tab.url))));
        let unchanged = fs::metadata(&path).is_ok_and(|m| m.len() == png.len() as u64);
        if !unchanged {
            let _ = fs::create_dir_all(&dir);
            if fs::write(&path, &png).is_err() {
                return;
            }
        }
        let path = path.to_string_lossy().into_owned();
        if tab.favicon.as_deref() != Some(path.as_str()) || !unchanged {
            inner.state.set_favicon_path(tab_id, &path);
            inner.dirty = true;
            inner.revision += 1;
        }
    }

    // --------------------------------------------------------------- folders

    pub fn create_folder(&self, space_id: u64, name: String, parent: Option<u64>) -> Option<u64> {
        self.mutate(|s, _| s.create_folder(space_id, &name, parent))
    }

    pub fn rename_folder(&self, id: u64, name: String) {
        self.mutate(|s, _| s.rename_folder(id, &name))
    }

    pub fn set_folder_expanded(&self, id: u64, expanded: bool) {
        self.mutate(|s, _| s.set_folder_expanded(id, expanded))
    }

    pub fn delete_folder(&self, id: u64) -> Vec<u64> {
        self.mutate(|s, _| s.delete_folder(id))
    }

    // ----------------------------------------------------------- drag & drop

    /// Moves a tab or folder; `index` is in pre-removal coordinates.
    /// Returns tabs that must be reloaded because their profile changed, or
    /// None if the move is not allowed.
    pub fn move_item(&self, id: u64, target: DropTarget, index: u32) -> Option<Vec<u64>> {
        self.mutate(|s, _| s.move_item(id, target.into(), index as usize))
    }

    pub fn pin_tab(&self, id: u64) -> Option<Vec<u64>> {
        let space = self.space_of(id)?;
        self.move_item(id, DropTarget::Pinned { space_id: space, folder_id: None }, u32::MAX)
    }

    pub fn unpin_tab(&self, id: u64) -> Option<Vec<u64>> {
        let space = self.space_of(id)?;
        self.move_item(id, DropTarget::Today { space_id: space }, 0)
    }

    pub fn add_favorite(&self, id: u64) -> Option<Vec<u64>> {
        let profile_id = self.profile_of_tab(id)?;
        self.move_item(id, DropTarget::Favorites { profile_id }, u32::MAX)
    }

    // ------------------------------------------------------------- lifecycle

    pub fn set_live(&self, id: u64, live: bool) {
        self.mutate(|s, _| s.set_live(id, live))
    }

    pub fn set_audible(&self, id: u64, audible: bool) {
        self.mutate(|s, _| s.set_audible(id, audible))
    }

    /// Exempts the site of `url` from sleeping and freezing, or stops doing so.
    pub fn set_keep_awake(&self, url: String, keep: bool) {
        self.mutate(|s, _| s.set_keep_awake(&url, keep))
    }

    pub fn set_policy(&self, sleep_after_secs: u64, max_live_tabs: u32) {
        self.mutate(|s, _| {
            s.policy.sleep_after_secs = sleep_after_secs.max(30);
            s.policy.max_live_tabs = max_live_tabs.max(1);
        })
    }

    /// Chooses tabs to put to sleep, marks them asleep and returns them. The
    /// shell must destroy their web views.
    pub fn collect_sleepers(&self, pressure: MemoryPressure) -> Vec<u64> {
        let pressure = match pressure {
            MemoryPressure::Normal => Pressure::Normal,
            MemoryPressure::Warning => Pressure::Warning,
            MemoryPressure::Critical => Pressure::Critical,
        };
        let mut inner = self.lock();
        let sleepers = inner.state.collect_sleepers(now_ms(), pressure);
        if !sleepers.is_empty() {
            inner.revision += 1;
        }
        sleepers
    }

    /// Freezes idle hidden Today tabs (see `State::collect_freezers`).
    /// The shell must freeze their web views.
    pub fn collect_freezers(&self) -> Vec<u64> {
        let mut inner = self.lock();
        let frozen = inner.state.collect_freezers(now_ms());
        if !frozen.is_empty() {
            inner.revision += 1;
        }
        frozen
    }

    /// Returns true if the tab was frozen; the shell must resume its web view.
    pub fn thaw(&self, id: u64) -> bool {
        let mut inner = self.lock();
        let thawed = inner.state.thaw(id);
        if thawed {
            inner.revision += 1;
        }
        thawed
    }

    // ------------------------------------------------------- process model

    pub fn set_strict_site_isolation(&self, strict: bool) {
        self.mutate(|s, _| s.policy.strict_site_isolation = strict)
    }

    /// Origins that keep a dedicated renderer when strict isolation is off.
    pub fn isolated_origins(&self) -> Vec<String> {
        model::ALWAYS_ISOLATED_ORIGINS.iter().map(|o| o.to_string()).collect()
    }

    // ---------------------------------------------------------------- misc

    pub fn resolve_input(&self, text: String) -> String {
        let inner = self.lock();
        model::resolve_input(&text, &inner.state.search_template)
    }

    /// A web search for `text`, even if it looks like an address.
    pub fn search_url(&self, text: String) -> String {
        let inner = self.lock();
        model::search_url(&text, &inner.state.search_template)
    }

    /// True until the first-launch onboarding has been completed or skipped.
    pub fn needs_onboarding(&self) -> bool {
        !self.lock().state.onboarded
    }

    pub fn finish_onboarding(&self) {
        self.mutate(|s, _| s.onboarded = true);
    }

    /// Finds other browsers' tabs and bookmarks under `home`. Reads every
    /// profile it finds, so call it off the main thread.
    pub fn detect_browsers(&self, home: String) -> Vec<ImportSourceInfo> {
        let exclude = self.lock().data_dir.clone();
        let sources = import::detect(Path::new(&home), &exclude);
        let infos = sources
            .iter()
            .map(|s| ImportSourceInfo {
                id: s.id.clone(),
                name: s.name.clone(),
                kind: match s.kind {
                    import::Kind::Arc => BrowserKind::Arc,
                    import::Kind::Chromium => BrowserKind::Chromium,
                    import::Kind::Firefox => BrowserKind::Firefox,
                    import::Kind::Safari => BrowserKind::Safari,
                },
                bundle_id: s.bundle_id.clone(),
                profiles: s
                    .profiles
                    .iter()
                    .map(|p| {
                        let c = import::count(p);
                        ImportProfileInfo {
                            id: p.id.clone(),
                            name: p.name.clone(),
                            spaces: c.spaces,
                            pinned: c.pinned,
                            favorites: c.favorites,
                            today: c.today,
                        }
                    })
                    .collect(),
                error: s.error.clone(),
            })
            .collect();
        self.lock().detected = sources;
        infos
    }

    /// Imports the chosen profiles of browsers found by `detect_browsers`.
    pub fn import_browsers(&self, choices: Vec<ImportChoice>) -> ImportSummary {
        let detected = self.lock().detected.clone();
        let chosen: Vec<(&import::Source, &import::ImportedProfile)> = detected
            .iter()
            .flat_map(|s| {
                let choice = choices.iter().find(|c| c.source_id == s.id);
                s.profiles
                    .iter()
                    .filter(move |p| choice.is_some_and(|c| c.profile_ids.contains(&p.id)))
                    .map(move |p| (s, p))
            })
            .collect();
        if chosen.is_empty() {
            return import_counts(import::Counts::default());
        }
        import_counts(self.mutate(|state, now| import::apply(state, &chosen, now)))
    }

    /// Writes state and history to disk if they changed. Atomic: write +
    /// rename.
    pub fn persist(&self) -> bool {
        let mut inner = self.lock();
        let mut ok = true;
        if inner.history_dirty {
            if write_atomic(&inner.data_dir, HISTORY_FILE, &inner.history) {
                inner.history_dirty = false;
            } else {
                ok = false;
            }
        }
        if inner.dirty {
            if write_atomic(&inner.data_dir, STATE_FILE, &inner.state) {
                inner.dirty = false;
            } else {
                ok = false;
            }
        }
        ok
    }
}

impl BrowserCore {
    fn space_of(&self, tab_id: u64) -> Option<u64> {
        let inner = self.lock();
        match inner.state.locate(tab_id)? {
            Container::Pinned { space_id, .. } | Container::Today { space_id } => Some(space_id),
            Container::Favorites { .. } => Some(inner.state.active_space),
        }
    }
}

#[cfg(test)]
mod tests;
