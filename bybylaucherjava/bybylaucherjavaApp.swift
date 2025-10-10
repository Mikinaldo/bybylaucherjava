import SwiftUI
import Foundation
import ZIPFoundation
import AuthenticationServices
import UniformTypeIdentifiers
import Darwin

// MARK: - Java Dynamic Invocation for iOS
final class JavaDynamicInvoker {
    private static var jvmHandle: UnsafeMutableRawPointer?
    private static var jniEnv: UnsafeMutableRawPointer?
    
    // Java Native Interface functions
    typealias JNI_CreateJavaVM_func = @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?, UnsafeMutableRawPointer?) -> Int32
    typealias JNI_GetDefaultJavaVMInitArgs_func = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias JNI_GetCreatedJavaVMs_func = @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>?, Int32, UnsafeMutablePointer<Int32>?) -> Int32
    
    // ==========================
    // Load Java Virtual Machine dynamically from embedded .dylib
    // ==========================
    static func loadJavaVM() throws {
        // Các path có thể cho Java .dylib trên iOS
        let javaLibPaths = [
            "@executable_path/Frameworks/libjvm.dylib",
            "libjvm.dylib"
        ]
        
        var javaLibHandle: UnsafeMutableRawPointer?
        
        for libName in javaLibPaths {
            if let bundlePath = Bundle.main.path(forResource: libName, ofType: nil) ??
                Bundle.main.path(forResource: (libName as NSString).deletingPathExtension,
                               ofType: (libName as NSString).pathExtension) {
                
                javaLibHandle = dlopen(bundlePath, RTLD_LAZY | RTLD_GLOBAL)
                if javaLibHandle != nil {
                    print("Loaded Java library from: \(bundlePath)")
                    break
                }
            }
        }
        
        // Thử load từ system paths nếu không tìm thấy trong bundle
        if javaLibHandle == nil {
            let systemPaths = [
                "/usr/lib/libjvm.dylib",
                "/usr/local/lib/libjvm.dylib"
            ]
            
            for path in systemPaths {
                javaLibHandle = dlopen(path, RTLD_LAZY | RTLD_GLOBAL)
                if javaLibHandle != nil {
                    print("Loaded Java library from system: \(path)")
                    break
                }
            }
        }
        
        guard let handle = javaLibHandle else {
            throw NSError(domain: "JavaDynamicInvoker", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load Java VM library. Make sure Java .dylib is embedded in the app."])
        }
        
        jvmHandle = handle
        try initializeJNI()
    }
    
    // ==========================
    // Initialize JNI environment
    // ==========================
    private static func initializeJNI() throws {
        guard let handle = jvmHandle else {
            throw NSError(domain: "JavaDynamicInvoker", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Java VM not loaded"])
        }
        
        // Get JNI function pointers
        guard let JNI_CreateJavaVM = dlsym(handle, "JNI_CreateJavaVM") else {
            throw NSError(domain: "JavaDynamicInvoker", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "JNI_CreateJavaVM not found"])
        }
        
        let createJavaVM = unsafeBitCast(JNI_CreateJavaVM, to: JNI_CreateJavaVM_func.self)
        
        // Create Java VM
        var jvm: UnsafeMutableRawPointer?
        var env: UnsafeMutableRawPointer?
        
        let result = createJavaVM(&jvm, &env, nil)
        guard result == 0 else {
            throw NSError(domain: "JavaDynamicInvoker", code: Int(result),
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create Java VM: error code \(result)"])
        }
        
        jniEnv = env
        print("Java VM initialized successfully")
    }
    
    // ==========================
    // Dynamic Java class loading and method invocation
    // ==========================
    static func loadJavaClass(_ className: String) throws -> UnsafeMutableRawPointer? {
        guard let env = jniEnv else {
            throw NSError(domain: "JavaDynamicInvoker", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "JNI environment not initialized"])
        }
        
        // Get FindClass function
        typealias FindClass_func = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
        guard let FindClass = dlsym(jvmHandle, "FindClass") else {
            throw NSError(domain: "JavaDynamicInvoker", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "FindClass not found"])
        }
        
        let findClass = unsafeBitCast(FindClass, to: FindClass_func.self)
        
        return className.withCString { cClassName in
            findClass(env, cClassName)
        }
    }
    
    static func callStaticVoidMethod(_ className: String, methodName: String, methodSignature: String) throws {
        guard let javaClass = try loadJavaClass(className) else {
            throw NSError(domain: "JavaDynamicInvoker", code: -6,
                          userInfo: [NSLocalizedDescriptionKey: "Class \(className) not found"])
        }
        
        guard let env = jniEnv else {
            throw NSError(domain: "JavaDynamicInvoker", code: -7,
                          userInfo: [NSLocalizedDescriptionKey: "JNI environment not initialized"])
        }
        
        // Get method ID
        typealias GetStaticMethodID_func = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
        guard let GetStaticMethodID = dlsym(jvmHandle, "GetStaticMethodID") else {
            throw NSError(domain: "JavaDynamicInvoker", code: -8,
                          userInfo: [NSLocalizedDescriptionKey: "GetStaticMethodID not found"])
        }
        
        let getStaticMethodID = unsafeBitCast(GetStaticMethodID, to: GetStaticMethodID_func.self)
        
        let methodID = methodName.withCString { cMethodName in
            methodSignature.withCString { cSignature in
                getStaticMethodID(env, javaClass, cMethodName, cSignature)
            }
        }
        
        guard methodID != nil else {
            throw NSError(domain: "JavaDynamicInvoker", code: -9,
                          userInfo: [NSLocalizedDescriptionKey: "Method \(methodName) not found in class \(className)"])
        }
        
        // Call static void method
        typealias CallStaticVoidMethod_func = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        guard let CallStaticVoidMethod = dlsym(jvmHandle, "CallStaticVoidMethod") else {
            throw NSError(domain: "JavaDynamicInvoker", code: -10,
                          userInfo: [NSLocalizedDescriptionKey: "CallStaticVoidMethod not found"])
        }
        
        let callStaticVoidMethod = unsafeBitCast(CallStaticVoidMethod, to: CallStaticVoidMethod_func.self)
        callStaticVoidMethod(env, javaClass, methodID)
    }
    
    // ==========================
    // Launch Minecraft using dynamic Java invocation
    // ==========================
    static func launchMinecraft(version: MinecraftVersion, account: MinecraftAccount) throws {
        // Đảm bảo Java VM được load
        if jvmHandle == nil {
            try loadJavaVM()
        }
        
        let gameDir = version.path.path
        let jarPath = "\(gameDir)/client.jar"
        
        // Kiểm tra file client.jar
        guard FileManager.default.fileExists(atPath: jarPath) else {
            throw NSError(domain: "JavaDynamicInvoker", code: -11,
                          userInfo: [NSLocalizedDescriptionKey: "Minecraft client.jar not found at: \(jarPath)"])
        }
        
        // Dynamic invocation of Minecraft main class
        try callStaticVoidMethod("net.minecraft.client.main.Main",
                               methodName: "main",
                               methodSignature: "([Ljava/lang/String;)V")
        
        print("Minecraft launched successfully through Java VM")
    }
    
    // ==========================
    // Cleanup
    // ==========================
    static func cleanup() {
        if let handle = jvmHandle {
            dlclose(handle)
            jvmHandle = nil
            jniEnv = nil
        }
    }
}

