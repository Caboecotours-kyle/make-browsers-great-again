//! Importing from other browsers installed on this Mac.
//!
//! Detection scans the user's Application Support folder for browser data:
//! known browsers by location, plus any other Chromium- or Firefox-based
//! browser by the files they leave (so new forks are found too). Each source
//! profile is read into plain `ImportedProfile` data, which `apply` turns
//! into MBGA profiles, spaces, pinned trees, Today tabs and favorites.
//!
//! Only tabs and bookmarks are copied; history, passwords and cookies stay
//! in the other browser.

mod arc;
mod chromium;
mod firefox;
mod safari;
pub mod snss;

use crate::model::{Id, Node, State, Tab, SPACE_COLORS};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq)]
pub enum Item {
    Tab { url: String, title: String },
    Folder { name: String, children: Vec<Item>, expanded: bool },
}

impl Item {
    fn tab(url: &str, title: &str) -> Item {
        Item::Tab { url: url.to_string(), title: title.to_string() }
    }

    fn folder(name: &str, children: Vec<Item>, expanded: bool) -> Item {
        Item::Folder { name: name.to_string(), children, expanded }
    }
}

#[derive(Debug, Clone)]
pub struct ImportedSpace {
    /// Position in the browser's sidebar, across its profiles.
    pub position: usize,
    pub name: String,
    pub icon: Option<String>,
    pub color: Option<u32>,
    pub pinned: Vec<Item>,
    pub today: Vec<Item>,
}

/// One profile of another browser: its spaces (one for browsers without
/// spaces) and favorites.
#[derive(Debug, Clone)]
pub struct ImportedProfile {
    /// The profile's directory, unique within its browser.
    pub id: String,
    pub name: String,
    pub spaces: Vec<ImportedSpace>,
    pub favorites: Vec<Item>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Arc,
    Chromium,
    Firefox,
    Safari,
}

#[derive(Debug, Clone)]
pub struct Source {
    /// The browser's data directory, unique per source.
    pub id: String,
    pub name: String,
    pub kind: Kind,
    pub bundle_id: Option<String>,
    pub icon: &'static str,
    pub profiles: Vec<ImportedProfile>,
    /// Why nothing could be read, e.g. missing Full Disk Access for Safari.
    pub error: Option<String>,
}

/// Sidebar items worth importing: web pages and local files.
fn importable(url: &str) -> bool {
    url.starts_with("https://") || url.starts_with("http://") || url.starts_with("file://")
}

/// (data directory under Application Support, name, bundle ID, space icon).
const CHROMIUM_BROWSERS: &[(&str, &str, &str, &str)] = &[
    ("Google/Chrome", "Chrome", "com.google.Chrome", "🌐"),
    ("Google/Chrome Beta", "Chrome Beta", "com.google.Chrome.beta", "🌐"),
    ("Google/Chrome Dev", "Chrome Dev", "com.google.Chrome.dev", "🌐"),
    ("Google/Chrome Canary", "Chrome Canary", "com.google.Chrome.canary", "🌐"),
    ("net.imput.helium", "Helium", "net.imput.helium", "🎈"),
    ("Chromium", "Chromium", "org.chromium.Chromium", "🔵"),
    ("BraveSoftware/Brave-Browser", "Brave", "com.brave.Browser", "🦁"),
    ("Microsoft Edge", "Edge", "com.microsoft.edgemac", "🌊"),
    ("Vivaldi", "Vivaldi", "com.vivaldi.Vivaldi", "🎻"),
    ("com.operasoftware.Opera", "Opera", "com.operasoftware.Opera", "⭕"),
    ("Dia/User Data", "Dia", "company.thebrowser.dia", "💬"),
    ("Comet", "Comet", "ai.perplexity.comet", "☄️"),
    ("Thorium", "Thorium", "org.chromium.Thorium", "⚛️"),
    ("Yandex/YandexBrowser", "Yandex Browser", "ru.yandex.desktop.yandex-browser", "🔴"),
];

const FIREFOX_BROWSERS: &[(&str, &str, &str, &str)] = &[
    ("Firefox", "Firefox", "org.mozilla.firefox", "🦊"),
    ("zen", "Zen", "app.zen-browser.zen", "🧘"),
    ("librewolf", "LibreWolf", "io.gitlab.librewolf-community", "🐺"),
    ("Waterfox", "Waterfox", "net.waterfox.waterfox", "💧"),
];

const ARC_DIR: &str = "Arc";

