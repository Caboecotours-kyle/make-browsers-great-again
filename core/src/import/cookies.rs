//! Other browsers' cookies, so imported profiles stay signed in.
//!
//! Chromium-based browsers (Arc too) encrypt each value with AES-128-CBC,
//! under a key derived (PBKDF2-SHA1, "saltysalt", 1003 rounds) from a
//! password they keep in the keychain, e.g. "Chrome Safe Storage". The shell
//! reads that password, with the person's permission, and passes it in.
//! Since version 24 of their database the plaintext starts with a SHA-256
//! of the cookie's domain. Firefox keeps values in the clear.

use super::{firefox, Kind, Source};
use rusqlite::Connection;
use std::path::{Path, PathBuf};

/// Microseconds from 1601 (Chromium's and the engine's clock) to 1970.
const UNIX_EPOCH_US: i64 = 11_644_473_600_000_000;

#[derive(Debug, Clone, PartialEq)]
pub struct Cookie {
    /// ".example.com" for the domain and its subdomains, "example.com" for
    /// that host alone.
    pub domain: String,
    pub name: String,
    pub value: String,
    pub path: String,
    pub secure: bool,
    pub http_only: bool,
    /// Microseconds since 1601; 0 for a session cookie.
    pub expires: i64,
    pub created: i64,
    pub last_used: i64,
    /// Chromium's values: -1 unspecified, 0 none, 1 lax, 2 strict.
    pub same_site: i32,
    /// 0 low, 1 medium, 2 high.
    pub priority: i32,
}

/// The keychain item holding the password a Chromium-based browser
/// encrypts its cookies with.
pub fn keychain_service(source: &Source) -> Option<String> {
    let name = match source.kind {
        Kind::Arc => "Arc",
        Kind::Chromium if source.name.starts_with("Chrome") => "Chrome",
        Kind::Chromium if source.name == "Edge" => "Microsoft Edge",
        Kind::Chromium if source.name == "Yandex Browser" => "Yandex",
        Kind::Chromium => &source.name,
        Kind::Firefox | Kind::Safari => return None,
    };
    Some(format!("{name} Safe Storage"))
}

/// Where one profile of `source` keeps its cookies, if it has any.
pub fn database(source: &Source, profile_id: &str) -> Option<PathBuf> {
    let data_dir = Path::new(&source.id);
    let candidates = match source.kind {
        Kind::Arc | Kind::Chromium => {
            let profile = if source.kind == Kind::Arc { data_dir.join("User Data") } else { data_dir.to_path_buf() }
                .join(profile_id);
            vec![profile.join("Cookies"), profile.join("Network/Cookies")]
        }
        Kind::Firefox => vec![firefox::profile_path(data_dir, profile_id).join("cookies.sqlite")],
        Kind::Safari => Vec::new(),
    };
    candidates.into_iter().find(|p| p.exists())
}

/// The cookies of one profile of `source` that haven't expired by `now_ms`.
/// Chromium-based browsers need their keychain `password`.
pub fn read(source: &Source, profile_id: &str, password: Option<&[u8]>, now_ms: u64) -> Result<Vec<Cookie>, String> {
    if source.kind == Kind::Safari {
        return Err("Safari's cookies can't be imported.".into());
    }
    let db = database(source, profile_id).ok_or("It has no cookies.")?;
    let now = UNIX_EPOCH_US + now_ms as i64 * 1000;
    let cookies = if source.kind == Kind::Firefox {
        super::read_copy(&db, read_firefox)?
    } else {
        let password = password.ok_or("Its keychain password is needed.")?;
        let key = derive_key(password).ok_or("Can't derive its cookie key.")?;
        super::read_copy(&db, |db| read_chromium(db, &key))?
    };
    Ok(cookies.into_iter().filter(|c| c.expires == 0 || c.expires > now).collect())
}

