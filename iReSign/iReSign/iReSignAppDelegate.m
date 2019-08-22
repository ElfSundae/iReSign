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

@interface NSString (TSSAdditions)

- (id)dictionaryFromString;

@end

@implementation NSString (TSSAdditions)

/*
 
 we use this to convert a raw dictionary plist string into a proper NSDictionary
 
 */

- (id)dictionaryFromString
{
    NSError *error = nil;
    NSPropertyListFormat format;
    NSData *theData = [self dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO];
    NSLog(@"theData: %@", theData);
   id theDict = [NSPropertyListSerialization propertyListWithData:theData options:NSPropertyListImmutable format:&format error:&error];
    
    /*
    id theDict = [NSPropertyListSerialization propertyListFromData:theData
                                                  mutabilityOption:NSPropertyListImmutable
                                                            format:&format
                                                  errorDescription:&error];
     */
    NSLog(@"error: %@", error);
    return theDict;
}


@end

@interface NSArray (profileHelper)

- (NSArray *)subarrayWithName:(NSString *)theName;

@end


@implementation NSArray (profileHelper)


//filter subarray based on what contacts have that particular name sorted ascending by creation date. used to easily sort the top most object as far as date created when doing profile comparisons

- (NSArray *)subarrayWithName:(NSString *)theName
{
    NSPredicate *filterPredicate = [NSPredicate predicateWithFormat:@"(Name == %@)", theName];
    NSSortDescriptor *sortDesc = [[NSSortDescriptor alloc] initWithKey:@"CreationDate" ascending:TRUE];
    NSArray *filteredArray = [self filteredArrayUsingPredicate:filterPredicate];
    return [filteredArray sortedArrayUsingDescriptors:@[sortDesc]];
}

@end

@interface NSString (profileHelper)
- (id)dictionaryFromString;
- (NSString *)plistSafeString;
@end

@implementation NSString (profileHelper)

//convert basic XML plist string from the profile and convert it into a mutable nsdictionary

- (NSString *)plistSafeString
{
    NSUInteger startingLocation = [self rangeOfString:@"<?xml"].location;
    
    //find NSRange of the end of the plist (there is "junk" cert data after our plist info as well
    NSRange endingRange = [self rangeOfString:@"</plist>"];
    
    //adjust the location of endingRange to include </plist> into our newly trimmed string.
    NSUInteger endingLocation = endingRange.location + endingRange.length;
    
    //offset the ending location to trim out the "garbage" before <?xml
    NSUInteger endingLocationAdjusted = endingLocation - startingLocation;
    
    //create the final range of the string data from <?xml to </plist>
    
    NSRange plistRange = NSMakeRange(startingLocation, endingLocationAdjusted);
    
    //actually create our string!
    return [self substringWithRange:plistRange];
}

- (id)dictionaryFromString
{
    NSString *error = nil;
    NSPropertyListFormat format;
    NSData *theData = [self dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    id theDict = [NSPropertyListSerialization propertyListFromData:theData
                                                  mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                                            format:&format
                                                  errorDescription:&error];
    //DLog(@"error: %@", error);
    return theDict;
}

@end

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
{
    NSDictionary *_provisioningProfileDict;
    NSDictionary *_firstDevice;
    NSString *_firstDeviceID;
    NSArray *_validProfiles;
    NSDictionary *_infoDict;
    NSString *exePath;
    
}
@property (nonatomic, strong) ATVDeviceController *deviceController;

@end

@implementation iReSignAppDelegate

@synthesize window,workingPath, sshSession, atvAvailable, isSending;

@synthesize deviceController;

static NSString *appleTVAddress = nil;


- (NSArray *)deviceList
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"afcclient" ofType:@"" inDirectory:@"mac_libs"];
    NSArray *returns = [iReSignAppDelegate returnForProcess:[NSString stringWithFormat:@"%@ -l", path]];
    NSString *string = [returns componentsJoinedByString:@"\n"];
    return [string dictionaryFromString];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSArray *devices = [self deviceList];
    if (devices.count > 0)
    {
        _firstDevice =  devices[0];
        _firstDeviceID = _firstDevice[@"UniqueDeviceID"];
        DLog(@"_firstDevice: %@", _firstDevice);
    }
   
    [self getValidProfilesWithCompletionBlock:^(NSArray *validProfiles) {
        
        //DLog(@"validProfiles; %@", validProfiles);
        _validProfiles = validProfiles;
        
    }];
    
    //DLog(@"dcf: %@", [iReSignAppDelegate devCertsFull]);
    
    
    certComboBoxItems = [NSMutableArray arrayWithArray:[iReSignAppDelegate devCertsFull]];
    
    [certComboBox reloadData];
    
    
    if ([defaults valueForKey:@"CERT_INDEX"]) {
        
        NSInteger selectedIndex = [[defaults valueForKey:@"CERT_INDEX"] integerValue];
        if (selectedIndex != -1) {
            NSString *selectedItem = [self comboBox:certComboBox objectValueForItemAtIndex:selectedIndex];
            [certComboBox setObjectValue:selectedItem];
            [certComboBox selectItemAtIndex:selectedIndex];
        }
        
        [self enableControls];
    } else {
        NSString *selectedItem = [self comboBox:certComboBox objectValueForItemAtIndex:0];
        [certComboBox setObjectValue:selectedItem];
        [certComboBox selectItemAtIndex:0];
    }
    
    [flurry setAlphaValue:0.5];
    
    defaults = [NSUserDefaults standardUserDefaults];
    
    // Look up available signing certificates
   // [self getCerts];
    
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
    
    
    //start my additions for scp / tvOS additions.
    
    //nsarray controller that handles available devices
    deviceController = [[ATVDeviceController alloc] init];
    //variables that was a carry over from code i migrated this from, can probably be pruned, dont think i use it.
    appleTVAddress = APPLE_TV_ADDRESS;
    
    NSLog(@"appleTVAddress: %@", appleTVAddress);
    
    if ([[appleTVAddress componentsSeparatedByString:@":"] count] < 2)
    {
        [self resetServerSettings];
        
    }
    
    
    //this check was to make sure if we have a default address saves that its currently available..
    //however if they arent using AirPlay or manually put in an IP address this check was bogus.
    
    /*
     if (appleTVAddress != nil)
     {
     
     if (![self hostAvailable])
     {
     NSLog(@"host not available? resetting!");
     [self resetServerSettings];
     }
     
     }
     */
    
    
    
}

