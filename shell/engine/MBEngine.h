// Objective-C face of the Chromium (CEF) engine. Pure Objective-C so Swift can
// import it through the bridging header; all C++ stays in the .mm files.

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// NSApplication subclass required by CEF's message loop on macOS.
@interface MBApplication : NSApplication
@end

@class MBWebView;

/// Decides whether to cancel a request for |url| made while |page| is the
/// tab's top-level page; |kind| is the filter-list request type ("script",
/// "image", "subdocument", ...). Called on the network thread.
typedef BOOL (^MBRequestFilter)(NSString* url, NSString* page, NSString* kind);
/// JavaScript to run in |page| as it starts loading, or an empty string.
typedef NSString* _Nonnull (^MBPageScript)(NSString* page);
/// JavaScript to run in |page| in reply to a report its page script sent,
/// or an empty string.
typedef NSString* _Nonnull (^MBPageReply)(NSString* page, NSString* report);
/// Whether |page| has scripts that must run before its own (scriptlets). A
/// new tab only waits for its page script before loading such pages.
typedef BOOL (^MBEarlyScript)(NSString* page);

/// Engine events for one tab. Always delivered on the main thread.
@protocol MBWebViewDelegate <NSObject>
- (void)webView:(MBWebView*)view didChangeURL:(NSString*)url;
- (void)webView:(MBWebView*)view didChangeTitle:(NSString*)title;
- (void)webView:(MBWebView*)view
    didChangeLoading:(BOOL)loading
           canGoBack:(BOOL)canGoBack
        canGoForward:(BOOL)canGoForward;
- (void)webView:(MBWebView*)view didReceiveFavicon:(NSData*)png;
/// Media elements playing with sound (answer to -probeMedia) or camera,
/// microphone or screen capture in use.
- (void)webView:(MBWebView*)view didChangeBusy:(BOOL)busy;
- (void)webView:(MBWebView*)view
    requestsNewTabWithURL:(NSString*)url
               foreground:(BOOL)foreground;
- (void)webView:(MBWebView*)view didChangeFullscreen:(BOOL)fullscreen;
- (void)webViewRendererDidTerminate:(MBWebView*)view;
/// The page's theme-color as "#rrggbb" or "rgba(r, g, b, a)", or an empty
/// string when it has none. Reported when a page finishes loading.
- (void)webView:(MBWebView*)view didChangeThemeColor:(NSString*)color;
/// Requests blocked since the page started loading.
- (void)webView:(MBWebView*)view didChangeBlockedCount:(NSUInteger)count;
/// The engine finished destroying the browser after -close.
- (void)webViewDidClose:(MBWebView*)view;
/// Console errors and warnings since the page started loading.
- (void)webView:(MBWebView*)view
    didChangeConsoleErrors:(NSUInteger)errors
                  warnings:(NSUInteger)warnings;
/// The page finished loading with an HTTP |status| (0 for none, or a
/// negative network error code when it failed) |duration| seconds after
/// navigation started.
- (void)webView:(MBWebView*)view
    didFinishLoadWithStatus:(int)status
                   duration:(NSTimeInterval)duration;
/// Picking an element ended: one was picked (and DevTools opened on it) or
/// the person pressed Escape.
- (void)webViewDidStopPicking:(MBWebView*)view;
/// DevTools opened or closed: -devToolsWindow appeared or went away.
- (void)webViewDidChangeDevTools:(MBWebView*)view;
/// A console message from the page (level 0 debug, 1 info, 2 warning,
/// 3 error).
- (void)webView:(MBWebView*)view
    didLogConsoleMessage:(NSString*)message
                   level:(NSInteger)level
                  source:(NSString*)source
                    line:(int)line;
/// A Network.* DevTools event while -recordsNetwork is on.
- (void)webView:(MBWebView*)view
    didObserveNetworkEvent:(NSString*)method
                    params:(NSDictionary*)params;
/// Any DevTools event of the page while -forwardsDevToolsEvents is on.
- (void)webView:(MBWebView*)view
    didReceiveDevToolsEvent:(NSString*)method
                     params:(NSDictionary*)params;
/// The element picked while -picksForInspector is on.
- (void)webView:(MBWebView*)view didPickNode:(NSInteger)backendNodeId;
@end

/// A cookie to set, e.g. one imported from another browser. Times are
/// microseconds since 1601; an |expires| of 0 is a session cookie.
@interface MBCookie : NSObject
/// ".example.com" covers its subdomains; "example.com" is that host alone.
@property(nonatomic, copy) NSString* domain;
@property(nonatomic, copy) NSString* name;
@property(nonatomic, copy) NSString* value;
@property(nonatomic, copy) NSString* path;
@property(nonatomic) BOOL secure;
@property(nonatomic) BOOL httpOnly;
@property(nonatomic) int64_t expires;
@property(nonatomic) int64_t created;
@property(nonatomic) int64_t lastUsed;
/// -1 unspecified, 0 none, 1 lax, 2 strict.
@property(nonatomic) int sameSite;
/// 0 low, 1 medium, 2 high.
@property(nonatomic) int priority;
@end

@interface MBEngine : NSObject

/// Loads the framework and initializes the engine. Call once, after creating
/// MBApplication.sharedApplication and before anything else in this file.
/// Without strict site isolation, sites share a few renderer processes and
/// only |isolatedOrigins| (and sites that request it) get their own.
+ (BOOL)startWithArgc:(int)argc
                    argv:(char* _Nullable* _Nonnull)argv
           rootCachePath:(NSString*)rootCachePath
     strictSiteIsolation:(BOOL)strictSiteIsolation
         isolatedOrigins:(NSArray<NSString*>*)isolatedOrigins;

