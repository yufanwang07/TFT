#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Vision/Vision.h>

@interface GameSnapshot : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *subtitle;
@property(nonatomic, copy, nullable) NSString *detail;
@property(nonatomic, copy, nullable) NSString *stageHint;
@property(nonatomic, copy) NSArray<NSDictionary *> *augmentTierOverlays;
@property(nonatomic, copy) NSArray<NSDictionary *> *godBoonTierOverlays;
@property(nonatomic, strong, nullable) NSDictionary *unitRecommendation;
@property(nonatomic, strong, nullable) NSDictionary *boardReconstruction;
@property(nonatomic, strong, nullable) NSDictionary *compSuggestion;
@property(nonatomic, copy) NSArray<NSString *> *visionDebugLines;
@property(nonatomic, copy, nullable) NSString *heroCompName;
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
    snapshot.augmentTierOverlays = @[];
    snapshot.godBoonTierOverlays = @[];
    snapshot.unitRecommendation = nil;
    snapshot.boardReconstruction = nil;
    snapshot.compSuggestion = nil;
    snapshot.visionDebugLines = @[];
    snapshot.heroCompName = nil;
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
    snapshot.augmentTierOverlays = @[];
    snapshot.godBoonTierOverlays = @[];
    snapshot.unitRecommendation = nil;
    snapshot.boardReconstruction = nil;
    snapshot.compSuggestion = nil;
    snapshot.visionDebugLines = @[];
    snapshot.heroCompName = nil;
    return snapshot;
}
@end

@interface OverlayView : NSView
@property(nonatomic, strong) GameSnapshot *snapshot;
@property(nonatomic) NSPoint mouseScreenPoint;
@property(nonatomic, strong, nullable) NSDictionary *hoveredCompBadge;
@property(nonatomic) NSRect hoveredCompBadgeRect;
@property(nonatomic) BOOL showOCRZones;
@end

@implementation OverlayView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _snapshot = [GameSnapshot idle];
        _mouseScreenPoint = NSMakePoint(CGFLOAT_MIN, CGFLOAT_MIN);
        _showOCRZones = NO;
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
    self.hoveredCompBadge = nil;
    self.hoveredCompBadgeRect = NSZeroRect;
    [self drawStatusPanel];
    [self drawVisionDebugPanel];
    [self drawStageHint];
    [self drawCompSuggestionPanel];
    [self drawAugmentTierOverlays];
    [self drawGodBoonTierOverlays];
    [self drawUnitRecommendationPanel];
    [self drawOCRZoneOverlay];
    if (self.hoveredCompBadge != nil) {
        [self drawCompTooltipForBadge:self.hoveredCompBadge anchorRect:self.hoveredCompBadgeRect];
    }
}

- (void)setShowOCRZones:(BOOL)showOCRZones {
    _showOCRZones = showOCRZones;
    [self setNeedsDisplay:YES];
}

- (void)drawStatusPanel {
    NSRect bounds = self.bounds;
    NSRect panel = NSMakeRect(NSMinX(bounds) + 24, NSMaxY(bounds) - 152, 540, 112);
    [self drawPanel:panel fill:[NSColor colorWithWhite:0 alpha:0.42]];
    [self drawText:self.snapshot.title in:NSInsetRect(panel, 16, 14) size:18 weight:NSFontWeightSemibold color:NSColor.whiteColor alignment:NSTextAlignmentLeft];
    [self drawText:self.snapshot.subtitle in:NSInsetRect(panel, 16, 44) size:13 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor alignment:NSTextAlignmentLeft];
    if (self.snapshot.detail.length > 0) {
        [self drawText:self.snapshot.detail in:NSInsetRect(panel, 16, 70) size:12 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor alignment:NSTextAlignmentLeft];
    }
}

- (void)drawVisionDebugPanel {
    if (self.snapshot.visionDebugLines.count == 0) {
        return;
    }

    NSRect bounds = self.bounds;
    CGFloat lineHeight = 17;
    CGFloat height = 24 + lineHeight * MIN(self.snapshot.visionDebugLines.count, 14);
    NSRect panel = NSMakeRect(NSMaxX(bounds) - 454, NSMaxY(bounds) - 24 - height, 430, height);
    [self drawPanel:panel fill:[NSColor colorWithWhite:0 alpha:0.52]];

    CGFloat y = NSMaxY(panel) - 22;
    for (NSUInteger i = 0; i < self.snapshot.visionDebugLines.count && i < 14; i += 1) {
        NSString *line = self.snapshot.visionDebugLines[i];
        [self drawText:line in:NSMakeRect(NSMinX(panel) + 12, y, NSWidth(panel) - 24, lineHeight)
                  size:12 weight:NSFontWeightRegular color:NSColor.whiteColor alignment:NSTextAlignmentLeft];
        y -= lineHeight;
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

- (void)drawAugmentTierOverlays {
    if ([self hasThreeValidAugmentMatches]) {
        [self drawAugmentClickDebugBorders];
    }
    CGFloat scaleX = NSWidth(self.bounds) / 1920.0;
    CGFloat scaleY = NSHeight(self.bounds) / 1080.0;
    for (NSDictionary *match in self.snapshot.augmentTierOverlays) {
        NSNumber *slotNumber = match[@"slot"];
        NSString *tier = match[@"tier"];
        if (![slotNumber isKindOfClass:NSNumber.class] || tier.length == 0) {
            continue;
        }
        NSArray *compBadges = [match[@"compBadges"] isKindOfClass:NSArray.class] ? match[@"compBadges"] : @[];
        NSString *actualTier = [match[@"actualTier"] isKindOfClass:NSString.class] ? match[@"actualTier"] : @"";
        if ([tier isEqualToString:@"X"] && actualTier.length == 0 && compBadges.count > 0) {
            NSDictionary *firstBadge = [compBadges.firstObject isKindOfClass:NSDictionary.class] ? compBadges.firstObject : nil;
            actualTier = [firstBadge[@"tier"] isKindOfClass:NSString.class] ? firstBadge[@"tier"] : @"";
        }

        NSInteger slot = slotNumber.integerValue;
        if (slot < 0 || slot >= 3) {
            continue;
        }

        CGFloat centerX = (slot == 0 ? 522 : (slot == 1 ? 960 : 1392)) * scaleX;
        CGFloat tierTopY = 740 * scaleY;
        NSRect tierRect = NSMakeRect(centerX - 33, NSHeight(self.bounds) - tierTopY - 66, 66, 66);
        [self drawTierHexagon:tier actualTier:actualTier inRect:tierRect];

        [self drawCompBadges:compBadges centerX:centerX topY:808 * scaleY];
    }
}

- (void)drawGodBoonTierOverlays {
    CGFloat scaleX = NSWidth(self.bounds) / 1920.0;
    CGFloat scaleY = NSHeight(self.bounds) / 1080.0;
    CGFloat centers[] = {735, 1185};
    for (NSDictionary *match in self.snapshot.godBoonTierOverlays) {
        NSNumber *slotNumber = [match[@"slot"] isKindOfClass:NSNumber.class] ? match[@"slot"] : nil;
        NSString *tier = [match[@"tier"] isKindOfClass:NSString.class] ? match[@"tier"] : @"";
        if (slotNumber == nil || tier.length == 0) {
            continue;
        }
        NSInteger slot = slotNumber.integerValue;
        if (slot < 0 || slot >= 2) {
            continue;
        }
        CGFloat centerX = centers[slot] * scaleX;
        CGFloat tierTopY = 790 * scaleY;
        NSRect tierRect = NSMakeRect(centerX - 33, NSHeight(self.bounds) - tierTopY - 66, 66, 66);
        [self drawTierHexagon:tier actualTier:@"" inRect:tierRect];
        NSArray *compBadges = [match[@"compBadges"] isKindOfClass:NSArray.class] ? match[@"compBadges"] : @[];
        [self drawCompBadges:compBadges centerX:centerX topY:858 * scaleY];
    }
}

- (void)drawUnitRecommendationPanel {
    NSDictionary *recommendation = self.snapshot.unitRecommendation;
    if (![recommendation isKindOfClass:NSDictionary.class]) {
        return;
    }
    NSArray *builds = [recommendation[@"builds"] isKindOfClass:NSArray.class] ? recommendation[@"builds"] : @[];
    if (builds.count == 0) {
        return;
    }

    CGFloat scale = MIN(NSWidth(self.bounds) / 1920.0, NSHeight(self.bounds) / 1080.0);
    CGFloat width = 252 * scale;
    CGFloat height = (78 + MIN(builds.count, 5) * 42) * scale;
    CGFloat rightInset = 240 * scale;
    NSRect panel = NSMakeRect(NSWidth(self.bounds) - rightInset - width,
                              NSMidY(self.bounds) - height / 2.0,
                              width,
                              height);
    [self drawPanel:panel fill:[NSColor colorWithWhite:0.03 alpha:0.84]];

    [self drawText:@"Top Builds" in:NSMakeRect(NSMinX(panel) + 14 * scale, NSMaxY(panel) - 34 * scale, NSWidth(panel) - 28 * scale, 24 * scale)
              size:20 * scale weight:NSFontWeightBold color:NSColor.whiteColor alignment:NSTextAlignmentLeft];
    [self drawText:@"Recommended by MetaTFT" in:NSMakeRect(NSMinX(panel) + 14 * scale, NSMaxY(panel) - 57 * scale, NSWidth(panel) - 28 * scale, 18 * scale)
              size:12 * scale weight:NSFontWeightMedium color:[NSColor colorWithWhite:1 alpha:0.70] alignment:NSTextAlignmentLeft];

    CGFloat iconSize = 30 * scale;
    CGFloat rowGap = 12 * scale;
    CGFloat y = NSMaxY(panel) - 98 * scale;
    NSUInteger count = MIN(builds.count, 5);
    for (NSUInteger i = 0; i < count; i += 1) {
        NSDictionary *build = [builds[i] isKindOfClass:NSDictionary.class] ? builds[i] : nil;
        NSArray *items = [build[@"items"] isKindOfClass:NSArray.class] ? build[@"items"] : @[];
        CGFloat x = NSMinX(panel) + 14 * scale;
        for (NSUInteger itemIndex = 0; itemIndex < MIN(items.count, 3); itemIndex += 1) {
            NSString *apiName = [items[itemIndex] isKindOfClass:NSString.class] ? items[itemIndex] : @"";
            NSRect iconRect = NSMakeRect(x, y, iconSize, iconSize);
            [self drawRoundedItemIcon:apiName inRect:iconRect fallbackText:[self compactItemName:apiName]];
            x += iconSize + 7 * scale;
        }
        NSNumber *avgPlace = [build[@"avgPlace"] isKindOfClass:NSNumber.class] ? build[@"avgPlace"] : nil;
        if (avgPlace != nil) {
            NSString *avgText = [NSString stringWithFormat:@"%.2f", avgPlace.doubleValue];
            [self drawText:avgText in:NSMakeRect(NSMaxX(panel) - 72 * scale, y + 13 * scale, 58 * scale, 18 * scale)
                      size:16 * scale weight:NSFontWeightBold color:[NSColor colorWithWhite:1 alpha:0.91] alignment:NSTextAlignmentRight];
            [self drawText:@"Avg place" in:NSMakeRect(NSMaxX(panel) - 72 * scale, y - 2 * scale, 58 * scale, 13 * scale)
                      size:9 * scale weight:NSFontWeightMedium color:[NSColor colorWithWhite:1 alpha:0.54] alignment:NSTextAlignmentRight];
        }
        y -= iconSize + rowGap;
    }
}

- (void)drawCompSuggestionPanel {
    NSDictionary *suggestion = self.snapshot.compSuggestion;
    if (![suggestion isKindOfClass:NSDictionary.class]) {
        return;
    }
    NSArray *comps = [suggestion[@"comps"] isKindOfClass:NSArray.class] ? suggestion[@"comps"] : @[];
    if (comps.count == 0) {
        return;
    }

    CGFloat scale = MIN(NSWidth(self.bounds) / 1920.0, NSHeight(self.bounds) / 1080.0);
    NSUInteger count = MIN(comps.count, 5);
    CGFloat iconSize = 52 * scale;
    CGFloat gap = 9 * scale;
    CGFloat labelWidth = 126 * scale;
    CGFloat width = labelWidth + count * iconSize + MAX(0, (NSInteger)count - 1) * gap + 26 * scale;
    CGFloat height = 76 * scale;
    NSRect panel = NSMakeRect(74 * scale, NSHeight(self.bounds) - 326 * scale, width, height);
    [self drawPanel:panel fill:[NSColor colorWithWhite:0.02 alpha:0.58]];

    NSString *label = [suggestion[@"label"] isKindOfClass:NSString.class] ? suggestion[@"label"] : @"Can play into";
    [self drawText:label in:NSMakeRect(NSMinX(panel) + 12 * scale, NSMaxY(panel) - 43 * scale, labelWidth - 16 * scale, 24 * scale)
              size:14 * scale weight:NSFontWeightBold color:[NSColor colorWithWhite:1 alpha:0.88] alignment:NSTextAlignmentLeft];

    NSString *selectedTitle = [suggestion[@"selectedTitle"] isKindOfClass:NSString.class] ? suggestion[@"selectedTitle"] : @"";
    if (selectedTitle.length > 0) {
        [self drawText:selectedTitle in:NSMakeRect(NSMinX(panel) + 12 * scale, NSMinY(panel) + 16 * scale, labelWidth - 16 * scale, 18 * scale)
                  size:11 * scale weight:NSFontWeightMedium color:[NSColor colorWithWhite:1 alpha:0.66] alignment:NSTextAlignmentLeft];
    }

    CGFloat x = NSMinX(panel) + labelWidth;
    CGFloat y = NSMidY(panel) - iconSize / 2.0;
    NSPoint mousePoint = [self currentMousePointInView];
    for (NSUInteger i = 0; i < count; i += 1) {
        NSDictionary *badge = [comps[i] isKindOfClass:NSDictionary.class] ? comps[i] : nil;
        NSRect rect = NSMakeRect(x + i * (iconSize + gap), y, iconSize, iconSize);
        [self drawCompBadgeIcon:badge inRect:rect locked:[badge[@"locked"] boolValue] mousePoint:mousePoint scale:scale];
    }
}

- (void)drawCompBadgeIcon:(NSDictionary *)badge inRect:(NSRect)rect locked:(BOOL)locked mousePoint:(NSPoint)mousePoint scale:(CGFloat)scale {
    if (![badge isKindOfClass:NSDictionary.class]) {
        return;
    }
    NSString *tier = [badge[@"tier"] isKindOfClass:NSString.class] ? badge[@"tier"] : @"";
    NSString *championApiName = [badge[@"championApiName"] isKindOfClass:NSString.class] ? badge[@"championApiName"] : @"";
    NSNumber *cost = [badge[@"cost"] isKindOfClass:NSNumber.class] ? badge[@"cost"] : nil;
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:rect];
    [[NSColor colorWithWhite:0 alpha:0.58] setFill];
    [circle fill];
    NSImage *icon = [self championIconForApiName:championApiName];
    if (icon != nil) {
        [NSGraphicsContext saveGraphicsState];
        [circle addClip];
        [icon drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
        [NSGraphicsContext restoreGraphicsState];
    }
    [[self championCostColor:cost.integerValue] setStroke];
    circle.lineWidth = MAX(2.0, 2.8 * scale);
    [circle stroke];

    BOOL hovered = NSPointInRect(mousePoint, NSInsetRect(rect, -4 * scale, -4 * scale));
    if (hovered) {
        self.hoveredCompBadge = badge;
        self.hoveredCompBadgeRect = rect;
        [[[self tierInnerColor:tier] colorWithAlphaComponent:0.72] setFill];
        [circle fill];
        [self drawCenteredText:tier inRect:rect size:MAX(14, 18 * scale) weight:NSFontWeightBlack color:[NSColor colorWithWhite:0 alpha:0.86]];
        [[self championCostColor:cost.integerValue] setStroke];
        circle.lineWidth = MAX(2.0, 2.8 * scale);
        [circle stroke];
    }

    if (locked) {
        [[[self championCostColor:cost.integerValue] colorWithAlphaComponent:0.44] setFill];
        [circle fill];
        [self drawCenteredText:@"X" inRect:rect size:MAX(18, 22 * scale) weight:NSFontWeightBlack color:[NSColor colorWithWhite:0 alpha:0.84]];
        [[NSColor colorWithWhite:1 alpha:0.48] setStroke];
        circle.lineWidth = MAX(1.5, 2.0 * scale);
        [circle stroke];
    }
}

- (void)drawOCRZoneOverlay {
    if (!self.showOCRZones) {
        return;
    }

    NSArray<NSDictionary *> *zones = @[
        @{@"label": @"traits", @"rect": [NSValue valueWithRect:NSMakeRect(55, 240, 230, 610)], @"h": @"left", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:0.20 green:0.95 blue:0.78 alpha:0.82]},
        @{@"label": @"augment 1", @"rect": [NSValue valueWithRect:NSMakeRect(417, 552, 270, 30)], @"h": @"center", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:0.26 green:0.75 blue:1.00 alpha:0.82]},
        @{@"label": @"augment 2", @"rect": [NSValue valueWithRect:NSMakeRect(825, 552, 270, 30)], @"h": @"center", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:0.26 green:0.75 blue:1.00 alpha:0.82]},
        @{@"label": @"augment 3", @"rect": [NSValue valueWithRect:NSMakeRect(1230, 552, 270, 30)], @"h": @"center", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:0.26 green:0.75 blue:1.00 alpha:0.82]},
        @{@"label": @"aug gate 1", @"rect": [NSValue valueWithRect:NSMakeRect(546, 591, 12, 12)], @"h": @"center", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:0.55 green:0.32 blue:1.00 alpha:0.78]},
        @{@"label": @"aug gate 2", @"rect": [NSValue valueWithRect:NSMakeRect(954, 591, 12, 12)], @"h": @"center", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:0.55 green:0.32 blue:1.00 alpha:0.78]},
        @{@"label": @"aug gate 3", @"rect": [NSValue valueWithRect:NSMakeRect(1359, 591, 12, 12)], @"h": @"center", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:0.55 green:0.32 blue:1.00 alpha:0.78]},
        @{@"label": @"god 1", @"rect": [NSValue valueWithRect:NSMakeRect(697.3, 382.7, 105.5, 39.8)], @"h": @"center", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:0.86 green:0.58 blue:1.00 alpha:0.82]},
        @{@"label": @"god 2", @"rect": [NSValue valueWithRect:NSMakeRect(1113.8, 384.6, 92.1, 35.9)], @"h": @"center", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:0.86 green:0.58 blue:1.00 alpha:0.82]},
        @{@"label": @"god gate 1", @"rect": [NSValue valueWithRect:NSMakeRect(744, 634, 12, 12)], @"h": @"center", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:0.44 green:0.34 blue:1.00 alpha:0.78]},
        @{@"label": @"god gate 2", @"rect": [NSValue valueWithRect:NSMakeRect(1154, 634, 12, 12)], @"h": @"center", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:0.44 green:0.34 blue:1.00 alpha:0.78]},
        @{@"label": @"panel p1", @"rect": [NSValue valueWithRect:NSMakeRect(1707.4, 818.6, 12, 12)], @"h": @"right", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:0.00 green:0.95 blue:0.82 alpha:0.74]},
        @{@"label": @"panel p2", @"rect": [NSValue valueWithRect:NSMakeRect(1711.9, 639.9, 12, 12)], @"h": @"right", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:0.00 green:0.95 blue:0.82 alpha:0.74]},
        @{@"label": @"panel p3", @"rect": [NSValue valueWithRect:NSMakeRect(1875.8, 643.7, 12, 12)], @"h": @"right", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:0.00 green:0.95 blue:0.82 alpha:0.74]},
        @{@"label": @"unit name", @"rect": [NSValue valueWithRect:NSMakeRect(1686.5, 330.0, 165.0, 26.0)], @"h": @"right", @"v": @"center", @"color": [NSColor colorWithCalibratedRed:1.00 green:0.82 blue:0.20 alpha:0.82]}
    ];

    for (NSDictionary *zone in zones) {
        NSValue *value = [zone[@"rect"] isKindOfClass:NSValue.class] ? zone[@"rect"] : nil;
        if (value == nil) {
            continue;
        }
        NSString *horizontal = [zone[@"h"] isKindOfClass:NSString.class] ? zone[@"h"] : @"left";
        NSString *vertical = [zone[@"v"] isKindOfClass:NSString.class] ? zone[@"v"] : @"top";
        NSString *label = [zone[@"label"] isKindOfClass:NSString.class] ? zone[@"label"] : @"OCR";
        NSColor *color = [zone[@"color"] isKindOfClass:NSColor.class] ? zone[@"color"] : [NSColor colorWithCalibratedRed:0.30 green:0.90 blue:1.00 alpha:0.82];
        NSRect rect = [self rectFromAnchoredBaseRect:value.rectValue horizontal:horizontal vertical:vertical];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:5 yRadius:5];
        [[color colorWithAlphaComponent:0.11] setFill];
        [path fill];
        [color setStroke];
        path.lineWidth = 1.5;
        CGFloat dash[] = {6, 4};
        [path setLineDash:dash count:2 phase:0];
        [path stroke];

        NSRect labelRect = NSMakeRect(NSMinX(rect), NSMaxY(rect) + 3, MAX(74, MIN(NSWidth(rect), 120)), 18);
        NSBezierPath *labelPath = [NSBezierPath bezierPathWithRoundedRect:labelRect xRadius:4 yRadius:4];
        [[NSColor colorWithWhite:0 alpha:0.72] setFill];
        [labelPath fill];
        [self drawText:label in:NSInsetRect(labelRect, 5, 2) size:10 weight:NSFontWeightBold color:color alignment:NSTextAlignmentLeft];
    }
}

- (BOOL)hasThreeValidAugmentMatches {
    NSMutableSet<NSNumber *> *slots = [NSMutableSet set];
    for (NSDictionary *match in self.snapshot.augmentTierOverlays) {
        NSNumber *slot = [match[@"slot"] isKindOfClass:NSNumber.class] ? match[@"slot"] : nil;
        NSString *name = [match[@"displayName"] isKindOfClass:NSString.class] ? match[@"displayName"] : @"";
        NSString *tier = [match[@"tier"] isKindOfClass:NSString.class] ? match[@"tier"] : @"";
        if (slot == nil || name.length == 0 || tier.length == 0) {
            continue;
        }
        if (slot.integerValue >= 0 && slot.integerValue < 3) {
            [slots addObject:slot];
        }
    }
    return slots.count == 3;
}

- (void)drawAugmentClickDebugBorders {
    NSArray<NSValue *> *zones = [self augmentCardZoneRects];
    [[NSColor colorWithCalibratedRed:0.3 green:0.9 blue:1 alpha:0.48] setStroke];
    for (NSValue *zoneValue in zones) {
        NSRect rect = [self rectFromAnchoredBaseRect:zoneValue.rectValue horizontal:@"center" vertical:@"center"];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:10 yRadius:10];
        path.lineWidth = 2;
        CGFloat dash[] = {8, 5};
        [path setLineDash:dash count:2 phase:0];
        [path stroke];
    }
}

- (NSArray<NSValue *> *)augmentCardZoneRects {
    return @[
        [NSValue valueWithRect:NSMakeRect(350, 276, 350, 560)],
        [NSValue valueWithRect:NSMakeRect(785, 276, 350, 560)],
        [NSValue valueWithRect:NSMakeRect(1220, 276, 350, 560)]
    ];
}

- (NSRect)rectFromAnchoredBaseRect:(NSRect)baseRect horizontal:(NSString *)horizontal vertical:(NSString *)vertical {
    CGFloat scaleX = NSWidth(self.bounds) / 1920.0;
    CGFloat scaleY = NSHeight(self.bounds) / 1080.0;
    CGFloat width = NSWidth(baseRect) * scaleX;
    CGFloat height = NSHeight(baseRect) * scaleY;
    CGFloat x = 0;
    if ([horizontal isEqualToString:@"center"]) {
        x = NSMidX(self.bounds) + (NSMidX(baseRect) - 960.0) * scaleX - width / 2.0;
    } else if ([horizontal isEqualToString:@"right"]) {
        x = NSMaxX(self.bounds) - (1920.0 - NSMaxX(baseRect)) * scaleX - width;
    } else {
        x = NSMinX(baseRect) * scaleX;
    }
    CGFloat topY = 0;
    if ([vertical isEqualToString:@"center"]) {
        topY = NSHeight(self.bounds) / 2.0 + (NSMidY(baseRect) - 540.0) * scaleY - height / 2.0;
    } else if ([vertical isEqualToString:@"bottom"]) {
        topY = NSHeight(self.bounds) - (1080.0 - NSMaxY(baseRect)) * scaleY - height;
    } else {
        topY = NSMinY(baseRect) * scaleY;
    }
    return NSMakeRect(x, NSHeight(self.bounds) - topY - height, width, height);
}

- (void)drawTierHexagon:(NSString *)tier actualTier:(NSString *)actualTier inRect:(NSRect)rect {
    [self drawSingleTierHexagon:tier inRect:rect textSize:28 borderWidth:4.0];

    if (![tier isEqualToString:@"X"] || actualTier.length == 0 || [actualTier isEqualToString:tier]) {
        return;
    }

    CGFloat smallSize = NSWidth(rect) * 0.44;
    NSRect innerRect = NSInsetRect(rect, 3, 3);
    NSPoint top = NSMakePoint(NSMidX(innerRect), NSMaxY(innerRect));
    NSPoint upperLeft = NSMakePoint(NSMidX(innerRect) - cos((CGFloat)M_PI / 6.0) * NSWidth(innerRect) / 2.0,
                                    NSMidY(innerRect) + sin((CGFloat)M_PI / 6.0) * NSHeight(innerRect) / 2.0);
    NSPoint center = NSMakePoint((top.x + upperLeft.x) / 2.0, (top.y + upperLeft.y) / 2.0);
    NSRect smallRect = NSMakeRect(center.x - smallSize / 2.0, center.y - smallSize / 2.0, smallSize, smallSize);
    [self drawSingleTierHexagon:actualTier inRect:smallRect textSize:13 borderWidth:2.0];
}

- (void)drawSingleTierHexagon:(NSString *)tier inRect:(NSRect)rect textSize:(CGFloat)textSize borderWidth:(CGFloat)borderWidth {
    NSColor *outer = [self tierOuterColor:tier];
    NSColor *inner = [self tierInnerColor:tier];
    NSBezierPath *outerPath = [self hexagonPathInRect:rect inset:0];
    NSGradient *outerGradient = [[NSGradient alloc] initWithStartingColor:[self tierGradientHighlightColorForColor:outer tier:tier amount:0.22]
                                                              endingColor:outer];
    [outerGradient drawInBezierPath:outerPath angle:90];

    NSBezierPath *innerPath = [self hexagonPathInRect:rect inset:borderWidth];
    NSGradient *innerGradient = [[NSGradient alloc] initWithStartingColor:[self tierGradientHighlightColorForColor:inner tier:tier amount:0.20]
                                                              endingColor:inner];
    [innerGradient drawInBezierPath:innerPath angle:90];

    [self drawCenteredText:tier inRect:rect size:textSize weight:NSFontWeightBlack color:[NSColor colorWithWhite:0 alpha:0.86]];
}

- (NSColor *)tierGradientHighlightColorForColor:(NSColor *)color tier:(NSString *)tier amount:(CGFloat)amount {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: color;
    CGFloat red = 0;
    CGFloat green = 0;
    CGFloat blue = 0;
    CGFloat alpha = 0;
    [rgb getRed:&red green:&green blue:&blue alpha:&alpha];

    CGFloat targetRed = 1.0;
    CGFloat targetGreen = [tier isEqualToString:@"S"] ? 1.0 : 0.92;
    CGFloat targetBlue = [tier isEqualToString:@"S"] ? 1.0 : 0.86;
    return [NSColor colorWithCalibratedRed:red + (targetRed - red) * amount
                                     green:green + (targetGreen - green) * amount
                                      blue:blue + (targetBlue - blue) * amount
                                     alpha:alpha];
}

- (NSBezierPath *)hexagonPathInRect:(NSRect)rect inset:(CGFloat)inset {
    NSRect r = NSInsetRect(rect, inset, inset);
    CGFloat midX = NSMidX(r);
    CGFloat midY = NSMidY(r);
    CGFloat radiusX = NSWidth(r) / 2.0;
    CGFloat radiusY = NSHeight(r) / 2.0;
    NSBezierPath *path = [NSBezierPath bezierPath];
    for (NSInteger i = 0; i < 6; i += 1) {
        CGFloat angle = (CGFloat)M_PI / 6.0 + ((CGFloat)i * (CGFloat)M_PI / 3.0);
        NSPoint point = NSMakePoint(midX + cos(angle) * radiusX, midY + sin(angle) * radiusY);
        if (i == 0) {
            [path moveToPoint:point];
        } else {
            [path lineToPoint:point];
        }
    }
    [path closePath];
    return path;
}

- (NSColor *)tierOuterColor:(NSString *)tier {
    if ([tier isEqualToString:@"X"]) return [NSColor colorWithCalibratedRed:0.42 green:1.00 blue:0.94 alpha:0.96];
    if ([tier isEqualToString:@"S"]) return [NSColor colorWithCalibratedRed:1.00 green:0.36 blue:0.42 alpha:0.96];
    if ([tier isEqualToString:@"A"]) return [NSColor colorWithCalibratedRed:1.00 green:0.66 blue:0.22 alpha:0.96];
    if ([tier isEqualToString:@"B"]) return [NSColor colorWithCalibratedRed:1.00 green:0.94 blue:0.24 alpha:0.96];
    if ([tier isEqualToString:@"C"]) return [NSColor colorWithCalibratedRed:0.64 green:1.00 blue:0.30 alpha:0.96];
    return [NSColor colorWithWhite:0.15 alpha:0.96];
}

- (NSColor *)tierInnerColor:(NSString *)tier {
    if ([tier isEqualToString:@"X"]) return [NSColor colorWithCalibratedRed:0.03 green:0.86 blue:0.90 alpha:0.96];
    if ([tier isEqualToString:@"S"]) return [NSColor colorWithCalibratedRed:1.00 green:0.08 blue:0.20 alpha:0.96];
    if ([tier isEqualToString:@"A"]) return [NSColor colorWithCalibratedRed:1.00 green:0.46 blue:0.08 alpha:0.96];
    if ([tier isEqualToString:@"B"]) return [NSColor colorWithCalibratedRed:1.00 green:0.82 blue:0.02 alpha:0.96];
    if ([tier isEqualToString:@"C"]) return [NSColor colorWithCalibratedRed:0.28 green:0.96 blue:0.05 alpha:0.96];
    return [NSColor colorWithWhite:0.28 alpha:0.96];
}