// MARK: - Minecraft Data Models
struct MinecraftVersion: Identifiable {
    let id: String
    let type: String
    var path: URL
    var mods: [Mod]
    var isInstalled: Bool
    var modLoader: ModLoaderType?
}

struct Mod: Identifiable {
    let id = UUID()
    let name: String
    let version: String
    let filePath: URL
}

struct ModLoaderVersion: Identifiable {
    let id: String
    let name: String
    let compatible: [String]
}

enum ModLoaderType: String, CaseIterable {
    case forge = "Forge"
    case fabric = "Fabric"
    case quilt = "Quilt"
}

struct MinecraftAccount {
    let username: String
    let uuid: String
    let accessToken: String
}

// MARK: - Complete MinecraftManager Implementation
final class MinecraftManager: ObservableObject {
    @Published var installedVersions = [MinecraftVersion]()
    @Published var availableVersions = [String]()
    @Published var modLoaderVersions = [ModLoaderVersion]()
    @Published var account: MinecraftAccount?
    @Published var isWorking = false
    @Published var showFileBrowser = false
    @Published var selectedVersionForInstall = ""
    @Published var selectedModLoader: ModLoaderType?
    @Published var selectedVersionForLaunch: MinecraftVersion?
    
    private let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Minecraft")
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    
    init() {
        setupDirectories()
        loadInstalledVersions()
        fetchAvailableVersions()
    }
    
    private func setupDirectories() {
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
    }
    