fn read_chromium(db: &Connection, key: &[u8; 16]) -> rusqlite::Result<Vec<Cookie>> {
    let version: i64 = db
        .query_row("SELECT value FROM meta WHERE key = 'version'", [], |r| r.get::<_, String>(0))
        .map(|v| v.parse().unwrap_or(0))
        .unwrap_or(0);
    let columns = columns(db, "cookies")?;
    let has = |c: &str| columns.iter().any(|n| n == c);
    // Older databases name some columns differently or lack them.
    let secure = if has("is_secure") { "is_secure" } else { "secure" };
    let http_only = if has("is_httponly") { "is_httponly" } else { "httponly" };
    let persistent = if has("is_persistent") { "is_persistent" } else { "persistent" };
    let same_site = if has("samesite") { "samesite" } else { "-1" };
    let priority = if has("priority") { "priority" } else { "1" };
    // Cookies partitioned by a top-level site can't be recreated as they were.
    let partitioned = if has("top_frame_site_key") { "top_frame_site_key = ''" } else { "1" };
    let sql = format!(
        "SELECT host_key, name, value, encrypted_value, path, {secure}, {http_only}, expires_utc, {persistent},
                creation_utc, last_access_utc, {same_site}, {priority}
         FROM cookies WHERE {partitioned}"
    );
    let mut stmt = db.prepare(&sql)?;
    let rows = stmt.query_map([], |r| {
        let domain: String = r.get(0)?;
        let plain: String = r.get(2)?;
        let encrypted: Vec<u8> = r.get(3)?;
        let value = if !plain.is_empty() || encrypted.is_empty() {
            Some(plain)
        } else {
            decrypt(key, &encrypted, version >= 24)
        };
        Ok(value.map(|value| Cookie {
            domain,
            name: r.get(1).unwrap_or_default(),
            value,
            path: r.get(4).unwrap_or_default(),
            secure: r.get::<_, i64>(5).unwrap_or(0) != 0,
            http_only: r.get::<_, i64>(6).unwrap_or(0) != 0,
            expires: if r.get::<_, i64>(8).unwrap_or(1) != 0 { r.get(7).unwrap_or(0) } else { 0 },
            created: r.get(9).unwrap_or(0),
            last_used: r.get(10).unwrap_or(0),
            same_site: r.get(11).unwrap_or(-1),
            priority: r.get(12).unwrap_or(1),
        }))
    })?;
    // A value that won't decrypt (another key, a newer format) is left out.
    Ok(rows.filter_map(|r| r.ok().flatten()).map(sane).collect())
}

fn read_firefox(db: &Connection) -> rusqlite::Result<Vec<Cookie>> {
    let columns = columns(db, "moz_cookies")?;
    let same_site = if columns.iter().any(|c| c == "sameSite") { "sameSite" } else { "256" };
    // Containers and partitioned cookies carry origin attributes; only the
    // default jar is the person's everyday sign-ins.
    let sql = format!(
        "SELECT host, name, value, path, isSecure, isHttpOnly, expiry, creationTime, lastAccessed, {same_site}
         FROM moz_cookies WHERE originAttributes = ''"
    );
    let mut stmt = db.prepare(&sql)?;
    let rows = stmt.query_map([], |r| {
        let expiry: i64 = r.get(6)?;
        // Seconds until Firefox 136ish, milliseconds since.
        let expires_ms = if expiry > 100_000_000_000 { expiry } else { expiry.saturating_mul(1000) };
        Ok(Cookie {
            domain: r.get(0)?,
            name: r.get(1)?,
            value: r.get(2)?,
            path: r.get(3)?,
            secure: r.get::<_, i64>(4)? != 0,
            http_only: r.get::<_, i64>(5)? != 0,
            expires: UNIX_EPOCH_US + expires_ms.saturating_mul(1000),
            created: UNIX_EPOCH_US + r.get::<_, i64>(7)?,
            last_used: UNIX_EPOCH_US + r.get::<_, i64>(8)?,
            same_site: match r.get::<_, i64>(9)? {
                0 => 0,
                1 => 1,
                2 => 2,
                _ => -1,
            },
            priority: 1,
        })
    })?;
    Ok(rows.filter_map(Result::ok).map(sane).collect())
}

/// SameSite=None needs Secure, or Chromium refuses the cookie.
fn sane(mut cookie: Cookie) -> Cookie {
    if cookie.same_site == 0 && !cookie.secure {
        cookie.same_site = -1;
    }
    cookie
}

