//
//  XLog.m
//  XLog
//
//  Created by WenDong Zhang on 5/8/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "XLog.h"
#import <objc/runtime.h>

#ifndef DEBUG
#define MXLog(...)
#endif

#define MXLog(...)  write2log([NSString stringWithFormat:__VA_ARGS__])

// env name
#define XLOG_FLAG   "XLOG_FLAG"

#define ESC_CH  @"\033"
#define XLOG_COLOR_PREX     ESC_CH @"#"
// hard code reset color.
#define XLOG_COLOR_RESET    @"00000m"
#define XLOG_LEVEL_DEBUG    @"DEBUG"
#define XLOG_LEVEL_INFO     @"INFO"
#define XLOG_LEVEL_WARN     @"WARN"
#define XLOG_LEVEL_ERROR     @"ERROR"

// color strlen: [000000, FFFFFF]
#define LENGTH_COLOR    6  
#define LENGTH_COLOR_PREX 2

/** global variables **/
static IMP originalFixAttributesInRange = nil;
static XLog *XLogInstance = nil;    // used to handle click event
static NSDictionary *defaultAttrs = nil;    // default console text attrs, used for reset()
static NSDictionary *hiddenAttrs = nil;

// there are more than one projects opened at the same time, each one has a console. we need cache it.
static NSMutableDictionary *consoleTextStorageMap = nil;    // <DVDFoldingTextStorage|DVTTextStorage *, XLog_Console *>


// for log file
const char *logfile = "log.txt";
static FILE *logfp = 0;
const long MAX_LOG_SIZE = 1000 * 1000;


@implementation XLog

+ (void)pluginDidLoad:(NSBundle *)bundle
{
    logfp = fopen([[NSString stringWithFormat:@"%@/%s", [bundle bundlePath], logfile] UTF8String], "w+");
    if (logfp == 0) {
        MXLog(@"open log file error");
    }
    MXLog(@"%s, %@", __PRETTY_FUNCTION__, bundle);
}

+ (void)load
{
    MXLog(@"%s env[%s]", __PRETTY_FUNCTION__, getenv(XLOG_FLAG));
	if (getenv(XLOG_FLAG) && !strcmp(getenv(XLOG_FLAG), "YES")) {   // alreay installed
		return;
    }

    replaceFixAttributesInRangeMethod();
    setenv(XLOG_FLAG, "YES", 0);
    
    // init map and set
    XLogInstance = [[XLog alloc] init];
    consoleTextStorageMap = [[NSMutableDictionary alloc] initWithCapacity:0];
    hiddenAttrs = [NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:0.001f], NSFontAttributeName, [NSColor clearColor], NSForegroundColorAttributeName, nil];

}

- (void)onLogLevelButtonClick:(id)sender
{
    NSPopUpButton *btn = (NSPopUpButton *)sender;
    XLog_Console *console = getConsole((NSTextStorage *)btn.tag);
    if (console == nil) {
        MXLog(@"FIXME: Console is null in %s", __FUNCTION__);
        return ;
    }
    NSUInteger idx = [btn indexOfSelectedItem];
    if (idx != console.lastLogLevel) {
        console.lastLogLevel = idx;
        reset(console.realTextStorage);
        parse(console, NSMakeRange(0, [console.realTextStorage length]));
        [XLogInstance performSelector:@selector(fixTextViewLayout:) withObject:console.textView afterDelay:0.0f];
    }
}

- (void)onFilterButtonClick:(id)sender
{
    NSButton *btn = (NSButton *)sender;
    XLog_Console *console = getConsole((NSTextStorage *)btn.tag);
    if (console == nil) {
        MXLog(@"FIXME: Console is null in %s", __FUNCTION__);
        return ;
    }

    // avoid multi click
    NSString *regexString = [console.searchField stringValue];
    if ([regexString isEqualToString:console.lastSearchText]) {
        return ;
    }
    console.lastSearchText = [console.searchField stringValue];
    reset(console.realTextStorage);
    parse(console, NSMakeRange(0, [console.realTextStorage length]));
    [XLogInstance performSelector:@selector(fixTextViewLayout:) withObject:console.textView afterDelay:0.0f];
}

- (void)fixTextViewLayout:(NSTextView *)textView
{
    MXLog(@"fix display");
    CGRect frame = textView.frame;
    frame.size.width--;
    textView.frame = frame;
    frame.size.width++;
    textView.frame = frame;
    [textView setNeedsDisplay:YES];
    [textView setNeedsLayout:YES];
}

@end

@implementation XLog_TextStorage