- (void)drawCompBadges:(NSArray *)compBadges centerX:(CGFloat)centerX topY:(CGFloat)topY {
    NSUInteger count = MIN(compBadges.count, 5);
    if (count == 0) {
        return;
    }
    CGFloat scale = MIN(NSWidth(self.bounds) / 1920.0, NSHeight(self.bounds) / 1080.0);
    CGFloat size = 30 * scale;
    CGFloat gap = 6 * scale;
    CGFloat total = count * size + (count - 1) * gap;
    CGFloat startX = centerX - total / 2.0;
    CGFloat y = NSHeight(self.bounds) - topY - size;
    NSPoint mousePoint = [self currentMousePointInView];
    for (NSUInteger i = 0; i < count; i += 1) {
        NSDictionary *badge = compBadges[i];
        NSString *tier = [badge[@"tier"] isKindOfClass:NSString.class] ? badge[@"tier"] : @"";
        NSString *championApiName = [badge[@"championApiName"] isKindOfClass:NSString.class] ? badge[@"championApiName"] : @"";
        NSNumber *cost = [badge[@"cost"] isKindOfClass:NSNumber.class] ? badge[@"cost"] : nil;
        NSRect rect = NSMakeRect(startX + i * (size + gap), y, size, size);
        NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:rect];
        [[NSColor colorWithWhite:0 alpha:0.56] setFill];
        [circle fill];
        NSImage *icon = [self championIconForApiName:championApiName];
        if (icon != nil) {
            [NSGraphicsContext saveGraphicsState];
            [circle addClip];
            [icon drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
            [NSGraphicsContext restoreGraphicsState];
        }
        [[self championCostColor:cost.integerValue] setStroke];
        circle.lineWidth = MAX(2.0, 2.4 * scale);
        [circle stroke];

        BOOL hovered = NSPointInRect(mousePoint, NSInsetRect(rect, -3 * scale, -3 * scale));
        if (hovered) {
            self.hoveredCompBadge = badge;
            self.hoveredCompBadgeRect = rect;
            NSColor *tierColor = [[self tierInnerColor:tier] colorWithAlphaComponent:0.78];
            [tierColor setFill];
            [circle fill];
            [self drawCenteredText:tier inRect:rect size:MAX(12, 14 * scale) weight:NSFontWeightBlack color:[NSColor colorWithWhite:0 alpha:0.86]];
            [[self championCostColor:cost.integerValue] setStroke];
            circle.lineWidth = MAX(2.0, 2.4 * scale);
            [circle stroke];
        }
    }
}

- (NSPoint)currentMousePointInView {
    if (self.mouseScreenPoint.x == CGFLOAT_MIN && self.mouseScreenPoint.y == CGFLOAT_MIN) {
        return NSMakePoint(CGFLOAT_MIN, CGFLOAT_MIN);
    }
    NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
    NSRect frame = screen != nil ? screen.frame : self.window.frame;
    return NSMakePoint(self.mouseScreenPoint.x - NSMinX(frame), self.mouseScreenPoint.y - NSMinY(frame));
}

- (NSColor *)championCostColor:(NSInteger)cost {
    if (cost <= 1) return [NSColor colorWithCalibratedRed:0.62 green:0.66 blue:0.70 alpha:0.96];
    if (cost == 2) return [NSColor colorWithCalibratedRed:0.08 green:0.78 blue:0.36 alpha:0.96];
    if (cost == 3) return [NSColor colorWithCalibratedRed:0.08 green:0.60 blue:1.00 alpha:0.96];
    if (cost == 4) return [NSColor colorWithCalibratedRed:0.66 green:0.30 blue:1.00 alpha:0.96];
    return [NSColor colorWithCalibratedRed:1.00 green:0.75 blue:0.06 alpha:0.96];
}

- (void)drawCompTooltipForBadge:(NSDictionary *)badge anchorRect:(NSRect)anchorRect {
    CGFloat scale = MIN(NSWidth(self.bounds) / 1920.0, NSHeight(self.bounds) / 1080.0);
    NSArray *tips = [badge[@"tips"] isKindOfClass:NSArray.class] ? badge[@"tips"] : @[];
    NSArray *traits = [badge[@"traits"] isKindOfClass:NSArray.class] ? badge[@"traits"] : @[];
    NSUInteger shownTips = MIN(tips.count, 3);
    CGFloat width = 700 * scale;
    CGFloat height = (255 + (traits.count > 0 ? 28 : 0) + MAX(0, (NSInteger)shownTips - 2) * 22) * scale;
    height = MIN(height, 340 * scale);
    CGFloat x = NSMidX(anchorRect) - width / 2.0;
    CGFloat y = NSMaxY(anchorRect) + 18 * scale;
    x = MAX(18 * scale, MIN(x, NSWidth(self.bounds) - width - 18 * scale));
    if (y + height > NSHeight(self.bounds) - 18 * scale) {
        y = NSMinY(anchorRect) - height - 18 * scale;
    }
    y = MAX(18 * scale, y);

    NSRect panel = NSMakeRect(x, y, width, height);
    [self drawPanel:panel fill:[NSColor colorWithWhite:0.02 alpha:0.90]];

    CGFloat sidebarWidth = 190 * scale;
    NSString *tier = [badge[@"tier"] isKindOfClass:NSString.class] ? badge[@"tier"] : @"";
    NSRect sidebar = NSMakeRect(NSMinX(panel), NSMinY(panel), sidebarWidth, NSHeight(panel));
    NSBezierPath *sidebarPath = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(sidebar, 1.5 * scale, 1.5 * scale) xRadius:8 yRadius:8];
    [[[self tierOuterColor:tier] colorWithAlphaComponent:0.82] setFill];
    [sidebarPath fill];
    [[NSColor colorWithWhite:0 alpha:0.24] setFill];
    [sidebarPath fill];

    NSString *championApiName = [badge[@"championApiName"] isKindOfClass:NSString.class] ? badge[@"championApiName"] : @"";
    NSNumber *cost = [badge[@"cost"] isKindOfClass:NSNumber.class] ? badge[@"cost"] : nil;
    NSRect heroIcon = NSMakeRect(NSMidX(sidebar) - 43 * scale, NSMaxY(sidebar) - 112 * scale, 86 * scale, 86 * scale);
    [self drawHexChampionIcon:championApiName inRect:heroIcon borderColor:[self tierInnerColor:tier] fallbackText:tier];

    NSString *title = [badge[@"title"] isKindOfClass:NSString.class] ? badge[@"title"] : @"Comp";
    NSString *style = [badge[@"style"] isKindOfClass:NSString.class] ? badge[@"style"] : @"";
    NSString *difficulty = [badge[@"difficulty"] isKindOfClass:NSString.class] ? badge[@"difficulty"] : @"";
    [self drawText:title.uppercaseString in:NSMakeRect(NSMinX(sidebar) + 14 * scale, NSMaxY(sidebar) - 146 * scale, sidebarWidth - 28 * scale, 28 * scale)
              size:17 * scale weight:NSFontWeightBlack color:NSColor.whiteColor alignment:NSTextAlignmentCenter];
    NSString *meta = [self joinedNonEmpty:@[style.length > 0 ? style : @"Playstyle TBD", difficulty]];
    [self drawText:meta.uppercaseString in:NSMakeRect(NSMinX(sidebar) + 12 * scale, NSMaxY(sidebar) - 170 * scale, sidebarWidth - 24 * scale, 18 * scale)
              size:11 * scale weight:NSFontWeightBold color:[[self tierInnerColor:tier] colorWithAlphaComponent:0.98] alignment:NSTextAlignmentCenter];

    NSRect tierPill = NSMakeRect(NSMidX(sidebar) - 42 * scale, NSMaxY(sidebar) - 204 * scale, 84 * scale, 24 * scale);
    [self drawTierPill:tier inRect:tierPill scale:scale];
    CGFloat traitHeight = traits.count > 0 ? 48 * scale : 22 * scale;
    [self drawTraitList:traits inRect:NSMakeRect(NSMinX(sidebar) + 14 * scale, NSMinY(sidebar) + 38 * scale, sidebarWidth - 28 * scale, traitHeight) scale:scale];

    NSString *costLabel = cost != nil ? [NSString stringWithFormat:@"%ld-cost carry", (long)cost.integerValue] : @"Carry";
    [self drawText:costLabel in:NSMakeRect(NSMinX(sidebar) + 18 * scale, NSMinY(sidebar) + 12 * scale, sidebarWidth - 36 * scale, 18 * scale)
              size:12 * scale weight:NSFontWeightMedium color:[NSColor colorWithWhite:1 alpha:0.76] alignment:NSTextAlignmentCenter];

    CGFloat contentX = NSMaxX(sidebar) + 20 * scale;
    CGFloat contentWidth = NSMaxX(panel) - contentX - 20 * scale;
    [self drawFinalCompRow:[badge[@"finalComp"] isKindOfClass:NSArray.class] ? badge[@"finalComp"] : @[]
                    inRect:NSMakeRect(contentX, NSMaxY(panel) - 74 * scale, contentWidth, 56 * scale)
                     scale:scale];
    [self drawItemPriority:[badge[@"carousel"] isKindOfClass:NSArray.class] ? badge[@"carousel"] : @[]
                    inRect:NSMakeRect(contentX, NSMaxY(panel) - 146 * scale, contentWidth, 60 * scale)
                     scale:scale];
    [self drawCompNotes:tips
                 inRect:NSMakeRect(contentX, NSMinY(panel) + 18 * scale, contentWidth, NSHeight(panel) - 178 * scale)
                  scale:scale];
}

- (void)drawFinalCompRow:(NSArray *)units inRect:(NSRect)rect scale:(CGFloat)scale {
    [self drawText:@"Final Comp" in:NSMakeRect(NSMinX(rect), NSMaxY(rect) - 18 * scale, 120 * scale, 18 * scale)
              size:13 * scale weight:NSFontWeightBold color:[NSColor colorWithWhite:1 alpha:0.78] alignment:NSTextAlignmentLeft];
    CGFloat size = 38 * scale;
    CGFloat gap = 7 * scale;
    CGFloat x = NSMinX(rect);
    CGFloat y = NSMinY(rect) + 8 * scale;
    NSUInteger count = MIN(units.count, 9);
    for (NSUInteger i = 0; i < count; i += 1) {
        NSDictionary *unit = [units[i] isKindOfClass:NSDictionary.class] ? units[i] : nil;
        NSString *apiName = [unit[@"apiName"] isKindOfClass:NSString.class] ? unit[@"apiName"] : @"";
        NSNumber *cost = [unit[@"cost"] isKindOfClass:NSNumber.class] ? unit[@"cost"] : nil;
        NSRect iconRect = NSMakeRect(x + i * (size + gap), y, size, size);
        [self drawHexChampionIcon:apiName inRect:iconRect borderColor:[self championCostColor:cost.integerValue] fallbackText:[self shortNameForApiName:apiName]];
    }
}

- (void)drawItemPriority:(NSArray *)items inRect:(NSRect)rect scale:(CGFloat)scale {
    [self drawText:@"Item Priority" in:NSMakeRect(NSMinX(rect), NSMaxY(rect) - 18 * scale, 130 * scale, 18 * scale)
              size:13 * scale weight:NSFontWeightBold color:[NSColor colorWithWhite:1 alpha:0.78] alignment:NSTextAlignmentLeft];
    CGFloat x = NSMinX(rect);
    CGFloat y = NSMinY(rect);
    CGFloat size = 30 * scale;
    NSUInteger count = MIN(items.count, 5);
    for (NSUInteger i = 0; i < count; i += 1) {
        id itemValue = items[i];
        NSString *apiName = [itemValue isKindOfClass:NSDictionary.class] ? itemValue[@"apiName"] : itemValue;
        NSString *fallback = [self compactItemName:apiName];
        NSRect iconRect = NSMakeRect(x, y, size, size);
        [self drawRoundedItemIcon:apiName inRect:iconRect fallbackText:fallback];
        x = NSMaxX(iconRect) + 10 * scale;
        if (i + 1 < count) {
            [self drawArrowInRect:NSMakeRect(x - 3 * scale, y + 7 * scale, 8 * scale, 16 * scale)];
            x += 13 * scale;
        }
    }
}

- (void)drawCompNotes:(NSArray *)tips inRect:(NSRect)rect scale:(CGFloat)scale {
    [self drawText:@"Tips" in:NSMakeRect(NSMinX(rect), NSMaxY(rect) - 18 * scale, 80 * scale, 18 * scale)
              size:13 * scale weight:NSFontWeightBold color:[NSColor colorWithWhite:1 alpha:0.78] alignment:NSTextAlignmentLeft];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSDictionary *tip in tips) {
        if (![tip isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *body = [tip[@"tip"] isKindOfClass:NSString.class] ? tip[@"tip"] : @"";
        if (body.length > 0) {
            [lines addObject:body];
        }
        if (lines.count >= 3) {
            break;
        }
    }
    NSString *text = lines.count > 0 ? [lines componentsJoinedByString:@"\n"] : @"No notes yet.";
    [self drawWrappedText:text in:NSMakeRect(NSMinX(rect), NSMinY(rect), NSWidth(rect), NSHeight(rect) - 22 * scale)
                    size:11.5 * scale weight:NSFontWeightRegular color:[NSColor colorWithWhite:1 alpha:0.84]];
}

- (void)drawTierPill:(NSString *)tier inRect:(NSRect)rect scale:(CGFloat)scale {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:6 * scale yRadius:6 * scale];
    [[[self tierInnerColor:tier] colorWithAlphaComponent:0.90] setFill];
    [path fill];
    [[NSColor colorWithWhite:1 alpha:0.20] setStroke];
    path.lineWidth = 1;
    [path stroke];
    NSString *label = [NSString stringWithFormat:@"TIER %@", tier.length > 0 ? tier : @"?"];
    [self drawText:label in:NSInsetRect(rect, 8 * scale, 4 * scale) size:11 * scale weight:NSFontWeightBlack color:[NSColor colorWithWhite:0 alpha:0.86] alignment:NSTextAlignmentCenter];
}

- (void)drawTraitList:(NSArray *)traits inRect:(NSRect)rect scale:(CGFloat)scale {
    if (traits.count == 0) {
        [self drawText:@"Traits pending" in:rect size:10 * scale weight:NSFontWeightMedium color:[NSColor colorWithWhite:1 alpha:0.48] alignment:NSTextAlignmentCenter];
        return;
    }

    CGFloat chipWidth = 47 * scale;
    CGFloat chipHeight = 22 * scale;
    CGFloat gap = 5 * scale;
    CGFloat x = NSMinX(rect);
    CGFloat y = NSMaxY(rect) - chipHeight;
    NSUInteger count = MIN(traits.count, 6);
    for (NSUInteger i = 0; i < count; i += 1) {
        NSDictionary *trait = [traits[i] isKindOfClass:NSDictionary.class] ? traits[i] : nil;
        NSString *apiName = [trait[@"apiName"] isKindOfClass:NSString.class] ? trait[@"apiName"] : @"";
        NSNumber *traitCount = [trait[@"count"] isKindOfClass:NSNumber.class] ? trait[@"count"] : nil;
        NSRect chip = NSMakeRect(x, y, chipWidth, chipHeight);
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:chip xRadius:4 * scale yRadius:4 * scale];
        [[NSColor colorWithWhite:1 alpha:0.15] setFill];
        [path fill];
        NSImage *icon = [self traitIconForApiName:apiName];
        if (icon != nil) {
            CGFloat iconSize = 17 * scale;
            NSRect iconRect = NSMakeRect(NSMinX(chip) + 7 * scale, NSMidY(chip) - iconSize / 2.0, iconSize, iconSize);
            [icon drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:0.88 respectFlipped:YES hints:nil];
        } else {
            NSString *fallback = [self traitFallbackTextForApiName:apiName];
            [self drawText:fallback in:NSMakeRect(NSMinX(chip) + 7 * scale, NSMinY(chip) + 4 * scale, 18 * scale, 14 * scale)
                      size:7.5 * scale weight:NSFontWeightBlack color:[NSColor colorWithWhite:1 alpha:0.62] alignment:NSTextAlignmentCenter];
        }
        NSString *label = traitCount != nil ? traitCount.stringValue : @"-";
        [self drawText:label in:NSMakeRect(NSMaxX(chip) - 22 * scale, NSMinY(chip) + 3 * scale, 18 * scale, 16 * scale)
                  size:11 * scale weight:NSFontWeightBlack color:NSColor.whiteColor alignment:NSTextAlignmentCenter];
        x += chipWidth + gap;
        if (x + chipWidth > NSMaxX(rect)) {
            x = NSMinX(rect);
            y -= chipHeight + gap;
        }
    }
}

- (void)drawHexChampionIcon:(NSString *)apiName inRect:(NSRect)rect borderColor:(NSColor *)borderColor fallbackText:(NSString *)fallbackText {
    NSBezierPath *outerHex = [self hexagonPathInRect:rect inset:0];
    [borderColor setFill];
    [outerHex fill];
    NSRect innerRect = NSInsetRect(rect, MAX(2.0, NSWidth(rect) * 0.075), MAX(2.0, NSHeight(rect) * 0.075));
    NSBezierPath *hex = [self hexagonPathInRect:innerRect inset:0];
    [[NSColor colorWithWhite:0.04 alpha:0.94] setFill];
    [hex fill];
    NSImage *icon = [self championIconForApiName:apiName];
    if (icon != nil) {
        [NSGraphicsContext saveGraphicsState];
        [hex addClip];
        [icon drawInRect:innerRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
        [NSGraphicsContext restoreGraphicsState];
    } else {
        [self drawCenteredText:fallbackText inRect:innerRect size:MAX(8, NSWidth(rect) * 0.22) weight:NSFontWeightBold color:[NSColor colorWithWhite:1 alpha:0.80]];
    }
}

- (void)drawRoundedItemIcon:(NSString *)apiName inRect:(NSRect)rect fallbackText:(NSString *)fallbackText {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:6 yRadius:6];
    [[NSColor colorWithWhite:0.03 alpha:0.90] setFill];
    [path fill];
    NSImage *icon = [self itemIconForApiName:apiName];
    if (icon != nil) {
        [NSGraphicsContext saveGraphicsState];
        [path addClip];
        [icon drawInRect:NSInsetRect(rect, 2, 2) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
        [NSGraphicsContext restoreGraphicsState];
    } else {
        [self drawCenteredText:fallbackText inRect:NSInsetRect(rect, 3, 5) size:8.5 weight:NSFontWeightBold color:[NSColor colorWithWhite:1 alpha:0.84]];
    }
    [[NSColor colorWithWhite:1 alpha:0.28] setStroke];
    path.lineWidth = 1.2;
    [path stroke];
}

- (void)drawArrowInRect:(NSRect)rect {
    NSBezierPath *arrow = [NSBezierPath bezierPath];
    [arrow moveToPoint:NSMakePoint(NSMinX(rect), NSMidY(rect))];
    [arrow lineToPoint:NSMakePoint(NSMaxX(rect), NSMidY(rect))];
    [arrow moveToPoint:NSMakePoint(NSMaxX(rect) - 4, NSMaxY(rect))];
    [arrow lineToPoint:NSMakePoint(NSMaxX(rect), NSMidY(rect))];
    [arrow lineToPoint:NSMakePoint(NSMaxX(rect) - 4, NSMinY(rect))];
    [[NSColor colorWithWhite:1 alpha:0.38] setStroke];
    arrow.lineWidth = 1.4;
    [arrow stroke];
}

- (NSString *)joinedNonEmpty:(NSArray<NSString *> *)values {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *value in values) {
        if ([value isKindOfClass:NSString.class] && value.length > 0) {
            [parts addObject:value];
        }
    }
    return [parts componentsJoinedByString:@" | "];
}

- (NSString *)shortNameForApiName:(NSString *)apiName {
    NSString *name = [apiName componentsSeparatedByString:@"_"].lastObject ?: @"";
    return name.length >= 2 ? [[name substringToIndex:2] uppercaseString] : name.uppercaseString;
}

- (NSString *)compactItemName:(NSString *)apiName {
    NSString *name = [apiName componentsSeparatedByString:@"_"].lastObject ?: apiName;
    name = [name stringByReplacingOccurrencesOfString:@"TFTItem" withString:@""];
    name = [name stringByReplacingOccurrencesOfString:@"BFSword" withString:@"BF Sword"];
    name = [name stringByReplacingOccurrencesOfString:@"GiantsBelt" withString:@"Belt"];
    name = [name stringByReplacingOccurrencesOfString:@"NegatronCloak" withString:@"Cloak"];
    name = [name stringByReplacingOccurrencesOfString:@"SparringGloves" withString:@"Gloves"];
    name = [name stringByReplacingOccurrencesOfString:@"RecurveBow" withString:@"Bow"];
    name = [name stringByReplacingOccurrencesOfString:@"NeedlesslyLargeRod" withString:@"Rod"];
    name = [name stringByReplacingOccurrencesOfString:@"TearOfTheGoddess" withString:@"Tear"];
    name = [name stringByReplacingOccurrencesOfString:@"ChainVest" withString:@"Vest"];
    name = [name stringByReplacingOccurrencesOfString:@"GargoyleStoneplate" withString:@"Stoneplate"];
    name = [name stringByReplacingOccurrencesOfString:@"RabadonsDeathcap" withString:@"Deathcap"];
    name = [name stringByReplacingOccurrencesOfString:@"StatikkShiv" withString:@"Shiv"];
    name = [name stringByReplacingOccurrencesOfString:@"GuinsoosRageblade" withString:@"Guinsoo"];
    name = [name stringByReplacingOccurrencesOfString:@"InfinityEdge" withString:@"IE"];
    name = [name stringByReplacingOccurrencesOfString:@"LastWhisper" withString:@"LW"];
    name = [name stringByReplacingOccurrencesOfString:@"SpearOfShojin" withString:@"Shojin"];
    name = [name stringByReplacingOccurrencesOfString:@"JeweledGauntlet" withString:@"JG"];
    return name.length > 0 ? name : @"Item";
}

- (NSString *)traitFallbackTextForApiName:(NSString *)apiName {
    NSString *clean = [[apiName ?: @"" stringByReplacingOccurrencesOfString:@"TFT17_" withString:@""] stringByReplacingOccurrencesOfString:@"Trait" withString:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@"[^A-Za-z0-9]" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, clean.length)];
    if (clean.length == 0) {
        return @"?";
    }
    return [clean substringToIndex:MIN((NSUInteger)2, clean.length)].uppercaseString;
}

- (NSImage *)championIconForApiName:(NSString *)apiName {
    return [self iconForApiName:apiName subdirectory:@"champions"];
}

- (NSImage *)itemIconForApiName:(NSString *)apiName {
    return [self iconForApiName:apiName subdirectory:@"items"];
}

- (NSImage *)traitIconForApiName:(NSString *)apiName {
    return [self iconForApiName:apiName subdirectory:@"traits"];
}

- (NSImage *)iconForApiName:(NSString *)apiName subdirectory:(NSString *)subdirectory {
    if (apiName.length == 0) {
        return nil;
    }

    static NSMutableDictionary<NSString *, id> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });

    NSString *cacheKey = [NSString stringWithFormat:@"%@/%@", subdirectory ?: @"", apiName];
    id cached = cache[cacheKey];
    if (cached != nil) {
        return [cached isKindOfClass:NSImage.class] ? cached : nil;
    }

    NSURL *url = nil;
    for (NSString *extension in @[@"webp", @"png", @"jpg", @"jpeg"]) {
        url = [NSBundle.mainBundle URLForResource:apiName withExtension:extension subdirectory:subdirectory];
        if (url != nil) {
            break;
        }
    }
    NSImage *image = url != nil ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    cache[cacheKey] = image ?: (id)NSNull.null;
    return image;
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

- (void)drawWrappedText:(NSString *)text in:(NSRect)rect size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentLeft;
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.lineSpacing = 2;

    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:size weight:weight],
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: paragraph
    };
    [text drawInRect:rect withAttributes:attributes];
}

- (void)drawCenteredText:(NSString *)text inRect:(NSRect)rect size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    if (text.length == 0) {
        return;
    }

    NSFont *font = [NSFont systemFontOfSize:size weight:weight];
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color
    };
    NSSize textSize = [text sizeWithAttributes:attributes];
    NSPoint point = NSMakePoint(NSMidX(rect) - textSize.width / 2.0,
                                NSMidY(rect) - textSize.height / 2.0);
    [text drawAtPoint:point withAttributes:attributes];
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

@interface CalibrationBoxView : NSView
@property(nonatomic) NSPoint dragStartScreenPoint;
@property(nonatomic) NSRect dragStartFrame;
@property(nonatomic) NSInteger dragEdges;
@end

@implementation CalibrationBoxView
- (BOOL)isOpaque {
    return NO;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = self.bounds;
    NSBezierPath *fill = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 2, 2) xRadius:6 yRadius:6];
    [[NSColor colorWithCalibratedRed:0.05 green:0.75 blue:1.0 alpha:0.10] setFill];
    [fill fill];

    NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 2, 2) xRadius:6 yRadius:6];
    [[NSColor colorWithCalibratedRed:0.05 green:0.85 blue:1.0 alpha:0.95] setStroke];
    border.lineWidth = 3;
    [border stroke];

    CGFloat handleSize = 10;
    NSArray<NSValue *> *handles = @[
        [NSValue valueWithRect:NSMakeRect(NSMinX(bounds) + 4, NSMinY(bounds) + 4, handleSize, handleSize)],
        [NSValue valueWithRect:NSMakeRect(NSMidX(bounds) - handleSize / 2.0, NSMinY(bounds) + 4, handleSize, handleSize)],
        [NSValue valueWithRect:NSMakeRect(NSMaxX(bounds) - handleSize - 4, NSMinY(bounds) + 4, handleSize, handleSize)],
        [NSValue valueWithRect:NSMakeRect(NSMinX(bounds) + 4, NSMidY(bounds) - handleSize / 2.0, handleSize, handleSize)],
        [NSValue valueWithRect:NSMakeRect(NSMaxX(bounds) - handleSize - 4, NSMidY(bounds) - handleSize / 2.0, handleSize, handleSize)],
        [NSValue valueWithRect:NSMakeRect(NSMinX(bounds) + 4, NSMaxY(bounds) - handleSize - 4, handleSize, handleSize)],
        [NSValue valueWithRect:NSMakeRect(NSMidX(bounds) - handleSize / 2.0, NSMaxY(bounds) - handleSize - 4, handleSize, handleSize)],
        [NSValue valueWithRect:NSMakeRect(NSMaxX(bounds) - handleSize - 4, NSMaxY(bounds) - handleSize - 4, handleSize, handleSize)]
    ];
    [[NSColor colorWithCalibratedRed:0.05 green:0.85 blue:1.0 alpha:0.88] setFill];
    for (NSValue *handle in handles) {
        [[NSBezierPath bezierPathWithRoundedRect:handle.rectValue xRadius:2 yRadius:2] fill];
    }

    NSString *label = @"Drag or resize. Press Cmd-N to save.";
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter;
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: NSColor.whiteColor,
        NSParagraphStyleAttributeName: paragraph
    };
    [label drawInRect:NSMakeRect(8, NSMidY(bounds) - 10, NSWidth(bounds) - 16, 20) withAttributes:attributes];
}

- (void)mouseDown:(NSEvent *)event {
    self.dragStartScreenPoint = NSEvent.mouseLocation;
    self.dragStartFrame = self.window.frame;
    self.dragEdges = [self resizeEdgesForPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint current = NSEvent.mouseLocation;
    CGFloat dx = current.x - self.dragStartScreenPoint.x;
    CGFloat dy = current.y - self.dragStartScreenPoint.y;
    NSRect frame = self.dragStartFrame;
    CGFloat minSize = 36;

    if (self.dragEdges == 0) {
        frame.origin.x += dx;
        frame.origin.y += dy;
    } else {
        if (self.dragEdges & 1) {
            CGFloat newMinX = MIN(NSMaxX(frame) - minSize, NSMinX(frame) + dx);
            frame.size.width = NSMaxX(frame) - newMinX;
            frame.origin.x = newMinX;
        }
        if (self.dragEdges & 2) {
            frame.size.width = MAX(minSize, NSWidth(frame) + dx);
        }
        if (self.dragEdges & 4) {
            CGFloat newMinY = MIN(NSMaxY(frame) - minSize, NSMinY(frame) + dy);
            frame.size.height = NSMaxY(frame) - newMinY;
            frame.origin.y = newMinY;
        }
        if (self.dragEdges & 8) {
            frame.size.height = MAX(minSize, NSHeight(frame) + dy);
        }
    }

    [self.window setFrame:frame display:YES];
}

- (NSInteger)resizeEdgesForPoint:(NSPoint)point {
    CGFloat margin = 16;
    NSInteger edges = 0;
    if (point.x <= margin) {
        edges |= 1;
    } else if (point.x >= NSWidth(self.bounds) - margin) {
        edges |= 2;
    }
    if (point.y <= margin) {
        edges |= 4;
    } else if (point.y >= NSHeight(self.bounds) - margin) {
        edges |= 8;
    }
    return edges;
}
@end

@interface CalibrationBoxWindow : NSPanel
@end

@implementation CalibrationBoxWindow
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithContentRect:frame
                            styleMask:NSWindowStyleMaskBorderless
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        CalibrationBoxView *boxView = [[CalibrationBoxView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame))];
        boxView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.contentView = boxView;
        self.opaque = NO;
        self.backgroundColor = NSColor.clearColor;
        self.hasShadow = NO;
        self.ignoresMouseEvents = NO;
        self.acceptsMouseMovedEvents = YES;
        self.movableByWindowBackground = YES;
        self.releasedWhenClosed = NO;
        self.hidesOnDeactivate = NO;
        self.floatingPanel = YES;
        self.level = NSScreenSaverWindowLevel + 1;
        self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorFullScreenAuxiliary |
            NSWindowCollectionBehaviorStationary;
    }
    return self;
}

- (BOOL)canBecomeKeyWindow {
    return YES;
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
        @"/lol-gameflow/v1/session",
        @"/lol-summoner/v1/current-summoner"
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

@interface VisionProbeRegion : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic) CGRect baseRect;
@property(nonatomic, copy) NSString *horizontalAnchor;
@property(nonatomic, copy) NSString *verticalAnchor;
+ (instancetype)regionWithIdentifier:(NSString *)identifier x1:(CGFloat)x1 y1:(CGFloat)y1 x2:(CGFloat)x2 y2:(CGFloat)y2 horizontal:(NSString *)horizontal vertical:(NSString *)vertical;
@end

@implementation VisionProbeRegion
+ (instancetype)regionWithIdentifier:(NSString *)identifier x1:(CGFloat)x1 y1:(CGFloat)y1 x2:(CGFloat)x2 y2:(CGFloat)y2 horizontal:(NSString *)horizontal vertical:(NSString *)vertical {
    VisionProbeRegion *region = [VisionProbeRegion new];
    region.identifier = identifier;
    region.baseRect = CGRectMake(x1, y1, x2 - x1, y2 - y1);
    region.horizontalAnchor = horizontal ?: @"left";
    region.verticalAnchor = vertical ?: @"top";
    return region;
}
@end

