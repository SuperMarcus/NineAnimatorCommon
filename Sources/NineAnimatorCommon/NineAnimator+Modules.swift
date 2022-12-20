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

import Foundation

// MARK: - NineAnimator framework modules management
public extension NineAnimator {
    /// Initialize all native NineAnimator sub-modules
    func loadModules() {
        if !_areModulesLoaded {
            Log.info("[NineAnimator] Discovering native modules...")
            _areModulesLoaded = true
            modules = _discoverModules()
            
            Log.info("[NineAnimator] Found %@ modules, loading...", modules.count)
            modules.forEach {
                module in module.initFunc(self)
            }
        }
    }
    
    func registerModule<Module: NineAnimatorModule>(type: Module.Type) {
        let moduleBundle = Bundle(for: type)
        if !self.modules.contains(where: { existing in existing.bundle.bundleURL == moduleBundle.bundleURL }) {
            let moduleClassFullName = String(reflecting: type)
            let moduleClassSplit = moduleClassFullName.split(separator: ".")
            
            if moduleClassSplit.count == 2 {
                let moduleNamespace = String(moduleClassSplit[0])
                let moduleName = String(moduleClassSplit[1])
                let module = NativeModule(
                    name: moduleName,
                    namespace: moduleNamespace,
                    bundle: moduleBundle,
                    initClass: type,
                    initFunc: type.initModule(with:)
                )
                self.modules.append(module)
                Log.info("[NineAnimator] Registered custom module %@ (%@, %@)", moduleName, moduleBundle.bundleIdentifier ?? "Unknown ID", moduleBundle.bundlePath)
            }
        }
    }
}

public extension NineAnimator {
    struct NativeModule: Hashable {
        public internal(set) var name: String
        public internal(set) var namespace: String
        public internal(set) var bundle: Bundle
        public internal(set) var initClass: AnyClass
        
        // Private values
        fileprivate var initFunc: (NineAnimator) -> Void
    }
}

public extension NineAnimator.NativeModule {
    func hash(into hasher: inout Hasher) {
        hasher.combine(bundle.bundleURL)
    }
    
    static func == (lhs: NineAnimator.NativeModule, rhs: NineAnimator.NativeModule) -> Bool {
        lhs.bundle.bundleURL == rhs.bundle.bundleURL
    }
}

internal extension NineAnimator {
    func _discoverModules() -> [NativeModule] {
        let modulesExecutablePrefix = "NineAnimator"
        
        return Bundle.allFrameworks.reduce(into: self.modules) {
            // Find all code bundles with the NineAnimator prefix
            discoveredModules, fw in
            // Do no re-add module
            if discoveredModules.contains(where: { existing in existing.bundle.bundleURL == fw.bundleURL }) {
                return
            }
            
            let fwNamespace = fw.bundleURL.deletingPathExtension().lastPathComponent
            guard fwNamespace.hasPrefix(modulesExecutablePrefix) else {
                return
            }
            
            let moduleName = fwNamespace[modulesExecutablePrefix.count...]
            guard let moduleInitializationClass = fw.classNamed("\(fwNamespace).\(moduleName)"),
                let moduleInitFunc = moduleInitializationClass.initModule(with:) else {
                return
            }
            
            Log.info("[NineAnimator] Found module %@ (%@, %@)", moduleName, fw.bundleIdentifier ?? "Unknown ID", fw.bundlePath)
            
            let newModule = NativeModule(
                name: moduleName,
                namespace: fwNamespace,
                bundle: fw,
                initClass: moduleInitializationClass,
                initFunc: moduleInitFunc
            )
            discoveredModules.append(newModule)
        }
    }
}

@objc public protocol NineAnimatorModule: NSObjectProtocol {
    @objc static func initModule(with parent: NineAnimator)
}
