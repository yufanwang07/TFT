#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Vision/Vision.h>

@interface GameSnapshot : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *subtitle;
@property(nonatomic, copy, nullable) NSString *detail;
@property(nonatomic, copy, nullable) NSString *stageHint;
@property(nonatomic, copy) NSArray<NSDictionary *> *augmentTierOverlays;
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
@end

@implementation OverlayView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _snapshot = [GameSnapshot idle];
        _mouseScreenPoint = NSMakePoint(CGFLOAT_MIN, CGFLOAT_MIN);
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
    [self drawVisionDebugPanel];
    [self drawStageHint];
    [self drawAugmentTierOverlays];
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

- (void)drawVisionDebugPanel {
    if (self.snapshot.visionDebugLines.count == 0) {
        return;
    }

    NSRect bounds = self.bounds;
    CGFloat lineHeight = 17;
    CGFloat height = 24 + lineHeight * MIN(self.snapshot.visionDebugLines.count, 10);
    NSRect panel = NSMakeRect(NSMinX(bounds) + 24, NSMaxY(bounds) - 172 - height, 430, height);
    [self drawPanel:panel fill:[NSColor colorWithWhite:0 alpha:0.52]];

    CGFloat y = NSMaxY(panel) - 22;
    for (NSUInteger i = 0; i < self.snapshot.visionDebugLines.count && i < 10; i += 1) {
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
    self.hoveredCompBadge = nil;
    self.hoveredCompBadgeRect = NSZeroRect;
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

    if (self.hoveredCompBadge != nil) {
        [self drawCompTooltipForBadge:self.hoveredCompBadge anchorRect:self.hoveredCompBadgeRect];
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
        NSRect rect = [self rectFromTopOriginBaseRect:zoneValue.rectValue];
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

- (NSRect)rectFromTopOriginBaseRect:(NSRect)baseRect {
    CGFloat scaleX = NSWidth(self.bounds) / 1920.0;
    CGFloat scaleY = NSHeight(self.bounds) / 1080.0;
    return NSMakeRect(NSMinX(baseRect) * scaleX,
                      NSHeight(self.bounds) - NSMaxY(baseRect) * scaleY,
                      NSWidth(baseRect) * scaleX,
                      NSHeight(baseRect) * scaleY);
}

- (void)drawTierHexagon:(NSString *)tier actualTier:(NSString *)actualTier inRect:(NSRect)rect {
    [self drawSingleTierHexagon:tier inRect:rect textSize:28];

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
    [self drawSingleTierHexagon:actualTier inRect:smallRect textSize:13];
}

- (void)drawSingleTierHexagon:(NSString *)tier inRect:(NSRect)rect textSize:(CGFloat)textSize {
    NSColor *outer = [self tierOuterColor:tier];
    NSColor *inner = [self tierInnerColor:tier];
    NSBezierPath *outerPath = [self hexagonPathInRect:rect inset:0];
    NSGradient *outerGradient = [[NSGradient alloc] initWithStartingColor:[self tierGradientHighlightColorForColor:outer tier:tier amount:0.18]
                                                              endingColor:outer];
    [outerGradient drawInBezierPath:outerPath angle:90];

    NSBezierPath *innerPath = [self hexagonPathInRect:rect inset:6];
    NSGradient *innerGradient = [[NSGradient alloc] initWithStartingColor:[self tierGradientHighlightColorForColor:inner tier:tier amount:0.16]
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
    if ([tier isEqualToString:@"X"]) return [NSColor colorWithCalibratedRed:0.02 green:0.38 blue:0.48 alpha:0.96];
    if ([tier isEqualToString:@"S"]) return [NSColor colorWithCalibratedRed:0.48 green:0.04 blue:0.08 alpha:0.96];
    if ([tier isEqualToString:@"A"]) return [NSColor colorWithCalibratedRed:0.70 green:0.30 blue:0.04 alpha:0.96];
    if ([tier isEqualToString:@"B"]) return [NSColor colorWithCalibratedRed:0.72 green:0.56 blue:0.08 alpha:0.96];
    if ([tier isEqualToString:@"C"]) return [NSColor colorWithCalibratedRed:0.05 green:0.42 blue:0.22 alpha:0.96];
    return [NSColor colorWithWhite:0.15 alpha:0.96];
}

- (NSColor *)tierInnerColor:(NSString *)tier {
    if ([tier isEqualToString:@"X"]) return [NSColor colorWithCalibratedRed:0.05 green:0.82 blue:0.96 alpha:0.96];
    if ([tier isEqualToString:@"S"]) return [NSColor colorWithCalibratedRed:1.00 green:0.08 blue:0.16 alpha:0.96];
    if ([tier isEqualToString:@"A"]) return [NSColor colorWithCalibratedRed:1.00 green:0.48 blue:0.10 alpha:0.96];
    if ([tier isEqualToString:@"B"]) return [NSColor colorWithCalibratedRed:1.00 green:0.78 blue:0.10 alpha:0.96];
    if ([tier isEqualToString:@"C"]) return [NSColor colorWithCalibratedRed:0.08 green:0.72 blue:0.36 alpha:0.96];
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
            NSRect iconRect = NSMakeRect(NSMinX(chip) + 4 * scale, NSMinY(chip) + 3 * scale, 16 * scale, 16 * scale);
            [icon drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:0.88 respectFlipped:YES hints:nil];
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

@interface VisionProbeRegion : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic) CGRect baseRect;
+ (instancetype)regionWithIdentifier:(NSString *)identifier x1:(CGFloat)x1 y1:(CGFloat)y1 x2:(CGFloat)x2 y2:(CGFloat)y2;
@end

@implementation VisionProbeRegion
+ (instancetype)regionWithIdentifier:(NSString *)identifier x1:(CGFloat)x1 y1:(CGFloat)y1 x2:(CGFloat)x2 y2:(CGFloat)y2 {
    VisionProbeRegion *region = [VisionProbeRegion new];
    region.identifier = identifier;
    region.baseRect = CGRectMake(x1, y1, x2 - x1, y2 - y1);
    return region;
}
@end

@interface VisionProbeReader : NSObject
@property(nonatomic, strong) NSArray<VisionProbeRegion *> *regions;
@property(nonatomic) NSUInteger captureIndex;
- (NSDictionary *)captureSnapshotInLogDirectory:(NSURL *)logDirectoryURL;
- (NSDictionary *)saveManualSnapshotInLogDirectory:(NSURL *)logDirectoryURL;
@end

@implementation VisionProbeReader
- (instancetype)init {
    self = [super init];
    if (self) {
        _regions = @[
            [VisionProbeRegion regionWithIdentifier:@"stage" x1:560 y1:0 x2:1300 y2:82],
            [VisionProbeRegion regionWithIdentifier:@"level" x1:185 y1:890 x2:355 y2:942],
            [VisionProbeRegion regionWithIdentifier:@"xp" x1:350 y1:888 x2:465 y2:930],
            [VisionProbeRegion regionWithIdentifier:@"gold" x1:880 y1:890 x2:1030 y2:942],
            [VisionProbeRegion regionWithIdentifier:@"shop_1" x1:440 y1:1038 x2:620 y2:1068],
            [VisionProbeRegion regionWithIdentifier:@"shop_2" x1:640 y1:1038 x2:835 y2:1068],
            [VisionProbeRegion regionWithIdentifier:@"shop_3" x1:875 y1:1040 x2:1010 y2:1066],
            [VisionProbeRegion regionWithIdentifier:@"shop_4" x1:1090 y1:1040 x2:1215 y2:1066],
            [VisionProbeRegion regionWithIdentifier:@"shop_5" x1:1290 y1:1040 x2:1415 y2:1066],
            [VisionProbeRegion regionWithIdentifier:@"augment_1" x1:417 y1:552 x2:687 y2:582],
            [VisionProbeRegion regionWithIdentifier:@"augment_2" x1:825 y1:552 x2:1095 y2:582],
            [VisionProbeRegion regionWithIdentifier:@"augment_3" x1:1230 y1:552 x2:1500 y2:582]
        ];
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

    NSMutableArray *regionResults = [NSMutableArray array];
    for (VisionProbeRegion *region in self.regions) {
        CGRect cropRect = CGRectMake(round(CGRectGetMinX(region.baseRect) * scaleX),
                                     round(contentTopInset + CGRectGetMinY(region.baseRect) * scaleY),
                                     round(CGRectGetWidth(region.baseRect) * scaleX),
                                     round(CGRectGetHeight(region.baseRect) * scaleY));
        cropRect = CGRectIntersection(cropRect, CGRectMake(0, 0, imageWidth, imageHeight));
        if (CGRectIsNull(cropRect) || cropRect.size.width < 2 || cropRect.size.height < 2) {
            continue;
        }

        CGImageRef crop = CGImageCreateWithImageInRect(image, cropRect);
        if (crop == NULL) {
            continue;
        }

        NSMutableDictionary *regionResult = [[self recognizedTextForImage:crop] mutableCopy];
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
        }

        [regionResults addObject:regionResult];
        CGImageRelease(crop);
    }

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
    if (reason.length > 0) {
        snapshot[@"reason"] = reason;
    }
    if (windowInfo != nil) {
        snapshot[@"window"] = [self publicWindowDictionary:windowInfo];
    }
    return snapshot;
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

    return rawText;
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

- (NSDictionary *)recognizedTextForImage:(CGImageRef)image {
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:nil];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.recognitionLanguages = @[@"en-US"];
    request.usesLanguageCorrection = YES;

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
        [candidates addObject:@{
            @"text": candidate.string ?: @"",
            @"confidence": @(candidate.confidence)
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
@property(nonatomic, strong) NSDictionary<NSString *, NSArray<NSDictionary *> *> *compBadgesByApiName;
- (NSArray<NSDictionary *> *)matchesForVisionSnapshot:(NSDictionary *)visionSnapshot;
@end

@implementation AugmentTierMatcher
- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [self loadEntries];
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
    NSString *roundText = [self textForRegion:@"stage" regions:regions];
    NSString *stage = [self normalizedStageFromRoundText:roundText];

    NSMutableArray *matches = [NSMutableArray array];
    for (NSInteger slot = 0; slot < 3; slot += 1) {
        NSString *regionID = [NSString stringWithFormat:@"augment_%ld", slot + 1];
        NSString *ocrText = [self textForRegion:regionID regions:regions];
        NSDictionary *match = [self matchForText:ocrText slot:slot stage:stage];
        if (match != nil) {
            [matches addObject:match];
        }
    }
    return matches;
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

    if (bestApiName.length == 0 || bestScore < 0.72) {
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
@property(nonatomic, strong) GameStateLogWriter *logWriter;
@property(nonatomic) NSTimeInterval pollingInterval;
@property(nonatomic, strong) id clickMonitor;
@property(nonatomic, strong) id keyMonitor;
@property(nonatomic, strong) id localKeyMonitor;
@property(nonatomic, strong) CalibrationBoxWindow *calibrationWindow;
@property(nonatomic, copy) NSArray<NSDictionary *> *currentAugmentMatches;
@property(nonatomic, copy, nullable) NSString *selectedHeroComp;
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
    return NO;
}

- (void)handleGlobalLeftClickAtScreenPoint:(NSPoint)point {
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

- (NSInteger)augmentSlotForScreenPoint:(NSPoint)point {
    NSScreen *screen = NSScreen.mainScreen;
    if (screen == nil) {
        return -1;
    }
    NSRect frame = screen.frame;
    CGFloat baseX = ((point.x - NSMinX(frame)) / NSWidth(frame)) * 1920.0;
    CGFloat baseY = ((NSMaxY(frame) - point.y) / NSHeight(frame)) * 1080.0;
    NSArray<NSValue *> *zones = @[
        [NSValue valueWithRect:NSMakeRect(350, 276, 350, 560)],
        [NSValue valueWithRect:NSMakeRect(785, 276, 350, 560)],
        [NSValue valueWithRect:NSMakeRect(1220, 276, 350, 560)]
    ];
    NSPoint basePoint = NSMakePoint(baseX, baseY);
    for (NSInteger i = 0; i < (NSInteger)zones.count; i += 1) {
        if (NSPointInRect(basePoint, zones[i].rectValue)) {
            return i;
        }
    }
    return -1;
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
    LeagueClientReader *leagueClient = self.leagueClient;
    LiveClientDataReader *liveClient = self.liveClient;
    VisionProbeReader *visionProbe = self.visionProbe;
    AugmentTierMatcher *augmentTierMatcher = self.augmentTierMatcher;
    GameStateLogWriter *logWriter = self.logWriter;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        LocalHTTPResult *lcuResult = nil;
        LocalHTTPResult *liveResult = nil;
        NSDictionary *lockfileInfo = nil;
        NSDictionary *liveJSON = nil;
        NSString *phase = [leagueClient gameflowPhaseWithResult:&lcuResult lockfileInfo:&lockfileInfo];
        NSDictionary *lcuEndpoints = [leagueClient endpointSnapshotsWithLockfileInfo:&lockfileInfo];
        NSNumber *gameTime = [liveClient gameTimeWithResult:&liveResult parsedJSON:&liveJSON];
        NSDictionary *visionSnapshot = [visionProbe captureSnapshotInLogDirectory:logWriter.logDirectoryURL];
        GameSnapshot *snapshot = (phase.length > 0 || gameTime != nil) ? [GameSnapshot snapshotWithPhase:phase gameTime:gameTime] : [GameSnapshot idle];
        snapshot.augmentTierOverlays = [augmentTierMatcher matchesForVisionSnapshot:visionSnapshot];
        self.currentAugmentMatches = snapshot.augmentTierOverlays;
        snapshot.heroCompName = self.selectedHeroComp;
        snapshot.visionDebugLines = [self visionDebugLinesForSnapshot:visionSnapshot augmentMatches:snapshot.augmentTierOverlays];

        [logWriter appendPhase:phase
                      gameTime:gameTime
                      snapshot:snapshot
                     lcuResult:lcuResult
                  lcuEndpoints:lcuEndpoints
                    liveResult:liveResult
                  lockfileInfo:lockfileInfo
                      liveJSON:liveJSON
                visionSnapshot:visionSnapshot];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.overlayView.snapshot = snapshot;
            [self.settingsWindowController updateSnapshot:snapshot overlayVisible:self.overlayWindow.visible];
        });
    });
}

- (NSArray<NSString *> *)visionDebugLinesForSnapshot:(NSDictionary *)visionSnapshot augmentMatches:(NSArray<NSDictionary *> *)augmentMatches {
    if (![visionSnapshot[@"available"] boolValue]) {
        NSString *error = [visionSnapshot[@"error"] isKindOfClass:NSString.class] ? visionSnapshot[@"error"] : @"Vision unavailable";
        return @[[NSString stringWithFormat:@"OCR: %@", error]];
    }

    NSArray *regions = [visionSnapshot[@"regions"] isKindOfClass:NSArray.class] ? visionSnapshot[@"regions"] : @[];
    NSString *stage = [self regionText:@"stage" regions:regions];
    NSString *level = [self regionText:@"level" regions:regions];
    NSString *xp = [self regionText:@"xp" regions:regions];
    NSString *gold = [self regionText:@"gold" regions:regions];

    NSMutableArray *shop = [NSMutableArray array];
    for (NSInteger i = 1; i <= 5; i += 1) {
        NSString *text = [self regionText:[NSString stringWithFormat:@"shop_%ld", i] regions:regions];
        [shop addObject:text.length > 0 ? text : @"-"];
    }

    NSMutableArray *augments = [NSMutableArray array];
    for (NSInteger i = 1; i <= 3; i += 1) {
        NSString *text = [self regionText:[NSString stringWithFormat:@"augment_%ld", i] regions:regions];
        [augments addObject:text.length > 0 ? text : @"-"];
    }

    NSMutableArray *tierLines = [NSMutableArray array];
    for (NSDictionary *match in augmentMatches) {
        NSString *name = [match[@"displayName"] isKindOfClass:NSString.class] ? match[@"displayName"] : @"?";
        NSString *tier = [match[@"tier"] isKindOfClass:NSString.class] ? match[@"tier"] : @"?";
        NSNumber *slot = [match[@"slot"] isKindOfClass:NSNumber.class] ? match[@"slot"] : @0;
        [tierLines addObject:[NSString stringWithFormat:@"%ld:%@=%@", slot.integerValue + 1, name, tier]];
    }

    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"OCR src:%@ stage:%@ lvl:%@ xp:%@ gold:%@",
                      visionSnapshot[@"source"] ?: @"?",
                      stage.length > 0 ? stage : @"-",
                      level.length > 0 ? level : @"-",
                      xp.length > 0 ? xp : @"-",
                      gold.length > 0 ? gold : @"-"]];
    [lines addObject:[NSString stringWithFormat:@"Shop: %@", [shop componentsJoinedByString:@" | "]]];
    [lines addObject:[NSString stringWithFormat:@"Augments: %@", [augments componentsJoinedByString:@" | "]]];
    if (tierLines.count > 0) {
        [lines addObject:[NSString stringWithFormat:@"Tiers: %@", [tierLines componentsJoinedByString:@" | "]]];
    }
    if (self.selectedHeroComp.length > 0) {
        [lines addObject:[NSString stringWithFormat:@"Hero Comp: %@", self.selectedHeroComp]];
    }
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
