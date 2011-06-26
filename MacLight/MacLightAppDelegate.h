//
//  MacLightAppDelegate.h
//  MacLight
//
//  Created by skattyadz on 26/06/2011.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "OpenGLScreenReader.h"

// import IOKit headers
#include <IOKit/IOKitLib.h>
#include <IOKit/serial/IOSerialKeys.h>
#include <IOKit/IOBSD.h>
#include <IOKit/serial/ioss.h>
#include <sys/ioctl.h>



@interface MacLightAppDelegate : NSObject <NSApplicationDelegate> {
@private
    NSWindow *window;
    IBOutlet NSMenu *statusMenu;
    NSStatusItem *statusItem;
    IBOutlet NSMenuItem *captureMenuItem;
    IBOutlet NSMenuItem *manualMenuItem;
    
    NSString *selectedSerialPort;
    NSMutableArray *serialPortList;
    OpenGLScreenReader *mOpenGLScreenReader;
    
	struct termios gOriginalTTYAttrs; // Hold the original termios attributes so we can reset them on quit ( best practice )
	int serialFileDescriptor; // file handle to the serial port
    NSTimer *sampleTimer;
    bool capturing;
}
//
- (NSString *) openSerialPort: (NSString *)serialPortFile baud: (speed_t)baudRate;
- (void) loadSerialPortList;
- (void) writeColor: (NSColor *)color;
- (void) writeByte: (uint8_t *) val;
- (void) sampleScreen;
- (IBAction)startCapturing:(id)sender;
- (void)stopCapturing;
- (void) colorPicked:(NSColorWell *) picker;
- (IBAction) openColorPicker:(id)sender;
- (IBAction)closeApp:(id)sender;

@end