- (BOOL)profileMatchesCert
{
  
    NSString *provisioningProfileFile = [provisioningPathField stringValue];
    if (provisioningProfileFile.length == 0) //
    {
        return YES;
    }
    NSInteger selectedIndex = [certComboBox indexOfSelectedItem];
    NSString *selectedItem = [self comboBox:certComboBox objectValueForItemAtIndex:selectedIndex];
    NSDictionary *profileDict = [iReSignAppDelegate provisioningDictionaryFromFilePath:provisioningProfileFile];
    if ([profileDict[@"CODE_SIGN_IDENTITY"] isEqualToString:selectedItem])
    {
        return YES;
    }
    
    return NO;
}


- (IBAction)resign:(id)sender {
    
    /*
     
     Some extra idiot proofing to make sure that the provisioning profile chosen matches the certificate chosen.
     
     */
    
    
    NSString *provisioningProfileFile = [provisioningPathField stringValue];
    if (provisioningProfileFile.length > 0) //if there is no provisioning profile, likey doing the self signing path.
    {
        NSInteger selectedIndex = [certComboBox indexOfSelectedItem];
        NSString *selectedItem = [self comboBox:certComboBox objectValueForItemAtIndex:selectedIndex];
        _provisioningProfileDict = [iReSignAppDelegate provisioningDictionaryFromFilePath:provisioningProfileFile];
       // DLog(@"profileDict: %@", _provisioningProfileDict);
        if (![_provisioningProfileDict[@"CODE_SIGN_IDENTITY"] isEqualToString:selectedItem])
        {
            
            NSAlert *mismatchAlert = [NSAlert alertWithMessageText:@"Profile/Cert Mistmatch" defaultButton:@"Select Certificate" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"The selected certificate name: '%@' does not match the certificate in the provisioning profile! '%@'", selectedItem, _provisioningProfileDict[@"CODE_SIGN_IDENTITY"]];
            
            //NSInteger index = [certComboBox indexOfItemWithObjectValue:profileDict[@"CODE_SIGN_IDENTITY"]];
            NSModalResponse returnValue =  [mismatchAlert runModal];
            if (returnValue == 1)
            {
                NSInteger index = [self comboBox:certComboBox indexOfObjectValue:_provisioningProfileDict[@"CODE_SIGN_IDENTITY"]];
                if (index != NSNotFound)
                {
                    [certComboBox selectItemAtIndex:index];
                } else {
                    return;
                }
            }
        }
    }

    
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
                NSLog(@"processing deb file: %@", sourcePath);
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
            
            [self _getBundleID];
            
            NSLog(@"bundle id: %@", self.bundleID);
            
            if (_provisioningProfileDict != nil)
            {
                NSString *provBundleId = _provisioningProfileDict[@"Entitlements"][@"application-identifier"];
                NSString *prefix = _provisioningProfileDict[@"ApplicationIdentifierPrefix"][0];
                DLog(@"bundle id: %@ prefix: %@", provBundleId, prefix);
                NSRange theRange = [provBundleId rangeOfString:[NSString stringWithFormat:@"%@.", prefix]];
                NSInteger location = theRange.location + theRange.length;
                NSString *rawbundle = [provBundleId substringFromIndex:location];
                
                //wildcard check
                if ([rawbundle rangeOfString:@"*"].location == NSNotFound)
                {
                    //automagically set it!
                    if (![self.bundleID isEqualToString:rawbundle])
                    {
                        [changeBundleIDCheckbox setState:NSOnState];
                        bundleIDField.stringValue = rawbundle;
                    }
                }
                
               if (_firstDeviceID != nil)
               {
                   NSArray *provisionedDevices = _provisioningProfileDict[@"ProvisionedDevices"];
                   if (![provisionedDevices containsObject:_firstDeviceID])
                   {
                       DLog(@"profile is missing first device udid!");
                       NSAlert *theAlert = [NSAlert alertWithMessageText:@"Profile missing device UUID" defaultButton:@"Ignore" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"The UUID for the device '%@' is missing from this provisioning profile!\n\nIf this is the target device please update your provisioning profile to include the UUID:\n\n%@", _firstDevice[@"DeviceName"], _firstDeviceID];
                       
                       NSInteger modalRet = [theAlert runModal];
                       if (modalRet != 1)
                       {
                           [self enableControls];
                           [statusLabel setStringValue:@"Ready"];
                           return;
                       }
                       
                   } else {
                       DLog(@"udid: %@ found!", _firstDeviceID);
                   }
               }
                
                
                
                
                
                
            }
            
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

- (void)_getBundleID
{
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[workingPath stringByAppendingPathComponent:kPayloadDirName] error:nil];
    NSString *infoPlistPath = nil;
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            infoPlistPath = [[[workingPath stringByAppendingPathComponent:kPayloadDirName]
                              stringByAppendingPathComponent:file]
                             stringByAppendingPathComponent:kInfoPlistFilename];
            NSDictionary *bundleDict = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
            self.bundleID = bundleDict[kKeyBundleIDPlistApp];
            break;
        }
    }
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
    DLog(@"entitlementsResultL %@", entitlementsResult);
    NSDictionary* entitlements = [[entitlementsResult plistSafeString] dictionaryFromString];
    
    DLog(@"here: %@", entitlements);
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
    NSLog(@"doCodeSigning");
    appPath = nil;
    frameworksDirPath = nil;
    hasFrameworks = NO;
    frameworks = [[NSMutableArray alloc] init];
    /*
    NSString *path = [workingPath stringByAppendingPathComponent:kPayloadDirName];
    DLog(@"path: %@", path);
    
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[workingPath stringByAppendingPathComponent:kPayloadDirName] error:nil];
    
     for (NSString *file in dirContents) {
     if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
         appPath = [[workingPath stringByAppendingPathComponent:kPayloadDirName] stringByAppendingPathComponent:file];
         appName = file;
     }
     }
     */
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
            
            //bit of a kludge to make sure we sign appex topshelf plugins for tvOS is applicable
            //just add the file to the frameworks array
            
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
            
            [statusLabel setStringValue:[NSString stringWithFormat:@"Codesigning %@",file.lastPathComponent]];
            break;
        }
    }
    
    
    
    
    
        //NSString *thePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Kodi.app"];
        NSFileManager *man = [NSFileManager defaultManager];
        NSArray *fileArray = [man subpathsOfDirectoryAtPath:appPath error:nil];
        NSArray *signedExtensions = @[@"py", @"so", @"dylib", @"appex"];
        for (NSString *file in fileArray)
        {
            NSString *lcpe = [[file pathExtension] lowercaseString];
            if ([signedExtensions containsObject:lcpe] || [man isExecutableFileAtPath:file])
            {
                NSString *fullFile = [appPath stringByAppendingPathComponent:file];
                [frameworks addObject:fullFile];
            }
        }
        
        
        
     
    
    
    
    NSLog(@"frameworks: %@ count: %lu", frameworks, frameworks.count);
    
    
    if (appPath) {
        if (hasFrameworks) {
            [self signFile:[frameworks lastObject]];
            [frameworks removeLastObject];
        } else {
            
            
            
            [self signFile:[appPath stringByAppendingPathComponent:exePath]];
        }
    }
}

