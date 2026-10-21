// CEF integration: application class, engine lifecycle, per-profile storage
// and one CefClient per tab. Every CEF callback used here runs on the browser
// UI thread, which on macOS is the main thread.

#import "MBEngine.h"

#include <algorithm>
#include <map>
#include <string>
#include <vector>

#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_request_context.h"
#include "include/wrapper/cef_library_loader.h"

// A permission question that is answered exactly once: by the user, or with
// Block if its tab closes first. Unanswered requests keep the engine from
// ever finishing closing the tab.
@interface MBPermissionPrompt : NSObject
- (instancetype)initWithMessage:(NSString*)message
                           done:(void (^)(BOOL allowed))done;
- (void)showForView:(NSView*)view;
- (void)answer:(BOOL)allowed;
@property(nonatomic, readonly) BOOL shown;
@property(nonatomic, readonly) BOOL answered;
@end

@interface MBWebView ()
- (void)engineAddPrompt:(MBPermissionPrompt*)prompt;
- (void)engineDidCreateBrowser:(CefRefPtr<CefBrowser>)browser;
- (void)engineWillCloseBrowser;
- (void)engineDidCloseBrowser;
- (void)engineSetMediaPlaying:(BOOL)playing;
- (void)engineSetCapturing:(BOOL)capturing;
@end