/// Runs the native event loop until -closeAllAndQuit completes.
+ (void)runMessageLoop;

/// Closes every browser, then stops the message loop.
+ (void)closeAllAndQuit;

/// Tears the engine down after the message loop returned.
+ (void)shutdown;

/// Makes pages refuse dropped items, or accept them again.
+ (void)setRejectsDrops:(BOOL)reject;

/// Adds |cookies| to the profile at |profilePath|, leaving any it already
/// has with the same name, domain and path. |completion| runs on the main
/// thread with how many were added, kept and refused.
+ (void)importCookies:(NSArray<MBCookie*>*)cookies
      intoProfilePath:(NSString*)profilePath
           completion:(void (^)(NSInteger added, NSInteger kept,
                                NSInteger refused))completion
    NS_SWIFT_NAME(importCookies(_:intoProfilePath:completion:));

/// Turns on ad blocking. Call before the first web view is created.
+ (void)setRequestFilter:(MBRequestFilter)filter
               pageScript:(MBPageScript)script
                pageReply:(MBPageReply)reply
              earlyScript:(MBEarlyScript)early;

@end

/// One browser (tab). Creating it starts a page load; -close destroys it and
/// frees its renderer. Each profile path gets an isolated storage partition.
@interface MBWebView : NSView

- (instancetype)initWithURL:(NSString*)url
                profilePath:(NSString*)profilePath
                      tabID:(uint64_t)tabID NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder*)coder NS_UNAVAILABLE;

@property(nonatomic, readonly) uint64_t tabID;
@property(nonatomic, weak, nullable) id<MBWebViewDelegate> delegate;
@property(nonatomic, readonly, getter=isClosing) BOOL closing;

- (void)loadURL:(NSString*)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stopLoading;
- (void)zoomIn;
- (void)zoomOut;
- (void)resetZoom;
/// Opens DevTools in a window of its own (CEF can't embed it in a view of
/// an Alloy-style browser), or brings it forward.
- (void)showDevTools;
- (void)closeDevTools;
/// The DevTools window while open, for the shell to dock beside the page.
@property(nonatomic, readonly, nullable) NSWindow* devToolsWindow;

// Developer tools. Emulations last until changed or the tab closes.

/// Reloads bypassing the cache.
- (void)reloadIgnoringCache;
/// Highlights elements under the pointer until one is clicked, then opens
/// DevTools on it. NO cancels.
- (void)setPicking:(BOOL)picking;
/// Emulates a CSS media feature, e.g. "prefers-color-scheme" = "dark"; an
/// empty value stops emulating it.
- (void)emulateMediaFeature:(NSString*)name value:(NSString*)value;
/// Makes the page think it runs on a phone or tablet (mobile viewport, touch
/// and |userAgent|) at the view's size, or stops when |userAgent| is nil.
- (void)emulateMobileWithUserAgent:(nullable NSString*)userAgent;
- (void)setCacheDisabled:(BOOL)disabled;
- (void)setScriptsDisabled:(BOOL)disabled;
/// Slows the network to |latency| ms and |throughput| bytes per second each
/// way; a negative throughput is offline, zero latency and throughput off.
- (void)emulateNetworkWithLatency:(double)latency throughput:(double)throughput;
/// Deletes the cookies, storage and caches of the page's origin, then
/// reloads it.
- (void)clearSiteDataAndReload;
/// The whole page, not just what fits the view, as PNG; nil on failure.
- (void)captureFullPage:(void (^)(NSData* _Nullable png))completion;

/// Sends a DevTools protocol command with |params| (a JSON object, or nil);
/// |completion| gets the result as JSON, or nil and the error.
- (void)sendDevToolsCommand:(NSString*)method
                     params:(nullable NSString*)params
                 completion:(void (^)(NSString* _Nullable result,
                                      NSString* _Nullable error))completion;
/// The same, sent to a DevTools |session| (a cross-site frame's, from
/// -frameSessions), or the page's own when nil.
- (void)sendDevToolsCommand:(NSString*)method
                     params:(nullable NSString*)params
                    session:(nullable NSString*)session
                 completion:(void (^)(NSString* _Nullable result,
                                      NSString* _Nullable error))completion;
/// Starts following cross-site frames, which run in processes of their
/// own: each gets a DevTools session in -frameSessions.
- (void)attachToFrames;
/// Cross-site frames DevTools can reach: frame id → session id.
@property(nonatomic, readonly) NSDictionary<NSString*, NSString*>* frameSessions;
/// Reports the page's network requests through the delegate.
@property(nonatomic) BOOL recordsNetwork;
/// Sends every DevTools event of the page to the delegate, for the
/// shell's own developer tools; the Network domain stays on meanwhile.
@property(nonatomic) BOOL forwardsDevToolsEvents;
/// Picking an element reports it to the delegate rather than opening
/// DevTools, and leaves the DOM and Overlay domains on.
@property(nonatomic) BOOL picksForInspector;
/// Gives keyboard focus to the page.
- (void)focusContent;
/// Asks the page whether it is playing audible media. The answer arrives via
/// -webView:didChangeBusy: when it changes.
- (void)probeMedia;
/// Pauses the media the page is playing, or resumes what was paused.
- (void)setMediaPaused:(BOOL)paused;
/// Suspends the page (no JavaScript, timers or rendering) while keeping all
/// of its state, or resumes it.
- (void)setFrozen:(BOOL)frozen;
/// Destroys the browser. -webViewDidClose: follows.
- (void)close;

@end

NS_ASSUME_NONNULL_END