- (void)signFile:(NSString*)filePath {
    NSLog(@"Codesigning %@", filePath);
    [statusLabel setStringValue:[NSString stringWithFormat:@"Codesigning %@",filePath.lastPathComponent]];
    
    NSString *hashValue = [[certComboBoxItems objectAtIndex:[certComboBox indexOfSelectedItem]] valueForKey:@"hash"];
    
    //NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"-fs", [certComboBox objectValue], nil];
    NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"-fs", hashValue, nil];
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
    
    DLog(@"/usr/bin/codesign %@", [arguments componentsJoinedByString:@" "]);
    
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
            //[self signFile:[appPath stringByAppendingPathComponent:exePath]];
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
        [statusLabel setStringValue:@"Finished"];
        [self enableControls];
        /*
        
        [statusLabel setStringValue:@"Checking for AppSync unified..."];
        
        if ([self hasASU] == true && INSTALL_ON_ATV == true)
        {
            NSLog(@"APPLE_TV_ADDRESS: %@", APPLE_TV_ADDRESS);
            [statusLabel setStringValue:[NSString stringWithFormat:@"Uploading file %@...", fileName]];
            
            //[DEFAULTS setValue:@"192.168.0.4:22" forKey:ATV_HOST];
            
            [self installFile:finalDestination withCompletionBlock:^(BOOL success) {
                
                [self enableControls];
                if (success == true)
                {
                    [statusLabel setStringValue:@"Application installed successfully!?"];
                } else {
                    [statusLabel setStringValue:@"Application install failed!?"];
                    [self showFailureAlert];
                    
                }
                
            }];
            
        } else if(INSTALL_ON_ATV == true){
            
            [statusLabel setStringValue:@"AppSync unified not found"];
            
            [self enableControls];
        } else {
            
            [statusLabel setStringValue:@"Finished"];
            [self enableControls];
        }
        
        */
        
        
        
    }
}

- (void)showFailureAlert
{
    NSAlert *failAlert = [NSAlert alertWithMessageText:@"Installation failed!" defaultButton:@"Open Logs" alternateButton:@"Ignore" otherButton:nil informativeTextWithFormat:@"The installation of app bundle %@ failed, would you like to read the related error logs?", self.bundleID];
    
    NSString *errorLog = [[self logLocation] stringByAppendingFormat:@"/%@.log", self.bundleID];
    NSString *syslog = [[self logLocation] stringByAppendingPathComponent:@"syslog.log"];
    
    NSModalResponse reponse = [failAlert runModal];
    
    switch (reponse) {
        case NSModalResponseOK:
            
            NSLog(@"read the logs?");
            
            [[NSWorkspace sharedWorkspace] openFile:errorLog];
            [[NSWorkspace sharedWorkspace] openFile:syslog];
            
            break;
            
        default:
            break;
    }
}

- (IBAction)checkSyslog:(id)sender
{
    [self downloadSyslogAndShow:true];
}

- (IBAction)showLogFolder:(id)sender
{
    [[NSWorkspace sharedWorkspace] selectFile:[self logLocation] inFileViewerRootedAtPath:[[self logLocation] stringByDeletingLastPathComponent]];
}