/// Every browser with importable data under `home`, Arc first. `exclude`
/// is MBGA's own data directory, which also looks like a Chromium browser.
pub fn detect(home: &Path, exclude: &Path) -> Vec<Source> {
    let support = home.join("Library/Application Support");
    let mut sources = Vec::new();

    let arc = support.join(ARC_DIR);
    if arc.join(arc::SIDEBAR_FILE).exists() {
        let (profiles, error) = match arc::load(&arc) {
            Ok(p) => (p, None),
            Err(e) => (Vec::new(), Some(e)),
        };
        sources.push(Source {
            id: arc.to_string_lossy().into_owned(),
            name: "Arc".into(),
            kind: Kind::Arc,
            bundle_id: Some("company.thebrowser.Browser".into()),
            icon: "🌈",
            profiles,
            error,
        });
    }

    let mut chromium_dirs: Vec<(PathBuf, String, Option<String>, &'static str)> = CHROMIUM_BROWSERS
        .iter()
        .map(|(dir, name, bundle, icon)| (support.join(dir), name.to_string(), Some(bundle.to_string()), *icon))
        .collect();
    // Unknown Chromium forks: any "Local State" one or two levels down.
    for dir in subdirs(&support).into_iter().flat_map(|d| {
        let nested = subdirs(&d);
        std::iter::once(d).chain(nested)
    }) {
        let known = chromium_dirs.iter().any(|(d, ..)| *d == dir)
            || dir == arc.join("User Data")
            || dir.starts_with(exclude)
            || exclude.starts_with(&dir);
        if !known && dir.join("Local State").exists() {
            chromium_dirs.push((dir.clone(), display_name(&support, &dir), None, "🌐"));
        }
    }
    for (dir, name, bundle_id, icon) in chromium_dirs {
        let profiles = chromium::profiles(&dir);
        if profiles.is_empty() {
            continue;
        }
        let single = profiles.len() == 1;
        let profiles = profiles
            .iter()
            .map(|(id, profile)| {
                let label = if single { name.clone() } else { format!("{name} · {profile}") };
                chromium::load(&dir, id, &label, &label)
            })
            .collect();
        sources.push(Source {
            id: dir.to_string_lossy().into_owned(),
            name,
            kind: Kind::Chromium,
            bundle_id,
            icon,
            profiles,
            error: None,
        });
    }

    let mut firefox_dirs: Vec<(PathBuf, String, Option<String>, &'static str)> = FIREFOX_BROWSERS
        .iter()
        .map(|(dir, name, bundle, icon)| (support.join(dir), name.to_string(), Some(bundle.to_string()), *icon))
        .collect();
    for dir in subdirs(&support) {
        if !firefox_dirs.iter().any(|(d, ..)| *d == dir) && dir.join("profiles.ini").exists() {
            firefox_dirs.push((dir.clone(), display_name(&support, &dir), None, "🦊"));
        }
    }
    for (dir, name, bundle_id, icon) in firefox_dirs {
        let profiles = firefox::profiles(&dir);
        if profiles.is_empty() {
            continue;
        }
        let single = profiles.len() == 1;
        let mut loaded = Vec::new();
        let mut error = None;
        for (path, profile) in &profiles {
            let label = if single { name.clone() } else { format!("{name} · {profile}") };
            match firefox::load(&dir, path, &label, &label) {
                Ok(p) => loaded.push(p),
                Err(e) => error = Some(e),
            }
        }
        sources.push(Source {
            id: dir.to_string_lossy().into_owned(),
            name,
            kind: Kind::Firefox,
            bundle_id,
            icon,
            error: if loaded.is_empty() { error } else { None },
            profiles: loaded,
        });
    }

    let safari = home.join("Library/Safari/Bookmarks.plist");
    if Path::new("/Applications/Safari.app").exists() || safari.exists() {
        let (profiles, error) = match safari::load(&safari) {
            Ok(p) => (vec![p], None),
            Err(e) => (Vec::new(), Some(e)),
        };
        // A Mac whose Safari was never used has no bookmarks file at all.
        if !profiles.is_empty() || error.as_deref() == Some(safari::NEEDS_ACCESS) {
            sources.push(Source {
                id: safari.to_string_lossy().into_owned(),
                name: "Safari".into(),
                kind: Kind::Safari,
                bundle_id: Some("com.apple.Safari".into()),
                icon: "🧭",
                profiles,
                error,
            });
        }
    }

    sources.retain(|s| s.error.is_some() || s.profiles.iter().any(|p| count(p).total() > 0));
    sources
}

fn subdirs(dir: &Path) -> Vec<PathBuf> {
    let mut out: Vec<PathBuf> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.file_type().is_ok_and(|t| t.is_dir()))
        .map(|e| e.path())
        .collect();
    out.sort();
    out
}

/// "net.example.browser" -> "Browser", "Foo/Foo Browser" -> "Foo Browser".
fn display_name(support: &Path, dir: &Path) -> String {
    let rel = dir.strip_prefix(support).unwrap_or(dir);
    let last = rel.iter().rfind(|c| *c != "User Data").map(|c| c.to_string_lossy().into_owned());
    let last = last.unwrap_or_else(|| "Browser".into());
    let base = if last.matches('.').count() >= 2 { last.rsplit('.').next().unwrap_or(&last).to_string() } else { last };
    let mut chars = base.chars();
    chars.next().map(|c| c.to_uppercase().chain(chars).collect()).unwrap_or(base)
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct Counts {
    pub spaces: u32,
    pub pinned: u32,
    pub favorites: u32,
    pub today: u32,
}

impl Counts {
    pub fn total(&self) -> u32 {
        self.pinned + self.favorites + self.today
    }
}

fn tabs_in(items: &[Item]) -> u32 {
    items
        .iter()
        .map(|i| match i {
            Item::Tab { .. } => 1,
            Item::Folder { children, .. } => tabs_in(children),
        })
        .sum()
}

pub fn count(p: &ImportedProfile) -> Counts {
    Counts {
        spaces: p.spaces.len() as u32,
        pinned: p.spaces.iter().map(|s| tabs_in(&s.pinned)).sum(),
        favorites: tabs_in(&p.favorites),
        today: p.spaces.iter().map(|s| tabs_in(&s.today)).sum(),
    }
}

/// Adds the chosen profiles to `state`: an MBGA profile for each (so each
/// keeps its own cookies and logins), their spaces, pinned trees, Today
/// tabs and favorites. Every imported tab starts asleep. A state nobody has
/// used yet (one empty space) is replaced rather than added to.
pub fn apply(state: &mut State, sources: &[(&Source, &ImportedProfile)], now: u64) -> Counts {
    let pristine = state.profiles.len() == 1 && state.spaces.len() == 1 && state.tabs.is_empty();
    let old_space = state.spaces[0].id;
    let old_profile = state.profiles[0].id;
    let mut counts = Counts::default();
    let mut first_space = None;

    // Profiles first, then every space in its browser's sidebar order (Arc
    // interleaves spaces of different profiles).
    let mut spaces: Vec<(usize, usize, Id, &Source, &ImportedSpace)> = Vec::new();
    for (source, profile) in sources {
        // The unused default profile is about to go, so its name is free.
        let taken = |state: &State, name: &str| {
            state.profiles.iter().any(|p| p.name == name && !(pristine && p.id == old_profile))
        };
        let mut name = profile.name.clone();
        if taken(state, &name) {
            name = format!("{name} ({})", source.name);
        }
        let profile_id = state.create_profile(&name);
        for fav in flatten(&profile.favorites) {
            let id = new_tab(state, fav, true, now);
            state.favorites.entry(profile_id).or_default().push(id);
            counts.favorites += 1;
        }
        let rank = sources.iter().position(|(s, _)| s.id == source.id).unwrap_or(0);
        for space in &profile.spaces {
            spaces.push((rank, space.position, profile_id, source, space));
        }
    }
    spaces.sort_by_key(|&(rank, position, ..)| (rank, position));
    for (_, _, profile_id, source, space) in spaces {
        let color = space.color.unwrap_or(SPACE_COLORS[state.spaces.len() % SPACE_COLORS.len()]);
        let icon = space.icon.clone().unwrap_or_else(|| source.icon.to_string());
        let space_id = state.create_space(&space.name, &icon, color, profile_id);
        first_space.get_or_insert(space_id);
        let pinned = nodes(state, &space.pinned, now);
        counts.pinned += tabs_in(&space.pinned);
        let today: Vec<Id> = flatten(&space.today).into_iter().map(|t| new_tab(state, t, false, now)).collect();
        counts.today += today.len() as u32;
        let s = state.spaces.iter_mut().find(|s| s.id == space_id).expect("space just created");
        s.pinned = pinned;
        s.today = today;
        counts.spaces += 1;
    }

    if let Some(first) = first_space {
        if pristine {
            state.delete_space(old_space);
            state.delete_profile(old_profile);
        }
        state.set_active_space(first, now);
    }
    counts
}

fn flatten(items: &[Item]) -> Vec<&Item> {
    items
        .iter()
        .flat_map(|i| match i {
            Item::Folder { children, .. } => flatten(children),
            tab => vec![tab],
        })
        .collect()
}

fn new_tab(state: &mut State, item: &Item, pinned: bool, now: u64) -> Id {
    let Item::Tab { url, title } = item else { unreachable!("only tabs are flattened") };
    let id = state.alloc();
    state.tabs.insert(
        id,
        Tab {
            id,
            url: url.clone(),
            title: title.clone(),
            favicon: None,
            pinned_url: pinned.then(|| url.clone()),
            last_active_ms: now,
            live: false,
            audible: false,
            frozen: false,
        },
    );
    id
}

fn nodes(state: &mut State, items: &[Item], now: u64) -> Vec<Node> {
    items
        .iter()
        .map(|item| match item {
            Item::Tab { .. } => Node::Tab { id: new_tab(state, item, true, now) },
            Item::Folder { name, children, expanded } => {
                let id = state.alloc();
                Node::Folder { id, name: name.clone(), expanded: *expanded, children: nodes(state, children, now) }
            }
        })
        .collect()
}

#[cfg(test)]
mod tests;