namespace {

CefScopedLibraryLoader* g_library_loader = nullptr;
std::map<std::string, CefRefPtr<CefRequestContext>> g_contexts;
// Tabs stay retained here until the engine reports them closed.
NSMutableSet<MBWebView*>* g_views = nil;
// Popup windows and DevTools, which CEF hosts in its own windows.
std::vector<CefRefPtr<CefBrowser>> g_auxiliary;
int g_browser_count = 0;
bool g_quitting = false;
bool g_strict_site_isolation = true;
std::string g_isolated_origins;

constexpr char kMediaProbePrefix[] = "__mbga_media:";
constexpr char kMediaProbeScript[] =
    "(function(){try{var p=false;"
    "document.querySelectorAll('video,audio').forEach(function(m){"
    "if(!m.paused&&!m.muted&&m.volume>0&&m.readyState>2)p=true;});"
    "console.debug('__mbga_media:'+(p?1:0));}catch(e){}})();";

enum MenuCommand {
  kOpenLinkInNewTab = MENU_ID_USER_FIRST,
  kCopyLink,
  kInspect,
};

NSString* ToNS(const CefString& s) {
  return [NSString stringWithUTF8String:s.ToString().c_str()] ?: @"";
}

bool DebugEvents() {
  static const bool enabled = getenv("MBGA_DEBUG_EVENTS") != nullptr;
  return enabled;
}

void BrowserGone() {
  --g_browser_count;
  if (DebugEvents() && g_quitting) {
    NSLog(@"browser closed, %d left", g_browser_count);
  }
  if (g_browser_count == 0 && g_quitting) {
    CefQuitMessageLoop();
  }
}

CefRefPtr<CefRequestContext> ContextForPath(const std::string& path) {
  auto it = g_contexts.find(path);
  if (it != g_contexts.end()) {
    return it->second;
  }
  CefRequestContextSettings settings;
  CefString(&settings.cache_path) = path;
  settings.persist_session_cookies = true;
  CefRefPtr<CefRequestContext> context =
      CefRequestContext::CreateContext(settings, nullptr);
  g_contexts[path] = context;
  return context;
}

NSString* UniqueDownloadPath(NSString* suggested) {
  NSString* dir = [NSSearchPathForDirectoriesInDomains(
      NSDownloadsDirectory, NSUserDomainMask, YES) firstObject]
      ?: NSTemporaryDirectory();
  NSString* name = suggested.length ? suggested.lastPathComponent : @"download";
  NSString* base = name.stringByDeletingPathExtension;
  NSString* ext = name.pathExtension;
  NSString* path = [dir stringByAppendingPathComponent:name];
  NSFileManager* fm = NSFileManager.defaultManager;
  for (int i = 1; [fm fileExistsAtPath:path]; i++) {
    NSString* candidate = [NSString stringWithFormat:@"%@ (%d)", base, i];
    if (ext.length) {
      candidate = [candidate stringByAppendingPathExtension:ext];
    }
    path = [dir stringByAppendingPathComponent:candidate];
  }
  return path;
}

void AskPermission(CefRefPtr<CefBrowser> browser,
                   const CefString& origin,
                   NSString* action,
                   void (^done)(BOOL allowed)) {
  NSString* host = [NSURL URLWithString:ToNS(origin)].host ?: ToNS(origin);
  MBPermissionPrompt* prompt = [[MBPermissionPrompt alloc]
      initWithMessage:[NSString stringWithFormat:@"%@ wants to %@", host, action]
                 done:done];
  NSView* browser_view =
      (__bridge NSView*)browser->GetHost()->GetWindowHandle();
  // Tabs ask only while on screen, like other browsers; popups and DevTools
  // windows ask right away.
  if ([browser_view.superview isKindOfClass:[MBWebView class]]) {
    [(MBWebView*)browser_view.superview engineAddPrompt:prompt];
  } else {
    [prompt showForView:browser_view];
  }
}

NSString* DescribeMedia(uint32_t permissions) {
  NSMutableArray* parts = [NSMutableArray array];
  if (permissions & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE) {
    [parts addObject:@"camera"];
  }
  if (permissions & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE) {
    [parts addObject:@"microphone"];
  }
  if (permissions & (CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE |
                     CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE)) {
    [parts addObject:@"screen"];
  }
  return [NSString stringWithFormat:@"use your %@",
                                    [parts componentsJoinedByString:@" and "]];
}

NSString* DescribePrompt(uint32_t permissions) {
  if (permissions & CEF_PERMISSION_TYPE_GEOLOCATION) {
    return @"know your location";
  }
  if (permissions & CEF_PERMISSION_TYPE_NOTIFICATIONS) {
    return @"show notifications";
  }
  if (permissions & (CEF_PERMISSION_TYPE_CAMERA_STREAM |
                     CEF_PERMISSION_TYPE_MIC_STREAM)) {
    return @"use your camera or microphone";
  }
  if (permissions & CEF_PERMISSION_TYPE_CLIPBOARD) {
    return @"see text and images copied to the clipboard";
  }
  return @"use additional permissions";
}

// Shortcuts the browser keeps even when a page would like to handle them.
bool IsReservedShortcut(NSEvent* event) {
  NSEventModifierFlags flags =
      event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask &
      (NSEventModifierFlagCommand | NSEventModifierFlagControl |
       NSEventModifierFlagOption | NSEventModifierFlagShift);
  NSString* key = event.charactersIgnoringModifiers.lowercaseString;
  if (key.length != 1) {
    return false;
  }
  unichar c = [key characterAtIndex:0];
  if (c > 0x7F && c < 0xF700) {
    // Non-Latin layouts (e.g. Cyrillic): match by physical key instead, as
    // the menu does.
    static const std::map<unsigned short, unichar> kAnsiKeys = {
        {17, 't'}, {13, 'w'}, {37, 'l'}, {12, 'q'}, {18, '1'}, {19, '2'},
        {20, '3'}, {21, '4'}, {23, '5'}, {22, '6'}, {26, '7'}, {28, '8'},
        {25, '9'}};
    auto it = kAnsiKeys.find(event.keyCode);
    if (it == kAnsiKeys.end()) {
      return false;
    }
    c = it->second;
  }
  if (flags == NSEventModifierFlagCommand) {
    return c == 't' || c == 'w' || c == 'l' || c == 'q' ||
           (c >= '1' && c <= '9');
  }
  if (flags == NSEventModifierFlagControl ||
      flags == (NSEventModifierFlagControl | NSEventModifierFlagShift)) {
    return c == '\t' || (c >= '1' && c <= '9');
  }
  if (flags == (NSEventModifierFlagCommand | NSEventModifierFlagOption)) {
    return c == NSUpArrowFunctionKey || c == NSDownArrowFunctionKey;
  }
  return false;
}

// Appends to a comma-separated switch such as --enable-features instead of
// replacing what is already there.
void AppendToListSwitch(CefRefPtr<CefCommandLine> command_line,
                        const std::string& name,
                        const std::string& items) {
  std::string value = command_line->GetSwitchValue(name);
  value += (value.empty() ? "" : ",") + items;
  command_line->AppendSwitchWithValue(name, value);
}

// MBGA_ENGINE_SWITCHES="--foo --bar=baz" adds engine switches, for
// measuring memory and performance options without rebuilding.
void AppendSwitchesFromEnvironment(CefRefPtr<CefCommandLine> command_line) {
  const char* env = getenv("MBGA_ENGINE_SWITCHES");
  if (!env) {
    return;
  }
  for (NSString* token in [@(env) componentsSeparatedByString:@" "]) {
    if (![token hasPrefix:@"--"]) {
      continue;
    }
    NSString* body = [token substringFromIndex:2];
    NSRange eq = [body rangeOfString:@"="];
    if (eq.location == NSNotFound) {
      command_line->AppendSwitch(body.UTF8String);
      continue;
    }
    std::string name = [body substringToIndex:eq.location].UTF8String;
    std::string value = [body substringFromIndex:eq.location + 1].UTF8String;
    if (name == "enable-features" || name == "disable-features") {
      AppendToListSwitch(command_line, name, value);
    } else if (name == "js-flags" && command_line->HasSwitch("js-flags")) {
      // Repeated --js-flags accumulate; V8 takes them space-separated.
      command_line->AppendSwitchWithValue(
          name, command_line->GetSwitchValue(name).ToString() + " " + value);
    } else {
      command_line->AppendSwitchWithValue(name, value);
    }
  }
}

class BrowserApp : public CefApp {
 public:
  void OnBeforeCommandLineProcessing(
      const CefString& process_type,
      CefRefPtr<CefCommandLine> command_line) override {
    if (!process_type.empty()) {
      return;
    }
    // Each switch below was measured with bench/trials.py on a 3-profile,
    // 50-tab workload; see bench/README.md for the numbers.

    // Process model. Tabs of the same site share one renderer.
    command_line->AppendSwitch("process-per-site");
    if (!g_strict_site_isolation) {
      // Chrome on Android's model: sites share four renderers, while
      // sign-in origins and sites that send COOP headers stay isolated.
      // Strict isolation used ~30% more memory with 50 tabs.
      AppendToListSwitch(command_line, "disable-features", "SitePerProcess");
      command_line->AppendSwitchWithValue("renderer-process-limit", "4");
      if (!g_isolated_origins.empty()) {
        command_line->AppendSwitchWithValue("isolate-origins",
                                            g_isolated_origins);
      }
    }

    // Renderers whose pages are all hidden release caches, collect garbage
    // and return free memory 30-60 s later. Freezing a tab (see the core's
    // freeze policy) does the same for its renderer even when that renderer
    // also hosts the visible tab.
    AppendToListSwitch(command_line, "enable-features",
                       "MemoryPurgeInBackground:"
                       "memory_purge_background_min_delay/30s/"
                       "memory_purge_background_max_delay/60s");
    AppendToListSwitch(command_line, "enable-features", "MemoryPurgeOnFreeze");
    // Cached scripts, stylesheets and fonts are dropped once no page uses
    // them instead of being pinned (they were ~190 MB across renderers), and
    // prerendered tiles outside the viewport are released when idle.
    AppendToListSwitch(command_line, "disable-features",
                       "MemoryCacheStrongReference");
    AppendToListSwitch(command_line, "enable-features",
                       "ReclaimPrepaintTilesWhenIdle,ReclaimOldPrepaintTiles");
    // The network service runs inside the browser process instead of its own
    // (its caches were ~140 MB in a separate process); same for audio. HTTP/3
    // (QUIC) is off: its per-connection buffers cost ~80 MB with 50 tabs, and
    // HTTP/2 over TCP is as fast on wired and Wi-Fi networks.
    AppendToListSwitch(command_line, "enable-features",
                       "NetworkServiceInProcess2");
    command_line->AppendSwitch("disable-quic");
    // No idle renderer kept warm for the next navigation, no speculative
    // prerendering, and no background fetching of optimization hints.
    AppendToListSwitch(command_line, "disable-features",
                       "SpareRendererForSitePerProcess,OptimizationHints,"
                       "AudioServiceOutOfProcess,Prerender2");
    // Smaller caches and heap budgets throughout Blink and V8.
    command_line->AppendSwitch("enable-low-end-device-mode");
    command_line->AppendSwitchWithValue("js-flags", "--optimize-for-size");

    AppendSwitchesFromEnvironment(command_line);

#if defined(MBGA_MOCK_KEYCHAIN)
    // Development builds are re-signed on every build, which would make the
    // real keychain prompt for the cookie encryption key at each launch.
    command_line->AppendSwitch("use-mock-keychain");
#endif
  }

