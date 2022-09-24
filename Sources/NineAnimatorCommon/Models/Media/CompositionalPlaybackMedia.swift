//
//  This file is part of the NineAnimator project.
//
//  Copyright © 2018-2021 Marcus Zhou. All rights reserved.
//
//  NineAnimator is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  NineAnimator is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with NineAnimator.  If not, see <http://www.gnu.org/licenses/>.
//

import Alamofire
import AVKit
import CoreServices
import Foundation
import OpenCastSwift

/// A media container for retrieved media capable of modifying loading requests
public class CompositionalPlaybackMedia: NSObject, PlaybackMedia, AVAssetResourceLoaderDelegate {
    public let url: URL
    public let parent: Episode
    public let contentType: String
    public let headers: [String: String]
    public let subtitles: [SubtitleComposition]
    
    /// Playback session identifier
    public var sessionId: String? {
        if #available(iOS 16.0, *) {
            return self.asset?.httpSessionIdentifier.uuidString
        }
        
        return nil
    }
    
    private var requestHeaders: HTTPHeaders {
        var requestHeaders = HTTPHeaders(headers)
        
        if let sessionId {
            requestHeaders.add(name: "X-Playback-Session-Id", value: sessionId)
        }
        
        return requestHeaders
    }
    
    /// Previously created URL asset for this playback media
    private weak var asset: AVURLAsset?
    
    /// Strong references to the loading tasks/promises
    private var loadingTasks = [NSObject: NineAnimatorAsyncTask]()
    
    /// Caching requested vtt files
    private var cachedVttData = [URL: Data]()
    
    /// The delegate queue
    private let delegateQueue: DispatchQueue = .global()
    
    public init(url: URL, parent: Episode, contentType: String, headers: [String: String], subtitles: [SubtitleComposition]) {
        self.url = url
        self.parent = parent
        self.contentType = contentType
        self.headers = headers
        self.subtitles = subtitles
    }
    
    public func resourceLoader(
            _ resourceLoader: AVAssetResourceLoader,
            shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
        ) -> Bool {
        do {
            // Check if the request should be intercepted
            guard let requestingResourceUrl = loadingRequest.request.url else {
                return false
            }
            
            switch requestingResourceUrl.scheme {
            case interceptResourceScheme:
                return try loadingRequestInterception(
                    requestingResourceUrl: requestingResourceUrl,
                    loadingRequest: loadingRequest
                )
            case injectionSubtitlePlaylistScheme:
                return try loadingRequestInjectSubtitle(
                    requestingResourceUrl: requestingResourceUrl,
                    loadingRequest: loadingRequest
                )
            default: throw NineAnimatorError.urlError
            }
        } catch { Log.error("[CompositionalPlaybackMedia] Loading error: %@", error) }
        return false
    }
    
    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        // Cancels the loading task and removes the reference to it
        if let loadingTask = loadingTasks[loadingRequest] {
            loadingTask.cancel()
            loadingTasks.removeValue(forKey: loadingRequest)
        }
    }
}

