//
//  ViewController.m
//  Print2BLE
//
//  Created by Larry Bank
//  Copyright (c) 2021 BitBank Software Inc. All rights reserved.
//

#import "ViewController.h"
#import "MyBLE.h"

MyBLE *BLEClass;
uint8_t contrast_lookup[256];
static uint8_t *pDithered = NULL; // Dithered image data ready to print
static int iWidth, iHeight; // size of the image that's ready to print

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _myview = [DragDropView alloc];
}

- (void)viewDidLayout {
    // the outer frame size is known here, so set our drag/drop frame to the same size
    
//    _myview.frame = NSMakeRect(0, 0, self.view.frame.size.width, self.view.frame.size.height);
    
    [_myview initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
    // Do any additional setup after loading the view.
    BLEClass = [[MyBLE alloc] init];
    
    _myview.myVC = self; // give DragDropView access to our methods
    [[self view] addSubview:_myview];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ditherFile:)
                                                 name:@"PrintFileNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(statusChanged:)
                                                 name:@"StatusChangedNotification"
                                               object:nil];

//    [BLEClass startScan]; // scan and connect to any printers in the area

}
- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}
- (IBAction)FeedPushed:(NSButton *)sender {
    NSLog(@"Feed!");
    [BLEClass feedPaper];
}
- (IBAction)ConnectPushed:(NSButton *)sender {
    NSLog(@"Connect!");
    [BLEClass startScan];
}

- (IBAction)TransmitPushed:(NSButton *)sender {
    NSLog(@"Print!");
    [self printImage];
}

// Process a new file
- (void)processFile:(NSString *)path
{
    _filename = [[NSString alloc] initWithString:path];
    NSLog(@"User dropped file %@", _filename);

} /* processFile */

- (uint8_t *)DitherImage:(uint8_t*)pPixels width:(int)iWidth height:(int)iHeight
{
    int x, y, xmask=0, iDestPitch=0;
    int32_t cNew, lFErr, v=0, h;
    int32_t e1,e2,e3,e4;
    uint8_t cOut; // forward errors for gray
    uint8_t *pSrc, *pDest, *errors, *pErrors=NULL, *d, *s; // destination 8bpp image
    uint8_t pixelmask=0, shift=0;
    uint8_t ucTemp[640];
    
        errors = ucTemp; // plenty of space here for the bitmaps we'll generate
        memset(ucTemp, 0, sizeof(ucTemp));
        pSrc = pPixels; // write the new pixels over the original
        iDestPitch = (iWidth+7)/8;
        pDest = (uint8_t *)malloc(iDestPitch * iHeight);
        pixelmask = 0x80;
        shift = 1;
        xmask = 7;
        for (y=0; y<iHeight; y++)
        {
            s = &pSrc[y * iWidth];
            d = &pDest[y * iDestPitch];
            pErrors = &errors[1]; // point to second pixel to avoid boundary check
            lFErr = 0;
            cOut = 0;
            for (x=0; x<iWidth; x++)
            {
                cNew = *s++; // get grayscale uint8_t pixel
                cNew = (cNew * 2)/3; // make white end of spectrum less "blown out"
                // add forward error
                cNew += lFErr;
                if (cNew > 255) cNew = 255;     // clip to uint8_t
                cOut <<= shift;                 // pack new pixels into a byte
                cOut |= (cNew >> (8-shift));    // keep top N bits
                if ((x & xmask) == xmask)       // store it when the byte is full
                {
                    *d++ = ~cOut; // color is inverted
                    cOut = 0;
                }
                // calculate the Floyd-Steinberg error for this pixel
                v = cNew - (cNew & pixelmask); // new error for N-bit gray output (always positive)
                h = v >> 1;
                e1 = (7*h)>>3;  // 7/16
                e2 = h - e1;  // 1/16
                e3 = (5*h) >> 3;   // 5/16
                e4 = h - e3;  // 3/16
                // distribute error to neighbors
                lFErr = e1 + pErrors[1];
                pErrors[1] = (uint8_t)e2;
                pErrors[0] += e3;
                pErrors[-1] += e4;
                pErrors++;
            } // for x
        } // for y
    return pDest;
} /* DitherImage */

