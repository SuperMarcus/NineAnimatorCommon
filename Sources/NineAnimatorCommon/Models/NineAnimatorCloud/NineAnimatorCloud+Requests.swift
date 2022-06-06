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
import Foundation

// MARK: - Requesting Source Descriptors
public extension NineAnimatorCloud {
    func requestSourceDescriptor<SourceDescriptorType: Decodable>(
        source: Source,
        descriptorType: SourceDescriptorType.Type
    ) -> NineAnimatorPromise<SourceDescriptorType> {
        requestManager.request(resourcePath: "descriptor/\(source.name)", responseType: descriptorType)
    }
}

// MARK: - Requesting Availability Information
public extension NineAnimatorCloud {
    /// Retrieves the availability data, returns a cached version if it exists
    func retrieveAvailabilityData() -> NineAnimatorPromise<VersionedAppAvailabilityData> {
        // Check if the availability data is loaded in cache
        if let cachedData = self._cachedAvailabilityData,
           let cacheLastUpdateElapsed = self._cachedAvailabilityDataLastUpdate?.timeIntervalSinceNow,
           (cacheLastUpdateElapsed + Self.availablilityDataRenewInterval) > 0 {
            return .success(cachedData)
        }
        
        return self._tryRenewAvailabilityData()
    }
    
    /// Start availability renewal task in the background
    func renewAvailabilityData() {
        Log.debug("[NineAnimatorCloud] Renewing availability data...")
        _availabilityDataRenewTask = self._tryRenewAvailabilityData()
            .dispatch(on: _requestProcessingQueue)
            .defer { _ in self._availabilityDataRenewTask = nil }
            .error {
                error in Log.error("[NineAnimatorCloud] Failed to renew availability data due to error: %@", error)
            }
            .finally { _ in }
    }
    
    /// Push availability data to sources
    internal func pushAvailabilityData(outdatedData: VersionedAppAvailabilityData?, updatedData: VersionedAppAvailabilityData) {
        Log.info("[NineAnimator] Pushing availability data to sources...")
        updatedData.sources.forEach {
            sourceData in
            // Find matching old entries
            let matchingOutdatedEntry = outdatedData?.sources.first {
                $0.name == sourceData.name
            }
            
            // Only update if the current entry has a newer status than the old one.
            if matchingOutdatedEntry?.status.updateDate != sourceData.status.updateDate,
                let baseSource = NineAnimator.default.source(with: sourceData.name) as? BaseSource {
                baseSource.onAvailabilityUpdate(newAvailabilityData: sourceData)
            }
        }
    }
}

internal extension NineAnimatorCloud {
    func _tryRenewAvailabilityData() -> NineAnimatorPromise<VersionedAppAvailabilityData> {
        // Wrapping a promise within promise here. Definetly not a good practice...
        return .init(queue: self._requestProcessingQueue) {
            errorSilencedCallback in
            // Copy the previous data for reference
            let previouslyCachedData = self._cachedAvailabilityData
            
            // First and foremost, try to load the data from file system so we restore the cache
            do {
                try self._loadAvailabilityDataFromFileCache()
            } catch {
                Log.error("[NineAnimatorCloud] Failed to load availability data from file system: %@. Continuing with the request...", error)
            }
            
            // Using the request initiation time as "last update" time
            let requestInitiationDate = Date()
            var requestAdditionalHeaders = HTTPHeaders()
            let expectedSourceNames = Array(NineAnimator.default.sources.keys)
            
            if let cachedData = self._cachedAvailabilityData {
                let dateFormatter = ISO8601DateFormatter()
                requestAdditionalHeaders.add(name: "Cache-LastUpdate", value: dateFormatter.string(from: cachedData.lastUpdate))
            }
            
            requestAdditionalHeaders.add(name: "App-DefinedSources", value: expectedSourceNames.joined(separator: ","))
            requestAdditionalHeaders.add(name: "App-DefinedSourcesCount", value: String(expectedSourceNames.count))
            
            // Making request to the availability route
            return self.requestManager.request(
                resourcePath: "availability",
                responseType: VersionedAppAvailabilityData.self,
                headers: requestAdditionalHeaders
            ) .dispatch(on: self._requestProcessingQueue)
                .then {
                    availabilityData -> VersionedAppAvailabilityData in
                    try self._cacheAvailabiliyData(availabilityData)
                    return availabilityData
                }
                .error {
                    error in
                    if let cachedAvailabilityData = self._cachedAvailabilityData {
                        // Sort of an awkward way of detecting "no change"...but it works lol
                        if let naCloudError = error as? NineAnimatorError.NineAnimatorCloudError,
                           naCloudError.statusCode == 304 {
                            self._cachedAvailabilityDataLastUpdate = requestInitiationDate
                            Log.debug("[NineAnimatorCloud] Renewed availablibilty data.")
                        } else {
                            Log.info("[NineAnimatorCloud] Couldn't renew availability data due to error: %@. Returning cached data...", error)
                        }
                        
                        errorSilencedCallback(cachedAvailabilityData, nil)
                    } else {
                        Log.info("[NineAnimatorCloud] Couldn't renew availability data due to error: %@. No cached data was found, sending error...", error)
                        errorSilencedCallback(nil, error)
                    }
                }
                .finally {
                    data in
                    // New availability data received
                    self._cachedAvailabilityDataLastUpdate = requestInitiationDate
                    self._cachedAvailabilityData = data
                    errorSilencedCallback(data, nil)
                    
                    // Push the availability data to sources and notify that the availability data has changed
                    self._requestProcessingQueue.async {
                        self.pushAvailabilityData(outdatedData: previouslyCachedData, updatedData: data)
                        NotificationCenter.default.post(name: .availabilityDataDidUpdate, object: self)
                    }
                }
        }
    }
    