@interface VisionProbeReader : NSObject
@property(nonatomic, strong) NSArray<VisionProbeRegion *> *regions;
@property(nonatomic, strong) NSArray<NSDictionary *> *knownTraitNames;
@property(nonatomic, strong) NSArray<NSDictionary *> *knownChampionNames;
@property(nonatomic, strong) NSDictionary *lastValidTraitList;
@property(nonatomic, strong) NSDictionary *lastValidTraitRegion;
@property(nonatomic, strong) NSDictionary *lastTraitOCRProfile;
@property(nonatomic) BOOL traitOCRInFlight;
@property(nonatomic) NSUInteger captureIndex;
- (NSDictionary *)captureSnapshotInLogDirectory:(NSURL *)logDirectoryURL;
- (NSDictionary *)saveManualSnapshotInLogDirectory:(NSURL *)logDirectoryURL;
@end

@implementation VisionProbeReader
- (instancetype)init {
    self = [super init];
    if (self) {
        _regions = @[
            [VisionProbeRegion regionWithIdentifier:@"trait_list" x1:55 y1:240 x2:285 y2:850 horizontal:@"left" vertical:@"center"],
            [VisionProbeRegion regionWithIdentifier:@"augment_1" x1:417 y1:552 x2:687 y2:582 horizontal:@"center" vertical:@"center"],
            [VisionProbeRegion regionWithIdentifier:@"augment_2" x1:825 y1:552 x2:1095 y2:582 horizontal:@"center" vertical:@"center"],
            [VisionProbeRegion regionWithIdentifier:@"augment_3" x1:1230 y1:552 x2:1500 y2:582 horizontal:@"center" vertical:@"center"],
            [VisionProbeRegion regionWithIdentifier:@"god_boon_1" x1:697.3 y1:382.7 x2:802.8 y2:422.5 horizontal:@"center" vertical:@"center"],
            [VisionProbeRegion regionWithIdentifier:@"god_boon_2" x1:1113.8 y1:384.6 x2:1205.9 y2:420.5 horizontal:@"center" vertical:@"center"],
            [VisionProbeRegion regionWithIdentifier:@"unit_name" x1:1686.5 y1:330.0 x2:1851.5 y2:356.0 horizontal:@"right" vertical:@"center"]
        ];
        _knownTraitNames = [self loadKnownTraitNames];
        _knownChampionNames = [self loadKnownChampionNames];
    }
    return self;
}

- (NSDictionary *)captureSnapshotInLogDirectory:(NSURL *)logDirectoryURL {
    self.captureIndex += 1;

    NSDictionary *windowInfo = [self leagueWindowInfo];
    if (windowInfo == nil) {
        return [self captureFullDisplaySnapshotInLogDirectory:logDirectoryURL reason:@"League game window not found; using full display fallback."];
    }

    NSNumber *windowNumber = windowInfo[(NSString *)kCGWindowNumber];
    CGImageRef windowImage = [self captureWindowImageForWindowNumber:windowNumber logDirectory:logDirectoryURL];
    if (windowImage == NULL) {
        NSMutableDictionary *fallback = [[self captureFullDisplaySnapshotInLogDirectory:logDirectoryURL reason:@"Window capture failed; using full display fallback."] mutableCopy];
        fallback[@"window"] = [self publicWindowDictionary:windowInfo];
        return fallback;
    }

    NSDictionary *snapshot = [self recognizedSnapshotForImage:windowImage logDirectory:logDirectoryURL source:@"window" reason:nil windowInfo:windowInfo];
    CGImageRelease(windowImage);
    return snapshot;
}

- (NSDictionary *)captureFullDisplaySnapshotInLogDirectory:(NSURL *)logDirectoryURL reason:(NSString *)reason {
    CGImageRef image = [self captureFullDisplayImageInLogDirectory:logDirectoryURL];
    if (image == NULL) {
        return @{
            @"attempted": @YES,
            @"available": @NO,
            @"source": @"display",
            @"error": @"Display capture failed. macOS Screen Recording permission may be required.",
            @"reason": reason ?: @"",
            @"regions": @[]
        };
    }

    NSDictionary *snapshot = [self recognizedSnapshotForImage:image logDirectory:logDirectoryURL source:@"display" reason:reason windowInfo:nil];
    CGImageRelease(image);
    return snapshot;
}

- (NSDictionary *)saveManualSnapshotInLogDirectory:(NSURL *)logDirectoryURL {
    NSURL *snapshotDirectory = [logDirectoryURL URLByAppendingPathComponent:@"ManualSnapshots" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:snapshotDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd_HH-mm-ss-SSS";
    NSString *stamp = [formatter stringFromDate:NSDate.date];
    NSURL *imageURL = [snapshotDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"manual-snapshot-%@.png", stamp]];
    NSURL *metadataURL = [snapshotDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"manual-snapshot-%@.json", stamp]];

    NSString *source = @"window";
    NSString *reason = @"";
    NSDictionary *windowInfo = [self leagueWindowInfo];
    BOOL captured = NO;
    if (windowInfo != nil) {
        NSNumber *windowNumber = windowInfo[(NSString *)kCGWindowNumber];
        captured = [self runScreencaptureWithArguments:@[@"-x", @"-l", windowNumber.stringValue, imageURL.path]];
    }
    if (!captured) {
        source = @"display";
        reason = windowInfo == nil ? @"League game window not found; captured full display." : @"Window capture failed; captured full display.";
        captured = [self runScreencaptureWithArguments:@[@"-x", imageURL.path]];
    }

    NSMutableDictionary *record = [@{
        @"type": @"MANUAL_SNAPSHOT",
        @"prefix": @"@@TFT_OVERLAY_MANUAL_SNAPSHOT@@",
        @"timestamp": [self isoTimestamp],
        @"captured": @(captured),
        @"source": source,
        @"reason": reason,
        @"imagePath": captured ? imageURL.path : @"",
        @"metadataPath": metadataURL.path
    } mutableCopy];

    if (windowInfo != nil) {
        record[@"window"] = [self publicWindowDictionary:windowInfo];
    }

    if (captured) {
        NSImage *image = [[NSImage alloc] initWithContentsOfURL:imageURL];
        CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
        if (cgImage != NULL) {
            CGFloat contentTopInset = [source isEqualToString:@"window"] ? [self detectedTopContentInsetForImage:cgImage] : 0;
            record[@"image"] = @{
                @"width": @((NSInteger)CGImageGetWidth(cgImage)),
                @"height": @((NSInteger)CGImageGetHeight(cgImage)),
                @"contentTopInset": @((NSInteger)contentTopInset)
            };
        }
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:nil];
    if (json.length > 0) {
        [json writeToURL:metadataURL atomically:YES];
    }
    return record;
}

- (BOOL)runScreencaptureWithArguments:(NSArray<NSString *> *)arguments {
    NSTask *task = [NSTask new];
    task.launchPath = @"/usr/sbin/screencapture";
    task.arguments = arguments;
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        return NO;
    }
    return task.terminationStatus == 0;
}

- (NSString *)isoTimestamp {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    return [formatter stringFromDate:NSDate.date];
}

- (NSDictionary *)recognizedSnapshotForImage:(CGImageRef)image
                                logDirectory:(NSURL *)logDirectoryURL
                                      source:(NSString *)source
                                      reason:(NSString *)reason
                                  windowInfo:(NSDictionary *)windowInfo {
    size_t imageWidth = CGImageGetWidth(image);
    size_t imageHeight = CGImageGetHeight(image);
    CGFloat contentTopInset = [source isEqualToString:@"window"] ? [self detectedTopContentInsetForImage:image] : 0;
    CGFloat scaleX = (CGFloat)imageWidth / 1920.0;
    CGFloat scaleY = ((CGFloat)imageHeight - contentTopInset) / 1080.0;
    BOOL shouldSaveCrops = self.captureIndex <= 3 || self.captureIndex % 10 == 0;
    NSDictionary *unitPanelColors = [self unitPanelColorSamplesForImage:image contentTopInset:contentTopInset scaleX:scaleX scaleY:scaleY];
    BOOL shouldOCRUnitName = [unitPanelColors[@"detected"] boolValue];
    NSDictionary *augmentOfferColors = [self augmentOfferColorSamplesForImage:image contentTopInset:contentTopInset scaleX:scaleX scaleY:scaleY];
    NSDictionary *godBoonOfferColors = [self godBoonOfferColorSamplesForImage:image contentTopInset:contentTopInset scaleX:scaleX scaleY:scaleY];

    NSMutableArray *regionResults = [NSMutableArray array];
    dispatch_group_t ocrGroup = dispatch_group_create();
    dispatch_queue_t ocrQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    for (VisionProbeRegion *region in self.regions) {
        if ([region.identifier isEqualToString:@"trait_list"]) {
            continue;
        }
        if ([region.identifier isEqualToString:@"unit_name"] && !shouldOCRUnitName) {
            continue;
        }
        if ([region.identifier hasPrefix:@"augment_"] && ![self shouldOCRAugmentRegion:region.identifier colorSamples:augmentOfferColors]) {
            continue;
        }
        if ([region.identifier hasPrefix:@"god_boon_"] && ![self shouldOCRGodBoonRegion:region.identifier colorSamples:godBoonOfferColors]) {
            continue;
        }
        dispatch_group_async(ocrGroup, ocrQueue, ^{
            @autoreleasepool {
                CGRect cropRect = [self cropRectForRegion:region imageWidth:imageWidth imageHeight:imageHeight contentTopInset:contentTopInset scaleX:scaleX scaleY:scaleY];
                cropRect = CGRectIntersection(cropRect, CGRectMake(0, 0, imageWidth, imageHeight));
                if (CGRectIsNull(cropRect) || cropRect.size.width < 2 || cropRect.size.height < 2) {
                    return;
                }

                CGImageRef crop = CGImageCreateWithImageInRect(image, cropRect);
                if (crop == NULL) {
                    return;
                }

                CGImageRef ocrImage = crop;
                CGImageRef filteredCrop = NULL;
                CGImageRef grayFilteredCrop = NULL;
                if ([region.identifier isEqualToString:@"trait_list"]) {
                    filteredCrop = [self whiteTextFilteredImageFromImage:crop];
                    grayFilteredCrop = [self grayTextFilteredImageFromImage:crop];
                }

                BOOL fastOCR = [region.identifier isEqualToString:@"trait_list"];
                NSMutableDictionary *regionResult = [[self recognizedTextForImage:ocrImage fast:fastOCR] mutableCopy];
                NSString *traitGrayText = nil;
                NSArray *traitGrayCandidates = nil;
                if (grayFilteredCrop != NULL) {
                    NSDictionary *grayResult = [self recognizedTextForImage:grayFilteredCrop fast:YES];
                    NSString *grayText = [grayResult[@"text"] isKindOfClass:NSString.class] ? grayResult[@"text"] : @"";
                    NSArray *grayCandidates = [grayResult[@"candidates"] isKindOfClass:NSArray.class] ? grayResult[@"candidates"] : @[];
                    if (grayText.length == 0 && grayCandidates.count == 0) {
                        grayResult = [self recognizedTextForImage:crop fast:YES];
                    }
                    traitGrayText = [grayResult[@"text"] isKindOfClass:NSString.class] ? grayResult[@"text"] : @"";
                    traitGrayCandidates = [grayResult[@"candidates"] isKindOfClass:NSArray.class] ? grayResult[@"candidates"] : @[];
                    regionResult[@"grayText"] = traitGrayText;
                    regionResult[@"grayCandidates"] = traitGrayCandidates;
                }
                if ([region.identifier isEqualToString:@"trait_list"]) {
                    NSString *text = [regionResult[@"text"] isKindOfClass:NSString.class] ? regionResult[@"text"] : @"";
                    NSArray *candidates = [regionResult[@"candidates"] isKindOfClass:NSArray.class] ? regionResult[@"candidates"] : @[];
                    BOOL shouldRefreshSparseTraitOCR = (text.length < 18 || candidates.count < 6) && (self.captureIndex <= 3 || self.captureIndex % 5 == 0);
                    if (shouldRefreshSparseTraitOCR) {
                        regionResult = [[self recognizedTextForImage:crop fast:NO] mutableCopy];
                        regionResult[@"grayText"] = traitGrayText ?: @"";
                        regionResult[@"grayCandidates"] = traitGrayCandidates ?: @[];
                    }
                }
                regionResult[@"id"] = region.identifier;
                NSString *cleanText = [self cleanTextForRegion:region.identifier recognizedResult:regionResult];
                if (cleanText.length > 0) {
                    regionResult[@"cleanText"] = cleanText;
                }
                regionResult[@"crop"] = @{
                    @"x": @((NSInteger)cropRect.origin.x),
                    @"y": @((NSInteger)cropRect.origin.y),
                    @"width": @((NSInteger)cropRect.size.width),
                    @"height": @((NSInteger)cropRect.size.height)
                };

                if (shouldSaveCrops) {
                    NSString *path = [self saveCrop:crop identifier:region.identifier logDirectory:logDirectoryURL];
                    if (path.length > 0) {
                        regionResult[@"imagePath"] = path;
                    }
                    if (filteredCrop != NULL) {
                        NSString *filteredPath = [self saveCrop:filteredCrop identifier:[NSString stringWithFormat:@"%@_white", region.identifier] logDirectory:logDirectoryURL];
                        if (filteredPath.length > 0) {
                            regionResult[@"filteredImagePath"] = filteredPath;
                        }
                    }
                    if (grayFilteredCrop != NULL) {
                        NSString *grayPath = [self saveCrop:grayFilteredCrop identifier:[NSString stringWithFormat:@"%@_gray", region.identifier] logDirectory:logDirectoryURL];
                        if (grayPath.length > 0) {
                            regionResult[@"grayFilteredImagePath"] = grayPath;
                        }
                    }
                }

                @synchronized (regionResults) {
                    [regionResults addObject:regionResult];
                }
                if (filteredCrop != NULL) {
                    CGImageRelease(filteredCrop);
                }
                if (grayFilteredCrop != NULL) {
                    CGImageRelease(grayFilteredCrop);
                }
                CGImageRelease(crop);
            }
        });
    }
    dispatch_group_wait(ocrGroup, DISPATCH_TIME_FOREVER);

    [self scheduleTraitOCRForImage:image
                      logDirectory:logDirectoryURL
                      imageWidth:imageWidth
                     imageHeight:imageHeight
                contentTopInset:contentTopInset
                         scaleX:scaleX
                         scaleY:scaleY
                   shouldSaveCrop:shouldSaveCrops];

    NSDictionary *cachedTraitRegion = nil;
    NSDictionary *cachedTraitList = nil;
    NSDictionary *cachedTraitProfile = nil;
    @synchronized (self) {
        cachedTraitRegion = self.lastValidTraitRegion;
        cachedTraitList = self.lastValidTraitList;
        cachedTraitProfile = self.lastTraitOCRProfile;
    }
    if (cachedTraitRegion != nil) {
        [regionResults addObject:cachedTraitRegion];
    }

    NSDictionary *unitPanel = [self unitPanelDetectionForRegions:regionResults colors:unitPanelColors];
    NSDictionary *traitList = cachedTraitList ?: @{@"detected": @NO, @"traits": @[], @"partialTraits": @[], @"source": @"pending"};

    NSMutableDictionary *snapshot = [@{
        @"attempted": @YES,
        @"available": @YES,
        @"source": source ?: @"unknown",
        @"captureIndex": @(self.captureIndex),
        @"savedCrops": @(shouldSaveCrops),
        @"image": @{
            @"width": @((NSInteger)imageWidth),
            @"height": @((NSInteger)imageHeight),
            @"contentTopInset": @((NSInteger)contentTopInset)
        },
        @"regions": regionResults
    } mutableCopy];
    snapshot[@"unitPanel"] = unitPanel ?: @{};
    snapshot[@"traitList"] = traitList ?: @{};
    snapshot[@"traitOCR"] = cachedTraitProfile ?: @{@"inFlight": @(self.traitOCRInFlight)};
    snapshot[@"augmentColor"] = augmentOfferColors ?: @{};
    snapshot[@"godBoonColor"] = godBoonOfferColors ?: @{};
    if (reason.length > 0) {
        snapshot[@"reason"] = reason;
    }
    if (windowInfo != nil) {
        snapshot[@"window"] = [self publicWindowDictionary:windowInfo];
    }
    return snapshot;
}

- (void)scheduleTraitOCRForImage:(CGImageRef)image
                     logDirectory:(NSURL *)logDirectoryURL
                       imageWidth:(CGFloat)imageWidth
                      imageHeight:(CGFloat)imageHeight
                   contentTopInset:(CGFloat)contentTopInset
                            scaleX:(CGFloat)scaleX
                            scaleY:(CGFloat)scaleY
                    shouldSaveCrop:(BOOL)shouldSaveCrop {
    VisionProbeRegion *traitRegion = nil;
    for (VisionProbeRegion *region in self.regions) {
        if ([region.identifier isEqualToString:@"trait_list"]) {
            traitRegion = region;
            break;
        }
    }
    if (traitRegion == nil) {
        return;
    }

    BOOL shouldRun = NO;
    @synchronized (self) {
        BOOL hasCachedTraits = [self.lastValidTraitList[@"detected"] boolValue];
        shouldRun = !self.traitOCRInFlight && (!hasCachedTraits || self.captureIndex <= 3 || self.captureIndex % 5 == 0);
        if (shouldRun) {
            self.traitOCRInFlight = YES;
        }
    }
    if (!shouldRun) {
        return;
    }

    CGRect cropRect = [self cropRectForRegion:traitRegion imageWidth:imageWidth imageHeight:imageHeight contentTopInset:contentTopInset scaleX:scaleX scaleY:scaleY];
    cropRect = CGRectIntersection(cropRect, CGRectMake(0, 0, imageWidth, imageHeight));
    if (CGRectIsNull(cropRect) || cropRect.size.width < 2 || cropRect.size.height < 2) {
        @synchronized (self) {
            self.traitOCRInFlight = NO;
        }
        return;
    }

    CGImageRef crop = CGImageCreateWithImageInRect(image, cropRect);
    if (crop == NULL) {
        @synchronized (self) {
            self.traitOCRInFlight = NO;
        }
        return;
    }

    NSUInteger captureIndex = self.captureIndex;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            NSMutableDictionary *regionResult = [[self recognizedTextForImage:crop fast:NO] mutableCopy];
            NSString *rawText = [regionResult[@"text"] isKindOfClass:NSString.class] ? regionResult[@"text"] : @"";
            NSArray *candidates = [regionResult[@"candidates"] isKindOfClass:NSArray.class] ? regionResult[@"candidates"] : @[];
            regionResult[@"id"] = @"trait_list";
            regionResult[@"grayText"] = rawText ?: @"";
            regionResult[@"grayCandidates"] = candidates ?: @[];
            regionResult[@"crop"] = @{
                @"x": @((NSInteger)cropRect.origin.x),
                @"y": @((NSInteger)cropRect.origin.y),
                @"width": @((NSInteger)cropRect.size.width),
                @"height": @((NSInteger)cropRect.size.height)
            };
            if (shouldSaveCrop) {
                NSString *path = [self saveCrop:crop identifier:@"trait_list" logDirectory:logDirectoryURL];
                if (path.length > 0) {
                    regionResult[@"imagePath"] = path;
                }
            }

            NSDictionary *traitList = [self traitListDetectionForRegions:@[regionResult]];
            BOOL hasActive = [[traitList[@"traits"] isKindOfClass:NSArray.class] ? traitList[@"traits"] : @[] count] > 0;
            BOOL hasPartial = [[traitList[@"partialTraits"] isKindOfClass:NSArray.class] ? traitList[@"partialTraits"] : @[] count] > 0;
            NSTimeInterval elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0;

            @synchronized (self) {
                if (hasActive || hasPartial) {
                    NSMutableDictionary *traitListCopy = [traitList mutableCopy];
                    traitListCopy[@"source"] = @"accurate-cache";
                    traitListCopy[@"captureIndex"] = @(captureIndex);
                    self.lastValidTraitList = [traitListCopy copy];
                    self.lastValidTraitRegion = [regionResult copy];
                }
                self.lastTraitOCRProfile = @{
                    @"inFlight": @NO,
                    @"captureIndex": @(captureIndex),
                    @"elapsedMs": @(elapsedMs),
                    @"updated": @(hasActive || hasPartial),
                    @"activeCount": @(hasActive ? [[traitList[@"traits"] isKindOfClass:NSArray.class] ? traitList[@"traits"] : @[] count] : 0),
                    @"partialCount": @(hasPartial ? [[traitList[@"partialTraits"] isKindOfClass:NSArray.class] ? traitList[@"partialTraits"] : @[] count] : 0)
                };
                self.traitOCRInFlight = NO;
            }
            CGImageRelease(crop);
        }
    });
}

- (CGRect)cropRectForRegion:(VisionProbeRegion *)region imageWidth:(CGFloat)imageWidth imageHeight:(CGFloat)imageHeight contentTopInset:(CGFloat)contentTopInset scaleX:(CGFloat)scaleX scaleY:(CGFloat)scaleY {
    CGFloat contentHeight = imageHeight - contentTopInset;
    CGFloat width = CGRectGetWidth(region.baseRect) * scaleX;
    CGFloat height = CGRectGetHeight(region.baseRect) * scaleY;
    CGFloat baseMinX = CGRectGetMinX(region.baseRect);
    CGFloat baseMaxX = CGRectGetMaxX(region.baseRect);
    CGFloat baseMidX = CGRectGetMidX(region.baseRect);
    CGFloat baseMinY = CGRectGetMinY(region.baseRect);
    CGFloat baseMaxY = CGRectGetMaxY(region.baseRect);
    CGFloat baseMidY = CGRectGetMidY(region.baseRect);

    CGFloat x = 0;
    if ([region.horizontalAnchor isEqualToString:@"center"]) {
        x = imageWidth / 2.0 + (baseMidX - 960.0) * scaleX - width / 2.0;
    } else if ([region.horizontalAnchor isEqualToString:@"right"]) {
        x = imageWidth - (1920.0 - baseMaxX) * scaleX - width;
    } else {
        x = baseMinX * scaleX;
    }

    CGFloat y = 0;
    if ([region.verticalAnchor isEqualToString:@"center"]) {
        y = contentTopInset + contentHeight / 2.0 + (baseMidY - 540.0) * scaleY - height / 2.0;
    } else if ([region.verticalAnchor isEqualToString:@"bottom"]) {
        y = contentTopInset + contentHeight - (1080.0 - baseMaxY) * scaleY - height;
    } else {
        y = contentTopInset + baseMinY * scaleY;
    }

    return CGRectMake(round(x), round(y), round(width), round(height));
}

- (NSString *)cleanTextForRegion:(NSString *)regionID recognizedResult:(NSDictionary *)result {
    NSString *rawText = [result[@"text"] isKindOfClass:NSString.class] ? result[@"text"] : @"";
    NSArray *candidates = [result[@"candidates"] isKindOfClass:NSArray.class] ? result[@"candidates"] : @[];

    if ([regionID hasPrefix:@"shop_"]) {
        for (NSDictionary *candidate in [candidates reverseObjectEnumerator]) {
            NSString *text = [candidate[@"text"] isKindOfClass:NSString.class] ? candidate[@"text"] : @"";
            if ([self containsLetter:text] && [self normalizedAlphaText:text].length >= 3) {
                return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            }
        }
        return [self containsLetter:rawText] ? rawText : @"";
    }

    if ([regionID isEqualToString:@"stage"]) {
        return [self firstRegexMatch:@"[0-9]-[0-9]" inString:rawText] ?: rawText;
    }

    if ([regionID isEqualToString:@"gold"] || [regionID isEqualToString:@"level"]) {
        return [self firstRegexMatch:@"[0-9]+" inString:rawText] ?: rawText;
    }

    if ([regionID isEqualToString:@"xp"]) {
        return [self firstRegexMatch:@"[0-9]+\\s*/\\s*[0-9]+" inString:rawText] ?: rawText;
    }

    if ([regionID isEqualToString:@"unit_name"]) {
        for (NSDictionary *candidate in candidates) {
            NSString *text = [candidate[@"text"] isKindOfClass:NSString.class] ? candidate[@"text"] : @"";
            NSString *cleaned = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if ([self containsLetter:cleaned] && [self normalizedAlphaText:cleaned].length >= 3) {
                return cleaned;
            }
        }
        return [self containsLetter:rawText] ? rawText : @"";
    }

    if ([regionID isEqualToString:@"trait_list"]) {
        return rawText;
    }

    return rawText;
}

- (NSDictionary *)traitListDetectionForRegions:(NSArray *)regions {
    NSDictionary *traitRegion = nil;
    for (NSDictionary *region in regions) {
        if ([region isKindOfClass:NSDictionary.class] && [region[@"id"] isEqualToString:@"trait_list"]) {
            traitRegion = region;
            break;
        }
    }
    if (traitRegion == nil) {
        return @{@"detected": @NO, @"traits": @[]};
    }

    NSArray *candidates = [traitRegion[@"candidates"] isKindOfClass:NSArray.class] ? traitRegion[@"candidates"] : @[];
    NSMutableArray<NSDictionary *> *tokens = [NSMutableArray array];
    for (NSDictionary *candidate in candidates) {
        if (![candidate isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *text = [candidate[@"text"] isKindOfClass:NSString.class] ? candidate[@"text"] : @"";
        text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length == 0 || (![self containsLetter:text] && [self firstRegexMatch:@"[0-9]" inString:text] == nil)) {
            continue;
        }
        NSDictionary *bbox = [candidate[@"bbox"] isKindOfClass:NSDictionary.class] ? candidate[@"bbox"] : @{};
        NSNumber *x = [bbox[@"x"] isKindOfClass:NSNumber.class] ? bbox[@"x"] : @0;
        NSNumber *y = [bbox[@"y"] isKindOfClass:NSNumber.class] ? bbox[@"y"] : @0;
        NSNumber *height = [bbox[@"height"] isKindOfClass:NSNumber.class] ? bbox[@"height"] : @0;
        [tokens addObject:@{
            @"text": text,
            @"x": x,
            @"cy": @(y.doubleValue + height.doubleValue / 2.0),
            @"confidence": [candidate[@"confidence"] isKindOfClass:NSNumber.class] ? candidate[@"confidence"] : @0
        }];
    }

    NSArray *sortedTokens = [tokens sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        double leftY = [left[@"cy"] doubleValue];
        double rightY = [right[@"cy"] doubleValue];
        if (fabs(leftY - rightY) > 0.001) {
            return leftY > rightY ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left[@"x"] doubleValue] < [right[@"x"] doubleValue] ? NSOrderedAscending : NSOrderedDescending;
    }];

    NSMutableArray<NSMutableDictionary *> *groups = [NSMutableArray array];
    for (NSDictionary *token in sortedTokens) {
        double cy = [token[@"cy"] doubleValue];
        NSMutableDictionary *target = nil;
        for (NSMutableDictionary *group in groups) {
            if (fabs([group[@"cy"] doubleValue] - cy) < 0.045) {
                target = group;
                break;
            }
        }
        if (target == nil) {
            target = [@{@"cy": @(cy), @"tokens": [NSMutableArray array]} mutableCopy];
            [groups addObject:target];
        }
        NSMutableArray *groupTokens = target[@"tokens"];
        [groupTokens addObject:token];
        target[@"cy"] = @(([target[@"cy"] doubleValue] + cy) / 2.0);
    }

    NSMutableArray *traits = [NSMutableArray array];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSMutableDictionary *group in groups) {
        NSArray *rowTokens = [group[@"tokens"] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [left[@"x"] doubleValue] < [right[@"x"] doubleValue] ? NSOrderedAscending : NSOrderedDescending;
        }];
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        NSNumber *activeCount = nil;
        NSMutableArray<NSString *> *nameParts = [NSMutableArray array];
        double confidenceSum = 0;
        NSUInteger confidenceCount = 0;

        for (NSDictionary *token in rowTokens) {
            NSString *text = token[@"text"] ?: @"";
            [texts addObject:text];
            confidenceSum += [token[@"confidence"] doubleValue];
            confidenceCount += 1;
            double x = [token[@"x"] doubleValue];
            NSNumber *count = [self traitActiveCountFromText:text];
            if (activeCount == nil && count != nil && x < 0.46) {
                activeCount = count;
            }
            if ([self containsLetter:text]) {
                NSString *namePart = [self traitNameFromText:text];
                if (namePart.length > 0) {
                    [nameParts addObject:namePart];
                }
            }
        }

        NSString *rawLine = [texts componentsJoinedByString:@" "];
        NSString *name = [[nameParts componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        name = [self collapsedWhitespace:name];
        NSString *matchedName = [self bestKnownTraitNameForOCRName:name];
        if (matchedName.length > 0) {
            name = matchedName;
        }
        if (name.length == 0 || activeCount == nil) {
            [rows addObject:@{@"raw": rawLine, @"used": @NO}];
            continue;
        }
        NSDictionary *trait = @{
            @"name": name,
            @"count": activeCount,
            @"raw": rawLine,
            @"confidence": confidenceCount > 0 ? @(confidenceSum / confidenceCount) : @0
        };
        [traits addObject:trait];
        [rows addObject:@{@"raw": rawLine, @"used": @YES}];
    }

    NSMutableSet<NSString *> *activeNames = [NSMutableSet set];
    for (NSDictionary *trait in traits) {
        NSString *name = [trait[@"name"] isKindOfClass:NSString.class] ? trait[@"name"] : @"";
        NSString *normalized = [self normalizedAlphaText:name].lowercaseString;
        if (normalized.length > 0) {
            [activeNames addObject:normalized];
        }
    }
    NSArray *grayCandidates = [traitRegion[@"grayCandidates"] isKindOfClass:NSArray.class] ? traitRegion[@"grayCandidates"] : @[];
    NSArray *partialTraits = [self partialTraitRowsFromCandidates:grayCandidates activeNames:activeNames];
    NSNumber *extraTraitAllowance = [self extraTraitAllowanceFromTraitRegion:traitRegion candidates:candidates grayCandidates:grayCandidates];

    return @{
        @"detected": @(traits.count > 0),
        @"rawText": [traitRegion[@"text"] isKindOfClass:NSString.class] ? traitRegion[@"text"] : @"",
        @"grayRawText": [traitRegion[@"grayText"] isKindOfClass:NSString.class] ? traitRegion[@"grayText"] : @"",
        @"traits": traits,
        @"partialTraits": partialTraits,
        @"extraTraitAllowance": extraTraitAllowance ?: @0,
        @"rows": rows,
        @"imagePath": [traitRegion[@"imagePath"] isKindOfClass:NSString.class] ? traitRegion[@"imagePath"] : @"",
        @"filteredImagePath": [traitRegion[@"filteredImagePath"] isKindOfClass:NSString.class] ? traitRegion[@"filteredImagePath"] : @"",
        @"grayFilteredImagePath": [traitRegion[@"grayFilteredImagePath"] isKindOfClass:NSString.class] ? traitRegion[@"grayFilteredImagePath"] : @""
    };
}