- (void)fixAttributesInRange:(NSRange)range
{
    originalFixAttributesInRange(self, _cmd, range);
    
    NSString *className = NSStringFromClass([self class]);
    MXLog(@"fixAttributesInRange[%@]", className);
    // it must not a console textstorage.
    if (![className isEqualToString:@"DVTFoldingTextStorage"]  
        && ![className isEqualToString:@"DVTTextStorage"]) {
        return ;
    }

    XLog_Console *console = getConsole(self);
    if (console != nil && console.lastStrlen != [self length]) {   // this is a console textStorage and text changed
        if (defaultAttrs == nil) {  // save default text attr at first time
            defaultAttrs = [self attributesAtIndex:0 effectiveRange:NULL];
        }
        console.lastStrlen = [self length];
        parse(console, range);
    }
    
    // self is new, test it. Only need test DVTFoldingTextStorage
    if (console == nil && [className isEqualToString:@"DVTFoldingTextStorage"]) {
        testTextStorage(self);
    }
}

@end

/** XLog_Console **/
@implementation XLog_Console
@synthesize realTextStorage, textView, searchField, lastSearchText, lastLogLevel, lastStrlen;
- (void)dealloc
{
    [lastSearchText release];
    [super dealloc];
}
@end

/** functions **/
void replaceFixAttributesInRangeMethod()
{
    Method originalMethod = class_getInstanceMethod([NSTextStorage class], @selector(fixAttributesInRange:));
    // save original impl
	originalFixAttributesInRange = method_getImplementation(originalMethod);
    
	IMP newImpl = class_getMethodImplementation([XLog_TextStorage class], @selector(fixAttributesInRange:));
	method_setImplementation(originalMethod, newImpl);
}

BOOL testTextStorage(NSTextStorage *textStorage)
{
    id textView = nil;
    // MXLog(@"%@, %lx", NSStringFromClass([textStorage class]), (long)textStorage);
    // is NSTextStorage instance
	if ([textStorage respondsToSelector:@selector(layoutManagers)])
	{
		id layoutManagers = [(NSTextStorage*)textStorage layoutManagers];
		if ([layoutManagers count])
		{
			id layoutManager = [layoutManagers objectAtIndex:0];
			if ([layoutManager respondsToSelector:@selector(firstTextView)])
				textView = [layoutManager firstTextView];
		}
	}
    // this textstorage hasn't NSTextView, return
    if (textView == nil) return NO;
    // textView is not console textView, return 
    if (![NSStringFromClass([textView class]) isEqualToString:@"IDEConsoleTextView"]) return NO;
    // try to find console NSTextView and toolbar View's commom parent. (Hardcode: I found it was NSView)
    NSView *pView = textView;
    while (pView != nil && ![NSStringFromClass([pView class]) isEqualToString:@"NSView"]) {
        // MXLog(@"pView class:[%@]", NSStringFromClass([pView class]));
        pView = pView.superview;
    }
    if (pView == nil) { // pView should not be nil. or the Xcode's UI changes. Fix it in other Xcode versions.
        MXLog(@"FIXME: Cannot find NSView in the hierarchy!");
        return NO;
    }
    //-- find toolbar view
    NSView *toolbarView = nil;
    for (int i = 0; i != [pView.subviews count]; ++i) {
        NSView *tmp = [pView.subviews objectAtIndex:i];
        if ([NSStringFromClass([tmp class]) isEqualToString:@"DVTScopeBarView"]) {
            toolbarView = tmp;
            break;
        }
    }
    if (toolbarView == nil) {
        MXLog(@"FIXME: Cannot find toolbar view!");
        return NO;
    }
    //-- find Output PopUpButton. add customized views after it.
    NSPopUpButton *outputPopUpButton = nil;
    for (int i = 0; i != [toolbarView.subviews count]; ++i) {
        NSView *tmp = [toolbarView.subviews objectAtIndex:i];
        if ([NSStringFromClass([tmp class]) isEqualToString:@"NSPopUpButton"]) {
            outputPopUpButton = (NSPopUpButton *)tmp;
            break;
        }
    }
    if (outputPopUpButton == nil) {
        MXLog(@"FIXME: Cannot find output popup button");
        return NO;
    }
    //-- almost done. now we find all views we need. BUT the textStorage is not!!
    /*
     * The textStorage is a DVTFoldTextStorage, you can dump it to see some detail.
     *  I found that change the textStorage's attrs not work for the console. 
     *  But there is a "realTextStorage" member in the DVTFoldTextStorage, that is exactly what we want.
     *  How to get it? HARDCODE! It's OK in Xcode4.3.2, maybe crash in other versions. Fix it!
     */
    NSTextStorage *realTextStorage = nil;
    NSString *classInfo = [NSString stringWithFormat:@"%@", textStorage];
    // MXLog(@"textStorage info:[%@]", classInfo);
    NSRange r = [classInfo rangeOfString:@"realTextStorage: <DVTTextStorage: "];
    if (r.length > 0) { // find
        unsigned long long addr;
        NSScanner *scanner = [NSScanner scannerWithString:[classInfo substringFromIndex:r.location + r.length]];
        [scanner scanHexLongLong:&addr];
        if (addr > 0) { 
            realTextStorage = (NSTextStorage *)addr;
            MXLog(@"Reset console textstorage:[%@]", realTextStorage);
        }
    }
    
    XLog_Console *console = [[XLog_Console alloc] init];
    console.realTextStorage = realTextStorage;
    console.textView = textView;
    console.lastStrlen = 0;
    console.lastSearchText = nil;
    console.lastLogLevel = 0;
    addCustomizedViews(outputPopUpButton, console, textStorage);
    // add to map
    [consoleTextStorageMap setObject:console forKey:hash(textStorage)]; // add textStorage to prevent multipule init console
    [consoleTextStorageMap setObject:console forKey:hash(realTextStorage)]; // add realTextStorage to parse it.
    // MXLog(@"%ld , %ld", [textStorage hash], [realTextStorage hash]); // there are equal...
    [console release];
    return YES;
}

