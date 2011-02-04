//
//  BitTorrent.m
//  TorrentCreator2
//
//  Created by Sigurd Ljødal on 07.12.10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "BitTorrent.h"

// Needed for SHA1 functions
#import <CommonCrypto/CommonDigest.h>

// Needed for BEncoding the file/dicitonary
#import "BEncoding.h";

// Needed for reading file
#include <stdio.h>

// "Private" methods
// You probably shouldn't call these unless you know what you're doing
@interface BitTorrent (Private)
// Create torrents from file/directory. All methods call these to create torrents
+ (NSData *)torrentFromFile:(NSString *)file withPieceLength:(NSNumber *)pieceLength andTrackers:(NSArray *)trackers andPrivate:(BOOL)private andDHT:(NSArray *)hashTable andCaller:(id)caller andTotalSize:(NSNumber *)totalSize;
+ (NSData *)torrentFromDirectory:(NSString *)directory withPieceLength:(NSNumber *)pieceLength andTrackers:(NSArray *)trackers andPrivate:(BOOL)private andDHT:(NSArray *)hashTable andCaller:(id)caller andTotalSize:(NSNumber *)totalSize;

// Methods to read data from files
+ (NSData *)copyChunkOfLength:(NSInteger)length fromFile:(FILE *)file;
+ (NSData *)newSHA1OfData:(NSData *)data;
+ (NSData *)newSHA1OfChunkOfLength:(NSInteger)length fromFile:(FILE *)file;

// Calculate piece size based on total file size
+ (NSNumber *)piecelengthForSize:(NSNumber *)size;

@end


@implementation BitTorrent

+ (NSData *)torrentFromPath:(NSString *)path {
	// Get the default file manager
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	// Chech that we can read the file/directory at that path
	if ([fileManager isReadableFileAtPath:path]) {
		// Get the properties of the path
		NSDictionary *properties = [fileManager attributesOfItemAtPath:path error:nil];
		// Chech if we have a file, a folder or something else
		if ([properties valueForKey:NSFileType] == NSFileTypeRegular) {
			// It's a file, so create a single file torrent
			return [self torrentFromFile:path];
		} else if ([properties valueForKey:NSFileType] == NSFileTypeDirectory) {
			// It's a directory so create a multi file torrent
			return [self torrentFromDirectory:path];
		} else {
			// Unsupported file type, return nil
			return nil;
		}

	} else {
		// If there's no readable file at that path, return nil
		return nil;
	}
}

+ (NSData *)torrentFromFile:(NSString *)source {
	
	// Get the default file manager
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	// We can read the file
	if ([fileManager isReadableFileAtPath:source]) {
		// Get the properties from the file
		NSDictionary *properties = [fileManager attributesOfItemAtPath:source error:nil];
		
		if ([properties valueForKey:NSFileType] == NSFileTypeRegular) {
			// Set piece size
			NSNumber *pieceSize = [self piecelengthForSize:[properties valueForKey:NSFileSize]];
			
			// Make and return the torrent
			return [self torrentFromFile:source withPieceSize:[pieceSize integerValue]];
		} else {
			// This isn't a file
			return nil;
		}
		
	}
	return nil;
}

+ (NSData *)torrentFromFile:(NSString *)source withPieceSize:(NSInteger)pieceLength {
	// Get the file manager
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	// Check that we can read the source file
	if ([fileManager isReadableFileAtPath:source]) {
		
		// Get the file's attributes
		NSDictionary *attributes = [fileManager attributesOfItemAtPath:source error:nil];
		
		// Check what kind of file
		if ([attributes valueForKey:NSFileType] == NSFileTypeRegular) {
			
			// The dictionary to be encoded
			NSMutableDictionary *file = [NSMutableDictionary dictionary];
			
			// Add the announce key
			//[file setObject:@"test" forKey:@"announce"];
			
			// Add the info key
			[file setObject:[NSMutableDictionary dictionary] forKey:@"info"];
			
			// Add the file name
			[[file valueForKey:@"info"] setObject:[source lastPathComponent] forKey:@"name"];
			
			// Add the piece length
			[[file valueForKey:@"info"] setObject:[NSNumber numberWithUnsignedLongLong:pieceLength] forKey:@"piece length"];
			
			// Add the length
			[[file valueForKey:@"info"] setObject:[attributes valueForKey:NSFileSize] forKey:@"length"];
			
			// Calculate SHA1 values and add them
			
			// Array to store pieces in
			NSMutableArray *pieces = [NSMutableArray array];
			
			// Open the file
			FILE *sourceFile = fopen([source cStringUsingEncoding:NSUTF8StringEncoding], "r");
			
			// Check that the file is indeed open
			if (sourceFile == NULL) {
				return nil;
			}
			
			//BOOL first = YES;
			while (!feof(sourceFile)) {
				NSData *sha1 = [self newSHA1OfChunkOfLength:pieceLength fromFile:sourceFile];
				[pieces addObject:sha1];
				//[piece release];
				[sha1 release];
			}
			
			// Close the file
			fclose(sourceFile);
			
			// Pieces "string"
			NSMutableData *piecesData = [NSMutableData data];
			for (int i = 0; i < [pieces count]; i++) {
				[piecesData appendData:[pieces objectAtIndex:i]];
			}
			
			// Add the pieces
			[[file valueForKey:@"info"] setObject:piecesData forKey:@"pieces"];
			
			// BEncode
			NSData *bencodedFile = [BEncoding encodedDataFromObject:file];
			
			// Return
			return bencodedFile;
		}
		
		// If we got here the file type isn't supported
		return nil;
	}
	// We couldn't read the file
	return nil;
}

