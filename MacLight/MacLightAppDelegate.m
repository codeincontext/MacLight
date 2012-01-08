//
//  MacLightAppDelegate.m
//  MacLight
//
//  Created by skattyadz on 26/06/2011.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "MacLightAppDelegate.h"

@implementation MacLightAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {

}

-(void)awakeFromNib{
    statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength] retain];
    [statusItem setMenu:statusMenu];
    [statusItem setTitle:@"MacLight"];
    [statusItem setHighlightMode:YES];
    
    [startupMenuItem setState:[self isLaunchAtStartup]];
    
	// we don't have a serial port open yet
	serialFileDescriptor = -1;
	
	[self loadSerialPortList];
    
    for (NSString *serialPort in serialPortList) {
        NSLog(@"Found a port: %@", serialPort);
        if ([serialPort rangeOfString:@"usbserial"].location != NSNotFound || [serialPort rangeOfString:@"usbmodem"].location != NSNotFound) {
            selectedSerialPort = serialPort;
            NSLog(@"Found an arduino: %@", serialPort);
        }
    }
    [self openSerialPort: selectedSerialPort baud:9600];
    
//	[self startCapturing:nil];
}


CVReturn DisplayLinkCallback (
                                CVDisplayLinkRef displayLink,
                                const CVTimeStamp *inNow,
                                const CVTimeStamp *inOutputTime,
                                CVOptionFlags flagsIn,
                                CVOptionFlags *flagsOut,
                                void *displayLinkContext)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [(MacLightAppDelegate*) displayLinkContext sampleScreen];
    [pool release];
    return YES;
}

- (void)dealloc {
    CVDisplayLinkStop(displayLink);
    [super dealloc];
}


-(IBAction)closeApp:(id)sender{
    // Add a delay to ensure that it terminates at the top of the next pass through the event loop
    [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
}


- (void) loadSerialPortList {
	io_object_t serialPort;
	io_iterator_t serialPortIterator;
	
	serialPortList = [[NSMutableArray alloc] init];
	
	// ask for all the serial ports
	IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(kIOSerialBSDServiceValue), &serialPortIterator);
	
	// loop through all the serial ports and add them to the array
	while ((serialPort = IOIteratorNext(serialPortIterator))) {
		[serialPortList addObject:
         [(NSString*)IORegistryEntryCreateCFProperty(serialPort, CFSTR(kIOCalloutDeviceKey),  kCFAllocatorDefault, 0) autorelease]];
        
		IOObjectRelease(serialPort);
	}
		
	IOObjectRelease(serialPortIterator);
}


- (void)sampleScreen {
    NSAssert(mOpenGLScreenReader, @"No screen reader");
	NSColor *averageCol = [mOpenGLScreenReader readFullScreenToBuffer];
    [self writeColor:averageCol];
}


- (IBAction)startCapturing:(id)sender
{
    [captureMenuItem setState:NSOnState];
    [manualMenuItem setState:NSOffState];
    
    mOpenGLScreenReader = [[[OpenGLScreenReader alloc] init] retain];
	NSAssert( mOpenGLScreenReader != 0, @"OpenGLScreenReader alloc failed");
    
    CVReturn            error = kCVReturnSuccess;
    CGDirectDisplayID   displayID = CGMainDisplayID();
    
    error = CVDisplayLinkCreateWithCGDisplay(displayID, &displayLink);
    if(error)
    {
        NSLog(@"DisplayLink created with error:%d", error);
        displayLink = NULL;
    }
    error = CVDisplayLinkSetOutputCallback(displayLink, DisplayLinkCallback, self);
    if(error)
    {
        NSLog(@"DisplayLink callback creation failed with error:%d", error);
        displayLink = NULL;
    }
    
    if (displayLink){
        CVDisplayLinkStart(displayLink);
    }
}