- (void)installFile:(NSString *)theFile withCompletionBlock:(void(^)(BOOL success))completionBlock
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        @autoreleasepool {
            
            BOOL success = FALSE;
            
            if ([self uploadFile:finalDestination toPath:@"/var/mobile/Documents"] == true)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    [statusLabel setStringValue:[NSString stringWithFormat:@"Installing file %@...", fileName]];
                    
                });
                
                /*
                 
                 Massively kludgy but it works, for some reason when appinst runs it doesnt go to stdout (or something) so i /need/ to redirect it to a text file, then cat that text file to check for whether or not "installed <bundle_id>" exists
                 
                 */
                
                NSString *checkResponse = [NSString stringWithFormat:@"installed %@", self.bundleID];
                
                NSString *runLine = [NSString stringWithFormat:@"/usr/bin/appinst /var/mobile/Documents/%@ 2> install.txt ; cat install.txt", fileName];
                //NSString *runLine = [NSString stringWithFormat:@"/usr/bin/appinst /var/mobile/Documents/%@", fileName];
                
                NSString *response =  [self sendCommandString:runLine];
                
                //using rangeOfString because containsString is too new for backwards compat.
                
                if ([response rangeOfString:checkResponse].location == NSNotFound)
                {
                    
                    NSString *errorLog = [[self logLocation] stringByAppendingFormat:@"/%@.log", self.bundleID];
                    
                    //remove old copies
                    if ([FM fileExistsAtPath:errorLog])
                    {
                        [FM removeItemAtPath:errorLog error:nil];
                    }
                    
                    //the response above has a bunch of garbled text in it, download the install file "proper" to get the cleaner version
                    
                    BOOL downloadFile = [sshSession downloadFile:@"/var/root/install.txt" to:errorLog error:nil];
                    if (downloadFile == false)
                    {
                        
                        //if that fails for some reason write the version with the garbage at the end
                        
                        [response writeToFile:errorLog atomically:true encoding:NSUTF8StringEncoding error:nil];
                        
                    }
                    
                    response = [NSString stringWithContentsOfFile:errorLog encoding:NSUTF8StringEncoding error:nil];
                    NSLog(@"INSTALLATION FAILED WITH LOG: %@", response);
                    
                    //grab latest relevant syslog chunk
                    [self downloadSyslogAndShow:false];
                    
                } else {
                    runLine = [NSString stringWithFormat:@"/bin/rm /var/mobile/Documents/%@", fileName];
                    [self sendCommandString:runLine];
                    success = true;
                }
                
                
            }
            
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                
                completionBlock(success);
                
                
                
            });
            
        }
        
    });
}

- (NSString *)logLocation
{
    NSString *location = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/iReSign"];
    if (![FM fileExistsAtPath:location])
    {
        [FM createDirectoryAtPath:location withIntermediateDirectories:true attributes:nil error:nil];
    }
    return location;
}



- (BOOL)downloadSyslogAndShow:(BOOL)show
{
    BOOL getSession = [self connectToSSH];
    if (getSession == FALSE)
    {
        NSLog(@"failed to get session!");
        return false;
    }
    NSError *error = nil;
    NSString *newSyslog = [[self logLocation] stringByAppendingPathComponent:@"syslog.log"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:newSyslog])
    {
        [[NSFileManager defaultManager] removeItemAtPath:newSyslog error:nil];
    }
    //echo latest syslog output to a new file for downloadin..
    [self sendCommandString:@"syslog > syslog.log"];
    BOOL downloadFile = [sshSession downloadFile:@"/var/root/syslog.log" to:newSyslog error:&error];
    if (downloadFile)
    {
        NSLog(@"File downloaded Successfully!");
        if (show == true)
        {
            [[NSWorkspace sharedWorkspace] openFile:newSyslog];
        }
        return true;
    }
    return false;
}

/**
 
 This method runs unzip on the file twice, onces to get its file listings to root out *.app/Info.plist and 
 the second time to pipe Info.plist into memory for our uses later.
 
 */

- (NSDictionary *)plistFromIPA:(NSString *)theFile withPath:(NSString *)path
{
    NSTask *swVers = [[NSTask alloc] init];
    NSPipe *swp = [[NSPipe alloc] init];
    NSFileHandle *swh = [swp fileHandleForReading];
    [swVers setLaunchPath:@"/usr/bin/unzip"];
    [swVers setArguments:@[@"-j", @"-p", theFile, path]];
    [swVers setStandardOutput:swp];
    [swVers setStandardError:swp];
    [swVers launch];
    [swVers waitUntilExit];
    NSData *outData = nil;
    outData = [swh readDataToEndOfFile];
    NSString *error = nil;
    NSPropertyListFormat format;
    return [NSPropertyListSerialization propertyListFromData:outData
                                     mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                               format:&format
                                     errorDescription:&error];
    
   
    
}

- (NSDictionary *)infoDictionaryFromIPA:(NSString *)theFile
{
    //get the path of the Info.plist file from the IPA
    NSString *proccessString = [NSString stringWithFormat:@"/usr/bin/unzip -l %@ | grep .app/Info.plist", theFile];
    //run process string
    NSString *returnFromUnzip = [[iReSignAppDelegate returnForProcess:proccessString] lastObject];
    //isolate the actual Info.plist path in the archive
    NSString *infoPlistPath = [[returnFromUnzip componentsSeparatedByString:@" "] lastObject];
    DLog(@"infoPlistPath: %@", infoPlistPath);
    //pipe the Info.plist into the return value
    
    return [self plistFromIPA:theFile withPath:infoPlistPath];
    proccessString = [NSString stringWithFormat:@"/usr/bin/unzip -j -p %@ %@", theFile, infoPlistPath];
    
    DLog(@"processString: %@", proccessString);
    NSArray *returnPr = [iReSignAppDelegate returnForProcess:proccessString];
    DLog(@"ReturnPR: %@", returnPr);
    return [[returnPr componentsJoinedByString:@"\n"] dictionaryFromString];
}

/*
 
 This method tries to capture the information of the Info.plist first and then checks our profiles
 to see if one applies to the project using the bundleID if that fails it looks for wildcard profiles
 
 
 */