- (NSNumber *)extraTraitAllowanceFromTraitRegion:(NSDictionary *)traitRegion candidates:(NSArray *)candidates grayCandidates:(NSArray *)grayCandidates {
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    NSString *raw = [traitRegion[@"text"] isKindOfClass:NSString.class] ? traitRegion[@"text"] : @"";
    NSString *grayRaw = [traitRegion[@"grayText"] isKindOfClass:NSString.class] ? traitRegion[@"grayText"] : @"";
    if (raw.length > 0) {
        [texts addObject:raw];
    }
    if (grayRaw.length > 0) {
        [texts addObject:grayRaw];
    }
    for (NSArray *source in @[candidates ?: @[], grayCandidates ?: @[]]) {
        for (NSDictionary *candidate in source) {
            if (![candidate isKindOfClass:NSDictionary.class]) {
                continue;
            }
            NSString *text = [candidate[@"text"] isKindOfClass:NSString.class] ? candidate[@"text"] : @"";
            if (text.length > 0) {
                [texts addObject:text];
            }
        }
    }

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\+\\s*([0-9Il|]+)" options:0 error:nil];
    NSInteger best = 0;
    for (NSString *text in texts) {
        NSString *normalized = [[text ?: @"" stringByReplacingOccurrencesOfString:@"＋" withString:@"+"] stringByReplacingOccurrencesOfString:@"l" withString:@"1"];
        normalized = [normalized stringByReplacingOccurrencesOfString:@"I" withString:@"1"];
        normalized = [normalized stringByReplacingOccurrencesOfString:@"|" withString:@"1"];
        NSTextCheckingResult *match = [regex firstMatchInString:normalized options:0 range:NSMakeRange(0, normalized.length)];
        if (match != nil && match.numberOfRanges >= 2) {
            NSString *digits = [normalized substringWithRange:[match rangeAtIndex:1]];
            best = MAX(best, digits.integerValue);
        }
    }
    return @(MAX(0, best));
}

- (NSArray *)partialTraitRowsFromCandidates:(NSArray *)candidates activeNames:(NSSet<NSString *> *)activeNames {
    NSMutableArray<NSDictionary *> *tokens = [NSMutableArray array];
    for (NSDictionary *candidate in candidates) {
        if (![candidate isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *text = [candidate[@"text"] isKindOfClass:NSString.class] ? candidate[@"text"] : @"";
        text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length == 0 || (![self containsLetter:text] && [self firstRegexMatch:@"[0-9]" inString:text] == nil)) {
            continue;
        }
        NSDictionary *bbox = [candidate[@"bbox"] isKindOfClass:NSDictionary.class] ? candidate[@"bbox"] : @{};
        NSNumber *x = [bbox[@"x"] isKindOfClass:NSNumber.class] ? bbox[@"x"] : @0;
        NSNumber *y = [bbox[@"y"] isKindOfClass:NSNumber.class] ? bbox[@"y"] : @0;
        NSNumber *height = [bbox[@"height"] isKindOfClass:NSNumber.class] ? bbox[@"height"] : @0;
        [tokens addObject:@{
            @"text": text,
            @"x": x,
            @"cy": @(y.doubleValue + height.doubleValue / 2.0),
            @"confidence": [candidate[@"confidence"] isKindOfClass:NSNumber.class] ? candidate[@"confidence"] : @0
        }];
    }

    NSArray *sortedTokens = [tokens sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        double leftY = [left[@"cy"] doubleValue];
        double rightY = [right[@"cy"] doubleValue];
        if (fabs(leftY - rightY) > 0.001) {
            return leftY > rightY ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left[@"x"] doubleValue] < [right[@"x"] doubleValue] ? NSOrderedAscending : NSOrderedDescending;
    }];

    NSMutableArray<NSMutableDictionary *> *groups = [NSMutableArray array];
    for (NSDictionary *token in sortedTokens) {
        double cy = [token[@"cy"] doubleValue];
        NSMutableDictionary *target = nil;
        for (NSMutableDictionary *group in groups) {
            if (fabs([group[@"cy"] doubleValue] - cy) < 0.05) {
                target = group;
                break;
            }
        }
        if (target == nil) {
            target = [@{@"cy": @(cy), @"tokens": [NSMutableArray array]} mutableCopy];
            [groups addObject:target];
        }
        NSMutableArray *groupTokens = target[@"tokens"];
        [groupTokens addObject:token];
        target[@"cy"] = @(([target[@"cy"] doubleValue] + cy) / 2.0);
    }

    NSMutableArray *partialTraits = [NSMutableArray array];
    for (NSMutableDictionary *group in groups) {
        NSArray *rowTokens = [group[@"tokens"] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [left[@"x"] doubleValue] < [right[@"x"] doubleValue] ? NSOrderedAscending : NSOrderedDescending;
        }];
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        NSMutableArray<NSString *> *nameParts = [NSMutableArray array];
        NSNumber *current = nil;
        NSNumber *threshold = nil;
        double confidenceSum = 0;
        NSUInteger confidenceCount = 0;
        for (NSDictionary *token in rowTokens) {
            NSString *text = token[@"text"] ?: @"";
            [texts addObject:text];
            confidenceSum += [token[@"confidence"] doubleValue];
            confidenceCount += 1;
            NSDictionary *progress = [self traitProgressFromText:text];
            if (progress != nil) {
                current = progress[@"current"];
                threshold = progress[@"threshold"];
            }
            if ([self containsLetter:text]) {
                NSString *namePart = [self traitNameFromText:text];
                if (namePart.length > 0) {
                    [nameParts addObject:namePart];
                }
            }
        }
        NSString *rawLine = [texts componentsJoinedByString:@" "];
        NSString *name = [self collapsedWhitespace:[nameParts componentsJoinedByString:@" "]];
        NSString *matchedName = [self bestKnownTraitNameForOCRName:name];
        if (matchedName.length > 0) {
            name = matchedName;
        }
        NSString *normalized = [self normalizedAlphaText:name].lowercaseString;
        if (name.length == 0 || current == nil || threshold == nil || current.integerValue <= 0 || [activeNames containsObject:normalized]) {
            continue;
        }
        [partialTraits addObject:@{
            @"name": name,
            @"count": current,
            @"threshold": threshold,
            @"raw": rawLine,
            @"confidence": confidenceCount > 0 ? @(confidenceSum / confidenceCount) : @0
        }];
    }
    return partialTraits;
}

- (NSDictionary *)traitProgressFromText:(NSString *)text {
    NSString *normalized = text ?: @"";
    normalized = [normalized stringByReplacingOccurrencesOfString:@"I" withString:@"1"];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"l" withString:@"1"];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"|" withString:@"1"];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([0-9]+)\\s*/\\s*([0-9]+)" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:normalized options:0 range:NSMakeRange(0, normalized.length)];
    if (match != nil && match.numberOfRanges >= 3) {
        NSString *current = [normalized substringWithRange:[match rangeAtIndex:1]];
        NSString *threshold = [normalized substringWithRange:[match rangeAtIndex:2]];
        return @{@"current": @(current.integerValue), @"threshold": @(threshold.integerValue)};
    }

    NSString *digitsOnly = [normalized stringByReplacingOccurrencesOfString:@"[^0-9]" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, normalized.length)];
    if (digitsOnly.length >= 3 && [digitsOnly characterAtIndex:1] == '1') {
        NSString *current = [digitsOnly substringToIndex:1];
        NSString *threshold = [digitsOnly substringFromIndex:2];
        if (current.integerValue > 0 && threshold.integerValue > current.integerValue) {
            return @{@"current": @(current.integerValue), @"threshold": @(threshold.integerValue)};
        }
    }
    return nil;
}

- (NSNumber *)traitActiveCountFromText:(NSString *)text {
    if ([self traitProgressFromText:text] != nil) {
        return nil;
    }
    NSString *match = [self firstRegexMatch:@"[0-9]+" inString:text ?: @""];
    if (match.length == 1) {
        return @(match.integerValue);
    }
    NSString *normalized = [[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"|" withString:@""];
    normalized = [normalized stringByReplacingOccurrencesOfString:@" " withString:@""];
    if ([normalized isEqualToString:@"i"] || [normalized isEqualToString:@"l"]) {
        return @1;
    }
    return nil;
}

- (NSString *)traitNameFromText:(NSString *)text {
    NSString *withoutDigits = [text stringByReplacingOccurrencesOfString:@"[0-9/]+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, text.length)];
    withoutDigits = [withoutDigits stringByReplacingOccurrencesOfString:@"[•·,;:()\\[\\]{}]+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, withoutDigits.length)];
    return [self collapsedWhitespace:withoutDigits];
}

- (NSArray<NSDictionary *> *)loadKnownTraitNames {
    NSURL *url = [NSBundle.mainBundle URLForResource:@"tftacademy-latest" withExtension:@"json"];
    if (url == nil) {
        url = [NSURL fileURLWithPath:[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"data/tftacademy/latest.json"]];
    }
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data.length == 0) {
        return @[];
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSString *currentPrefix = [self currentChampionApiPrefixForJSON:json];
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    for (NSDictionary *champion in [json[@"champions"] isKindOfClass:NSArray.class] ? json[@"champions"] : @[]) {
        NSString *apiName = [champion[@"apiName"] isKindOfClass:NSString.class] ? champion[@"apiName"] : @"";
        if (![self isRosterChampionApiName:apiName currentPrefix:currentPrefix]) {
            continue;
        }
        NSArray *traits = [champion[@"traits"] isKindOfClass:NSArray.class] ? champion[@"traits"] : @[];
        for (NSString *trait in traits) {
            if ([trait isKindOfClass:NSString.class] && trait.length > 0) {
                [names addObject:trait];
            }
        }
    }
    for (NSDictionary *comp in [json[@"comps"] isKindOfClass:NSArray.class] ? json[@"comps"] : @[]) {
        for (NSDictionary *trait in [comp[@"traits"] isKindOfClass:NSArray.class] ? comp[@"traits"] : @[]) {
            NSString *name = [trait[@"name"] isKindOfClass:NSString.class] ? trait[@"name"] : @"";
            if (name.length > 0) {
                [names addObject:name];
            }
        }
    }
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *name in names) {
        NSString *normalized = [self normalizedAlphaText:name].lowercaseString;
        if (normalized.length > 0) {
            [entries addObject:@{@"name": name, @"normalized": normalized}];
        }
    }
    return entries;
}

- (NSArray<NSDictionary *> *)loadKnownChampionNames {
    NSURL *url = [NSBundle.mainBundle URLForResource:@"tftacademy-latest" withExtension:@"json"];
    if (url == nil) {
        url = [NSURL fileURLWithPath:[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"data/tftacademy/latest.json"]];
    }
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data.length == 0) {
        return @[];
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSString *currentPrefix = [self currentChampionApiPrefixForJSON:json];
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    for (NSDictionary *champion in [json[@"champions"] isKindOfClass:NSArray.class] ? json[@"champions"] : @[]) {
        NSString *apiName = [champion[@"apiName"] isKindOfClass:NSString.class] ? champion[@"apiName"] : @"";
        if (![self isRosterChampionApiName:apiName currentPrefix:currentPrefix]) {
            continue;
        }
        NSString *name = [champion[@"name"] isKindOfClass:NSString.class] ? champion[@"name"] : @"";
        if (name.length > 0) {
            [names addObject:name];
        }
    }
    for (NSDictionary *comp in [json[@"comps"] isKindOfClass:NSArray.class] ? json[@"comps"] : @[]) {
        NSMutableArray *units = [NSMutableArray array];
        if ([comp[@"mainChampion"] isKindOfClass:NSDictionary.class]) {
            [units addObject:comp[@"mainChampion"]];
        }
        if ([comp[@"finalComp"] isKindOfClass:NSArray.class]) {
            [units addObjectsFromArray:comp[@"finalComp"]];
        }
        if ([comp[@"earlyComp"] isKindOfClass:NSArray.class]) {
            [units addObjectsFromArray:comp[@"earlyComp"]];
        }
        for (NSDictionary *unit in units) {
            NSString *apiName = [unit[@"apiName"] isKindOfClass:NSString.class] ? unit[@"apiName"] : @"";
            if (![self isRosterChampionApiName:apiName currentPrefix:currentPrefix]) {
                continue;
            }
            NSString *name = [unit[@"name"] isKindOfClass:NSString.class] ? unit[@"name"] : @"";
            if (name.length > 0) {
                [names addObject:name];
            }
        }
    }
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *name in names) {
        NSString *normalized = [self normalizedAlphaText:name].lowercaseString;
        if (normalized.length > 0) {
            [entries addObject:@{@"name": name, @"normalized": normalized}];
        }
    }
    return entries;
}

- (NSString *)currentChampionApiPrefixForJSON:(NSDictionary *)json {
    NSNumber *setNumber = [json[@"set"] isKindOfClass:NSNumber.class] ? json[@"set"] : nil;
    if (setNumber == nil || setNumber.integerValue <= 0) {
        return @"";
    }
    return [NSString stringWithFormat:@"TFT%ld_", (long)setNumber.integerValue];
}

- (BOOL)isRosterChampionApiName:(NSString *)apiName currentPrefix:(NSString *)currentPrefix {
    if (apiName.length == 0) {
        return NO;
    }
    if (currentPrefix.length > 0 && ![apiName hasPrefix:currentPrefix]) {
        return NO;
    }
    if ([apiName rangeOfString:@"FakeUnit" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return NO;
    }
    if ([apiName hasSuffix:@"_Summon"] || [apiName hasSuffix:@"_Relic"]) {
        return NO;
    }
    return YES;
}

- (NSString *)bestKnownTraitNameForOCRName:(NSString *)name {
    NSString *normalized = [self normalizedAlphaText:name].lowercaseString;
    if (normalized.length == 0 || self.knownTraitNames.count == 0) {
        return name ?: @"";
    }

    NSString *bestName = nil;
    double bestScore = 0;
    for (NSDictionary *entry in self.knownTraitNames) {
        NSString *candidate = [entry[@"normalized"] isKindOfClass:NSString.class] ? entry[@"normalized"] : @"";
        if (candidate.length == 0) {
            continue;
        }
        double score = [self fuzzyScoreForNormalizedOCR:normalized candidate:candidate];
        if (score > bestScore) {
            bestScore = score;
            bestName = [entry[@"name"] isKindOfClass:NSString.class] ? entry[@"name"] : nil;
        }
    }

    double threshold = normalized.length <= 3 ? 0.42 : 0.34;
    return bestScore >= threshold ? (bestName ?: name ?: @"") : (name ?: @"");
}

- (NSString *)bestKnownChampionNameForOCRName:(NSString *)name {
    NSString *normalized = [self normalizedAlphaText:name].lowercaseString;
    if (normalized.length == 0 || self.knownChampionNames.count == 0) {
        return name ?: @"";
    }
    NSString *bestName = nil;
    double bestScore = 0;
    for (NSDictionary *entry in self.knownChampionNames) {
        NSString *candidate = [entry[@"normalized"] isKindOfClass:NSString.class] ? entry[@"normalized"] : @"";
        if (candidate.length == 0) {
            continue;
        }
        double score = [self fuzzyScoreForNormalizedOCR:normalized candidate:candidate];
        if (score > bestScore) {
            bestScore = score;
            bestName = [entry[@"name"] isKindOfClass:NSString.class] ? entry[@"name"] : nil;
        }
    }
    double threshold = normalized.length <= 3 ? 0.54 : 0.44;
    return bestScore >= threshold ? (bestName ?: name ?: @"") : (name ?: @"");
}

- (double)fuzzyScoreForNormalizedOCR:(NSString *)ocr candidate:(NSString *)candidate {
    if (ocr.length == 0 || candidate.length == 0) {
        return 0;
    }
    if ([ocr isEqualToString:candidate]) {
        return 1;
    }
    if ([candidate hasPrefix:ocr] && ocr.length >= 2) {
        return 0.82 + MIN(0.12, (double)ocr.length / MAX(1.0, (double)candidate.length) * 0.12);
    }
    if ([ocr hasPrefix:[candidate substringToIndex:MIN(candidate.length, 2)]]) {
        return MAX(0.0, 0.58 + [self editSimilarityBetween:ocr and:candidate] * 0.28);
    }
    if ([ocr characterAtIndex:0] == [candidate characterAtIndex:0]) {
        return MAX([self editSimilarityBetween:ocr and:candidate], [self orderedCharacterScoreForOCR:ocr candidate:candidate] * 0.74);
    }
    return [self editSimilarityBetween:ocr and:candidate] * 0.8;
}

- (double)editSimilarityBetween:(NSString *)left and:(NSString *)right {
    NSUInteger maxLength = MAX(left.length, right.length);
    if (maxLength == 0) {
        return 0;
    }
    return 1.0 - ((double)[self editDistanceBetween:left and:right] / (double)maxLength);
}

- (NSUInteger)editDistanceBetween:(NSString *)left and:(NSString *)right {
    NSUInteger leftCount = left.length;
    NSUInteger rightCount = right.length;
    NSMutableArray<NSNumber *> *previous = [NSMutableArray arrayWithCapacity:rightCount + 1];
    NSMutableArray<NSNumber *> *current = [NSMutableArray arrayWithCapacity:rightCount + 1];
    for (NSUInteger j = 0; j <= rightCount; j += 1) {
        [previous addObject:@(j)];
        [current addObject:@0];
    }
    for (NSUInteger i = 1; i <= leftCount; i += 1) {
        current[0] = @(i);
        unichar leftChar = [left characterAtIndex:i - 1];
        for (NSUInteger j = 1; j <= rightCount; j += 1) {
            unichar rightChar = [right characterAtIndex:j - 1];
            NSUInteger cost = leftChar == rightChar ? 0 : 1;
            NSUInteger deletion = previous[j].unsignedIntegerValue + 1;
            NSUInteger insertion = current[j - 1].unsignedIntegerValue + 1;
            NSUInteger substitution = previous[j - 1].unsignedIntegerValue + cost;
            current[j] = @(MIN(MIN(deletion, insertion), substitution));
        }
        NSArray *swap = previous;
        previous = [current mutableCopy];
        current = [swap mutableCopy];
    }
    return previous[rightCount].unsignedIntegerValue;
}

- (double)orderedCharacterScoreForOCR:(NSString *)ocr candidate:(NSString *)candidate {
    NSUInteger matched = 0;
    NSUInteger searchStart = 0;
    for (NSUInteger i = 0; i < ocr.length; i += 1) {
        unichar c = [ocr characterAtIndex:i];
        BOOL found = NO;
        for (NSUInteger j = searchStart; j < candidate.length; j += 1) {
            if ([candidate characterAtIndex:j] == c) {
                matched += 1;
                searchStart = j + 1;
                found = YES;
                break;
            }
        }
        if (!found && i == 0) {
            return 0;
        }
    }
    return (double)matched / (double)MAX(ocr.length, candidate.length);
}

- (NSString *)collapsedWhitespace:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [trimmed stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, trimmed.length)];
}

- (NSDictionary *)unitPanelDetectionForRegions:(NSArray *)regions colors:(NSDictionary *)colors {
    NSString *rawName = [self textForRegion:@"unit_name" regions:regions];
    NSString *name = [self bestKnownChampionNameForOCRName:rawName];
    BOOL hasName = [self containsLetter:name] && [self normalizedAlphaText:name].length >= 3;

    BOOL colorLooksLikePanel = [colors[@"detected"] boolValue];
    BOOL detected = colorLooksLikePanel;
    return @{
        @"detected": @(detected),
        @"name": name ?: @"",
        @"rawName": rawName ?: @"",
        @"hasName": @(hasName),
        @"color": colors ?: @{}
    };
}

- (NSDictionary *)unitPanelColorSamplesForImage:(CGImageRef)image contentTopInset:(CGFloat)contentTopInset scaleX:(CGFloat)scaleX scaleY:(CGFloat)scaleY {
    size_t imageWidth = CGImageGetWidth(image);
    size_t imageHeight = CGImageGetHeight(image);
    NSArray<NSValue *> *basePoints = @[
        [NSValue valueWithPoint:NSMakePoint(1713.4035087719299, 824.568345323741)],
        [NSValue valueWithPoint:NSMakePoint(1717.8947368421054, 645.863309352518)],
        [NSValue valueWithPoint:NSMakePoint(1881.8245614035088, 649.7482014388489)]
    ];
    NSInteger panelSamples = 0;
    NSMutableArray *samples = [NSMutableArray array];
    for (NSValue *pointValue in basePoints) {
        NSPoint basePoint = pointValue.pointValue;
        NSInteger x = (NSInteger)round((CGFloat)imageWidth - (1920.0 - basePoint.x) * scaleX);
        NSInteger y = (NSInteger)round(contentTopInset + ((CGFloat)imageHeight - contentTopInset) / 2.0 + (basePoint.y - 540.0) * scaleY);
        if (x < 0 || y < 0 || x >= (NSInteger)imageWidth || y >= (NSInteger)imageHeight) {
            continue;
        }
        NSDictionary *pixel = [self colorSampleForImage:image x:x y:y];
        if (pixel == nil) {
            continue;
        }
        CGFloat red = [pixel[@"r"] doubleValue];
        CGFloat green = [pixel[@"g"] doubleValue];
        CGFloat blue = [pixel[@"b"] doubleValue];
        CGFloat brightness = (red + green + blue) / 3.0;
        CGFloat distance = sqrt(pow(red - 0.03, 2) + pow(green - 0.09, 2) + pow(blue - 0.08, 2));
        BOOL looksLikePanel = brightness < 0.18 && green >= red * 1.15 && blue >= red * 0.90 && green <= 0.18 && blue <= 0.16 && distance < 0.12;
        if (looksLikePanel) {
            panelSamples += 1;
        }
        [samples addObject:@{
            @"x": @(x),
            @"y": @(y),
            @"r": @(red),
            @"g": @(green),
            @"b": @(blue),
            @"brightness": @(brightness),
            @"distance": @(distance),
            @"looksLikePanel": @(looksLikePanel)
        }];
    }
    return @{
        @"detected": @(panelSamples >= 3),
        @"panelSamples": @(panelSamples),
        @"requiredSamples": @3,
        @"samples": samples
    };
}

- (NSDictionary *)augmentOfferColorSamplesForImage:(CGImageRef)image contentTopInset:(CGFloat)contentTopInset scaleX:(CGFloat)scaleX scaleY:(CGFloat)scaleY {
    size_t imageWidth = CGImageGetWidth(image);
    size_t imageHeight = CGImageGetHeight(image);
    NSArray<NSValue *> *basePoints = @[
        [NSValue valueWithPoint:NSMakePoint(552, 597)],
        [NSValue valueWithPoint:NSMakePoint(960, 597)],
        [NSValue valueWithPoint:NSMakePoint(1365, 597)]
    ];
    NSMutableArray *samples = [NSMutableArray array];
    NSInteger detected = 0;
    for (NSValue *pointValue in basePoints) {
        NSPoint basePoint = pointValue.pointValue;
        NSInteger x = (NSInteger)round((CGFloat)imageWidth / 2.0 + (basePoint.x - 960.0) * scaleX);
        NSInteger y = (NSInteger)round(contentTopInset + ((CGFloat)imageHeight - contentTopInset) / 2.0 + (basePoint.y - 540.0) * scaleY);
        if (x < 0 || y < 0 || x >= (NSInteger)imageWidth || y >= (NSInteger)imageHeight) {
            [samples addObject:@{@"detected": @NO}];
            continue;
        }
        NSDictionary *pixel = [self colorSampleForImage:image x:x y:y];
        if (pixel == nil) {
            [samples addObject:@{@"detected": @NO, @"x": @(x), @"y": @(y)}];
            continue;
        }
        CGFloat red = [pixel[@"r"] doubleValue];
        CGFloat green = [pixel[@"g"] doubleValue];
        CGFloat blue = [pixel[@"b"] doubleValue];
        CGFloat brightness = (red + green + blue) / 3.0;
        BOOL looksLikeAugmentPurple = brightness > 0.04 &&
                                      brightness < 0.40 &&
                                      blue > 0.14 &&
                                      blue >= red * 1.25 &&
                                      red >= green * 1.10 &&
                                      green < 0.24;
        if (looksLikeAugmentPurple) {
            detected += 1;
        }
        [samples addObject:@{
            @"x": @(x),
            @"y": @(y),
            @"r": @(red),
            @"g": @(green),
            @"b": @(blue),
            @"brightness": @(brightness),
            @"detected": @(looksLikeAugmentPurple)
        }];
    }
    return @{
        @"detected": @(detected),
        @"samples": samples
    };
}

- (BOOL)shouldOCRAugmentRegion:(NSString *)regionID colorSamples:(NSDictionary *)colorSamples {
    NSString *suffix = [regionID stringByReplacingOccurrencesOfString:@"augment_" withString:@""];
    NSInteger index = suffix.integerValue - 1;
    NSArray *samples = [colorSamples[@"samples"] isKindOfClass:NSArray.class] ? colorSamples[@"samples"] : @[];
    if (index < 0 || index >= (NSInteger)samples.count) {
        return NO;
    }
    NSDictionary *sample = [samples[index] isKindOfClass:NSDictionary.class] ? samples[index] : @{};
    return [sample[@"detected"] boolValue];
}

- (NSDictionary *)godBoonOfferColorSamplesForImage:(CGImageRef)image contentTopInset:(CGFloat)contentTopInset scaleX:(CGFloat)scaleX scaleY:(CGFloat)scaleY {
    size_t imageWidth = CGImageGetWidth(image);
    size_t imageHeight = CGImageGetHeight(image);
    NSArray<NSValue *> *basePoints = @[
        [NSValue valueWithPoint:NSMakePoint(750, 640)],
        [NSValue valueWithPoint:NSMakePoint(1160, 640)]
    ];
    NSMutableArray *samples = [NSMutableArray array];
    NSInteger detected = 0;
    for (NSValue *pointValue in basePoints) {
        NSPoint basePoint = pointValue.pointValue;
        NSInteger x = (NSInteger)round((CGFloat)imageWidth / 2.0 + (basePoint.x - 960.0) * scaleX);
        NSInteger y = (NSInteger)round(contentTopInset + ((CGFloat)imageHeight - contentTopInset) / 2.0 + (basePoint.y - 540.0) * scaleY);
        if (x < 0 || y < 0 || x >= (NSInteger)imageWidth || y >= (NSInteger)imageHeight) {
            [samples addObject:@{@"detected": @NO}];
            continue;
        }
        NSDictionary *pixel = [self colorSampleForImage:image x:x y:y];
        if (pixel == nil) {
            [samples addObject:@{@"detected": @NO, @"x": @(x), @"y": @(y)}];
            continue;
        }
        CGFloat red = [pixel[@"r"] doubleValue];
        CGFloat green = [pixel[@"g"] doubleValue];
        CGFloat blue = [pixel[@"b"] doubleValue];
        CGFloat brightness = (red + green + blue) / 3.0;
        BOOL looksLikeGodCardDark = brightness < 0.13 &&
                                    blue >= red * 1.20 &&
                                    blue >= green * 1.15 &&
                                    red < 0.10 &&
                                    green < 0.10 &&
                                    blue < 0.20;
        if (looksLikeGodCardDark) {
            detected += 1;
        }
        [samples addObject:@{
            @"x": @(x),
            @"y": @(y),
            @"r": @(red),
            @"g": @(green),
            @"b": @(blue),
            @"brightness": @(brightness),
            @"detected": @(looksLikeGodCardDark)
        }];
    }
    return @{
        @"detected": @(detected),
        @"samples": samples
    };
}

- (BOOL)shouldOCRGodBoonRegion:(NSString *)regionID colorSamples:(NSDictionary *)colorSamples {
    NSString *suffix = [regionID stringByReplacingOccurrencesOfString:@"god_boon_" withString:@""];
    NSInteger index = suffix.integerValue - 1;
    NSArray *samples = [colorSamples[@"samples"] isKindOfClass:NSArray.class] ? colorSamples[@"samples"] : @[];
    if (index < 0 || index >= (NSInteger)samples.count) {
        return NO;
    }
    NSDictionary *sample = [samples[index] isKindOfClass:NSDictionary.class] ? samples[index] : @{};
    return [sample[@"detected"] boolValue];
}

- (NSDictionary *)colorSampleForImage:(CGImageRef)image x:(NSInteger)x y:(NSInteger)y {
    CGRect rect = CGRectMake(x, y, 1, 1);
    CGImageRef crop = CGImageCreateWithImageInRect(image, rect);
    if (crop == NULL) {
        return nil;
    }
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:crop];
    CGImageRelease(crop);
    if (bitmap.pixelsWide < 1 || bitmap.pixelsHigh < 1) {
        return nil;
    }
    NSColor *rgb = [[bitmap colorAtX:0 y:0] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    [rgb getRed:&red green:&green blue:&blue alpha:&alpha];
    return @{@"r": @(red), @"g": @(green), @"b": @(blue), @"a": @(alpha)};
}

- (NSString *)textForRegion:(NSString *)regionID regions:(NSArray *)regions {
    for (NSDictionary *region in regions) {
        if (![region isKindOfClass:NSDictionary.class] || ![region[@"id"] isEqualToString:regionID]) {
            continue;
        }
        if ([region[@"cleanText"] isKindOfClass:NSString.class]) {
            return region[@"cleanText"];
        }
        return [region[@"text"] isKindOfClass:NSString.class] ? region[@"text"] : @"";
    }
    return @"";
}

- (BOOL)containsLetter:(NSString *)text {
    return [text rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound;
}

- (NSString *)normalizedAlphaText:(NSString *)text {
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < text.length; i += 1) {
        unichar c = [text characterAtIndex:i];
        if ([[NSCharacterSet.letterCharacterSet invertedSet] characterIsMember:c]) {
            continue;
        }
        [result appendFormat:@"%C", c];
    }
    return result;
}

- (NSString *)firstRegexMatch:(NSString *)pattern inString:(NSString *)text {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:text ?: @"" options:0 range:NSMakeRange(0, text.length)];
    if (match == nil) {
        return nil;
    }
    return [text substringWithRange:match.range];
}

- (CGFloat)detectedTopContentInsetForImage:(CGImageRef)image {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:image];
    NSInteger width = bitmap.pixelsWide;
    NSInteger height = bitmap.pixelsHigh;
    NSInteger sampleWidth = MIN(width, 48);
    NSInteger maxRows = MIN(height, 160);

    for (NSInteger y = 0; y < maxRows; y += 1) {
        NSInteger bright = 0;
        for (NSInteger x = 0; x < sampleWidth; x += 1) {
            NSColor *color = [bitmap colorAtX:x y:y];
            NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            CGFloat red = 0;
            CGFloat green = 0;
            CGFloat blue = 0;
            CGFloat alpha = 0;
            [rgb getRed:&red green:&green blue:&blue alpha:&alpha];
            if (red > 0.86 && green > 0.86 && blue > 0.86) {
                bright += 1;
            }
        }
        if (bright < sampleWidth * 0.8) {
            return y;
        }
    }
    return 0;
}

- (NSDictionary *)leagueWindowInfo {
    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
    NSArray *windows = CFBridgingRelease(windowList);
    NSDictionary *bestWindow = nil;
    CGFloat bestArea = 0;

    for (NSDictionary *window in windows) {
        NSString *ownerName = window[(NSString *)kCGWindowOwnerName];
        NSString *windowName = window[(NSString *)kCGWindowName];
        NSString *ownerLower = ownerName.lowercaseString ?: @"";
        NSString *nameLower = windowName.lowercaseString ?: @"";
        BOOL looksLikeLeague = [ownerLower containsString:@"league"] || [nameLower containsString:@"league"];
        if (!looksLikeLeague) {
            continue;
        }

        NSDictionary *boundsDictionary = window[(NSString *)kCGWindowBounds];
        CGRect bounds = CGRectNull;
        CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)boundsDictionary, &bounds);
        CGFloat area = bounds.size.width * bounds.size.height;
        if (area > bestArea && bounds.size.width > 600 && bounds.size.height > 400) {
            bestArea = area;
            bestWindow = window;
        }
    }

    return bestWindow;
}