// MARK: - Playlist modification
internal extension CompositionalPlaybackMedia {
    /// Generates and return subtitle playlists
    private func loadingRequestInjectSubtitle(requestingResourceUrl: URL, loadingRequest: AVAssetResourceLoadingRequest) throws -> Bool {
        // Obtain the subtitle information
        guard let subtitleTrackInformation = subtitles.first(where: {
            $0.url.uniqueHashingIdentifier == requestingResourceUrl.fragment
        }) else { return false }
        
        let vttCachedUrl = try swapScheme(
            forUrl: subtitleTrackInformation.url,
            withNewScheme: injectionCachedVttScheme
        )
        
        loadingTasks[loadingRequest] = requestVtt(vttCachedUrl).then {
            vttData -> Data? in
            
            let vttContentString = try String(
                data: vttData,
                encoding: .utf8
            ).tryUnwrap()
            let timestampMutipliers: [Double] = [ 3600, 60, 1 ]
            let vttEndTimestamp = try NSRegularExpression(
                pattern: "(?:\\d+:)?\\d+:[\\d\\.]+\\s+-->\\s+(?:(\\d+):)?(\\d+):([\\d\\.]+)",
                options: []
            ) .lastMatch(in: vttContentString)
                .tryUnwrap()
                .compactMap { Double($0) }
                .enumerated()
                .reduce(0) { $0 + timestampMutipliers[$1.offset] * $1.element }
            let numFormatter = NumberFormatter()
            numFormatter.maximumFractionDigits = 3
            numFormatter.minimumFractionDigits = 3
            numFormatter.minimumIntegerDigits = 1
            
            return """
                #EXTM3U
                #EXT-X-VERSION:3
                #EXT-X-MEDIA-SEQUENCE:1
                #EXT-X-PLAYLIST-TYPE:VOD
                #EXT-X-ALLOW-CACHE:NO
                #EXT-X-TARGETDURATION:\(Int(vttEndTimestamp))
                #EXTINF:\(numFormatter.string(from: NSNumber(value: vttEndTimestamp)) ?? "0.000"), no desc
                \(subtitleTrackInformation.url.absoluteString)
                #EXT-X-ENDLIST
                """.data(using: .utf8)
        } .error {
            [weak self] in
            guard self != nil else { return }
            loadingRequest.finishLoading(with: $0)
            Log.info(">>> DEBUG: Subtitle loading failed with error %@", $0)
        } .finally {
            [weak self] generatedPlaylist in
            guard self != nil else { return }
            
            // Respond with generated playlist data
            if let dataRequest = loadingRequest.dataRequest {
                dataRequest.respond(with: generatedPlaylist)
            }
            
            // Fill in data information
            if let infoRequest = loadingRequest.contentInformationRequest {
                infoRequest.contentType = "public.m3u-playlist"
                infoRequest.contentLength = Int64(generatedPlaylist.count)
                infoRequest.isByteRangeAccessSupported = false
            }
            
            Log.debug("[CompositionalPlaybackMedia] Responded with subtitle playlist content %@", String(data: generatedPlaylist, encoding: .utf8)!)
            
            // Informs that the loading has been completed
            loadingRequest.finishLoading()
        }
        
        return true
    }
    
    /// Intercept and modify the master playlist request
    private func loadingRequestInterception(requestingResourceUrl: URL, loadingRequest: AVAssetResourceLoadingRequest) throws -> Bool {
        // Redirect to original url
        let originalUrl = try swapScheme(forUrl: requestingResourceUrl, withNewScheme: "https")
        
        // Master playlist
        if originalUrl == url {
            loadingTasks[loadingRequest] = AF.request(
                originalUrl,
                method: .get,
                headers: self.requestHeaders
            ) .responseData {
                [subtitleCompositionGroupId, injectionSubtitlePlaylistScheme, subtitles] response in
                do {
                    switch response.result {
                    case let .success(playlistResponse):
                        // Reconstruct the playlist
                        let playlistContent = try String(
                            data: playlistResponse,
                            encoding: .utf8
                        ) .tryUnwrap(.decodeError)
                          .replacingOccurrences(
                            of: "(#EXT-X-STREAM-INF:.+)\\n",
                            with: "$1,SUBTITLES=\"\(subtitleCompositionGroupId)\"\n",
                            options: [.regularExpression]
                          ) .replacingOccurrences(
                            of: "#EXTM3U\\s*",
                            with: "",
                            options: [.regularExpression]
                          )
                          .trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Construct subtitle group
                        let subtitles = subtitles.map {
                            subtitleTrack in
                            let properties = [
                                ("TYPE", "SUBTITLES"),
                                ("GROUP-ID", "\"\(subtitleCompositionGroupId)\""),
                                ("NAME", "\"\(subtitleTrack.name)\""),
                                ("CHARACTERISTICS", "\"public.accessibility.transcribes-spoken-dialog\""),
                                ("DEFAULT", subtitleTrack.default ? "YES" : "NO"),
                                ("AUTOSELECT", subtitleTrack.autoselect ? "YES" : "NO"),
                                ("FORCED", subtitleTrack.forced ? "YES" : "NO"),
                                ("LANGUAGE", "\"\(subtitleTrack.language)\""),
                                ("URI", "\"\(injectionSubtitlePlaylistScheme)://subtitle.m3u8#\(subtitleTrack.url.uniqueHashingIdentifier)\"")
                            ]
                            let encodedProperties = properties.map {
                                "\($0.0)=\($0.1)"
                            }.joined(separator: ",")
                            return "#EXT-X-MEDIA:\(encodedProperties)"
                        } .joined(separator: "\n")
                        
                        // Convert to data
                        let playlistData = "#EXTM3U\n\(subtitles)\n\(playlistContent)".data(using: .utf8) ?? playlistResponse
                        
                        Log.debug("[CompositionalPlaybackMedia] Responded with playlist data:\n%@", String(decoding: playlistData, as: UTF8.self))
                        
                        // Respond with modified playlist data
                        if let dataRequest = loadingRequest.dataRequest {
                            dataRequest.respond(with: playlistData)
                        }
                        
                        // Fill in the request information
                        if let contentInformationRequest = loadingRequest.contentInformationRequest {
                            contentInformationRequest.contentType = "public.m3u-playlist"
                            contentInformationRequest.contentLength = Int64(playlistData.count)
                            contentInformationRequest.isByteRangeAccessSupported = false
                        }
                        
                        loadingRequest.finishLoading()
                    case let .failure(error): throw error
                    }
                } catch { loadingRequest.finishLoading(with: error) }
            }
        } else {
            loadingRequest.redirect = try URLRequest(
                url: originalUrl,
                method: .get,
                headers: loadingRequest.request.allHTTPHeaderFields ?? [:]
            )
            
            loadingRequest.response = HTTPURLResponse(
                url: originalUrl,
                statusCode: 302,
                httpVersion: nil,
                headerFields: loadingRequest.request.allHTTPHeaderFields ?? [:]
            )
            
            loadingRequest.finishLoading()
        }
        
        return true
    }
    