//
// Send the image that was previously dithered
// to the connected printer
//
- (void)printImage
{
    if (pDithered == NULL) return; // no image to print
    // Now send it to the printer
    [BLEClass preGraphics:iHeight];
    int iPitch = iWidth/8;
    uint8_t *pSrc = pDithered;
    for (int y=0; y<iHeight; y++) {
        [BLEClass scanLine:pSrc withLength:iPitch];
        pSrc += iPitch;
    }
    [BLEClass postGraphics];

} /* printImage */

- (void)statusChanged:(NSNotification *) notification
{
    if ([BLEClass isConnected]) {
        _StatusLabel.stringValue = [NSString stringWithFormat:@"Connected to: %@", [BLEClass getName]];
    } else {
        _StatusLabel.stringValue = @"Disconnected";
    }
} /* statusChanged */

- (void)ditherFile:(NSNotification *) notification
{
    // load the file into an image object
    NSData *theFileData = [[NSData alloc] initWithContentsOfFile:_filename options: NSDataReadingMappedAlways error: nil]; // read file into memory
    if (theFileData) {
        // decode the image into a bitmap
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithData:theFileData];
        if (bitmap) {
            // convert to grayscale
            NSColorSpace *targetColorSpace = [NSColorSpace genericGrayColorSpace];
            NSBitmapImageRep *grayBitmap = [bitmap bitmapImageRepByConvertingToColorSpace: targetColorSpace renderingIntent: NSColorRenderingIntentDefault];
                                           
            int iOriginalWidth, iOriginalHeight;
            // scale to correct size (576 or 384 pixels wide)
            float ratio;
            iOriginalWidth = bitmap.size.width;
            iOriginalHeight = bitmap.size.height;
            iWidth = [BLEClass getWidth]; // get printer width in pixels
            ratio = (float)iOriginalWidth / (float)iWidth;
            iHeight = (int)((float)iOriginalHeight / ratio);
            NSSize newSize;
            newSize.width = iWidth;
            newSize.height = iHeight;
            // now resize it
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
                      initWithBitmapDataPlanes:NULL
                                    pixelsWide:newSize.width
                                    pixelsHigh:newSize.height
                                 bitsPerSample:8
                               samplesPerPixel:1
                                      hasAlpha:NO
                                      isPlanar:NO
                                colorSpaceName:NSCalibratedWhiteColorSpace
                                   bytesPerRow:0
                                  bitsPerPixel:0];
            rep.size = newSize;
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
            [grayBitmap drawInRect:NSMakeRect(0, 0, newSize.width, newSize.height)];
            [NSGraphicsContext restoreGraphicsState];
            uint8_t *pPixels = [rep bitmapData];
            if (pDithered) free(pDithered);
            pDithered = [self DitherImage:pPixels width:iWidth height:iHeight];
            // Create a preview image
            // convert the 1-bpp image to 8-bit grayscale so that we can show it in the preview window
            uint8_t *pGray = (uint8_t *)malloc(iWidth * iHeight);
            int i, j, iCount;
            uint8_t c, ucMask, *s, *d;
            iCount = (iWidth/8) * iHeight;
            d = pGray;
            s = pDithered;
            for (i=0; i<iCount; i++) {
                ucMask = 0x80;
                c = *s++;
                for (j=0; j<8; j++) {
                    if (c & ucMask)
                        *d = 0;
                    else
                        *d = 0xff;
                    ucMask >>= 1;
                    d++;
                }
            }
            // make an NSImage out of the grayscale bitmap
            CGColorSpaceRef colorSpace;
            CGContextRef gtx;
            NSUInteger bitsPerComponent = 8;
            NSUInteger bytesPerRow = iWidth;
            colorSpace = CGColorSpaceCreateDeviceGray();
            gtx = CGBitmapContextCreate(pGray, iWidth, iHeight, bitsPerComponent, bytesPerRow, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaNone);
            CGImageRef myimage = CGBitmapContextCreateImage(gtx);
//            CGContextSetInterpolationQuality(gtx, kCGInterpolationNone);
            NSImage *image = [[NSImage alloc]initWithCGImage:myimage size:NSZeroSize];
            _myImage.image = image; // set it into the image view
            // Free temp objects
            CGColorSpaceRelease(colorSpace);
            CGContextRelease(gtx);
            CGImageRelease(myimage);
            free(pGray);
        }
    }
} /* ditherFile*/
@end