- (CGImageRef)captureWindowImageForWindowNumber:(NSNumber *)windowNumber logDirectory:(NSURL *)logDirectoryURL CF_RETURNS_RETAINED {
    NSURL *tempDirectory = [logDirectoryURL URLByAppendingPathComponent:@"VisionCrops" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:tempDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *captureURL = [tempDirectory URLByAppendingPathComponent:@"window-capture-latest.png"];
    [NSFileManager.defaultManager removeItemAtURL:captureURL error:nil];

    NSTask *task = [NSTask new];
    task.launchPath = @"/usr/sbin/screencapture";
    task.arguments = @[@"-x", @"-l", windowNumber.stringValue, captureURL.path];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        return NULL;
    }

    if (task.terminationStatus != 0) {
        return NULL;
    }

    NSImage *image = [[NSImage alloc] initWithContentsOfURL:captureURL];
    if (image == nil) {
        return NULL;
    }

    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (cgImage == NULL) {
        return NULL;
    }

    return CGImageRetain(cgImage);
}

- (CGImageRef)captureFullDisplayImageInLogDirectory:(NSURL *)logDirectoryURL CF_RETURNS_RETAINED {
    NSURL *tempDirectory = [logDirectoryURL URLByAppendingPathComponent:@"VisionCrops" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:tempDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *captureURL = [tempDirectory URLByAppendingPathComponent:@"display-capture-latest.png"];
    [NSFileManager.defaultManager removeItemAtURL:captureURL error:nil];

    NSTask *task = [NSTask new];
    task.launchPath = @"/usr/sbin/screencapture";
    task.arguments = @[@"-x", captureURL.path];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        return NULL;
    }

    if (task.terminationStatus != 0) {
        return NULL;
    }

    NSImage *image = [[NSImage alloc] initWithContentsOfURL:captureURL];
    if (image == nil) {
        return NULL;
    }

    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (cgImage == NULL) {
        return NULL;
    }

    return CGImageRetain(cgImage);
}

- (NSDictionary *)publicWindowDictionary:(NSDictionary *)windowInfo {
    NSDictionary *boundsDictionary = windowInfo[(NSString *)kCGWindowBounds] ?: @{};
    return @{
        @"owner": windowInfo[(NSString *)kCGWindowOwnerName] ?: @"",
        @"name": windowInfo[(NSString *)kCGWindowName] ?: @"",
        @"number": windowInfo[(NSString *)kCGWindowNumber] ?: [NSNull null],
        @"bounds": boundsDictionary
    };
}

- (CGImageRef)whiteTextFilteredImageFromImage:(CGImageRef)image CF_RETURNS_RETAINED {
    NSBitmapImageRep *input = [[NSBitmapImageRep alloc] initWithCGImage:image];
    NSInteger width = input.pixelsWide;
    NSInteger height = input.pixelsHigh;
    NSBitmapImageRep *output = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                       pixelsWide:width
                                                                       pixelsHigh:height
                                                                    bitsPerSample:8
                                                                  samplesPerPixel:4
                                                                         hasAlpha:YES
                                                                         isPlanar:NO
                                                                   colorSpaceName:NSCalibratedRGBColorSpace
                                                                      bytesPerRow:0
                                                                     bitsPerPixel:0];
    NSColor *black = [NSColor colorWithCalibratedWhite:0 alpha:1];
    NSColor *white = [NSColor colorWithCalibratedWhite:1 alpha:1];
    for (NSInteger y = 0; y < height; y += 1) {
        for (NSInteger x = 0; x < width; x += 1) {
            NSColor *color = [[input colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            CGFloat r = 0, g = 0, b = 0, a = 0;
            [color getRed:&r green:&g blue:&b alpha:&a];
            CGFloat maxChannel = MAX(r, MAX(g, b));
            CGFloat minChannel = MIN(r, MIN(g, b));
            CGFloat luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
            CGFloat spread = maxChannel - minChannel;
            BOOL looksWhite = a > 0.35 && luma > 0.56 && maxChannel > 0.62 && spread < 0.28;
            [output setColor:(looksWhite ? white : black) atX:x y:y];
        }
    }
    return CGImageRetain(output.CGImage);
}

- (CGImageRef)grayTextFilteredImageFromImage:(CGImageRef)image CF_RETURNS_RETAINED {
    NSBitmapImageRep *input = [[NSBitmapImageRep alloc] initWithCGImage:image];
    NSInteger width = input.pixelsWide;
    NSInteger height = input.pixelsHigh;
    NSBitmapImageRep *output = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                       pixelsWide:width
                                                                       pixelsHigh:height
                                                                    bitsPerSample:8
                                                                  samplesPerPixel:4
                                                                         hasAlpha:YES
                                                                         isPlanar:NO
                                                                   colorSpaceName:NSCalibratedRGBColorSpace
                                                                      bytesPerRow:0
                                                                     bitsPerPixel:0];
    NSColor *black = [NSColor colorWithCalibratedWhite:0 alpha:1];
    NSColor *white = [NSColor colorWithCalibratedWhite:1 alpha:1];
    for (NSInteger y = 0; y < height; y += 1) {
        for (NSInteger x = 0; x < width; x += 1) {
            NSColor *color = [[input colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            CGFloat r = 0, g = 0, b = 0, a = 0;
            [color getRed:&r green:&g blue:&b alpha:&a];
            CGFloat maxChannel = MAX(r, MAX(g, b));
            CGFloat minChannel = MIN(r, MIN(g, b));
            CGFloat luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
            CGFloat spread = maxChannel - minChannel;
            BOOL looksGrayText = a > 0.35 && luma > 0.32 && luma < 0.78 && maxChannel > 0.38 && spread < 0.34;
            BOOL tooWhite = luma > 0.70 && maxChannel > 0.78 && spread < 0.22;
            [output setColor:(looksGrayText && !tooWhite ? white : black) atX:x y:y];
        }
    }
    return CGImageRetain(output.CGImage);
}

- (NSDictionary *)recognizedTextForImage:(CGImageRef)image {
    return [self recognizedTextForImage:image fast:NO];
}

- (NSDictionary *)recognizedTextForImage:(CGImageRef)image fast:(BOOL)fast {
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:nil];
    request.recognitionLevel = fast ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
    request.recognitionLanguages = @[@"en-US"];
    request.usesLanguageCorrection = !fast;

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
    NSError *error = nil;
    BOOL ok = [handler performRequests:@[request] error:&error];
    if (!ok) {
        return @{
            @"text": @"",
            @"candidates": @[],
            @"error": error.localizedDescription ?: @"Vision text recognition failed."
        };
    }

    NSMutableArray *candidates = [NSMutableArray array];
    NSMutableArray *lines = [NSMutableArray array];
    for (VNRecognizedTextObservation *observation in request.results) {
        VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
        if (candidate == nil) {
            continue;
        }
        [lines addObject:candidate.string ?: @""];
        CGRect box = observation.boundingBox;
        [candidates addObject:@{
            @"text": candidate.string ?: @"",
            @"confidence": @(candidate.confidence),
            @"bbox": @{
                @"x": @(box.origin.x),
                @"y": @(box.origin.y),
                @"width": @(box.size.width),
                @"height": @(box.size.height)
            }
        }];
    }

    return @{
        @"text": [lines componentsJoinedByString:@" "],
        @"candidates": candidates
    };
}

- (NSString *)saveCrop:(CGImageRef)image identifier:(NSString *)identifier logDirectory:(NSURL *)logDirectoryURL {
    NSURL *cropDirectory = [logDirectoryURL URLByAppendingPathComponent:@"VisionCrops" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:cropDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *filename = [NSString stringWithFormat:@"vision-%06lu-%@.png", (unsigned long)self.captureIndex, identifier];
    NSURL *url = [cropDirectory URLByAppendingPathComponent:filename];
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:image];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (png.length == 0) {
        return nil;
    }
    if (![png writeToURL:url atomically:YES]) {
        return nil;
    }
    return url.path;
}
@end

@interface AugmentTierEntry : NSObject
@property(nonatomic, copy) NSString *apiName;
@property(nonatomic, copy) NSString *displayName;
@property(nonatomic, copy) NSString *normalizedName;
@property(nonatomic, copy) NSString *tier;
@property(nonatomic, copy) NSString *actualTier;
@property(nonatomic, copy) NSString *stage;
@property(nonatomic, strong) NSNumber *augmentTier;
@end

@implementation AugmentTierEntry
@end

@interface AugmentTierMatcher : NSObject
@property(nonatomic, strong) NSArray<AugmentTierEntry *> *entries;
@property(nonatomic, strong) NSArray<AugmentTierEntry *> *godEntries;
@property(nonatomic, strong) NSDictionary<NSString *, NSArray<NSDictionary *> *> *compBadgesByApiName;
@property(nonatomic, strong) NSDictionary<NSString *, NSArray<NSDictionary *> *> *compBadgesByGodBoonName;
@property(nonatomic, strong) NSArray<NSDictionary *> *allCompBadges;
- (NSArray<NSDictionary *> *)matchesForVisionSnapshot:(NSDictionary *)visionSnapshot;
- (NSArray<NSDictionary *> *)godBoonMatchesForVisionSnapshot:(NSDictionary *)visionSnapshot;
- (NSDictionary *)compSuggestionForBoardReconstruction:(NSDictionary *)boardReconstruction level:(NSInteger)level selectedTitle:(NSString *)selectedTitle;
@end

@implementation AugmentTierMatcher
- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [self loadEntries];
        _godEntries = [self loadGodEntries];
    }
    return self;
}

