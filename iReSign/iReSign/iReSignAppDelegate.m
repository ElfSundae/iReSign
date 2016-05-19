//
//  iReSignAppDelegate.m
//  iReSign
//
//  Created by Maciej Swic on 2011-05-16.
//  Copyright (c) 2011 Maciej Swic, Licensed under the MIT License.
//  See README.md for details
//

#import "iReSignAppDelegate.h"
#import "ATVDeviceController.h"

static NSString *kKeyPrefsBundleIDChange            = @"keyBundleIDChange";

static NSString *kKeyBundleIDPlistApp               = @"CFBundleIdentifier";
static NSString *kKeyBundleIDPlistiTunesArtwork     = @"softwareVersionBundleId";
static NSString *kKeyInfoPlistApplicationProperties = @"ApplicationProperties";
static NSString *kKeyInfoPlistApplicationPath       = @"ApplicationPath";
static NSString *kFrameworksDirName                 = @"Frameworks";
static NSString *kPluginsDirName                    = @"PlugIns";
static NSString *kPayloadDirName                    = @"Payload";
static NSString *kProductsDirName                   = @"Products";
static NSString *kInfoPlistFilename                 = @"Info.plist";
static NSString *kiTunesMetadataFileName            = @"iTunesMetadata";

@interface iReSignAppDelegate()

@property (nonatomic, strong) ATVDeviceController *deviceController;

@end

@implementation iReSignAppDelegate

@synthesize window,workingPath, sshSession;

@synthesize deviceController;

static NSString *appleTVAddress = nil;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [flurry setAlphaValue:0.5];
    
    defaults = [NSUserDefaults standardUserDefaults];
    
    // Look up available signing certificates
    [self getCerts];
    
    if ([defaults valueForKey:@"ENTITLEMENT_PATH"])
        [entitlementField setStringValue:[defaults valueForKey:@"ENTITLEMENT_PATH"]];
    if ([defaults valueForKey:@"MOBILEPROVISION_PATH"])
        [provisioningPathField setStringValue:[defaults valueForKey:@"MOBILEPROVISION_PATH"]];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/zip"]) {
        [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"This app cannot run without the zip utility present at /usr/bin/zip"];
        exit(0);
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/unzip"]) {
        [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"This app cannot run without the unzip utility present at /usr/bin/unzip"];
        exit(0);
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/codesign"]) {
        [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"This app cannot run without the codesign utility present at /usr/bin/codesign"];
        exit(0);
    }
    
    deviceController = [[ATVDeviceController alloc] init];
    appleTVAddress = APPLE_TV_ADDRESS;
    
    NSLog(@"appleTVAddress: %@", appleTVAddress);
    
    if ([[appleTVAddress componentsSeparatedByString:@":"] count] < 2)
    {
        [self resetServerSettings];
        
    }
    
    if (appleTVAddress != nil)
    {
//        if (![self hostAvailable])
//        {
//            NSLog(@"host not available? resetting!");
//            [self resetServerSettings];
//        }
    }
    
    
    
    
}

- (int)extractDeb:(NSString *)inputFile toPath:(NSString *)theLocation
{
    NSTask *arTask = [[NSTask alloc] init];
    
    [arTask setLaunchPath:@"/usr/bin/ar"];
    [arTask setArguments:[NSArray arrayWithObjects:@"-x", inputFile, nil]];
    [arTask setCurrentDirectoryPath:theLocation];
    
    // NSFileHandle *nullOut = [NSFileHandle fileHandleWithNullDevice];
    //[arTask setStandardError:nullOut];
    //[arTask setStandardOutput:nullOut];
    [arTask launch];
    [arTask waitUntilExit];
    
    int theTerm = [arTask terminationStatus];
    
    arTask = nil;
    return theTerm;
    
}

- (void)processDeb:(NSString *)debFile withCompletionBlock:(void(^)(BOOL success))completionBlock
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        @autoreleasepool {
            
            BOOL success = false;
            int status = [self extractDeb:debFile toPath:workingPath];
            NSString *newPath = [workingPath stringByAppendingPathComponent:@"data.tar.lzma"];
            
            if (![FM fileExistsAtPath:newPath])
            {
                NSLog(@"no lzma file found, looking for gz");
                newPath = [workingPath stringByAppendingPathComponent:@"data.tar.gz"];
            }
            
            if ([FM fileExistsAtPath:newPath])
            {
                //found the file keep doing stuff
                NSString *ext = [[newPath pathExtension] lowercaseString];
                if ([ext isEqualToString:@"lzma"])
                {
                    status = [self extractLZMA:newPath toPath:workingPath];
                } else {
                    status = [self gunZip:newPath toLocation:workingPath];
                }
                
                NSString *applicationDir = [workingPath stringByAppendingPathComponent:@"Applications"];
                if ([FM fileExistsAtPath:applicationDir])
                {
                   
                    NSString *theAppName = [[FM contentsOfDirectoryAtPath:applicationDir error:nil] lastObject];
                    applicationDir = [applicationDir stringByAppendingPathComponent:theAppName];
                     NSLog(@"found application dir: %@", applicationDir);
                    NSString *tmpPayload = [workingPath stringByAppendingPathComponent:@"Payload"];
                    [FM createDirectoryAtPath:tmpPayload
                  withIntermediateDirectories:true attributes:nil error:nil];
                    [FM moveItemAtPath:applicationDir toPath:[tmpPayload stringByAppendingPathComponent:theAppName] error:nil];
                    success = true;
                }
                
            } else {
                
                  NSLog(@"no gz file found either, bail!");
                
            }
            
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
               
                completionBlock(success);
                
                
                
            });
            
        }
        
    });
}