- (void)attemptAutoSelectProfileForIPA:(NSString *)theFile
{
    DLOG_SELF;
    _infoDict = [self infoDictionaryFromIPA:theFile];
    //DLog(@"infoDicT: %@", _infoDict);
    if (_infoDict != nil)
    {
        exePath = _infoDict[@"CFBundleExecutable"];
        DLog(@"exePath: %@", exePath);
     
        //the first check for profiles that have matching bundleID (applicationIdentifier)
        
        NSPredicate *filterPredicate = [NSPredicate predicateWithFormat:@"(applicationIdentifier contains %@)", self.bundleID];
        NSArray *filteredArray = [_validProfiles filteredArrayUsingPredicate:filterPredicate];
        //DLog(@"filtered array: %@", filteredArray);
        
        if (filteredArray.count == 0) //failed to find a profile with matching app id, search for wildcard
        {
            filterPredicate = [NSPredicate predicateWithFormat:@"(applicationIdentifier contains %@)", @"*"];
            filteredArray = [_validProfiles filteredArrayUsingPredicate:filterPredicate];
            //DLog(@"wildcard filtered array: %@", filteredArray);
            
            //if there is a device plugged in we check to see if its deviceID exists in any of the valid profiles
            if (_firstDeviceID.length > 0)
            {
                filterPredicate = [NSPredicate predicateWithFormat:@"(ProvisionedDevices contains %@)", _firstDeviceID];
                filteredArray = [_validProfiles filteredArrayUsingPredicate:filterPredicate];
                //DLog(@"device filtered array: %@", filteredArray);
                if (filteredArray.count > 0)
                {
                    _provisioningProfileDict = filteredArray[0];
                    dispatch_async(dispatch_get_main_queue(), ^{
                    
                    provisioningPathField.stringValue = _provisioningProfileDict[@"Path"];
                   [self syncCertToProfile];
                        });
                    
                }
            } else { //no devices plugged in or detected, just choose the first valid profile
                
                
                if (filteredArray.count > 0)
                {
                    _provisioningProfileDict = filteredArray[0];
                    provisioningPathField.stringValue = _provisioningProfileDict[@"Path"];
                    [self syncCertToProfile];
                }
                
            }
        } else { //we did find a profile that matches the app id
            _provisioningProfileDict = filteredArray[0];
            provisioningPathField.stringValue = _provisioningProfileDict[@"Path"];
            [self syncCertToProfile];
        }
        
    }
 //proccessString = [NSString stringWithFormat:@"/usr/bin/unzip -l %@ | grep .app/Info.plist", theFile];
}

- (void)syncCertToProfile
{
  
        NSInteger selectedIndex = [certComboBox indexOfSelectedItem];
        DLog(@"selected index: %lu", selectedIndex);
        NSString *selectedItem = [self comboBox:certComboBox objectValueForItemAtIndex:selectedIndex];
        DLog(@"selected item: %@", selectedItem);
    DLog(@"prov %@", _provisioningProfileDict[@"CODE_SIGN_IDENTITY"] );
        if (![_provisioningProfileDict[@"CODE_SIGN_IDENTITY"] isEqualToString:selectedItem])
        {
            NSInteger index = [self comboBox:certComboBox indexOfObjectValue:_provisioningProfileDict[@"CODE_SIGN_IDENTITY"]];
            DLog(@"index: %lu", index);
            if (index != NSNotFound)
            {
                DLog(@"selecting it and shit");
                [certComboBox selectItemAtIndex:index];
            }
        }
    
   
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
        
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"autoSelect"] == YES)
        {
            if ([[[fileNameOpened pathExtension] lowercaseString] isEqualToString:@"ipa"])
            {
               // dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    [self attemptAutoSelectProfileForIPA:fileNameOpened];
               // });
                
                // [self extractInfoPlistFromFile:fileNameOpened];
            }
        }
      
        
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

- (NSInteger)comboBox:(NSComboBox *)aComboBox indexOfObjectValue:(NSString *)objectValue
{
    //[self comboBox:certComboBox objectValueForItemAtIndex:selectedIndex]
    int i = 0;
    for (i = 0; i < aComboBox.numberOfItems; i++){
        NSString * value = [self comboBox:certComboBox objectValueForItemAtIndex:i];
        if ([value isEqualToString:objectValue]){
            return i;
        }
    }
    return [certComboBoxItems indexOfObject:objectValue];
}


- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index {
    NSDictionary *item = nil;
    if ([aComboBox isEqual:certComboBox]) {
        item = [certComboBoxItems objectAtIndex:index];
    }
    return item[@"name"];
}

//obsolete

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

#pragma mark kevins additions for JB tvOS & appsync

#pragma mark extraction methods

/**
 
 https://blogs.oracle.com/ksplice/entry/anatomy_of_a_debian_package
 
 long story short this is an easier way to make sure dpkg-deb isnt required
 
 ar -x will dump the contents of the deb file (control.tar.gz and data.tar.*)
 
 from there we don't care about the control file but we DO care about the data.tar.* file
 
 
 */

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

/**
 
 Run the app binary through lipo to make sure its arm64
 
 */


- (BOOL)applicationTVOSCompat:(NSString *)appFolder
{
    BOOL isCompat = false;
    
    NSDictionary *infoDict = [NSDictionary dictionaryWithContentsOfFile:[appFolder stringByAppendingPathComponent:@"Info.plist"]];
    NSString *executablePath = [appFolder stringByAppendingPathComponent:infoDict[@"CFBundleExecutable"]];
    
    // self.bundleID = infoDict[kKeyBundleIDPlistApp];
    NSString *lipoInfo = [self stringReturnForTask:@"/usr/bin/lipo" withArguments:@[@"-info", executablePath]];
    if ([lipoInfo rangeOfString:@"arm64"].location != NSNotFound)
    {
        isCompat = true;
    }
    return isCompat;
}

- (NSString *)stringReturnForTask:(NSString *)taskBinary withArguments:(NSArray *)taskArguments
{
    NSLog(@"%@ %@", taskBinary, [taskArguments componentsJoinedByString:@" "]);
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [[NSPipe alloc] init];
    NSFileHandle *handle = [pipe fileHandleForReading];
    
    [task setLaunchPath:taskBinary];
    [task setArguments:taskArguments];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];
    
    [task launch];
    
    NSData *outData = nil;
    NSString *temp = nil;
    while((outData = [handle readDataToEndOfFile]) && [outData length])
    {
        temp = [[NSString alloc] initWithData:outData encoding:NSASCIIStringEncoding];
        
    }
    [handle closeFile];
    task = nil;
    
    return temp;
    
}

