//
//  EventSource.m
//  EventSource
//
//  Created by Neil on 25/07/2013.
//  Copyright (c) 2013 Neil Cowburn. All rights reserved.
//

#import "EventSource.h"
#import <CoreGraphics/CGBase.h>

static CGFloat const ES_RETRY_INTERVAL = 1.0;
static CGFloat const ES_DEFAULT_TIMEOUT = 300.0;

static NSString *const ESKeyValueDelimiter = @":";
static NSString *const ESEventSeparatorLFLF = @"\n\n";
static NSString *const ESEventSeparatorCRCR = @"\r\r";
static NSString *const ESEventSeparatorCRLFCRLF = @"\r\n\r\n";
static NSString *const ESEventKeyValuePairSeparator = @"\n";

static NSString *const ESEventDataKey = @"data";
static NSString *const ESEventIDKey = @"id";
static NSString *const ESEventEventKey = @"event";
static NSString *const ESEventRetryKey = @"retry";

@interface EventSource () <NSURLSessionDataDelegate> {
    BOOL wasClosed;
    dispatch_queue_t messageQueue;
    dispatch_queue_t connectionQueue;
}

@property (nonatomic, strong) EventSourceConfig *config;

@property (nonatomic, strong) NSURLSession *eventSourceSession;
@property (nonatomic, strong) NSURLSessionDataTask *eventSourceTask;
@property (nonatomic, strong) NSMutableDictionary *listeners;
@property (nonatomic, strong) id lastEventID;

- (void)_open;

@end

@interface EventSourceConfig ()

@property (nonatomic, assign) NSUInteger currentRetryCount;

@end

@implementation EventSource

+ (instancetype)eventSourceWithConfig:(EventSourceConfig *)config {
    return [[EventSource alloc] initWithConfig:config];
}

- (instancetype)initWithConfig:(EventSourceConfig *)config {
    self = [super init];
    if (self) {
        _config = config;
        _listeners = [NSMutableDictionary dictionary];

        messageQueue = dispatch_queue_create("co.cwbrn.eventsource-queue", DISPATCH_QUEUE_SERIAL);
        connectionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(config.retryInterval * NSEC_PER_SEC));
        dispatch_after(popTime, connectionQueue, ^(void){
            [self _open];
        });
    }
    return self;
}

- (void)addEventListener:(NSString *)eventName handler:(EventSourceEventHandler)handler
{
    if (self.listeners[eventName] == nil) {
        [self.listeners setObject:[NSMutableArray array] forKey:eventName];
    }
    
    [self.listeners[eventName] addObject:handler];
}

- (void)onMessage:(EventSourceEventHandler)handler
{
    [self addEventListener:MessageEvent handler:handler];
}

- (void)onError:(EventSourceEventHandler)handler
{
    [self addEventListener:ErrorEvent handler:handler];
}

- (void)onOpen:(EventSourceEventHandler)handler
{
    [self addEventListener:OpenEvent handler:handler];
}

- (void)onClose:(EventSourceEventHandler)handler
{
    [self addEventListener:CloseEvent handler:handler];
}

- (void)onReadyStateChanged:(EventSourceEventHandler)handler
{
    [self addEventListener:ReadyStateEvent handler:handler];
}

- (void)close
{
    wasClosed = YES;
    [self.eventSourceTask cancel];
    self.eventSourceTask = nil;
    [self.eventSourceSession invalidateAndCancel];
    self.eventSourceSession = nil;
}