- (void)stopCapturing {
    CVDisplayLinkStop(displayLink);
    
    if (sampleTimer) {
        [captureMenuItem setState:NSOffState];
        [manualMenuItem setState:NSOnState];
        [sampleTimer invalidate];
        [sampleTimer release];
        sampleTimer = nil;
        if (mOpenGLScreenReader){
            [mOpenGLScreenReader release];
            mOpenGLScreenReader = nil;
        }
    }
}
    
// open the serial port
//   - nil is returned on success
//   - an error message is returned otherwise
- (NSString *) openSerialPort: (NSString *)serialPortFile baud: (speed_t)baudRate {
	int success;
	
	// close the port if it is already open
	if (serialFileDescriptor != -1) {
		close(serialFileDescriptor);
		serialFileDescriptor = -1;
        
		// re-opening the same port REALLY fast will fail spectacularly... better to sleep a sec
		sleep(0.5);
	}
	
	// c-string path to serial-port file
	const char *bsdPath = [serialPortFile cStringUsingEncoding:NSUTF8StringEncoding];
	
	// Hold the original termios attributes we are setting
	struct termios options;
	
	// receive latency ( in microseconds )
	unsigned long mics = 3;
	
	// error message string
	NSString *errorMessage = nil;
	
	// open the port
	//     O_NONBLOCK causes the port to open without any delay (we'll block with another call)
	serialFileDescriptor = open(bsdPath, O_RDWR | O_NOCTTY | O_NONBLOCK );
	
	if (serialFileDescriptor == -1) { 
		// check if the port opened correctly
		errorMessage = @"Error: couldn't open serial port";
	} else {
		// TIOCEXCL causes blocking of non-root processes on this serial-port
		success = ioctl(serialFileDescriptor, TIOCEXCL);
		if ( success == -1) { 
			errorMessage = @"Error: couldn't obtain lock on serial port";
		} else {
			success = fcntl(serialFileDescriptor, F_SETFL, 0);
			if ( success == -1) { 
				// clear the O_NONBLOCK flag; all calls from here on out are blocking for non-root processes
				errorMessage = @"Error: couldn't obtain lock on serial port";
			} else {
				// Get the current options and save them so we can restore the default settings later.
				success = tcgetattr(serialFileDescriptor, &gOriginalTTYAttrs);
				if ( success == -1) { 
					errorMessage = @"Error: couldn't get serial attributes";
				} else {
					// copy the old termios settings into the current
					//   you want to do this so that you get all the control characters assigned
					options = gOriginalTTYAttrs;
					
					/*
					 cfmakeraw(&options) is equivilent to:
					 options->c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
					 options->c_oflag &= ~OPOST;
					 options->c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
					 options->c_cflag &= ~(CSIZE | PARENB);
					 options->c_cflag |= CS8;
					 */
					cfmakeraw(&options);
					
					// set tty attributes (raw-mode in this case)
					success = tcsetattr(serialFileDescriptor, TCSANOW, &options);
					if ( success == -1) {
						errorMessage = @"Error: coudln't set serial attributes";
					} else {
						// Set baud rate (any arbitrary baud rate can be set this way)
						success = ioctl(serialFileDescriptor, IOSSIOSPEED, &baudRate);
						if ( success == -1) { 
							errorMessage = @"Error: Baud Rate out of bounds";
						} else {
							// Set the receive latency (a.k.a. don't wait to buffer data)
							success = ioctl(serialFileDescriptor, IOSSDATALAT, &mics);
							if ( success == -1) { 
								errorMessage = @"Error: coudln't set serial latency";
							}
						}
					}
				}
			}
		}
	}
	
	// make sure the port is closed if a problem happens
	if ((serialFileDescriptor != -1) && (errorMessage != nil)) {
		close(serialFileDescriptor);
		serialFileDescriptor = -1;
	}
	
	return errorMessage;
}