- (NSArray<AugmentTierEntry *> *)loadEntries {
    NSURL *url = [NSBundle.mainBundle URLForResource:@"tftacademy-latest" withExtension:@"json"];
    if (url == nil) {
        url = [NSURL fileURLWithPath:[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"data/tftacademy/latest.json"]];
    }

    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data.length == 0) {
        return @[];
    }

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    self.compBadgesByApiName = [self buildCompBadgesByApiNameFromJSON:json];
    self.compBadgesByGodBoonName = [self buildCompBadgesByGodBoonNameFromJSON:json];
    self.allCompBadges = [self buildAllCompBadgesFromJSON:json];
    NSArray *augments = [json[@"augments"] isKindOfClass:NSArray.class] ? json[@"augments"] : @[];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSDictionary *augment in augments) {
        if (![augment isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *apiName = [augment[@"apiName"] isKindOfClass:NSString.class] ? augment[@"apiName"] : @"";
        NSString *displayName = [augment[@"displayName"] isKindOfClass:NSString.class] ? augment[@"displayName"] : [self displayNameFromApiName:apiName];
        NSString *tier = [augment[@"tier"] isKindOfClass:NSString.class] ? augment[@"tier"] : @"";
        NSString *actualTier = [augment[@"actualTier"] isKindOfClass:NSString.class] ? augment[@"actualTier"] : @"";
        NSString *stage = [augment[@"stage"] isKindOfClass:NSString.class] ? augment[@"stage"] : @"";
        if (apiName.length == 0 || displayName.length == 0 || tier.length == 0) {
            continue;
        }

        AugmentTierEntry *entry = [AugmentTierEntry new];
        entry.apiName = apiName;
        entry.displayName = displayName;
        entry.normalizedName = [self normalizedName:displayName];
        entry.tier = tier;
        entry.actualTier = actualTier;
        entry.stage = stage;
        entry.augmentTier = [augment[@"augmentTier"] isKindOfClass:NSNumber.class] ? augment[@"augmentTier"] : nil;
        [entries addObject:entry];
    }
    return entries;
}

- (NSArray<AugmentTierEntry *> *)loadGodEntries {
    NSURL *url = [NSBundle.mainBundle URLForResource:@"metatft-god-tiers" withExtension:@"json"];
    if (url == nil) {
        url = [NSURL fileURLWithPath:[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"data/metatft/god-tiers.json"]];
    }

    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data.length == 0) {
        return @[];
    }

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *boons = [json[@"boons"] isKindOfClass:NSArray.class] ? json[@"boons"] : @[];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSDictionary *boon in boons) {
        if (![boon isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *apiName = [boon[@"apiName"] isKindOfClass:NSString.class] ? boon[@"apiName"] : @"";
        NSString *displayName = [boon[@"displayName"] isKindOfClass:NSString.class] ? boon[@"displayName"] : @"";
        NSString *tier = [boon[@"tier"] isKindOfClass:NSString.class] ? boon[@"tier"] : @"";
        if (displayName.length == 0 || tier.length == 0) {
            continue;
        }
        AugmentTierEntry *entry = [AugmentTierEntry new];
        entry.apiName = apiName.length > 0 ? apiName : displayName;
        entry.displayName = displayName;
        entry.normalizedName = [self normalizedName:displayName];
        entry.tier = tier;
        entry.actualTier = @"";
        entry.stage = @"";
        [entries addObject:entry];
    }
    return entries;
}

- (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)buildCompBadgesByApiNameFromJSON:(NSDictionary *)json {
    NSArray *comps = [json[@"comps"] isKindOfClass:NSArray.class] ? json[@"comps"] : @[];
    NSMutableDictionary<NSString *, NSNumber *> *championCostsByApiName = [NSMutableDictionary dictionary];
    for (NSDictionary *comp in comps) {
        if (![comp isKindOfClass:NSDictionary.class] || ![comp[@"mainChampion"] isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *apiName = [comp[@"mainChampion"][@"apiName"] isKindOfClass:NSString.class] ? comp[@"mainChampion"][@"apiName"] : @"";
        NSNumber *cost = [comp[@"mainChampion"][@"cost"] isKindOfClass:NSNumber.class] ? comp[@"mainChampion"][@"cost"] : nil;
        if (apiName.length > 0 && cost != nil) {
            championCostsByApiName[apiName] = cost;
        }
    }

    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *index = [NSMutableDictionary dictionary];
    for (NSDictionary *comp in comps) {
        if (![comp isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *title = [comp[@"title"] isKindOfClass:NSString.class] ? comp[@"title"] : @"";
        NSString *tier = [comp[@"tier"] isKindOfClass:NSString.class] ? comp[@"tier"] : @"";
        NSString *style = [comp[@"style"] isKindOfClass:NSString.class] ? comp[@"style"] : @"";
        NSString *difficulty = [comp[@"difficulty"] isKindOfClass:NSString.class] ? comp[@"difficulty"] : @"";
        NSString *mainChampion = @"";
        NSNumber *mainChampionCost = nil;
        if ([comp[@"mainChampion"] isKindOfClass:NSDictionary.class]) {
            mainChampion = [comp[@"mainChampion"][@"apiName"] isKindOfClass:NSString.class] ? comp[@"mainChampion"][@"apiName"] : @"";
            mainChampionCost = [comp[@"mainChampion"][@"cost"] isKindOfClass:NSNumber.class] ? comp[@"mainChampion"][@"cost"] : nil;
        }
        NSString *initials = [self initialsForCompTitle:title mainChampion:mainChampion];
        NSMutableDictionary *badge = [@{
            @"title": title.length > 0 ? title : @"Comp",
            @"tier": tier.length > 0 ? tier : @"",
            @"mainChampion": mainChampion.length > 0 ? mainChampion : @"",
            @"championApiName": mainChampion.length > 0 ? mainChampion : @"",
            @"initials": initials.length > 0 ? initials : @"?",
            @"style": style.length > 0 ? style : @"",
            @"difficulty": difficulty.length > 0 ? difficulty : @"",
            @"carousel": [comp[@"carousel"] isKindOfClass:NSArray.class] ? comp[@"carousel"] : @[],
            @"traits": [comp[@"traits"] isKindOfClass:NSArray.class] ? comp[@"traits"] : @[],
            @"tips": [comp[@"tips"] isKindOfClass:NSArray.class] ? comp[@"tips"] : @[]
        } mutableCopy];
        if (mainChampionCost != nil) {
            badge[@"cost"] = mainChampionCost;
        }

        NSArray *finalComp = [comp[@"finalComp"] isKindOfClass:NSArray.class] ? comp[@"finalComp"] : @[];
        NSMutableArray *finalCompWithCosts = [NSMutableArray array];
        for (NSDictionary *unit in finalComp) {
            if (![unit isKindOfClass:NSDictionary.class]) {
                continue;
            }
            NSMutableDictionary *unitCopy = [unit mutableCopy];
            NSString *unitApiName = [unitCopy[@"apiName"] isKindOfClass:NSString.class] ? unitCopy[@"apiName"] : @"";
            if (![unitCopy[@"cost"] isKindOfClass:NSNumber.class] && championCostsByApiName[unitApiName] != nil) {
                unitCopy[@"cost"] = championCostsByApiName[unitApiName];
            }
            [finalCompWithCosts addObject:unitCopy];
        }
        badge[@"finalComp"] = finalCompWithCosts;

        NSMutableSet<NSString *> *apiNames = [NSMutableSet set];
        for (NSString *key in @[@"augments", @"overlayAugments"]) {
            NSArray *values = [comp[key] isKindOfClass:NSArray.class] ? comp[key] : @[];
            for (NSString *apiName in values) {
                if ([apiName isKindOfClass:NSString.class] && apiName.length > 0) {
                    [apiNames addObject:apiName];
                }
            }
        }
        if ([comp[@"mainAugment"] isKindOfClass:NSDictionary.class]) {
            NSString *apiName = comp[@"mainAugment"][@"apiName"];
            if ([apiName isKindOfClass:NSString.class] && apiName.length > 0) {
                [apiNames addObject:apiName];
            }
        }

        for (NSString *apiName in apiNames) {
            if (index[apiName] == nil) {
                index[apiName] = [NSMutableArray array];
            }
            [index[apiName] addObject:[badge copy]];
        }
    }

    NSMutableDictionary *trimmed = [NSMutableDictionary dictionary];
    for (NSString *apiName in index) {
        NSArray *badges = [index[apiName] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSInteger leftRank = [self compTierRank:left[@"tier"]];
            NSInteger rightRank = [self compTierRank:right[@"tier"]];
            if (leftRank != rightRank) {
                return leftRank < rightRank ? NSOrderedAscending : NSOrderedDescending;
            }
            return [left[@"title"] compare:right[@"title"]];
        }];
        trimmed[apiName] = [badges subarrayWithRange:NSMakeRange(0, MIN(badges.count, 5))];
    }
    return trimmed;
}

- (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)buildCompBadgesByGodBoonNameFromJSON:(NSDictionary *)json {
    NSArray *comps = [json[@"comps"] isKindOfClass:NSArray.class] ? json[@"comps"] : @[];
    NSMutableDictionary<NSString *, NSNumber *> *championCostsByApiName = [NSMutableDictionary dictionary];
    for (NSDictionary *comp in comps) {
        if (![comp isKindOfClass:NSDictionary.class] || ![comp[@"mainChampion"] isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *apiName = [comp[@"mainChampion"][@"apiName"] isKindOfClass:NSString.class] ? comp[@"mainChampion"][@"apiName"] : @"";
        NSNumber *cost = [comp[@"mainChampion"][@"cost"] isKindOfClass:NSNumber.class] ? comp[@"mainChampion"][@"cost"] : nil;
        if (apiName.length > 0 && cost != nil) {
            championCostsByApiName[apiName] = cost;
        }
    }

    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *index = [NSMutableDictionary dictionary];
    for (NSDictionary *comp in comps) {
        if (![comp isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSArray *godBoons = [comp[@"godBoons"] isKindOfClass:NSArray.class] ? comp[@"godBoons"] : @[];
        if (godBoons.count == 0) {
            continue;
        }

        NSString *title = [comp[@"title"] isKindOfClass:NSString.class] ? comp[@"title"] : @"";
        NSString *tier = [comp[@"tier"] isKindOfClass:NSString.class] ? comp[@"tier"] : @"";
        NSString *style = [comp[@"style"] isKindOfClass:NSString.class] ? comp[@"style"] : @"";
        NSString *difficulty = [comp[@"difficulty"] isKindOfClass:NSString.class] ? comp[@"difficulty"] : @"";
        NSString *mainChampion = @"";
        NSNumber *mainChampionCost = nil;
        if ([comp[@"mainChampion"] isKindOfClass:NSDictionary.class]) {
            mainChampion = [comp[@"mainChampion"][@"apiName"] isKindOfClass:NSString.class] ? comp[@"mainChampion"][@"apiName"] : @"";
            mainChampionCost = [comp[@"mainChampion"][@"cost"] isKindOfClass:NSNumber.class] ? comp[@"mainChampion"][@"cost"] : nil;
        }

        NSMutableDictionary *badge = [@{
            @"title": title.length > 0 ? title : @"Comp",
            @"tier": tier.length > 0 ? tier : @"",
            @"mainChampion": mainChampion.length > 0 ? mainChampion : @"",
            @"championApiName": mainChampion.length > 0 ? mainChampion : @"",
            @"initials": [self initialsForCompTitle:title mainChampion:mainChampion] ?: @"?",
            @"style": style.length > 0 ? style : @"",
            @"difficulty": difficulty.length > 0 ? difficulty : @"",
            @"carousel": [comp[@"carousel"] isKindOfClass:NSArray.class] ? comp[@"carousel"] : @[],
            @"traits": [comp[@"traits"] isKindOfClass:NSArray.class] ? comp[@"traits"] : @[],
            @"tips": [comp[@"tips"] isKindOfClass:NSArray.class] ? comp[@"tips"] : @[]
        } mutableCopy];
        if (mainChampionCost != nil) {
            badge[@"cost"] = mainChampionCost;
        }

        NSArray *finalComp = [comp[@"finalComp"] isKindOfClass:NSArray.class] ? comp[@"finalComp"] : @[];
        NSMutableArray *finalCompWithCosts = [NSMutableArray array];
        for (NSDictionary *unit in finalComp) {
            if (![unit isKindOfClass:NSDictionary.class]) {
                continue;
            }
            NSMutableDictionary *unitCopy = [unit mutableCopy];
            NSString *unitApiName = [unitCopy[@"apiName"] isKindOfClass:NSString.class] ? unitCopy[@"apiName"] : @"";
            if (![unitCopy[@"cost"] isKindOfClass:NSNumber.class] && championCostsByApiName[unitApiName] != nil) {
                unitCopy[@"cost"] = championCostsByApiName[unitApiName];
            }
            [finalCompWithCosts addObject:unitCopy];
        }
        badge[@"finalComp"] = finalCompWithCosts;

        for (NSDictionary *godBoon in godBoons) {
            NSString *name = @"";
            if ([godBoon isKindOfClass:NSDictionary.class]) {
                name = [godBoon[@"displayName"] isKindOfClass:NSString.class] ? godBoon[@"displayName"] : ([godBoon[@"apiName"] isKindOfClass:NSString.class] ? godBoon[@"apiName"] : @"");
            } else if ([godBoon isKindOfClass:NSString.class]) {
                name = (NSString *)godBoon;
            }
            NSString *normalized = [self normalizedName:name];
            if (normalized.length == 0) {
                continue;
            }
            if (index[normalized] == nil) {
                index[normalized] = [NSMutableArray array];
            }
            [index[normalized] addObject:[badge copy]];
        }
    }

    NSMutableDictionary *trimmed = [NSMutableDictionary dictionary];
    for (NSString *name in index) {
        NSArray *badges = [index[name] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSInteger leftRank = [self compTierRank:left[@"tier"]];
            NSInteger rightRank = [self compTierRank:right[@"tier"]];
            if (leftRank != rightRank) {
                return leftRank < rightRank ? NSOrderedAscending : NSOrderedDescending;
            }
            return [left[@"title"] compare:right[@"title"]];
        }];
        trimmed[name] = [badges subarrayWithRange:NSMakeRange(0, MIN(badges.count, 5))];
    }
    return trimmed;
}

- (NSArray<NSDictionary *> *)buildAllCompBadgesFromJSON:(NSDictionary *)json {
    NSArray *comps = [json[@"comps"] isKindOfClass:NSArray.class] ? json[@"comps"] : @[];
    NSMutableDictionary<NSString *, NSNumber *> *championCostsByApiName = [NSMutableDictionary dictionary];
    for (NSDictionary *champion in [json[@"champions"] isKindOfClass:NSArray.class] ? json[@"champions"] : @[]) {
        if (![champion isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *apiName = [champion[@"apiName"] isKindOfClass:NSString.class] ? champion[@"apiName"] : @"";
        NSNumber *cost = [champion[@"cost"] isKindOfClass:NSNumber.class] ? champion[@"cost"] : nil;
        if (apiName.length > 0 && cost != nil) {
            championCostsByApiName[apiName] = cost;
        }
    }

    NSMutableArray *badges = [NSMutableArray array];
    for (NSDictionary *comp in comps) {
        if (![comp isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *title = [comp[@"title"] isKindOfClass:NSString.class] ? comp[@"title"] : @"";
        NSString *tier = [comp[@"tier"] isKindOfClass:NSString.class] ? comp[@"tier"] : @"";
        NSString *style = [comp[@"style"] isKindOfClass:NSString.class] ? comp[@"style"] : @"";
        NSString *difficulty = [comp[@"difficulty"] isKindOfClass:NSString.class] ? comp[@"difficulty"] : @"";
        NSString *mainChampion = @"";
        NSNumber *mainChampionCost = nil;
        if ([comp[@"mainChampion"] isKindOfClass:NSDictionary.class]) {
            mainChampion = [comp[@"mainChampion"][@"apiName"] isKindOfClass:NSString.class] ? comp[@"mainChampion"][@"apiName"] : @"";
            mainChampionCost = [comp[@"mainChampion"][@"cost"] isKindOfClass:NSNumber.class] ? comp[@"mainChampion"][@"cost"] : championCostsByApiName[mainChampion];
        }
        NSMutableDictionary *badge = [@{
            @"title": title.length > 0 ? title : @"Comp",
            @"tier": tier.length > 0 ? tier : @"",
            @"mainChampion": mainChampion.length > 0 ? mainChampion : @"",
            @"championApiName": mainChampion.length > 0 ? mainChampion : @"",
            @"initials": [self initialsForCompTitle:title mainChampion:mainChampion] ?: @"?",
            @"style": style.length > 0 ? style : @"",
            @"difficulty": difficulty.length > 0 ? difficulty : @"",
            @"carousel": [comp[@"carousel"] isKindOfClass:NSArray.class] ? comp[@"carousel"] : @[],
            @"traits": [comp[@"traits"] isKindOfClass:NSArray.class] ? comp[@"traits"] : @[],
            @"tips": [comp[@"tips"] isKindOfClass:NSArray.class] ? comp[@"tips"] : @[]
        } mutableCopy];
        if (mainChampionCost != nil) {
            badge[@"cost"] = mainChampionCost;
        }
        badge[@"earlyComp"] = [self compUnitsWithCosts:[comp[@"earlyComp"] isKindOfClass:NSArray.class] ? comp[@"earlyComp"] : @[] costs:championCostsByApiName];
        badge[@"finalComp"] = [self compUnitsWithCosts:[comp[@"finalComp"] isKindOfClass:NSArray.class] ? comp[@"finalComp"] : @[] costs:championCostsByApiName];
        badge[@"earlyUnitApiNames"] = [self apiNamesFromUnits:badge[@"earlyComp"]];
        badge[@"finalUnitApiNames"] = [self apiNamesFromUnits:badge[@"finalComp"]];
        [badges addObject:[badge copy]];
    }
    return [badges sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSInteger leftRank = [self compTierRank:left[@"tier"]];
        NSInteger rightRank = [self compTierRank:right[@"tier"]];
        if (leftRank != rightRank) {
            return leftRank < rightRank ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left[@"title"] compare:right[@"title"]];
    }];
}

- (NSArray *)compUnitsWithCosts:(NSArray *)units costs:(NSDictionary<NSString *, NSNumber *> *)costs {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *unit in units) {
        if (![unit isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSMutableDictionary *unitCopy = [unit mutableCopy];
        NSString *apiName = [unitCopy[@"apiName"] isKindOfClass:NSString.class] ? unitCopy[@"apiName"] : @"";
        if (![unitCopy[@"cost"] isKindOfClass:NSNumber.class] && costs[apiName] != nil) {
            unitCopy[@"cost"] = costs[apiName];
        }
        [result addObject:unitCopy];
    }
    return result;
}

- (NSArray<NSString *> *)apiNamesFromUnits:(NSArray *)units {
    NSMutableArray<NSString *> *apiNames = [NSMutableArray array];
    for (NSDictionary *unit in units) {
        if (![unit isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *apiName = [unit[@"apiName"] isKindOfClass:NSString.class] ? unit[@"apiName"] : @"";
        if (apiName.length > 0) {
            [apiNames addObject:apiName];
        }
    }
    return apiNames;
}

- (NSDictionary *)compSuggestionForBoardReconstruction:(NSDictionary *)boardReconstruction level:(NSInteger)level selectedTitle:(NSString *)selectedTitle {
    if (self.allCompBadges.count == 0) {
        return nil;
    }

    NSString *normalizedSelected = [self normalizedName:selectedTitle ?: @""];
    if (normalizedSelected.length > 0) {
        for (NSDictionary *badge in self.allCompBadges) {
            NSString *title = [badge[@"title"] isKindOfClass:NSString.class] ? badge[@"title"] : @"";
            if ([[self normalizedName:title] isEqualToString:normalizedSelected]) {
                NSMutableDictionary *locked = [badge mutableCopy];
                locked[@"locked"] = @YES;
                return @{@"label": @"Selected:", @"selectedTitle": title, @"mode": @"selected", @"comps": @[[locked copy]]};
            }
        }
    }

    if (![boardReconstruction isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSArray *units = [boardReconstruction[@"units"] isKindOfClass:NSArray.class] ? boardReconstruction[@"units"] : @[];
    NSMutableSet<NSString *> *boardApiNames = [NSMutableSet set];
    for (NSDictionary *unit in units) {
        NSString *apiName = [unit[@"apiName"] isKindOfClass:NSString.class] ? unit[@"apiName"] : @"";
        if (apiName.length > 0) {
            [boardApiNames addObject:apiName];
        }
    }
    if (boardApiNames.count == 0) {
        return nil;
    }

    BOOL earlyMode = level <= 5 && boardApiNames.count >= 1 && boardApiNames.count <= 4;
    NSMutableArray *scored = [NSMutableArray array];
    for (NSDictionary *badge in self.allCompBadges) {
        NSString *tier = [badge[@"tier"] isKindOfClass:NSString.class] ? badge[@"tier"] : @"";
        if (earlyMode && [tier isEqualToString:@"X"]) {
            continue;
        }
        NSArray *targetUnits = earlyMode ? badge[@"earlyUnitApiNames"] : badge[@"finalUnitApiNames"];
        if (![targetUnits isKindOfClass:NSArray.class] || targetUnits.count == 0) {
            continue;
        }
        NSInteger matches = 0;
        for (NSString *apiName in targetUnits) {
            if ([boardApiNames containsObject:apiName]) {
                matches += 1;
            }
        }
        if (matches <= 0) {
            continue;
        }
        NSMutableDictionary *copy = [badge mutableCopy];
        copy[@"matchCount"] = @(matches);
        copy[@"targetCount"] = @(targetUnits.count);
        [scored addObject:[copy copy]];
    }
    if (scored.count == 0) {
        return nil;
    }

    NSArray *sorted = [scored sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSInteger leftMatches = [left[@"matchCount"] integerValue];
        NSInteger rightMatches = [right[@"matchCount"] integerValue];
        if (leftMatches != rightMatches) {
            return leftMatches > rightMatches ? NSOrderedAscending : NSOrderedDescending;
        }
        NSString *leftTier = [left[@"tier"] isKindOfClass:NSString.class] ? left[@"tier"] : @"";
        NSString *rightTier = [right[@"tier"] isKindOfClass:NSString.class] ? right[@"tier"] : @"";
        BOOL leftX = [leftTier isEqualToString:@"X"];
        BOOL rightX = [rightTier isEqualToString:@"X"];
        if (leftX != rightX) {
            return leftX ? NSOrderedDescending : NSOrderedAscending;
        }
        NSInteger leftRank = [self compTierRank:left[@"tier"]];
        NSInteger rightRank = [self compTierRank:right[@"tier"]];
        if (leftRank != rightRank) {
            return leftRank < rightRank ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left[@"title"] compare:right[@"title"]];
    }];

    if (earlyMode) {
        return @{@"label": @"Can play into:", @"mode": @"early", @"comps": [sorted subarrayWithRange:NSMakeRange(0, MIN(sorted.count, 5))]};
    }

    NSInteger best = [[sorted.firstObject objectForKey:@"matchCount"] integerValue];
    NSMutableArray *close = [NSMutableArray array];
    for (NSDictionary *badge in sorted) {
        NSInteger matches = [badge[@"matchCount"] integerValue];
        if (matches >= MAX(1, best - 1)) {
            [close addObject:badge];
        }
        if (close.count >= 3) {
            break;
        }
    }
    NSString *label = close.count > 1 ? @"Are you playing?" : @"Can play into:";
    return @{@"label": label, @"mode": close.count > 1 ? @"question" : @"best", @"comps": close};
}

- (NSInteger)compTierRank:(NSString *)tier {
    if ([tier isEqualToString:@"X"]) return 0;
    if ([tier isEqualToString:@"S"]) return 0;
    if ([tier isEqualToString:@"A"]) return 1;
    if ([tier isEqualToString:@"B"]) return 2;
    if ([tier isEqualToString:@"C"]) return 3;
    return 9;
}

- (NSString *)initialsForCompTitle:(NSString *)title mainChampion:(NSString *)mainChampion {
    NSString *source = title.length > 0 ? title : mainChampion;
    NSArray<NSString *> *parts = [source componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableString *initials = [NSMutableString string];
    for (NSString *part in parts) {
        if (part.length == 0) {
            continue;
        }
        unichar c = [part characterAtIndex:0];
        if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) {
            [initials appendFormat:@"%C", c];
        }
        if (initials.length >= 2) {
            break;
        }
    }
    return initials.uppercaseString;
}

- (NSArray<NSDictionary *> *)matchesForVisionSnapshot:(NSDictionary *)visionSnapshot {
    if (self.entries.count == 0 || ![visionSnapshot[@"available"] boolValue]) {
        return @[];
    }

    NSArray *regions = [visionSnapshot[@"regions"] isKindOfClass:NSArray.class] ? visionSnapshot[@"regions"] : @[];
    NSMutableArray *matches = [NSMutableArray array];
    for (NSInteger slot = 0; slot < 3; slot += 1) {
        NSString *regionID = [NSString stringWithFormat:@"augment_%ld", slot + 1];
        NSString *ocrText = [self textForRegion:regionID regions:regions];
        NSDictionary *match = [self matchForText:ocrText slot:slot stage:@""];
        if (match != nil) {
            [matches addObject:match];
        }
    }
    return matches.count == 3 ? matches : @[];
}

- (NSArray<NSDictionary *> *)godBoonMatchesForVisionSnapshot:(NSDictionary *)visionSnapshot {
    if (self.godEntries.count == 0 || ![visionSnapshot[@"available"] boolValue]) {
        return @[];
    }

    NSArray *regions = [visionSnapshot[@"regions"] isKindOfClass:NSArray.class] ? visionSnapshot[@"regions"] : @[];
    NSMutableArray *matches = [NSMutableArray array];
    for (NSInteger slot = 0; slot < 2; slot += 1) {
        NSString *regionID = [NSString stringWithFormat:@"god_boon_%ld", slot + 1];
        NSString *ocrText = [self textForRegion:regionID regions:regions];
        NSDictionary *match = [self godBoonMatchForText:ocrText slot:slot];
        if (match != nil) {
            [matches addObject:match];
        }
    }
    return matches;
}

- (NSDictionary *)godBoonMatchForText:(NSString *)text slot:(NSInteger)slot {
    NSString *normalizedText = [self normalizedName:text];
    if (normalizedText.length < 4) {
        return nil;
    }

    AugmentTierEntry *bestEntry = nil;
    double bestScore = 0;
    for (AugmentTierEntry *entry in self.godEntries) {
        double score = [self fuzzyContainmentScoreForText:normalizedText candidate:entry.normalizedName];
        if (score > bestScore) {
            bestScore = score;
            bestEntry = entry;
        }
    }
    if (bestEntry == nil || bestScore < 0.74) {
        return nil;
    }

    NSString *normalizedName = [self normalizedName:bestEntry.displayName];
    return @{
        @"slot": @(slot),
        @"tier": bestEntry.tier ?: @"",
        @"apiName": bestEntry.apiName ?: @"",
        @"displayName": bestEntry.displayName ?: @"",
        @"compBadges": self.compBadgesByGodBoonName[normalizedName] ?: @[],
        @"ocrText": text ?: @"",
        @"matchScore": @(bestScore)
    };
}

- (double)fuzzyContainmentScoreForText:(NSString *)text candidate:(NSString *)candidate {
    if (text.length == 0 || candidate.length == 0) {
        return 0;
    }
    if ([text containsString:candidate]) {
        return 1.0;
    }
    if (text.length <= candidate.length) {
        return [self similarityBetween:text and:candidate];
    }

    double bestScore = [self similarityBetween:text and:candidate] * 0.72;
    NSInteger candidateLength = (NSInteger)candidate.length;
    NSInteger textLength = (NSInteger)text.length;
    NSInteger minLength = MAX(4, candidateLength - 3);
    NSInteger maxLength = MIN(textLength, candidateLength + 4);
    for (NSInteger windowLength = minLength; windowLength <= maxLength; windowLength += 1) {
        if (windowLength > textLength) {
            break;
        }
        for (NSInteger start = 0; start + windowLength <= textLength; start += 1) {
            NSString *window = [text substringWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)windowLength)];
            double score = [self similarityBetween:window and:candidate];
            if (score > bestScore) {
                bestScore = score;
            }
        }
    }
    return bestScore;
}

- (NSDictionary *)matchForText:(NSString *)text slot:(NSInteger)slot stage:(NSString *)stage {
    NSString *normalizedText = [self normalizedName:text];
    if (normalizedText.length < 4) {
        return nil;
    }

    NSMutableDictionary<NSString *, AugmentTierEntry *> *bestByApiName = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *scoreByApiName = [NSMutableDictionary dictionary];
    for (AugmentTierEntry *entry in self.entries) {
        if (entry.normalizedName.length == 0) {
            continue;
        }
        double score = [self similarityBetween:normalizedText and:entry.normalizedName];
        NSNumber *previous = scoreByApiName[entry.apiName];
        if (previous == nil || score > previous.doubleValue) {
            scoreByApiName[entry.apiName] = @(score);
            bestByApiName[entry.apiName] = entry;
        }
    }

    NSString *bestApiName = nil;
    double bestScore = 0;
    for (NSString *apiName in scoreByApiName) {
        double score = scoreByApiName[apiName].doubleValue;
        if (score > bestScore) {
            bestScore = score;
            bestApiName = apiName;
        }
    }

    if (bestApiName.length == 0 || bestScore < 0.75) {
        return nil;
    }

    AugmentTierEntry *entry = [self tierEntryForApiName:bestApiName stage:stage] ?: bestByApiName[bestApiName];
    if (entry == nil) {
        return nil;
    }

    BOOL isHeroAugment = [self isHeroAugmentName:entry.displayName];
    NSString *displayTier = isHeroAugment ? @"X" : (entry.tier ?: @"");
    NSString *actualTier = isHeroAugment ? (entry.tier ?: @"") : (entry.actualTier ?: @"");

    return @{
        @"slot": @(slot),
        @"tier": displayTier,
        @"actualTier": actualTier,
        @"stage": entry.stage ?: @"",
        @"augmentTier": entry.augmentTier ?: [NSNull null],
        @"apiName": entry.apiName ?: @"",
        @"displayName": entry.displayName ?: @"",
        @"compBadges": self.compBadgesByApiName[entry.apiName] ?: @[],
        @"ocrText": text ?: @"",
        @"matchScore": @(bestScore)
    };
}

- (BOOL)isHeroAugmentName:(NSString *)name {
    NSString *normalized = [self normalizedHeroName:name];
    NSSet<NSString *> *heroNames = [NSSet setWithArray:@[
        @"selfdestruct",
        @"thebigbang",
        @"invaderzed",
        @"shieldmaiden",
        @"stellarcombo",
        @"reachforthestars",
        @"heatdeath",
        @"termeepnalvelocity",
        @"terminalvelocity",
        @"bonk",
        @"contractkiller"
    ]];
    return [heroNames containsObject:normalized];
}

- (NSString *)normalizedHeroName:(NSString *)name {
    NSMutableString *normalized = [NSMutableString string];
    NSString *lower = (name ?: @"").lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i += 1) {
        unichar c = [lower characterAtIndex:i];
        if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) {
            [normalized appendFormat:@"%C", c];
        }
    }
    return normalized;
}

- (AugmentTierEntry *)tierEntryForApiName:(NSString *)apiName stage:(NSString *)stage {
    AugmentTierEntry *allStage = nil;
    AugmentTierEntry *first = nil;
    for (AugmentTierEntry *entry in self.entries) {
        if (![entry.apiName isEqualToString:apiName]) {
            continue;
        }
        if (first == nil) {
            first = entry;
        }
        if (stage.length > 0 && [entry.stage isEqualToString:stage]) {
            return entry;
        }
        if ([entry.stage isEqualToString:@"All"]) {
            allStage = entry;
        }
    }
    return allStage ?: first;
}

- (NSString *)textForRegion:(NSString *)regionID regions:(NSArray *)regions {
    for (NSDictionary *region in regions) {
        if (![region isKindOfClass:NSDictionary.class]) {
            continue;
        }
        if ([region[@"id"] isEqualToString:regionID]) {
            if ([region[@"cleanText"] isKindOfClass:NSString.class]) {
                return region[@"cleanText"];
            }
            if ([region[@"text"] isKindOfClass:NSString.class]) {
                return region[@"text"];
            }
        }
    }
    return @"";
}

- (NSString *)normalizedStageFromRoundText:(NSString *)text {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[234]-[12]" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:text ?: @"" options:0 range:NSMakeRange(0, text.length)];
    if (match == nil) {
        return @"";
    }
    return [text substringWithRange:match.range];
}

- (NSString *)displayNameFromApiName:(NSString *)apiName {
    NSString *name = apiName ?: @"";
    NSArray *prefixes = @[@"TFT10_Augment_", @"TFT11_Augment_", @"TFT12_Augment_", @"TFT13_Augment_", @"TFT14_Augment_", @"TFT15_Augment_", @"TFT16_Augment_", @"TFT17_Augment_", @"TFT9_Augment_", @"TFT8_Augment_", @"TFT7_Augment_", @"TFT6_Augment_", @"TFT_Augment_"];
    for (NSString *prefix in prefixes) {
        if ([name hasPrefix:prefix]) {
            name = [name substringFromIndex:prefix.length];
            break;
        }
    }
    name = [name stringByReplacingOccurrencesOfString:@"_PAIRS" withString:@""];
    name = [name stringByReplacingOccurrencesOfString:@"_" withString:@" "];

    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < name.length; i += 1) {
        unichar c = [name characterAtIndex:i];
        if (i > 0) {
            unichar previous = [name characterAtIndex:i - 1];
            if ([[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c] &&
                [[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:previous]) {
                [result appendString:@" "];
            }
        }
        [result appendFormat:@"%C", c];
    }
    return result;
}

- (NSString *)normalizedName:(NSString *)name {
    NSMutableString *normalized = [NSMutableString string];
    NSString *lower = (name ?: @"").lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i += 1) {
        unichar c = [lower characterAtIndex:i];
        if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) {
            [normalized appendFormat:@"%C", c];
        }
    }
    return normalized;
}

- (double)similarityBetween:(NSString *)left and:(NSString *)right {
    NSUInteger maxLength = MAX(left.length, right.length);
    if (maxLength == 0) {
        return 0;
    }
    NSUInteger distance = [self editDistanceBetween:left and:right];
    return 1.0 - ((double)distance / (double)maxLength);
}

- (NSUInteger)editDistanceBetween:(NSString *)left and:(NSString *)right {
    NSUInteger leftCount = left.length;
    NSUInteger rightCount = right.length;
    NSMutableArray<NSNumber *> *previous = [NSMutableArray arrayWithCapacity:rightCount + 1];
    NSMutableArray<NSNumber *> *current = [NSMutableArray arrayWithCapacity:rightCount + 1];
    for (NSUInteger j = 0; j <= rightCount; j += 1) {
        [previous addObject:@(j)];
        [current addObject:@0];
    }

    for (NSUInteger i = 1; i <= leftCount; i += 1) {
        current[0] = @(i);
        unichar leftChar = [left characterAtIndex:i - 1];
        for (NSUInteger j = 1; j <= rightCount; j += 1) {
            unichar rightChar = [right characterAtIndex:j - 1];
            NSUInteger cost = leftChar == rightChar ? 0 : 1;
            NSUInteger deletion = previous[j].unsignedIntegerValue + 1;
            NSUInteger insertion = current[j - 1].unsignedIntegerValue + 1;
            NSUInteger substitution = previous[j - 1].unsignedIntegerValue + cost;
            current[j] = @(MIN(MIN(deletion, insertion), substitution));
        }
        NSArray *swap = previous;
        previous = [current mutableCopy];
        current = [swap mutableCopy];
    }

    return previous[rightCount].unsignedIntegerValue;
}
@end

@interface UnitBuildRecommender : NSObject
@property(nonatomic, strong) NSDictionary<NSString *, NSDictionary *> *unitsByNormalizedName;
@property(nonatomic, strong) NSArray<NSDictionary *> *unitEntries;
- (nullable NSDictionary *)recommendationForUnitName:(NSString *)unitName;
@end

@implementation UnitBuildRecommender
- (instancetype)init {
    self = [super init];
    if (self) {
        _unitsByNormalizedName = [self loadUnits];
    }
    return self;
}

- (NSDictionary<NSString *, NSDictionary *> *)loadUnits {
    NSURL *url = [NSBundle.mainBundle URLForResource:@"metatft-latest" withExtension:@"json"];
    if (url == nil) {
        url = [NSURL fileURLWithPath:[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"data/metatft/latest.json"]];
    }
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data.length == 0) {
        return @{};
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *units = [json[@"units"] isKindOfClass:NSArray.class] ? json[@"units"] : @[];
    NSMutableDictionary *index = [NSMutableDictionary dictionary];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSDictionary *unit in units) {
        if (![unit isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *name = [unit[@"name"] isKindOfClass:NSString.class] ? unit[@"name"] : @"";
        if (name.length > 0) {
            NSString *normalized = [self normalizedName:name];
            index[normalized] = unit;
            [entries addObject:@{@"name": name, @"normalized": normalized, @"unit": unit}];
        }
    }
    self.unitEntries = entries;
    return index;
}

- (NSDictionary *)recommendationForUnitName:(NSString *)unitName {
    NSString *normalized = [self normalizedName:unitName];
    NSDictionary *unit = self.unitsByNormalizedName[normalized];
    double matchScore = unit != nil ? 1.0 : 0;
    if (unit == nil && normalized.length >= 3) {
        NSDictionary *bestEntry = nil;
        double bestScore = 0;
        for (NSDictionary *entry in self.unitEntries) {
            NSString *candidate = [entry[@"normalized"] isKindOfClass:NSString.class] ? entry[@"normalized"] : @"";
            if (candidate.length == 0) {
                continue;
            }
            double score = [self fuzzyScoreForNormalizedOCR:normalized candidate:candidate];
            if (score > bestScore) {
                bestScore = score;
                bestEntry = entry;
            }
        }
        if (bestScore >= 0.50 && [bestEntry[@"unit"] isKindOfClass:NSDictionary.class]) {
            unit = bestEntry[@"unit"];
            matchScore = bestScore;
        }
    }
    if (unit == nil) {
        return nil;
    }
    NSArray *builds = [unit[@"builds"] isKindOfClass:NSArray.class] ? unit[@"builds"] : @[];
    if (builds.count == 0) {
        return nil;
    }
    return @{
        @"name": [unit[@"name"] isKindOfClass:NSString.class] ? unit[@"name"] : unitName,
        @"builds": builds,
        @"ocrText": unitName ?: @"",
        @"matchScore": @(matchScore)
    };
}

- (NSString *)normalizedName:(NSString *)name {
    NSMutableString *result = [NSMutableString string];
    NSString *lower = (name ?: @"").lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i += 1) {
        unichar c = [lower characterAtIndex:i];
        if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) {
            [result appendFormat:@"%C", c];
        }
    }
    return result;
}

- (double)fuzzyScoreForNormalizedOCR:(NSString *)ocr candidate:(NSString *)candidate {
    if (ocr.length == 0 || candidate.length == 0) {
        return 0;
    }
    if ([ocr isEqualToString:candidate]) {
        return 1;
    }
    if ([candidate hasPrefix:ocr] && ocr.length >= 3) {
        return 0.78 + MIN(0.16, (double)ocr.length / MAX(1.0, (double)candidate.length) * 0.16);
    }
    double edit = [self editSimilarityBetween:ocr and:candidate];
    if ([ocr characterAtIndex:0] == [candidate characterAtIndex:0]) {
        return MAX(edit, [self orderedCharacterScoreForOCR:ocr candidate:candidate] * 0.76);
    }
    return edit * 0.82;
}

- (double)editSimilarityBetween:(NSString *)left and:(NSString *)right {
    NSUInteger maxLength = MAX(left.length, right.length);
    if (maxLength == 0) {
        return 0;
    }
    return 1.0 - ((double)[self editDistanceBetween:left and:right] / (double)maxLength);
}

- (NSUInteger)editDistanceBetween:(NSString *)left and:(NSString *)right {
    NSUInteger leftCount = left.length;
    NSUInteger rightCount = right.length;
    NSMutableArray<NSNumber *> *previous = [NSMutableArray arrayWithCapacity:rightCount + 1];
    NSMutableArray<NSNumber *> *current = [NSMutableArray arrayWithCapacity:rightCount + 1];
    for (NSUInteger j = 0; j <= rightCount; j += 1) {
        [previous addObject:@(j)];
        [current addObject:@0];
    }
    for (NSUInteger i = 1; i <= leftCount; i += 1) {
        current[0] = @(i);
        unichar leftChar = [left characterAtIndex:i - 1];
        for (NSUInteger j = 1; j <= rightCount; j += 1) {
            unichar rightChar = [right characterAtIndex:j - 1];
            NSUInteger cost = leftChar == rightChar ? 0 : 1;
            NSUInteger deletion = previous[j].unsignedIntegerValue + 1;
            NSUInteger insertion = current[j - 1].unsignedIntegerValue + 1;
            NSUInteger substitution = previous[j - 1].unsignedIntegerValue + cost;
            current[j] = @(MIN(MIN(deletion, insertion), substitution));
        }
        NSArray *swap = previous;
        previous = [current mutableCopy];
        current = [swap mutableCopy];
    }
    return previous[rightCount].unsignedIntegerValue;
}

- (double)orderedCharacterScoreForOCR:(NSString *)ocr candidate:(NSString *)candidate {
    NSUInteger matched = 0;
    NSUInteger searchStart = 0;
    for (NSUInteger i = 0; i < ocr.length; i += 1) {
        unichar c = [ocr characterAtIndex:i];
        BOOL found = NO;
        for (NSUInteger j = searchStart; j < candidate.length; j += 1) {
            if ([candidate characterAtIndex:j] == c) {
                matched += 1;
                searchStart = j + 1;
                found = YES;
                break;
            }
        }
        if (!found && i == 0) {
            return 0;
        }
    }
    return (double)matched / (double)MAX(ocr.length, candidate.length);
}
@end

@interface BoardUnitReconstructor : NSObject
@property(nonatomic, strong) NSArray<NSDictionary *> *champions;
@property(nonatomic) NSInteger searchNodeBudget;
- (nullable NSDictionary *)reconstructionForTraitList:(NSDictionary *)traitList levelText:(NSString *)levelText;
@end

@implementation BoardUnitReconstructor
- (instancetype)init {
    self = [super init];
    if (self) {
        _champions = [self loadChampions];
    }
    return self;
}

- (NSArray<NSDictionary *> *)loadChampions {
    NSURL *url = [NSBundle.mainBundle URLForResource:@"tftacademy-latest" withExtension:@"json"];
    if (url == nil) {
        url = [NSURL fileURLWithPath:[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"data/tftacademy/latest.json"]];
    }
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data.length == 0) {
        return @[];
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSString *currentPrefix = [self currentChampionApiPrefixForJSON:json];
    NSArray *champions = [json[@"champions"] isKindOfClass:NSArray.class] ? json[@"champions"] : @[];
    if (champions.count > 0) {
        return [self normalizedChampionRosterFromArray:champions currentPrefix:currentPrefix];
    }

    NSArray *comps = [json[@"comps"] isKindOfClass:NSArray.class] ? json[@"comps"] : @[];
    NSMutableDictionary<NSString *, NSDictionary *> *unique = [NSMutableDictionary dictionary];
    for (NSDictionary *comp in comps) {
        if (![comp isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSMutableArray *units = [NSMutableArray array];
        if ([comp[@"mainChampion"] isKindOfClass:NSDictionary.class]) {
            [units addObject:comp[@"mainChampion"]];
        }
        if ([comp[@"finalComp"] isKindOfClass:NSArray.class]) {
            [units addObjectsFromArray:comp[@"finalComp"]];
        }
        if ([comp[@"earlyComp"] isKindOfClass:NSArray.class]) {
            [units addObjectsFromArray:comp[@"earlyComp"]];
        }
        for (NSDictionary *unit in units) {
            if (![unit isKindOfClass:NSDictionary.class]) {
                continue;
            }
            NSString *apiName = [unit[@"apiName"] isKindOfClass:NSString.class] ? unit[@"apiName"] : @"";
            NSArray *traits = [unit[@"traits"] isKindOfClass:NSArray.class] ? unit[@"traits"] : @[];
            if ([self isRosterChampionApiName:apiName currentPrefix:currentPrefix] && traits.count > 0) {
                unique[apiName] = unit;
            }
        }
    }
    return [self normalizedChampionRosterFromArray:unique.allValues currentPrefix:currentPrefix];
}

- (NSArray<NSDictionary *> *)normalizedChampionRosterFromArray:(NSArray *)rawChampions currentPrefix:(NSString *)currentPrefix {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *champion in rawChampions) {
        if (![champion isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *apiName = [champion[@"apiName"] isKindOfClass:NSString.class] ? champion[@"apiName"] : @"";
        NSString *name = [champion[@"name"] isKindOfClass:NSString.class] ? champion[@"name"] : [self displayNameFromApiName:apiName];
        NSArray *traits = [champion[@"traits"] isKindOfClass:NSArray.class] ? champion[@"traits"] : @[];
        if (![self isRosterChampionApiName:apiName currentPrefix:currentPrefix] || name.length == 0 || traits.count == 0) {
            continue;
        }
        NSMutableArray *normalizedTraits = [NSMutableArray array];
        for (NSString *trait in traits) {
            if ([trait isKindOfClass:NSString.class]) {
                [normalizedTraits addObject:[self normalizedName:trait]];
            }
        }
        NSNumber *cost = [champion[@"cost"] isKindOfClass:NSNumber.class] ? champion[@"cost"] : @0;
        [result addObject:@{
            @"apiName": apiName,
            @"name": name,
            @"cost": cost,
            @"traits": traits,
            @"normalizedTraits": normalizedTraits
        }];
    }
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSInteger leftCost = [left[@"cost"] integerValue];
        NSInteger rightCost = [right[@"cost"] integerValue];
        if (leftCost != rightCost) {
            return leftCost < rightCost ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left[@"name"] compare:right[@"name"]];
    }];
}

- (NSString *)currentChampionApiPrefixForJSON:(NSDictionary *)json {
    NSNumber *setNumber = [json[@"set"] isKindOfClass:NSNumber.class] ? json[@"set"] : nil;
    if (setNumber == nil || setNumber.integerValue <= 0) {
        return @"";
    }
    return [NSString stringWithFormat:@"TFT%ld_", (long)setNumber.integerValue];
}

- (BOOL)isRosterChampionApiName:(NSString *)apiName currentPrefix:(NSString *)currentPrefix {
    if (apiName.length == 0) {
        return NO;
    }
    if (currentPrefix.length > 0 && ![apiName hasPrefix:currentPrefix]) {
        return NO;
    }
    if ([apiName rangeOfString:@"FakeUnit" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return NO;
    }
    if ([apiName hasSuffix:@"_Summon"] || [apiName hasSuffix:@"_Relic"]) {
        return NO;
    }
    return YES;
}

- (NSDictionary *)reconstructionForTraitList:(NSDictionary *)traitList levelText:(NSString *)levelText {
    NSArray *traits = [traitList[@"traits"] isKindOfClass:NSArray.class] ? traitList[@"traits"] : @[];
    NSArray *partialTraits = [traitList[@"partialTraits"] isKindOfClass:NSArray.class] ? traitList[@"partialTraits"] : @[];
    if ((traits.count == 0 && partialTraits.count == 0) || self.champions.count == 0) {
        return nil;
    }

    NSMutableDictionary<NSString *, NSNumber *> *targetCounts = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *displayNames = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *targetSources = [NSMutableDictionary dictionary];
    for (NSDictionary *trait in traits) {
        NSString *name = [trait[@"name"] isKindOfClass:NSString.class] ? trait[@"name"] : @"";
        NSNumber *count = [trait[@"count"] isKindOfClass:NSNumber.class] ? trait[@"count"] : nil;
        NSString *normalized = [self normalizedName:name];
        if (normalized.length == 0 || count == nil || count.integerValue <= 0) {
            continue;
        }
        targetCounts[normalized] = count;
        displayNames[normalized] = name;
        targetSources[normalized] = @"active";
    }
    for (NSDictionary *trait in partialTraits) {
        NSString *name = [trait[@"name"] isKindOfClass:NSString.class] ? trait[@"name"] : @"";
        NSNumber *count = [trait[@"count"] isKindOfClass:NSNumber.class] ? trait[@"count"] : nil;
        NSString *normalized = [self normalizedName:name];
        if (normalized.length == 0 || count == nil || count.integerValue <= 0 || targetCounts[normalized] != nil) {
            continue;
        }
        targetCounts[normalized] = count;
        displayNames[normalized] = name;
        targetSources[normalized] = @"partial";
    }
    if (targetCounts.count == 0) {
        return nil;
    }
    NSInteger extraTraitAllowance = 0;
    if ([traitList[@"extraTraitAllowance"] isKindOfClass:NSNumber.class]) {
        extraTraitAllowance = MAX(0, [traitList[@"extraTraitAllowance"] integerValue]);
    }

    NSInteger level = [[self firstRegexMatch:@"[0-9]+" inString:levelText ?: @""] integerValue];
    if (level <= 0) {
        level = MIN(10, MAX(1, (NSInteger)targetCounts.count));
    }

    NSDictionary<NSString *, NSArray<NSDictionary *> *> *uniqueTraitOwners = [self uniqueTraitOwnersForChampions:self.champions];
    NSMutableArray<NSDictionary *> *eligible = [NSMutableArray array];
    for (NSDictionary *champion in self.champions) {
        NSArray *normalizedTraits = [champion[@"normalizedTraits"] isKindOfClass:NSArray.class] ? champion[@"normalizedTraits"] : @[];
        BOOL contributes = NO;
        BOOL hasUnseenUniqueTrait = NO;
        for (NSString *trait in normalizedTraits) {
            if (uniqueTraitOwners[trait] != nil && targetCounts[trait] == nil) {
                hasUnseenUniqueTrait = YES;
                break;
            }
            if (targetCounts[trait] != nil) {
                contributes = YES;
            }
        }
        if (contributes && !hasUnseenUniqueTrait) {
            [eligible addObject:champion];
        }
    }
    if (eligible.count == 0) {
        return nil;
    }

    NSSet *targetTraitSet = [NSSet setWithArray:targetCounts.allKeys];
    NSMutableSet<NSString *> *eligibleApiNames = [NSMutableSet set];
    for (NSDictionary *champion in eligible) {
        NSString *apiName = [champion[@"apiName"] isKindOfClass:NSString.class] ? champion[@"apiName"] : @"";
        if (apiName.length > 0) {
            [eligibleApiNames addObject:apiName];
        }
    }
    NSMutableSet<NSString *> *forcedApiNames = [NSMutableSet set];
    NSMutableArray<NSString *> *forcedReasons = [NSMutableArray array];
    for (NSString *trait in targetTraitSet) {
        NSArray *owners = uniqueTraitOwners[trait];
        if (owners.count == 1) {
            NSDictionary *only = owners.firstObject;
            NSString *apiName = only[@"apiName"];
            if (apiName.length > 0 && [eligibleApiNames containsObject:apiName] && ![forcedApiNames containsObject:apiName]) {
                [forcedApiNames addObject:apiName];
                NSString *traitName = displayNames[trait] ?: trait;
                [forcedReasons addObject:[NSString stringWithFormat:@"%@ -> %@", traitName, only[@"name"] ?: apiName]];
            }
        }
    }

    NSMutableArray *forced = [NSMutableArray array];
    NSMutableArray *remaining = [NSMutableArray array];
    for (NSDictionary *champion in eligible) {
        NSString *apiName = champion[@"apiName"];
        if ([forcedApiNames containsObject:apiName]) {
            [forced addObject:champion];
        } else {
            [remaining addObject:champion];
        }
    }

    NSInteger targetSize = MAX(forced.count, level);
    remaining = [[self sortedCandidates:remaining targetCounts:targetCounts] mutableCopy];
    if (remaining.count > 34) {
        remaining = [[remaining subarrayWithRange:NSMakeRange(0, 34)] mutableCopy];
    }
    NSDictionary *solution = [self searchSolutionWithForced:forced
                                                 candidates:remaining
                                               targetCounts:targetCounts
                                               targetTraits:targetTraitSet
                                                 targetSize:targetSize
                                    extraTraitAllowance:extraTraitAllowance];
    if (solution != nil) {
        NSMutableDictionary *result = [solution mutableCopy];
        result[@"detected"] = @YES;
        result[@"level"] = @(level);
        result[@"candidateCount"] = @(eligible.count);
        result[@"forced"] = forcedReasons;
        result[@"extraTraitAllowance"] = @(extraTraitAllowance);
        result[@"targetTraits"] = [self displayTraitTargets:targetCounts displayNames:displayNames sources:targetSources];
        return result;
    }

    return @{
        @"detected": @NO,
        @"level": @(level),
        @"candidateCount": @(eligible.count),
        @"forced": forcedReasons,
        @"extraTraitAllowance": @(extraTraitAllowance),
        @"reason": [NSString stringWithFormat:@"No exact visible trait solution found with %ld extra trait%@ allowed.", (long)extraTraitAllowance, extraTraitAllowance == 1 ? @"" : @"s"],
        @"targetTraits": [self displayTraitTargets:targetCounts displayNames:displayNames sources:targetSources]
    };
}

- (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)uniqueTraitOwnersForChampions:(NSArray<NSDictionary *> *)champions {
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *owners = [NSMutableDictionary dictionary];
    for (NSDictionary *champion in champions) {
        NSArray *traits = [champion[@"normalizedTraits"] isKindOfClass:NSArray.class] ? champion[@"normalizedTraits"] : @[];
        for (NSString *trait in traits) {
            if (trait.length == 0) {
                continue;
            }
            if (owners[trait] == nil) {
                owners[trait] = [NSMutableArray array];
            }
            [owners[trait] addObject:champion];
        }
    }
    NSMutableDictionary *unique = [NSMutableDictionary dictionary];
    for (NSString *trait in owners) {
        if (owners[trait].count == 1) {
            unique[trait] = [owners[trait] copy];
        }
    }
    return unique;
}

- (NSArray *)sortedCandidates:(NSArray *)candidates targetCounts:(NSDictionary<NSString *, NSNumber *> *)targetCounts {
    NSMutableDictionary<NSString *, NSNumber *> *rarity = [NSMutableDictionary dictionary];
    for (NSDictionary *champion in candidates) {
        for (NSString *trait in champion[@"normalizedTraits"] ?: @[]) {
            if (targetCounts[trait] != nil) {
                rarity[trait] = @([rarity[trait] integerValue] + 1);
            }
        }
    }
    return [candidates sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        double leftScore = [self rarityScoreForChampion:left rarity:rarity];
        double rightScore = [self rarityScoreForChampion:right rarity:rarity];
        if (fabs(leftScore - rightScore) > 0.0001) {
            return leftScore > rightScore ? NSOrderedAscending : NSOrderedDescending;
        }
        NSInteger leftCost = [left[@"cost"] integerValue];
        NSInteger rightCost = [right[@"cost"] integerValue];
        if (leftCost != rightCost) {
            return leftCost > rightCost ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left[@"name"] compare:right[@"name"]];
    }];
}

- (double)rarityScoreForChampion:(NSDictionary *)champion rarity:(NSDictionary<NSString *, NSNumber *> *)rarity {
    double score = 0;
    for (NSString *trait in champion[@"normalizedTraits"] ?: @[]) {
        NSInteger count = MAX(1, [rarity[trait] integerValue]);
        score += 1.0 / (double)count;
    }
    return score;
}

- (NSDictionary *)searchSolutionWithForced:(NSArray *)forced
                                candidates:(NSArray *)candidates
                              targetCounts:(NSDictionary<NSString *, NSNumber *> *)targetCounts
                              targetTraits:(NSSet *)targetTraits
                                targetSize:(NSInteger)targetSize
                       extraTraitAllowance:(NSInteger)extraTraitAllowance {
    NSMutableArray *selected = [forced mutableCopy];
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (NSString *trait in targetCounts) {
        counts[trait] = @0;
    }
    for (NSDictionary *champion in forced) {
        [self addChampion:champion toCounts:counts delta:1];
    }
    if ([self counts:counts exceedTargets:targetCounts] || [self extraTraitCountForSelected:selected targetTraits:targetTraits] > extraTraitAllowance) {
        return nil;
    }
    NSInteger slotsRemaining = targetSize - selected.count;
    if (slotsRemaining < 0) {
        return nil;
    }

    self.searchNodeBudget = 12000;
    return [self findSolutionFromIndex:0
                             slotsLeft:slotsRemaining
                             selected:selected
                                counts:counts
                            candidates:candidates
                          targetCounts:targetCounts
                          targetTraits:targetTraits
                   extraTraitAllowance:extraTraitAllowance];
}

- (NSDictionary *)findSolutionFromIndex:(NSInteger)index
                              slotsLeft:(NSInteger)slotsLeft
                               selected:(NSMutableArray *)selected
                                 counts:(NSMutableDictionary<NSString *, NSNumber *> *)counts
                             candidates:(NSArray *)candidates
                           targetCounts:(NSDictionary<NSString *, NSNumber *> *)targetCounts
                           targetTraits:(NSSet *)targetTraits
                    extraTraitAllowance:(NSInteger)extraTraitAllowance {
    self.searchNodeBudget -= 1;
    if (self.searchNodeBudget <= 0) {
        return nil;
    }
    if (slotsLeft == 0) {
        NSInteger missing = [self missingTraitPointsForCounts:counts targets:targetCounts];
        NSInteger extraTraits = [self extraTraitCountForSelected:selected targetTraits:targetTraits];
        return (missing == 0 && extraTraits <= extraTraitAllowance) ? [self resultForSelected:selected counts:counts targets:targetCounts extraTraits:extraTraits extraTraitAllowance:extraTraitAllowance] : nil;
    }
    if (index >= (NSInteger)candidates.count || (NSInteger)candidates.count - index < slotsLeft) {
        return nil;
    }
    if (![self canStillReachTargetsFromIndex:index
                                   slotsLeft:slotsLeft
                                      counts:counts
                                  candidates:candidates
                                targetCounts:targetCounts
                       extraTraitAllowance:extraTraitAllowance]) {
        return nil;
    }

    NSDictionary *champion = candidates[index];
    [selected addObject:champion];
    [self addChampion:champion toCounts:counts delta:1];
    NSDictionary *withChampion = nil;
    if (![self counts:counts exceedTargets:targetCounts] && [self extraTraitCountForSelected:selected targetTraits:targetTraits] <= extraTraitAllowance) {
        withChampion = [self findSolutionFromIndex:index + 1
                                         slotsLeft:slotsLeft - 1
                                          selected:selected
                                            counts:counts
                                        candidates:candidates
                                      targetCounts:targetCounts
                                      targetTraits:targetTraits
                               extraTraitAllowance:extraTraitAllowance];
    }
    [self addChampion:champion toCounts:counts delta:-1];
    [selected removeLastObject];
    if (withChampion != nil) {
        return withChampion;
    }
    return [self findSolutionFromIndex:index + 1
                             slotsLeft:slotsLeft
                             selected:selected
                                counts:counts
                            candidates:candidates
                          targetCounts:targetCounts
                          targetTraits:targetTraits
                   extraTraitAllowance:extraTraitAllowance];
}

- (BOOL)canStillReachTargetsFromIndex:(NSInteger)index
                            slotsLeft:(NSInteger)slotsLeft
                               counts:(NSDictionary<NSString *, NSNumber *> *)counts
                           candidates:(NSArray *)candidates
                         targetCounts:(NSDictionary<NSString *, NSNumber *> *)targetCounts
                  extraTraitAllowance:(NSInteger)extraTraitAllowance {
    NSInteger totalMissing = 0;
    for (NSString *trait in targetCounts) {
        NSInteger current = [counts[trait] integerValue];
        NSInteger target = [targetCounts[trait] integerValue];
        if (current > target) {
            return NO;
        }
        NSInteger deficit = target - current;
        totalMissing += deficit;
        NSInteger carriersRemaining = 0;
        for (NSInteger i = index; i < (NSInteger)candidates.count; i += 1) {
            NSDictionary *champion = candidates[i];
            NSArray *traits = [champion[@"normalizedTraits"] isKindOfClass:NSArray.class] ? champion[@"normalizedTraits"] : @[];
            if ([traits containsObject:trait]) {
                carriersRemaining += 1;
            }
        }
        NSInteger possibleFromUnits = MIN(slotsLeft, carriersRemaining);
        if (deficit > possibleFromUnits) {
            return NO;
        }
    }
    return totalMissing <= slotsLeft * 3;
}

- (void)addChampion:(NSDictionary *)champion toCounts:(NSMutableDictionary<NSString *, NSNumber *> *)counts delta:(NSInteger)delta {
    for (NSString *trait in champion[@"normalizedTraits"] ?: @[]) {
        if (counts[trait] != nil) {
            counts[trait] = @([counts[trait] integerValue] + delta);
        }
    }
}

- (BOOL)counts:(NSDictionary<NSString *, NSNumber *> *)counts exceedTargets:(NSDictionary<NSString *, NSNumber *> *)targets {
    for (NSString *trait in counts) {
        if (targets[trait] == nil) {
            continue;
        }
        if ([counts[trait] integerValue] > [targets[trait] integerValue]) {
            return YES;
        }
    }
    return NO;
}

- (NSInteger)missingTraitPointsForCounts:(NSDictionary<NSString *, NSNumber *> *)counts targets:(NSDictionary<NSString *, NSNumber *> *)targets {
    NSInteger missing = 0;
    for (NSString *trait in targets) {
        NSInteger diff = [targets[trait] integerValue] - [counts[trait] integerValue];
        if (diff < 0) {
            return NSIntegerMax / 2;
        }
        missing += diff;
    }
    return missing;
}

- (NSInteger)extraTraitCountForSelected:(NSArray *)selected targetTraits:(NSSet *)targetTraits {
    NSMutableSet<NSString *> *extra = [NSMutableSet set];
    for (NSDictionary *champion in selected) {
        NSArray *traits = [champion[@"normalizedTraits"] isKindOfClass:NSArray.class] ? champion[@"normalizedTraits"] : @[];
        for (NSString *trait in traits) {
            if (trait.length > 0 && ![targetTraits containsObject:trait]) {
                [extra addObject:trait];
            }
        }
    }
    return extra.count;
}

- (NSDictionary *)resultForSelected:(NSArray *)selected counts:(NSDictionary *)counts targets:(NSDictionary *)targets extraTraits:(NSInteger)extraTraits extraTraitAllowance:(NSInteger)extraTraitAllowance {
    NSMutableArray *units = [NSMutableArray array];
    for (NSDictionary *champion in selected) {
        [units addObject:@{
            @"apiName": champion[@"apiName"] ?: @"",
            @"name": champion[@"name"] ?: @"",
            @"cost": champion[@"cost"] ?: @0,
            @"traits": champion[@"traits"] ?: @[]
        }];
    }
    return @{
        @"units": units,
        @"unitNames": [units valueForKey:@"name"],
        @"extraTraitsUsed": @(extraTraits),
        @"extraTraitAllowance": @(extraTraitAllowance),
        @"counts": counts,
        @"status": extraTraits == 0 ? @"exact-visible-traits" : [NSString stringWithFormat:@"uses-%ld-extra-trait%@", extraTraits, extraTraits == 1 ? @"" : @"s"]
    };
}

- (NSArray *)displayTraitTargets:(NSDictionary<NSString *, NSNumber *> *)targets displayNames:(NSDictionary<NSString *, NSString *> *)displayNames sources:(NSDictionary<NSString *, NSString *> *)sources {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *trait in targets) {
        [result addObject:@{
            @"name": displayNames[trait] ?: trait,
            @"count": targets[trait],
            @"source": sources[trait] ?: @"active"
        }];
    }
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"name"] compare:right[@"name"]];
    }];
}

- (NSString *)displayNameFromApiName:(NSString *)apiName {
    NSString *name = apiName ?: @"";
    NSRange range = [name rangeOfString:@"_" options:NSBackwardsSearch];
    if (range.location != NSNotFound && range.location + 1 < name.length) {
        name = [name substringFromIndex:range.location + 1];
    }
    return name;
}

- (NSString *)normalizedName:(NSString *)name {
    NSMutableString *result = [NSMutableString string];
    NSString *lower = (name ?: @"").lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i += 1) {
        unichar c = [lower characterAtIndex:i];
        if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) {
            [result appendFormat:@"%C", c];
        }
    }
    return result;
}

- (NSString *)firstRegexMatch:(NSString *)pattern inString:(NSString *)text {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:text ?: @"" options:0 range:NSMakeRange(0, text.length)];
    if (match == nil) {
        return nil;
    }
    return [text substringWithRange:match.range];
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
          liveJSON:(nullable NSDictionary *)liveJSON
     visionSnapshot:(nullable NSDictionary *)visionSnapshot;
- (void)appendCalibrationRegionWithName:(NSString *)name frame:(NSRect)frame screenFrame:(NSRect)screenFrame;
- (void)appendManualSnapshotRecord:(NSDictionary *)snapshotRecord;
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
          liveJSON:(NSDictionary *)liveJSON
     visionSnapshot:(NSDictionary *)visionSnapshot {
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
        @"stageHint": snapshot.stageHint ?: [NSNull null],
        @"augmentTierOverlays": snapshot.augmentTierOverlays ?: @[],
        @"godBoonTierOverlays": snapshot.godBoonTierOverlays ?: @[],
        @"unitRecommendation": snapshot.unitRecommendation ?: [NSNull null],
        @"boardReconstruction": snapshot.boardReconstruction ?: [NSNull null],
        @"compSuggestion": snapshot.compSuggestion ?: [NSNull null],
        @"heroComp": snapshot.heroCompName ?: [NSNull null]
    };
    record[@"lockfile"] = lockfileInfo ?: @{@"found": @NO};
    record[@"lcuGameflowPhase"] = [self dictionaryForResult:lcuResult];
    record[@"lcuEndpoints"] = lcuEndpoints ?: @{};
    record[@"liveAllGameData"] = [self dictionaryForResult:liveResult];
    record[@"liveSummary"] = [self summaryForLiveJSON:liveJSON];
    record[@"visionProbe"] = visionSnapshot ?: @{};

    [self appendRecord:record];
}

- (void)appendCalibrationRegionWithName:(NSString *)name frame:(NSRect)frame screenFrame:(NSRect)screenFrame {
    CGFloat screenWidth = MAX(1, NSWidth(screenFrame));
    CGFloat screenHeight = MAX(1, NSHeight(screenFrame));
    CGFloat x1 = ((NSMinX(frame) - NSMinX(screenFrame)) / screenWidth) * 1920.0;
    CGFloat x2 = ((NSMaxX(frame) - NSMinX(screenFrame)) / screenWidth) * 1920.0;
    CGFloat y1 = ((NSMaxY(screenFrame) - NSMaxY(frame)) / screenHeight) * 1080.0;
    CGFloat y2 = ((NSMaxY(screenFrame) - NSMinY(frame)) / screenHeight) * 1080.0;

    NSDictionary *record = @{
        @"type": @"CALIBRATION_REGION",
        @"prefix": @"@@TFT_OVERLAY_CALIBRATION_REGION@@",
        @"timestamp": [self.formatter stringFromDate:NSDate.date],
        @"name": name.length > 0 ? name : @"unnamed_region",
        @"screenFrame": @{
            @"x": @(NSMinX(screenFrame)),
            @"y": @(NSMinY(screenFrame)),
            @"width": @(NSWidth(screenFrame)),
            @"height": @(NSHeight(screenFrame))
        },
        @"boxFrameScreen": @{
            @"x": @(NSMinX(frame)),
            @"y": @(NSMinY(frame)),
            @"width": @(NSWidth(frame)),
            @"height": @(NSHeight(frame))
        },
        @"cornersScreen": @{
            @"bottomLeft": @{@"x": @(NSMinX(frame)), @"y": @(NSMinY(frame))},
            @"bottomRight": @{@"x": @(NSMaxX(frame)), @"y": @(NSMinY(frame))},
            @"topLeft": @{@"x": @(NSMinX(frame)), @"y": @(NSMaxY(frame))},
            @"topRight": @{@"x": @(NSMaxX(frame)), @"y": @(NSMaxY(frame))}
        },
        @"baseRectTopOrigin1920x1080": @{
            @"x1": @(x1),
            @"y1": @(y1),
            @"x2": @(x2),
            @"y2": @(y2),
            @"width": @(x2 - x1),
            @"height": @(y2 - y1)
        },
        @"cornersTopOrigin1920x1080": @{
            @"topLeft": @{@"x": @(x1), @"y": @(y1)},
            @"topRight": @{@"x": @(x2), @"y": @(y1)},
            @"bottomLeft": @{@"x": @(x1), @"y": @(y2)},
            @"bottomRight": @{@"x": @(x2), @"y": @(y2)}
        }
    };
    [self appendRecord:record];
    [self.fileHandle synchronizeFile];
}

- (void)appendManualSnapshotRecord:(NSDictionary *)snapshotRecord {
    if (![snapshotRecord isKindOfClass:NSDictionary.class]) {
        return;
    }
    [self appendRecord:snapshotRecord];
    [self.fileHandle synchronizeFile];
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
@property(nonatomic, strong) VisionProbeReader *visionProbe;
@property(nonatomic, strong) AugmentTierMatcher *augmentTierMatcher;
@property(nonatomic, strong) UnitBuildRecommender *unitBuildRecommender;
@property(nonatomic, strong) BoardUnitReconstructor *boardUnitReconstructor;
@property(nonatomic, strong) GameStateLogWriter *logWriter;
@property(nonatomic) NSTimeInterval pollingInterval;
@property(nonatomic) BOOL pollInFlight;
@property(nonatomic, copy) NSString *lastBoardReconstructionKey;
@property(nonatomic, strong) NSDictionary *lastBoardReconstruction;
@property(nonatomic, strong) NSDictionary *lastCompSuggestion;
@property(nonatomic, copy) NSString *pendingBoardReconstructionKey;
@property(nonatomic) BOOL boardReconstructionInFlight;
@property(nonatomic, strong) id clickMonitor;
@property(nonatomic, strong) id keyMonitor;
@property(nonatomic, strong) id localKeyMonitor;
@property(nonatomic, strong) CalibrationBoxWindow *calibrationWindow;
@property(nonatomic, copy) NSArray<NSDictionary *> *currentAugmentMatches;
@property(nonatomic, copy, nullable) NSString *selectedHeroComp;
@property(nonatomic, copy, nullable) NSString *selectedCompTitle;
@property(nonatomic) NSUInteger calibrationRegionCount;
@property(nonatomic) BOOL calibrationPromptOpen;
@property(nonatomic) BOOL calibrationDragActive;
@property(nonatomic) NSPoint calibrationDragStartPoint;
@property(nonatomic) NSRect calibrationDragStartFrame;
@property(nonatomic) NSInteger calibrationDragEdges;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    self.pollingInterval = 1.5;
    [self requestScreenCapturePermissionIfNeeded];
    [self requestKeyboardMonitoringPermissionIfNeeded];

    self.overlayView = [[OverlayView alloc] initWithFrame:NSScreen.mainScreen.frame];
    self.overlayWindow = [[OverlayWindow alloc] initWithContentView:self.overlayView];
    [self.overlayWindow orderFrontRegardless];

    self.leagueClient = [LeagueClientReader new];
    self.liveClient = [LiveClientDataReader new];
    self.visionProbe = [VisionProbeReader new];
    self.augmentTierMatcher = [AugmentTierMatcher new];
    self.unitBuildRecommender = [UnitBuildRecommender new];
    self.boardUnitReconstructor = [BoardUnitReconstructor new];
    self.logWriter = [GameStateLogWriter new];
    [self installSettingsWindow];

    [self installStatusMenu];
    [self installClickMonitor];
    [self installKeyboardShortcutMonitor];
    [self startPolling];
    [self showSettings:nil];
}

- (void)requestScreenCapturePermissionIfNeeded {
    if (@available(macOS 10.15, *)) {
        if (!CGPreflightScreenCaptureAccess()) {
            CGRequestScreenCaptureAccess();
        }
    }
}

- (void)requestKeyboardMonitoringPermissionIfNeeded {
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

- (void)installClickMonitor {
    __weak typeof(self) weakSelf = self;
    NSEventMask mask = NSEventMaskLeftMouseDown | NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp | NSEventMaskMouseMoved;
    self.clickMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:mask handler:^(NSEvent *event) {
        [weakSelf handleGlobalMouseEvent:event];
    }];
}

- (void)handleGlobalMouseEvent:(NSEvent *)event {
    if (self.calibrationWindow.visible) {
        [self handleCalibrationMouseEvent:event];
        return;
    }
    if (event.type == NSEventTypeMouseMoved) {
        self.overlayView.mouseScreenPoint = NSEvent.mouseLocation;
        [self.overlayView setNeedsDisplay:YES];
        return;
    }
    if (event.type == NSEventTypeLeftMouseDown) {
        [self handleGlobalLeftClickAtScreenPoint:NSEvent.mouseLocation];
    }
}

- (void)handleCalibrationMouseEvent:(NSEvent *)event {
    NSPoint point = NSEvent.mouseLocation;
    if (event.type == NSEventTypeLeftMouseDown) {
        if (!NSPointInRect(point, self.calibrationWindow.frame)) {
            self.calibrationDragActive = NO;
            return;
        }
        self.calibrationDragActive = YES;
        self.calibrationDragStartPoint = point;
        self.calibrationDragStartFrame = self.calibrationWindow.frame;
        self.calibrationDragEdges = [self calibrationResizeEdgesForScreenPoint:point frame:self.calibrationWindow.frame];
        return;
    }

    if (event.type == NSEventTypeLeftMouseUp) {
        self.calibrationDragActive = NO;
        return;
    }

    if (event.type == NSEventTypeLeftMouseDragged && self.calibrationDragActive) {
        [self updateCalibrationWindowForScreenPoint:point];
    }
}

- (NSInteger)calibrationResizeEdgesForScreenPoint:(NSPoint)point frame:(NSRect)frame {
    CGFloat margin = 18;
    NSInteger edges = 0;
    if (point.x <= NSMinX(frame) + margin) {
        edges |= 1;
    } else if (point.x >= NSMaxX(frame) - margin) {
        edges |= 2;
    }
    if (point.y <= NSMinY(frame) + margin) {
        edges |= 4;
    } else if (point.y >= NSMaxY(frame) - margin) {
        edges |= 8;
    }
    return edges;
}

- (void)updateCalibrationWindowForScreenPoint:(NSPoint)point {
    CGFloat dx = point.x - self.calibrationDragStartPoint.x;
    CGFloat dy = point.y - self.calibrationDragStartPoint.y;
    NSRect frame = self.calibrationDragStartFrame;
    CGFloat minSize = 36;

    if (self.calibrationDragEdges == 0) {
        frame.origin.x += dx;
        frame.origin.y += dy;
    } else {
        if (self.calibrationDragEdges & 1) {
            CGFloat newMinX = MIN(NSMaxX(frame) - minSize, NSMinX(frame) + dx);
            frame.size.width = NSMaxX(frame) - newMinX;
            frame.origin.x = newMinX;
        }
        if (self.calibrationDragEdges & 2) {
            frame.size.width = MAX(minSize, NSWidth(frame) + dx);
        }
        if (self.calibrationDragEdges & 4) {
            CGFloat newMinY = MIN(NSMaxY(frame) - minSize, NSMinY(frame) + dy);
            frame.size.height = NSMaxY(frame) - newMinY;
            frame.origin.y = newMinY;
        }
        if (self.calibrationDragEdges & 8) {
            frame.size.height = MAX(minSize, NSHeight(frame) + dy);
        }
    }

    [self.calibrationWindow setFrame:frame display:YES];
}

- (void)installKeyboardShortcutMonitor {
    __weak typeof(self) weakSelf = self;
    self.keyMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^(NSEvent *event) {
        [weakSelf handleKeyDown:event];
    }];
    self.localKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        return [weakSelf handleKeyDown:event] ? nil : event;
    }];
}

