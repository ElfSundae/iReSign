

#import "ATVDeviceController.h"
#import <sys/types.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import "iReSignAppDelegate.h"

#define APP_DELEGATE (iReSignAppDelegate *)[[NSApplication sharedApplication] delegate]

@implementation ATVDeviceController


@synthesize deviceController, theComboBox, delegate;

- (NSString *)input: (NSString *)prompt defaultValue: (NSString *)defaultValue {
    NSAlert *alert = [NSAlert alertWithMessageText: prompt
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@""];
    
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    [input setStringValue:defaultValue];
    [alert setAccessoryView:input];
    NSInteger button = [alert runModal];
    if (button == NSAlertDefaultReturn) {
        [input validateEditing];
        NSString *inputString = [input stringValue];

        return inputString;
    } else if (button == NSAlertAlternateReturn) {

        return nil;
    } else {
        
        NSAssert1(NO, @"Invalid input dialog button %d", button);
        //[input autorelease];
        return nil;
    }
}

- (IBAction)menuItemSelected:(id)sender
{
    if (sender == nil)
    {
        return;
    }
    
    int index = [sender indexOfSelectedItem];
    
    int itemCount = [sender numberOfItems];
    
    if (index == 0)
    {
        [APP_DELEGATE setAtvAvailable:FALSE];
        [APP_DELEGATE resetServerSettings];
        return;
    }
    
    if (index == itemCount-1)
    {
        //[sender setEditable:TRUE];
        
        NSString *output = [self input:@"Enter an Apple TV name or IP address" defaultValue:@""];
        [APP_DELEGATE setAtvAvailable:TRUE];
        [DEFAULTS setObject:output forKey:@"appleTVHost"];
        return;
        
    } else {
        
        //	[sender setEditable:FALSE];
    }
    
    
    NSNetService * clickedService = [services objectAtIndex:index];
    
    
    NSDictionary *finalDict = [self stringDictionaryFromService:clickedService];
    
    if ([[finalDict allKeys] count] > 0)
    {
        
        NSString *model = [finalDict objectForKey:@"model"];
        if ([model isEqualToString:@"AppleTV3,1"])
        {
            [sender selectItemAtIndex:0];
            [APP_DELEGATE setAtvAvailable:FALSE];
            [APP_DELEGATE showATVWarning];
            return;
        }
  
        
    } else {
        
        
        return;
    }
    
    
    
    NSString *ip;
    //int port;
    struct sockaddr_in *addr;
    
    addr = (struct sockaddr_in *) [[[clickedService addresses] objectAtIndex:0]
                                   bytes];
    ip = [NSString stringWithUTF8String:(char *) inet_ntoa(addr->sin_addr)];

    NSString *fullIP = [NSString stringWithFormat:@"%@:%i", ip, 22];

    [APP_DELEGATE setAtvAvailable:TRUE];
    [DEFAULTS setObject:fullIP forKey:ATV_HOST];
    
    NSLog(@"ATVADDRESS: %@", APPLE_TV_ADDRESS);
    
    //hacky check here to see if its jailbroken
    BOOL jailbroken = [APP_DELEGATE isJailbroken];
    if (jailbroken == FALSE)
    {
        [APP_DELEGATE showNotJailbrokenWarning];
        [DEFAULTS removeObjectForKey:ATV_HOST];
        [DEFAULTS removeObjectForKey:@"selectedValue"];
    }
}

- (NSString *)convertedName:(NSString *)inputName
{
	
	
    NSMutableString	*fixedNetLabel = [NSMutableString stringWithString:[inputName stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@".#,<>/?\'\\\[]{}+=-~`\";:"]]];
	//NSLog(@"fixedNetLabel: %@", fixedNetLabel);
    [fixedNetLabel replaceOccurrencesOfString:@" " withString:@"-" options:0 range:NSMakeRange(0, [fixedNetLabel length])];
	//int nameLength = [fixedNetLabel length];
	//fixedNetLabel = [fixedNetLabel substringToIndex:(nameLength-1)];
    return [NSString stringWithString:fixedNetLabel];
}

- (NSString *)fixedName:(NSString *)inputName
{
	NSInteger nameLength = [inputName length];
	NSString *newName = [inputName substringToIndex:(nameLength-1)];
	return newName;
}



- (NSDictionary *)stringDictionaryFromService:(NSNetService *)theService
{
	NSData *txtRecordDict = [theService TXTRecordData];
	
	NSDictionary *theDict = [NSNetService dictionaryFromTXTRecordData:txtRecordDict];
	NSMutableDictionary *finalDict = [[NSMutableDictionary alloc] init];
	NSArray *keys = [theDict allKeys];
	for (NSString *theKey in keys)
	{
		NSString *currentString = [[NSString alloc] initWithData:[theDict valueForKey:theKey] encoding:NSUTF8StringEncoding];
		[finalDict setObject:currentString forKey:theKey];
	}
    NSString *ip;
    int port;
    struct sockaddr_in *addr;
    if ([[theService addresses] count] == 0)
    {
        NSLog(@"no addresses resolved!?!?");
        return nil;
    }
    addr = (struct sockaddr_in *) [[[theService addresses] objectAtIndex:0]
                                   bytes];
    ip = [NSString stringWithUTF8String:(char *) inet_ntoa(addr->sin_addr)];
    port = ntohs(((struct sockaddr_in *)addr)->sin_port);
    //NSLog(@"ipaddress: %@", ip);
    //NSLog(@"port: %i", port);
    
    NSString *fullIP = [NSString stringWithFormat:@"%@:%i", ip, port];
    finalDict[@"fullIP"] = fullIP;
    finalDict[@"hostname"] = theService.hostName;
	return finalDict;
}