- (int)extractLZMA:(NSString *)inputFile toPath:(NSString *)theLocation
{
    NSTask *tarTask = [[NSTask alloc] init];
   // NSFileHandle *nullOut = [NSFileHandle fileHandleWithNullDevice];
    
    [tarTask setLaunchPath:@"/usr/bin/tar"];
    [tarTask setArguments:[NSArray arrayWithObjects:@"-xpv", @"--lzma", @"-f", inputFile ,@"-C", theLocation, nil]];
    //[tarTask setCurrentDirectoryPath:toLocation];
    //[tarTask setStandardError:nullOut];
    //[tarTask setStandardOutput:nullOut];
    [tarTask launch];
    [tarTask waitUntilExit];
    
    int theTerm = [tarTask terminationStatus];
    
    tarTask = nil;
    return theTerm;
    
}

- (int)gunZip:(NSString *)inputTar toLocation:(NSString *)toLocation
{
    NSLog(@"/usr/bin/tar fxpz %@ -C %@", inputTar, toLocation);
    NSTask *tarTask = [[NSTask alloc] init];
    //NSFileHandle *nullOut = [NSFileHandle fileHandleWithNullDevice];
    
    [tarTask setLaunchPath:@"/usr/bin/tar"];
    [tarTask setArguments:[NSArray arrayWithObjects:@"-xpzv", @"-f", inputTar,@"-C", toLocation, nil]];
    //[tarTask setCurrentDirectoryPath:toLocation];
    //[tarTask setStandardError:nullOut];
    //[tarTask setStandardOutput:nullOut];
    [tarTask launch];
    [tarTask waitUntilExit];
    
    int theTerm = [tarTask terminationStatus];
    
    tarTask = nil;
    return theTerm;
    
}


- (BOOL)hostAvailable
{
    NSMutableURLRequest *request = [self hostAvailableRequest];
    NSHTTPURLResponse * theResponse = nil;
    NSError *theError = nil;
    [NSURLConnection sendSynchronousRequest:request returningResponse:&theResponse error:&theError];
    if (theError != nil)
    {
        NSLog(@"theResponse: %i theError; %@", [theResponse statusCode], theError);
        return (FALSE);
    }
    
    return (TRUE);
    
}

- (NSMutableURLRequest *)hostAvailableRequest // theres gotta be a more elegant way to do this
{
    NSString *httpCommand = [NSString stringWithFormat:@"http://%@/ap", APPLE_TV_ADDRESS];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setTimeoutInterval:2];
    [request setURL:[NSURL URLWithString:httpCommand]];
    [request setHTTPMethod:@"GET"];
    [request setValue:@"text/xml" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"X-User-Agent" forHTTPHeaderField:@"User-Agent"];
    [request setValue:nil forHTTPHeaderField:@"X-User-Agent"];
    return request;
}



- (void)resetServerSettings
{
    [DEFAULTS removeObjectForKey:@"appleTVHost"];
    [DEFAULTS removeObjectForKey:ATV_OS];
    [DEFAULTS removeObjectForKey:ATV_API];
    [DEFAULTS setObject:@"Choose Apple TV" forKey:@"selectedValue"];
    appleTVAddress = nil;
}


- (IBAction)resign:(id)sender {
    //Save cert name
    [defaults setValue:[NSNumber numberWithInteger:[certComboBox indexOfSelectedItem]] forKey:@"CERT_INDEX"];
    [defaults setValue:[entitlementField stringValue] forKey:@"ENTITLEMENT_PATH"];
    [defaults setValue:[provisioningPathField stringValue] forKey:@"MOBILEPROVISION_PATH"];
    [defaults setValue:[bundleIDField stringValue] forKey:kKeyPrefsBundleIDChange];
    [defaults synchronize];
    
    codesigningResult = nil;
    verificationResult = nil;
    
    sourcePath = [pathField stringValue];
    workingPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"com.appulize.iresign"];
    
    NSArray *acceptableArray = @[@"ipa", @"xcarchive", @"deb"];
    NSString *pathExt = [[sourcePath pathExtension] lowercaseString];
    
    if ([certComboBox objectValue]) {
        //if (([[[sourcePath pathExtension] lowercaseString] isEqualToString:@"ipa"]) ||
        //    ([[[sourcePath pathExtension] lowercaseString] isEqualToString:@"xcarchive"])) {
        if ([acceptableArray containsObject:pathExt]){
      
            [self disableControls];
            
            NSLog(@"Setting up working directory in %@",workingPath);
            [statusLabel setHidden:NO];
            [statusLabel setStringValue:@"Setting up working directory"];
            
            [[NSFileManager defaultManager] removeItemAtPath:workingPath error:nil];
            
            [[NSFileManager defaultManager] createDirectoryAtPath:workingPath withIntermediateDirectories:TRUE attributes:nil error:nil];
            
            if ([pathExt isEqualToString:@"ipa"]) {
                if (sourcePath && [sourcePath length] > 0) {
                    NSLog(@"Unzipping %@",sourcePath);
                    [statusLabel setStringValue:@"Extracting original app"];
                }
                
                unzipTask = [[NSTask alloc] init];
                [unzipTask setLaunchPath:@"/usr/bin/unzip"];
                [unzipTask setArguments:[NSArray arrayWithObjects:@"-q", sourcePath, @"-d", workingPath, nil]];
                
                [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkUnzip:) userInfo:nil repeats:TRUE];
                
                [unzipTask launch];
            } else if ([pathExt isEqualToString:@"deb"])
            {
                [self processDeb:sourcePath withCompletionBlock:^(BOOL success) {
                    
                    if (success)
                    {
                        [self checkUnzip:nil];
                        NSLog(@"success?!?!?!");
                    } else {
                        NSLog(@"FAILLE?!?!?!");
                    }
                    
                }];
            }
            else {
                NSString* payloadPath = [workingPath stringByAppendingPathComponent:kPayloadDirName];
                
                NSLog(@"Setting up %@ path in %@", kPayloadDirName, payloadPath);
                [statusLabel setStringValue:[NSString stringWithFormat:@"Setting up %@ path", kPayloadDirName]];
                
                [[NSFileManager defaultManager] createDirectoryAtPath:payloadPath withIntermediateDirectories:TRUE attributes:nil error:nil];
                
                NSLog(@"Retrieving %@", kInfoPlistFilename);
                [statusLabel setStringValue:[NSString stringWithFormat:@"Retrieving %@", kInfoPlistFilename]];
                
                NSString* infoPListPath = [sourcePath stringByAppendingPathComponent:kInfoPlistFilename];
                
                NSDictionary* infoPListDict = [NSDictionary dictionaryWithContentsOfFile:infoPListPath];
                
                if (infoPListDict != nil) {
                    NSString* applicationPath = nil;
                    
                    NSDictionary* applicationPropertiesDict = [infoPListDict objectForKey:kKeyInfoPlistApplicationProperties];
                    
                    if (applicationPropertiesDict != nil) {
                        applicationPath = [applicationPropertiesDict objectForKey:kKeyInfoPlistApplicationPath];
                    }
                    
                    if (applicationPath != nil) {
                        applicationPath = [[sourcePath stringByAppendingPathComponent:kProductsDirName] stringByAppendingPathComponent:applicationPath];
                        
                        NSLog(@"Copying %@ to %@ path in %@", applicationPath, kPayloadDirName, payloadPath);
                        [statusLabel setStringValue:[NSString stringWithFormat:@"Copying .xcarchive app to %@ path", kPayloadDirName]];
                        
                        copyTask = [[NSTask alloc] init];
                        [copyTask setLaunchPath:@"/bin/cp"];
                        [copyTask setArguments:[NSArray arrayWithObjects:@"-r", applicationPath, payloadPath, nil]];
                        
                        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkCopy:) userInfo:nil repeats:TRUE];
                        
                        [copyTask launch];
                    }
                    else {
                        [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:[NSString stringWithFormat:@"Unable to parse %@", kInfoPlistFilename]];
                        [self enableControls];
                        [statusLabel setStringValue:@"Ready"];
                    }
                }
                else {
                    [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:[NSString stringWithFormat:@"Retrieve %@ failed", kInfoPlistFilename]];
                    [self enableControls];
                    [statusLabel setStringValue:@"Ready"];
                }
            }
        }
        else {
            [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"You must choose an *.ipa or *.xcarchive file"];
            [self enableControls];
            [statusLabel setStringValue:@"Please try again"];
        }
    } else {
        [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"You must choose an signing certificate from dropdown."];
        [self enableControls];
        [statusLabel setStringValue:@"Please try again"];
    }
}

