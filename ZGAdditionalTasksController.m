/*
 * This file is part of Bit Slicer.
 *
 * Bit Slicer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 
 * Bit Slicer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with Bit Slicer.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Created by Mayur Pawashe on 5/13/11
 * Copyright 2011 zgcoder. All rights reserved.
 */

#import "ZGAdditionalTasksController.h"
#import "MyDocument.h"
#import "ZGProcess.h"
#import "ZGMemoryTypes.h"
#import "ZGCalculator.h"
#import "ZGUtilities.h"

@implementation ZGAdditionalTasksController

#pragma mark Memory Dump in Range

- (IBAction)memoryDumpOkayButton:(id)sender
{
	NSString *fromAddressExpression = [ZGCalculator evaluateExpression:[memoryDumpFromAddressTextField stringValue]];
	ZGMemoryAddress fromAddress = memoryAddressFromExpression(fromAddressExpression);
	
	NSString *toAddressExpression = [ZGCalculator evaluateExpression:[memoryDumpToAddressTextField stringValue]];
	ZGMemoryAddress toAddress = memoryAddressFromExpression(toAddressExpression);
	
	if (toAddress > fromAddress && ![fromAddressExpression isEqualToString:@""] && ![toAddressExpression isEqualToString:@""])
	{
		[NSApp endSheet:memoryDumpWindow];
		[memoryDumpWindow close];
		
		NSSavePanel *savePanel = [NSSavePanel savePanel];
		[savePanel beginSheetModalForWindow:watchWindow
						  completionHandler:^(NSInteger result)
		 {
			 if (result == NSFileHandlingPanelOKButton)
			 {
				 BOOL success = YES;
				 
				 @try
				 {
					 
					 ZGMemorySize size = toAddress - fromAddress;
					 void *bytes = malloc((size_t)size);
					 
					 if (bytes)
					 {
						 ZGReadBytesCarefully([[document currentProcess] processID], fromAddress, bytes, &size);
						 
						 NSData *data = [NSData dataWithBytes:bytes
													   length:(NSUInteger)size];
						 
						 success = [data writeToFile:[savePanel filename]
										  atomically:NO];
						 
						 free(bytes); 
					 }
					 else
					 {
						 NSLog(@"Failed to allocate region");
						 success = NO;
					 }
				 }
				 @catch (NSException *exception)
				 {
					 NSLog(@"Failed to write data");
					 success = NO;
				 }
				 @finally
				 {
					 if (!success)
					 {
						 NSRunAlertPanel(@"The Memory Dump failed",
										 @"An error resulted in writing the memory dump.",
										 @"OK", nil, nil);
					 }
				 }
			 }
		 }];
	}
	else
	{
		NSRunAlertPanel(@"Invalid range",
						@"Please make sure you typed in the addresses correctly.",
						@"OK", nil, nil);
	}
}

- (IBAction)memoryDumpCancelButton:(id)sender
{
	[NSApp endSheet:memoryDumpWindow];
	[memoryDumpWindow close];
}

- (void)memoryDumpRequest
{
	// guess what the user may want if nothing is in the text fields
	NSArray *selectedVariables = [document selectedVariables];
	if (selectedVariables && [[memoryDumpFromAddressTextField stringValue] isEqualToString:@""] && [[memoryDumpToAddressTextField stringValue] isEqualToString:@""])
	{
		ZGVariable *firstVariable = [selectedVariables objectAtIndex:0];
		ZGVariable *lastVariable = [selectedVariables lastObject];
		
		[memoryDumpFromAddressTextField setStringValue:[firstVariable addressStringValue]];
		
		if (firstVariable != lastVariable)
		{
			[memoryDumpToAddressTextField setStringValue:[lastVariable addressStringValue]];
		}
	}
	
	[NSApp beginSheet:memoryDumpWindow
	   modalForWindow:watchWindow
		modalDelegate:self
	   didEndSelector:nil
		  contextInfo:NULL];
}

#pragma mark Memory Dump All

- (void)updateMemoryDumpProgress:(NSTimer *)timer
{
	if ([document canStartTask])
	{
		[document prepareDocumentTask];
	}
	
	[searchingProgressIndicator setDoubleValue:[document currentProcess]->searchProgress];
}

