import Foundation
import MachOKit

// SPEC: domain.macho-image
/// Abstracts file-existence checks so callers can inject a fake in tests.
public protocol FileExistenceChecking {
  func fileExists(atPath: String) -> Bool
}

extension FileManager: FileExistenceChecking {}

// SPEC: domain.macho-image
/// Loading a Mach-O image from disk or the dyld shared cache — handling universal
/// (fat) binaries and runtime-root rebasing. Pure: callers pass the dyld
/// runtime-root candidates (read from the environment at the tool's edge), so
/// this stays free of process-environment policy. Shared by the static-analysis
/// cluster (`headerdump`, and `redump`).
public enum MachOImage {
  /// Load `url` as a supported Mach-O slice, falling back to the dyld shared
  /// cache when `useSharedCache` is set or the file can't be read directly.
  public static func load(at url: URL, useSharedCache: Bool, runtimeRoots: [String]) -> MachOFile? {
    if useSharedCache,
      let cached = loadFromSharedCache(imagePath: url.path, runtimeRoots: runtimeRoots)
    {
      return cached
    }
    do {
      let file = try loadFromFile(url: url)
      switch file {
      case .machO(let machO):
        return isSupported(machO) ? machO : nil
      case .fat(let fat):
        let machOFiles = try fat.machOFiles()
        if let match = machOFiles.first(where: { isSupported($0) }) {
          return match
        }
        return nil
      }
    } catch {
      if useSharedCache {
        return loadFromSharedCache(imagePath: url.path, runtimeRoots: runtimeRoots)
      }
      return nil
    }
  }

  /// True for arm64 / x86_64 slices.
  public static func isSupported(_ machO: MachOFile) -> Bool {
    switch machO.header.cpuType {
    case .arm64, .x86_64:
      return true
    default:
      return false
    }
  }

  /// Resolve `imagePath` out of the active dyld shared cache, trying the
  /// versioned / runtime-root-rebased candidate paths.
  public static func loadFromSharedCache(imagePath: String, runtimeRoots: [String]) -> MachOFile? {
    let cachePath = sharedCachePath(runtimeRoots: runtimeRoots)
    guard let fullCache = try? FullDyldCache(url: URL(fileURLWithPath: cachePath)) else {
      return nil
    }
    let candidates = normalizedCacheImagePaths(for: imagePath, runtimeRoots: runtimeRoots)
    if let match = fullCache.machOFiles().first(where: { candidates.contains($0.imagePath) }) {
      return match
    }
    for candidate in candidates {
      if let match = fullCache.machOFiles().first(where: { $0.imagePath.hasSuffix(candidate) }) {
        return match
      }
    }
    return nil
  }

  /// Candidate cache image paths for `path`: versioned framework variants,
  /// runtime-root-stripped paths, and canonical `/System/Library` / `/usr/lib` forms.
  public static func normalizedCacheImagePaths(for path: String, runtimeRoots: [String]) -> [String]
  {
    var results: [String] = [path]

    // On macOS, cache entries for frameworks frequently use versioned image paths
    // (e.g. ".../Foo.framework/Versions/A/Foo"), while callers may provide
    // ".../Foo.framework/Foo". Include common versioned variants so cache lookup
    // still resolves when the unversioned symlink target is absent.
    if let frameworkRange = path.range(of: ".framework/"), !path.contains(".framework/Versions/") {
      let frameworkPrefix = String(path[..<frameworkRange.upperBound])
      let imageName = URL(fileURLWithPath: path).lastPathComponent
      if !imageName.isEmpty {
        results.append(frameworkPrefix + "Versions/Current/" + imageName)
        results.append(frameworkPrefix + "Versions/A/" + imageName)
        results.append(frameworkPrefix + "Versions/B/" + imageName)
        results.append(frameworkPrefix + "Versions/C/" + imageName)
      }
    }

    for runtimeRoot in runtimeRoots {
      let trimmedRoot = runtimeRoot.hasSuffix("/") ? String(runtimeRoot.dropLast()) : runtimeRoot
      if path.hasPrefix(trimmedRoot + "/") {
        let suffix = String(path.dropFirst(trimmedRoot.count))
        if !suffix.isEmpty {
          results.append(suffix)
        }
      }
    }

    if let range = path.range(of: "/System/Library/") {
      results.append(String(path[range.lowerBound...]))
    }
    if let range = path.range(of: "/usr/lib/") {
      results.append(String(path[range.lowerBound...]))
    }

    var unique: [String] = []
    for item in results where !unique.contains(item) {
      unique.append(item)
    }
    return unique
  }

  /// The path to the active dyld shared cache, preferring a runtime-root sim
  /// cache when present, else the host cache.
  public static func sharedCachePath(
    runtimeRoots: [String],
    fileManager: FileExistenceChecking = FileManager.default
  ) -> String {
    for runtimeRoot in runtimeRoots {
      let simArm64eCandidate = URL(fileURLWithPath: runtimeRoot)
        .appendingPathComponent("System/Library/Caches/com.apple.dyld/dyld_sim_shared_cache_arm64e")
      if fileManager.fileExists(atPath: simArm64eCandidate.path) {
        return simArm64eCandidate.path
      }

      let simArm64Candidate = URL(fileURLWithPath: runtimeRoot)
        .appendingPathComponent("System/Library/Caches/com.apple.dyld/dyld_sim_shared_cache_arm64")
      if fileManager.fileExists(atPath: simArm64Candidate.path) {
        return simArm64Candidate.path
      }

      let candidate = URL(fileURLWithPath: runtimeRoot)
        .appendingPathComponent("System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e")
      if fileManager.fileExists(atPath: candidate.path) {
        return candidate.path
      }

      let arm64Candidate = URL(fileURLWithPath: runtimeRoot)
        .appendingPathComponent("System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64")
      if fileManager.fileExists(atPath: arm64Candidate.path) {
        return arm64Candidate.path
      }
    }

    let primary = "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e"
    if fileManager.fileExists(atPath: primary) {
      return primary
    }

    let candidates = [
      "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e",
      "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64",
      "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64",
      "/private/var/db/dyld/dyld_shared_cache_arm64e",
      "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64",
      "/private/var/db/dyld/dyld_shared_cache_x86_64",
      "/private/var/db/dyld/dyld_shared_cache_arm64",
    ]
    for candidate in candidates where fileManager.fileExists(atPath: candidate) {
      return candidate
    }
    return primary
  }
}