    func loadInstalledVersions() {
        installedVersions = []
        let versionDirs = (try? FileManager.default.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)) ?? []
        
        for dir in versionDirs {
            let modsDir = dir.appendingPathComponent("mods")
            let modFiles = (try? FileManager.default.contentsOfDirectory(at: modsDir, includingPropertiesForKeys: nil)) ?? []
            
            var mods = [Mod]()
            for modFile in modFiles {
                let name = modFile.deletingPathExtension().lastPathComponent
                mods.append(Mod(name: name, version: "1.0", filePath: modFile))
            }
            
            let versionName = dir.lastPathComponent
            let components = versionName.components(separatedBy: "_")
            let mcVersion = components.first ?? versionName
            let loaderType = components.count > 1 ? ModLoaderType(rawValue: components[1]) : nil
            
            installedVersions.append(MinecraftVersion(
                id: versionName,
                type: "release",
                path: dir,
                mods: mods,
                isInstalled: true,
                modLoader: loaderType
            ))
        }
    }
    
    func fetchAvailableVersions() {
        guard let url = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest.json") else { return }
        
        isWorking = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { DispatchQueue.main.async { self.isWorking = false } }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let versions = json["versions"] as? [[String: Any]] else { return }
            
            DispatchQueue.main.async {
                self.availableVersions = versions.compactMap { $0["id"] as? String }
            }
        }.resume()
    }
    
    func fetchModLoaderVersions(for mcVersion: String) {
        isWorking = true
        
        DispatchQueue.global().async {
            let group = DispatchGroup()
            var loaders = [ModLoaderVersion]()
            
            group.enter()
            if let url = URL(string: "https://meta.fabricmc.net/v2/versions/loader/\(mcVersion)") {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data = data,
                       let versions = try? JSONDecoder().decode([FabricVersion].self, from: data) {
                        versions.forEach {
                            loaders.append(ModLoaderVersion(
                                id: "fabric_\($0.loader.version)",
                                name: "Fabric \($0.loader.version)",
                                compatible: [$0.loader.version]
                            ))
                        }
                    }
                    group.leave()
                }.resume()
            } else {
                group.leave()
            }
            
            group.enter()
            if let url = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/maven-metadata.json") {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data = data,
                       let metadata = try? JSONDecoder().decode(ForgeMetadata.self, from: data) {
                        metadata.versions
                            .filter { $0.contains(mcVersion) }
                            .forEach {
                                loaders.append(ModLoaderVersion(
                                    id: "forge_\($0)",
                                    name: "Forge \($0)",
                                    compatible: [$0]
                                ))
                            }
                    }
                    group.leave()
                }.resume()
            } else {
                group.leave()
            }
            
            group.notify(queue: .main) {
                self.modLoaderVersions = loaders
                self.isWorking = false
            }
        }
    }
    
    func installVersion(version: String, loader: ModLoaderType?) {
        isWorking = true
        
        DispatchQueue.global().async {
            let versionName = loader == nil ? version : "\(version)_\(loader!.rawValue.lowercased())"
            let versionURL = self.baseURL.appendingPathComponent(versionName)
            
            do {
                try FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true, attributes: nil)
                try FileManager.default.createDirectory(at: versionURL.appendingPathComponent("mods"), withIntermediateDirectories: true, attributes: nil)
                
                if let loader = loader {
                    switch loader {
                    case .fabric:
                        self.installFabricLoader(version: version, directory: versionURL)
                    case .forge:
                        self.installForgeLoader(version: version, directory: versionURL)
                    case .quilt:
                        break
                    }
                } else {
                    self.downloadMinecraftClient(version: version, directory: versionURL)
                }
                
                DispatchQueue.main.async {
                    self.loadInstalledVersions()
                    self.isWorking = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                }
            }
        }
    }
    
    private func installFabricLoader(version: String, directory: URL) {
        guard let url = URL(string: "https://meta.fabricmc.net/v2/versions/loader/\(version)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let versions = try? JSONDecoder().decode([FabricVersion].self, from: data),
                  let latest = versions.first,
                  let installerURL = URL(string: "https://maven.fabricmc.net/net/fabricmc/fabric-installer/\(latest.loader.version)/fabric-installer-\(latest.loader.version).jar") else { return }
            
            self.downloadAndSaveInstaller(url: installerURL, directory: directory)
        }.resume()
    }
    
    private func installForgeLoader(version: String, directory: URL) {
        guard let url = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/maven-metadata.json") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let metadata = try? JSONDecoder().decode(ForgeMetadata.self, from: data),
                  let forgeVersion = metadata.versions.first(where: { $0.contains(version) }),
                  let installerURL = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/\(forgeVersion)/forge-\(forgeVersion)-installer.jar") else { return }
            
            self.downloadAndSaveInstaller(url: installerURL, directory: directory)
        }.resume()
    }
    
    private func downloadAndSaveInstaller(url: URL, directory: URL) {
        URLSession.shared.downloadTask(with: url) { tempURL, _, _ in
            guard let tempURL = tempURL else { return }
            
            do {
                let installerURL = directory.appendingPathComponent("installer.jar")
                try FileManager.default.moveItem(at: tempURL, to: installerURL)
            } catch {
                print(error)
            }
        }.resume()
    }
    
    private func downloadMinecraftClient(version: String, directory: URL) {
        guard let url = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest.json") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let versions = json["versions"] as? [[String: Any]],
                  let versionInfo = versions.first(where: { ($0["id"] as? String) == version }),
                  let versionURLString = versionInfo["url"] as? String,
                  let versionURL = URL(string: versionURLString) else { return }
            
            URLSession.shared.dataTask(with: versionURL) { data, _, _ in
                guard let data = data,
                      let versionJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let downloads = versionJson["downloads"] as? [String: Any],
                      let client = downloads["client"] as? [String: Any],
                      let clientURLString = client["url"] as? String,
                      let clientURL = URL(string: clientURLString) else { return }
                
                URLSession.shared.downloadTask(with: clientURL) { tempURL, _, _ in
                    guard let tempURL = tempURL else { return }
                    
                    do {
                        let clientJar = directory.appendingPathComponent("client.jar")
                        try FileManager.default.moveItem(at: tempURL, to: clientJar)
                    } catch {
                        print(error)
                    }
                }.resume()
            }.resume()
        }.resume()
    }
    
    func importModpack(_ fileURL: URL) {
        isWorking = true
        
        DispatchQueue.global().async {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            
            do {
                try FileManager.default.unzipItem(at: fileURL, to: tempDir)
                
                guard let manifestFile = FileManager.default.contents(atPath: tempDir.appendingPathComponent("manifest.json").path),
                      let manifest = try? JSONSerialization.jsonObject(with: manifestFile) as? [String: Any],
                      let minecraftInfo = manifest["minecraft"] as? [String: Any],
                      let version = minecraftInfo["version"] as? String else {
                    DispatchQueue.main.async {
                        self.isWorking = false
                    }
                    return
                }
                
                let versionName = "\(version)_modpack"
                let versionURL = self.baseURL.appendingPathComponent(versionName)
                try? FileManager.default.removeItem(at: versionURL)
                try? FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true, attributes: nil)
                
                let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
                for item in contents {
                    let source = tempDir.appendingPathComponent(item)
                    let destination = versionURL.appendingPathComponent(item)
                    try FileManager.default.copyItem(at: source, to: destination)
                }
                
                DispatchQueue.main.async {
                    self.loadInstalledVersions()
                    self.isWorking = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                }
            }
        }
    }
    
    func launchVersion(_ version: MinecraftVersion) {
        guard let account = account else {
            showAlert(title: "Error", message: "Please login first")
            return
        }
        
        do {
            // Launch Minecraft through dynamic Java invocation
            try JavaDynamicInvoker.launchMinecraft(version: version, account: account)
            
        } catch {
            showAlert(title: "Launch Error", message: error.localizedDescription)
        }
    }
    
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(alert, animated: true)
            }
        }
    }
    
    func openAppDirectory() {
        showFileBrowser = true
    }
}