void addCustomizedViews(NSPopUpButton *anchorBtn, XLog_Console *console, NSTextStorage *key)
{
    NSFont *font = anchorBtn.font;
    
    NSView *pView = anchorBtn.superview;    // parent view (container)
    CGFloat x = anchorBtn.frame.origin.x + anchorBtn.frame.size.width;  // for horizental layout
    CGFloat pHeight = pView.frame.size.height; 
    CGFloat margin = 1.0f;   // search field and filter button's top/bottom margin 
    
    // add log level popup button
    NSPopUpButton *logLevelButton = [[NSPopUpButton alloc] initWithFrame:CGRectZero pullsDown:NO];
    NSArray *items = [NSArray arrayWithObjects:@"All logs", @"Debug", @"Info", @"Warn", @"Error", nil];
    [logLevelButton addItemsWithTitles:items];
    [logLevelButton setBordered:NO];
    [logLevelButton setFont:font];
    [logLevelButton sizeToFit];
    CGRect frame = logLevelButton.frame;
    logLevelButton.frame = CGRectMake(x, (pHeight - frame.size.height) / 2.0f, frame.size.width, frame.size.height) ;
    [pView addSubview:logLevelButton];
    [logLevelButton release];
    
    // set click handler
    [logLevelButton setTarget:XLogInstance];
    [logLevelButton setAction:@selector(onLogLevelButtonClick:)];
    logLevelButton.tag = (long)key; // save the refer
    
    x += logLevelButton.frame.size.width;
    
    // add regex filter textview
    NSSearchField *field = [[NSSearchField alloc] initWithFrame:CGRectMake(x, margin, 200.0f, pHeight - 2 * margin)];
    field.font = font;
    [field.cell setPlaceholderString:@"Use regex to filter"];
    [pView addSubview:field];
    [field release];
    
    x += field.frame.size.width;
    
    // add filter button
    NSButton *filterButton = [[NSButton alloc] initWithFrame:CGRectZero];
    filterButton.font = font;
    [filterButton setTitle:@"Filter"];
    [filterButton sizeToFit];
    frame = filterButton.frame;
    filterButton.frame = CGRectMake(x + 10.0f, (pHeight - frame.size.height) / 2.0f, frame.size.width, frame.size.height);
    [pView addSubview:filterButton];
    [filterButton release];
    
    // set filter button handler
    [filterButton setTarget:XLogInstance];
    [filterButton setAction:@selector(onFilterButtonClick:)];
    filterButton.tag = (long)key;
    
    console.searchField = field;
}

NSString *hash(id obj) 
{
    return [NSString stringWithFormat:@"%lx", (long)obj];
}

NSDictionary *getDefaultAttrs()
{
    if (defaultAttrs == nil) {
        return [NSDictionary dictionary];
    }
    return defaultAttrs;
}

XLog_Console *getConsole(NSTextStorage *textStorage)
{
    XLog_Console *console = [consoleTextStorageMap objectForKey:hash(textStorage)];
    // MXLog(@"getConsole: %@, %@", key, console);
    return console;
}

