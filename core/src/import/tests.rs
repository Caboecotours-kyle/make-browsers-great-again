use super::*;
use serde_json::json;

const SESSION: &[u8] = include_bytes!("../../tests/fixtures/chromium-session");

fn tab(url: &str, title: &str) -> Item {
    Item::tab(url, title)
}

fn write(path: &Path, contents: impl AsRef<[u8]>) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, contents).unwrap();
}

/// A home folder with Arc, Chrome (two profiles), Helium, an unknown
/// Chromium fork, Firefox and Safari, plus things that must not be
/// detected: an Electron app and MBGA's own engine data.
fn fixture_home(name: &str) -> PathBuf {
    let home = std::env::temp_dir().join(format!("mbga-import-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&home);
    let support = home.join("Library/Application Support");

    let sidebar = json!({"sidebar": {"containers": [
        {"global": {}},
        {
            "spaces": [
                "S1", {"id": "S1", "title": "Home", "profile": {"default": true},
                       "customInfo": {"iconType": {"emoji_v2": "🏠"}, "windowTheme": {"background": {"single": {"_0": {
                           "style": {"color": {"_0": {"color": {"red": 1.0, "green": 0.5, "blue": 0.0, "alpha": 1.0}}}}}}}}},
                       "newContainerIDs": [{"pinned": {}}, "P1", {"unpinned": {"_0": {"shared": {}}}}, "U1"]},
                "S2", {"id": "S2", "title": "Work",
                       "profile": {"custom": {"_0": {"directoryBasename": "Profile 1", "machineID": "x"}}},
                       "customInfo": {"iconType": {"emoji": 128188}},
                       "newContainerIDs": [{"pinned": {}}, "P2", {"unpinned": {}}, "U2"]},
                "S3", {"id": "S3", "title": "Research", "profile": {"default": true},
                       "newContainerIDs": [{"pinned": {}}, "P3", {"unpinned": {}}, "U3"]}
            ],
            "items": [
                "P1", {"id": "P1", "childrenIds": ["F1", "T1"], "data": {"itemContainer": {}}},
                "F1", {"id": "F1", "title": "News", "parentID": "P1", "childrenIds": ["T2", "SV"], "data": {"list": {}}},
                "T2", {"id": "T2", "title": null, "parentID": "F1", "childrenIds": [],
                       "data": {"tab": {"savedURL": "https://bbc.com/", "savedTitle": "BBC"}}},
                "SV", {"id": "SV", "parentID": "F1", "childrenIds": ["T3", "T4"], "data": {"splitView": {}}},
                "T3", {"id": "T3", "parentID": "SV", "data": {"tab": {"savedURL": "https://a.com/", "savedTitle": "A"}}},
                "T4", {"id": "T4", "parentID": "SV", "data": {"tab": {"savedURL": "https://b.com/", "savedTitle": "B"}}},
                "T1", {"id": "T1", "title": "Renamed", "parentID": "P1",
                       "data": {"tab": {"savedURL": "https://example.com/", "savedTitle": "Example"}}},
                "U1", {"id": "U1", "childrenIds": ["T5", "T6"]},
                "T5", {"id": "T5", "data": {"tab": {"savedURL": "https://news.ycombinator.com/", "savedTitle": "HN"}}},
                "T6", {"id": "T6", "data": {"tab": {"savedURL": "arc://settings", "savedTitle": "Settings"}}},
                "P2", {"id": "P2", "childrenIds": ["T7"]},
                "T7", {"id": "T7", "data": {"tab": {"savedURL": "https://github.com/", "savedTitle": "GitHub"}}},
                "U2", {"id": "U2", "childrenIds": []},
                "P3", {"id": "P3", "childrenIds": ["T10"]},
                "T10", {"id": "T10", "data": {"tab": {"savedURL": "https://arxiv.org/", "savedTitle": "arXiv"}}},
                "U3", {"id": "U3", "childrenIds": []},
                "TA1", {"id": "TA1", "childrenIds": ["T8"]},
                "T8", {"id": "T8", "data": {"tab": {"savedURL": "https://mail.google.com/", "savedTitle": "Gmail"}}},
                "TA2", {"id": "TA2", "childrenIds": ["T9"]},
                "T9", {"id": "T9", "data": {"tab": {"savedURL": "https://linear.app/", "savedTitle": "Linear"}}}
            ],
            "topAppsContainerIDs": [{"default": true}, "TA1",
                                    {"custom": {"_0": {"directoryBasename": "Profile 1"}}}, "TA2"]
        }
    ]}});
    write(&support.join("Arc/StorableSidebar.json"), sidebar.to_string());
    write(
        &support.join("Arc/User Data/Local State"),
        json!({"profile": {"info_cache": {"Default": {"name": "Personal"}, "Profile 1": {"name": "Work"}}}}).to_string(),
    );

    let chrome = support.join("Google/Chrome");
    write(
        &chrome.join("Local State"),
        json!({"profile": {"info_cache": {"Default": {"name": "Person 1"}, "Profile 2": {"name": "Work"}}}}).to_string(),
    );
    write(
        &chrome.join("Default/Bookmarks"),
        json!({"roots": {
            "bookmark_bar": {"children": [
                {"type": "url", "name": "Docs", "url": "https://docs.rs/"},
                {"type": "folder", "name": "Dev", "children": [
                    {"type": "url", "name": "Rust", "url": "https://rust-lang.org/"},
                    {"type": "url", "name": "Settings", "url": "chrome://settings"}
                ]}
            ]},
            "other": {"children": []},
            "synced": {"children": [{"type": "url", "name": "Mobile", "url": "https://m.example.com/"}]}
        }})
        .to_string(),
    );
    write(&chrome.join("Default/Sessions/Session_13437039062408342"), SESSION);
    write(
        &chrome.join("Profile 2/Bookmarks"),
        json!({"roots": {"bookmark_bar": {"children": [
            {"type": "url", "name": "Jira", "url": "https://jira.example.com/"}
        ]}}})
        .to_string(),
    );

    // Helium has no profile list in its Local State: "Default" is found anyway.
    write(&support.join("net.imput.helium/Local State"), "{}");
    write(
        &support.join("net.imput.helium/Default/Bookmarks"),
        json!({"roots": {"bookmark_bar": {"children": [
            {"type": "url", "name": "Helium", "url": "https://helium.computer/"}
        ]}}})
        .to_string(),
    );

    write(&support.join("Acme/Acme Browser/Local State"), "{}");
    write(
        &support.join("Acme/Acme Browser/Default/Bookmarks"),
        json!({"roots": {"other": {"children": [
            {"type": "url", "name": "Acme", "url": "https://acme.example/"}
        ]}}})
        .to_string(),
    );
    write(&support.join("Slack/Local State"), "{}");
    write(&support.join("MBGA/engine/Local State"), "{}");
    write(&support.join("MBGA/engine/Profile 1/History"), "");

    let firefox = support.join("Firefox");
    write(
        &firefox.join("profiles.ini"),
        "[General]\nStartWithLastProfile=1\n\n[Profile0]\nName=default-release\nIsRelative=1\nPath=Profiles/abc.default-release\n",
    );
    let places = firefox.join("Profiles/abc.default-release/places.sqlite");
    fs::create_dir_all(places.parent().unwrap()).unwrap();
    let db = rusqlite::Connection::open(&places).unwrap();
    db.execute_batch(
        "CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, title TEXT);
         CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, parent INTEGER,
                                     position INTEGER, title TEXT, guid TEXT);
         INSERT INTO moz_places VALUES (1, 'https://mozilla.org/', 'Mozilla'), (2, 'https://mdn.dev/', 'MDN'),
                                       (3, 'place:sort=8', NULL);
         INSERT INTO moz_bookmarks VALUES
           (1, 2, NULL, 0, 0, '', 'root________'),
           (2, 2, NULL, 1, 0, 'menu', 'menu________'),
           (3, 2, NULL, 1, 1, 'toolbar', 'toolbar_____'),
           (4, 2, NULL, 1, 2, 'unfiled', 'unfiled_____'),
           (5, 2, NULL, 1, 3, 'mobile', 'mobile______'),
           (6, 1, 1, 3, 0, 'Mozilla', 'a'),
           (7, 2, NULL, 3, 1, 'Stuff', 'b'),
           (8, 1, 2, 7, 0, 'MDN docs', 'c'),
           (9, 1, 3, 7, 1, 'Most Visited', 'd'),
           (10, 3, NULL, 3, 2, NULL, 'e');",
    )
    .unwrap();
    drop(db);

    let mut leaf = plist::Dictionary::new();
    leaf.insert("WebBookmarkType".into(), "WebBookmarkTypeLeaf".into());
    leaf.insert("URLString".into(), "https://apple.com/".into());
    let mut uri = plist::Dictionary::new();
    uri.insert("title".into(), "Apple".into());
    leaf.insert("URIDictionary".into(), uri.into());
    let mut bar = plist::Dictionary::new();
    bar.insert("WebBookmarkType".into(), "WebBookmarkTypeList".into());
    bar.insert("Title".into(), "BookmarksBar".into());
    bar.insert("Children".into(), vec![plist::Value::from(leaf)].into());
    let mut reading = plist::Dictionary::new();
    reading.insert("WebBookmarkType".into(), "WebBookmarkTypeList".into());
    reading.insert("Title".into(), "com.apple.ReadingList".into());
    reading.insert("Children".into(), Vec::<plist::Value>::new().into());
    let mut root = plist::Dictionary::new();
    root.insert("Children".into(), vec![plist::Value::from(bar), plist::Value::from(reading)].into());
    let safari = home.join("Library/Safari/Bookmarks.plist");
    fs::create_dir_all(safari.parent().unwrap()).unwrap();
    plist::Value::from(root).to_file_binary(&safari).unwrap();

    home
}

fn exclude(home: &Path) -> PathBuf {
    home.join("Library/Application Support/MBGA")
}

#[test]
fn session_file_replays_to_open_tabs() {
    // Written by Chromium 154: example.com navigated to example.org, a
    // Wikipedia tab opened, an IANA tab closed.
    let tabs = snss::parse(SESSION).unwrap();
    let urls: Vec<&str> = tabs.iter().map(|t| t.url.as_str()).collect();
    assert_eq!(urls, ["https://example.org/", "https://www.wikipedia.org/"]);
    assert_eq!(tabs[1].title, "Wikipedia");
    assert!(tabs.iter().all(|t| !t.pinned));
    assert_eq!(snss::parse(b"not a session"), None);
}

#[test]
fn detects_browsers_and_skips_look_alikes() {
    let home = fixture_home("detect");
    let sources = detect(&home, &exclude(&home));
    let names: Vec<&str> = sources.iter().map(|s| s.name.as_str()).collect();
    assert_eq!(names, ["Arc", "Chrome", "Helium", "Acme Browser", "Firefox", "Safari"]);
    let chrome = &sources[1];
    assert_eq!(chrome.kind, Kind::Chromium);
    assert_eq!(chrome.bundle_id.as_deref(), Some("com.google.Chrome"));
    let profiles: Vec<(&str, &str)> = chrome.profiles.iter().map(|p| (p.id.as_str(), p.name.as_str())).collect();
    assert_eq!(profiles, [("Default", "Chrome · Person 1"), ("Profile 2", "Chrome · Work")]);
    assert_eq!(sources[2].profiles[0].name, "Helium");
    let _ = fs::remove_dir_all(home);
}

#[test]
fn arc_sidebar_becomes_profiles_spaces_and_favorites() {
    let home = fixture_home("arc");
    let sources = detect(&home, &exclude(&home));
    let arc = &sources[0];
    assert_eq!(arc.profiles.len(), 2);

    let personal = &arc.profiles[0];
    assert_eq!((personal.id.as_str(), personal.name.as_str()), ("Default", "Personal"));
    assert_eq!(personal.favorites, [tab("https://mail.google.com/", "Gmail")]);
    let space = &personal.spaces[0];
    assert_eq!(space.name, "Home");
    assert_eq!(space.icon.as_deref(), Some("🏠"));
    assert_eq!(space.color, Some(0xFF8000));
    assert_eq!(
        space.pinned,
        [
            Item::folder(
                "News",
                vec![tab("https://bbc.com/", "BBC"), tab("https://a.com/", "A"), tab("https://b.com/", "B")],
                true
            ),
            tab("https://example.com/", "Renamed"),
        ]
    );
    // arc:// pages are left behind.
    assert_eq!(space.today, [tab("https://news.ycombinator.com/", "HN")]);

    let work = &arc.profiles[1];
    assert_eq!(work.name, "Work");
    assert_eq!(work.spaces[0].icon.as_deref(), Some("💼"));
    assert_eq!(work.spaces[0].pinned, [tab("https://github.com/", "GitHub")]);
    assert_eq!(work.favorites, [tab("https://linear.app/", "Linear")]);
    let _ = fs::remove_dir_all(home);
}

#[test]
fn chromium_bookmarks_and_open_tabs() {
    let home = fixture_home("chromium");
    let sources = detect(&home, &exclude(&home));
    let profile = &sources[1].profiles[0];
    let space = &profile.spaces[0];
    assert_eq!(space.name, "Chrome · Person 1");
    assert_eq!(
        space.pinned,
        [
            Item::folder(
                "Bookmarks Bar",
                vec![
                    tab("https://docs.rs/", "Docs"),
                    Item::folder("Dev", vec![tab("https://rust-lang.org/", "Rust")], false),
                ],
                false
            ),
            Item::folder("Mobile Bookmarks", vec![tab("https://m.example.com/", "Mobile")], false),
        ]
    );
    let today: Vec<&Item> = space.today.iter().collect();
    assert_eq!(today.len(), 2);
    let _ = fs::remove_dir_all(home);
}

#[test]
fn firefox_and_safari_bookmarks() {
    let home = fixture_home("ff");
    let sources = detect(&home, &exclude(&home));
    let firefox = sources.iter().find(|s| s.kind == Kind::Firefox).unwrap();
    assert_eq!(
        firefox.profiles[0].spaces[0].pinned,
        [Item::folder(
            "Bookmarks Toolbar",
            vec![
                tab("https://mozilla.org/", "Mozilla"),
                Item::folder("Stuff", vec![tab("https://mdn.dev/", "MDN docs")], false),
            ],
            false
        )]
    );
    let safari = sources.iter().find(|s| s.kind == Kind::Safari).unwrap();
    assert_eq!(
        safari.profiles[0].spaces[0].pinned,
        [Item::folder("Favorites Bar", vec![tab("https://apple.com/", "Apple")], false)]
    );
    let _ = fs::remove_dir_all(home);
}

#[test]
fn importing_into_a_fresh_state_replaces_the_empty_space() {
    let home = fixture_home("apply");
    let sources = detect(&home, &exclude(&home));
    let arc = &sources[0];
    let mut state = State::new_default();
    let chosen: Vec<(&Source, &ImportedProfile)> = arc.profiles.iter().map(|p| (arc, p)).collect();
    let counts = apply(&mut state, &chosen, 1);
    assert_eq!(counts, Counts { spaces: 3, pinned: 6, favorites: 2, today: 1 });

    // The unused "Personal" profile and "Home" space are gone; Arc's took
    // over, in Arc's sidebar order.
    let names: Vec<&str> = state.profiles.iter().map(|p| p.name.as_str()).collect();
    assert_eq!(names, ["Personal", "Work"]);
    let spaces: Vec<&str> = state.spaces.iter().map(|s| s.name.as_str()).collect();
    assert_eq!(spaces, ["Home", "Work", "Research"]);
    assert_eq!(state.spaces[2].profile_id, state.profiles[0].id);
    assert_eq!(state.active_space, state.spaces[0].id);
    let home_space = &state.spaces[0];
    assert_eq!(home_space.profile_id, state.profiles[0].id);
    assert_eq!(home_space.today.len(), 1);
    let today = &state.tabs[&home_space.today[0]];
    assert_eq!((today.url.as_str(), today.title.as_str(), today.pinned_url.as_ref()), ("https://news.ycombinator.com/", "HN", None));
    let mut pinned = Vec::new();
    crate::model::collect_tabs(&home_space.pinned, &mut pinned);
    assert!(pinned.iter().all(|id| state.tabs[id].pinned_url.is_some() && !state.tabs[id].live));
    let fav = state.favorites[&state.profiles[0].id][0];
    assert_eq!(state.tabs[&fav].pinned_url.as_deref(), Some("https://mail.google.com/"));
    let _ = fs::remove_dir_all(home);
}

#[test]
fn importing_into_a_used_state_adds_alongside() {
    let home = fixture_home("apply-used");
    let sources = detect(&home, &exclude(&home));
    let arc = &sources[0];
    let mut state = State::new_default();
    let existing = state.spaces[0].id;
    state.open_tab(existing, "https://kept.example/", true, 1);
    apply(&mut state, &[(arc, &arc.profiles[0])], 2);
    let names: Vec<&str> = state.profiles.iter().map(|p| p.name.as_str()).collect();
    assert_eq!(names, ["Personal", "Personal (Arc)"]);
    assert_eq!(state.spaces.len(), 3);
    assert_eq!(state.spaces[0].id, existing);
    assert_eq!(state.active_space, state.spaces[1].id);
    let _ = fs::remove_dir_all(home);
}