- (void)memoryDumpAllRequest
{
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setMessage:@"Choose a folder name to save the memory dump files. This may take a while."];
	
	[savePanel beginSheetModalForWindow:watchWindow
					  completionHandler:^(NSInteger result)
	 {
		 if (result == NSFileHandlingPanelOKButton)
		 {
			 if ([[NSFileManager defaultManager] fileExistsAtPath:[savePanel filename]])
			 {
				 [[NSFileManager defaultManager] removeItemAtPath:[savePanel filename]
															error:NULL];
			 }
			 
			 // Since Bit Slicer is running as root, we'll need to pass attributes dictionary so that
			 // the folder is owned by the user
			 [[NSFileManager defaultManager] createDirectoryAtPath:[savePanel filename]
									   withIntermediateDirectories:NO
														attributes:[NSDictionary dictionaryWithObjectsAndKeys:NSUserName(), NSFileGroupOwnerAccountName, NSUserName(), NSFileOwnerAccountName, nil]
															 error:NULL];
			 
			 [searchingProgressIndicator setMaxValue:[[document currentProcess] numberOfRegions]];
			 
			 NSTimer *progressTimer = [[NSTimer scheduledTimerWithTimeInterval:USER_INTERFACE_UPDATE_TIME_INTERVAL
																		target:self
																	  selector:@selector(updateMemoryDumpProgress:)
																	  userInfo:nil
																	   repeats:YES] retain];
			 
			 //not doing this here, there's a bug with setKeyEquivalent, instead i'm going to do this in the timer
			 //[document prepareDocumentTask];
			 [generalStatusTextField setStringValue:@"Writing Memory Dump..."];
			 
			 dispatch_block_t searchForDataCompleteBlock = ^
			 {
				 [progressTimer invalidate];
				 [progressTimer release];
				 
				 if (!([document currentProcess]->isDoingMemoryDump))
				 {
					 [generalStatusTextField setStringValue:@"Canceled Memory Dump"];
				 }
				 else
				 {
					 [document currentProcess]->isDoingMemoryDump = NO;
					 [generalStatusTextField setStringValue:@"Finished Memory Dump"];
				 }
				 [searchingProgressIndicator setDoubleValue:0];
				 [document resumeDocument];
			 };
			 
			 dispatch_block_t searchForDataBlock = ^
			 {
				 if (!ZGSaveAllDataToDirectory([savePanel filename], [document currentProcess]))
				 {
					 NSRunAlertPanel(@"The Memory Dump failed",
									 @"An error resulted in writing the memory dump.",
									 @"OK", nil, nil);
				 }
				 
				 dispatch_async(dispatch_get_main_queue(), searchForDataCompleteBlock);
			 };
			 dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), searchForDataBlock);
		 }
	 }];
}

#pragma mark Memory Protection

- (IBAction)changeProtectionOkayButton:(id)sender
{
	NSString *addressExpression = [ZGCalculator evaluateExpression:[changeProtectionAddressTextField stringValue]];
	ZGMemoryAddress address = memoryAddressFromExpression(addressExpression);
	
	NSString *sizeExpression = [ZGCalculator evaluateExpression:[changeProtectionSizeTextField stringValue]];
	ZGMemorySize size = (ZGMemorySize)memoryAddressFromExpression(sizeExpression);
	
	if (size > 0 && ![addressExpression isEqualToString:@""] && ![sizeExpression isEqualToString:@""])
	{
		ZGMemoryProtection protection = VM_PROT_NONE;
		
		if ([changeProtectionReadButton state] == NSOnState)
		{
			protection |= VM_PROT_READ;
		}
		
		if ([changeProtectionWriteButton state] == NSOnState)
		{
			protection |= VM_PROT_WRITE;
		}
		
		if ([changeProtectionExecuteButton state] == NSOnState)
		{
			protection |= VM_PROT_EXECUTE;
		}
		
		if (!ZGProtect([[document currentProcess] processID], address, size, protection))
		{
			NSRunAlertPanel(@"Memory Protection Change Failed",
							@"The memory's protection could not be changed to the specified permissions.",
							@"OK", nil, nil);
		}
		else
		{
			[NSApp endSheet:changeProtectionWindow];
			[changeProtectionWindow close];
		}
	}
	else
	{
		NSRunAlertPanel(@"Invalid range",
						@"Please make sure you typed in the addresses correctly.",
						@"OK", nil, nil);
	}
}

- (IBAction)changeProtectionCancelButton:(id)sender
{
	[NSApp endSheet:changeProtectionWindow];
	[changeProtectionWindow close];
}

- (void)changeMemoryProtectionRequest
{
	// guess what the user may want if nothing is in the text fields
	NSArray *selectedVariables = [document selectedVariables];
	if (selectedVariables && [[changeProtectionAddressTextField stringValue] isEqualToString:@""] && [[changeProtectionSizeTextField stringValue] isEqualToString:@""])
	{
		ZGVariable *firstVariable = [selectedVariables objectAtIndex:0];
		
		[changeProtectionAddressTextField setStringValue:[firstVariable addressStringValue]];
		[changeProtectionSizeTextField setStringValue:[NSString stringWithFormat:@"%lld", firstVariable->size]];
	}
	
	[NSApp beginSheet:changeProtectionWindow
	   modalForWindow:watchWindow
		modalDelegate:self
	   didEndSelector:nil
		  contextInfo:NULL];
}

@end
