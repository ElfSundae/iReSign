//
//  Defines.h
//  iReSign
//
//  Created by Kevin Bradley on 5/19/16.
//  Copyright © 2016 nil. All rights reserved.
//

#ifndef Defines_h
#define Defines_h

#define DLog(format, ...) CFShow((__bridge CFStringRef)[NSString stringWithFormat:format, ## __VA_ARGS__]);
#define LOG_SELF        NSLog(@"%@ %@", self, NSStringFromSelector(_cmd))
#define DLOG_SELF DLog(@"%@ %@", self, NSStringFromSelector(_cmd))

#define DEFAULTS [NSUserDefaults standardUserDefaults]
#define ATV_HOST @"appleTVHost"
#define ATV_API  @"atvAPIVersion"
#define ATV_OS	 @"atvOSVersion"
#define ATV4Install @"atv4Install"
#define APPLE_TV_ADDRESS [DEFAULTS stringForKey:ATV_HOST]
#define INSTALL_ON_ATV [DEFAULTS boolForKey:ATV4Install]
#define APPLE_TV_API [DEFAULTS stringForKey:ATV_API]
#define APPLE_TV_OS [DEFAULTS stringForKey:ATV_OS]
#define SELECTED_VALUE [DEFAULTS stringForKey:@"selectedValue"]

#endif /* Defines_h */
