//
//  XLog.h
//  XLog
//
//  Created by WenDong Zhang on 5/8/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

/****************************************************
 *                                                  *
 *              Plugin principal class              *
 *                                                  *
 ****************************************************/
@interface XLog : NSObject

// entry for plugin
+ (void)load;
+ (void)pluginDidLoad:(NSBundle *)bundle;

// handle log level change event
- (void)onLogLevelButtonClick:(id)sender;

// use filter by regex
- (void)onFilterButtonClick:(id)sender;

/*
 * it seems when TextStorage changed, the textview won't
 * relayout programmly, cause text overlay. 
 */
- (void)fixTextViewLayout:(NSTextView *)textView;
@end


/****************************************************
 *                                                  *
 * Customized TextStrage, used for hook system's    *
 * NSTextStorage.                                   *
 *                                                  *
 ****************************************************/
@interface XLog_TextStorage : NSTextStorage
// used to replace NSTextStorage's method
- (void)fixAttributesInRange:(NSRange)range;
@end

/****************************************************
 *                                                  *
 * There are more than one console, when user open  *
 * multiple projects. Each one should save some     *
 * status.                                          *
 *                                                  *
 ****************************************************/
@interface XLog_Console : NSObject
{
    NSTextStorage *realTextStorage;
    NSTextView *textView;
    NSSearchField *searchField;
    NSString *lastSearchText;
    NSUInteger lastLogLevel;

    /*
     * Two purpose for lastStrlen:
     *  1. bugfix: fixAttributesInRange will be invoked multi times (I don't why). 
     *      when we fix multi lines, it will call fixAttr... for each line additionally.
     *  2. optimize, only call fixAttr... when the text changes 
            (ho, bug: text changes may not change the length, but I don't care this...)
     */

    NSUInteger lastStrlen;
}
@property (nonatomic, assign) NSTextStorage *realTextStorage;   // need not retain, when the console destory, we won't use those member anymore.
@property (nonatomic, assign) NSTextField *searchField;
@property (nonatomic, assign) NSTextView *textView;
@property (nonatomic, retain) NSString *lastSearchText;
@property (nonatomic, assign) NSUInteger lastLogLevel;
@property (nonatomic, assign) NSUInteger lastStrlen;
@end

/****************************************************
 *                                                  *
 *                     Functions                    *
 *                                                  *
 ****************************************************/

void replaceFixAttributesInRangeMethod(); // replace system's default method
BOOL testTextStorage(NSAttributedString *textStorage);  // test if current textStorage is console textStorage.
void addCustomizedViews(NSPopUpButton *anchorBtn, XLog_Console *console, NSTextStorage *key);  // add log level, regex filter views to the toolbar
NSString *hash(id obj); // used to hash DVTFolding|DVT TextStorage. [DVTFoldingTextStroage hash] == [DVTTextStorage hash]

/** functions for manipulate textStorage **/
NSDictionary *getDefaultAttrs();    // the console's default text apperence
XLog_Console *getConsole(NSTextStorage *textStorage);   // get console from consoleMap by textStrage id
NSColor* string2color(NSString *str);   // parse FF00FF to NSColor
BOOL findColorPatten(NSString *string, NSRange range, NSRangePointer resultRange, NSString **colorStr); // find \033#FF00FF in the str. return NO if not find. pass result range and colorStr by pointer when find
void hideLogTags(NSTextStorage *textStorage, NSRange range);    // hide the log tags: \033[DEBUG], \033[/DEBUG], INFO.. and so on

void applyColor(NSTextStorage *textStorage, NSRange range); // apply color attribute
void applyRegexFilter(NSTextStorage *textStorage, NSRange range);   // apply regex filter. only show the text which match the regex string.
void applyLogLevel(NSTextStorage *textStorage, NSRange range, NSString *tag);   // only show the text match the log level (by log tag [DEBUG|INFO|WARN|ERROR])
void parse(XLog_Console *console, NSRange range);  // entry to do apply color, regex filter and log level.
void reset(NSTextStorage *textStorage);   // clear all the filters, reset the textStorage to default. Sorry, this method also reset DGB color, font 

// log util
void write2log(NSString *str);