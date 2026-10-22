//! Other browsers' saved passwords.
//!
//! Chromium-based browsers (Arc too) keep them in each profile's "Login
//! Data" database (and "Login Data For Account" for those saved to the
//! person's account), encrypted like their cookies with the key in their
//! keychain item. Firefox keeps them in "logins.json", encrypted with a key
//! that "key4.db" holds, itself sealed with the Primary Password (empty for
//! most people). Safari's live in the system's Passwords app, which only
//! gives them out as an exported file; so do password managers, hence
//! `read_csv`.

use super::cookies::{columns, decrypt_value, derive_key};
use super::{firefox, Kind, Source};
use crate::crypto::{self, Cipher, Hash};
use base64::Engine;
use rusqlite::Connection;
use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};

/// Microseconds from 1601 (Chromium's clock) to 1970.
const UNIX_EPOCH_US: i64 = 11_644_473_600_000_000;

#[derive(Debug, Clone, PartialEq)]
pub struct ImportedLogin {
    /// The page it was saved on; only its origin matters.
    pub url: String,
    pub username: String,
    pub password: String,
    /// Milliseconds since 1970, 0 when unknown.
    pub created_ms: u64,
    pub used_ms: u64,
    pub changed_ms: u64,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Read {
    pub logins: Vec<ImportedLogin>,
    /// Sites the person told the browser never to save a password for.
    pub never: Vec<String>,
    /// Saved passwords that couldn't be decrypted.
    pub unreadable: u32,
}

/// Where one profile of a Chromium-based `source` keeps its passwords.
fn chromium_databases(source: &Source, profile_id: &str) -> Vec<PathBuf> {
    let data_dir = Path::new(&source.id);
    let profile =
        if source.kind == Kind::Arc { data_dir.join("User Data") } else { data_dir.to_path_buf() }.join(profile_id);
    ["Login Data", "Login Data For Account"].iter().map(|f| profile.join(f)).filter(|p| p.exists()).collect()
}

/// How many passwords one profile of `source` has saved, without
/// decrypting them. Safari's can't be counted.
pub fn count(source: &Source, profile_id: &str) -> u32 {
    match source.kind {
        Kind::Arc | Kind::Chromium => chromium_databases(source, profile_id)
            .iter()
            .filter_map(|db| {
                super::read_copy(db, |db| {
                    db.query_row(
                        "SELECT COUNT(*) FROM logins WHERE blacklisted_by_user = 0 AND length(password_value) > 0
                             AND (origin_url LIKE 'http://%' OR origin_url LIKE 'https://%')",
                        [],
                        |r| r.get::<_, u32>(0),
                    )
                })
                .ok()
            })
            .sum(),
        Kind::Firefox => {
            firefox_logins(&firefox::profile_path(Path::new(&source.id), profile_id)).map_or(0, |l| l.len() as u32)
        }
        Kind::Safari => 0,
    }
}

/// One profile's passwords. Chromium-based browsers need their keychain
/// `password`.
pub fn read(source: &Source, profile_id: &str, password: Option<&[u8]>) -> Result<Read, String> {
    match source.kind {
        Kind::Arc | Kind::Chromium => {
            let databases = chromium_databases(source, profile_id);
            if databases.is_empty() {
                return Err("It has no saved passwords.".into());
            }
            let password = password.ok_or("Its keychain password is needed.")?;
            let key = derive_key(password).ok_or("Can't derive its password key.")?;
            let mut read = Read::default();
            for db in databases {
                let part = super::read_copy(&db, |db| read_chromium(db, &key))?;
                read.logins.extend(part.logins);
                read.never.extend(part.never);
                read.unreadable += part.unreadable;
            }
            if read.logins.is_empty() && read.unreadable > 0 {
                return Err("Its passwords didn't decrypt with the key in your keychain.".into());
            }
            Ok(read)
        }
        Kind::Firefox => read_firefox(&firefox::profile_path(Path::new(&source.id), profile_id)),
        Kind::Safari => Err(SAFARI.into()),
    }
}

pub const SAFARI: &str =
    "Safari's passwords are in the Passwords app. Choose File ▸ Export All Passwords there, then import the file.";

fn read_chromium(db: &Connection, key: &[u8]) -> rusqlite::Result<Read> {
    let columns = columns(db, "logins")?;
    let has = |c: &str| columns.iter().any(|n| n == c);
    let used = if has("date_last_used") { "date_last_used" } else { "0" };
    let changed = if has("date_password_modified") { "date_password_modified" } else { "date_created" };
    let sql = format!(
        "SELECT origin_url, signon_realm, username_value, password_value, blacklisted_by_user, date_created,
                {used}, {changed}
         FROM logins"
    );
    let mut stmt = db.prepare(&sql)?;
    let mut read = Read::default();
    let rows = stmt.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1).unwrap_or_default(),
            r.get::<_, String>(2).unwrap_or_default(),
            r.get::<_, Vec<u8>>(3).unwrap_or_default(),
            r.get::<_, i64>(4).unwrap_or(0) != 0,
            [r.get::<_, i64>(5).unwrap_or(0), r.get::<_, i64>(6).unwrap_or(0), r.get::<_, i64>(7).unwrap_or(0)],
        ))
    })?;
    for (origin, realm, username, encrypted, never, [created, used, changed]) in rows.filter_map(Result::ok) {
        let url = if origin.is_empty() { realm } else { origin };
        // Android apps ("android://…") and federated sign-ins have no web
        // password to fill.
        if !(url.starts_with("https://") || url.starts_with("http://")) {
            continue;
        }
        if never {
            read.never.push(url);
            continue;
        }
        if encrypted.is_empty() {
            continue;
        }
        match decrypt_value(key, &encrypted).and_then(|p| String::from_utf8(p).ok()) {
            Some(password) if !password.is_empty() => read.logins.push(ImportedLogin {
                url,
                username,
                password,
                created_ms: chromium_ms(created),
                used_ms: chromium_ms(used),
                changed_ms: chromium_ms(changed),
            }),
            Some(_) => {}
            None => read.unreadable += 1,
        }
    }
    Ok(read)
}