 private:
  IMPLEMENT_REFCOUNTING(BrowserApp);
};

// Behaviour shared by tabs, popups and DevTools.
class BaseClient : public CefClient,
                   public CefDownloadHandler,
                   public CefPermissionHandler,
                   public CefKeyboardHandler {
 public:
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override {
    return this;
  }
  CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }

  bool OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefDownloadItem> download_item,
                        const CefString& suggested_name,
                        CefRefPtr<CefBeforeDownloadCallback> callback) override {
    callback->Continue(UniqueDownloadPath(ToNS(suggested_name)).UTF8String,
                       false);
    return true;
  }

  void OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                         CefRefPtr<CefDownloadItem> download_item,
                         CefRefPtr<CefDownloadItemCallback> callback) override {
    if (download_item->IsComplete()) {
      // Makes the Downloads stack in the Dock bounce, like other browsers.
      [NSDistributedNotificationCenter.defaultCenter
          postNotificationName:@"com.apple.DownloadFileFinished"
                        object:ToNS(download_item->GetFullPath())];
    }
  }

  bool OnRequestMediaAccessPermission(
      CefRefPtr<CefBrowser> browser,
      CefRefPtr<CefFrame> frame,
      const CefString& requesting_origin,
      uint32_t requested_permissions,
      CefRefPtr<CefMediaAccessCallback> callback) override {
    AskPermission(browser, requesting_origin,
                  DescribeMedia(requested_permissions), ^(BOOL allowed) {
                    callback->Continue(allowed ? requested_permissions
                                               : CEF_MEDIA_PERMISSION_NONE);
                  });
    return true;
  }

  bool OnShowPermissionPrompt(
      CefRefPtr<CefBrowser> browser,
      uint64_t prompt_id,
      const CefString& requesting_origin,
      uint32_t requested_permissions,
      CefRefPtr<CefPermissionPromptCallback> callback) override {
    AskPermission(browser, requesting_origin,
                  DescribePrompt(requested_permissions), ^(BOOL allowed) {
                    callback->Continue(allowed ? CEF_PERMISSION_RESULT_ACCEPT
                                               : CEF_PERMISSION_RESULT_DENY);
                  });
    return true;
  }

  bool OnPreKeyEvent(CefRefPtr<CefBrowser> browser,
                     const CefKeyEvent& event,
                     CefEventHandle os_event,
                     bool* is_keyboard_shortcut) override {
    if (event.type != KEYEVENT_RAWKEYDOWN || !os_event) {
      return false;
    }
    NSEvent* ns_event = (__bridge NSEvent*)os_event;
    return IsReservedShortcut(ns_event) &&
           [NSApp.mainMenu performKeyEquivalent:ns_event];
  }
};