- (int)extractLZMA:(NSString *)inputFile toPath:(NSString *)theLocation
{
    NSTask *tarTask = [[NSTask alloc] init];
    
    [tarTask setLaunchPath:@"/usr/bin/tar"];
    [tarTask setArguments:[NSArray arrayWithObjects:@"-xpv", @"--lzma", @"-f", inputFile ,@"-C", theLocation, nil]];
    // NSFileHandle *nullOut = [NSFileHandle fileHandleWithNullDevice];
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
    NSLog(@"/usr/bin/tar -xpzv -f %@ -C %@", inputTar, toLocation);
    NSTask *tarTask = [[NSTask alloc] init];
    
    [tarTask setLaunchPath:@"/usr/bin/tar"];
    [tarTask setArguments:[NSArray arrayWithObjects:@"-xpzv", @"-f", inputTar,@"-C", toLocation, nil]];
    //NSFileHandle *nullOut = [NSFileHandle fileHandleWithNullDevice];
    
    //[tarTask setStandardError:nullOut];
    //[tarTask setStandardOutput:nullOut];
    [tarTask launch];
    [tarTask waitUntilExit];
    
    int theTerm = [tarTask terminationStatus];
    
    tarTask = nil;
    return theTerm;
    
}

/*
 
 the method called when a user selects a deb rather than an IPA or xcarchive
 
 extracts the deb and moves /Applications into /Payload in workingPath if applicable
 
 */