    private func requestVtt(_ url: URL) -> NineAnimatorPromise<Data> {
        do {
            // If the cache was found, return directly
            if let cachedVttData = self.cachedVttData[url] {
                Log.info("Subtitle is cached, returning directly")
                return .success(cachedVttData)
            }
            
            let vttUrl = try swapScheme(forUrl: url, withNewScheme: "https")
            
            // Request and cached the vtt
            return NineAnimatorPromise(queue: delegateQueue) {
                callback in AF.request(vttUrl).responseData {
                    response in
                    switch response.result {
                    case let .success(vttData): callback(vttData, nil)
                    case let .failure(error): callback(nil, error)
                    }
                }
            } .then {
                [weak self] (vttData: Data) in
                guard let self = self else { return nil }
                // Cache vtt data
                self.cachedVttData[url] = vttData
                return vttData
            }
        } catch { return NineAnimatorPromise.firstly(queue: delegateQueue) { throw error } }
    }
}

// MARK: - PlaybackMedia
public extension CompositionalPlaybackMedia {
    var avPlayerItem: AVPlayerItem {
        if let asset = self.asset {
            Log.debug("[CompositionalPlaybackMedia] Returning cached AVAsset for item with URL: %@", url)
            return AVPlayerItem(asset: asset)
        }
        
        let schemedUrl = (try? swapScheme(forUrl: url, withNewScheme: interceptResourceScheme)) ?? url
        Log.debug("[CompositionalPlaybackMedia] Creating AVAsset with scheme swapped for url %@", schemedUrl)
        
        let asset = AVURLAsset(
            url: schemedUrl,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        asset.resourceLoader.setDelegate(self, queue: delegateQueue)
        self.asset = asset
        
        return AVPlayerItem(asset: asset)
    }
    
    var link: EpisodeLink { parent.link }
    
    var name: String { parent.name }
    
    var castMedia: CastMedia? {
        CastMedia(
            title: parent.name,
            url: url,
            poster: parent.link.parent.image,
            contentType: contentType,
            streamType: .buffered,
            autoplay: true,
            currentTime: 0
        )
    }
    
    // SubtitledPlaybackMedia only works with HLS contents
    var isAggregated: Bool { true }
    var urlRequest: URLRequest? { nil }
    
    private var interceptResourceScheme: String {
        "na-compositional-media"
    }
    
    private var injectionSubtitlePlaylistScheme: String {
        "na-inject-subtitle"
    }
    
    private var injectionCachedVttScheme: String {
        "na-inject-cached-vtt"
    }
    
    private var subtitleCompositionGroupId: String {
        "nasub1"
    }
    
    private func swapScheme(forUrl originalUrl: URL, withNewScheme newScheme: String) throws -> URL {
        var components = try URLComponents(
            url: originalUrl,
            resolvingAgainstBaseURL: true
        ).tryUnwrap()
        components.scheme = newScheme
        return try components.url.tryUnwrap()
    }
}

public extension CompositionalPlaybackMedia {
    struct SubtitleComposition {
        public var url: URL
        public var name: String
        public var language: String
        
        public var `default`: Bool
        public var autoselect: Bool
        public var forced: Bool
        
        public init(url: URL, name: String, language: String, `default`: Bool = false, autoselect: Bool = false, forced: Bool = false) {
            self.url = url
            self.name = name
            self.language = language
            self.`default` = `default`
            self.autoselect = autoselect
            self.forced = forced
        }
    }
}