- (void)checkUnzip:(NSTimer *)timer {
    if ([unzipTask isRunning] == 0) {
        [timer invalidate];
        unzipTask = nil;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[workingPath stringByAppendingPathComponent:kPayloadDirName]]) {
            NSLog(@"Unzipping done");
            [statusLabel setStringValue:@"Original app extracted"];
            
            if (changeBundleIDCheckbox.state == NSOnState) {
                [self doBundleIDChange:bundleIDField.stringValue];
            }
            
            if ([[provisioningPathField stringValue] isEqualTo:@""]) {
                [self doCodeSigning];
            } else {
                [self doProvisioning];
            }
        } else {
            [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"Unzip failed"];
            [self enableControls];
            [statusLabel setStringValue:@"Ready"];
        }
    }
}

- (void)checkCopy:(NSTimer *)timer {
    if ([copyTask isRunning] == 0) {
        [timer invalidate];
        copyTask = nil;
        
        NSLog(@"Copy done");
        [statusLabel setStringValue:@".xcarchive app copied"];
        
        if (changeBundleIDCheckbox.state == NSOnState) {
            [self doBundleIDChange:bundleIDField.stringValue];
        }
        
        if ([[provisioningPathField stringValue] isEqualTo:@""]) {
            [self doCodeSigning];
        } else {
            [self doProvisioning];
        }
    }
}

- (BOOL)doBundleIDChange:(NSString *)newBundleID {
    BOOL success = YES;
    
    success &= [self doAppBundleIDChange:newBundleID];
    success &= [self doITunesMetadataBundleIDChange:newBundleID];
    
    return success;
}


- (BOOL)doITunesMetadataBundleIDChange:(NSString *)newBundleID {
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:workingPath error:nil];
    NSString *infoPlistPath = nil;
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"plist"]) {
            infoPlistPath = [workingPath stringByAppendingPathComponent:file];
            break;
        }
    }
    
    return [self changeBundleIDForFile:infoPlistPath bundleIDKey:kKeyBundleIDPlistiTunesArtwork newBundleID:newBundleID plistOutOptions:NSPropertyListXMLFormat_v1_0];
    
}

- (BOOL)doAppBundleIDChange:(NSString *)newBundleID {
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[workingPath stringByAppendingPathComponent:kPayloadDirName] error:nil];
    NSString *infoPlistPath = nil;
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            infoPlistPath = [[[workingPath stringByAppendingPathComponent:kPayloadDirName]
                              stringByAppendingPathComponent:file]
                             stringByAppendingPathComponent:kInfoPlistFilename];
            break;
        }
    }
    
    return [self changeBundleIDForFile:infoPlistPath bundleIDKey:kKeyBundleIDPlistApp newBundleID:newBundleID plistOutOptions:NSPropertyListBinaryFormat_v1_0];
}

- (BOOL)changeBundleIDForFile:(NSString *)filePath bundleIDKey:(NSString *)bundleIDKey newBundleID:(NSString *)newBundleID plistOutOptions:(NSPropertyListWriteOptions)options {
    
    NSMutableDictionary *plist = nil;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        plist = [[NSMutableDictionary alloc] initWithContentsOfFile:filePath];
        [plist setObject:newBundleID forKey:bundleIDKey];
        
        NSData *xmlData = [NSPropertyListSerialization dataWithPropertyList:plist format:options options:kCFPropertyListImmutable error:nil];
        
        return [xmlData writeToFile:filePath atomically:YES];
        
    }
    
    return NO;
}