fn chromium_ms(us: i64) -> u64 {
    if us <= UNIX_EPOCH_US {
        0
    } else {
        ((us - UNIX_EPOCH_US) / 1000) as u64
    }
}

// ------------------------------------------------------------------ Firefox

/// The web logins in a Firefox profile's "logins.json"; logins for HTTP
/// authentication dialogs are left out.
fn firefox_logins(profile: &Path) -> Option<Vec<Value>> {
    let bytes = fs::read(profile.join("logins.json")).ok()?;
    let json: Value = serde_json::from_slice(&bytes).ok()?;
    let logins = json["logins"].as_array()?;
    Some(logins.iter().filter(|l| l["httpRealm"].is_null() && l["hostname"].as_str().is_some()).cloned().collect())
}

pub const FIREFOX_PRIMARY_PASSWORD: &str = "It has a Primary Password. In Firefox, export its passwords from the Passwords page (⋯ ▸ Export Passwords), then import the file.";

fn read_firefox(profile: &Path) -> Result<Read, String> {
    let logins = firefox_logins(profile).ok_or("It has no saved passwords.")?;
    let key = firefox_key(profile)?;
    let mut read = Read::default();
    let b64 = base64::engine::general_purpose::STANDARD;
    for login in logins {
        let field = |name: &str| {
            b64.decode(login[name].as_str().unwrap_or_default())
                .ok()
                .and_then(|blob| decrypt_login_field(&key, &blob))
                .and_then(|plain| String::from_utf8(plain).ok())
        };
        let (Some(username), Some(password)) = (field("encryptedUsername"), field("encryptedPassword")) else {
            read.unreadable += 1;
            continue;
        };
        if password.is_empty() {
            continue;
        }
        let ms = |name: &str| login[name].as_u64().unwrap_or(0);
        read.logins.push(ImportedLogin {
            url: login["hostname"].as_str().unwrap_or_default().to_string(),
            username,
            password,
            created_ms: ms("timeCreated"),
            used_ms: ms("timeLastUsed"),
            changed_ms: ms("timePasswordChanged"),
        });
    }
    if read.logins.is_empty() && read.unreadable > 0 {
        return Err("Its passwords couldn't be decrypted.".into());
    }
    Ok(read)
}

