#!/usr/bin/swift
import Darwin
import Foundation

struct PublicationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func fail(_ message: String) -> PublicationError { PublicationError(message: message) }

func checkApp(_ app: URL) throws {
    var directory: ObjCBool = false
    guard app.pathExtension == "app",
          FileManager.default.fileExists(atPath: app.path, isDirectory: &directory), directory.boolValue else {
        throw fail("应用产物不存在或不是 .app 目录：\(app.path)")
    }
    let plist = app.appendingPathComponent("Contents/Info.plist")
    let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), options: [], format: nil)
    guard let info = value as? [String: Any],
          info["CFBundleIdentifier"] as? String == "com.acered.whisperingtime.prototype",
          let executable = info["CFBundleExecutable"] as? String,
          !executable.isEmpty, executable == (executable as NSString).lastPathComponent,
          FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/\(executable)").path) else {
        throw fail("应用标识或主执行文件校验失败：\(app.path)")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = ["--verify", "--deep", "--strict", app.path]
    let errors = Pipe()
    process.standardError = errors
    try process.run()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationReason == .exit && process.terminationStatus == 0 else {
        throw fail("应用签名校验失败：\(app.path)\n\(String(decoding: diagnostics, as: UTF8.self))")
    }
}

// lstat also rejects a dangling symbolic link, which fileExists would overlook.
func checkAliasDestination(_ alias: URL) throws -> Bool {
    var metadata = stat()
    if lstat(alias.path, &metadata) != 0 {
        if errno == ENOENT { return false }
        throw fail("无法检查桌面替身：\(String(cString: strerror(errno)))")
    }
    guard metadata.st_mode & S_IFMT == S_IFREG,
          try alias.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile == true else {
        throw fail("桌面入口已被普通文件、目录或符号链接占用，已保留：\(alias.path)")
    }
    return true
}

func verifyAlias(_ alias: URL, target: URL) throws {
    guard try checkAliasDestination(alias) else { throw fail("未生成 Finder 替身：\(alias.path)") }
    let resolved = try URL(resolvingAliasFileAt: alias, options: [.withoutUI, .withoutMounting])
    guard resolved.resolvingSymlinksInPath().standardizedFileURL == target.resolvingSymlinksInPath().standardizedFileURL else {
        throw fail("Finder 替身目标不是本次产物：\(resolved.path)")
    }
}

func atomicRename(_ source: URL, _ destination: URL) throws {
    guard rename(source.path, destination.path) == 0 else {
        throw fail("原子更新失败：\(destination.path)：\(String(cString: strerror(errno)))")
    }
}

func publish(source: URL, root: URL, alias: URL) throws {
    let manager = FileManager.default
    try checkApp(source)
    var desktopIsDirectory: ObjCBool = false
    guard manager.fileExists(atPath: alias.deletingLastPathComponent().path, isDirectory: &desktopIsDirectory), desktopIsDirectory.boolValue else {
        throw fail("桌面目录不存在：\(alias.deletingLastPathComponent().path)")
    }
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    let lockPath = root.appendingPathComponent(".publication.lock").path
    let descriptor = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw fail("无法创建发布锁：\(String(cString: strerror(errno)))") }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw fail("无法取得发布锁：\(String(cString: strerror(errno)))") }
    defer { flock(descriptor, LOCK_UN) }
    _ = try checkAliasDestination(alias)

    let identifier = UUID().uuidString
    let staging = root.appendingPathComponent(".staging-\(identifier)", isDirectory: true)
    let publication = root.appendingPathComponent(identifier, isDirectory: true)
    let stagedApp = staging.appendingPathComponent("WhisperingTime.app", isDirectory: true)
    let publishedApp = publication.appendingPathComponent("WhisperingTime.app", isDirectory: true)
    let temporaryAlias = alias.deletingLastPathComponent().appendingPathComponent(".印迹-\(identifier).alias")
    let backupAlias = alias.deletingLastPathComponent().appendingPathComponent(".印迹-\(identifier).previous")
    var committed = false
    var retainBackup = false
    defer {
        try? manager.removeItem(at: staging)
        try? manager.removeItem(at: temporaryAlias)
        if !retainBackup { try? manager.removeItem(at: backupAlias) }
        if !committed { try? manager.removeItem(at: publication) }
    }
    try manager.createDirectory(at: staging, withIntermediateDirectories: false)
    try manager.copyItem(at: source, to: stagedApp)
    try checkApp(stagedApp)
    try atomicRename(staging, publication)
    try checkApp(publishedApp)

    let bookmark = try publishedApp.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
    try URL.writeBookmarkData(bookmark, to: temporaryAlias)
    try verifyAlias(temporaryAlias, target: publishedApp)
    // Recheck after copying so an ordinary file added meanwhile is never overwritten.
    let replacingAlias = try checkAliasDestination(alias)
    if replacingAlias { try manager.copyItem(at: alias, to: backupAlias) }
    try atomicRename(temporaryAlias, alias)
    do {
        try verifyAlias(alias, target: publishedApp)
        try checkApp(publishedApp)
    } catch {
        let publicationError = error
        do {
            if replacingAlias { try atomicRename(backupAlias, alias) }
            else { try manager.removeItem(at: alias) }
        } catch {
            // Retain both the new app and backup if rollback itself fails.
            committed = true
            retainBackup = true
            throw fail("替身核验失败，且回滚失败：\(error.localizedDescription)；原替身备份：\(backupAlias.path)；原始错误：\(publicationError.localizedDescription)")
        }
        throw publicationError
    }
    committed = true
    print("桌面 Finder 替身已更新并核验：\(alias.path)")
    print("本次成功构建的应用副本：\(publishedApp.path)")
    print("原始构建产物：\(source.path)")
}

do {
    guard CommandLine.arguments.count == 4 else {
        throw fail("用法：swift update-desktop-app.swift <source.app> <publication-root> <desktop-alias>")
    }
    try publish(
        source: URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.resolvingSymlinksInPath(),
        root: URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL.resolvingSymlinksInPath(),
        alias: URL(fileURLWithPath: CommandLine.arguments[3]).standardizedFileURL
    )
} catch {
    FileHandle.standardError.write(Data("error: 桌面应用交付失败：\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
