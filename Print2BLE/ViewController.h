//
//  ViewController.h
//  Print2BLE
//
//  Created by Laurence Bank on 8/31/21.
//

#import <Cocoa/Cocoa.h>
#import "DragDropView.h"
#import "MyBLE.h"

@interface ViewController : NSViewController

@property (nonatomic, retain) DragDropView *myview;
@property (nonatomic) NSString *filename;

// Process a new file
- (void)processFile:(NSString *)path;
- (void)printFile:(NSNotification *) notification;

@end