- (void)doProvisioning {
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[workingPath stringByAppendingPathComponent:kPayloadDirName] error:nil];
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            appPath = [[workingPath stringByAppendingPathComponent:kPayloadDirName] stringByAppendingPathComponent:file];
            if ([[NSFileManager defaultManager] fileExistsAtPath:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"]]) {
                NSLog(@"Found embedded.mobileprovision, deleting.");
                [[NSFileManager defaultManager] removeItemAtPath:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"] error:nil];
            }
            break;
        }
    }
    
    NSString *targetPath = [appPath stringByAppendingPathComponent:@"embedded.mobileprovision"];
    
    provisioningTask = [[NSTask alloc] init];
    [provisioningTask setLaunchPath:@"/bin/cp"];
    [provisioningTask setArguments:[NSArray arrayWithObjects:[provisioningPathField stringValue], targetPath, nil]];
    
    [provisioningTask launch];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkProvisioning:) userInfo:nil repeats:TRUE];
}

- (void)checkProvisioning:(NSTimer *)timer {
    if ([provisioningTask isRunning] == 0) {
        [timer invalidate];
        provisioningTask = nil;
        
        NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[workingPath stringByAppendingPathComponent:kPayloadDirName] error:nil];
        
        for (NSString *file in dirContents) {
            if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
                appPath = [[workingPath stringByAppendingPathComponent:kPayloadDirName] stringByAppendingPathComponent:file];
                if ([[NSFileManager defaultManager] fileExistsAtPath:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"]]) {
                    
                    BOOL identifierOK = FALSE;
                    NSString *identifierInProvisioning = @"";
                    
                    NSString *embeddedProvisioning = [NSString stringWithContentsOfFile:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"] encoding:NSASCIIStringEncoding error:nil];
                    NSArray* embeddedProvisioningLines = [embeddedProvisioning componentsSeparatedByCharactersInSet:
                                                          [NSCharacterSet newlineCharacterSet]];
                    
                    for (int i = 0; i < [embeddedProvisioningLines count]; i++) {
                        if ([[embeddedProvisioningLines objectAtIndex:i] rangeOfString:@"application-identifier"].location != NSNotFound) {
                            
                            NSInteger fromPosition = [[embeddedProvisioningLines objectAtIndex:i+1] rangeOfString:@"<string>"].location + 8;
                            
                            NSInteger toPosition = [[embeddedProvisioningLines objectAtIndex:i+1] rangeOfString:@"</string>"].location;
                            
                            NSRange range;
                            range.location = fromPosition;
                            range.length = toPosition-fromPosition;
                            
                            NSString *fullIdentifier = [[embeddedProvisioningLines objectAtIndex:i+1] substringWithRange:range];
                            
                            NSArray *identifierComponents = [fullIdentifier componentsSeparatedByString:@"."];
                            
                            if ([[identifierComponents lastObject] isEqualTo:@"*"]) {
                                identifierOK = TRUE;
                            }
                            
                            for (int i = 1; i < [identifierComponents count]; i++) {
                                identifierInProvisioning = [identifierInProvisioning stringByAppendingString:[identifierComponents objectAtIndex:i]];
                                if (i < [identifierComponents count]-1) {
                                    identifierInProvisioning = [identifierInProvisioning stringByAppendingString:@"."];
                                }
                            }
                            break;
                        }
                    }
                    
                    NSLog(@"Mobileprovision identifier: %@",identifierInProvisioning);
                    
                    NSDictionary *infoplist = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Info.plist"]];
                    if ([identifierInProvisioning isEqualTo:[infoplist objectForKey:kKeyBundleIDPlistApp]]) {
                        NSLog(@"Identifiers match");
                        identifierOK = TRUE;
                    }
                    
                    if (identifierOK) {
                        NSLog(@"Provisioning completed.");
                        [statusLabel setStringValue:@"Provisioning completed"];
                        [self doEntitlementsFixing];
                    } else {
                        [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"Product identifiers don't match"];
                        [self enableControls];
                        [statusLabel setStringValue:@"Ready"];
                    }
                } else {
                    [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"Provisioning failed"];
                    [self enableControls];
                    [statusLabel setStringValue:@"Ready"];
                }
                break;
            }
        }
    }
}

- (void)doEntitlementsFixing
{
    if (![entitlementField.stringValue isEqualToString:@""] || [provisioningPathField.stringValue isEqualToString:@""]) {
        [self doCodeSigning];
        return; // Using a pre-made entitlements file or we're not re-provisioning.
    }
    
    [statusLabel setStringValue:@"Generating entitlements"];

    if (appPath) {
        generateEntitlementsTask = [[NSTask alloc] init];
        [generateEntitlementsTask setLaunchPath:@"/usr/bin/security"];
        [generateEntitlementsTask setArguments:@[@"cms", @"-D", @"-i", provisioningPathField.stringValue]];
        [generateEntitlementsTask setCurrentDirectoryPath:workingPath];

        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkEntitlementsFix:) userInfo:nil repeats:TRUE];

        NSPipe *pipe=[NSPipe pipe];
        [generateEntitlementsTask setStandardOutput:pipe];
        [generateEntitlementsTask setStandardError:pipe];
        NSFileHandle *handle = [pipe fileHandleForReading];

        [generateEntitlementsTask launch];

        [NSThread detachNewThreadSelector:@selector(watchEntitlements:)
                                 toTarget:self withObject:handle];
    }
}

- (void)watchEntitlements:(NSFileHandle*)streamHandle {
    @autoreleasepool {
        entitlementsResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
    }
}

- (void)checkEntitlementsFix:(NSTimer *)timer {
    if ([generateEntitlementsTask isRunning] == 0) {
        [timer invalidate];
        generateEntitlementsTask = nil;
        NSLog(@"Entitlements fixed done");
        [statusLabel setStringValue:@"Entitlements generated"];
        [self doEntitlementsEdit];
    }
}