NSColor* string2color(NSString *str)
{
    // is valid color format: [000000, ffffff]
    if ([str length] != LENGTH_COLOR) {
        return nil;
    }
    for (int i = 0; i != [str length]; ++i) {
        char ch = [str characterAtIndex:i];
        if (!(('0' <= ch && ch <= '9') || ('a' <= ch && ch <= 'f') || ('A' <= ch && ch <= 'F'))) {
            return nil;
        }
    }
    unsigned r, g, b;
    NSScanner *scanner = [NSScanner scannerWithString:[str substringWithRange:NSMakeRange(0, 2)]];  // scan red value
    [scanner scanHexInt:&r];
    scanner = [NSScanner scannerWithString:[str substringWithRange:NSMakeRange(2, 2)]]; // green value
    [scanner scanHexInt:&g];
    scanner = [NSScanner scannerWithString:[str substringWithRange:NSMakeRange(4, 2)]]; // blue value
    [scanner scanHexInt:&b];
    CGFloat radio = 255.0f;
    return [NSColor colorWithDeviceRed:r / radio green: g / radio blue:b / radio alpha:1.0f];
}

BOOL findColorPatten(NSString *string, NSRange range, NSRangePointer resultRange, NSString **colorStr)
{
    NSRange r = [string rangeOfString:XLOG_COLOR_PREX options:0 range:range];
    if (r.length == 0) return NO;   // not find
    int colorTotalLen = LENGTH_COLOR_PREX + LENGTH_COLOR;
    if (r.location + colorTotalLen > [string length]) return NO;  // end of str, not color
    *colorStr = [string substringWithRange:NSMakeRange(r.location + LENGTH_COLOR_PREX, LENGTH_COLOR)];
    if ([*colorStr isEqualToString:XLOG_COLOR_RESET] || string2color(*colorStr) != nil) {
        resultRange->location = r.location;
        resultRange->length = colorTotalLen;
        return YES;
    } else {    // invalid color format, find next
        return findColorPatten(string, NSMakeRange(r.location + colorTotalLen, [string length] - r.location - colorTotalLen), resultRange, colorStr);
    }
}

void hideLogTags(NSTextStorage *textStorage, NSRange range)
{
    NSError *error;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\033\\[/?(" 
                                  XLOG_LEVEL_DEBUG @"|" 
                                  XLOG_LEVEL_INFO @"|"
                                  XLOG_LEVEL_WARN @"|"
                                  XLOG_LEVEL_ERROR
                                  @")\\]" options:0 error:&error];
    NSArray *matches = [regex matchesInString:[textStorage string] options:0 range:range];
    
    for (NSTextCheckingResult *match in matches) {
        [textStorage addAttributes:hiddenAttrs range:match.range];
    }
}

void applyColor(NSTextStorage *textStorage, NSRange range)
{
    NSString *affectString = [[textStorage string] substringWithRange:range];
    NSUInteger len = [affectString length];
    
    // ^#ffffff(start range).....(text need apply color)^#ffffff(next range)...
    NSRange startRange, nextRange;
    startRange = nextRange = NSMakeRange(0, 0);
    NSString *startColorStr = @"";
    NSString *nextColorStr = @"";
    
    if (!findColorPatten(affectString, NSMakeRange(0, [affectString length]), &startRange, &startColorStr)) {
        // there is no color patten
        return;
    }
    
    while (startRange.location < len) {
        if (!findColorPatten(affectString, NSMakeRange(startRange.location + startRange.length, len - startRange.location - startRange.length), &nextRange, &nextColorStr)) {
            // cannot find color patten anymore, use end as nextRange
            nextRange.location = len;
        }
        //-- set color attr
        // 1. hide color patten
        [textStorage addAttributes:hiddenAttrs range:NSMakeRange(startRange.location + range.location, LENGTH_COLOR_PREX + LENGTH_COLOR)];
        
        // 2. set text color
        NSRange r = NSMakeRange(range.location + startRange.location + startRange.length, nextRange.location - startRange.location - startRange.length);
        // NSString *str = [[textStorage string] substringWithRange:r];
        if ([startColorStr isEqualToString:XLOG_COLOR_RESET]) {  // reset color
            // MXLog(@"reset color for text[%@]", str);
            [textStorage addAttributes:getDefaultAttrs() range:r];
        } else {    // set customized color
            NSColor *color = string2color(startColorStr);
            // MXLog(@"set color[%@] for text[%@]", color, str);
            [textStorage addAttributes:[NSDictionary dictionaryWithObject:color forKey:NSForegroundColorAttributeName] range:r];
        }
        startRange = nextRange;
        startColorStr = nextColorStr;
    }
}

void applyRegexFilter(NSTextStorage *textStorage, NSRange range)
{
    // use new value each time
    XLog_Console *console = getConsole(textStorage);
    NSString *regexString = [console.searchField stringValue];
    if (regexString.length == 0) return ;
    NSError *error;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexString options:(NSRegularExpressionCaseInsensitive|NSRegularExpressionDotMatchesLineSeparators) error:&error];
    if (regex == nil) { // invalid regex string
        // display in console
        NSString *errorInfo = [NSString stringWithFormat:@"Invalid regex, error: %@", error];
        // WTF: realTextStorage and DVTFoldingTextStorage's string is not the same, cause re fix, recurrence forever.
        console.lastStrlen = [console.realTextStorage length] + [errorInfo length];  
        [console.realTextStorage replaceCharactersInRange:NSMakeRange([console.realTextStorage length], 0) withString:errorInfo];
        return;
    }
    
    NSArray *matches = [regex matchesInString:[textStorage string] options:0 range:range];
    long loc = range.location;
    for (NSTextCheckingResult *match in matches) {
        NSRange r = NSMakeRange(loc, match.range.location - loc);
        [textStorage addAttributes:hiddenAttrs range:r];
        // next loc
        loc = match.range.location + match.range.length;
    }
    // hide loc to end
    NSRange r = NSMakeRange(loc, range.location + range.length - loc);
    [textStorage addAttributes:hiddenAttrs range:r];
}

