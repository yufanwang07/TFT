#import <AppKit/AppKit.h>

@interface GameSnapshot : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *subtitle;
@property(nonatomic, copy, nullable) NSString *detail;
@property(nonatomic, copy, nullable) NSString *stageHint;
+ (instancetype)idle;
+ (instancetype)snapshotWithPhase:(nullable NSString *)phase gameTime:(nullable NSNumber *)gameTime;
@end

@implementation GameSnapshot
+ (instancetype)idle {
    GameSnapshot *snapshot = [GameSnapshot new];
    snapshot.title = @"Waiting for TFT";
    snapshot.subtitle = @"Open League/TFT to connect to local game state.";
    snapshot.detail = nil;
    snapshot.stageHint = nil;
    return snapshot;
}

+ (instancetype)snapshotWithPhase:(NSString *)phase gameTime:(NSNumber *)gameTime {
    GameSnapshot *snapshot = [GameSnapshot new];
    snapshot.title = @"TFT Overlay Connected";

    NSString *phaseText = phase.length > 0 ? phase : @"Unknown phase";
    NSString *timeText = @"No live timer yet";
    if (gameTime != nil) {
        NSInteger total = MAX(0, (NSInteger)llround(gameTime.doubleValue));
        timeText = [NSString stringWithFormat:@"%02ld:%02ld", total / 60, total % 60];
    }
    snapshot.subtitle = [NSString stringWithFormat:@"Phase: %@  |  Game time: %@", phaseText, timeText];
    snapshot.detail = @"Collection logging is writing a local NDJSON run file.";

    snapshot.stageHint = nil;
    if (gameTime != nil) {
        double seconds = gameTime.doubleValue;
        if (seconds >= 85 && seconds <= 115) {
            snapshot.stageHint = @"Likely augment window: show opening augment notes";
        } else if (seconds >= 520 && seconds <= 560) {
            snapshot.stageHint = @"Likely augment window: show mid-game options";
        } else if (seconds >= 900 && seconds <= 940) {
            snapshot.stageHint = @"Likely augment window: show late-game options";
        }
    }
    return snapshot;
}
@end

@interface OverlayView : NSView
@property(nonatomic, strong) GameSnapshot *snapshot;
@end

@implementation OverlayView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _snapshot = [GameSnapshot idle];
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
    }
    return self;
}

- (BOOL)isOpaque {
    return NO;
}

- (void)setSnapshot:(GameSnapshot *)snapshot {
    _snapshot = snapshot;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [self drawStatusPanel];
    [self drawStageHint];
}

- (void)drawStatusPanel {
    NSRect bounds = self.bounds;
    NSRect panel = NSMakeRect(NSMinX(bounds) + 24, NSMaxY(bounds) - 152, 380, 112);
    [self drawPanel:panel fill:[NSColor colorWithWhite:0 alpha:0.42]];
    [self drawText:self.snapshot.title in:NSInsetRect(panel, 16, 14) size:18 weight:NSFontWeightSemibold color:NSColor.whiteColor alignment:NSTextAlignmentLeft];
    [self drawText:self.snapshot.subtitle in:NSInsetRect(panel, 16, 44) size:13 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor alignment:NSTextAlignmentLeft];
    if (self.snapshot.detail.length > 0) {
        [self drawText:self.snapshot.detail in:NSInsetRect(panel, 16, 70) size:12 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor alignment:NSTextAlignmentLeft];
    }
}

- (void)drawStageHint {
    if (self.snapshot.stageHint.length == 0) {
        return;
    }

    NSRect bounds = self.bounds;
    NSRect panel = NSMakeRect(NSMidX(bounds) - 220, NSMinY(bounds) + 72, 440, 76);
    [self drawPanel:panel fill:[NSColor colorWithWhite:0 alpha:0.58]];
    [self drawText:self.snapshot.stageHint in:NSInsetRect(panel, 18, 18) size:20 weight:NSFontWeightBold color:NSColor.whiteColor alignment:NSTextAlignmentCenter];
}

- (void)drawPanel:(NSRect)rect fill:(NSColor *)fill {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:8 yRadius:8];
    [fill setFill];
    [path fill];

    [[NSColor colorWithWhite:1 alpha:0.14] setStroke];
    path.lineWidth = 1;
    [path stroke];
}