- (void)doEntitlementsEdit
{
    NSDictionary* entitlements = entitlementsResult.propertyList;
    entitlements = entitlements[@"Entitlements"];
    NSString* filePath = [workingPath stringByAppendingPathComponent:@"entitlements.plist"];
    NSData *xmlData = [NSPropertyListSerialization dataWithPropertyList:entitlements format:NSPropertyListXMLFormat_v1_0 options:kCFPropertyListImmutable error:nil];
    if(![xmlData writeToFile:filePath atomically:YES]) {
        NSLog(@"Error writing entitlements file.");
        [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"Failed entitlements generation"];
        [self enableControls];
        [statusLabel setStringValue:@"Ready"];
    }
    else {
        entitlementField.stringValue = filePath;
        [self doCodeSigning];
    }
}

- (void)doCodeSigning {
    appPath = nil;
    frameworksDirPath = nil;
    hasFrameworks = NO;
    frameworks = [[NSMutableArray alloc] init];
    
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[workingPath stringByAppendingPathComponent:kPayloadDirName] error:nil];
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            appPath = [[workingPath stringByAppendingPathComponent:kPayloadDirName] stringByAppendingPathComponent:file];
            frameworksDirPath = [appPath stringByAppendingPathComponent:kFrameworksDirName];
            pluginsDirPath = [appPath stringByAppendingPathComponent:kPluginsDirName];
            NSLog(@"Found %@",appPath);
            appName = file;
            if ([[NSFileManager defaultManager] fileExistsAtPath:frameworksDirPath]) {
                NSLog(@"Found %@",frameworksDirPath);
                hasFrameworks = YES;
                NSArray *frameworksContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:frameworksDirPath error:nil];
                for (NSString *frameworkFile in frameworksContents) {
                    NSString *extension = [[frameworkFile pathExtension] lowercaseString];
                    if ([extension isEqualTo:@"framework"] || [extension isEqualTo:@"dylib"]) {
                        frameworkPath = [frameworksDirPath stringByAppendingPathComponent:frameworkFile];
                        NSLog(@"Found %@",frameworkPath);
                        [frameworks addObject:frameworkPath];
                    }
                }
            }
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:pluginsDirPath]) {
                NSLog(@"Found %@",pluginsDirPath);
                hasFrameworks = YES;
                NSArray *pluginContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:pluginsDirPath error:nil];
                for (NSString *pluginFile in pluginContents) {
                    NSString *extension = [[pluginFile pathExtension] lowercaseString];
                    if ([extension isEqualTo:@"appex"]) {
                        frameworkPath = [pluginsDirPath stringByAppendingPathComponent:pluginFile];
                        NSLog(@"Found %@",frameworkPath);
                        [frameworks addObject:frameworkPath];
                    }
                }
            }
            
            [statusLabel setStringValue:[NSString stringWithFormat:@"Codesigning %@",file]];
            break;
        }
    }
    
    if (appPath) {
        if (hasFrameworks) {
            [self signFile:[frameworks lastObject]];
            [frameworks removeLastObject];
        } else {
            [self signFile:appPath];
        }
    }
}

- (void)signFile:(NSString*)filePath {
    NSLog(@"Codesigning %@", filePath);
    [statusLabel setStringValue:[NSString stringWithFormat:@"Codesigning %@",filePath]];
    
    NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"-fs", [certComboBox objectValue], nil];
    NSDictionary *systemVersionDictionary = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    NSString * systemVersion = [systemVersionDictionary objectForKey:@"ProductVersion"];
    NSArray * version = [systemVersion componentsSeparatedByString:@"."];
    if ([version[0] intValue]<10 || ([version[0] intValue]==10 && ([version[1] intValue]<9 || ([version[1] intValue]==9 && [version[2] intValue]<5)))) {
        
        /*
         Before OSX 10.9, code signing requires a version 1 signature.
         The resource envelope is necessary.
         To ensure it is added, append the resource flag to the arguments.
         */
        
        NSString *resourceRulesPath = [[NSBundle mainBundle] pathForResource:@"ResourceRules" ofType:@"plist"];
        NSString *resourceRulesArgument = [NSString stringWithFormat:@"--resource-rules=%@",resourceRulesPath];
        [arguments addObject:resourceRulesArgument];
    } else {
        
        /*
         For OSX 10.9 and later, code signing requires a version 2 signature.
         The resource envelope is obsolete.
         To ensure it is ignored, remove the resource key from the Info.plist file.
         */
        
        NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", filePath];
        NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
        [infoDict removeObjectForKey:@"CFBundleResourceSpecification"];
        [infoDict writeToFile:infoPath atomically:YES];
        [arguments addObject:@"--no-strict"]; // http://stackoverflow.com/a/26204757
    }
    
    if (![[entitlementField stringValue] isEqualToString:@""]) {
        [arguments addObject:[NSString stringWithFormat:@"--entitlements=%@", [entitlementField stringValue]]];
    }
    
    [arguments addObjectsFromArray:[NSArray arrayWithObjects:filePath, nil]];
    
    codesignTask = [[NSTask alloc] init];
    [codesignTask setLaunchPath:@"/usr/bin/codesign"];
    [codesignTask setArguments:arguments];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkCodesigning:) userInfo:nil repeats:TRUE];
    
    
    NSPipe *pipe=[NSPipe pipe];
    [codesignTask setStandardOutput:pipe];
    [codesignTask setStandardError:pipe];
    NSFileHandle *handle=[pipe fileHandleForReading];
    
    [codesignTask launch];
    
    [NSThread detachNewThreadSelector:@selector(watchCodesigning:)
                             toTarget:self withObject:handle];
}

- (void)watchCodesigning:(NSFileHandle*)streamHandle {
    @autoreleasepool {
        
        codesigningResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
        
    }
}

- (void)checkCodesigning:(NSTimer *)timer {
    if ([codesignTask isRunning] == 0) {
        [timer invalidate];
        codesignTask = nil;
        if (frameworks.count > 0) {
            [self signFile:[frameworks lastObject]];
            [frameworks removeLastObject];
        } else if (hasFrameworks) {
            hasFrameworks = NO;
            [self signFile:appPath];
        } else {
            NSLog(@"Codesigning done");
            [statusLabel setStringValue:@"Codesigning completed"];
            [self doVerifySignature];
        }
    }
}