// Popups (window.open with features, e.g. sign-in flows) and DevTools. They
// keep their opener, so they get real windows owned by CEF.
class AuxiliaryClient : public BaseClient, public CefLifeSpanHandler {
 public:
  static CefRefPtr<AuxiliaryClient> Get() {
    static CefRefPtr<AuxiliaryClient> instance(new AuxiliaryClient);
    return instance;
  }

  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }

  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     int popup_id,
                     const CefString& target_url,
                     const CefString& target_frame_name,
                     WindowOpenDisposition target_disposition,
                     bool user_gesture,
                     const CefPopupFeatures& popupFeatures,
                     CefWindowInfo& windowInfo,
                     CefRefPtr<CefClient>& client,
                     CefBrowserSettings& settings,
                     CefRefPtr<CefDictionaryValue>& extra_info,
                     bool* no_javascript_access) override {
    windowInfo.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
    return false;
  }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    g_browser_count++;
    g_auxiliary.push_back(browser);
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    std::erase_if(g_auxiliary, [&](const CefRefPtr<CefBrowser>& b) {
      return b->IsSame(browser);
    });
    BrowserGone();
  }

 private:
  IMPLEMENT_REFCOUNTING(AuxiliaryClient);
};

void ShowDevTools(CefRefPtr<CefBrowser> browser, const CefPoint& at) {
  CefWindowInfo info;
  info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  CefBrowserSettings settings;
  browser->GetHost()->ShowDevTools(info, AuxiliaryClient::Get(), settings, at);
}

// Downloads the page's icons in order of preference until one decodes.
class FaviconCallback : public CefDownloadImageCallback {
 public:
  FaviconCallback(MBWebView* view,
                  CefRefPtr<CefBrowser> browser,
                  std::vector<CefString> urls)
      : view_(view), browser_(browser), urls_(std::move(urls)) {}

  static void Start(MBWebView* view,
                    CefRefPtr<CefBrowser> browser,
                    const std::vector<CefString>& icon_urls) {
    // Bitmaps first: SVG icons often depend on media queries or fail to
    // decode, and pages usually list a bitmap as well.
    std::vector<CefString> urls(icon_urls);
    std::stable_partition(urls.begin(), urls.end(), [](const CefString& url) {
      return url.ToString().find(".svg") == std::string::npos;
    });
    std::reverse(urls.begin(), urls.end());
    CefRefPtr<FaviconCallback>(new FaviconCallback(view, browser, urls))
        ->Next();
  }

  void OnDownloadImageFinished(const CefString& image_url,
                               int http_status_code,
                               CefRefPtr<CefImage> image) override {
    MBWebView* view = view_;
    if (!view || view.closing) {
      return;
    }
    int width = 0;
    int height = 0;
    CefRefPtr<CefBinaryValue> png =
        image && !image->IsEmpty() ? image->GetAsPNG(2.0f, true, width, height)
                                   : nullptr;
    if (!png || png->GetSize() == 0) {
      Next();
      return;
    }
    NSMutableData* data = [NSMutableData dataWithLength:png->GetSize()];
    png->GetData(data.mutableBytes, data.length, 0);
    [view.delegate webView:view didReceiveFavicon:data];
  }