/// The key that encrypts the profile's logins, from "key4.db", if no
/// Primary Password seals it.
fn firefox_key(profile: &Path) -> Result<Vec<u8>, String> {
    let db = profile.join("key4.db");
    if !db.exists() {
        return Err("Its password key (key4.db) is missing.".into());
    }
    let (salt, check, keys) = super::read_copy(&db, |db| {
        let (salt, check) = db.query_row("SELECT item1, item2 FROM metaData WHERE id = 'password'", [], |r| {
            Ok((r.get::<_, Vec<u8>>(0)?, r.get::<_, Vec<u8>>(1)?))
        })?;
        let mut stmt = db.prepare("SELECT a11, a102 FROM nssPrivate")?;
        let keys = stmt
            .query_map([], |r| Ok((r.get::<_, Vec<u8>>(0)?, r.get::<_, Vec<u8>>(1)?)))?
            .filter_map(Result::ok)
            .collect::<Vec<_>>();
        Ok((salt, check, keys))
    })
    .map_err(|e| format!("Can't read its password key: {e}"))?;
    match decrypt_pbe(&check, &salt, b"") {
        Some(plain) if plain.starts_with(b"password-check") => {}
        _ => return Err(FIREFOX_PRIMARY_PASSWORD.into()),
    }
    // The logins key is the one with NSS's fixed key ID.
    const KEY_ID: [u8; 16] = [0xf8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1];
    keys.iter()
        .filter(|(_, id)| id.as_slice() == KEY_ID)
        .find_map(|(sealed, _)| decrypt_pbe(sealed, &salt, b""))
        .ok_or_else(|| "Can't decrypt its password key.".into())
}

mod oid {
    pub const PBES2: &[u8] = &[0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x05, 0x0d];
    pub const PBE_SHA1_3DES: &[u8] = &[0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x05, 0x01, 0x03];
    pub const AES256_CBC: &[u8] = &[0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x01, 0x2a];
    pub const DES_EDE3_CBC: &[u8] = &[0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x03, 0x07];
}

/// A DER element: its tag, its contents and what follows it.
fn der(input: &[u8]) -> Option<(u8, &[u8], &[u8])> {
    let (&tag, rest) = input.split_first()?;
    let (&first, mut rest) = rest.split_first()?;
    let len = if first < 0x80 {
        first as usize
    } else {
        let n = (first & 0x7f) as usize;
        if n == 0 || n > 4 || rest.len() < n {
            return None;
        }
        let len = rest[..n].iter().fold(0usize, |l, &b| l << 8 | b as usize);
        rest = &rest[n..];
        len
    };
    (rest.len() >= len).then(|| (tag, &rest[..len], &rest[len..]))
}

/// The elements inside a DER SEQUENCE.
fn sequence(input: &[u8]) -> Option<Vec<(u8, &[u8])>> {
    let (tag, body, _) = der(input)?;
    if tag != 0x30 {
        return None;
    }
    inner(body)
}

/// The elements in the `contents` of a constructed element.
fn inner(mut contents: &[u8]) -> Option<Vec<(u8, &[u8])>> {
    let mut out = Vec::new();
    while !contents.is_empty() {
        let (tag, body, rest) = der(contents)?;
        out.push((tag, body));
        contents = rest;
    }
    Some(out)
}

#[cfg(test)]
fn encode_len(len: usize) -> Vec<u8> {
    if len < 0x80 {
        return vec![len as u8];
    }
    let bytes: Vec<u8> = len.to_be_bytes().into_iter().skip_while(|&b| b == 0).collect();
    let mut out = vec![0x80 | bytes.len() as u8];
    out.extend(bytes);
    out
}

fn integer(contents: &[u8]) -> u32 {
    contents.iter().fold(0u32, |n, &b| n << 8 | b as u32)
}