- (id)init {
	
    browser = [[NSNetServiceBrowser alloc] init];
    services = [NSMutableArray array];
    [browser setDelegate:self];
    //NSLog(@"awake from nib");
    // Passing in "" for the domain causes us to browse in the default browse domain

    
   [browser searchForServicesOfType:@"_airplay._tcp." inDomain:@""];
	// [hostNameField setStringValue:@""];
	self = [super init];
    

	NSDictionary *catv = [NSDictionary dictionaryWithObject:@"Choose Apple TV" forKey:@"name"];
	NSDictionary *theDict = [NSDictionary dictionaryWithObject:@"Other..." forKey:@"name"];
	[services addObject:catv];
	[services addObject:theDict];

	return self;
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)browser

{
	//NSLog(@"%@ %s", self, _cmd);
    searching = NO;
	//[_parentObject endServices:services];
    [self updateUI];
	
}

- (void)updateUI

{
	//NSLog(@"%@ %s", self, _cmd);
    if(searching)
		
    {
		
        // Update the user interface to indicate searching
		
        // Also update any UI that lists available services
		
    }
	
    else
		
    {
		
		NSLog(@"services: %@", services);
        // Update the user interface to indicate not searching
		
    }
	
}

- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)browser

{

	//NSLog(@"%@ %s", self, _cmd);
    searching = YES;
	
    [self updateUI];
	
}

// Error handling code

- (void)handleError:(NSNumber *)error

{
	
    NSLog(@"An error occurred. Error code = %d", [error intValue]);
	
    // Handle error here
	
}


- (BOOL)searching {
    return searching;
}


// This object is the delegate of its NSNetServiceBrowser object. We're only interested in services-related methods, so that's what we'll call.
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
	
    NSInteger servicesCount = [services count]-1;
    
    [services insertObject:aNetService atIndex:servicesCount];

    [aNetService setDelegate:self];
    [aNetService resolveWithTimeout:5.0];
    
    if(!moreComing) {
 		

		[deviceController setContent:services];

		 
	}
}

#if TARGET_OS_OSX

- (NSString *)input: (NSString *)prompt defaultValue: (NSString *)defaultValue {
	NSAlert *alert = [NSAlert alertWithMessageText: prompt
									 defaultButton:@"OK"
								   alternateButton:@"Cancel"
									   otherButton:nil
						 informativeTextWithFormat:@""];
	
	NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
	[input setStringValue:defaultValue];

	[alert setAccessoryView:input];
	NSInteger button = [alert runModal];
	if (button == NSAlertDefaultReturn) {
		[input validateEditing];
		NSString *inputString = [input stringValue];

		return inputString;
	} else if (button == NSAlertAlternateReturn) {
		return nil;
	} else {
		
		NSAssert1(NO, @"Invalid input dialog button %d", button);
		return nil;
	}
}
#endif

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
    [services removeObject:aNetService];
    
    if(!moreComing) {
	
	}
}

- (NSDictionary *)deviceDictionary {
    return deviceDictionary;
}

- (void)setDeviceDictionary:(NSDictionary *)value {
    if (deviceDictionary != value) {
    
        deviceDictionary = [value copy];
    }
}

//resolution stuff


- (BOOL)addressesComplete:(NSArray *)addresses

		   forServiceType:(NSString *)serviceType

{
    // Perform appropriate logic to ensure that [netService addresses]
	
    if ([self.delegate respondsToSelector:@selector(servicesFound:)])
    {
        NSMutableArray *fullServices = [NSMutableArray new];
        for (NSNetService *service in services)
        {
            NSDictionary *fullDict = [self stringDictionaryFromService:service];
            if (fullDict != nil)
                [fullServices addObject:fullDict];
        }
        
          [self.delegate servicesFound:fullServices];
    }
    
	
    return YES;
	
}

// Sent when addresses are resolved

- (void)netServiceDidResolveAddress:(NSNetService *)aNetService

{
    NSDictionary *finalDict = [self stringDictionaryFromService:aNetService];
    if ([[finalDict allKeys] count] > 0)
    {
        
        NSString *model = [finalDict objectForKey:@"model"];
        if ([model isEqualToString:@"AppleTV5,3"])
        {
            //NSLog(@"should add service: %@", aNetService);
           // NSInteger servicesCount = [services count]-1;
            
            //[services insertObject:aNetService atIndex:servicesCount];
            
        } else {
            [services removeObject:aNetService];
            
            [deviceController setContent:services];
        }
    }
	/*
    if ([self addressesComplete:[netService addresses]
		 
				 forServiceType:[netService type]]) {
		
		
    }
	*/
}



// Sent if resolution fails

- (void)netService:(NSNetService *)netService

	 didNotResolve:(NSDictionary *)errorDict

{
	//NSLog(@"%@ %s", self, _cmd);
    [self handleError:[errorDict objectForKey:NSNetServicesErrorCode]];
	
    [services removeObject:netService];
	
}

#if TARGET_OS_OSX

// This object is the data source of its NSTableView. servicesList is the NSArray containing all those services that have been discovered.
- (int)numberOfRowsInTableView:(NSTableView *)theTableView {
    return [services count];
}

- (NSDictionary *)currentServiceDictionary {
    NSNetService * clickedService = [services objectAtIndex:[[self theComboBox] indexOfSelectedItem]];
    
    //NSLog(@"clickedService: %@" ,[self theComboBox]);
    
    return [self stringDictionaryFromService:clickedService];
}


- (id)tableView:(NSTableView *)theTableView objectValueForTableColumn:(NSTableColumn *)theColumn row:(int)rowIndex {
   NSString *fixedName = [[[[services objectAtIndex:rowIndex] name] componentsSeparatedByString:@"@"] lastObject];
	return fixedName;
	// return [[services objectAtIndex:rowIndex] name];
}

#endif

@end