- (BOOL)handleKeyDown:(NSEvent *)event {
    if (self.calibrationPromptOpen) {
        return NO;
    }

    if ((event.modifierFlags & NSEventModifierFlagCommand) == 0) {
        return NO;
    }
    NSString *key = event.charactersIgnoringModifiers.lowercaseString ?: @"";
    if ([key isEqualToString:@"n"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self toggleCalibrationBox:nil];
        });
        return YES;
    }
    if ([key isEqualToString:@"s"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self saveManualSnapshot:nil];
        });
        return YES;
    }
    if ([key isEqualToString:@"d"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self toggleOCRZones:nil];
        });
        return YES;
    }
    return NO;
}

- (void)handleGlobalLeftClickAtScreenPoint:(NSPoint)point {
    NSDictionary *clickedComp = [self compSuggestionBadgeForScreenPoint:point];
    if (clickedComp != nil) {
        NSString *title = [clickedComp[@"title"] isKindOfClass:NSString.class] ? clickedComp[@"title"] : @"";
        if (title.length > 0) {
            if ([self.selectedCompTitle isEqualToString:title]) {
                self.selectedCompTitle = nil;
            } else {
                self.selectedCompTitle = title;
            }
            [self refreshCompSuggestionAfterSelectionChange];
        }
        return;
    }

    NSInteger slot = [self augmentSlotForScreenPoint:point];
    if (slot < 0) {
        return;
    }

    for (NSDictionary *match in self.currentAugmentMatches ?: @[]) {
        NSNumber *slotNumber = [match[@"slot"] isKindOfClass:NSNumber.class] ? match[@"slot"] : nil;
        if (slotNumber == nil || slotNumber.integerValue != slot) {
            continue;
        }
        NSString *name = [match[@"displayName"] isKindOfClass:NSString.class] ? match[@"displayName"] : @"";
        if ([self isHeroAugmentName:name]) {
            self.selectedHeroComp = name;
        }
        break;
    }
}

- (void)refreshCompSuggestionAfterSelectionChange {
    GameSnapshot *snapshot = self.overlayView.snapshot;
    if (snapshot == nil) {
        return;
    }
    NSDictionary *suggestion = nil;
    if (self.selectedCompTitle.length > 0) {
        suggestion = [self.augmentTierMatcher compSuggestionForBoardReconstruction:nil level:0 selectedTitle:self.selectedCompTitle];
    } else {
        suggestion = self.lastCompSuggestion;
    }
    snapshot.compSuggestion = suggestion;
    self.overlayView.snapshot = snapshot;
    [self.overlayView setNeedsDisplay:YES];
}

- (NSDictionary *)compSuggestionBadgeForScreenPoint:(NSPoint)point {
    NSDictionary *suggestion = self.overlayView.snapshot.compSuggestion;
    if (![suggestion isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSArray *comps = [suggestion[@"comps"] isKindOfClass:NSArray.class] ? suggestion[@"comps"] : @[];
    if (comps.count == 0) {
        return nil;
    }

    NSScreen *screen = NSScreen.mainScreen;
    if (screen == nil) {
        return nil;
    }
    NSRect frame = screen.frame;
    CGFloat scale = MIN(NSWidth(frame) / 1920.0, NSHeight(frame) / 1080.0);
    NSUInteger count = MIN(comps.count, 5);
    CGFloat iconSize = 52 * scale;
    CGFloat gap = 9 * scale;
    CGFloat labelWidth = 126 * scale;
    CGFloat width = labelWidth + count * iconSize + MAX(0, (NSInteger)count - 1) * gap + 26 * scale;
    CGFloat height = 76 * scale;
    NSRect panel = NSMakeRect(NSMinX(frame) + 74 * scale, NSMaxY(frame) - 326 * scale, width, height);
    CGFloat x = NSMinX(panel) + labelWidth;
    CGFloat y = NSMidY(panel) - iconSize / 2.0;
    for (NSUInteger i = 0; i < count; i += 1) {
        NSRect rect = NSMakeRect(x + i * (iconSize + gap), y, iconSize, iconSize);
        if (NSPointInRect(point, NSInsetRect(rect, -4 * scale, -4 * scale))) {
            return [comps[i] isKindOfClass:NSDictionary.class] ? comps[i] : nil;
        }
    }
    return nil;
}

- (NSInteger)augmentSlotForScreenPoint:(NSPoint)point {
    NSScreen *screen = NSScreen.mainScreen;
    if (screen == nil) {
        return -1;
    }
    NSRect frame = screen.frame;
    NSArray<NSValue *> *zones = @[
        [NSValue valueWithRect:NSMakeRect(350, 276, 350, 560)],
        [NSValue valueWithRect:NSMakeRect(785, 276, 350, 560)],
        [NSValue valueWithRect:NSMakeRect(1220, 276, 350, 560)]
    ];
    for (NSInteger i = 0; i < (NSInteger)zones.count; i += 1) {
        NSRect zone = [self screenRectForBaseRect:zones[i].rectValue screenFrame:frame horizontal:@"center" vertical:@"center"];
        if (NSPointInRect(point, zone)) {
            return i;
        }
    }
    return -1;
}

- (NSRect)screenRectForBaseRect:(NSRect)baseRect screenFrame:(NSRect)screenFrame horizontal:(NSString *)horizontal vertical:(NSString *)vertical {
    CGFloat scaleX = NSWidth(screenFrame) / 1920.0;
    CGFloat scaleY = NSHeight(screenFrame) / 1080.0;
    CGFloat width = NSWidth(baseRect) * scaleX;
    CGFloat height = NSHeight(baseRect) * scaleY;
    CGFloat x = 0;
    if ([horizontal isEqualToString:@"center"]) {
        x = NSMidX(screenFrame) + (NSMidX(baseRect) - 960.0) * scaleX - width / 2.0;
    } else if ([horizontal isEqualToString:@"right"]) {
        x = NSMaxX(screenFrame) - (1920.0 - NSMaxX(baseRect)) * scaleX - width;
    } else {
        x = NSMinX(screenFrame) + NSMinX(baseRect) * scaleX;
    }

    CGFloat topY = 0;
    if ([vertical isEqualToString:@"center"]) {
        topY = NSHeight(screenFrame) / 2.0 + (NSMidY(baseRect) - 540.0) * scaleY - height / 2.0;
    } else if ([vertical isEqualToString:@"bottom"]) {
        topY = NSHeight(screenFrame) - (1080.0 - NSMaxY(baseRect)) * scaleY - height;
    } else {
        topY = NSMinY(baseRect) * scaleY;
    }
    CGFloat y = NSMaxY(screenFrame) - topY - height;
    return NSMakeRect(x, y, width, height);
}

- (BOOL)isHeroAugmentName:(NSString *)name {
    NSString *normalized = [self normalizedHeroName:name];
    NSSet<NSString *> *heroNames = [NSSet setWithArray:@[
        @"selfdestruct",
        @"thebigbang",
        @"invaderzed",
        @"shieldmaiden",
        @"stellarcombo",
        @"reachforthestars",
        @"heatdeath",
        @"termeepnalvelocity",
        @"terminalvelocity",
        @"bonk",
        @"contractkiller"
    ]];
    return [heroNames containsObject:normalized];
}

- (NSString *)normalizedHeroName:(NSString *)name {
    NSMutableString *normalized = [NSMutableString string];
    NSString *lower = (name ?: @"").lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i += 1) {
        unichar c = [lower characterAtIndex:i];
        if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) {
            [normalized appendFormat:@"%C", c];
        }
    }
    return normalized;
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
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Toggle OCR Zones" action:@selector(toggleOCRZones:) keyEquivalent:@"d"]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Start/Save Calibration Box" action:@selector(toggleCalibrationBox:) keyEquivalent:@"n"]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Save Manual Snapshot" action:@selector(saveManualSnapshot:) keyEquivalent:@"s"]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Open Log Folder" action:@selector(openLogFolder:) keyEquivalent:@"l"]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@"q"]];
    self.statusItem.menu = menu;
}