// MARK: - Supporting Types
struct FabricVersion: Decodable {
    struct Loader: Decodable {
        let version: String
    }
    let loader: Loader
}

struct ForgeMetadata: Decodable {
    let versions: [String]
}

// MARK: - Auth Handler
class AuthHandler: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - Content View
struct ContentView: View {
    @StateObject private var manager = MinecraftManager()
    @State private var showingImporter = false
    @State private var showingInstaller = false
    @State private var isAuthenticating = false
    @State private var authError: String?
    private let authHandler = AuthHandler()
    
    var body: some View {
        NavigationView {
            List {
                Section("Installed Versions") {
                    ForEach(manager.installedVersions) { version in
                        VersionRow(version: version) {
                            manager.launchVersion(version)
                        }
                    }
                }
                
                Section("Actions") {
                    Button("Install New Version") {
                        showingInstaller = true
                    }
                    
                    Button("Import Modpack") {
                        showingImporter = true
                    }
                    
                    Button("Open App Directory") {
                        manager.openAppDirectory()
                    }
                    
                    if manager.account == nil {
                        Button {
                            login()
                        } label: {
                            HStack {
                                Image(systemName: "xbox.logo")
                                Text("Login with Microsoft")
                            }
                        }
                        .disabled(isAuthenticating)
                    } else {
                        Button("Logout") {
                            manager.account = nil
                        }
                    }
                }
            }
            .navigationTitle("Minecraft Manager")
            .sheet(isPresented: $showingInstaller) {
                VersionInstallerView(manager: manager)
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.zip]) { result in
                if case .success(let url) = result {
                    manager.importModpack(url)
                }
            }
            .sheet(isPresented: $manager.showFileBrowser) {
                DocumentBrowserView(directoryURL: manager.documentsURL)
            }
            .overlay {
                if manager.isWorking || isAuthenticating {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.5))
                }
            }
            .alert("Authentication Error", isPresented: .constant(authError != nil)) {
                Button("OK") { authError = nil }
            } message: {
                Text(authError ?? "")
            }
        }
    }
    
    private func login() {
        isAuthenticating = true
        
        let authURL = URL(string: "https://login.live.com/oauth20_authorize.srf?client_id=00000000402b5328&response_type=code&scope=service%3A%3Auser.auth.xboxlive.com%3A%3AMBI_SSL&redirect_uri=https%3A%2F%2Flogin.live.com%2Foauth20_desktop.srf")!
        
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "https") { callbackURL, error in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                
                if let error = error {
                    self.authError = error.localizedDescription
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
                      let code = queryItems.first(where: { $0.name == "code" })?.value else {
                    self.authError = "Failed to get authentication code"
                    return
                }
                
                self.exchangeCodeForToken(code: code)
            }
        }
        
        session.presentationContextProvider = authHandler
        session.start()
    }
    
    private func exchangeCodeForToken(code: String) {
        // Implement token exchange logic here
        // This is a simplified version - you'll need to implement the actual Microsoft OAuth flow
        
        let account = MinecraftAccount(
            username: "Player",
            uuid: UUID().uuidString,
            accessToken: "dummy_token_\(code.prefix(10))"
        )
        
        manager.account = account
    }
}

