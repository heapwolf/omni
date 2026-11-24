// src/cli/platform/windows/WindowsInstaller.swift
import Foundation

extension WindowsBuilder {
    private struct Guids {
        // Static across builds: what makes Windows Installer treat two versions as
        // upgrades of each other.
        static let upgradeCode = "{2F6B4B0E-8C2E-4A6B-9C1D-6E7F8A9B0C1D}"

        // Derived from name, version and arch, so the same inputs reproduce the same
        // GUIDs.
        static func product(_ seed: String) -> String {
            deterministicGuid(seed: "omni-msi-product-\(seed)")
        }
        static func package(_ seed: String) -> String {
            deterministicGuid(seed: "omni-msi-package-\(seed)")
        }
        static func component(_ seed: String) -> String {
            deterministicGuid(seed: "omni-msi-component-\(seed)")
        }

        private static func deterministicGuid(seed: String) -> String {
            var hash = Digest.sha256(Array(seed.utf8))
            hash[6] = (hash[6] & 0x0F) | 0x40
            hash[8] = (hash[8] & 0x3F) | 0x80
            let hex = hash.prefix(16).map { String(format: "%02X", $0) }.joined()
            let s = Array(hex)
            let g = "\(String(s[0..<8]))-\(String(s[8..<12]))-\(String(s[12..<16]))-\(String(s[16..<20]))-\(String(s[20..<32]))"
            return "{\(g)}"
        }
    }

