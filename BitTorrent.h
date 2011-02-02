//
//  BitTorrent.h
//  TorrentCreator2
//
//  Created by Sigurd Ljødal on 07.12.10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// The delegate protocol
@protocol BitTorrentDelegate <NSObject>

- (void)progressUpdate:(NSNumber *)progress;

@end

@interface BitTorrent : NSObject {
}

//
// torrentFromFile:
//
// Returns a basic .torrent-file with default piece size (256 kB)
//
+ (NSData *)torrentFromPath:(NSString *)path;

+ (NSData *)torrentFromPath:(NSString *)path withDelegate:(id <BitTorrentDelegate>)delegate;

//
+ (NSData *)torrentFromFile:(NSString *)source;

+ (NSData *)torrentFromFile:(NSString *)source withPieceSize:(NSInteger)pieceLength;

+ (NSData *)torrentFromFile:(NSString *)source withTrackers:(NSArray *)trackers;

+ (NSData *)torrentFromFile:(NSString *)source withPieceSize:(NSInteger)pieceSize andTrackers:(NSArray *)trackers;

+ (NSData *)torrentFromDirectory:(NSString *)path;

// Create a torrent with all posible options. Can be called with arguments as nil
+ (NSData *)torrentFromPath:(NSString *)path withPieceLength:(NSNumber *)pieceLength andTrackers:(NSArray *)trackers andPrivate:(BOOL)private andDHT:(NSArray *)hashTable andCaller:(id)caller;

@end