// Create torrent with all possible options
+ (NSData *)torrentFromPath:(NSString *)path withPieceLength:(NSNumber *)pieceLength andTrackers:(NSArray *)trackers andPrivate:(BOOL)private andDHT:(NSArray *)hashTable andCaller:(id)caller {
	if (caller && [caller respondsToSelector:@selector(statusUpdate:)]) {
		[caller performSelector:@selector(statusUpdate:) withObject:@"Preparing"];
	}
	
	// Path must be set
	if (!path) {
		if (caller && [caller respondsToSelector:@selector(error:)]) {
			[caller performSelector:@selector(error:) withObject:@"No path set"];
		}
		return nil;
	}
	
	// Get the default file manager
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	// Check that we can read at the path
	if (![fileManager isReadableFileAtPath:path]) {
		if (caller && [caller respondsToSelector:@selector(error:)]) {
			[caller performSelector:@selector(error:) withObject:@"Unable to read file/folder at path"];
		}
		return nil;
	}
	
	// Get the attributes of the path
	NSError *error = nil;
	NSDictionary *pathAtributes = [fileManager attributesOfItemAtPath:path error:&error];
	
	// If something went wrong when getting the attributes
	if (error) {
		if (caller && [caller respondsToSelector:@selector(error:)]) {
			[caller performSelector:@selector(error:) withObject:@"Something went wrong when getting the path attributes"];
		}
		return nil;
	}
	
	if ([pathAtributes valueForKey:NSFileType] == NSFileTypeRegular) {
		// Calculate piece length
		NSNumber *pieceLength = [self piecelengthForSize:[pathAtributes valueForKey:NSFileSize]];
		
		// Make and return the torrent
		return [self torrentFromFile:path
					 withPieceLength:pieceLength
						 andTrackers:trackers
						  andPrivate:private
							  andDHT:hashTable
						   andCaller:caller
						andTotalSize:[pathAtributes valueForKey:NSFileSize]];
		
	} else if ([pathAtributes valueForKey:NSFileType] == NSFileTypeDirectory) {
		
		// We need to calculate the total size of the folder
		unsigned long long size = 0;
		
		NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtPath:path];
		NSString *file;
		while (file = [directoryEnumerator nextObject]) {											  
			// Get the attribues
			NSDictionary *attributes = [directoryEnumerator fileAttributes];
			
			// If this is a directory or symlink skip it
			if ([attributes objectForKey:NSFileType] != NSFileTypeRegular) {
				continue;
				// If it's a file, add the size
			} else {
				// If it's a file get the path relative to the top level folder in the torrent
				// and the file length and add them to the files array
				size +=[[attributes objectForKey:NSFileSize] unsignedLongLongValue];
			}
		}
		NSNumber *pieceLength = [self piecelengthForSize:[NSNumber numberWithUnsignedLongLong:size]];
		
		return [self torrentFromDirectory:path
						  withPieceLength:pieceLength
							  andTrackers:trackers
							   andPrivate:private
								   andDHT:hashTable
								andCaller:caller
							 andTotalSize:[NSNumber numberWithUnsignedLongLong:size]];
		
	} else {
		// This isn't a file
		if (caller && [caller respondsToSelector:@selector(error:)]) {
			[caller performSelector:@selector(error:) withObject:@"Unable to make a torrent from that!"];
		}
		return nil;
	}
	
	return nil;
}