 private:
  // |urls_| is stored reversed so the next candidate is at the back.
  void Next() {
    if (urls_.empty()) {
      return;
    }
    CefString url = urls_.back();
    urls_.pop_back();
    browser_->GetHost()->DownloadImage(url, true, 32, false, this);
  }

  __weak MBWebView* view_;
  CefRefPtr<CefBrowser> browser_;
  std::vector<CefString> urls_;
  IMPLEMENT_REFCOUNTING(FaviconCallback);
};

class WebClient : public BaseClient,
                  public CefLifeSpanHandler,
                  public CefDisplayHandler,
                  public CefLoadHandler,
                  public CefRequestHandler,
                  public CefContextMenuHandler {
 public:
  explicit WebClient(MBWebView* view) : view_(view) {}

  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override {
    return this;
  }

  // CefLifeSpanHandler

  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     int popup_id,
                     const CefString& target_url,
                     const CefString& target_frame_name,
                     WindowOpenDisposition target_disposition,
                     bool user_gesture,
                     const CefPopupFeatures& popupFeatures,
                     CefWindowInfo& windowInfo,
                     CefRefPtr<CefClient>& client,
                     CefBrowserSettings& settings,
                     CefRefPtr<CefDictionaryValue>& extra_info,
                     bool* no_javascript_access) override {
    switch (target_disposition) {
      case CEF_WOD_NEW_FOREGROUND_TAB:
      case CEF_WOD_NEW_BACKGROUND_TAB:
      case CEF_WOD_NEW_WINDOW:
      case CEF_WOD_SINGLETON_TAB: {
        MBWebView* view = view_;
        [view.delegate webView:view
            requestsNewTabWithURL:ToNS(target_url)
                       foreground:target_disposition !=
                                  CEF_WOD_NEW_BACKGROUND_TAB];
        return true;
      }
      default:
        windowInfo.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
        client = AuxiliaryClient::Get();
        return false;
    }
  }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    [view_ engineDidCreateBrowser:browser];
  }

  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    // Returning false would make CEF close the whole window hosting the
    // browser. Tear down only this browser's view instead.
    [view_ engineWillCloseBrowser];
    return true;
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    [view_ engineDidCloseBrowser];
    BrowserGone();
  }

  // CefDisplayHandler

  void OnAddressChange(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       const CefString& url) override {
    if (frame->IsMain()) {
      MBWebView* view = view_;
      [view.delegate webView:view didChangeURL:ToNS(url)];
    }
  }

  void OnTitleChange(CefRefPtr<CefBrowser> browser,
                     const CefString& title) override {
    MBWebView* view = view_;
    [view.delegate webView:view didChangeTitle:ToNS(title)];
  }

  void OnFaviconURLChange(CefRefPtr<CefBrowser> browser,
                          const std::vector<CefString>& icon_urls) override {
    FaviconCallback::Start(view_, browser, icon_urls);
  }

  void OnFullscreenModeChange(CefRefPtr<CefBrowser> browser,
                              bool fullscreen) override {
    MBWebView* view = view_;
    [view.delegate webView:view didChangeFullscreen:fullscreen];
  }

  bool OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                        cef_log_severity_t level,
                        const CefString& message,
                        const CefString& source,
                        int line) override {
    std::string text = message.ToString();
    if (text.rfind(kMediaProbePrefix, 0) != 0) {
      return false;
    }
    [view_ engineSetMediaPlaying:text.back() == '1'];
    return true;
  }

  void OnMediaAccessChange(CefRefPtr<CefBrowser> browser,
                           bool has_video_access,
                           bool has_audio_access) override {
    [view_ engineSetCapturing:has_video_access || has_audio_access];
  }

  // CefLoadHandler

  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                            bool isLoading,
                            bool canGoBack,
                            bool canGoForward) override {
    MBWebView* view = view_;
    [view.delegate webView:view
          didChangeLoading:isLoading
                 canGoBack:canGoBack
              canGoForward:canGoForward];
  }

  // CefRequestHandler

  void OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser,
                                 TerminationStatus status,
                                 int error_code,
                                 const CefString& error_string) override {
    MBWebView* view = view_;
    [view.delegate webViewRendererDidTerminate:view];
  }

  // CefContextMenuHandler

  void OnBeforeContextMenu(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefFrame> frame,
                           CefRefPtr<CefContextMenuParams> params,
                           CefRefPtr<CefMenuModel> model) override {
    if (!params->GetLinkUrl().empty()) {
      model->InsertItemAt(0, kOpenLinkInNewTab, "Open Link in New Tab");
      model->InsertItemAt(1, kCopyLink, "Copy Link Address");
      model->InsertSeparatorAt(2);
    }
    if (model->GetCount() > 0) {
      model->AddSeparator();
    }
    model->AddItem(kInspect, "Inspect");
  }

  bool OnContextMenuCommand(CefRefPtr<CefBrowser> browser,
                            CefRefPtr<CefFrame> frame,
                            CefRefPtr<CefContextMenuParams> params,
                            int command_id,
                            EventFlags event_flags) override {
    MBWebView* view = view_;
    switch (command_id) {
      case kOpenLinkInNewTab:
        [view.delegate webView:view
            requestsNewTabWithURL:ToNS(params->GetLinkUrl())
                       foreground:NO];
        return true;
      case kCopyLink:
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard
            setString:ToNS(params->GetLinkUrl())
              forType:NSPasteboardTypeString];
        return true;
      case kInspect:
        ShowDevTools(browser,
                     CefPoint(params->GetXCoord(), params->GetYCoord()));
        return true;
      default:
        return false;
    }
  }

 private:
  __weak MBWebView* view_;
  IMPLEMENT_REFCOUNTING(WebClient);
};

}  // namespace