- (void)doVerifySignature {
    if (appPath) {
        verifyTask = [[NSTask alloc] init];
        [verifyTask setLaunchPath:@"/usr/bin/codesign"];
        [verifyTask setArguments:[NSArray arrayWithObjects:@"-v", appPath, nil]];
		
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkVerificationProcess:) userInfo:nil repeats:TRUE];
        
        NSLog(@"Verifying %@",appPath);
        [statusLabel setStringValue:[NSString stringWithFormat:@"Verifying %@",appName]];
        
        NSPipe *pipe=[NSPipe pipe];
        [verifyTask setStandardOutput:pipe];
        [verifyTask setStandardError:pipe];
        NSFileHandle *handle=[pipe fileHandleForReading];
        
        [verifyTask launch];
        
        [NSThread detachNewThreadSelector:@selector(watchVerificationProcess:)
                                 toTarget:self withObject:handle];
    }
}

- (void)watchVerificationProcess:(NSFileHandle*)streamHandle {
    @autoreleasepool {
        
        verificationResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
        
    }
}

- (void)checkVerificationProcess:(NSTimer *)timer {
    if ([verifyTask isRunning] == 0) {
        [timer invalidate];
        verifyTask = nil;
        if ([verificationResult length] == 0) {
            NSLog(@"Verification done");
            [statusLabel setStringValue:@"Verification completed"];
            [self doZip];
        } else {
            NSString *error = [[codesigningResult stringByAppendingString:@"\n\n"] stringByAppendingString:verificationResult];
            [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Signing failed" AndMessage:error];
            [self enableControls];
            [statusLabel setStringValue:@"Please try again"];
        }
    }
}

- (void)doZip {
    if (appPath) {
        NSArray *destinationPathComponents = [sourcePath pathComponents];
        NSString *destinationPath = @"";
        
        for (int i = 0; i < ([destinationPathComponents count]-1); i++) {
            destinationPath = [destinationPath stringByAppendingPathComponent:[destinationPathComponents objectAtIndex:i]];
        }
        
        fileName = [sourcePath lastPathComponent];
        fileName = [fileName substringToIndex:([fileName length] - ([[sourcePath pathExtension] length] + 1))];
        fileName = [fileName stringByAppendingString:@"-resigned"];
        fileName = [fileName stringByAppendingPathExtension:@"ipa"];
        
        destinationPath = [destinationPath stringByAppendingPathComponent:fileName];
        
        NSLog(@"Dest: %@",destinationPath);
        
        zipTask = [[NSTask alloc] init];
        [zipTask setLaunchPath:@"/usr/bin/zip"];

        [zipTask setCurrentDirectoryPath:workingPath];
        [zipTask setArguments:[NSArray arrayWithObjects:@"-qry", destinationPath, @".", nil]];
		
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkZip:) userInfo:nil repeats:TRUE];
        
        NSLog(@"Zipping %@", destinationPath);
        finalDestination = destinationPath;
        [statusLabel setStringValue:[NSString stringWithFormat:@"Saving %@",fileName]];
        
        [zipTask launch];
    }
}

- (void)checkZip:(NSTimer *)timer {
    if ([zipTask isRunning] == 0) {
        [timer invalidate];
        zipTask = nil;
        NSLog(@"Zipping done");
        [statusLabel setStringValue:[NSString stringWithFormat:@"Saved %@",fileName]];
        
        [[NSFileManager defaultManager] removeItemAtPath:workingPath error:nil];
   
        
        NSString *result = [[codesigningResult stringByAppendingString:@"\n\n"] stringByAppendingString:verificationResult];
        NSLog(@"Codesigning result: %@",result);
        
        
        [statusLabel setStringValue:@"Checking for AppSync unified..."];
        
        if ([self hasASU] == true && INSTALL_ON_ATV == true)
        {
            NSLog(@"APPLE_TV_ADDRESS: %@", APPLE_TV_ADDRESS);
            [statusLabel setStringValue:[NSString stringWithFormat:@"Installing file %@...", fileName]];
            
            //[DEFAULTS setValue:@"192.168.0.4:22" forKey:ATV_HOST];
            
            [self installFile:finalDestination withCompletionBlock:^(BOOL success) {
                
               [self enableControls];
                if (success == true)
                {
                    [statusLabel setStringValue:@"Application installed successfully!?"];
                } else {
                    [statusLabel setStringValue:@"Application install failed!?"];
                }
                
            }];
            
        } else if(INSTALL_ON_ATV == true){
            
            [statusLabel setStringValue:@"AppSync unified not found"];
            
            [self enableControls];
        } else {
            
            [statusLabel setStringValue:@"Finished"];
            [self enableControls];
        }
        

        
      
        
    }
}

- (void)installFile:(NSString *)theFile withCompletionBlock:(void(^)(BOOL success))completionBlock
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        @autoreleasepool {
            
            BOOL success = FALSE;
            
            if ([self uploadFile:finalDestination] == true)
            {
                NSString *runLine = [NSString stringWithFormat:@"/usr/bin/appinst /var/root/%@", fileName];
                NSString *doInstall =  [self sendCommandString:runLine];
                success = true;
                NSLog(@"response: %@", doInstall);
            }
            
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
         
                    completionBlock(success);
                
                
                
            });
            
        }
        
    });
}


- (IBAction)browse:(id)sender {
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    
    [openDlg setCanChooseFiles:TRUE];
    [openDlg setCanChooseDirectories:FALSE];
    [openDlg setAllowsMultipleSelection:FALSE];
    [openDlg setAllowsOtherFileTypes:FALSE];
    [openDlg setAllowedFileTypes:@[@"ipa", @"IPA", @"xcarchive", @"deb"]];
    
    if ([openDlg runModal] == NSOKButton)
    {
        NSString* fileNameOpened = [[[openDlg URLs] objectAtIndex:0] path];
        [pathField setStringValue:fileNameOpened];
    }
}

