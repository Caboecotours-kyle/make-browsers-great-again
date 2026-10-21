//! Ad and tracker blocking with Brave's engine and EasyList-style filter
//! lists. Network requests matching a rule are cancelled; page-specific
//! hiding rules become a style sheet injected into the page.
//!
//! The engine is compiled from the downloaded lists once and cached in a
//! binary file, so later launches load in milliseconds.

use adblock::lists::{FilterSet, ParseOptions};
use adblock::request::Request;
use adblock::Engine;
use std::collections::HashSet;
use std::fs;
use std::path::Path;

/// Filter lists downloaded by the shell, as (file name, URL).
pub const LISTS: [(&str, &str); 2] = [
    ("easylist.txt", "https://easylist.to/easylist/easylist.txt"),
    ("easyprivacy.txt", "https://easylist.to/easylist/easyprivacy.txt"),
];

const CACHE_FILE: &str = "engine.dat";

/// Everything a request check needs, behind its own lock so the engine's
/// network thread never waits for the main browser state.
#[derive(Default)]
pub struct Blocker {
    engine: Option<Engine>,
    pub enabled: bool,
    /// Sites (see `model::site_of`) where blocking is off.
    pub allowed: HashSet<String>,
}

impl Blocker {
    /// A blocker without rules until `load` succeeds.
    pub fn new(enabled: bool, allowed: impl IntoIterator<Item = String>) -> Blocker {
        Blocker { engine: None, enabled, allowed: allowed.into_iter().collect() }
    }

    /// Loads the engine from the cache, or compiles it from the lists in
    /// `dir` when they are newer. Returns false if there are no lists yet.
    pub fn load(&mut self, dir: &Path) -> bool {
        let lists: Vec<_> = LISTS.iter().map(|(name, _)| dir.join(name)).filter(|p| p.exists()).collect();
        if lists.is_empty() {
            return false;
        }
        let cache = dir.join(CACHE_FILE);
        let modified = |p: &Path| fs::metadata(p).and_then(|m| m.modified()).ok();
        let cache_fresh = modified(&cache).is_some_and(|c| lists.iter().all(|l| modified(l).is_some_and(|m| m <= c)));
        if cache_fresh {
            if let Ok(bytes) = fs::read(&cache) {
                let mut engine = Engine::default();
                if engine.deserialize(&bytes).is_ok() {
                    self.engine = Some(engine);
                    return true;
                }
            }
        }
        let mut set = FilterSet::new(false);
        for list in &lists {
            if let Ok(text) = fs::read_to_string(list) {
                set.add_filter_list(text, ParseOptions::default());
            }
        }
        let engine = Engine::new_with_filter_set(set);
        let _ = fs::write(&cache, engine.serialize());
        self.engine = Some(engine);
        true
    }

    /// Frees the engine's memory.
    pub fn unload(&mut self) {
        self.engine = None;
    }

    /// Builds an engine straight from rules, for tests.
    pub fn from_rules(rules: &str) -> Blocker {
        let mut set = FilterSet::new(false);
        set.add_filter_list(rules.to_string(), ParseOptions::default());
        Blocker { engine: Some(Engine::new_with_filter_set(set)), enabled: true, allowed: HashSet::new() }
    }

    fn active_for(&self, page: &str) -> Option<&Engine> {
        if !self.enabled || self.allowed.contains(&crate::model::site_of(page)) {
            return None;
        }
        self.engine.as_ref()
    }

    /// Whether a request for `url` made by the page `page` should be
    /// cancelled. `kind` is the request type ("script", "image", ...).
    pub fn should_block(&self, url: &str, page: &str, kind: &str) -> bool {
        let Some(engine) = self.active_for(page) else { return false };
        match Request::new(url, page, kind, "GET") {
            Ok(request) => engine.check_network_request(&request).should_block(),
            Err(_) => false,
        }
    }

    /// CSS hiding the page's ad slots, or an empty string.
    pub fn hiding_css(&self, page: &str) -> String {
        let Some(engine) = self.active_for(page) else { return String::new() };
        let resources = engine.url_cosmetic_resources(page);
        if resources.hide_selectors.is_empty() {
            return String::new();
        }
        let mut selectors: Vec<&str> = resources.hide_selectors.iter().map(String::as_str).collect();
        selectors.sort_unstable();
        // One rule per selector: a single invalid selector would void a
        // combined rule.
        selectors.iter().map(|s| format!("{s}{{display:none!important}}")).collect::<Vec<_>>().join("\n")
    }
}
