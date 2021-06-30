//
//  This file is part of the NineAnimator project.
//
//  Copyright © 2018-2020 Marcus Zhou. All rights reserved.
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

import Kingfisher

public extension KingfisherError {
    var shortenedDescription: String {
        switch self {
        case let .requestError(reason): return reason.shortenedDescription
        case let .responseError(reason): return reason.shortenedDescription
        case let .cacheError(reason): return reason.shortenedDescription
        case let .processorError(reason): return reason.shortenedDescription
        case let .imageSettingError(reason): return reason.shortenedDescription
        }
    }
}

public extension KingfisherError.RequestErrorReason {
    var shortenedDescription: String {
        switch self {
        case .emptyRequest:
            return "The request is empty or `nil`."
        case .invalidURL:
            return "The request contains an invalid or empty URL."
        case .taskCancelled:
            return "The session task was cancelled."
        }
    }
}

public extension KingfisherError.ResponseErrorReason {
    var shortenedDescription: String {
        switch self {
        case .invalidURLResponse:
            return "The URL response is invalid."
        case let .invalidHTTPStatusCode(response):
            return "The HTTP status code in response is invalid. Code: \(response.statusCode)."
        case let .URLSessionError(error):
            return "A URL session error happened. The underlying error: \(error.localizedDescription)"
        case .dataModifyingFailed:
            return "The data modifying delegate returned `nil` for the downloaded data."
        case .noURLResponse:
            return "No URL response received."
        }
    }
}

public extension KingfisherError.CacheErrorReason {
    var shortenedDescription: String {
        switch self {
        case let .fileEnumeratorCreationFailed(url):
            return "Cannot create file enumerator for URL: \(url)."
        case let .invalidFileEnumeratorContent(url):
            return "Cannot get contents from the file enumerator at URL: \(url)."
        case let .invalidURLResource(error, key, url):
            return "Cannot get URL resource values or data for the given URL: \(url). " +
                "Cache key: \(key). Underlying error: \(error)"
        case let .cannotLoadDataFromDisk(url, error):
            return "Cannot load data from disk at URL: \(url). Underlying error: \(error)"
        case let .cannotCreateDirectory(path, error):
            return "Cannot create directory at given path: Path: \(path). Underlying error: \(error)"
        case let .imageNotExisting(key):
            return "The image is not in cache, but you requires it should only be " +
                "from cache by enabling the `.onlyFromCache` option. Key: \(key)."
        case let .cannotConvertToData(object, error):
            return "Cannot convert the input object to a `Data` object when storing it to disk cache. " +
                "Object: \(object). Underlying error: \(error)"
        case .cannotSerializeImage:
            return "Cannot serialize an image due to the cache serializer returning `nil`. "
        case let .cannotCreateCacheFile(fileURL, key, data, error):
            return "Cannot create cache file at url: \(fileURL), key: \(key), data length: \(data.count). " +
                "Underlying foundation error: \(error.localizedDescription)."
        case let .cannotSetCacheFileAttribute(filePath, attributes, error):
            return "Cannot set file attribute for the cache file at path: \(filePath), attributes: \(attributes)." +
                "Underlying foundation error: \(error.localizedDescription)."
        case .diskStorageIsNotReady:
            return "Could not create cache folder to due low disk space."
        }
    }
}

public extension KingfisherError.ProcessorErrorReason {
    var shortenedDescription: String {
        switch self {
        case .processingFailed:
            return "Processing image failed."
        }
    }
}

public extension KingfisherError.ImageSettingErrorReason {
    var shortenedDescription: String {
        switch self {
        case .emptySource:
            return "The input resource is empty."
        case .notCurrentSourceTask:
            return "Retrieving resource succeeded, but this source is " +
                "not the one currently expected."
        case let .dataProviderError(_, error):
            return "Image data provider fails to provide data. error: \(error.localizedDescription)"
        case .alternativeSourcesExhausted:
            return "Image setting from alternative sources failed"
        }
    }
}
