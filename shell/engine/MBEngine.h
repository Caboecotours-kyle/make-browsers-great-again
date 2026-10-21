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
/// CSS to inject into |page| when it starts loading, or an empty string.
typedef NSString* _Nonnull (^MBHidingCSS)(NSString* page);

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

/// Turns on ad blocking. Call before the first web view is created.
+ (void)setRequestFilter:(MBRequestFilter)filter hidingCSS:(MBHidingCSS)css;

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
- (void)showDevTools;
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
