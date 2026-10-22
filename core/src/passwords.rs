//! Saved passwords, per profile. Kept in their own file; each password is
//! sealed (AES-256-CBC, then HMAC-SHA256 over the IV and ciphertext) with a
//! key the shell keeps in the keychain and hands over when a password is
//! first needed. Sites and usernames stay readable, so suggestions and the
//! list in Settings work before that.

use crate::crypto::{self, Cipher, Hash};
use crate::import::passwords::ImportedLogin;
use crate::model::Id;
use base64::Engine;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Login {
    pub id: u64,
    pub profile: Id,
    /// "https://example.com" or "http://localhost:3000": scheme, host and
    /// port of the page it was saved on.
    pub origin: String,
    pub username: String,
    /// Sealed, in base64.
    pub password: String,
    pub created_ms: u64,
    pub used_ms: u64,
    pub changed_ms: u64,
}

#[derive(Serialize, Deserialize, Default, Debug)]
pub struct Store {
    pub logins: Vec<Login>,
    /// Origins, per profile, whose passwords are never offered for saving.
    pub never: Vec<(Id, String)>,
    /// A fixed text sealed with the key, telling the right key from another
    /// (say, after the keychain item was deleted).
    pub check: Option<String>,
    pub next_id: u64,
}

/// The key in two halves: one encrypts, the other authenticates.
#[derive(Clone)]
pub struct Key {
    cipher: Vec<u8>,
    mac: Vec<u8>,
}

const CHECK: &[u8] = b"MBGA passwords";

impl Key {
    /// Derives both halves from the shell's 32 random bytes.
    pub fn new(secret: &[u8]) -> Option<Key> {
        if secret.len() < 32 {
            return None;
        }
        Some(Key { cipher: crypto::hmac(Hash::Sha256, secret, b"cipher"), mac: crypto::hmac(Hash::Sha256, secret, b"mac") })
    }

    pub fn seal(&self, plain: &str) -> Option<String> {
        let iv = crypto::random(16)?;
        let mut sealed = iv.clone();
        sealed.extend(crypto::cbc(true, Cipher::Aes, &self.cipher, &iv, plain.as_bytes())?);
        let tag = crypto::hmac(Hash::Sha256, &self.mac, &sealed);
        sealed.extend(tag);
        Some(base64::engine::general_purpose::STANDARD.encode(sealed))
    }

    pub fn open(&self, sealed: &str) -> Option<String> {
        let bytes = base64::engine::general_purpose::STANDARD.decode(sealed).ok()?;
        if bytes.len() < 16 + 16 + 32 {
            return None;
        }
        let (body, tag) = bytes.split_at(bytes.len() - 32);
        if !crypto::same(&crypto::hmac(Hash::Sha256, &self.mac, body), tag) {
            return None;
        }
        let (iv, ciphertext) = body.split_at(16);
        String::from_utf8(crypto::cbc(false, Cipher::Aes, &self.cipher, iv, ciphertext)?).ok()
    }
}

/// What to ask after a sign-in form was sent.
#[derive(Debug, Clone, PartialEq)]
pub enum Offer {
    /// Saved already, or never saved on this site.
    Nothing,
    Save,
    /// The login with this username has another password now.
    Update(u64),
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct Merged {
    pub added: u32,
    pub updated: u32,
    pub kept: u32,
}

/// "https://example.com" for a web page's URL; None for other schemes.
pub fn origin_of(url: &str) -> Option<String> {
    let parsed = url::Url::parse(url).ok()?;
    matches!(parsed.scheme(), "https" | "http").then(|| parsed.origin().ascii_serialization())
}

fn host_of(origin: &str) -> &str {
    let rest = origin.split_once("://").map_or(origin, |(_, r)| r);
    rest.rsplit_once(':').filter(|(_, port)| port.bytes().all(|b| b.is_ascii_digit())).map_or(rest, |(h, _)| h)
}

/// The part of a host its owner registered: "example.co.uk" for
/// "login.example.co.uk". Addresses and single-label hosts are their own.
fn registrable(host: &str) -> &str {
    if host.parse::<std::net::IpAddr>().is_ok() || host.starts_with('[') {
        return host;
    }
    psl::domain_str(host).unwrap_or(host)
}

impl Store {
    /// Unlocks with `key`, or tells that it isn't the key the passwords
    /// were sealed with. The first key ever given becomes the key.
    pub fn verify(&mut self, key: &Key) -> bool {
        match &self.check {
            Some(check) => key.open(check).is_some_and(|c| c.as_bytes() == CHECK),
            None => {
                self.check = key.seal(std::str::from_utf8(CHECK).unwrap_or_default());
                self.check.is_some()
            }
        }
    }

