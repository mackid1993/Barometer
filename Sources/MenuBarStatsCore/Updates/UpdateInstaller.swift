import Foundation
import Security

/// Installs a verified Barometer DMG after the running app exits.
public enum UpdateInstaller {
    private static let installScript = #"""
    set -eu
    dmg=$1
    mount=$2
    applications=$3
    pid=$4
    relaunch=$5
    requirement=$6
    replacement="$applications/.Barometer.app.update"
    backup="$applications/.Barometer.app.backup"

    cleanup() {
        /usr/bin/hdiutil detach "$mount" -force >/dev/null 2>&1 || true
        /bin/rm -rf "$mount"
    }
    trap cleanup EXIT HUP INT TERM

    if [ -n "$pid" ]; then
        /bin/kill -TERM "$pid" 2>/dev/null || true
        attempts=0
        while /bin/kill -0 "$pid" 2>/dev/null; do
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 50 ]; then
                /bin/kill -KILL "$pid" 2>/dev/null || true
                break
            fi
            /bin/sleep 0.1
        done
    fi

    /bin/rm -rf "$mount"
    /bin/mkdir -p "$mount"
    /usr/bin/hdiutil attach "$dmg" -mountpoint "$mount" -nobrowse -readonly >/dev/null
    app="$mount/Barometer.app"
    [ -d "$app" ]
    [ -f "$app/Contents/MacOS/Barometer" ]
    identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
    [ "$identifier" = "com.barometer.app" ]
    links=$(/usr/bin/find "$app" -type l -print)
    [ -z "$links" ]
    /usr/bin/codesign --verify --deep --strict -R="$requirement" "$app"

    /bin/mkdir -p "$applications"
    /bin/rm -rf "$replacement"
    /usr/bin/ditto "$app" "$replacement"
    /usr/bin/codesign --verify --deep --strict -R="$requirement" "$replacement"
    /bin/rm -rf "$backup"
    had_existing=no
    if [ -e "$applications/Barometer.app" ]; then
        /bin/mv "$applications/Barometer.app" "$backup"
        had_existing=yes
    fi
    if ! /bin/mv "$replacement" "$applications/Barometer.app"; then
        if [ "$had_existing" = "yes" ]; then
            /bin/mv "$backup" "$applications/Barometer.app" || true
        fi
        exit 1
    fi
    /bin/rm -rf "$backup"
    cleanup
    trap - EXIT HUP INT TERM
    /bin/rm -f "$dmg"

    if [ "$relaunch" = "yes" ]; then
        /usr/bin/open "$applications/Barometer.app"
    fi
    """#

    /// Verifies that the downloaded file is a readable disk image before ending the running app.
    public static func verifyDiskImage(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["verify", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateInstallationError.unreadableDiskImage
        }
    }

    /// Starts a detached installer that waits for this process, replaces the app, and relaunches it.
    public static func scheduleInstallation(
        diskImage: URL,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws {
        let designatedRequirement = try runningDesignatedRequirement()
        let mount = FileManager.default.temporaryDirectory
            .appendingPathComponent("Barometer-update-mount-\(UUID().uuidString)", isDirectory: true)
        let process = installerProcess(
            diskImage: diskImage,
            mount: mount,
            applicationsDirectory: applicationsDirectory,
            processIdentifier: processIdentifier,
            relaunch: true,
            designatedRequirement: designatedRequirement
        )
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    static func installForTesting(
        diskImage: URL,
        mount: URL,
        applicationsDirectory: URL
    ) throws {
        let process = installerProcess(
            diskImage: diskImage,
            mount: mount,
            applicationsDirectory: applicationsDirectory,
            processIdentifier: nil,
            relaunch: false,
            designatedRequirement: #"identifier "com.barometer.app""#
        )
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateInstallationError.installFailed
        }
    }

    static var installScriptForTesting: String { installScript }

    static func runningDesignatedRequirement() throws -> String {
        var runningCode: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &runningCode) == errSecSuccess,
              let runningCode
        else {
            throw UpdateInstallationError.signingRequirementUnavailable
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(runningCode, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else {
            throw UpdateInstallationError.signingRequirementUnavailable
        }

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement
        else {
            throw UpdateInstallationError.signingRequirementUnavailable
        }

        var requirementText: CFString?
        guard SecRequirementCopyString(requirement, SecCSFlags(), &requirementText) == errSecSuccess,
              let requirementText
        else {
            throw UpdateInstallationError.signingRequirementUnavailable
        }
        return requirementText as String
    }

    private static func installerProcess(
        diskImage: URL,
        mount: URL,
        applicationsDirectory: URL,
        processIdentifier: Int32?,
        relaunch: Bool,
        designatedRequirement: String
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            installScript,
            "barometer-updater",
            diskImage.path,
            mount.path,
            applicationsDirectory.path,
            processIdentifier.map(String.init) ?? "",
            relaunch ? "yes" : "no",
            designatedRequirement,
        ]
        return process
    }
}

/// Failures specific to extracting and replacing Barometer from a DMG.
public enum UpdateInstallationError: LocalizedError {
    case unreadableDiskImage
    case signingRequirementUnavailable
    case installFailed

    public var errorDescription: String? {
        switch self {
        case .unreadableDiskImage:
            "The verified update is not a readable Barometer disk image."
        case .signingRequirementUnavailable:
            "Barometer could not verify its signing identity before installing the update."
        case .installFailed:
            "The update could not replace Barometer in Applications."
        }
    }
}
