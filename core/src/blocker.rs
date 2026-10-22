//! Ad and tracker blocking with Brave's engine and EasyList-style filter
//! lists. Network requests matching a rule are cancelled. Each page gets a
//! script at load start that adds its site-specific hiding rules, runs the
//! scriptlets the lists ask for (`##+js(...)`), and reports the class and id
//! names it uses so generic hiding rules (`##.ad-banner`) can follow.
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
pub const LISTS: [(&str, &str); 4] = [
    ("easylist.txt", "https://easylist.to/easylist/easylist.txt"),
    ("easyprivacy.txt", "https://easylist.to/easylist/easyprivacy.txt"),
    ("ublock-filters.txt", "https://ublockorigin.github.io/uAssets/filters/filters.txt"),
    ("ublock-privacy.txt", "https://ublockorigin.github.io/uAssets/filters/privacy.txt"),
];

/// The scriptlets `##+js(...)` rules call, from the last uBlock Origin
/// release in the format the engine reads. Pinned to the tag, so it never
/// changes underneath us.
pub const SCRIPTLETS: (&str, &str) =
    ("scriptlets.js", "https://raw.githubusercontent.com/gorhill/uBlock/1.48.8/assets/resources/scriptlets.js");

/// Rules the person writes themselves, in the same syntax.
pub const USER_RULES: &str = "my-filters.txt";

const CACHE_FILE: &str = "engine.dat";

/// Runs first on every page: a style element for hiding rules
/// (`window.__mbgaAddCSS`), the page's own rules and scriptlets, and the
/// collector that reports new class and id names in batches.
const PAGE_SCRIPT: &str = r"(function(){if(window.__mbgaAddCSS)return;var style=null,queue=[];
function add(c){if(!c)return;var r=document.documentElement;if(!r){queue.push(c);return;}
if(!style||!style.isConnected){style=document.createElement('style');r.appendChild(style);}
style.textContent+=c+'\n';}
window.__mbgaAddCSS=add;
if(!document.documentElement){new MutationObserver(function(_,o){if(document.documentElement){o.disconnect();queue.splice(0).forEach(add);}}).observe(document,{childList:true});}
add(__CSS__);
try{__SCRIPTLETS__}catch(e){}
__COLLECT__})();";

/// Reports class and id names not seen before, at most every 300 ms and
/// 500 of each per message, for generic hiding rules.
const COLLECTOR: &str = r"var seenC=new Set(),seenI=new Set(),pending=[],timer=0;
function scan(el,c,i){if(el.classList)for(var k of el.classList)if(!seenC.has(k)){seenC.add(k);c.push(k);}
if(el.id&&!seenI.has(el.id)){seenI.add(el.id);i.push(el.id);}}
function flush(){timer=0;var c=[],i=[];for(var n of pending.splice(0)){if(n.nodeType!==1)continue;scan(n,c,i);
var all=n.querySelectorAll('[class],[id]');for(var j=0;j<all.length;j++)scan(all[j],c,i);}
for(var s=0;s<c.length||s<i.length;s+=500)console.debug('__mbga_cosmetic:'+JSON.stringify({c:c.slice(s,s+500),i:i.slice(s,s+500)}));}
function later(n){pending.push(n);if(!timer)timer=setTimeout(flush,300);}
function start(){later(document.documentElement);new MutationObserver(function(ms){for(var m of ms){if(m.type==='attributes')later(m.target);else m.addedNodes.forEach(later);}}).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['class','id']});}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start);else start();";