// ---------------------------------------------------------- MBPermissionPrompt

@implementation MBPermissionPrompt {
  NSString* _message;
  void (^_done)(BOOL);
  NSAlert* _alert;
  NSWindow* _window;
}

- (instancetype)initWithMessage:(NSString*)message
                           done:(void (^)(BOOL allowed))done {
  if ((self = [super init])) {
    _message = [message copy];
    _done = [done copy];
  }
  return self;
}

- (void)showForView:(NSView*)view {
  if (_answered || _shown) {
    return;
  }
  _shown = YES;
  if (DebugEvents()) {
    NSLog(@"permission prompt: %@", _message);
  }
  _alert = [[NSAlert alloc] init];
  _alert.messageText = _message;
  [_alert addButtonWithTitle:@"Allow"];
  [_alert addButtonWithTitle:@"Block"];
  _window = view.window ?: NSApp.keyWindow;
  if (!_window) {
    [self answer:[_alert runModal] == NSAlertFirstButtonReturn];
    return;
  }
  [_alert beginSheetModalForWindow:_window
                 completionHandler:^(NSModalResponse response) {
                   [self answer:response == NSAlertFirstButtonReturn];
                 }];
}

- (void)answer:(BOOL)allowed {
  if (_answered) {
    return;
  }
  _answered = YES;
  if (_alert && _window.attachedSheet == _alert.window) {
    // Re-enters -answer: through the completion handler, which is ignored.
    [_window endSheet:_alert.window returnCode:NSAlertSecondButtonReturn];
  }
  void (^done)(BOOL) = _done;
  _done = nil;
  if (done) {
    done(allowed);
  }
}

@end

// ---------------------------------------------------------------- MBApplication

@interface MBApplication () <CefAppProtocol>
@end

@implementation MBApplication {
  BOOL _handlingSendEvent;
}

- (BOOL)isHandlingSendEvent {
  return _handlingSendEvent;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
  _handlingSendEvent = handlingSendEvent;
}

- (void)sendEvent:(NSEvent*)event {
  static const bool debug_events = getenv("MBGA_DEBUG_EVENTS") != nullptr;
  if (debug_events && (event.type == NSEventTypeKeyDown)) {
    NSLog(@"key %@ flags=%lx window=%@ firstResponder=%@", event.characters,
          (unsigned long)event.modifierFlags, event.window.title,
          NSStringFromClass([event.window.firstResponder class]));
  }
  // Permission prompts are sheets, and a sheet with keyboard focus swallows
  // Cmd+Q. Quit anyway; quitting answers open prompts with Block.
  NSEventModifierFlags modifiers =
      event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
  NSWindow* sheet_parent = NSApp.keyWindow.sheetParent;
  if (event.type == NSEventTypeKeyDown && event.keyCode == 12 /* Q */ &&
      (modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagControl |
                    NSEventModifierFlagOption)) == NSEventModifierFlagCommand &&
      sheet_parent) {
    if (DebugEvents()) {
      NSLog(@"Cmd+Q over a sheet: closing it, then quitting");
    }
    [sheet_parent endSheet:NSApp.keyWindow returnCode:NSAlertSecondButtonReturn];
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp terminate:nil];
    });
    return;
  }
  CefScopedSendingEvent sendingEventScoper;
  [super sendEvent:event];
}

@end

// --------------------------------------------------------------------- MBEngine

@implementation MBEngine

