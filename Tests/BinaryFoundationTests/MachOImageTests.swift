import Foundation
import TestSupport
import Testing

@testable import BinaryFoundation

private struct FakeFileManager: FileExistenceChecking {
  let existing: Set<String>
  func fileExists(atPath path: String) -> Bool { existing.contains(path) }
}

@Suite(.spec("domain.macho-image"))
struct MachOImageTests {
  @Test func `prefers a runtime-root sim cache, else the host cache`() {
    let simCache = "/Runtime/System/Library/Caches/com.apple.dyld/dyld_sim_shared_cache_arm64e"
    let fake = FakeFileManager(existing: [simCache])
    #expect(MachOImage.sharedCachePath(runtimeRoots: ["/Runtime"], fileManager: fake) == simCache)

    let empty = FakeFileManager(existing: [])
    #expect(
      MachOImage.sharedCachePath(runtimeRoots: [], fileManager: empty)
        == "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e")
  }

  @Test func `derives versioned, runtime-root-stripped, and canonical cache paths`() {
    let path = "/Runtime/System/Library/Frameworks/Foo.framework/Foo"
    let paths = MachOImage.normalizedCacheImagePaths(for: path, runtimeRoots: ["/Runtime"])

    #expect(paths.first == path)
    #expect(paths.contains("/System/Library/Frameworks/Foo.framework/Foo"))
    #expect(paths.contains("/Runtime/System/Library/Frameworks/Foo.framework/Versions/Current/Foo"))
    #expect(paths.contains("/Runtime/System/Library/Frameworks/Foo.framework/Versions/A/Foo"))
    #expect(Set(paths).count == paths.count)

    let usrPaths = MachOImage.normalizedCacheImagePaths(
      for: "/Runtime/usr/lib/libobjc.A.dylib", runtimeRoots: ["/Runtime"])
    #expect(usrPaths.contains("/usr/lib/libobjc.A.dylib"))
  }
}