- (void)drawText:(NSString *)text in:(NSRect)rect size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color alignment:(NSTextAlignment)alignment {
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = alignment;
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;

    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:size weight:weight],
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: paragraph
    };
    [text drawInRect:rect withAttributes:attributes];
}
@end

@interface SettingsWindowController : NSWindowController
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSTextField *logPathLabel;
@property(nonatomic, strong) NSButton *overlayCheckbox;
@property(nonatomic, strong) NSStepper *intervalStepper;
@property(nonatomic, strong) NSTextField *intervalLabel;
@property(nonatomic) NSTimeInterval pollingInterval;
@property(nonatomic, copy) void (^overlayVisibilityChanged)(BOOL visible);
@property(nonatomic, copy) void (^pollingIntervalChanged)(NSTimeInterval interval);
@property(nonatomic, copy) void (^openLogsRequested)(void);
@property(nonatomic, copy) void (^quitRequested)(void);
- (instancetype)initWithLogURL:(NSURL *)logURL pollingInterval:(NSTimeInterval)pollingInterval;
- (void)updateSnapshot:(GameSnapshot *)snapshot overlayVisible:(BOOL)overlayVisible;
@end

@implementation SettingsWindowController
- (instancetype)initWithLogURL:(NSURL *)logURL pollingInterval:(NSTimeInterval)pollingInterval {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 320)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"TFT Overlay";
    window.releasedWhenClosed = NO;
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        _pollingInterval = pollingInterval;
        [self buildContentWithLogURL:logURL];
    }
    return self;
}

- (void)buildContentWithLogURL:(NSURL *)logURL {
    NSView *content = self.window.contentView;

    NSTextField *title = [self labelWithText:@"TFT Overlay" frame:NSMakeRect(24, 268, 280, 26) font:[NSFont systemFontOfSize:22 weight:NSFontWeightSemibold]];
    [content addSubview:title];

    self.statusLabel = [self labelWithText:@"Waiting for TFT" frame:NSMakeRect(24, 234, 460, 22) font:[NSFont systemFontOfSize:14 weight:NSFontWeightRegular]];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    [content addSubview:self.statusLabel];

    self.overlayCheckbox = [NSButton checkboxWithTitle:@"Show click-through overlay" target:self action:@selector(overlayCheckboxChanged:)];
    self.overlayCheckbox.frame = NSMakeRect(24, 196, 240, 24);
    self.overlayCheckbox.state = NSControlStateValueOn;
    [content addSubview:self.overlayCheckbox];

    NSTextField *intervalTitle = [self labelWithText:@"Polling interval" frame:NSMakeRect(24, 158, 150, 22) font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]];
    [content addSubview:intervalTitle];

    self.intervalLabel = [self labelWithText:[self intervalText] frame:NSMakeRect(168, 158, 80, 22) font:[NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular]];
    self.intervalLabel.alignment = NSTextAlignmentRight;
    [content addSubview:self.intervalLabel];

    self.intervalStepper = [[NSStepper alloc] initWithFrame:NSMakeRect(258, 153, 24, 28)];
    self.intervalStepper.minValue = 0.5;
    self.intervalStepper.maxValue = 10.0;
    self.intervalStepper.increment = 0.5;
    self.intervalStepper.doubleValue = self.pollingInterval;
    self.intervalStepper.target = self;
    self.intervalStepper.action = @selector(intervalChanged:);
    [content addSubview:self.intervalStepper];

    NSTextField *logTitle = [self labelWithText:@"Current collection file" frame:NSMakeRect(24, 116, 220, 20) font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]];
    [content addSubview:logTitle];

    self.logPathLabel = [self labelWithText:logURL.path frame:NSMakeRect(24, 88, 470, 20) font:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular]];
    self.logPathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.logPathLabel.textColor = NSColor.secondaryLabelColor;
    [content addSubview:self.logPathLabel];

    NSButton *openLogs = [NSButton buttonWithTitle:@"Open Logs" target:self action:@selector(openLogs:)];
    openLogs.frame = NSMakeRect(24, 34, 110, 32);
    [content addSubview:openLogs];

    NSButton *showOverlay = [NSButton buttonWithTitle:@"Show Overlay" target:self action:@selector(showOverlay:)];
    showOverlay.frame = NSMakeRect(146, 34, 120, 32);
    [content addSubview:showOverlay];

    NSButton *quit = [NSButton buttonWithTitle:@"Quit" target:self action:@selector(quit:)];
    quit.frame = NSMakeRect(386, 34, 110, 32);
    [content addSubview:quit];
}