    func _cacheAvailabiliyData(_ availabilityData: VersionedAppAvailabilityData) throws {
        let cacheFilePath = try _retrieveAvailabilityDataCacheFilePath()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let encodedData = try encoder.encode(availabilityData)
        try encodedData.write(to: cacheFilePath, options: [])
        self._cachedAvailabilityData = availabilityData
    }
    
    func _retrieveAvailabilityDataCacheFilePath() throws -> URL {
        let appSupportDir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .allDomainsMask,
            appropriateFor: nil,
            create: true
        )
        
        return appSupportDir.appendingPathComponent("com.marcuszhou.nineanimator.NineAnimatorCloud.availability.plist")
    }
    
    func _loadAvailabilityDataFromFileCache() throws {
        if case .none = self._cachedAvailabilityData {
            let cacheFilePath = try _retrieveAvailabilityDataCacheFilePath()
            if (try? cacheFilePath.checkResourceIsReachable()) == true {
                let encodedData = try Data(contentsOf: cacheFilePath, options: [])
                let decoder = PropertyListDecoder()
                let decodedObject = try decoder.decode(VersionedAppAvailabilityData.self, from: encodedData)
                
                if decodedObject.version.version == .current {
                    self._cachedAvailabilityData = decodedObject
                } else {
                    Log.info("[NineAnimatorCloud] File system cached availability data was for version %@, which is outdated.", decodedObject.version)
                }
            }
        }
    }
}

// MARK: - API Object Types
public extension NineAnimatorCloud {
    struct APIResponse<DataType: Decodable>: Decodable {
        public var data: DataType?
        public var status: Int
        public var message: String
    }
}

/// A private network request manager used only by the NineAnimatorCloud service
public class NACloudRequestManager: NAEndpointRelativeRequestManager {
    unowned var parent: NineAnimatorCloud
    
    internal init(parent: NineAnimatorCloud) {
        self.parent = parent
        super.init(endpoint: NineAnimatorCloud.baseUrl)
    }
    
    public func request<ResponseType: Decodable>(
        resourcePath: String,
        responseType: ResponseType.Type,
        method: HTTPMethod = .get,
        query: URLQueryParameters? = nil,
        parameters: Parameters? = nil,
        encoding: ParameterEncoding = URLEncoding.default,
        headers: HTTPHeaders? = nil
    ) -> NineAnimatorPromise<ResponseType> {
        // Init decoder for standard NACloud API responses
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        
        let customDecoder = JSONDecoder()
        customDecoder.dateDecodingStrategy = .formatted(dateFormatter)
        customDecoder.keyDecodingStrategy = .convertFromSnakeCase
        customDecoder.dataDecodingStrategy = .base64
        
        let executableName = (Bundle.main.infoDictionary?["CFBundleExecutable"] as? String) ??
                    (ProcessInfo.processInfo.arguments.first?.split(separator: "/").last.map(String.init)) ??
                    "Unknown"
        
        var modifiedHeaders = headers ?? HTTPHeaders()
        modifiedHeaders.add(name: "Binary-ReleaseVersion", value: NineAnimator.default.version)
        modifiedHeaders.add(name: "Binary-ReleaseBuild", value: String(NineAnimator.default.buildNumber))
        modifiedHeaders.add(name: "Binary-BuildID", value: self.parent.buildIdentifier)
        modifiedHeaders.add(
            name: "Binary-BundleID",
            value: (Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String) ?? "com.unknown.app.bundle"
        )
        modifiedHeaders.add(name: "Binary-Executable", value: executableName)
        modifiedHeaders.add(name: "Accept", value: "application/json")
        
        return self.request(resourcePath, method: method, query: query, parameters: parameters, encoding: encoding, headers: modifiedHeaders)
            .responseDecodable(type: NineAnimatorCloud.APIResponse<ResponseType>.self, decoder: customDecoder)
            .then {
                responseObject in
                if (200..<300).contains(responseObject.status), let data = responseObject.data {
                    return data
                } else {
                    throw NineAnimatorError.NineAnimatorCloudError(statusCode: responseObject.status, message: responseObject.message)
                }
            }
    }
}
