//! Pages visited, for command bar suggestions. Ranked by frecency: how often
//! and how recently a page was visited. Kept in its own file so the state
//! file stays small, and capped so it never grows without bound.

use serde::{Deserialize, Serialize};

/// Most pages remembered; the lowest-ranked are forgotten first.
const MAX_ENTRIES: usize = 2000;
const DAY_MS: f64 = 86_400_000.0;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Visit {
    pub url: String,
    pub title: String,
    pub count: u32,
    pub last_ms: u64,
}

#[derive(Serialize, Deserialize, Default, Debug)]
pub struct History {
    pub visits: Vec<Visit>,
}

/// A suggestion: the page, and whether the query is the start of its site
/// so the bar can offer it as the top "Go to" result.
#[derive(Clone, Debug, PartialEq)]
pub struct Match {
    pub url: String,
    pub title: String,
    pub site_prefix: bool,
}

impl History {
    /// Records a visit to `url`. Only web pages are remembered.
    pub fn record(&mut self, url: &str, now: u64) {
        if !(url.starts_with("https://") || url.starts_with("http://")) {
            return;
        }
        if let Some(v) = self.visits.iter_mut().find(|v| v.url == url) {
            v.count += 1;
            v.last_ms = now;
            return;
        }
        self.visits.push(Visit { url: url.to_string(), title: String::new(), count: 1, last_ms: now });
        if self.visits.len() > MAX_ENTRIES {
            let worst = (0..self.visits.len())
                .min_by(|&a, &b| score(&self.visits[a], now).total_cmp(&score(&self.visits[b], now)))
                .unwrap();
            self.visits.swap_remove(worst);
        }
    }

    pub fn clear(&mut self) {
        self.visits.clear();
    }

    pub fn set_title(&mut self, url: &str, title: &str) {
        if let Some(v) = self.visits.iter_mut().find(|v| v.url == url) {
            v.title = title.to_string();
        }
    }

    /// Pages whose address or title contains every word of `query`, best
    /// first. Pages whose site starts with the query rank highest.
    pub fn suggest(&self, query: &str, limit: usize, now: u64) -> Vec<Match> {
        let query = query.trim().to_lowercase();
        let words: Vec<&str> = query.split_whitespace().collect();
        if words.is_empty() {
            return Vec::new();
        }
        let mut ranked: Vec<(f64, Match)> = self
            .visits
            .iter()
            .filter_map(|v| {
                let address = strip_scheme(&v.url).to_lowercase();
                let title = v.title.to_lowercase();
                if !words.iter().all(|w| address.contains(w) || title.contains(w)) {
                    return None;
                }
                let site_prefix = address.starts_with(&query);
                let bonus = if site_prefix { 1000.0 } else { 0.0 };
                Some((
                    score(v, now) + bonus,
                    Match { url: v.url.clone(), title: v.title.clone(), site_prefix },
                ))
            })
            .collect();
        ranked.sort_by(|a, b| b.0.total_cmp(&a.0));
        ranked.into_iter().map(|(_, m)| m).take(limit).collect()
    }
}

/// Frecency: the visit count matters logarithmically and fades over the
/// weeks since the last visit, so a page visited daily last month still
/// beats one seen once today.
fn score(v: &Visit, now: u64) -> f64 {
    let days = now.saturating_sub(v.last_ms) as f64 / DAY_MS;
    (1.0 + v.count as f64).ln() * 10.0 / (1.0 + days / 14.0)
}

/// "https://www.example.com/a" -> "example.com/a"
fn strip_scheme(url: &str) -> &str {
    let rest = url.split_once("://").map_or(url, |(_, r)| r);
    rest.strip_prefix("www.").unwrap_or(rest)
}