    public func buildMsi(architecture: String = "x64", version: String = "1.0.0") throws -> String {
        let fm = FileManager.default
        let exePath = "\(path)/.omni/windows/\(target).exe"
        guard fm.fileExists(atPath: exePath) else {
            throw ShellError.failed("building .msi", "no built .exe at \(exePath) — build for Windows first")
        }

        // pkgbuild silently corrupts output written to a path containing spaces.
        let buildDir = NSTemporaryDirectory() + "omni-windows-msi-\(UUID().uuidString)"
        try? fm.removeItem(atPath: buildDir)
        let stageDir = "\(buildDir)/stage"
        let idtDir = "\(buildDir)/idt"
        let cabDir = "\(buildDir)/cab"
        for dir in [stageDir, idtDir, cabDir] {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let exeName = "\(target).exe"
        try fm.copyItem(atPath: exePath, toPath: "\(stageDir)/\(exeName)")

        let seed = "\(target)-\(version)-\(architecture)"
        let productCode = Guids.product(seed)
        let packageCode = Guids.package(seed)
        let componentId = Guids.component(seed)

        Console.info("Building .msi (architecture=\(architecture) version=\(version))")
        print("   ProductCode: \(productCode)")

        try writeIdtFiles(
            into: idtDir, exeName: exeName, architecture: architecture,
            version: version, productCode: productCode, componentId: componentId,
            exeSize: (try? fm.attributesOfItem(atPath: "\(stageDir)/\(exeName)")[.size] as? Int) ?? 0
        )

        // --- Cabinet (makecab.exe, built into every Windows install) ---
        let ddfPath = "\(buildDir)/omni.ddf"
        let ddf = """
        .OPTION EXPLICIT
        .Set CabinetNameTemplate=omni.cab
        .Set DiskDirectoryTemplate="\(cabDir)"
        .Set MaxDiskSize=0
        .Set Cabinet=ON
        .Set Compress=ON
        .Set CompressionType=MSZIP
        "\(stageDir)/\(exeName)" AppExe
        """
        try ddf.write(toFile: ddfPath, atomically: true, encoding: .utf8)

        _ = try Shell.checked("makecab.exe /F \"\(ddfPath)\"", step: "makecab.exe")
        let cabPath = "\(cabDir)/omni.cab"
        guard fm.fileExists(atPath: cabPath) else {
            throw ShellError.failed("makecab.exe", "expected cabinet not found at \(cabPath)")
        }

        // --- msidb.exe: import IDT tables, then inject the cabinet ---
        guard let msidb = findSdkTool("msidb.exe") else {
            throw ShellError.failed(
                "building .msi",
                "msidb.exe not found — install the Windows SDK (Desktop C++ Build Tools component)")
        }

        let msiPath = "\(idtDir)/omni.msi"
        try? fm.removeItem(atPath: msiPath)
        _ = try Shell.checked(
            "cd \"\(idtDir)\" && \"\(msidb)\" -d omni.msi -c -f \"\(idtDir)\" -i \"*\"",
            step: "msidb.exe import")
        guard fm.fileExists(atPath: msiPath) else {
            throw ShellError.failed("msidb.exe import", "no MSI produced — check IDT formatting")
        }

        _ = try Shell.checked(
            "cd \"\(idtDir)\" && \"\(msidb)\" -d omni.msi -a \"\(cabPath)\"",
            step: "msidb.exe cabinet injection")

        let outputDir = "\(path)/.build/installers"
        try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let output = "\(outputDir)/\(target)-\(architecture).msi"
        try? fm.removeItem(atPath: output)
        try fm.moveItem(atPath: msiPath, toPath: output)

        try stampSummaryInformation(msiPath: output, architecture: architecture,
                                     version: version, packageCode: packageCode)

        Console.success("Installer built: \(output)")
        print("   Install with: msiexec /i \"\(output)\" /qn")
        print("   Uninstall with: msiexec /x \(productCode) /qn")
        return output
    }

    private func writeIdtFiles(
        into idtDir: String, exeName: String, architecture: String, version: String,
        productCode: String, componentId: String, exeSize: Int
    ) throws {
        let programFilesFolder = architecture == "arm64" ? "ProgramFiles64Folder" : "ProgramFiles64Folder"

        let tables: [(String, String)] = [
            ("Property", """
            Property\tValue
            s72\tl0
            Property\tProperty
            UpgradeCode\t\(Guids.upgradeCode)
            Manufacturer\tomni-app
            ProductName\t\(target)
            ProductLanguage\t1033
            ProductCode\t\(productCode)
            ProductVersion\t\(version)
            ALLUSERS\t1
            """),
            ("Directory", """
            Directory\tDirectory_Parent\tDefaultDir
            s72\tS72\tl255
            Directory\tDirectory
            TARGETDIR\t\tSourceDir
            \(programFilesFolder)\tTARGETDIR\t.
            APP_ROOT\t\(programFilesFolder)\t\(sanitizedDirName)
            ProgramMenuFolder\tTARGETDIR\t.
            """),
            ("Component", """
            Component\tComponentId\tDirectory_\tAttributes\tCondition\tKeyPath
            s72\tS38\ts72\ti2\tS255\tS72
            Component\tComponent
            AppComponent\t\(componentId)\tAPP_ROOT\t0\t\tAppExe
            """),
            ("File", """
            File\tComponent_\tFileName\tFileSize\tVersion\tLanguage\tAttributes\tSequence
            s72\ts72\tl255\ti4\tS72\tS20\tI2\ti2
            File\tFile
            AppExe\tAppComponent\t\(exeName)\t\(exeSize)\t\t\t512\t1
            """),
            ("Feature", """
            Feature\tFeature_Parent\tTitle\tDescription\tDisplay\tLevel\tDirectory_\tAttributes
            s38\tS38\tL64\tL255\tI2\ti2\tS72\ti4
            Feature\tFeature
            Complete\t\t\(target)\t\(target)\t1\t1\tAPP_ROOT\t0
            """),
            ("FeatureComponents", """
            Feature_\tComponent_
            s38\ts72
            FeatureComponents\tFeature_\tComponent_
            Complete\tAppComponent
            """),
            ("Media", """
            DiskId\tLastSequence\tDiskPrompt\tCabinet\tVolumeLabel\tSource
            i2\ti2\tL64\tS255\tS32\tS72
            Media\tDiskId
            1\t1\t\t#omni.cab\t\t
            """),
            ("Shortcut", """
            Shortcut\tDirectory_\tName\tComponent_\tTarget\tArguments\tDescription\tHotkey\tIcon_\tIconIndex\tShowCmd\tWkDir
            s38\ts72\tl128\ts72\ts72\tL255\tL255\tI2\tS72\tI2\tI2\tS72
            Shortcut\tShortcut
            AppShortcut\tProgramMenuFolder\t\(target)\tAppComponent\t[#AppExe]\t\t\t\t\t\t3\tAPP_ROOT
            """),
            ("Upgrade", """
            UpgradeCode\tVersionMin\tVersionMax\tLanguage\tAttributes\tRemove\tActionProperty
            s72\tS20\tS20\tS20\ti4\tS255\ts72
            Upgrade\tUpgradeCode\tVersionMin\tVersionMax\tLanguage\tAttributes
            \(Guids.upgradeCode)\t0.0.0\t\(version)\t1033\t257\t\tOLDPRODUCTS
            """),
            ("InstallExecuteSequence", """
            Action\tCondition\tSequence
            s72\tS255\tI2
            InstallExecuteSequence\tAction
            FindRelatedProducts\t\t25
            LaunchConditions\t\t100
            CostInitialize\t\t800
            FileCost\t\t900
            CostFinalize\t\t1000
            InstallValidate\t\t1400
            RemoveExistingProducts\t\t1450
            InstallInitialize\t\t1500
            ProcessComponents\t\t1600
            RemoveShortcuts\t\t3200
            RemoveFiles\t\t3500
            InstallFiles\t\t4000
            CreateShortcuts\t\t4500
            RegisterProduct\t\t6100
            PublishFeatures\t\t6300
            PublishProduct\t\t6400
            InstallFinalize\t\t6600
            """),
            ("AdminExecuteSequence", """
            Action\tCondition\tSequence
            s72\tS255\tI2
            AdminExecuteSequence\tAction
            CostInitialize\t\t800
            FileCost\t\t900
            CostFinalize\t\t1000
            InstallValidate\t\t1400
            InstallInitialize\t\t1500
            InstallFiles\t\t4000
            InstallFinalize\t\t6600
            """)
        ]

        for (name, content) in tables {
            try content.write(toFile: "\(idtDir)/\(name).idt", atomically: true, encoding: .ascii)
        }
    }

    private var sanitizedDirName: String {
        target.replacingOccurrences(of: " ", with: "")
    }

    private func findSdkTool(_ name: String) -> String? {
        if let onPath = try? Shell.run("which \(name) 2>/dev/null"), !onPath.isEmpty {
            return onPath
        }
        let roots = [
            "C:\\Program Files (x86)\\Windows Kits\\10\\bin",
            "C:\\Program Files\\Windows Kits\\10\\bin"
        ]
        for root in roots {
            if let found = try? Shell.run(
                "find \"\(root)\" -name \"\(name)\" 2>/dev/null | sort -r | head -1"), !found.isEmpty {
                return found
            }
        }
        return nil
    }

    private func stampSummaryInformation(
        msiPath: String, architecture: String, version: String, packageCode: String
    ) throws {
        let platform = architecture == "arm64" ? "Arm64" : "x64"
        let template = "\(platform);1033"
        let minSchema = architecture == "arm64" ? 500 : 200

        let script = """
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $installer.GetType().InvokeMember('UILevel','SetProperty',$null,$installer,@(2))
        $database = $installer.GetType().InvokeMember('OpenDatabase','InvokeMethod',$null,$installer,@('\(msiPath)',1))
        $summary = $database.GetType().InvokeMember('SummaryInformation','GetProperty',$null,$database,@(20))
        $summary.GetType().InvokeMember('Property','SetProperty',$null,$summary,@(1,1252))
        $summary.GetType().InvokeMember('Property','SetProperty',$null,$summary,@(2,'Installation Database'))
        $summary.GetType().InvokeMember('Property','SetProperty',$null,$summary,@(3,'\(target) \(version)'))
        $summary.GetType().InvokeMember('Property','SetProperty',$null,$summary,@(4,'omni-app'))
        $summary.GetType().InvokeMember('Property','SetProperty',$null,$summary,@(7,'\(template)'))
        $summary.GetType().InvokeMember('Property','SetProperty',$null,$summary,@(9,'\(packageCode)'))
        $summary.GetType().InvokeMember('Property','SetProperty',$null,$summary,@(14,\(minSchema)))
        $summary.GetType().InvokeMember('Property','SetProperty',$null,$summary,@(15,2))
        $summary.GetType().InvokeMember('Persist','InvokeMethod',$null,$summary,$null)
        $database.GetType().InvokeMember('Commit','InvokeMethod',$null,$database,$null)
        """

        let scriptPath = NSTemporaryDirectory() + "omni-msi-summary-\(UUID().uuidString).ps1"
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        _ = try Shell.checked(
            "powershell.exe -NoProfile -NonInteractive -File \"\(scriptPath)\"",
            step: "stamping Summary Information Stream")
    }
}
