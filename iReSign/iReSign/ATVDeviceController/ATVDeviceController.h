/* ATVDeviceController */

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

@protocol ATVDeviceControllerDelegate <NSObject>

- (void)servicesFound:(NSArray *)services;

@end

@interface ATVDeviceController : NSObject <NSNetServiceBrowserDelegate>
{
	
	IBOutlet id hostNameField;
	IBOutlet id deviceList;
	IBOutlet id apiVersionLabel;
	IBOutlet id osVersionLabel;

    IBOutlet NSWindow *myWindow;
	IBOutlet NSPopUpButton *theComboBox;
	IBOutlet NSArrayController *deviceController;

    BOOL searching;
    NSNetServiceBrowser * browser;
    NSMutableArray * services;
    NSMutableData * currentDownload;
	NSArray *receivedFiles;
    NSDictionary *deviceDictionary;
	
	
}


@property (nonatomic, strong) IBOutlet NSPopUpButton *theComboBox;
@property (nonatomic, strong) NSArrayController *deviceController;

@property (readwrite, weak) id <ATVDeviceControllerDelegate> delegate;


- (NSDictionary *)deviceDictionary;

- (NSDictionary *)stringDictionaryFromService:(NSNetService *)theService;


- (IBAction)serviceClicked:(id)sender;
- (IBAction)menuItemSelected:(id)sender;
- (NSDictionary *)currentServiceDictionary;

@end