    /// Logins of `profile` to offer on `url`: those saved on its very
    /// origin, then those of other hosts of the same site (another
    /// subdomain, or http for an https page), most recently used first.
    /// Logins saved over https are never offered to an http page.
    pub fn matching(&self, profile: Id, url: &str) -> Vec<&Login> {
        let Some(origin) = origin_of(url) else { return Vec::new() };
        let secure = origin.starts_with("https://");
        let site = registrable(host_of(&origin));
        let mut found: Vec<(bool, &Login)> = self
            .logins
            .iter()
            .filter(|l| l.profile == profile)
            .filter_map(|l| {
                if l.origin == origin {
                    return Some((true, l));
                }
                let same_site = registrable(host_of(&l.origin)) == site;
                (same_site && (secure || !l.origin.starts_with("https://"))).then_some((false, l))
            })
            .collect();
        found.sort_by(|(exact_a, a), (exact_b, b)| {
            exact_b.cmp(exact_a).then(b.used_ms.max(b.changed_ms).cmp(&a.used_ms.max(a.changed_ms)))
        });
        found.into_iter().map(|(_, l)| l).collect()
    }

    /// Whether to offer saving `password` sent with `username` on `url`.
    pub fn offer(&self, key: &Key, profile: Id, url: &str, username: &str, password: &str) -> Offer {
        let Some(origin) = origin_of(url) else { return Offer::Nothing };
        if password.is_empty() || self.never.iter().any(|(p, o)| *p == profile && *o == origin) {
            return Offer::Nothing;
        }
        let matching = self.matching(profile, url);
        let same_password = |l: &&Login| key.open(&l.password).is_some_and(|p| p == password);
        // Filled from a login saved here or on another host of the site.
        if matching.iter().any(|l| (l.username == username || username.is_empty()) && same_password(l)) {
            return Offer::Nothing;
        }
        match matching.iter().find(|l| l.origin == origin && l.username == username) {
            Some(l) => Offer::Update(l.id),
            None => Offer::Save,
        }
    }

    /// Saves a login, replacing the password of the one with the same
    /// origin and username.
    pub fn save(&mut self, key: &Key, profile: Id, url: &str, username: &str, password: &str, now: u64) -> Option<u64> {
        let origin = origin_of(url)?;
        let sealed = key.seal(password)?;
        if let Some(l) = self.logins.iter_mut().find(|l| l.profile == profile && l.origin == origin && l.username == username) {
            l.password = sealed;
            l.changed_ms = now;
            l.used_ms = now;
            return Some(l.id);
        }
        Some(self.insert(profile, origin, username, sealed, now, now, now))
    }

    #[allow(clippy::too_many_arguments)]
    fn insert(&mut self, profile: Id, origin: String, username: &str, sealed: String, created: u64, used: u64, changed: u64) -> u64 {
        self.next_id += 1;
        let id = self.next_id;
        self.logins.push(Login {
            id,
            profile,
            origin,
            username: username.to_string(),
            password: sealed,
            created_ms: created,
            used_ms: used,
            changed_ms: changed,
        });
        id
    }

    pub fn never_save(&mut self, profile: Id, url: &str) {
        if let Some(origin) = origin_of(url) {
            if !self.never.iter().any(|(p, o)| *p == profile && *o == origin) {
                self.never.push((profile, origin));
            }
        }
    }

    pub fn mark_used(&mut self, id: u64, now: u64) {
        if let Some(l) = self.logins.iter_mut().find(|l| l.id == id) {
            l.used_ms = now;
        }
    }

    pub fn delete(&mut self, id: u64) -> bool {
        let before = self.logins.len();
        self.logins.retain(|l| l.id != id);
        self.logins.len() != before
    }

    /// Forgets everything of profiles that no longer exist.
    pub fn keep_profiles(&mut self, profiles: &[Id]) {
        self.logins.retain(|l| profiles.contains(&l.profile));
        self.never.retain(|(p, _)| profiles.contains(p));
    }

    /// Adds imported logins to `profile`. A login MBGA has with the same
    /// origin and username takes the imported password only if that was
    /// changed more recently.
    pub fn merge(&mut self, key: &Key, profile: Id, logins: &[ImportedLogin], never: &[String], now: u64) -> Merged {
        let mut merged = Merged::default();
        for login in logins {
            let Some(origin) = origin_of(&login.url) else { continue };
            let changed = if login.changed_ms > 0 { login.changed_ms } else { login.created_ms };
            let existing = self
                .logins
                .iter()
                .position(|l| l.profile == profile && l.origin == origin && l.username == login.username);
            match existing {
                Some(i) => {
                    let current = &self.logins[i];
                    if key.open(&current.password).as_deref() == Some(login.password.as_str()) || changed <= current.changed_ms {
                        merged.kept += 1;
                        continue;
                    }
                    let Some(sealed) = key.seal(&login.password) else { continue };
                    let l = &mut self.logins[i];
                    l.password = sealed;
                    l.changed_ms = changed;
                    l.used_ms = l.used_ms.max(login.used_ms);
                    merged.updated += 1;
                }
                None => {
                    let Some(sealed) = key.seal(&login.password) else { continue };
                    let created = if login.created_ms > 0 { login.created_ms } else { now };
                    self.insert(profile, origin, &login.username, sealed, created, login.used_ms, changed.max(created));
                    merged.added += 1;
                }
            }
        }
        for url in never {
            self.never_save(profile, url);
        }
        merged
    }
}