- (NSTextField *)labelWithText:(NSString *)text frame:(NSRect)frame font:(NSFont *)font {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text ?: @"";
    label.font = font;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    return label;
}

- (NSString *)intervalText {
    return [NSString stringWithFormat:@"%.1fs", self.pollingInterval];
}

- (void)updateSnapshot:(GameSnapshot *)snapshot overlayVisible:(BOOL)overlayVisible {
    self.statusLabel.stringValue = snapshot.subtitle ?: snapshot.title ?: @"";
    self.overlayCheckbox.state = overlayVisible ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)overlayCheckboxChanged:(id)sender {
    if (self.overlayVisibilityChanged != nil) {
        self.overlayVisibilityChanged(self.overlayCheckbox.state == NSControlStateValueOn);
    }
}

- (void)intervalChanged:(id)sender {
    self.pollingInterval = self.intervalStepper.doubleValue;
    self.intervalLabel.stringValue = [self intervalText];
    if (self.pollingIntervalChanged != nil) {
        self.pollingIntervalChanged(self.pollingInterval);
    }
}

- (void)openLogs:(id)sender {
    if (self.openLogsRequested != nil) {
        self.openLogsRequested();
    }
}

- (void)showOverlay:(id)sender {
    self.overlayCheckbox.state = NSControlStateValueOn;
    [self overlayCheckboxChanged:sender];
}

- (void)quit:(id)sender {
    if (self.quitRequested != nil) {
        self.quitRequested();
    }
}
@end

@interface OverlayWindow : NSPanel
@end

@implementation OverlayWindow
- (instancetype)initWithContentView:(NSView *)contentView {
    NSScreen *screen = NSScreen.mainScreen;
    NSRect frame = screen != nil ? screen.frame : NSMakeRect(0, 0, 1440, 900);
    self = [super initWithContentRect:frame
                            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        self.contentView = contentView;
        self.opaque = NO;
        self.backgroundColor = NSColor.clearColor;
        self.hasShadow = NO;
        self.ignoresMouseEvents = YES;
        self.level = NSScreenSaverWindowLevel;
        self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorFullScreenAuxiliary |
            NSWindowCollectionBehaviorStationary |
            NSWindowCollectionBehaviorIgnoresCycle;
    }
    return self;
}

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (BOOL)canBecomeMainWindow {
    return NO;
}
@end

@interface LocalHTTPResult : NSObject
@property(nonatomic) NSInteger statusCode;
@property(nonatomic, strong, nullable) NSData *data;
@property(nonatomic, copy, nullable) NSString *errorDescription;
@property(nonatomic, copy) NSString *bodyString;
@end

@implementation LocalHTTPResult
- (NSString *)bodyString {
    if (_bodyString != nil) {
        return _bodyString;
    }
    if (self.data.length == 0) {
        return @"";
    }
    NSString *body = [[NSString alloc] initWithData:self.data encoding:NSUTF8StringEncoding];
    return body != nil ? body : @"";
}
@end

static NSDictionary *HTTPResultDictionary(LocalHTTPResult *result) {
    if (result == nil) {
        return @{
            @"attempted": @NO,
            @"statusCode": [NSNull null],
            @"error": [NSNull null],
            @"body": @""
        };
    }

    return @{
        @"attempted": @YES,
        @"statusCode": @(result.statusCode),
        @"error": result.errorDescription ?: [NSNull null],
        @"body": result.bodyString ?: @""
    };
}

@interface LocalHTTPSClient : NSObject <NSURLSessionDelegate>
@end

@implementation LocalHTTPSClient
- (LocalHTTPResult *)resultForRequest:(NSURLRequest *)request {
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest = 1.0;
    config.timeoutIntervalForResource = 1.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    LocalHTTPResult *result = [LocalHTTPResult new];
    __block NSInteger code = 0;
    __block NSData *dataResult = nil;
    __block NSString *errorDescription = nil;

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if ([response isKindOfClass:NSHTTPURLResponse.class]) {
            code = ((NSHTTPURLResponse *)response).statusCode;
        }
        if (error != nil) {
            errorDescription = error.localizedDescription;
        } else {
            dataResult = data;
        }
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    long waitResult = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)));
    [session invalidateAndCancel];

    result.statusCode = code;
    result.data = dataResult;
    if (waitResult != 0 && errorDescription.length == 0) {
        result.errorDescription = @"Timed out waiting for local API response.";
    } else {
        result.errorDescription = errorDescription;
    }
    return result;
}