- (IBAction)provisioningBrowse:(id)sender {
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    
    [openDlg setCanChooseFiles:TRUE];
    [openDlg setCanChooseDirectories:FALSE];
    [openDlg setAllowsMultipleSelection:FALSE];
    [openDlg setAllowsOtherFileTypes:FALSE];
    [openDlg setAllowedFileTypes:@[@"mobileprovision", @"MOBILEPROVISION"]];
    
    if ([openDlg runModal] == NSOKButton)
    {
        NSString* fileNameOpened = [[[openDlg URLs] objectAtIndex:0] path];
        [provisioningPathField setStringValue:fileNameOpened];
    }
}

- (IBAction)entitlementBrowse:(id)sender {
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    
    [openDlg setCanChooseFiles:TRUE];
    [openDlg setCanChooseDirectories:FALSE];
    [openDlg setAllowsMultipleSelection:FALSE];
    [openDlg setAllowsOtherFileTypes:FALSE];
    [openDlg setAllowedFileTypes:@[@"plist", @"PLIST", @"entitlements"]];
    
    if ([openDlg runModal] == NSOKButton)
    {
        NSString* fileNameOpened = [[[openDlg URLs] objectAtIndex:0] path];
        [entitlementField setStringValue:fileNameOpened];
    }
}

- (IBAction)changeBundleIDPressed:(id)sender {
    
    if (sender != changeBundleIDCheckbox) {
        return;
    }
    
    bundleIDField.enabled = changeBundleIDCheckbox.state == NSOnState;
}

- (void)disableControls {
    [pathField setEnabled:FALSE];
    [entitlementField setEnabled:FALSE];
    [browseButton setEnabled:FALSE];
    [resignButton setEnabled:FALSE];
    [provisioningBrowseButton setEnabled:NO];
    [provisioningPathField setEnabled:NO];
    [changeBundleIDCheckbox setEnabled:NO];
    [bundleIDField setEnabled:NO];
    [certComboBox setEnabled:NO];
    
    [flurry startAnimation:self];
    [flurry setAlphaValue:1.0];
}

- (void)enableControls {
    [pathField setEnabled:TRUE];
    [entitlementField setEnabled:TRUE];
    [browseButton setEnabled:TRUE];
    [resignButton setEnabled:TRUE];
    [provisioningBrowseButton setEnabled:YES];
    [provisioningPathField setEnabled:YES];
    [changeBundleIDCheckbox setEnabled:YES];
    [bundleIDField setEnabled:changeBundleIDCheckbox.state == NSOnState];
    [certComboBox setEnabled:YES];
    
    [flurry stopAnimation:self];
    [flurry setAlphaValue:0.5];
}

-(NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox {
    NSInteger count = 0;
    if ([aComboBox isEqual:certComboBox]) {
        count = [certComboBoxItems count];
    }
    return count;
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index {
    id item = nil;
    if ([aComboBox isEqual:certComboBox]) {
        item = [certComboBoxItems objectAtIndex:index];
    }
    return item;
}

- (void)getCerts {
    
    getCertsResult = nil;
    
    NSLog(@"Getting Certificate IDs");
    [statusLabel setStringValue:@"Getting Signing Certificate IDs"];
    
    certTask = [[NSTask alloc] init];
    [certTask setLaunchPath:@"/usr/bin/security"];
    //taking out -v allows you to codesign with self signed certs
    [certTask setArguments:[NSArray arrayWithObjects:@"find-identity", @"-p", @"codesigning", nil]];
    //[certTask setArguments:[NSArray arrayWithObjects:@"find-identity", @"-v", @"-p", @"codesigning", nil]];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkCerts:) userInfo:nil repeats:TRUE];
    
    NSPipe *pipe=[NSPipe pipe];
    [certTask setStandardOutput:pipe];
    [certTask setStandardError:pipe];
    NSFileHandle *handle=[pipe fileHandleForReading];
    
    [certTask launch];
    
    [NSThread detachNewThreadSelector:@selector(watchGetCerts:) toTarget:self withObject:handle];
}

- (void)watchGetCerts:(NSFileHandle*)streamHandle {
    @autoreleasepool {
        
        NSString *securityResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
        // Verify the security result
        if (securityResult == nil || securityResult.length < 1) {
            // Nothing in the result, return
            return;
        }
        NSArray *rawResult = [securityResult componentsSeparatedByString:@"\""];
        NSMutableArray *tempGetCertsResult = [NSMutableArray arrayWithCapacity:20];
        for (int i = 0; i <= [rawResult count] - 2; i+=2) {
            
           // NSLog(@"i:%d", i+1);
            if (rawResult.count - 1 < i + 1) {
                // Invalid array, don't add an object to that position
            } else {
                // Valid object
                [tempGetCertsResult addObject:[rawResult objectAtIndex:i+1]];
            }
        }
        
        certComboBoxItems = [NSMutableArray arrayWithArray:tempGetCertsResult];
        
        [certComboBox reloadData];
        
    }
}

- (void)checkCerts:(NSTimer *)timer {
    if ([certTask isRunning] == 0) {
        [timer invalidate];
        certTask = nil;
        
        if ([certComboBoxItems count] > 0) {
            NSLog(@"Get Certs done");
            [statusLabel setStringValue:@"Signing Certificate IDs extracted"];
            
            if ([defaults valueForKey:@"CERT_INDEX"]) {
                
                NSInteger selectedIndex = [[defaults valueForKey:@"CERT_INDEX"] integerValue];
                if (selectedIndex != -1) {
                    NSString *selectedItem = [self comboBox:certComboBox objectValueForItemAtIndex:selectedIndex];
                    [certComboBox setObjectValue:selectedItem];
                    [certComboBox selectItemAtIndex:selectedIndex];
                }
                
                [self enableControls];
            }
        } else {
            [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"Getting Certificate ID's failed"];
            [self enableControls];
            [statusLabel setStringValue:@"Ready"];
        }
    }
}

// If the application dock icon is clicked, reopen the window
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    // Make sure the window is visible
    if (![self.window isVisible]) {
        // Window isn't shown, show it
        [self.window makeKeyAndOrderFront:self];
    }
    
    // Return YES
    return YES;
}

#pragma mark - Alert Methods

/* NSRunAlerts are being deprecated in 10.9 */

// Show a critical alert
- (void)showAlertOfKind:(NSAlertStyle)style WithTitle:(NSString *)title AndMessage:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"OK"];
    [alert setMessageText:title];
    [alert setInformativeText:message];
    [alert setAlertStyle:style];
    [alert runModal];
}