+ (BOOL)startWithArgc:(int)argc
                    argv:(char**)argv
           rootCachePath:(NSString*)rootCachePath
     strictSiteIsolation:(BOOL)strictSiteIsolation
         isolatedOrigins:(NSArray<NSString*>*)isolatedOrigins {
  g_strict_site_isolation = strictSiteIsolation;
  g_isolated_origins = [isolatedOrigins componentsJoinedByString:@","].UTF8String;
  g_library_loader = new CefScopedLibraryLoader();
  if (!g_library_loader->LoadInMain()) {
    return NO;
  }
  g_views = [NSMutableSet set];

  CefMainArgs main_args(argc, argv);
  CefSettings settings;
#if !defined(CEF_USE_SANDBOX)
  settings.no_sandbox = true;
#endif
  CefString(&settings.root_cache_path) = rootCachePath.UTF8String;
  CefString(&settings.log_file) =
      [rootCachePath stringByAppendingPathComponent:@"engine.log"].UTF8String;
  settings.log_severity = LOGSEVERITY_WARNING;
  settings.persist_session_cookies = true;
  settings.background_color = 0xFFFFFFFF;

  CefRefPtr<BrowserApp> app(new BrowserApp);
  return CefInitialize(main_args, settings, app.get(), nullptr);
}

+ (void)runMessageLoop {
  CefRunMessageLoop();
}

+ (void)closeAllAndQuit {
  if (g_quitting) {
    return;
  }
  g_quitting = true;
  // An open permission prompt would hold up shutdown; answer it with Block.
  for (NSWindow* window in NSApp.windows) {
    if (window.attachedSheet) {
      [window endSheet:window.attachedSheet
            returnCode:NSAlertSecondButtonReturn];
    }
  }
  if (DebugEvents()) {
    NSLog(@"quitting: %d browsers, %lu tab views, %zu auxiliary",
          g_browser_count, (unsigned long)g_views.count, g_auxiliary.size());
    for (MBWebView* view in g_views) {
      NSLog(@"  tab %llu closing=%d", view.tabID, view.closing);
    }
  }
  for (MBWebView* view in g_views.allObjects) {
    [view close];
  }
  for (const CefRefPtr<CefBrowser>& browser :
       std::vector<CefRefPtr<CefBrowser>>(g_auxiliary)) {
    browser->GetHost()->CloseBrowser(true);
  }
  if (g_browser_count == 0) {
    CefQuitMessageLoop();
  }
}

+ (void)shutdown {
  g_contexts.clear();
  CefShutdown();
  delete g_library_loader;
  g_library_loader = nullptr;
}

@end

// -------------------------------------------------------------------- MBWebView

@implementation MBWebView {
  CefRefPtr<WebClient> _client;
  CefRefPtr<CefBrowser> _browser;
  NSString* _pendingURL;
  BOOL _mediaPlaying;
  BOOL _capturing;
  BOOL _frozen;
  NSMutableArray<MBPermissionPrompt*>* _prompts;
}

- (instancetype)initWithURL:(NSString*)url
                profilePath:(NSString*)profilePath
                      tabID:(uint64_t)tabID {
  self = [super initWithFrame:NSMakeRect(0, 0, 800, 600)];
  if (!self) {
    return nil;
  }
  _tabID = tabID;
  self.wantsLayer = YES;
  _client = new WebClient(self);

  CefWindowInfo info;
  info.SetAsChild((__bridge CefWindowHandle)self, CefRect(0, 0, 800, 600));
  info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  CefBrowserSettings settings;
  settings.background_color = 0xFFFFFFFF;

  [g_views addObject:self];
  g_browser_count++;
  if (!CefBrowserHost::CreateBrowser(info, _client, url.UTF8String, settings,
                                     nullptr,
                                     ContextForPath(profilePath.UTF8String))) {
    _closing = YES;
    [g_views removeObject:self];
    BrowserGone();
  }
  return self;
}

- (BOOL)isFlipped {
  return YES;
}

- (void)engineAddPrompt:(MBPermissionPrompt*)prompt {
  if (_closing) {
    [prompt answer:NO];
    return;
  }
  if (!_prompts) {
    _prompts = [NSMutableArray array];
  }
  [_prompts addObject:prompt];
  if (!self.isHiddenOrHasHiddenAncestor) {
    [prompt showForView:self];
  }
}

- (void)viewDidUnhide {
  [super viewDidUnhide];
  [_prompts filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(
                                     MBPermissionPrompt* prompt, id bindings) {
              return !prompt.answered;
            }]];
  for (MBPermissionPrompt* prompt in [_prompts copy]) {
    [prompt showForView:self];
  }
}