// These two methods are the methods that every other method calls in the end. One for single files and one for directories
+ (NSData *)torrentFromFile:(NSString *)file withPieceLength:(NSNumber *)pieceLength andTrackers:(NSArray *)trackers andPrivate:(BOOL)private andDHT:(NSArray *)hashTable andCaller:(id)caller andTotalSize:(NSNumber *)totalSize {
	// Check that the two required arguments are set, if not return now
	if (!file || !pieceLength) {
		return nil;
	}
	
	// Get the default file manager
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	NSLog(@"%@", [fileManager attributesOfItemAtPath:file error:nil]);
	
	return nil;
}
+ (NSData *)torrentFromDirectory:(NSString *)directory withPieceLength:(NSNumber *)pieceLength andTrackers:(NSArray *)trackers andPrivate:(BOOL)private andDHT:(NSArray *)hashTable andCaller:(id)caller andTotalSize:(NSNumber *)totalSize {
	// Check that the two required arguments are set, if not return now
	if (!directory || !pieceLength) {
		return nil;
	}
	
	// Create the dictionary
	NSMutableDictionary *unencoded = [[NSMutableDictionary alloc] init];
	
	// Set announce
	if (trackers) {
		if ([trackers count] == 1) {
			[unencoded setObject:[trackers objectAtIndex:0] forKey:@"announce"];
		} else if ([trackers count] > 1) {
			[unencoded setObject:trackers forKey:@"announce-list"];
		}
	}
	
	// Create the info dictionary and add it to the main dictionary
	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	[unencoded setObject:info forKey:@"info"];
	
	// Set the piece length
	[info setObject:pieceLength forKey:@"piece length"];
	
	// Set the name of the directory
	[info setObject:[directory lastPathComponent] forKey:@"name"];
	
	// Add the files list to the dictionary
	[info setObject:[NSMutableArray array] forKey:@"files"];
	
	// We then need a place to store the hash values
	NSMutableData *hashes = [NSMutableData data];
	
	// We also need a variable to store the current file chunk in
	NSMutableData *chunk = nil;
	
	// Get the default file manager
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	// Get the enumerator for the folder
	NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtPath:directory];
	
	// Variable to keep track of progress
	unsigned long long bytesRead = 0;
	NSNumber *progress = [NSNumber numberWithInt:0];
	
	// Enumerate through the directory and calculate hashes for all files
	NSString *file;
	while (file = [enumerator nextObject]) {
		
		// Get the attribues of the current file
		NSDictionary *attributes = [enumerator fileAttributes];
		
		// Check the file type
        if ([attributes objectForKey:NSFileType] != NSFileTypeRegular) {
			// If it's not a regular file, skip to next object
			continue;
		} else {
			// If it's a file get the path relative to the top level folder in the torrent
			// and the file length and add them to the files array
			NSMutableDictionary *fileAttributes = [NSMutableDictionary dictionary];
			[fileAttributes setObject:[file pathComponents] forKey:@"path"];
			[fileAttributes setObject:[attributes objectForKey:NSFileSize] forKey:@"length"];
			[[info valueForKey:@"files"] addObject:fileAttributes];
		}
		
		// Open the file for reading
		FILE *sourceFile = fopen([[NSString stringWithFormat:@"%@/%@", directory, file] cStringUsingEncoding:NSUTF8StringEncoding], "r");
		
		// Check that the file was successfully opened
		if (sourceFile == NULL) {
			// Something went wrong. Clean up the allocated memory and return
			[hashes release];
			[unencoded release];
			if (chunk != nil) {
				[chunk release];
			}
			return nil;
		}
		
		// Read and hash the file
		while (!feof(sourceFile)) {
			
			// If chunk isn't initialized do it now
			if (chunk == nil) {
				chunk = [[NSMutableData alloc] init];
			}
			
			// Read data from file
			NSData *tmp = [self copyChunkOfLength:([pieceLength unsignedIntegerValue] - [chunk length]) fromFile:sourceFile];
			
			// Add the data read from file to the chunk
			[chunk appendData:tmp];
			
			// Release the data read from file
			[tmp release];
			
			if ([chunk length] == [pieceLength unsignedIntegerValue]) {
				// Get the SHA-1 hash
				NSData *sha1 = [self newSHA1OfData:chunk];
				
				// Get the hash
				[hashes appendData:sha1];
				
				// Update progress
				bytesRead += [chunk length];
				
				// Release the chunk and set the pointer to nil
				[sha1 release];
				[chunk release];
				
				chunk = nil;
				
				// Report progress
				if (caller && [caller respondsToSelector:@selector(progressUpdate:)] && ([progress unsignedIntValue] < [[NSNumber numberWithInt:(int)(((float)bytesRead / (float)[totalSize unsignedLongLongValue]) * 100)] unsignedIntValue])) {
					progress = [NSNumber numberWithInt:(int)(((float)bytesRead / (float)[totalSize unsignedLongLongValue]) * 100)];
					[caller performSelector:@selector(progressUpdate:) withObject:progress];
				}
			}
		}
		
		// Close the file
		fclose(sourceFile);
		
	}
	
	// If the file length didn't fit exactly to piece length we will have some remaining data to hash
	if (chunk != nil) {
		// Get the SHA-1 hash
		NSData *sha1 = [self newSHA1OfData:chunk];
		
		// Generating and storing the hash of the last piece
		[hashes appendData:sha1];
		
		// Update progress
		bytesRead += [chunk length];
		
		// Release the piece
		[sha1 release];
		[chunk release];
		chunk = nil;
	}
	
	// Report progress
	float byteFloat = (float)bytesRead;
	float totalFloat = (float)[totalSize unsignedLongLongValue];
	
	NSNumber *currentProgress = [NSNumber numberWithInt:(int)((byteFloat / totalFloat) * 100)];
	//NSLog(@"Old: %@ New: %@", progress, currentProgress);
	if (caller && [caller respondsToSelector:@selector(progressUpdate:)] && ([progress unsignedIntValue] < [currentProgress unsignedIntValue])) {
		progress = currentProgress;
		[caller performSelector:@selector(progressUpdate:) withObject:progress];
	}
	
	// Add the pieces to the dictionary
	[info setObject:hashes forKey:@"pieces"];
	
	// BEncode the file
	NSData *encoded = [NSData dataWithData:[BEncoding encodedDataFromObject:unencoded]];
	
	// Release the unencoded torrent
	[unencoded release];
	
	// Tell the caller that we've finished
	if (caller && [caller respondsToSelector:@selector(statusUpdate:)]) {
		[caller performSelector:@selector(statusUpdate:) withObject:@"Done"];
	}
	
	// Return the BEncoded file
	return encoded;
}

