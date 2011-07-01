 /*
 
 File: OpenGLScreenReader.m
 
 Abstract: OpenGLScreenReader class implementation. Contains
            OpenGL code which creates a full-screen OpenGL context
            to use for rendering, then calls glReadPixels to read the 
            actual screen bits.
 
 Version: 1.0
 
 */ 
 
#import "OpenGLScreenReader.h"

@implementation OpenGLScreenReader

#pragma mark ---------- Initialization ----------

-(id) init
{
    if ((self = [super init]))
    {
		// Create a full-screen OpenGL graphics context
		
		// Specify attributes of the GL graphics context
		NSOpenGLPixelFormatAttribute attributes[] = {
			NSOpenGLPFAFullScreen,
			NSOpenGLPFAScreenMask,
			CGDisplayIDToOpenGLDisplayMask(kCGDirectMainDisplay),
			(NSOpenGLPixelFormatAttribute) 0
			};

		NSOpenGLPixelFormat *glPixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
		if (!glPixelFormat)
		{
			return nil;
		}

		// Create OpenGL context used to render
		mGLContext = [[[NSOpenGLContext alloc] initWithFormat:glPixelFormat shareContext:nil] autorelease];

		// Cleanup, pixel format object no longer needed
		[glPixelFormat release];
    
        if (!mGLContext)
        {
            [self release];
            return nil;
        }
        [mGLContext retain];

        // Set our context as the current OpenGL context
        [mGLContext makeCurrentContext];
        // Set full-screen mode
        [mGLContext setFullScreen];

		NSRect mainScreenRect = [[NSScreen mainScreen] frame];
		mWidth = mainScreenRect.size.width;
		mHeight = mainScreenRect.size.height;

        mByteWidth = mWidth * 4;                // Assume 4 bytes/pixel for now
        mByteWidth = (mByteWidth + 3) & ~3;    // Align to 4 bytes

        mData = malloc(mByteWidth * mHeight);
        NSAssert( mData != 0, @"malloc failed");
    }
    return self;
}

#pragma mark ---------- Screen Reader  ----------

// Perform a simple, synchronous full-screen read operation using glReadPixels(). 
// Although this is not the most optimal technique, it is sufficient for doing 
// simple one-shot screen grabs.
- (NSColor *)readFullScreenToBuffer
{
    return [self readPartialScreenToBuffer: mWidth bufferHeight: mHeight bufferBaseAddress: mData];
}

// Use this routine if you want to read only a portion of the screen pixels
- (NSColor *)readPartialScreenToBuffer: (size_t) width bufferHeight:(size_t) height bufferBaseAddress: (void *)baseAddress
{
	
    // select front buffer as our source for pixel data
    glReadBuffer(GL_FRONT);
    
    //Read OpenGL context pixels directly.

    // For extra safety, save & restore OpenGL states that are changed
    glPushClientAttrib(GL_CLIENT_PIXEL_STORE_BIT);
    
    glPixelStorei(GL_PACK_ALIGNMENT, 4); /* Force 4-byte alignment */
    glPixelStorei(GL_PACK_ROW_LENGTH, 0);
    glPixelStorei(GL_PACK_SKIP_ROWS, 0);
    glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
    
	
    //Read a block of pixels from the frame buffer
    glReadPixels(0, 0, width, height, GL_BGRA, 
            GL_UNSIGNED_INT_8_8_8_8_REV,
            baseAddress);
	int pixelIndex;
	unsigned char blue, green, red;
	unsigned char *restrict tempBuffer = baseAddress;
	
	NSInteger sumRed = 0;	
	NSInteger sumGreen = 0;	
	NSInteger sumBlue = 0;
	NSInteger sampleCount = 0;
	
	NSInteger skipFactor = 10;
	NSAssert( skipFactor > 0, @"accuraccy below 1");
	
	
	int topMargin = 200;
	int bottomMargin = 200;
	int leftMargin = 200;
	int rightMargin = 200;
	
	NSInteger yPixels = height - topMargin - bottomMargin;
	NSInteger xPixels = width - leftMargin - rightMargin;
	
	for( int j=topMargin; j<yPixels; j+=skipFactor ) {
		for( int i=leftMargin; i<xPixels; i++ ) {
			pixelIndex = (j*width + i)*4;
			blue = tempBuffer[pixelIndex];
			green = tempBuffer[pixelIndex+1];
			red = tempBuffer[pixelIndex+2];
			
			sumRed += red;
			sumGreen += green;
			sumBlue += blue;
			sampleCount++;
		}
	}
	//NSLog(@"%i samples", sampleCount);
	
	//NSAssert( sampleCount == height*width, @"sampleCount failed");
	NSAssert( sampleCount != 0, @"sampleCount shouldn't be 0");
	
	int32_t avRed = (sumRed / sampleCount) & 0x000000ff;
	int32_t avGreen = (sumGreen / sampleCount) & 0x000000ff;
	int32_t avBlue = (sumBlue / sampleCount) & 0x000000ff;

	return [NSColor colorWithDeviceRed: avRed/255.0 green: avGreen/255.0 blue: avBlue/255.0 alpha: 1.0];
			
    glPopClientAttrib();

    //Check for OpenGL errors
    GLenum theError = GL_NO_ERROR;
    theError = glGetError();
    NSAssert( theError == GL_NO_ERROR, @"OpenGL error 0x%04X", theError);
}


#pragma mark ---------- Cleanup  ----------

-(void)dealloc
{    
    // Get rid of GL context
    [NSOpenGLContext clearCurrentContext];
    // disassociate from full screen
    [mGLContext clearDrawable];
    // and release the context
    [mGLContext release];
	// release memory for screen data
	free(mData);

    [super dealloc];
}

@end