- (void)processDeb:(NSString *)debFile withCompletionBlock:(void(^)(BOOL success))completionBlock
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        @autoreleasepool {
            
            BOOL success = false;
            
            //make a tmp dir to deal with our dpkg file
            NSString *tmpPath = [workingPath stringByAppendingPathComponent:@"tmp"];
            [FM createDirectoryAtPath:tmpPath withIntermediateDirectories:true attributes:nil error:nil];
            
            //dump the deb
            int status = [self extractDeb:debFile toPath:tmpPath];
            
            //deb files generally have a .lzma file or a .gz file, check to see which.
            
            NSString *newPath = [tmpPath stringByAppendingPathComponent:@"data.tar.lzma"];
            if (![FM fileExistsAtPath:newPath])
            {
                NSLog(@"no lzma file found, looking for xz");
                newPath = [tmpPath stringByAppendingPathComponent:@"data.tar.xz"];
            }
            if (![FM fileExistsAtPath:newPath])
            {
                NSLog(@"no xz file found, looking for gz");
                newPath = [tmpPath stringByAppendingPathComponent:@"data.tar.gz"];
            }
            
            
            if ([FM fileExistsAtPath:newPath])
            {
                
                
                NSLog(@"found archive: %@", newPath);
                NSString *ext = [[newPath pathExtension] lowercaseString];
                if ([ext isEqualToString:@"lzma"] || [ext isEqualToString:@"xz"])
                {
                    status = [self extractLZMA:newPath toPath:tmpPath];
                } else {
                    status = [self gunZip:newPath toLocation:tmpPath];
                }
                
                //check to see if there is an Applications folder, otherwise this deb is useless.
                
                NSString *applicationDir = [tmpPath stringByAppendingPathComponent:@"private/var/mobile/Applications"];
                if ([FM fileExistsAtPath:applicationDir])
                {
                    
                    NSString *theAppName = [[FM contentsOfDirectoryAtPath:applicationDir error:nil] lastObject];
                    applicationDir = [applicationDir stringByAppendingPathComponent:theAppName];
                    NSLog(@"found application dir: %@", applicationDir);
                    
                    //idiot proofing to make sure no one tries to load older bins that arent tvOS compat.
                    
                    if ([self applicationTVOSCompat:applicationDir])
                    {
                        //create the payload folder that we will copy the Application over into
                        NSString *tmpPayload = [workingPath stringByAppendingPathComponent:@"Payload"];
                        [FM createDirectoryAtPath:tmpPayload
                      withIntermediateDirectories:true attributes:nil error:nil];
                        
                        //move *Applications/*.app over to workingPath/Payload/*.app
                        
                        [FM moveItemAtPath:applicationDir toPath:[tmpPayload stringByAppendingPathComponent:theAppName] error:nil];
                        
                        //crucial to remove the tmp dir! EVERYTHING in workingPath gets zipped into final IPA
                        [FM removeItemAtPath:tmpPath error:nil];
                        success = true;
                    } else {
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            
                            [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"This debian file does not contain an arm64 binary, it will not work on tvOS"];
                            [self enableControls];
                            [statusLabel setStringValue:@"Ready"];
                            
                            
                            
                        });
                        
                    }
                    
                    
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

//currently unused

- (BOOL)hostAvailable
{
    NSMutableURLRequest *request = [self hostAvailableRequest];
    NSHTTPURLResponse * theResponse = nil;
    NSError *theError = nil;
    NSData *returnData = [NSURLConnection sendSynchronousRequest:request returningResponse:&theResponse error:&theError];
    //  NSString *datString = [[NSString alloc] initWithData:returnData  encoding:NSUTF8StringEncoding];
    //NSLog(@"datString: %@", datString);
    if (theError != nil)
    {
        NSLog(@"theResponse: %li theError; %@", (long)[theResponse statusCode], theError);
        return (FALSE);
    }
    
    return (TRUE);
    
}

- (NSMutableURLRequest *)hostAvailableRequest
{
    /*
     
     was thinking this could be a valid way to check for a host, but just realized if they put in
     an IP address manually thats because AirPlay is probably off...
     
     the thinking was take the ip, swap the port with airplay port and then check for server info,
     if it returns successfully, our host is available.
     
     */
    NSString *baseIP = [[APPLE_TV_ADDRESS componentsSeparatedByString:@":"] firstObject];
    baseIP = [baseIP stringByAppendingString:@":7000"];
    NSString *httpCommand = [NSString stringWithFormat:@"http://%@/server-info", baseIP];
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

//check to see if the AppleTV selected has AppSync unified by checking for /usr/bin/appinst

- (BOOL)hasASU
{
    NSString *theReturn = [self sendCommandString:@"ls /usr/bin/ | grep appinst"];
    if (theReturn != nil)
    { return (TRUE);
    } else { return (FALSE);}
    
    return (FALSE);
}

//even if we are using the wrong password this should still at least attempt to connect with "Failed to connect" error returned

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

//currently unused

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

//if they changed password from alpine this is used to get the proper password to connect

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

//add a password to the keychain for SSH

- (void)addkeychainPassword:(NSString *)password
{
    //kSecProtocolTypeSSH
    [EMInternetKeychainItem addInternetKeychainItemForServer:APPLE_TV_ADDRESS	withUsername:@"root" password:password path:@"/usr/bin/ssh" port:22 protocol:kSecProtocolTypeSSH];
}

//fetch the password from the keychain for the specified ip address

- (NSString *)passwordForHost:(NSString *)ipAddress
{
    EMInternetKeychainItem *keychainItem = [EMInternetKeychainItem internetKeychainItemForServer:ipAddress withUsername:@"root" path:@"/usr/bin/ssh" port:22 protocol:kSecProtocolTypeSSH];
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

- (BOOL)uploadFile:(NSString *)theFile toPath:(NSString *)newPath
{
    NSLog(@"uploading file: %@", theFile);
    NSError *error = nil;
    BOOL getSession = [self connectToSSH];
    if (getSession == FALSE)
    {
        NSLog(@"failed to get session!");
        return (FALSE);
    }
    
    NSString *finalPath = [newPath stringByAppendingPathComponent:[theFile lastPathComponent]];
    
    BOOL uploadFile = [sshSession uploadFile:theFile to:finalPath error:&error];
    if (error)
    {
        NSLog(@"ERROR!: %@", error);
    }
    return (uploadFile);
    
}


//upload a file over SSH to the selected AppleTV

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

//used to send basic commands to the jailbroken AppleTV over SSH

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

//open the SSH session

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


+ (NSArray *)certIDsFromCerts:(NSArray *)devCerts
{
    NSMutableArray *certIDs = [NSMutableArray new];
    
    for (NSData *devCert in devCerts)
    {
        //the origin offset of iPhone Developer: / iPhone Distribution / 3rd Party Mac Developer Application: appears to be the same in ever raw cert
        //we grab way too much data on purpose since we have no idea how long the names appended will be.
        NSData *userData = [devCert subdataWithRange:NSMakeRange(0x00109, 100)];
        
        NSString *stringData = [[NSString alloc] initWithData:userData encoding:NSASCIIStringEncoding];
        //grab all the way up to ), split, grab first object, readd ) could probably do a range of string thing here too.. this works tho.
        NSString *devName = [[[stringData componentsSeparatedByString:@")"] firstObject] stringByAppendingString:@")"];
        if (![certIDs containsObject:devName]) //dont add any repeats
        {
            [certIDs addObject:devName];
        }
    }
    return certIDs;
}

+ (NSMutableDictionary *)provisioningDictionaryFromFilePath:(NSString *)profilePath
{
    NSString *fileContents = [NSString stringWithContentsOfFile:profilePath encoding:NSASCIIStringEncoding error:nil];
    NSUInteger fileLength = [fileContents length];
    if (fileLength == 0)
        fileContents = [NSString stringWithContentsOfFile:profilePath]; //if ascii doesnt work, have to use the deprecated (thankfully not obsolete!) method
    
    fileLength = [fileContents length];
    if (fileLength == 0)
        return nil;
    
    //find NSRange location of <?xml to pass by all the "garbage" data before our plist
    
    NSUInteger startingLocation = [fileContents rangeOfString:@"<?xml"].location;
    
    //find NSRange of the end of the plist (there is "junk" cert data after our plist info as well
    NSRange endingRange = [fileContents rangeOfString:@"</plist>"];
    
    //adjust the location of endingRange to include </plist> into our newly trimmed string.
    NSUInteger endingLocation = endingRange.location + endingRange.length;
    
    //offset the ending location to trim out the "garbage" before <?xml
    NSUInteger endingLocationAdjusted = endingLocation - startingLocation;
    
    //create the final range of the string data from <?xml to </plist>
    
    NSRange plistRange = NSMakeRange(startingLocation, endingLocationAdjusted);
    
    //actually create our string!
    NSString *plistString = [fileContents substringWithRange:plistRange];
    
    //yay categories!! convert the dictionary raw string into an actual NSDictionary
    NSMutableDictionary *dict = [plistString dictionaryFromString];
    
    
    NSString *appID = [dict[@"Entitlements"] objectForKey:@"application-identifier"];
    
    [dict setObject:appID forKey:@"applicationIdentifier"];
    
    //since we will always need this data, best to grab it here and make it part of the dictionary for easy re-use / validity check.
    
    NSString *ourID = [self validIDFromCerts:dict[@"DeveloperCertificates"]];
    
    if (ourID != nil)
    {
        [dict setValue:ourID forKey:@"CODE_SIGN_IDENTITY"];
        //in THEORY should set the profile target to Debug or Release depending on if it finds "Developer:" string.
        if ([ourID rangeOfString:@"Developer:"].location != NSNotFound)
        {
            [dict setValue:@"Debug" forKey:@"Target"];
            
        } else {
            
            [dict setValue:@"Release" forKey:@"Target"];
        }
    }
    
    //grab all the valid certs, for later logging / debugging for why a profile might be invalid
    
    NSArray *validCertIds = [self certIDsFromCerts:dict[@"DeveloperCertificates"]];
    
    [dict setValue:validCertIds forKey:@"CodeSignArray"];
    
    // shouldnt need this frivolous data any longer, we know which ID (if any) we have and have all the valid ones too
    
    [dict removeObjectForKey:@"DeveloperCertificates"];
    
    
    
    //write to file for debug / posterity
    // [dict writeToFile:[[[self pwd] stringByAppendingPathComponent:dict[@"Name"]] stringByAppendingPathExtension:@"plist"] atomically:TRUE];
    
    return dict;
}

+ (NSString *)validIDFromCerts:(NSArray *)devCerts
{
    NSArray *validDevCerts = [self devCertsFull];
    for (NSData *devCert in devCerts)
    {
        for (NSDictionary *currentValidCertDict in validDevCerts)
        {
            NSString *currentValidCert = currentValidCertDict[@"name"];
            NSData *distroData = [currentValidCert dataUsingEncoding:NSUTF8StringEncoding];
            NSRange searchRange = NSMakeRange(0, devCert.length);
            NSRange dataRange = [devCert rangeOfData:distroData options:0 range:searchRange];
            if (dataRange.location != NSNotFound)
            {
                //DLog(@"found profile: %@", currentValidCert);
                return currentValidCert;
            }
        }
    }
    return nil;
}

+ (NSArray *)devCertsFull
{
    NSMutableArray *outputArray = [[NSMutableArray alloc ]init];
    NSArray *securityReturn = [self returnForProcess:@"security find-identity -p codesigning"];
    //DLog(@"securityReturn: %@", securityReturn);
    for (NSString *profileLine in securityReturn)
    {
        //DLog(@"profileLine: %@", profileLine);
        if (profileLine.length > 0)
        {
            NSArray *clips = [profileLine componentsSeparatedByString:@"\""];
            if ([clips count] > 1)
            {
                NSString *hash = [[[clips objectAtIndex:0] componentsSeparatedByString:@" "] objectAtIndex:1];
                //DLog(@"hash: %@", hash);
                
                NSString *name = [clips objectAtIndex:1];
                
                NSDictionary *certDict = @{@"hash": hash, @"name": name};
                
                if (![outputArray containsObject:certDict])
                {
                    [outputArray addObject:certDict];
                }
            }
        }
        
    }
    return outputArray;
}

+ (NSArray *)returnForProcess:(NSString *)call
{
    if (call==nil)
        return 0;
    char line[200];
    
    FILE* fp = popen([call UTF8String], "r");
    NSMutableArray *lines = [[NSMutableArray alloc]init];
    if (fp)
    {
        while (fgets(line, sizeof line, fp))
        {
            NSString *s = [NSString stringWithCString:line encoding:NSUTF8StringEncoding];
            s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            [lines addObject:s];
        }
    }
    pclose(fp);
    return lines;
}


- (NSString *)provisioningProfilesPath
{
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/MobileDevice/Provisioning Profiles"];
}

- (void)getValidProfilesWithCompletionBlock:(void(^)(NSArray *validProfiles))completionBlock
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        
        @autoreleasepool {
         
            NSMutableArray *profileArray = [NSMutableArray new];
            NSMutableArray *profileNames = [NSMutableArray new];
            NSString *profileDir = [self provisioningProfilesPath];
            NSArray *fileArray = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:profileDir error:nil];
            for (NSString *theObject in fileArray)
            {
                if ([[[theObject pathExtension] lowercaseString] isEqualToString:@"mobileprovision"])
                {
                    NSString *fullPath = [profileDir stringByAppendingPathComponent:theObject];
                    NSMutableDictionary *provisionDict = [iReSignAppDelegate provisioningDictionaryFromFilePath:
                                                          [profileDir stringByAppendingPathComponent:theObject]];
                    
                    NSString *csid = provisionDict[@"CODE_SIGN_IDENTITY"];
                    NSDate *expireDate = provisionDict[@"ExpirationDate"];
                    NSDate *createdDate = provisionDict[@"CreationDate"];
                    NSString *name = provisionDict[@"Name"];
                    [provisionDict setObject:fullPath forKey:@"Path"];
                    BOOL expired = FALSE;
                    
                    if ([expireDate isGreaterThan:[NSDate date]])
                    {
                        //     DLog(@"not expired: %@", expireDate);
                        
                    } else {
                        
                        //its expired, who cares about any of the other details. add it to the expired list.
                        
                        DLog(@"expired: %@\n", expireDate);
                        //[_expired addObject:provisionDict];
                        expired = TRUE;
                    }
                    
                    //check to see if our valid non expired certificates in our keychain are referenced by the profile, or if its expired
                    
                    if (csid == nil || expired == TRUE)
                    {
                        if (csid == nil)
                        {
                            
                            DLog(@"No valid codesigning identities found!!");
                            
                        } else {
                            
                            DLog(@"invalid or expired cert: %@\n", theObject );
                            
                        }
                    } else { //we got this far the profile is not expired and can be compared against other potential duplicates
                        
                        if ([profileNames containsObject:name]) //we have this profile already, is ours newer or is the one already in our collection newer?
                        {
                            NSDictionary *otherDict = [[profileArray subarrayWithName:name] objectAtIndex:0];
                            NSDate *previousCreationDate = otherDict[@"CreationDate"];
                            if ([previousCreationDate isGreaterThan:createdDate])
                            {
                                DLog(@"found repeat name, but we're older: %@ vs: %@\n", createdDate, previousCreationDate);
                                //    [_duplicates addObject:provisionDict];
                                
                            } else {
                                
                                DLog(@"found a newer profile: %@ replace the old one: %@\n", createdDate, previousCreationDate);
                                //   [_duplicates addObject:otherDict];
                                [profileArray removeObject:otherDict];
                                [profileArray addObject:provisionDict];
                            }
                            
                        } else {
                            
                            //we dont have this name on record and it should be a valid profile!
                            
                            [profileArray addObject:provisionDict];
                            [profileNames addObject:name];
                            
                        }
                        
                        
                    }
                }
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                
                completionBlock(profileArray);
                
                
                
            });
            
            
        }
        
    });
}




@end