// -----------------------------------------------------------------------------------------------------------------------------------------

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    if (httpResponse.statusCode == 200) {
        // Opened
        EventSourceEvent *e = [[EventSourceEvent alloc] init];
        e.readyState = kEventStateOpen;

        [self _dispatchEvent:e type:ReadyStateEvent];
        [self _dispatchEvent:e type:OpenEvent];
    }

    if (completionHandler) {
        completionHandler(NSURLSessionResponseAllow);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    NSString *eventString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSArray *lines = [eventString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    EventSourceEvent *event = [[EventSourceEvent alloc] init];
    event.readyState = kEventStateOpen;

    for (NSString *line in lines) {
        if ([line hasPrefix:ESKeyValueDelimiter]) {
            continue;
        }

        if (!line || line.length == 0) {
            if (event.data.length > 0) {
                [self _dispatchEvent:event type:MessageEvent];
                if (event.event.length > 0) {
                    [self _dispatchEvent:event type:event.event];
                }

                event = [[EventSourceEvent alloc] init];
                event.readyState = kEventStateOpen;
            }
            continue;
        }

        @autoreleasepool {
            NSScanner *scanner = [NSScanner scannerWithString:line];
            scanner.charactersToBeSkipped = [NSCharacterSet whitespaceCharacterSet];

            NSString *key, *value;
            [scanner scanUpToString:ESKeyValueDelimiter intoString:&key];
            [scanner scanString:ESKeyValueDelimiter intoString:nil];
            [scanner scanUpToCharactersFromSet:[NSCharacterSet newlineCharacterSet] intoString:&value];

            if (key && value) {
                if ([key isEqualToString:ESEventEventKey]) {
                    event.event = value;
                } else if ([key isEqualToString:ESEventDataKey]) {
                    if (event.data != nil) {
                        event.data = [event.data stringByAppendingFormat:@"\n%@", value];
                    } else {
                        event.data = value;
                    }
                } else if ([key isEqualToString:ESEventIDKey]) {
                    event.id = value;
                    self.lastEventID = event.id;
                } else if ([key isEqualToString:ESEventRetryKey]) {
                    self.config.retryInterval = [value doubleValue];
                }
            }
        }
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error
{
    self.eventSourceTask = nil;

    if (wasClosed) {
        return;
    }
    
    if (!error) {
        EventSourceEvent *e = [[EventSourceEvent alloc] init];
        e.readyState = kEventStateClosed;
        [self _dispatchEvent:e type:ReadyStateEvent];
        [self _dispatchEvent:e type:CloseEvent];
        return;
    }
    
    EventSourceEvent *e = [[EventSourceEvent alloc] init];
    e.readyState = kEventStateClosed;
    e.error = error;
    
    [self _dispatchEvent:e type:ErrorEvent];
    [self _dispatchEvent:e type:ReadyStateEvent];
    [self _dispatchEvent:e type:CloseEvent];

    if (self.config.currentRetryCount < self.config.retryCount) {
        self.config.currentRetryCount++;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.config.retryInterval * NSEC_PER_SEC));
        dispatch_after(popTime, connectionQueue, ^(void){
            [self _open];
        });
    }
}

// -------------------------------------------------------------------------------------------------------------------------------------

- (void)_open
{
    wasClosed = NO;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.config.url
                                                           cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                       timeoutInterval:self.config.timeoutInterval];
    request.HTTPMethod = self.config.method ?: @"GET";
    request.HTTPBody = self.config.body;
    for (NSString *key in self.config.headers) {
        [request setValue:self.config.headers[key] forHTTPHeaderField:key];
    }

    if (self.lastEventID) {
        [request setValue:self.lastEventID forHTTPHeaderField:@"Last-Event-ID"];
    }

    if (self.eventSourceTask) {
        [self.eventSourceTask cancel];
        self.eventSourceTask = nil;
    }
    if (self.eventSourceSession) {
        [self.eventSourceSession invalidateAndCancel];
        self.eventSourceSession = nil;
    }
    self.eventSourceSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                            delegate:self
                                                       delegateQueue:[NSOperationQueue currentQueue]];
    self.eventSourceTask = [self.eventSourceSession dataTaskWithRequest:request];
    [self.eventSourceTask resume];

    EventSourceEvent *e = [[EventSourceEvent alloc] init];
    e.readyState = kEventStateConnecting;

    [self _dispatchEvent:e type:ReadyStateEvent];

    if (![NSThread isMainThread]) {
        CFRunLoopRun();
    }
}

- (void)_dispatchEvent:(EventSourceEvent *)event type:(NSString * const)type
{
    NSArray *handlers = self.listeners[type];
    for (EventSourceEventHandler handler in handlers) {
        dispatch_async(messageQueue, ^{
            handler(event);
        });
    }
}

@end

// ---------------------------------------------------------------------------------------------------------------------

@implementation EventSourceEvent

- (NSString *)description
{
    NSString *state = nil;
    switch (self.readyState) {
        case kEventStateConnecting:
            state = @"CONNECTING";
            break;
        case kEventStateOpen:
            state = @"OPEN";
            break;
        case kEventStateClosed:
            state = @"CLOSED";
            break;
    }
    
    return [NSString stringWithFormat:@"<%@: readyState: %@, id: %@; event: %@; data: %@>",
            [self class],
            state,
            self.id,
            self.event,
            self.data];
}

@end

// ---------------------------------------------------------------------------------------------------------------------

@implementation EventSourceConfig

- (instancetype)init
{
    self = [super init];
    if (self) {
        _method = @"GET";
        _timeoutInterval = ES_DEFAULT_TIMEOUT;
        _retryInterval = ES_RETRY_INTERVAL;
        _retryCount = 0;
        _currentRetryCount = 0;
    }
    return self;
}

@end

NSString *const MessageEvent = @"message";
NSString *const ErrorEvent = @"error";
NSString *const OpenEvent = @"open";
NSString *const CloseEvent = @"close";
NSString *const ReadyStateEvent = @"readyState";
