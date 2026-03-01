import Photos
import Foundation

enum VideoLibrarySaver {
    static func saveVideo(url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        requestPermission { granted in
            guard granted else {
                completion(.failure(SaveError.accessDenied))
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                if success {
                    completion(.success(()))
                } else {
                    completion(.failure(SaveError.unknown))
                }
            }
        }
    }

    private static func requestPermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                completion(status == .authorized || status == .limited)
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                completion(status == .authorized)
            }
        }
    }

    enum SaveError: LocalizedError {
        case accessDenied
        case unknown

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Photo Library access denied."
            case .unknown:
                return "Could not save the video."
            }
        }
    }
}
