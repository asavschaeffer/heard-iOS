import Foundation
import LinkPresentation

@MainActor
final class LinkMetadataStore: ObservableObject {
    @Published private(set) var metadataByKey: [String: LPLinkMetadata] = [:]
    private var inFlight: Set<String> = []

    func metadata(for key: String) -> LPLinkMetadata? {
        metadataByKey[key]
    }

    func prefetch(url: URL, key: String? = nil) {
        let cacheKey = key ?? url.absoluteString
        guard metadataByKey[cacheKey] == nil else { return }
        guard !inFlight.contains(cacheKey) else { return }
        inFlight.insert(cacheKey)

        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { [weak self] metadata, _ in
            Task { @MainActor in
                self?.inFlight.remove(cacheKey)
                if let metadata {
                    self?.metadataByKey[cacheKey] = metadata
                }
            }
        }
    }
}
