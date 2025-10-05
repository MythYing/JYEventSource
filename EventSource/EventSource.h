//
//  EventSource.h
//  EventSource
//
//  Created by Neil on 25/07/2013.
//  Copyright (c) 2013 Neil Cowburn. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    kEventStateConnecting = 0,
    kEventStateOpen = 1,
    kEventStateClosed = 2,
} EventState;

// ---------------------------------------------------------------------------------------------------------------------

/// Describes an Event received from an EventSource
@interface EventSourceEvent : NSObject

/// The Event ID
@property (nonatomic, strong, nullable) NSString *id;
/// The name of the Event
@property (nonatomic, strong, nullable) NSString *event;
/// The data received from the EventSource
@property (nonatomic, strong, nullable) NSString *data;

/// The current state of the connection to the EventSource
@property (nonatomic, assign) EventState readyState;
/// Provides details of any errors with the connection to the EventSource
@property (nonatomic, strong, nullable) NSError *error;

@end

// ---------------------------------------------------------------------------------------------------------------------

/// Configuration options for the EventSource
@interface EventSourceConfig : NSObject

/// The request url.
@property (nonatomic, strong, nonnull) NSURL *url;
/// The request HTTP method.  Default: GET.
@property (nonatomic, strong, nonnull) NSString *method;
/// The request body.  Default: nil.
@property (nonatomic, strong, nullable) NSData *body;
/// The request headers.  Default: nil.
@property (nonatomic, strong, nullable) NSDictionary<NSString *, NSString *> *headers;
/// The request timeout interval in seconds.  Default: 300 seconds.
@property (nonatomic, assign) NSTimeInterval timeoutInterval;
/// The request retry interval in seconds.  Default: 1 seconds.
@property (nonatomic, assign) NSTimeInterval retryInterval;

@end

// ---------------------------------------------------------------------------------------------------------------------

typedef void (^EventSourceEventHandler)(EventSourceEvent *_Nonnull event);

// ---------------------------------------------------------------------------------------------------------------------

/// Connect to and receive Server-Sent Events (SSEs).
@interface EventSource : NSObject

/// Unavailable. Use `initWithConfig:` instead.
- (instancetype _Nonnull)init NS_UNAVAILABLE;

/// Creates a new instance of EventSource with the specified Config.
///
/// @param config The config of the EventSource.
- (instancetype _Nonnull)initWithConfig:(EventSourceConfig *_Nonnull)config NS_DESIGNATED_INITIALIZER;

/// Registers an event handler for the Message event.
///
/// @param handler The handler for the Message event.
- (void)onMessage:(EventSourceEventHandler _Nonnull)handler;

/// Registers an event handler for the Error event.
///
/// @param handler The handler for the Error event.
- (void)onError:(EventSourceEventHandler _Nonnull)handler;

/// Registers an event handler for the Open event.
///
/// @param handler The handler for the Open event.
- (void)onOpen:(EventSourceEventHandler _Nonnull)handler;

- (void)onReadyStateChanged:(EventSourceEventHandler _Nonnull)handler;

/// Registers an event handler for a named event.
///
/// @param eventName The name of the event you registered.
/// @param handler The handler for the Message event.
- (void)addEventListener:(NSString *_Nonnull)eventName handler:(EventSourceEventHandler _Nonnull)handler;

/// Closes the connection to the EventSource.
- (void)close;

@end

// ---------------------------------------------------------------------------------------------------------------------

extern NSString * _Nonnull const MessageEvent;
extern NSString * _Nonnull const ErrorEvent;
extern NSString * _Nonnull const OpenEvent;
extern NSString * _Nonnull const ReadyStateEvent;
