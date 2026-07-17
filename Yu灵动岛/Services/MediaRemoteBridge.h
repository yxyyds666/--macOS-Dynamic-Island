// MediaRemoteBridge.h
// Bridging header for MediaRemote.framework private API

#ifndef MediaRemoteBridge_h
#define MediaRemoteBridge_h

#import <Foundation/Foundation.h>

// MediaRemote function declarations
typedef enum {
    kMRPlay = 0,
    kMRPause = 1,
    kMRTogglePlayPause = 2,
    kMRNextTrack = 3,
    kMRPreviousTrack = 4
} MRMediaRemoteCommand;

extern void MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_queue_t queue);
extern void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t queue, void (^handler)(NSDictionary *info));
extern void MRMediaRemoteSendCommand(MRMediaRemoteCommand command, NSDictionary *userInfo);
extern void MRMediaRemoteSetElapsedTime(double time);
extern void MRMediaRemoteSetVolume(float volume);

extern NSString * const kMRMediaRemoteNowPlayingInfoTitle;
extern NSString * const kMRMediaRemoteNowPlayingInfoArtist;
extern NSString * const kMRMediaRemoteNowPlayingInfoAlbum;
extern NSString * const kMRMediaRemoteNowPlayingInfoDuration;
extern NSString * const kMRMediaRemoteNowPlayingInfoElapsedTime;
extern NSString * const kMRMediaRemoteNowPlayingInfoPlaybackRate;
extern NSString * const kMRMediaRemoteNowPlayingInfoArtworkData;

#endif