/// Decrypts a password-based encrypted blob of "key4.db" (the password
/// check, or a key) with `global_salt` and the Primary Password.
fn decrypt_pbe(blob: &[u8], global_salt: &[u8], primary: &[u8]) -> Option<Vec<u8>> {
    let outer = sequence(blob)?;
    let (_, algorithm) = outer.first()?;
    let (_, ciphertext) = outer.get(1).filter(|(tag, _)| *tag == 0x04)?;
    let algorithm = inner(algorithm)?;
    let (_, id) = algorithm.first()?;
    let (_, params) = algorithm.get(1)?;
    let password = crypto::digest(Hash::Sha1, &[global_salt, primary].concat());
    if *id == oid::PBES2 {
        // PBKDF2-HMAC-SHA256 then AES-256-CBC.
        let params = inner(params)?;
        let kdf = inner(params.first()?.1)?;
        let kdf_params = inner(kdf.get(1)?.1)?;
        let salt = kdf_params.first()?.1;
        let rounds = integer(kdf_params.get(1)?.1);
        let scheme = inner(params.get(1)?.1)?;
        if scheme.first()?.1 != oid::AES256_CBC {
            return None;
        }
        let iv = scheme.get(1)?.1;
        // NSS stores 14 bytes of the IV and its DER header makes up the rest.
        let iv = if iv.len() == 14 { [&[0x04, 0x0e], iv].concat() } else { iv.to_vec() };
        let key = crypto::pbkdf2(Hash::Sha256, &password, salt, rounds, 32)?;
        crypto::cbc(false, Cipher::Aes, &key, &iv, ciphertext)
    } else if *id == oid::PBE_SHA1_3DES {
        // NSS's own PKCS#12-like derivation, from before Firefox 72.
        let params = inner(params)?;
        let salt = params.first()?.1;
        let mut padded = salt.to_vec();
        padded.resize(padded.len().max(20), 0);
        let chp = crypto::digest(Hash::Sha1, &[password.as_slice(), salt].concat());
        let k1 = crypto::hmac(Hash::Sha1, &chp, &[padded.as_slice(), salt].concat());
        let tk = crypto::hmac(Hash::Sha1, &chp, &padded);
        let k2 = crypto::hmac(Hash::Sha1, &chp, &[tk.as_slice(), salt].concat());
        let k = [k1, k2].concat();
        crypto::cbc(false, Cipher::TripleDes, &k[..24], &k[32..40], ciphertext)
    } else {
        None
    }
}

/// Decrypts an encrypted username or password of "logins.json".
fn decrypt_login_field(key: &[u8], blob: &[u8]) -> Option<Vec<u8>> {
    let parts = sequence(blob)?;
    let algorithm = inner(parts.get(1)?.1)?;
    let (_, ciphertext) = parts.get(2)?;
    let (id, iv) = (algorithm.first()?.1, algorithm.get(1)?.1);
    if id == oid::DES_EDE3_CBC && key.len() >= 24 {
        crypto::cbc(false, Cipher::TripleDes, &key[..24], iv, ciphertext)
    } else if id == oid::AES256_CBC && key.len() >= 32 {
        crypto::cbc(false, Cipher::Aes, &key[..32], iv, ciphertext)
    } else {
        None
    }
}

// --------------------------------------------------------------------- CSV

/// Passwords exported to a CSV file: by the Passwords app (Safari),
/// Chrome, Firefox, 1Password, Bitwarden and most others. Columns are found
/// by their names.
pub fn read_csv(text: &str) -> Result<Read, String> {
    let mut rows = parse_csv(text.trim_start_matches('\u{feff}')).into_iter();
    let header: Vec<String> =
        rows.next().ok_or("The file is empty.")?.iter().map(|h| h.trim().to_lowercase()).collect();
    let find = |names: &[&str]| header.iter().position(|h| names.contains(&h.as_str()));
    let url =
        find(&["url", "login_uri", "website", "web site", "hostname", "origin", "login url", "uri", "web address"]);
    let username = find(&["username", "login_username", "user name", "login name", "login", "user", "email", "e-mail"]);
    let password = find(&["password", "login_password"]);
    let (Some(url), Some(password)) = (url, password) else {
        return Err("The file has no URL and Password columns.".into());
    };
    let mut read = Read::default();
    for row in rows {
        let cell = |i: usize| row.get(i).map(|s| s.trim()).unwrap_or_default();
        let (site, secret) = (cell(url), row.get(password).map(String::as_str).unwrap_or_default());
        if site.is_empty() || secret.is_empty() {
            continue;
        }
        let site = if site.contains("://") { site.to_string() } else { format!("https://{site}") };
        if !(site.starts_with("https://") || site.starts_with("http://")) {
            continue;
        }
        read.logins.push(ImportedLogin {
            url: site,
            username: username.map(cell).unwrap_or_default().to_string(),
            password: secret.to_string(),
            created_ms: 0,
            used_ms: 0,
            changed_ms: 0,
        });
    }
    Ok(read)
}