- (void) writeColor: (NSColor *) color {
    [self writeByte:0x55];    
    [self writeByte:0xAA];
    
    int val;
    val = [color redComponent]*255*0.9;
    [self writeByte:val];
    
    val = [color greenComponent]*255;
    [self writeByte:val];
    
    val = [color blueComponent]*255;
    [self writeByte:val];
}

- (void) writeByte: (int)val {
	if(serialFileDescriptor!=-1) {
		write(serialFileDescriptor, &val, 1);
	} else {
		NSLog(@"Tried to write byte but no Serial Port found");
	}
}

- (IBAction) openColorPicker:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    [[NSColorPanel sharedColorPanel] setTarget:self];
	[[NSColorPanel sharedColorPanel] setAction:@selector(colorPicked:)];
	[[NSColorPanel sharedColorPanel] makeKeyAndOrderFront:nil];
}

- (void) colorPicked: (NSColorWell *) picker{
    [self stopCapturing];
    [self writeColor:picker.color];
}

// action sent when serial port selected
- (IBAction) serialPortSelected: (id) cntrl {
	// open the serial port
	NSString *error = [self openSerialPort: selectedSerialPort baud:9600];
	
	if(error!=nil) {
		NSLog(error);
	} else {
	}
}

- (BOOL)isLaunchAtStartup {
    // See if the app is currently in LoginItems.
    LSSharedFileListItemRef itemRef = [self itemRefInLoginItems];
    // Store away that boolean.
    BOOL isInList = itemRef != nil;
    // Release the reference if it exists.
    if (itemRef != nil) CFRelease(itemRef);
    
    return isInList;
}

- (IBAction)toggleLaunchAtStartup:(id)sender {
    // Toggle the state.
    BOOL shouldBeToggled = ![self isLaunchAtStartup];
    // Get the LoginItems list.
    LSSharedFileListRef loginItemsRef = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (loginItemsRef == nil) return;
    if (shouldBeToggled) {
        // Add the app to the LoginItems list.
        CFURLRef appUrl = (CFURLRef)[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
        LSSharedFileListItemRef itemRef = LSSharedFileListInsertItemURL(loginItemsRef, kLSSharedFileListItemLast, NULL, NULL, appUrl, NULL, NULL);
        if (itemRef) CFRelease(itemRef);
    }
    else {
        // Remove the app from the LoginItems list.
        LSSharedFileListItemRef itemRef = [self itemRefInLoginItems];
        LSSharedFileListItemRemove(loginItemsRef,itemRef);
        if (itemRef != nil) CFRelease(itemRef);
    }
    CFRelease(loginItemsRef);
    [sender setState:shouldBeToggled];
}

- (LSSharedFileListItemRef)itemRefInLoginItems {
    LSSharedFileListItemRef itemRef = nil;
    NSURL *itemUrl = nil;
    
    // Get the app's URL.
    NSURL *appUrl = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
    // Get the LoginItems list.
    LSSharedFileListRef loginItemsRef = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (loginItemsRef == nil) return nil;
    // Iterate over the LoginItems.
    NSArray *loginItems = (NSArray *)LSSharedFileListCopySnapshot(loginItemsRef, nil);
    for (int currentIndex = 0; currentIndex < [loginItems count]; currentIndex++) {
        // Get the current LoginItem and resolve its URL.
        LSSharedFileListItemRef currentItemRef = (LSSharedFileListItemRef)[loginItems objectAtIndex:currentIndex];
        if (LSSharedFileListItemResolve(currentItemRef, 0, (CFURLRef *) &itemUrl, NULL) == noErr) {
            // Compare the URLs for the current LoginItem and the app.
            if ([itemUrl isEqual:appUrl]) {
                // Save the LoginItem reference.
                itemRef = currentItemRef;
            }
        }
    }
    // Retain the LoginItem reference.
    if (itemRef != nil) CFRetain(itemRef);
    // Release the LoginItems lists.
    [loginItems release];
    CFRelease(loginItemsRef);
    
    return itemRef;
}


@end