- (void)URLSession:(NSURLSession *)session
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler {
    SecTrustRef trust = challenge.protectionSpace.serverTrust;
    if (trust != NULL) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:trust]);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}
@end

@interface LeagueClientReader : NSObject
- (nullable NSString *)gameflowPhaseWithResult:(LocalHTTPResult *_Nullable *_Nullable)resultOut lockfileInfo:(NSDictionary *_Nullable *_Nullable)lockfileInfoOut;
- (NSDictionary *)endpointSnapshotsWithLockfileInfo:(NSDictionary *_Nullable *_Nullable)lockfileInfoOut;
@end

@implementation LeagueClientReader
- (NSString *)gameflowPhaseWithResult:(LocalHTTPResult **)resultOut lockfileInfo:(NSDictionary **)lockfileInfoOut {
    NSDictionary *lockfile = [self readLockfile];
    if (lockfile == nil) {
        if (lockfileInfoOut != NULL) {
            *lockfileInfoOut = @{@"found": @NO};
        }
        return nil;
    }
    if (lockfileInfoOut != NULL) {
        *lockfileInfoOut = @{
            @"found": @YES,
            @"process": lockfile[@"process"],
            @"pid": lockfile[@"pid"],
            @"port": lockfile[@"port"],
            @"scheme": lockfile[@"scheme"]
        };
    }

    NSString *urlString = [NSString stringWithFormat:@"%@://127.0.0.1:%@/lol-gameflow/v1/gameflow-phase", lockfile[@"scheme"], lockfile[@"port"]];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 1.0;

    NSString *rawAuth = [NSString stringWithFormat:@"riot:%@", lockfile[@"password"]];
    NSString *encoded = [[rawAuth dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    [request setValue:[NSString stringWithFormat:@"Basic %@", encoded] forHTTPHeaderField:@"Authorization"];

    LocalHTTPResult *result = [[LocalHTTPSClient new] resultForRequest:request];
    if (resultOut != NULL) {
        *resultOut = result;
    }
    if (result.statusCode != 200 || result.data.length == 0) {
        return nil;
    }

    NSString *phase = [[NSString alloc] initWithData:result.data encoding:NSUTF8StringEncoding];
    phase = [phase stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    phase = [phase stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
    return phase;
}

- (NSDictionary *)endpointSnapshotsWithLockfileInfo:(NSDictionary **)lockfileInfoOut {
    NSDictionary *lockfile = [self readLockfile];
    if (lockfile == nil) {
        if (lockfileInfoOut != NULL) {
            *lockfileInfoOut = @{@"found": @NO};
        }
        return @{};
    }

    if (lockfileInfoOut != NULL) {
        *lockfileInfoOut = @{
            @"found": @YES,
            @"process": lockfile[@"process"],
            @"pid": lockfile[@"pid"],
            @"port": lockfile[@"port"],
            @"scheme": lockfile[@"scheme"]
        };
    }

    NSArray<NSString *> *endpoints = @[
        @"/lol-gameflow/v1/gameflow-phase",
        @"/lol-gameflow/v1/session",
        @"/lol-lobby/v2/lobby",
        @"/lol-lobby/v2/lobby/members",
        @"/lol-matchmaking/v1/search",
        @"/lol-summoner/v1/current-summoner",
        @"/lol-login/v1/session"
    ];

    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    for (NSString *endpoint in endpoints) {
        NSURLRequest *request = [self requestForEndpoint:endpoint lockfile:lockfile];
        if (request == nil) {
            continue;
        }
        LocalHTTPResult *result = [[LocalHTTPSClient new] resultForRequest:request];
        results[endpoint] = HTTPResultDictionary(result);
    }

    return results;
}

- (NSURLRequest *)requestForEndpoint:(NSString *)endpoint lockfile:(NSDictionary *)lockfile {
    NSString *urlString = [NSString stringWithFormat:@"%@://127.0.0.1:%@%@", lockfile[@"scheme"], lockfile[@"port"], endpoint];
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 1.0;

    NSString *rawAuth = [NSString stringWithFormat:@"riot:%@", lockfile[@"password"]];
    NSString *encoded = [[rawAuth dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    [request setValue:[NSString stringWithFormat:@"Basic %@", encoded] forHTTPHeaderField:@"Authorization"];
    return request;
}

- (NSDictionary *)readLockfile {
    NSArray<NSString *> *paths = [self candidateLockfilePaths];
    for (NSString *path in paths) {
        NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (content.length == 0) {
            continue;
        }

        NSArray<NSString *> *parts = [[content stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsSeparatedByString:@":"];
        if (parts.count == 5) {
            return @{
                @"process": parts[0],
                @"pid": parts[1],
                @"port": parts[2],
                @"password": parts[3],
                @"scheme": parts[4]
            };
        }
    }
    return nil;
}

- (NSArray<NSString *> *)candidateLockfilePaths {
    NSString *home = NSHomeDirectory();
    return @[
        @"/Applications/League of Legends.app/Contents/LoL/lockfile",
        @"/Applications/League of Legends.app/Contents/LoL/LeagueClient.app/Contents/MacOS/lockfile",
        [home stringByAppendingPathComponent:@"Applications/League of Legends.app/Contents/LoL/lockfile"]
    ];
}
@end

@interface LiveClientDataReader : NSObject
- (nullable NSNumber *)gameTimeWithResult:(LocalHTTPResult *_Nullable *_Nullable)resultOut parsedJSON:(NSDictionary *_Nullable *_Nullable)jsonOut;
@end

@implementation LiveClientDataReader
- (NSNumber *)gameTimeWithResult:(LocalHTTPResult **)resultOut parsedJSON:(NSDictionary **)jsonOut {
    NSURL *url = [NSURL URLWithString:@"https://127.0.0.1:2999/liveclientdata/allgamedata"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:1.0];

    LocalHTTPResult *result = [[LocalHTTPSClient new] resultForRequest:request];
    if (resultOut != NULL) {
        *resultOut = result;
    }
    if (result.statusCode != 200 || result.data.length == 0) {
        return nil;
    }

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:result.data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    if (jsonOut != NULL) {
        *jsonOut = json;
    }

    NSDictionary *gameData = json[@"gameData"];
    NSNumber *gameTime = gameData[@"gameTime"];
    return [gameTime isKindOfClass:NSNumber.class] ? gameTime : nil;
}
@end

@interface GameStateLogWriter : NSObject
@property(nonatomic, strong) NSURL *logDirectoryURL;
@property(nonatomic, strong) NSURL *logFileURL;
@property(nonatomic, strong) NSFileHandle *fileHandle;
@property(nonatomic, strong) NSDateFormatter *formatter;
@property(nonatomic) NSUInteger tick;
- (instancetype)init;
- (void)appendPhase:(nullable NSString *)phase
           gameTime:(nullable NSNumber *)gameTime
           snapshot:(GameSnapshot *)snapshot
          lcuResult:(nullable LocalHTTPResult *)lcuResult
       lcuEndpoints:(nullable NSDictionary *)lcuEndpoints
       liveResult:(nullable LocalHTTPResult *)liveResult
       lockfileInfo:(nullable NSDictionary *)lockfileInfo
          liveJSON:(nullable NSDictionary *)liveJSON;
@end

@implementation GameStateLogWriter
- (instancetype)init {
    self = [super init];
    if (self) {
        NSFileManager *fileManager = NSFileManager.defaultManager;
        NSURL *appSupport = [fileManager URLForDirectory:NSApplicationSupportDirectory
                                                inDomain:NSUserDomainMask
                                       appropriateForURL:nil
                                                  create:YES
                                                   error:nil];
        _logDirectoryURL = [appSupport URLByAppendingPathComponent:@"TFTOverlay/Captures" isDirectory:YES];
        [fileManager createDirectoryAtURL:_logDirectoryURL withIntermediateDirectories:YES attributes:nil error:nil];

        NSDateFormatter *fileFormatter = [NSDateFormatter new];
        fileFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fileFormatter.dateFormat = @"yyyy-MM-dd_HH-mm-ss";
        NSString *filename = [NSString stringWithFormat:@"collection-%@.ndjson", [fileFormatter stringFromDate:NSDate.date]];
        _logFileURL = [_logDirectoryURL URLByAppendingPathComponent:filename];

        [fileManager createFileAtPath:_logFileURL.path contents:nil attributes:nil];
        _fileHandle = [NSFileHandle fileHandleForWritingToURL:_logFileURL error:nil];

        _formatter = [NSDateFormatter new];
        _formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        _formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        _formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";

        [self appendMetadata];
    }
    return self;
}

- (void)appendMetadata {
    NSDictionary *record = @{
        @"type": @"session_start",
        @"timestamp": [self.formatter stringFromDate:NSDate.date],
        @"schemaVersion": @1,
        @"notes": @"Raw local API responses are captured for offline TFT overlay development. No lockfile password is logged."
    };
    [self appendRecord:record];
}

- (void)appendPhase:(NSString *)phase
           gameTime:(NSNumber *)gameTime
           snapshot:(GameSnapshot *)snapshot
          lcuResult:(LocalHTTPResult *)lcuResult
       lcuEndpoints:(NSDictionary *)lcuEndpoints
        liveResult:(LocalHTTPResult *)liveResult
       lockfileInfo:(NSDictionary *)lockfileInfo
          liveJSON:(NSDictionary *)liveJSON {
    self.tick += 1;

    NSMutableDictionary *record = [NSMutableDictionary dictionary];
    record[@"type"] = @"poll";
    record[@"tick"] = @(self.tick);
    record[@"timestamp"] = [self.formatter stringFromDate:NSDate.date];
    record[@"parsed"] = @{
        @"phase": phase ?: [NSNull null],
        @"gameTime": gameTime ?: [NSNull null],
        @"overlayTitle": snapshot.title ?: @"",
        @"overlaySubtitle": snapshot.subtitle ?: @"",
        @"stageHint": snapshot.stageHint ?: [NSNull null]
    };
    record[@"lockfile"] = lockfileInfo ?: @{@"found": @NO};
    record[@"lcuGameflowPhase"] = [self dictionaryForResult:lcuResult];
    record[@"lcuEndpoints"] = lcuEndpoints ?: @{};
    record[@"liveAllGameData"] = [self dictionaryForResult:liveResult];
    record[@"liveSummary"] = [self summaryForLiveJSON:liveJSON];

    [self appendRecord:record];
}

- (NSDictionary *)dictionaryForResult:(LocalHTTPResult *)result {
    return HTTPResultDictionary(result);
}

- (NSDictionary *)summaryForLiveJSON:(NSDictionary *)json {
    if (![json isKindOfClass:NSDictionary.class]) {
        return @{};
    }

    NSDictionary *gameData = [json[@"gameData"] isKindOfClass:NSDictionary.class] ? json[@"gameData"] : @{};
    NSArray *allPlayers = [json[@"allPlayers"] isKindOfClass:NSArray.class] ? json[@"allPlayers"] : @[];
    NSArray *events = [json[@"events"][@"Events"] isKindOfClass:NSArray.class] ? json[@"events"][@"Events"] : @[];

    NSMutableArray *playerSummaries = [NSMutableArray array];
    for (NSDictionary *player in allPlayers) {
        if (![player isKindOfClass:NSDictionary.class]) {
            continue;
        }
        [playerSummaries addObject:@{
            @"summonerName": player[@"summonerName"] ?: @"",
            @"championName": player[@"championName"] ?: @"",
            @"team": player[@"team"] ?: [NSNull null],
            @"level": player[@"level"] ?: [NSNull null],
            @"isBot": player[@"isBot"] ?: [NSNull null]
        }];
    }

    return @{
        @"topLevelKeys": [json.allKeys sortedArrayUsingSelector:@selector(compare:)],
        @"gameMode": gameData[@"gameMode"] ?: [NSNull null],
        @"gameTime": gameData[@"gameTime"] ?: [NSNull null],
        @"mapName": gameData[@"mapName"] ?: [NSNull null],
        @"playerCount": @(allPlayers.count),
        @"eventCount": @(events.count),
        @"players": playerSummaries
    };
}

- (void)appendRecord:(NSDictionary *)record {
    if (self.fileHandle == nil) {
        return;
    }

    if (![NSJSONSerialization isValidJSONObject:record]) {
        return;
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    if (json.length == 0) {
        return;
    }

    [self.fileHandle writeData:json];
    [self.fileHandle writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    if (self.tick % 5 == 0) {
        [self.fileHandle synchronizeFile];
    }
}

- (void)dealloc {
    [self.fileHandle synchronizeFile];
    [self.fileHandle closeFile];
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) OverlayWindow *overlayWindow;
@property(nonatomic, strong) OverlayView *overlayView;
@property(nonatomic, strong) SettingsWindowController *settingsWindowController;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) LeagueClientReader *leagueClient;
@property(nonatomic, strong) LiveClientDataReader *liveClient;
@property(nonatomic, strong) GameStateLogWriter *logWriter;
@property(nonatomic) NSTimeInterval pollingInterval;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    self.pollingInterval = 1.5;

    self.overlayView = [[OverlayView alloc] initWithFrame:NSScreen.mainScreen.frame];
    self.overlayWindow = [[OverlayWindow alloc] initWithContentView:self.overlayView];
    [self.overlayWindow orderFrontRegardless];

    self.leagueClient = [LeagueClientReader new];
    self.liveClient = [LiveClientDataReader new];
    self.logWriter = [GameStateLogWriter new];
    [self installSettingsWindow];

    [self installStatusMenu];
    [self startPolling];
    [self showSettings:nil];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self showSettings:nil];
    return YES;
}

- (void)installSettingsWindow {
    self.settingsWindowController = [[SettingsWindowController alloc] initWithLogURL:self.logWriter.logFileURL pollingInterval:self.pollingInterval];

    __weak typeof(self) weakSelf = self;
    self.settingsWindowController.overlayVisibilityChanged = ^(BOOL visible) {
        [weakSelf setOverlayVisible:visible];
    };
    self.settingsWindowController.pollingIntervalChanged = ^(NSTimeInterval interval) {
        [weakSelf applyPollingInterval:interval];
    };
    self.settingsWindowController.openLogsRequested = ^{
        [weakSelf openLogFolder:nil];
    };
    self.settingsWindowController.quitRequested = ^{
        [weakSelf quit:nil];
    };
}

- (void)installStatusMenu {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"TFT";

    NSMenu *menu = [NSMenu new];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Show Settings" action:@selector(showSettings:) keyEquivalent:@","]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Toggle Overlay" action:@selector(toggleOverlay:) keyEquivalent:@"t"]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Open Log Folder" action:@selector(openLogFolder:) keyEquivalent:@"l"]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@"q"]];
    self.statusItem.menu = menu;
}

- (void)startPolling {
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.pollingInterval target:self selector:@selector(pollGameState:) userInfo:nil repeats:YES];
    [self pollGameState:nil];
}

- (void)pollGameState:(NSTimer *)timer {
    LeagueClientReader *leagueClient = self.leagueClient;
    LiveClientDataReader *liveClient = self.liveClient;
    GameStateLogWriter *logWriter = self.logWriter;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        LocalHTTPResult *lcuResult = nil;
        LocalHTTPResult *liveResult = nil;
        NSDictionary *lockfileInfo = nil;
        NSDictionary *liveJSON = nil;
        NSString *phase = [leagueClient gameflowPhaseWithResult:&lcuResult lockfileInfo:&lockfileInfo];
        NSDictionary *lcuEndpoints = [leagueClient endpointSnapshotsWithLockfileInfo:&lockfileInfo];
        NSNumber *gameTime = [liveClient gameTimeWithResult:&liveResult parsedJSON:&liveJSON];
        GameSnapshot *snapshot = (phase.length > 0 || gameTime != nil) ? [GameSnapshot snapshotWithPhase:phase gameTime:gameTime] : [GameSnapshot idle];

        [logWriter appendPhase:phase
                      gameTime:gameTime
                      snapshot:snapshot
                     lcuResult:lcuResult
                  lcuEndpoints:lcuEndpoints
                    liveResult:liveResult
                  lockfileInfo:lockfileInfo
                      liveJSON:liveJSON];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.overlayView.snapshot = snapshot;
            [self.settingsWindowController updateSnapshot:snapshot overlayVisible:self.overlayWindow.visible];
        });
    });
}

- (void)toggleOverlay:(id)sender {
    [self setOverlayVisible:!self.overlayWindow.visible];
}

- (void)setOverlayVisible:(BOOL)visible {
    if (visible) {
        [self.overlayWindow orderFrontRegardless];
    } else {
        [self.overlayWindow orderOut:nil];
    }
    [self.settingsWindowController updateSnapshot:self.overlayView.snapshot overlayVisible:visible];
}

- (void)applyPollingInterval:(NSTimeInterval)interval {
    self.pollingInterval = interval;
    [self.timer invalidate];
    [self startPolling];
}

- (void)showSettings:(id)sender {
    [self.settingsWindowController showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.settingsWindowController.window makeKeyAndOrderFront:nil];
}

- (void)openLogFolder:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:self.logWriter.logDirectoryURL];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