/// RFC 4180: commas, quoted fields with doubled quotes, any line ending.
fn parse_csv(text: &str) -> Vec<Vec<String>> {
    let mut rows = Vec::new();
    let mut row = Vec::new();
    let mut field = String::new();
    let mut quoted = false;
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if quoted {
            match c {
                '"' if chars.peek() == Some(&'"') => {
                    field.push('"');
                    chars.next();
                }
                '"' => quoted = false,
                _ => field.push(c),
            }
            continue;
        }
        match c {
            '"' => quoted = true,
            ',' => row.push(std::mem::take(&mut field)),
            '\r' | '\n' => {
                if c == '\r' && chars.peek() == Some(&'\n') {
                    chars.next();
                }
                row.push(std::mem::take(&mut field));
                if row.iter().any(|f| !f.is_empty()) {
                    rows.push(std::mem::take(&mut row));
                } else {
                    row.clear();
                }
            }
            _ => field.push(c),
        }
    }
    row.push(field);
    if row.iter().any(|f| !f.is_empty()) {
        rows.push(row);
    }
    rows
}

#[cfg(test)]
pub(super) mod test_support {
    use super::*;

    /// Encrypts like NSS: PBES2 with PBKDF2-HMAC-SHA256 and AES-256-CBC.
    pub fn pbes2(plain: &[u8], global_salt: &[u8], salt: &[u8], iv14: &[u8]) -> Vec<u8> {
        let password = crypto::digest(Hash::Sha1, global_salt);
        let key = crypto::pbkdf2(Hash::Sha256, &password, salt, 1, 32).unwrap();
        let iv = [&[0x04, 0x0e], iv14].concat();
        let ciphertext = crypto::cbc(true, Cipher::Aes, &key, &iv, plain).unwrap();
        let hmac = seq(&[tlv(0x06, &[0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x02, 0x09])]);
        let kdf = seq(&[
            tlv(0x06, &[0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x05, 0x0c]),
            seq(&[tlv(0x04, salt), tlv(0x02, &[1]), tlv(0x02, &[32]), hmac]),
        ]);
        let scheme = seq(&[tlv(0x06, oid::AES256_CBC), tlv(0x04, iv14)]);
        seq(&[seq(&[tlv(0x06, oid::PBES2), seq(&[kdf, scheme])]), tlv(0x04, &ciphertext)])
    }

    /// A "logins.json" field encrypted with 3DES under `key`.
    pub fn login_field(key: &[u8], plain: &str) -> String {
        let iv = [7u8; 8];
        let ciphertext = crypto::cbc(true, Cipher::TripleDes, &key[..24], &iv, plain.as_bytes()).unwrap();
        let blob = seq(&[
            tlv(0x04, &[0xf8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]),
            seq(&[tlv(0x06, oid::DES_EDE3_CBC), tlv(0x04, &iv)]),
            tlv(0x04, &ciphertext),
        ]);
        base64::engine::general_purpose::STANDARD.encode(blob)
    }

    fn tlv(tag: u8, contents: &[u8]) -> Vec<u8> {
        let mut out = vec![tag];
        out.extend(encode_len(contents.len()));
        out.extend_from_slice(contents);
        out
    }

    fn seq(parts: &[Vec<u8>]) -> Vec<u8> {
        tlv(0x30, &parts.concat())
    }
}