// Read length bytes from file and return as NSData
+ (NSData *)copyChunkOfLength:(NSInteger)length fromFile:(FILE *)file {
	// Allocate and set memory for the chunk we're reading
	unsigned char *buffer = malloc(length);
	memset(buffer, 0, length);
	
	// Read length bytes from file to buffer
	size_t read = fread(buffer, 1, length, file);
	
	// Copy the buffer to a NSData object
	NSData *chunck = [[NSData alloc] initWithBytes:buffer length:read];
	
	// Free the buffer
	free(buffer);
	
	// Return the NSData object
	return chunck;
}

+ (NSData *)newSHA1OfData:(NSData *)data {
	// Allocate and set memory for the SHA-1 hash
	unsigned char *buffer = malloc(CC_SHA1_DIGEST_LENGTH);
	memset(buffer, 0, CC_SHA1_DIGEST_LENGTH);
	
	// Calculate the hash of data and store it in buffer
	CC_SHA1([data bytes], [data length], buffer);
	
	// Copy buffer to a NSData object
	NSData *sha1 = [[NSData alloc] initWithBytes:buffer length:CC_SHA1_DIGEST_LENGTH];
	
	// Free the buffer
	free(buffer);
	
	// Return the NSData object
	return sha1;
}

+ (NSData *)newSHA1OfChunkOfLength:(NSInteger)length fromFile:(FILE *)file {
	// Allocate and set memory for the chunk we're reading from file
	unsigned char *fileChunk = malloc(length);
	memset(fileChunk, 0, length);
	
	// Read length bytes from file into fileChunk
	size_t read = fread(fileChunk, 1, length, file);
	
	// Allocate and set the memory for the SHA-1 hash
	unsigned char *sha1 = malloc(CC_SHA1_DIGEST_LENGTH);
	memset(sha1, 0, CC_SHA1_DIGEST_LENGTH);
	
	// Generate the SHA-1 hash and store it in sha1
	CC_SHA1(fileChunk, read, sha1);
	
	// Free the file chunk
	free(fileChunk);
	
	// Copy the hash into a NSData object
	NSData *hash = [[NSData alloc] initWithBytes:sha1 length:CC_SHA1_DIGEST_LENGTH];
	
	// Free sha1
	free(sha1);
	
	// Return the NSData object
	return hash;
}