- (void)didAddSubview:(NSView*)subview {
  [super didAddSubview:subview];
  subview.frame = self.bounds;
  subview.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

- (void)loadURL:(NSString*)url {
  if (_browser) {
    _browser->GetMainFrame()->LoadURL(url.UTF8String);
  } else {
    _pendingURL = [url copy];
  }
}

- (void)goBack {
  if (_browser) {
    _browser->GoBack();
  }
}

- (void)goForward {
  if (_browser) {
    _browser->GoForward();
  }
}

- (void)reload {
  if (_browser) {
    _browser->Reload();
  }
}

- (void)stopLoading {
  if (_browser) {
    _browser->StopLoad();
  }
}

- (void)zoomIn {
  if (_browser) {
    _browser->GetHost()->Zoom(CEF_ZOOM_COMMAND_IN);
  }
}

- (void)zoomOut {
  if (_browser) {
    _browser->GetHost()->Zoom(CEF_ZOOM_COMMAND_OUT);
  }
}

- (void)resetZoom {
  if (_browser) {
    _browser->GetHost()->Zoom(CEF_ZOOM_COMMAND_RESET);
  }
}

- (void)showDevTools {
  if (_browser) {
    ShowDevTools(_browser, CefPoint());
  }
}

- (void)focusContent {
  if (_browser) {
    _browser->GetHost()->SetFocus(true);
  }
}

- (void)probeMedia {
  if (_browser && !_capturing) {
    _browser->GetMainFrame()->ExecuteJavaScript(kMediaProbeScript, "", 0);
  }
}

- (void)setFrozen:(BOOL)frozen {
  if (!_browser || _frozen == frozen) {
    return;
  }
  _frozen = frozen;
  CefRefPtr<CefDictionaryValue> params = CefDictionaryValue::Create();
  params->SetString("state", frozen ? "frozen" : "active");
  _browser->GetHost()->ExecuteDevToolsMethod(0, "Page.setWebLifecycleState",
                                             params);
}

- (void)close {
  if (_closing) {
    return;
  }
  if (DebugEvents()) {
    NSLog(@"tab %llu: close requested (frozen=%d, browser=%d)", _tabID, _frozen,
          _browser != nullptr);
  }
  for (MBPermissionPrompt* prompt in _prompts) {
    [prompt answer:NO];
  }
  _prompts = nil;
  if (_frozen) {
    // A frozen page never acknowledges the close, which would leave the
    // browser half-closed (and quitting waiting for it) forever.
    [self setFrozen:NO];
  }
  _closing = YES;
  if (_browser) {
    _browser->GetHost()->CloseBrowser(true);
    [self scheduleCloseFallback];
  }
  // Otherwise the browser is closed as soon as it has been created.
}

// A page that does not answer the close request (frozen, hung) would never
// finish closing. Tearing down the engine's view destroys the browser
// regardless, the same way the normal close path does.
- (void)scheduleCloseFallback {
  __weak MBWebView* weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                 dispatch_get_main_queue(), ^{
                   MBWebView* view = weakSelf;
                   if (view && view->_browser) {
                     if (DebugEvents()) {
                       NSLog(@"tab %llu: close fallback, %lu engine views",
                             view.tabID, (unsigned long)view.subviews.count);
                     }
                     [view engineWillCloseBrowser];
                   }
                 });
}

// Engine callbacks.

- (void)engineDidCreateBrowser:(CefRefPtr<CefBrowser>)browser {
  _browser = browser;
  if (_closing) {
    _browser->GetHost()->CloseBrowser(true);
    [self scheduleCloseFallback];
  } else if (_pendingURL) {
    _browser->GetMainFrame()->LoadURL(_pendingURL.UTF8String);
    _pendingURL = nil;
  }
}

- (void)engineWillCloseBrowser {
  if (DebugEvents()) {
    NSLog(@"tab %llu: DoClose / teardown", _tabID);
  }
  _closing = YES;
  // Removing the engine's view destroys the browser (see DoClose).
  dispatch_async(dispatch_get_main_queue(), ^{
    for (NSView* subview in [self.subviews copy]) {
      [subview removeFromSuperview];
    }
  });
}

- (void)engineDidCloseBrowser {
  if (DebugEvents()) {
    NSLog(@"tab %llu: closed", _tabID);
  }
  _browser = nullptr;
  [self.delegate webViewDidClose:self];
  [g_views removeObject:self];
}

- (void)engineSetMediaPlaying:(BOOL)playing {
  BOOL wasBusy = _mediaPlaying || _capturing;
  _mediaPlaying = playing;
  if (wasBusy != (_mediaPlaying || _capturing)) {
    [self.delegate webView:self didChangeBusy:!wasBusy];
  }
}

- (void)engineSetCapturing:(BOOL)capturing {
  BOOL wasBusy = _mediaPlaying || _capturing;
  _capturing = capturing;
  if (wasBusy != (_mediaPlaying || _capturing)) {
    [self.delegate webView:self didChangeBusy:!wasBusy];
  }
}

@end