/// What the page script's collector sends.
#[derive(serde::Deserialize)]
struct Names {
    #[serde(default)]
    c: Vec<String>,
    #[serde(default)]
    i: Vec<String>,
}

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
        self.load_from(dir, true)
    }

    /// Loads the engine only if a compiled cache is up to date: tens of
    /// milliseconds, so it can happen before the first page loads.
    pub fn load_cached(&mut self, dir: &Path) -> bool {
        self.load_from(dir, false)
    }

    fn load_from(&mut self, dir: &Path, compile: bool) -> bool {
        let lists: Vec<_> = LISTS
            .iter()
            .map(|(name, _)| *name)
            .chain([USER_RULES])
            .map(|name| dir.join(name))
            .filter(|p| p.exists())
            .collect();
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
                    use_scriptlets(&mut engine, dir);
                    self.engine = Some(engine);
                    return true;
                }
            }
        }
        if !compile {
            return false;
        }
        let mut set = FilterSet::new(false);
        for list in &lists {
            if let Ok(text) = fs::read_to_string(list) {
                set.add_filter_list(text, ParseOptions::default());
            }
        }
        let mut engine = Engine::new_with_filter_set(set);
        let _ = fs::write(&cache, engine.serialize());
        use_scriptlets(&mut engine, dir);
        self.engine = Some(engine);
        true
    }

    /// Frees the engine's memory.
    /// Drops the engine, handing it back so the caller can free it outside
    /// any lock.
    pub fn unload(&mut self) -> Option<Engine> {
        self.engine.take()
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

    /// The script to run as `page` starts loading, or "" when blocking is
    /// off for it.
    /// Whether `page` gets scriptlets (which must run before the page's own
    /// scripts). Hiding rules and the collector can come a moment later.
    pub fn needs_early_script(&self, page: &str) -> bool {
        self.active_for(page).is_some_and(|e| !e.url_cosmetic_resources(page).injected_script.trim().is_empty())
    }

    pub fn page_script(&self, page: &str) -> String {
        let Some(engine) = self.active_for(page) else { return String::new() };
        let resources = engine.url_cosmetic_resources(page);
        let css = hiding_css(resources.hide_selectors.iter());
        PAGE_SCRIPT
            .replace("__CSS__", &serde_json::to_string(&css).unwrap_or_else(|_| "\"\"".into()))
            .replace("__SCRIPTLETS__", &resources.injected_script)
            .replace("__COLLECT__", if resources.generichide { "" } else { COLLECTOR })
    }

    /// The answer to a collector report (`{"c": [classes], "i": [ids]}`):
    /// a script adding the generic hiding rules those names match, or "".
    pub fn cosmetic_reply(&self, page: &str, report: &str) -> String {
        let Some(engine) = self.active_for(page) else { return String::new() };
        let Ok(names) = serde_json::from_str::<Names>(report) else { return String::new() };
        let resources = engine.url_cosmetic_resources(page);
        if resources.generichide {
            return String::new();
        }
        let selectors = engine.hidden_class_id_selectors(&names.c, &names.i, &resources.exceptions);
        if selectors.is_empty() {
            return String::new();
        }
        let css = hiding_css(selectors.iter());
        format!("window.__mbgaAddCSS&&window.__mbgaAddCSS({});", serde_json::to_string(&css).unwrap_or_default())
    }
}

/// One rule per selector: a single invalid selector would void a combined
/// rule.
fn hiding_css<'a>(selectors: impl Iterator<Item = &'a String>) -> String {
    let mut selectors: Vec<&str> = selectors.map(String::as_str).collect();
    selectors.sort_unstable();
    selectors.iter().map(|s| format!("{s}{{display:none!important}}")).collect::<Vec<_>>().join("\n")
}

/// Gives the engine uBlock Origin's scriptlets, if they were downloaded.
fn use_scriptlets(engine: &mut Engine, dir: &Path) {
    let path = dir.join(SCRIPTLETS.0);
    if !path.exists() {
        return;
    }
    // The reader panics on files it doesn't understand; a broken download
    // must not take the browser down.
    #[allow(deprecated)]
    let resources =
        std::panic::catch_unwind(|| adblock::resources::resource_assembler::assemble_scriptlet_resources(&path));
    if let Ok(resources) = resources {
        engine.use_resources(resources);
    }
}