+ (NSNumber *)piecelengthForSize:(NSNumber *)size {
	if ([size unsignedLongLongValue] <= 536870912) {
		return [NSNumber numberWithInteger:262144];
	} else if ([size unsignedLongLongValue] > 536870912 && [size unsignedLongLongValue] <= 1073741824) {
		return [NSNumber numberWithInteger:524288];
	} else if ([size unsignedLongLongValue] > 1073741824 && [size unsignedLongLongValue] <= 2147483648) {
		return [NSNumber numberWithInteger:1048576];
	} else if ([size unsignedLongLongValue] > 2147483648 && [size unsignedLongLongValue] <= 4294967296) {
		return [NSNumber numberWithInteger:2097152];
	} else {
		return [NSNumber numberWithInteger:4194304];
	}
}

+ (NSData *)torrentFromDirectory:(NSString *)path {
	// The dictionary to be encoded
	NSMutableDictionary *unencoded = [[NSMutableDictionary alloc] init];
	
	// Set announce
	[unencoded setObject:@"udp://tracker.openbittorrent.com:80/announce" forKey:@"announce"];
	
	// Add the info key
	[unencoded setObject:[NSMutableDictionary dictionary] forKey:@"info"];
	
	// Add the file name
	[[unencoded valueForKey:@"info"] setObject:[path lastPathComponent] forKey:@"name"];
	
	// Add the piece length
	[[unencoded valueForKey:@"info"] setObject:[NSNumber numberWithUnsignedLongLong:65536] forKey:@"piece length"];
	
	// Add the length
	[[unencoded valueForKey:@"info"] setObject:[NSMutableArray array] forKey:@"files"];
	
	// The NSData we will store the sha1-hashes in
	NSMutableData *hashes = [[NSMutableData alloc] init];
	
	// Get an enumerator of the directory
	NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:path];
	
	// The NSData to store the current chunk in
	NSMutableData *chunk = nil;

	// Enumerate through all files in the directory and subdirectories
	NSString *file;
	while (file = [directoryEnumerator nextObject]) {
		
		// Get the attribues
		NSDictionary *attributes = [directoryEnumerator fileAttributes];
		
		// If this is a directory or symlink skip it
        if ([attributes objectForKey:NSFileType] != NSFileTypeRegular) {
			continue;
		// If it's a file, add it to the files array
		} else {
			// If it's a file get the path relative to the top level folder in the torrent
			// and the file length and add them to the files array
			NSMutableDictionary *fileAttributes = [NSMutableDictionary dictionary];
			[fileAttributes setObject:[file pathComponents] forKey:@"path"];
			[fileAttributes setObject:[attributes objectForKey:NSFileSize] forKey:@"length"];
			[[[unencoded valueForKey:@"info"] valueForKey:@"files"] addObject:fileAttributes];
		}
		
		// Open the file for reading
		FILE *sourceFile = fopen([[NSString stringWithFormat:@"%@/%@", path, file] cStringUsingEncoding:NSUTF8StringEncoding], "r");
		
		// Check that the file was successfully opened
		if (sourceFile == NULL) {
			// Something went wrong. Clear memory and return
			[hashes release];
			if (chunk != nil) {
				[chunk release];
				chunk = nil;
			}
			return nil;
		}
		
		// Read and hash the file
		while (!feof(sourceFile)) {
			
			// If chunk isn't initialized do it now
			if (chunk == nil) {
				chunk = [[NSMutableData alloc] init];
			}
			
			// Read data from file
			NSData *tmp = [self copyChunkOfLength:(65536 - [chunk length]) fromFile:sourceFile];
			
			// Add the data read from file to the chunk
			[chunk appendData:tmp];
			
			// Release the data read from file
			[tmp release];
			
			if ([chunk length] == 65536) {
				// Get the SHA-1 hash
				NSData *sha1 = [self newSHA1OfData:chunk];
				
				// Get the hash
				[hashes appendData:sha1];
				
				// Release the chunk and set the pointer to nil
				[sha1 release];
				[chunk release];
				
				chunk = nil;
			}
		}
		fclose(sourceFile);
	}
	
	if (chunk != nil) {
		// Get the SHA-1 hash
		NSData *sha1 = [self newSHA1OfData:chunk];
		
		// Generating and storing the hash of the last piece
		[hashes appendData:sha1];
		
		// Release the piece
		[sha1 release];
		[chunk release];
		chunk = nil;
	}
	
	// Add the pieces to the dictionary
	[[unencoded objectForKey:@"info"] setObject:hashes forKey:@"pieces"];
	
	// BEncode the file
	NSData *encoded = [NSData dataWithData:[BEncoding encodedDataFromObject:unencoded]];
	
	// Release the unencoded torrent
	[unencoded release];
	
	// Release the hashes
	[hashes release];
	
	// Return the BEncoded file
	return encoded;
}

@end