void applyLogLevel(NSTextStorage *textStorage, NSRange range, NSString *tag)
{
    NSString *affectString = [[textStorage string] substringWithRange:range];
    
    NSString *startDelimiter = [NSString stringWithFormat:ESC_CH @"[%@]", tag];
    NSString *endDelimiter = [NSString stringWithFormat:ESC_CH @"[/%@]", tag];
    
    // hidden string(...) between (start)...^[D]***^[/D]...^[D]***^[/D]...(end)
    NSRange startRange = NSMakeRange(0, 1);
    NSRange nextRange = [affectString rangeOfString:startDelimiter];
    unsigned long len = [affectString length];
    // hide head
    while (nextRange.length > 0) {
        NSRange r = NSMakeRange(range.location + startRange.location, nextRange.location - startRange.location + nextRange.length);
        [textStorage addAttributes:hiddenAttrs range:r];
        
        // find next one
        NSRange tmpR = NSMakeRange(nextRange.location + nextRange.length, len - nextRange.location - nextRange.length);
        // MXLog(@"find end tag string in %@", [affectString substringWithRange:tmpR]);
        startRange = [affectString rangeOfString:endDelimiter options:0 range:tmpR];
        if (startRange.length == 0l) break;
        nextRange = [affectString rangeOfString:startDelimiter options:0 range:NSMakeRange(startRange.location + startRange.length, len - startRange.location - startRange.length)];
    }
    // hide tail
    NSRange r = NSMakeRange(range.location + startRange.location, len - startRange.location);
    [textStorage addAttributes:hiddenAttrs range:r];
}

void parse(XLog_Console *console, NSRange range)
{
    if (console == nil) return;
    NSTextStorage *textStorage = console.realTextStorage;
    // ROBUST: check if range is valid
    unsigned long len = [textStorage length];
    if (range.location >= len || range.location + range.length > len) {
        return ;
    }
    
    // set color
    applyColor(textStorage, range);
    // hide DEBUG/INFO .. tags
    hideLogTags(textStorage, range);
    // apply regex filter
    applyRegexFilter(textStorage, range);
    
    switch (console.lastLogLevel) {
        case 0: // all
            return;
            break;
        case 1: // debug
            applyLogLevel(textStorage, range, XLOG_LEVEL_DEBUG);
            break;
        case 2:
            applyLogLevel(textStorage, range, XLOG_LEVEL_INFO);
            break;
        case 3:
            applyLogLevel(textStorage, range, XLOG_LEVEL_WARN);
            break;
        case 4:
            applyLogLevel(textStorage, range, XLOG_LEVEL_ERROR);
            break;
    }

}

void reset(NSTextStorage *textStorage)
{
    NSRange range = NSMakeRange(0, [textStorage length]);
    [textStorage addAttributes:getDefaultAttrs() range:range];
}

// rewrite log to file
void write2log(NSString *str)
{
    NSLog(@"%@", str);

    if (logfp == 0) {
        return ;
    }
    
    long size = ftell(logfp);
    if (size > MAX_LOG_SIZE) {  // write log from beginning
        fseek(logfp, 0, SEEK_SET);
    }

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    //[dateFormatter setDateFormat:@"hh:mm:ss"]
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timeString = [dateFormatter stringFromDate:[NSDate date]];
    [dateFormatter release];

    fprintf(logfp, "%s %s\n", [timeString UTF8String], [str UTF8String]);

}

