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

import Foundation

/// An object that handles retrieving updates for cached anime
public struct AnimeWatcher {
    /// An object representing a cached version of an `Anime`
    public struct CachedAnime: Codable {
        /// `AnimeLink` of the cached Anime
        public let link: AnimeLink
        /// List of episode names
        public let episodeNames: [String]
        /// Creation date of the cache
        public let lastCheck: Date
    }
    
    /// An object representing the changes between a cached version and a recently fetched version of an anime
    public struct FetchResult {
        /// The `AnimeLink` of the cached and recently fetched anime
        public let animeLink: AnimeLink
        /// Array of episode titles which were not present on the cached version
        public let newEpisodeTitles: [String]
        /// Array of server names the `newEpisodeTitles` are available on
        public let availableServerNames: [String]
    }
    
    private let cachedAnimeDirectory: URL
    
    public init() {
        let fs = FileManager.default
        let topLevelCacheDirectory = try! fs.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        
        cachedAnimeDirectory =  topLevelCacheDirectory.appendingPathComponent("NineAnimatorAnimeCache")
        
        try! fs.createDirectory(
            at: cachedAnimeDirectory,
            withIntermediateDirectories: true
        )
    }
    
    /// Creates a cached copy of an anime and saves it to the file system
    /// - Parameter anime: Anime object to cache
    public func saveCachedCopy(of anime: Anime) {
        let cachedCopy = CachedAnime(
            link: anime.link,
            episodeNames: anime.episodes.uniqueEpisodeNames,
            lastCheck: Date()
        )
        saveToFileSystem(cachedCopy)
    }
    
    /// Saves a cached copy of an anime to the file system
    private func saveToFileSystem(_ cache: CachedAnime) {
        do {
            let pathToSave = generateCacheURL(for: cache.link)
            let encoder = PropertyListEncoder()
            let serializedCache = try encoder.encode(cache)
            try serializedCache.write(to: pathToSave)
        } catch { Log.error("[AnimeWatcher] Unable to persist cached anime:  %@", error) }
    }
    
    /// Removes all cached copies of anime from the file system
    public func removeAllCachedAnime() {
        do {
            let fs = FileManager.default
            let cachedAnimeURLs = try fs.contentsOfDirectory(
                at: cachedAnimeDirectory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            try cachedAnimeURLs.forEach { cachedAnimeURL in
                try fs.removeItem(at: cachedAnimeURL)
            }
        } catch {
            Log.error("[AnimeWatcher] Unable to remove all cached anime - %@", error)
        }
    }
    
    /// Retrieves a cached copy of an anime from the file system
    public func retrieveCachedCopy(ofAnimeWithLink animeLink: AnimeLink) -> CachedAnime? {
        do {
            let correspondingURL = generateCacheURL(for: animeLink)
            if FileManager.default.fileExists(atPath: correspondingURL.path),
                try correspondingURL.checkResourceIsReachable() {
                let serializedCache = try Data(contentsOf: correspondingURL)
                let decoder = PropertyListDecoder()
                return try decoder.decode(CachedAnime.self, from: serializedCache)
            }
        } catch { Log.error("[AnimeWatcher] Unable to retrieve cached copy for anime - %@", error) }
        return nil
    }
    
    /// Removes a cached copy of an anime from the file system
    public func removeCachedCopy(ofAnimeWithLink animeLink: AnimeLink) {
        do {
            let fileManager = FileManager.default
            let correspondingURL = generateCacheURL(for: animeLink)
            
            if fileManager.fileExists(atPath: correspondingURL.path) {
                try fileManager.removeItem(at: correspondingURL)
            }
        } catch { Log.error("[UserNotificationManager] Unable to remove persisted watcher - %@", error) }
    }
}

// MARK: - Cache Updater
extension AnimeWatcher {
    public func retrieveAndUpdateCachedCopyOf(_ animeLink: AnimeLink) -> NineAnimatorPromise<FetchResult> {
        NineAnimator.default.anime(with: animeLink).then {
            anime in
            defer {
                // Create and save the updated cached copy
                self.saveCachedCopy(of: anime)
            }
            
            guard let previousCachedCopy = self.retrieveCachedCopy(ofAnimeWithLink: animeLink) else {
                Log.info("[AnimeWatcher] Cached copy of Anime '%@' is being updated but has not been previously cached yet. Returning no content updates", anime.link.title)
                return FetchResult(
                    animeLink: animeLink,
                    newEpisodeTitles: [],
                    availableServerNames: []
                )
            }
            
            let newEpisodeTitles = anime.episodes.uniqueEpisodeNames.filter {
                !previousCachedCopy.episodeNames.contains($0)
            }
            
            let serverNames = newEpisodeTitles
                .flatMap(anime.episodes.links)
                .reduce(into: [Anime.ServerIdentifier]()) {
                    if !$0.contains($1.server) {
                        $0.append($1.server)
                    }
                }
                .compactMap { anime.servers[$0] }
            
            return FetchResult(
                animeLink: animeLink,
                newEpisodeTitles: newEpisodeTitles,
                availableServerNames: serverNames
            )
        }
    }
    
    /// Performs an update for the user's subscribed anime, checking for new content
    /// - Returns: Array of objects showing any content updates for every subscribed anime
    public func performUpdateForSubscribedAnime() -> NineAnimatorPromise<[FetchResult]> {
        let subscribedAnimes = NineAnimator.default.user.subscribedAnimes
        
        guard !subscribedAnimes.isEmpty else { return .success([]) }
        
        return NineAnimatorPromise<[FetchResult]>.queue(
            listOfPromises: subscribedAnimes.map {
                retrieveAndUpdateCachedCopyOf($0)
            }
        )
    }
}

// MARK: - Helper Methods
private extension AnimeWatcher {
    /// Generates the location where a cached version of an anime can be saved to the file system
    func generateCacheURL(for animeLink: AnimeLink) -> URL {
        let linkHashRepresentation = animeLink.link.uniqueHashingIdentifier
        let filename = "com.marcuszhou.NineAnimator.anime.\(linkHashRepresentation).plist"
        return self.cachedAnimeDirectory.appendingPathComponent(filename)
    }
}
