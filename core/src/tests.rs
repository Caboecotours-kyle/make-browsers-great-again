use super::*;
use model::{resolve_input, Container, Pressure, State};

fn temp_dir(name: &str) -> String {
    let dir = std::env::temp_dir().join(format!("mbga-test-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    dir.to_string_lossy().into_owned()
}

fn home(s: &State) -> u64 {
    s.spaces[0].id
}

#[test]
fn default_state_has_one_space_and_profile() {
    let s = State::new_default();
    assert_eq!(s.spaces.len(), 1);
    assert_eq!(s.profiles.len(), 1);
    assert_eq!(s.active_space, home(&s));
}

#[test]
fn new_tabs_go_to_top_of_today_and_activate() {
    let mut s = State::new_default();
    let a = s.open_tab(home(&s), "https://a.com", true, 1).unwrap();
    let b = s.open_tab(home(&s), "https://b.com", true, 2).unwrap();
    assert_eq!(s.spaces[0].today, vec![b, a]);
    assert_eq!(s.visible_tab(), Some(b));
}

#[test]
fn closing_today_tab_selects_tab_below_then_above() {
    let mut s = State::new_default();
    let sp = home(&s);
    let a = s.open_tab(sp, "https://a.com", false, 1).unwrap();
    let b = s.open_tab(sp, "https://b.com", false, 2).unwrap();
    let c = s.open_tab(sp, "https://c.com", false, 3).unwrap();
    // today = [c, b, a]
    s.activate_tab(sp, b, 4);
    assert_eq!(s.close_tab(b, 5), (true, Some(a)));
    assert_eq!(s.close_tab(a, 6), (true, Some(c)));
    assert!(!s.tabs.contains_key(&a));
}

#[test]
fn closing_pinned_tab_sleeps_and_resets_url() {
    let mut s = State::new_default();
    let sp = home(&s);
    let t = s.open_tab(sp, "https://mail.com", true, 1).unwrap();
    s.move_item(t, Container::Pinned { space_id: sp, folder_id: None }, 0).unwrap();
    s.set_live(t, true);
    s.update_tab(t, Some("https://mail.com/inbox/123"), None);
    assert!(!s.close_tab(t, 2).0);
    let tab = &s.tabs[&t];
    assert_eq!(tab.url, "https://mail.com");
    assert!(!tab.live);
    assert!(s.spaces[0].active_tab.is_none());
}

#[test]
fn favorites_are_shared_by_spaces_with_the_same_profile() {
    let mut s = State::new_default();
    let p = s.profiles[0].id;
    let work_profile = s.create_profile("Work");
    let sp2 = s.create_space("Side", "✨", 0, p);
    let sp3 = s.create_space("Work", "💼", 0, work_profile);
    let t = s.open_tab(home(&s), "https://x.com", false, 1).unwrap();
    s.move_item(t, Container::Favorites { profile_id: p }, 0).unwrap();
    assert_eq!(s.profile_of_tab(t), Some(p));
    assert!(s.favorites[&p].contains(&t));
    assert_eq!(s.space(sp2).unwrap().profile_id, p);
    assert_ne!(s.space(sp3).unwrap().profile_id, p);
}

#[test]
fn moving_tab_to_other_profile_requires_reload() {
    let mut s = State::new_default();
    let work = s.create_profile("Work");
    let sp2 = s.create_space("Work", "💼", 0, work);
    let t = s.open_tab(home(&s), "https://x.com", true, 1).unwrap();
    s.set_live(t, true);
    let reload = s.move_item(t, Container::Today { space_id: sp2 }, 0).unwrap();
    assert_eq!(reload, vec![t]);
    assert!(!s.tabs[&t].live);
    // It left the home space, so it is no longer selected there.
    assert!(s.spaces[0].active_tab.is_none());
}

#[test]
fn folders_nest_and_cannot_contain_themselves() {
    let mut s = State::new_default();
    let sp = home(&s);
    let outer = s.create_folder(sp, "Outer", None).unwrap();
    let inner = s.create_folder(sp, "Inner", Some(outer)).unwrap();
    let t = s.open_tab(sp, "https://x.com", false, 1).unwrap();
    s.move_item(t, Container::Pinned { space_id: sp, folder_id: Some(inner) }, 0).unwrap();
    assert_eq!(s.locate(t), Some(Container::Pinned { space_id: sp, folder_id: Some(inner) }));
    assert!(s.move_item(outer, Container::Pinned { space_id: sp, folder_id: Some(inner) }, 0).is_none());
    assert!(s.move_item(outer, Container::Today { space_id: sp }, 0).is_none());
    assert_eq!(s.delete_folder(outer), vec![t]);
    assert!(s.tabs.is_empty());
}

#[test]
fn reorder_within_list_uses_pre_removal_index() {
    let mut s = State::new_default();
    let sp = home(&s);
    let a = s.open_tab(sp, "a", false, 1).unwrap();
    let b = s.open_tab(sp, "b", false, 2).unwrap();
    let c = s.open_tab(sp, "c", false, 3).unwrap();
    // today = [c, b, a]; drag c to the end (index 3 before removal).
    s.move_item(c, Container::Today { space_id: sp }, 3).unwrap();
    assert_eq!(s.spaces[0].today, vec![b, a, c]);
    // drag a to the front.
    s.move_item(a, Container::Today { space_id: sp }, 0).unwrap();
    assert_eq!(s.spaces[0].today, vec![a, b, c]);
}

#[test]
fn sleeps_idle_and_excess_tabs_but_never_visible_or_audible() {
    let mut s = State::new_default();
    let sp = home(&s);
    s.policy.max_live_tabs = 2;
    s.policy.sleep_after_secs = 60;
    let mut ids = Vec::new();
    for i in 0..5 {
        let id = s.open_tab(sp, &format!("https://{i}.com"), true, 1_000 + i).unwrap();
        s.set_live(id, true);
        ids.push(id);
    }
    // ids[4] is visible. Make ids[0] audible.
    s.set_audible(ids[0], true);
    let sleepers = s.collect_sleepers(2_000, Pressure::Normal);
    // 4 hidden live tabs, max 2, ids[0] protected: oldest unprotected go first.
    assert_eq!(sleepers, vec![ids[1], ids[2]]);
    // After the timeout everything hidden and silent sleeps.
    let sleepers = s.collect_sleepers(1_000 + 61_000 + 10, Pressure::Normal);
    assert_eq!(sleepers, vec![ids[3]]);
    assert!(s.tabs[&ids[4]].live);
    assert!(s.tabs[&ids[0]].live);
}

#[test]
fn critical_pressure_sleeps_everything_hidden() {
    let mut s = State::new_default();
    let sp = home(&s);
    let a = s.open_tab(sp, "a", true, 1).unwrap();
    let b = s.open_tab(sp, "b", true, 2).unwrap();
    s.set_live(a, true);
    s.set_live(b, true);
    assert_eq!(s.collect_sleepers(3, Pressure::Critical), vec![a]);
}

#[test]
fn switching_profile_of_space_sleeps_its_live_tabs() {
    let mut s = State::new_default();
    let sp = home(&s);
    let work = s.create_profile("Work");
    let a = s.open_tab(sp, "a", true, 1).unwrap();
    s.set_live(a, true);
    assert_eq!(s.set_space_profile(sp, work), vec![a]);
    assert_eq!(s.profile_of_tab(a), Some(work));
    assert!(s.delete_profile(work).is_none());
}

#[test]
fn omnibox_input_resolution() {
    let t = "https://s.test/?q=%s";
    assert_eq!(resolve_input("example.com", t), "https://example.com");
    assert_eq!(resolve_input("example.com/a?b=c", t), "https://example.com/a?b=c");
    assert_eq!(resolve_input("localhost:3000", t), "http://localhost:3000");
    assert_eq!(resolve_input("192.168.1.1", t), "http://192.168.1.1");
    assert_eq!(resolve_input("http://x", t), "http://x");
    assert_eq!(resolve_input("about:blank", t), "about:blank");
    assert_eq!(resolve_input("rust lifetimes", t), "https://s.test/?q=rust+lifetimes");
    assert_eq!(resolve_input("c++", t), "https://s.test/?q=c%2B%2B");
    assert_eq!(resolve_input("file.txt", t), "https://file.txt");
    assert_eq!(resolve_input("version1.2", t), "https://s.test/?q=version1.2");
}

#[test]
fn persists_and_reloads_through_ffi() {
    let dir = temp_dir("persist");
    let core = BrowserCore::new(dir.clone());
    let snap = core.snapshot();
    let sp = snap.active_space;
    let t = core.open_tab(sp, "https://keep.me".into(), true).unwrap();
    core.update_tab(t, None, Some("Keep".into()));
    let f = core.create_folder(sp, "Docs".into(), None).unwrap();
    core.move_item(t, DropTarget::Pinned { space_id: sp, folder_id: Some(f) }, 0).unwrap();
    core.set_live(t, true);
    assert!(core.persist());
    drop(core);

    let core = BrowserCore::new(dir.clone());
    let snap = core.snapshot();
    let space = &snap.spaces[0];
    assert_eq!(space.pinned.len(), 2);
    assert_eq!(space.pinned[0].folder_name.as_deref(), Some("Docs"));
    let row = &space.pinned[1];
    assert_eq!(row.depth, 1);
    assert_eq!(row.parent_id, Some(f));
    let tab = row.tab.as_ref().unwrap();
    assert_eq!(tab.title, "Keep");
    assert_eq!(tab.pinned_url.as_deref(), Some("https://keep.me"));
    assert!(!tab.live, "tabs always start asleep");
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn corrupt_state_is_backed_up() {
    let dir = temp_dir("corrupt");
    fs::create_dir_all(&dir).unwrap();
    fs::write(Path::new(&dir).join(STATE_FILE), b"{not json").unwrap();
    let core = BrowserCore::new(dir.clone());
    assert_eq!(core.snapshot().spaces.len(), 1);
    let backups = fs::read_dir(&dir)
        .unwrap()
        .filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().contains("corrupt"))
        .count();
    assert_eq!(backups, 1);
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn profile_dirs_are_direct_children_of_engine_root() {
    let dir = temp_dir("profiles");
    let core = BrowserCore::new(dir.clone());
    let profile = core.snapshot().profiles[0].id;
    let path = PathBuf::from(core.profile_dir(profile));
    assert_eq!(path.parent().unwrap(), Path::new(&core.engine_root_dir()));
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn freezes_only_idle_hidden_today_tabs() {
    let mut s = State::new_default();
    let sp = home(&s);
    s.policy.freeze_after_secs = 60;
    let pinned = s.open_tab(sp, "https://mail.example", true, 0).unwrap();
    s.move_item(pinned, Container::Pinned { space_id: sp, folder_id: None }, 0).unwrap();
    let old = s.open_tab(sp, "https://a.example", true, 1_000).unwrap();
    let audible = s.open_tab(sp, "https://music.example", true, 2_000).unwrap();
    let visible = s.open_tab(sp, "https://b.example", true, 3_000).unwrap();
    for id in [pinned, old, audible, visible] {
        s.set_live(id, true);
    }
    s.set_audible(audible, true);
    // Nothing has been hidden for a minute yet.
    assert!(s.collect_freezers(30_000).is_empty());
    assert_eq!(s.collect_freezers(70_000), vec![old]);
    assert!(s.collect_freezers(80_000).is_empty(), "already frozen");
    assert!(s.thaw(old));
    assert!(!s.thaw(old));
    // A recreated web view starts unfrozen.
    s.collect_freezers(90_000);
    s.set_live(old, false);
    s.set_live(old, true);
    assert!(!s.tabs[&old].frozen);
    let _ = visible;
}

#[test]
fn old_state_files_get_default_policy_fields() {
    let json = r#"{"sleep_after_secs": 30, "max_live_tabs": 2}"#;
    let p: model::Policy = serde_json::from_str(json).unwrap();
    assert_eq!(p.sleep_after_secs, 30);
    assert_eq!(p.freeze_after_secs, 60);
    assert!(!p.strict_site_isolation);
}

#[test]
fn engine_paths_are_resolved_through_symlinks() {
    let real = temp_dir("real");
    let link = temp_dir("link");
    fs::create_dir_all(&real).unwrap();
    let _ = fs::remove_file(&link);
    std::os::unix::fs::symlink(&real, &link).unwrap();
    let core = BrowserCore::new(link.clone());
    let root = PathBuf::from(core.engine_root_dir());
    assert_eq!(root, fs::canonicalize(&real).unwrap().join("engine"));
    let _ = fs::remove_file(&link);
    let _ = fs::remove_dir_all(real);
}