// MARK: - Version Installer View
struct VersionInstallerView: View {
    @ObservedObject var manager: MinecraftManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section("Minecraft Version") {
                    Picker("Select Version", selection: $manager.selectedVersionForInstall) {
                        ForEach(manager.availableVersions, id: \.self) { version in
                            Text(version).tag(version)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: manager.selectedVersionForInstall) { _ in
                        if !manager.selectedVersionForInstall.isEmpty {
                            manager.fetchModLoaderVersions(for: manager.selectedVersionForInstall)
                        }
                    }
                }
                
                Section("Mod Loader (Optional)") {
                    Picker("Select Loader Type", selection: $manager.selectedModLoader) {
                        Text("None").tag(nil as ModLoaderType?)
                        ForEach(ModLoaderType.allCases, id: \.self) { loader in
                            Text(loader.rawValue).tag(loader as ModLoaderType?)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if !manager.modLoaderVersions.isEmpty && manager.selectedModLoader != nil {
                        Picker("Loader Version", selection: .constant(0)) {
                            ForEach(manager.modLoaderVersions) { version in
                                Text(version.name).tag(version.id)
                            }
                        }
                    }
                }
                
                Section {
                    Button("Install") {
                        manager.installVersion(
                            version: manager.selectedVersionForInstall,
                            loader: manager.selectedModLoader
                        )
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(manager.selectedVersionForInstall.isEmpty)
                }
            }
            .navigationTitle("Install Version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Version Row
struct VersionRow: View {
    let version: MinecraftVersion
    let action: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(version.id)
                    .font(.headline)
                
                if let loader = version.modLoader {
                    Text(loader.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text("\(version.mods.count) mods")
                    .font(.caption)
            }
            
            Spacer()
            
            Button("Launch", action: action)
                .buttonStyle(.bordered)
        }
    }
}

// MARK: - Document Browser
struct DocumentBrowserView: UIViewControllerRepresentable {
    let directoryURL: URL
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        controller.directoryURL = directoryURL
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

// MARK: - App Entry
@main
struct MinecraftManagerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