fn columns(db: &Connection, table: &str) -> rusqlite::Result<Vec<String>> {
    let mut stmt = db.prepare(&format!("PRAGMA table_info({table})"))?;
    let names = stmt.query_map([], |r| r.get::<_, String>(1))?.filter_map(Result::ok).collect();
    Ok(names)
}

fn decrypt(key: &[u8; 16], encrypted: &[u8], hashed_domain: bool) -> Option<String> {
    let data = encrypted.strip_prefix(b"v10")?;
    let mut plain = crypto::aes_cbc(false, key, data)?;
    if hashed_domain {
        if plain.len() < 32 {
            return None;
        }
        plain.drain(..32);
    }
    String::from_utf8(plain).ok()
}

fn derive_key(password: &[u8]) -> Option<[u8; 16]> {
    crypto::pbkdf2_sha1(password, b"saltysalt", 1003)
}

#[cfg(test)]
pub(super) fn encrypt_for_test(password: &[u8], domain: &str, value: &str) -> Vec<u8> {
    let key = derive_key(password).unwrap();
    let mut plain = crypto::sha256(domain.as_bytes()).to_vec();
    plain.extend_from_slice(value.as_bytes());
    let mut out = b"v10".to_vec();
    out.extend(crypto::aes_cbc(true, &key, &plain).unwrap());
    out
}

/// AES and PBKDF2 from the system's CommonCrypto.
#[cfg(target_os = "macos")]
mod crypto {
    use std::ffi::c_void;

    const PBKDF2: u32 = 2;
    const HMAC_SHA1: u32 = 1;
    const AES128: u32 = 0;
    const PKCS7: u32 = 1;

    extern "C" {
        fn CCKeyDerivationPBKDF(
            algorithm: u32,
            password: *const u8,
            password_len: usize,
            salt: *const u8,
            salt_len: usize,
            prf: u32,
            rounds: u32,
            derived: *mut u8,
            derived_len: usize,
        ) -> i32;
        fn CCCrypt(
            op: u32,
            alg: u32,
            options: u32,
            key: *const c_void,
            key_len: usize,
            iv: *const c_void,
            data_in: *const c_void,
            data_in_len: usize,
            data_out: *mut c_void,
            data_out_available: usize,
            data_out_moved: *mut usize,
        ) -> i32;
        #[cfg(test)]
        fn CC_SHA256(data: *const c_void, len: u32, md: *mut u8) -> *mut u8;
    }

    #[cfg(test)]
    pub fn sha256(data: &[u8]) -> [u8; 32] {
        let mut digest = [0u8; 32];
        unsafe { CC_SHA256(data.as_ptr().cast(), data.len() as u32, digest.as_mut_ptr()) };
        digest
    }

    pub fn pbkdf2_sha1(password: &[u8], salt: &[u8], rounds: u32) -> Option<[u8; 16]> {
        let mut key = [0u8; 16];
        let status = unsafe {
            CCKeyDerivationPBKDF(PBKDF2, password.as_ptr(), password.len(), salt.as_ptr(), salt.len(),
                                 HMAC_SHA1, rounds, key.as_mut_ptr(), key.len())
        };
        (status == 0).then_some(key)
    }

    /// AES-128-CBC with PKCS#7 padding and Chromium's IV of 16 spaces.
    pub fn aes_cbc(encrypt: bool, key: &[u8; 16], data: &[u8]) -> Option<Vec<u8>> {
        let iv = [b' '; 16];
        let mut out = vec![0u8; data.len() + 16];
        let mut moved = 0usize;
        let status = unsafe {
            CCCrypt(if encrypt { 0 } else { 1 }, AES128, PKCS7, key.as_ptr().cast(), key.len(), iv.as_ptr().cast(),
                    data.as_ptr().cast(), data.len(), out.as_mut_ptr().cast(), out.len(), &mut moved)
        };
        if status != 0 {
            return None;
        }
        out.truncate(moved);
        Some(out)
    }
}

#[cfg(not(target_os = "macos"))]
mod crypto {
    pub fn pbkdf2_sha1(_: &[u8], _: &[u8], _: u32) -> Option<[u8; 16]> {
        None
    }

    pub fn aes_cbc(_: bool, _: &[u8; 16], _: &[u8]) -> Option<Vec<u8>> {
        None
    }
}