- (void)startPolling {
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.pollingInterval target:self selector:@selector(pollGameState:) userInfo:nil repeats:YES];
    [self pollGameState:nil];
}

- (void)pollGameState:(NSTimer *)timer {
    if (self.pollInFlight) {
        return;
    }
    self.pollInFlight = YES;

    LeagueClientReader *leagueClient = self.leagueClient;
    LiveClientDataReader *liveClient = self.liveClient;
    VisionProbeReader *visionProbe = self.visionProbe;
    AugmentTierMatcher *augmentTierMatcher = self.augmentTierMatcher;
    UnitBuildRecommender *unitBuildRecommender = self.unitBuildRecommender;
    BoardUnitReconstructor *boardUnitReconstructor = self.boardUnitReconstructor;
    GameStateLogWriter *logWriter = self.logWriter;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        CFAbsoluteTime pollStart = CFAbsoluteTimeGetCurrent();
        CFAbsoluteTime sectionStart = pollStart;
        LocalHTTPResult *lcuResult = nil;
        LocalHTTPResult *liveResult = nil;
        NSDictionary *lockfileInfo = nil;
        NSDictionary *liveJSON = nil;
        NSString *phase = [leagueClient gameflowPhaseWithResult:&lcuResult lockfileInfo:&lockfileInfo];
        NSTimeInterval lcuPhaseMs = (CFAbsoluteTimeGetCurrent() - sectionStart) * 1000.0;
        sectionStart = CFAbsoluteTimeGetCurrent();
        NSDictionary *lcuEndpoints = [leagueClient endpointSnapshotsWithLockfileInfo:&lockfileInfo];
        NSTimeInterval lcuEndpointsMs = (CFAbsoluteTimeGetCurrent() - sectionStart) * 1000.0;
        sectionStart = CFAbsoluteTimeGetCurrent();
        NSNumber *gameTime = [liveClient gameTimeWithResult:&liveResult parsedJSON:&liveJSON];
        NSTimeInterval liveMs = (CFAbsoluteTimeGetCurrent() - sectionStart) * 1000.0;
        GameSnapshot *snapshot = (phase.length > 0 || gameTime != nil) ? [GameSnapshot snapshotWithPhase:phase gameTime:gameTime] : [GameSnapshot idle];
        BOOL shouldRunVision = [phase isEqualToString:@"InProgress"] && gameTime != nil;
        sectionStart = CFAbsoluteTimeGetCurrent();
        NSDictionary *visionSnapshot = shouldRunVision ? [visionProbe captureSnapshotInLogDirectory:logWriter.logDirectoryURL] : @{
            @"attempted": @NO,
            @"available": @NO,
            @"reason": @"Skipped OCR because gameflow is not InProgress.",
            @"regions": @[]
        };
        NSTimeInterval visionMs = (CFAbsoluteTimeGetCurrent() - sectionStart) * 1000.0;
        NSMutableDictionary *visionSnapshotWithDerivedState = [visionSnapshot mutableCopy];
        NSInteger apiLevel = [self activePlayerLevelFromLiveJSON:liveJSON];
        visionSnapshotWithDerivedState[@"apiLevel"] = @(apiLevel);
        visionSnapshot = visionSnapshotWithDerivedState;

        NSDictionary *traitList = [visionSnapshot[@"traitList"] isKindOfClass:NSDictionary.class] ? visionSnapshot[@"traitList"] : @{};
        NSString *levelText = apiLevel > 0 ? [NSString stringWithFormat:@"%ld", (long)apiLevel] : @"";
        NSDictionary *unitPanel = [visionSnapshot[@"unitPanel"] isKindOfClass:NSDictionary.class] ? visionSnapshot[@"unitPanel"] : @{};

        dispatch_queue_t calculationQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        dispatch_group_t calculationGroup = dispatch_group_create();
        __block NSDictionary *boardReconstruction = nil;
        __block NSArray *augmentMatches = @[];
        __block NSArray *godBoonMatches = @[];
        __block NSDictionary *unitRecommendation = nil;

        sectionStart = CFAbsoluteTimeGetCurrent();
        NSString *boardReconstructionKey = [self boardReconstructionKeyForTraitList:traitList levelText:levelText];
        __block BOOL boardReconstructionStarted = NO;
        __block BOOL boardReconstructionPending = NO;
        @synchronized (self) {
            if (boardReconstructionKey.length > 0 && [boardReconstructionKey isEqualToString:self.lastBoardReconstructionKey]) {
                boardReconstruction = self.lastBoardReconstruction;
            }
            BOOL shouldStartBoardWork = boardReconstructionKey.length > 0 &&
                                        ![boardReconstructionKey isEqualToString:self.lastBoardReconstructionKey] &&
                                        ![boardReconstructionKey isEqualToString:self.pendingBoardReconstructionKey] &&
                                        !self.boardReconstructionInFlight;
            if (shouldStartBoardWork) {
                self.boardReconstructionInFlight = YES;
                self.pendingBoardReconstructionKey = boardReconstructionKey;
                boardReconstructionStarted = YES;
                NSDictionary *traitListCopy = [traitList copy];
                NSString *levelTextCopy = [levelText copy];
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    NSDictionary *computed = [boardUnitReconstructor reconstructionForTraitList:traitListCopy levelText:levelTextCopy];
                    @synchronized (self) {
                        if ([self.pendingBoardReconstructionKey isEqualToString:boardReconstructionKey]) {
                            self.lastBoardReconstructionKey = boardReconstructionKey ?: @"";
                            self.lastBoardReconstruction = computed;
                        }
                        self.pendingBoardReconstructionKey = @"";
                        self.boardReconstructionInFlight = NO;
                    }
                });
            }
            boardReconstructionPending = self.boardReconstructionInFlight;
        }
        dispatch_group_async(calculationGroup, calculationQueue, ^{
            augmentMatches = [augmentTierMatcher matchesForVisionSnapshot:visionSnapshot];
        });
        dispatch_group_async(calculationGroup, calculationQueue, ^{
            godBoonMatches = [augmentTierMatcher godBoonMatchesForVisionSnapshot:visionSnapshot];
        });
        dispatch_group_async(calculationGroup, calculationQueue, ^{
            if ([unitPanel[@"detected"] boolValue]) {
                NSString *unitName = [unitPanel[@"name"] isKindOfClass:NSString.class] ? unitPanel[@"name"] : @"";
                unitRecommendation = [unitBuildRecommender recommendationForUnitName:unitName];
            }
        });
        dispatch_group_wait(calculationGroup, DISPATCH_TIME_FOREVER);
        NSTimeInterval calculationMs = (CFAbsoluteTimeGetCurrent() - sectionStart) * 1000.0;

        if (boardReconstruction != nil) {
            visionSnapshotWithDerivedState[@"boardReconstruction"] = boardReconstruction;
            snapshot.boardReconstruction = boardReconstruction;
        }
        visionSnapshot = visionSnapshotWithDerivedState;
        snapshot.augmentTierOverlays = augmentMatches ?: @[];
        snapshot.godBoonTierOverlays = godBoonMatches ?: @[];
        NSDictionary *compSuggestion = nil;
        if (self.selectedCompTitle.length > 0) {
            compSuggestion = [augmentTierMatcher compSuggestionForBoardReconstruction:boardReconstruction level:apiLevel selectedTitle:self.selectedCompTitle];
        } else {
            compSuggestion = [augmentTierMatcher compSuggestionForBoardReconstruction:boardReconstruction level:apiLevel selectedTitle:nil];
            if (compSuggestion != nil) {
                self.lastCompSuggestion = compSuggestion;
            } else {
                compSuggestion = self.lastCompSuggestion;
            }
        }
        snapshot.compSuggestion = compSuggestion;
        if (snapshot.compSuggestion != nil) {
            visionSnapshotWithDerivedState[@"compSuggestion"] = snapshot.compSuggestion;
            visionSnapshot = visionSnapshotWithDerivedState;
        }
        self.currentAugmentMatches = snapshot.augmentTierOverlays;
        snapshot.heroCompName = self.selectedHeroComp;
        snapshot.unitRecommendation = unitRecommendation;
        NSDictionary *traitProfile = [visionSnapshot[@"traitOCR"] isKindOfClass:NSDictionary.class] ? visionSnapshot[@"traitOCR"] : @{};
        NSTimeInterval totalBeforeLogMs = (CFAbsoluteTimeGetCurrent() - pollStart) * 1000.0;
        NSMutableDictionary *profile = [@{
            @"lcuPhaseMs": @(lcuPhaseMs),
            @"lcuEndpointsMs": @(lcuEndpointsMs),
            @"liveMs": @(liveMs),
            @"visionMs": @(visionMs),
            @"calculationMs": @(calculationMs),
            @"totalBeforeLogMs": @(totalBeforeLogMs),
            @"boardStarted": @(boardReconstructionStarted),
            @"boardPending": @(boardReconstructionPending)
        } mutableCopy];
        if ([traitProfile[@"elapsedMs"] isKindOfClass:NSNumber.class]) {
            profile[@"traitOCRMs"] = traitProfile[@"elapsedMs"];
        }
        visionSnapshotWithDerivedState[@"profile"] = profile;
        visionSnapshot = visionSnapshotWithDerivedState;
        snapshot.detail = [self profileSummaryLineForProfile:profile];
        snapshot.visionDebugLines = [self visionDebugLinesForSnapshot:visionSnapshot augmentMatches:snapshot.augmentTierOverlays godBoonMatches:snapshot.godBoonTierOverlays];

        sectionStart = CFAbsoluteTimeGetCurrent();
        [logWriter appendPhase:phase
                      gameTime:gameTime
                      snapshot:snapshot
                     lcuResult:lcuResult
                  lcuEndpoints:lcuEndpoints
                    liveResult:liveResult
                  lockfileInfo:lockfileInfo
                      liveJSON:liveJSON
                visionSnapshot:visionSnapshot];
        NSTimeInterval logMs = (CFAbsoluteTimeGetCurrent() - sectionStart) * 1000.0;
        profile[@"logMs"] = @(logMs);
        profile[@"totalMs"] = @((CFAbsoluteTimeGetCurrent() - pollStart) * 1000.0);
        snapshot.detail = [self profileSummaryLineForProfile:profile];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.overlayView.snapshot = snapshot;
            [self.settingsWindowController updateSnapshot:snapshot overlayVisible:self.overlayWindow.visible];
            self.pollInFlight = NO;
        });
    });
}

- (NSString *)boardReconstructionKeyForTraitList:(NSDictionary *)traitList levelText:(NSString *)levelText {
    if (![traitList isKindOfClass:NSDictionary.class]) {
        return @"";
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *level = [self firstRegexMatch:@"[0-9]+" inString:levelText ?: @""] ?: @"";
    [parts addObject:[NSString stringWithFormat:@"level=%@", level]];
    NSNumber *extraTraitAllowance = [traitList[@"extraTraitAllowance"] isKindOfClass:NSNumber.class] ? traitList[@"extraTraitAllowance"] : @0;
    [parts addObject:[NSString stringWithFormat:@"extra=%ld", (long)extraTraitAllowance.integerValue]];
    BOOL hasTrait = NO;

    NSArray *activeTraits = [traitList[@"traits"] isKindOfClass:NSArray.class] ? traitList[@"traits"] : @[];
    for (NSDictionary *trait in activeTraits) {
        if (![trait isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *name = [trait[@"name"] isKindOfClass:NSString.class] ? trait[@"name"] : @"";
        NSNumber *count = [trait[@"count"] isKindOfClass:NSNumber.class] ? trait[@"count"] : nil;
        if (name.length > 0 && count != nil) {
            [parts addObject:[NSString stringWithFormat:@"a:%@=%ld", [self normalizedHeroName:name], (long)count.integerValue]];
            hasTrait = YES;
        }
    }

    NSArray *partialTraits = [traitList[@"partialTraits"] isKindOfClass:NSArray.class] ? traitList[@"partialTraits"] : @[];
    for (NSDictionary *trait in partialTraits) {
        if (![trait isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *name = [trait[@"name"] isKindOfClass:NSString.class] ? trait[@"name"] : @"";
        NSNumber *count = [trait[@"count"] isKindOfClass:NSNumber.class] ? trait[@"count"] : nil;
        NSNumber *threshold = [trait[@"threshold"] isKindOfClass:NSNumber.class] ? trait[@"threshold"] : @0;
        if (name.length > 0 && count != nil) {
            [parts addObject:[NSString stringWithFormat:@"p:%@=%ld/%ld", [self normalizedHeroName:name], (long)count.integerValue, (long)threshold.integerValue]];
            hasTrait = YES;
        }
    }

    if (!hasTrait) {
        return @"";
    }
    NSArray *sortedParts = [parts sortedArrayUsingSelector:@selector(compare:)];
    return [sortedParts componentsJoinedByString:@"|"];
}

- (NSInteger)activePlayerLevelFromLiveJSON:(NSDictionary *)liveJSON {
    if (![liveJSON isKindOfClass:NSDictionary.class]) {
        return 0;
    }
    NSDictionary *activePlayer = [liveJSON[@"activePlayer"] isKindOfClass:NSDictionary.class] ? liveJSON[@"activePlayer"] : @{};
    NSNumber *level = [activePlayer[@"level"] isKindOfClass:NSNumber.class] ? activePlayer[@"level"] : nil;
    return level.integerValue;
}

- (NSString *)profileSummaryLineForProfile:(NSDictionary *)profile {
    if (![profile isKindOfClass:NSDictionary.class]) {
        return @"";
    }
    NSNumber *total = [profile[@"totalMs"] isKindOfClass:NSNumber.class] ? profile[@"totalMs"] : profile[@"totalBeforeLogMs"];
    NSArray<NSString *> *keys = @[@"visionMs", @"lcuEndpointsMs", @"lcuPhaseMs", @"liveMs", @"calculationMs", @"logMs", @"traitOCRMs"];
    NSDictionary<NSString *, NSString *> *labels = @{
        @"visionMs": @"vision",
        @"lcuEndpointsMs": @"lcu",
        @"lcuPhaseMs": @"phase",
        @"liveMs": @"live",
        @"calculationMs": @"calc",
        @"logMs": @"log",
        @"traitOCRMs": @"trait"
    };
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSString *key in keys) {
        NSNumber *value = [profile[key] isKindOfClass:NSNumber.class] ? profile[key] : nil;
        if (value != nil) {
            [items addObject:@{@"label": labels[key] ?: key, @"value": value}];
        }
    }
    NSArray *sorted = [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        double leftValue = [left[@"value"] doubleValue];
        double rightValue = [right[@"value"] doubleValue];
        if (fabs(leftValue - rightValue) < 0.001) {
            return NSOrderedSame;
        }
        return leftValue > rightValue ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSUInteger count = MIN(sorted.count, 4);
    for (NSUInteger i = 0; i < count; i += 1) {
        NSDictionary *item = sorted[i];
        [parts addObject:[NSString stringWithFormat:@"%@ %.0f", item[@"label"], [item[@"value"] doubleValue]]];
    }
    NSString *board = [profile[@"boardPending"] boolValue] ? @" | board bg" : @"";
    return [NSString stringWithFormat:@"Perf %.0fms | %@%@", total.doubleValue, [parts componentsJoinedByString:@" | "], board];
}

- (NSString *)firstRegexMatch:(NSString *)pattern inString:(NSString *)text {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:text ?: @"" options:0 range:NSMakeRange(0, text.length)];
    if (match == nil) {
        return nil;
    }
    return [text substringWithRange:match.range];
}

- (NSArray<NSString *> *)visionDebugLinesForSnapshot:(NSDictionary *)visionSnapshot augmentMatches:(NSArray<NSDictionary *> *)augmentMatches godBoonMatches:(NSArray<NSDictionary *> *)godBoonMatches {
    if (![visionSnapshot[@"available"] boolValue]) {
        NSString *error = [visionSnapshot[@"error"] isKindOfClass:NSString.class] ? visionSnapshot[@"error"] : @"Vision unavailable";
        return @[[NSString stringWithFormat:@"OCR: %@", error]];
    }

    NSArray *regions = [visionSnapshot[@"regions"] isKindOfClass:NSArray.class] ? visionSnapshot[@"regions"] : @[];
    NSDictionary *unitPanel = [visionSnapshot[@"unitPanel"] isKindOfClass:NSDictionary.class] ? visionSnapshot[@"unitPanel"] : @{};

    NSMutableArray *augments = [NSMutableArray array];
    for (NSInteger i = 1; i <= 3; i += 1) {
        NSString *text = [self regionText:[NSString stringWithFormat:@"augment_%ld", i] regions:regions];
        [augments addObject:text.length > 0 ? text : @"-"];
    }

    NSMutableArray *godBoons = [NSMutableArray array];
    for (NSInteger i = 1; i <= 2; i += 1) {
        NSString *text = [self regionText:[NSString stringWithFormat:@"god_boon_%ld", i] regions:regions];
        [godBoons addObject:text.length > 0 ? text : @"-"];
    }

    NSMutableArray *tierLines = [NSMutableArray array];
    for (NSDictionary *match in augmentMatches) {
        NSString *name = [match[@"displayName"] isKindOfClass:NSString.class] ? match[@"displayName"] : @"?";
        NSString *tier = [match[@"tier"] isKindOfClass:NSString.class] ? match[@"tier"] : @"?";
        NSNumber *slot = [match[@"slot"] isKindOfClass:NSNumber.class] ? match[@"slot"] : @0;
        [tierLines addObject:[NSString stringWithFormat:@"%ld:%@=%@", slot.integerValue + 1, name, tier]];
    }

    NSMutableArray *lines = [NSMutableArray array];
    NSNumber *apiLevel = [visionSnapshot[@"apiLevel"] isKindOfClass:NSNumber.class] ? visionSnapshot[@"apiLevel"] : @0;
    [lines addObject:[NSString stringWithFormat:@"OCR src:%@ api lvl:%@", visionSnapshot[@"source"] ?: @"?", apiLevel.integerValue > 0 ? apiLevel.stringValue : @"-"]];
    if (unitPanel.count > 0) {
        NSDictionary *color = [unitPanel[@"color"] isKindOfClass:NSDictionary.class] ? unitPanel[@"color"] : @{};
        NSNumber *panelSamples = [color[@"panelSamples"] isKindOfClass:NSNumber.class] ? color[@"panelSamples"] : @0;
        NSString *unitName = [unitPanel[@"name"] isKindOfClass:NSString.class] ? unitPanel[@"name"] : @"-";
        NSString *rawName = [unitPanel[@"rawName"] isKindOfClass:NSString.class] ? unitPanel[@"rawName"] : @"";
        NSString *displayName = (rawName.length > 0 && unitName.length > 0 && ![rawName isEqualToString:unitName]) ? [NSString stringWithFormat:@"%@ -> %@", rawName, unitName] : unitName;
        [lines addObject:[NSString stringWithFormat:@"Unit panel:%@ color:%@/3 name:%@",
                          [unitPanel[@"detected"] boolValue] ? @"yes" : @"no",
                          panelSamples,
                          displayName]];
    }
    NSDictionary *augmentColor = [visionSnapshot[@"augmentColor"] isKindOfClass:NSDictionary.class] ? visionSnapshot[@"augmentColor"] : @{};
    NSArray *augmentColorSamples = [augmentColor[@"samples"] isKindOfClass:NSArray.class] ? augmentColor[@"samples"] : @[];
    if (augmentColorSamples.count > 0) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSDictionary *sample in augmentColorSamples) {
            [parts addObject:[sample[@"detected"] boolValue] ? @"Y" : @"-"];
        }
        [lines addObject:[NSString stringWithFormat:@"Augment gate: %@", [parts componentsJoinedByString:@" "]]];
    }
    NSDictionary *godBoonColor = [visionSnapshot[@"godBoonColor"] isKindOfClass:NSDictionary.class] ? visionSnapshot[@"godBoonColor"] : @{};
    NSArray *godBoonColorSamples = [godBoonColor[@"samples"] isKindOfClass:NSArray.class] ? godBoonColor[@"samples"] : @[];
    if (godBoonColorSamples.count > 0) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSDictionary *sample in godBoonColorSamples) {
            [parts addObject:[sample[@"detected"] boolValue] ? @"Y" : @"-"];
        }
        [lines addObject:[NSString stringWithFormat:@"God gate: %@", [parts componentsJoinedByString:@" "]]];
    }
    NSDictionary *traitList = [visionSnapshot[@"traitList"] isKindOfClass:NSDictionary.class] ? visionSnapshot[@"traitList"] : @{};
    NSArray *parsedTraits = [traitList[@"traits"] isKindOfClass:NSArray.class] ? traitList[@"traits"] : @[];
    NSMutableArray *traitParts = [NSMutableArray array];
    for (NSDictionary *trait in parsedTraits) {
        NSString *name = [trait[@"name"] isKindOfClass:NSString.class] ? trait[@"name"] : @"?";
        NSNumber *count = [trait[@"count"] isKindOfClass:NSNumber.class] ? trait[@"count"] : @0;
        [traitParts addObject:[NSString stringWithFormat:@"%@=%@", name, count]];
        if (traitParts.count >= 8) {
            break;
        }
    }
    [lines addObject:traitParts.count > 0 ? [NSString stringWithFormat:@"Traits: %@", [traitParts componentsJoinedByString:@" | "]] : @"Traits: none"];

    NSArray *partialTraits = [traitList[@"partialTraits"] isKindOfClass:NSArray.class] ? traitList[@"partialTraits"] : @[];
    NSMutableArray *partialParts = [NSMutableArray array];
    for (NSDictionary *trait in partialTraits) {
        NSString *name = [trait[@"name"] isKindOfClass:NSString.class] ? trait[@"name"] : @"?";
        NSNumber *count = [trait[@"count"] isKindOfClass:NSNumber.class] ? trait[@"count"] : @0;
        NSNumber *threshold = [trait[@"threshold"] isKindOfClass:NSNumber.class] ? trait[@"threshold"] : @0;
        [partialParts addObject:[NSString stringWithFormat:@"%@=%@/%@", name, count, threshold]];
        if (partialParts.count >= 6) {
            break;
        }
    }
    NSNumber *extraTraitAllowance = [traitList[@"extraTraitAllowance"] isKindOfClass:NSNumber.class] ? traitList[@"extraTraitAllowance"] : @0;
    [lines addObject:partialParts.count > 0 ? [NSString stringWithFormat:@"Partial (+%@): %@", extraTraitAllowance, [partialParts componentsJoinedByString:@" | "]] : [NSString stringWithFormat:@"Partial: none (+%@)", extraTraitAllowance]];

    NSDictionary *boardReconstruction = [visionSnapshot[@"boardReconstruction"] isKindOfClass:NSDictionary.class] ? visionSnapshot[@"boardReconstruction"] : @{};
    NSArray *unitNames = [boardReconstruction[@"unitNames"] isKindOfClass:NSArray.class] ? boardReconstruction[@"unitNames"] : @[];
    if (unitNames.count > 0) {
        NSString *status = [boardReconstruction[@"status"] isKindOfClass:NSString.class] ? boardReconstruction[@"status"] : @"";
        [lines addObject:[NSString stringWithFormat:@"Board %@: %@", status, [unitNames componentsJoinedByString:@", "]]];
    } else if ([boardReconstruction[@"reason"] isKindOfClass:NSString.class]) {
        [lines addObject:[NSString stringWithFormat:@"Board: %@", boardReconstruction[@"reason"]]];
    } else {
        [lines addObject:@"Board: no reconstruction"];
    }
    [lines addObject:[NSString stringWithFormat:@"Augments: %@", [augments componentsJoinedByString:@" | "]]];
    BOOL sawGodBoonText = NO;
    for (NSString *godBoon in godBoons) {
        if (godBoon.length > 0 && ![godBoon isEqualToString:@"-"]) {
            sawGodBoonText = YES;
            break;
        }
    }
    if (sawGodBoonText) {
        [lines addObject:[NSString stringWithFormat:@"God OCR: %@", [godBoons componentsJoinedByString:@" | "]]];
    }
    if (tierLines.count > 0) {
        [lines addObject:[NSString stringWithFormat:@"Tiers: %@", [tierLines componentsJoinedByString:@" | "]]];
    }
    if (godBoonMatches.count > 0) {
        NSMutableArray *godTierLines = [NSMutableArray array];
        for (NSDictionary *match in godBoonMatches) {
            NSString *name = [match[@"displayName"] isKindOfClass:NSString.class] ? match[@"displayName"] : @"?";
            NSString *tier = [match[@"tier"] isKindOfClass:NSString.class] ? match[@"tier"] : @"?";
            NSNumber *slot = [match[@"slot"] isKindOfClass:NSNumber.class] ? match[@"slot"] : @0;
            [godTierLines addObject:[NSString stringWithFormat:@"%ld:%@=%@", slot.integerValue + 1, name, tier]];
        }
        [lines addObject:[NSString stringWithFormat:@"Gods: %@ OCR:%@", [godTierLines componentsJoinedByString:@" | "], [godBoons componentsJoinedByString:@" | "]]];
    }
    if (self.selectedHeroComp.length > 0) {
        [lines addObject:[NSString stringWithFormat:@"Hero Comp: %@", self.selectedHeroComp]];
    }
    NSDictionary *compSuggestion = [visionSnapshot[@"compSuggestion"] isKindOfClass:NSDictionary.class] ? visionSnapshot[@"compSuggestion"] : @{};
    NSArray *suggestedComps = [compSuggestion[@"comps"] isKindOfClass:NSArray.class] ? compSuggestion[@"comps"] : @[];
    NSMutableArray *titles = [NSMutableArray array];
    for (NSDictionary *comp in suggestedComps) {
        NSString *title = [comp[@"title"] isKindOfClass:NSString.class] ? comp[@"title"] : @"?";
        NSNumber *matchCount = [comp[@"matchCount"] isKindOfClass:NSNumber.class] ? comp[@"matchCount"] : nil;
        [titles addObject:matchCount != nil ? [NSString stringWithFormat:@"%@=%@", title, matchCount] : title];
        if (titles.count >= 3) {
            break;
        }
    }
    [lines addObject:titles.count > 0 ? [NSString stringWithFormat:@"Comps: %@", [titles componentsJoinedByString:@" | "]] : @"Comps: none"];
    return lines;
}

- (NSString *)regionText:(NSString *)regionID regions:(NSArray *)regions {
    for (NSDictionary *region in regions) {
        if (![region isKindOfClass:NSDictionary.class]) {
            continue;
        }
        if (![region[@"id"] isEqualToString:regionID]) {
            continue;
        }
        NSString *cleanText = [region[@"cleanText"] isKindOfClass:NSString.class] ? region[@"cleanText"] : nil;
        if (cleanText.length > 0) {
            return cleanText;
        }
        return [region[@"text"] isKindOfClass:NSString.class] ? region[@"text"] : @"";
    }
    return @"";
}

- (void)toggleOverlay:(id)sender {
    [self setOverlayVisible:!self.overlayWindow.visible];
}

- (void)toggleOCRZones:(id)sender {
    self.overlayView.showOCRZones = !self.overlayView.showOCRZones;
}

- (void)toggleCalibrationBox:(id)sender {
    if (self.calibrationWindow.visible) {
        [self saveVisibleCalibrationBox];
        return;
    }

    NSScreen *screen = NSScreen.mainScreen;
    NSRect screenFrame = screen != nil ? screen.frame : NSMakeRect(0, 0, 1440, 900);
    NSRect initialFrame = NSMakeRect(NSMidX(screenFrame) - 160, NSMidY(screenFrame) - 90, 320, 180);
    if (self.calibrationWindow == nil) {
        self.calibrationWindow = [[CalibrationBoxWindow alloc] initWithFrame:initialFrame];
    } else {
        [self.calibrationWindow setFrame:initialFrame display:NO];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self.calibrationWindow orderFrontRegardless];
    [self.calibrationWindow makeKeyWindow];
}

- (void)saveManualSnapshot:(id)sender {
    NSDictionary *snapshotRecord = [self.visionProbe saveManualSnapshotInLogDirectory:self.logWriter.logDirectoryURL];
    [self.logWriter appendManualSnapshotRecord:snapshotRecord];

    NSString *imagePath = [snapshotRecord[@"imagePath"] isKindOfClass:NSString.class] ? snapshotRecord[@"imagePath"] : @"";
    if (imagePath.length > 0) {
        self.overlayView.snapshot.stageHint = [NSString stringWithFormat:@"Saved snapshot: %@", imagePath.lastPathComponent];
        [self.overlayView setNeedsDisplay:YES];
    }
}

- (void)saveVisibleCalibrationBox {
    if (!self.calibrationWindow.visible) {
        return;
    }

    NSRect frame = self.calibrationWindow.frame;
    NSScreen *screen = [self screenContainingRect:frame] ?: NSScreen.mainScreen;
    NSRect screenFrame = screen != nil ? screen.frame : NSMakeRect(0, 0, 1440, 900);
    self.calibrationRegionCount += 1;
    NSString *defaultName = [NSString stringWithFormat:@"region_%03lu", (unsigned long)self.calibrationRegionCount];
    NSString *name = [self promptForCalibrationRegionName:defaultName];
    if (name.length == 0) {
        [self.calibrationWindow orderOut:nil];
        return;
    }

    [self.logWriter appendCalibrationRegionWithName:name frame:frame screenFrame:screenFrame];
    [self.calibrationWindow orderOut:nil];
}

- (NSString *)promptForCalibrationRegionName:(NSString *)defaultName {
    self.calibrationPromptOpen = YES;
    [NSApp activateIgnoringOtherApps:YES];

    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Save calibration region";
    alert.informativeText = @"Name this box so the coordinates are easy to find in the collection log.";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    input.stringValue = defaultName ?: @"region";
    alert.accessoryView = input;

    NSModalResponse response = [alert runModal];
    self.calibrationPromptOpen = NO;
    if (response != NSAlertFirstButtonReturn) {
        return nil;
    }

    NSString *name = [input.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return name.length > 0 ? name : defaultName;
}

- (NSScreen *)screenContainingRect:(NSRect)rect {
    NSScreen *bestScreen = nil;
    CGFloat bestArea = 0;
    for (NSScreen *screen in NSScreen.screens) {
        NSRect intersection = NSIntersectionRect(screen.frame, rect);
        CGFloat area = NSWidth(intersection) * NSHeight(intersection);
        if (area > bestArea) {
            bestArea = area;
            bestScreen = screen;
        }
    }
    return bestScreen;
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
