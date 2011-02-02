//
//  BitTorrent.h
//  TorrentCreator2
//
//  Created by Sigurd Ljødal on 07.12.10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface BitTorrent : NSObject {
}

//
// torrentFromFile:
//
// Returns a basic .torrent-file with default piece size (256 kB)
//
+ (NSData *)torrentFromPath:(NSString *)path;
//
+ (NSData *)torrentFromFile:(NSString *)source;

+ (NSData *)torrentFromDirectory:(NSString *)path;

// Create a torrent with all posible options. Can be called with arguments as nil
+ (NSData *)torrentFromPath:(NSString *)path withPieceLength:(NSNumber *)pieceLength andTrackers:(NSArray *)trackers andPrivate:(BOOL)private andDHT:(NSArray *)hashTable andCaller:(id)caller;

@end