#pragma kevins additions for JB tvOS & appsync

- (BOOL)hasASU
{
    NSString *theReturn = [self sendCommandString:@"ls /usr/bin/ | grep appinst"];
    if (theReturn != nil)
    { return (TRUE);
    } else { return (FALSE);}
    
    return (FALSE);
}

- (BOOL)isJailbroken
{
    NSError *error = nil;
    if (APPLE_TV_ADDRESS != nil)
    {
        ObjSSH *ssh = [ObjSSH connectToHost:APPLE_TV_ADDRESS withUsername:@"root" password:@"alpine" error:&error];
        if (error)
        {
            NSLog(@"error: %@", [error localizedDescription]);
            if ([[error localizedDescription] isEqualToString:@"Failed to connect"])
            {
                [ssh disconnect];

                return (FALSE);
            }
            
            [ssh disconnect];

        }
    } else {
        return (FALSE);
    }
    
    
    return (TRUE);
}

- (NSString *)input: (NSString *)prompt defaultValue: (NSString *)defaultValue {
    NSAlert *alert = [NSAlert alertWithMessageText: prompt
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@""];
    
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
    [input setStringValue:defaultValue];
    //[input autorelease];
    [alert setAccessoryView:input];
    NSInteger button = [alert runModal];
    if (button == NSAlertDefaultReturn) {
        [input validateEditing];
        NSString *inputString = [input stringValue];
        //[input autorelease];
        return inputString;
    } else if (button == NSAlertAlternateReturn) {
        return nil;
    } else {
        
        return nil;
    }
}

- (NSString *)secureInput: (NSString *)prompt defaultValue: (NSString *)defaultValue {
    NSAlert *alert = [NSAlert alertWithMessageText: prompt
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@""];
    
    NSSecureTextField *input = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
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
        
        return nil;
    }
}

- (void)addkeychainPassword:(NSString *)password
{
    //kSecProtocolTypeSSH
    [EMInternetKeychainItem addInternetKeychainItemForServer:APPLE_TV_ADDRESS	withUsername:@"root" password:password path:@"/usr/bin/ssh" port:22 protocol:kSecProtocolTypeSSH];
}

- (NSString *)passwordForHost:(NSString *)ipAddress
{
    EMInternetKeychainItem *keychainItem = [EMInternetKeychainItem internetKeychainItemForServer:APPLE_TV_ADDRESS withUsername:@"root" path:@"/usr/bin/ssh" port:22 protocol:kSecProtocolTypeSSH];
    //Grab the password.
    if (keychainItem != nil)
    {
        //Grab the password.
        NSString *password = keychainItem.password;
        
        return password;
    }
    
    NSLog(@"nothing!");
    return nil;
    
}

- (BOOL)uploadFile:(NSString *)theFile
{
    NSLog(@"uploading file: %@", theFile);
    NSError *error = nil;
    BOOL getSession = [self connectToSSH];
    if (getSession == FALSE)
    {
        NSLog(@"failed to get session!");
        return (FALSE);
    }
    
    
    
    BOOL uploadFile = [sshSession uploadFile:theFile to:[theFile lastPathComponent] error:&error];
    if (error)
    {
        NSLog(@"ERROR!: %@", error);
    }
    return (uploadFile);
    
}

- (NSString *)sendCommandString:(NSString *)theCommand
{
    
    NSError *error = nil;
    BOOL getSession = [self connectToSSH];
    if (getSession == FALSE)
    {
        NSLog(@"failed to get session!");
        return nil;
    }
    
    
    NSString *response = [sshSession execute:theCommand error:&error];
    
    return response;
    
}

- (BOOL)connectToSSH
{
    NSError *error = nil;
    
    if (sshSession == nil)
    {
        //NSLog(@"APPLE_TV_ADDRESS: %@", APPLE_TV_ADDRESS);
        sshSession = [ObjSSH connectToHost:APPLE_TV_ADDRESS withUsername:@"root" password:@"alpine" error:&error];
        if (sshSession == nil)
        {
            NSLog(@"error: %@ get password!", error);
            NSString *passwordForHost = [self passwordForHost:APPLE_TV_ADDRESS];
            NSString *output = nil;
            if (passwordForHost != nil)
            {
                output = passwordForHost;
                
            } else {
                output = [self secureInput:@"Enter Password" defaultValue:@""];
            }
            
            if ([output length] == 0)
            {
                NSLog(@"no password to send!! return!");
                
                return (FALSE);
                
            } else {
                
                [self addkeychainPassword:output];
                
                error = nil;
                sshSession = [ObjSSH connectToHost:APPLE_TV_ADDRESS withUsername:@"root" password:output error:&error];
                
                if (error != nil)
                {
                    NSLog(@"error: %@ password failed!", error);	
                    
                    return (FALSE);
                }
                
            }
            
            
        }
    }
    if (sshSession != nil)
        return (TRUE);
    
    
    return (FALSE);
}

- (void)showNotJailbrokenWarning
{
    NSAlert *alert = [NSAlert alertWithMessageText:@"This Apple TV isn't jailbroken, please jailbreak it first! Would you like to visit our web site for further assistance?"
                                     defaultButton:@"Yes"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@""];
    
    NSInteger button = [alert runModal];
    if (button == NSAlertDefaultReturn) {
        
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://wiki.awkwardtv.org"]];
    }
}

- (void)showATVWarning
{
    NSAlert *alert = [NSAlert alertWithMessageText:@"Only the AppleTV 4 is supported"
                                     defaultButton:@"OK"
                                   alternateButton:nil
                                       otherButton:nil
                         informativeTextWithFormat:@""];
    
    [alert runModal];
}


@end
