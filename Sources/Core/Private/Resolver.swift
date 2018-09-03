//
//  DIResolver.swift
//  DITranquillity
//
//  Created by Alexander Ivlev on 21/06/16.
//  Copyright © 2016 Alexander Ivlev. All rights reserved.
//

class Resolver {

  init(container: DIContainer) {
    self.container = container // unowned
  }
  
  func resolve<T>(type: T.Type = T.self, name: String? = nil, from bundle: Bundle? = nil) -> T {
    log(.verbose, msg: "Begin resolve \(description(type: type))", brace: .begin)
    defer { log(.verbose, msg: "End resolve \(description(type: type))", brace: .end) }
    
    return gmake(by: make(by: type, with: name, from: bundle, use: nil))
  }
  
  func injection<T>(obj: T, from bundle: Bundle? = nil) {
    log(.verbose, msg: "Begin injection in obj: \(obj)", brace: .begin)
    defer { log(.verbose, msg: "End injection in obj: \(obj)", brace: .end) }
    
    // swift bug - if T is Any then type(of: obj) return always any. - compile optimization?
    _ = make(by: type(of: (obj as Any)), with: nil, from: bundle, use: obj)
  }

  
  func resolveSingleton(component: Component) {
    log(.verbose, msg: "Begin resolve singleton by component: \(component.info)", brace: .begin)
    defer { log(.verbose, msg: "End resolve singleton by component: \(component.info)", brace: .end) }
    
    _ = makeObject(by: component, use: nil)
  }
  
  func resolve<T>(type: T.Type = T.self, component: Component) -> T {
    log(.verbose, msg: "Begin resolve \(description(type: type)) by component: \(component.info)", brace: .begin)
    defer { log(.verbose, msg: "End resolve \(description(type: type)) by component: \(component.info)", brace: .end) }
    
    return gmake(by: makeObject(by: component, use: nil))
  }
  
  /// Finds the most suitable components that satisfy the types.
  ///
  /// - Parameters:
  ///   - type: a type
  ///   - name: a name
  ///   - bundle: bundle from whic the call is made
  /// - Returns: components
  func findComponents(by type: DIAType, with name: String?, from bundle: Bundle?) -> Components {
    func defaults(_ components: Components) -> Components {
      let filtering = ContiguousArray(components.filter{ $0.isDefault })
      return filtering.isEmpty ? components : filtering
    }
    
    func filter(by bundle: Bundle?, _ components: Components) -> Components {
      if components.count <= 1 {
        return components
      }
      
      /// check into self bundle
      if let bundle = bundle {
        /// get all components in bundle
        let filteredByBundle = ContiguousArray(components.filter{ $0.bundle.map{ bundle == $0 } ?? false })
        
        func componentsIsNeedReturn(_ components: Components) -> Components? {
          let filtered = defaults(components)
          return 1 == filtered.count ? filtered : nil
        }
        
        if let components = componentsIsNeedReturn(filteredByBundle) {
          return components
        }
        
        /// get direct dependencies
        let childs = container.bundleContainer.childs(for: bundle)
        let filteredByChilds = ContiguousArray(components.filter{ $0.bundle.map{ childs.contains($0) } ?? false })
        
        if let components = componentsIsNeedReturn(filteredByChilds) {
          return components
        }
      }
      
      return defaults(components)
    }
    
    /// real type without many, tags, optional
    var type: DIAType = removeTypeWrappers(type)
    let simpleType: DIAType = removeTypeWrappersFully(type)
    var components: Set<Component> = []
    var filterByBundle: Bool = true
    
    var first: Bool = true
    repeat {
      let currentComponents: Set<Component>
      if let manyType = type as? IsMany.Type {
        currentComponents = container.componentContainer[ShortTypeKey(by: simpleType)]
        filterByBundle = filterByBundle && manyType.inBundle /// filter
      } else if let taggedType = type as? IsTag.Type {
        currentComponents = container.componentContainer[TypeKey(by: simpleType, tag: taggedType.tag)]
      } else if let name = name {
        currentComponents = container.componentContainer[TypeKey(by: simpleType, name: name)]
      } else {
        currentComponents = container.componentContainer[TypeKey(by: simpleType)]
      }

      if let subtype = (type as? WrappedType.Type)?.type {
        type = removeTypeWrappers(subtype) /// iteration
      }
      
      /// it's not equals components.isEmpty !!!
      components = first ? currentComponents : components.intersection(currentComponents)
      first = false
      
    } while ObjectIdentifier(type) != ObjectIdentifier(simpleType)
    
    if filterByBundle {
      return filter(by: bundle, Components(components))
    }
    
    return Components(components)
  }
  
  /// Remove components who doesn't have initialization method
  ///
  /// - Parameter components: Components from which will be removed
  /// - Returns: components Having a initialization method
  func removeWhoDoesNotHaveInitialMethod(components: Components) -> Components {
    return Components(components.filter { nil != $0.initial })
  }
  
  /// Remove all cache objects in container
  func clean() {
    mutex.sync { cache.perContainer.data.removeAll() }
  }
  
  private func make(by type: DIAType, with name: String?, from bundle: Bundle?, use object: Any?) -> Any? {
    let isMany: Bool = hasMany(in: type)
    var components: Components = findComponents(by: type, with: name, from: bundle)

    return mutex.sync {
      if isMany {
          //isManyRemove objects contains in stack for exclude cycle initialization
          components = components.filter{ !stack.contains($0.info) }
      }

      if let delayMaker = asDelayMaker(type) {
        let saveGraph = cache.graph

        return delayMaker.init({ () -> Any? in
          return self.mutex.sync {
            self.cache.graph = saveGraph
            return self.make(by: type, isMany: isMany, components: components, use: object)
          }
        })
      }

      return make(by: type, isMany: isMany, components: components, use: object)
    }
  }

  /// isMany for optimization
  private func make(by type: DIAType, isMany: Bool, components: Components, use object: Any?) -> Any? {
    if isMany {
      assert(nil == object, "Many injection not supported")
      return components.compactMap{ makeObject(by: $0, use: nil) }
    }

    if let component = components.first, 1 == components.count {
      return makeObject(by: component, use: object)
    }

    if components.isEmpty {
      log(.info, msg: "Not found \(description(type: type))")
    } else {
      let infos = components.map{ $0.info }
      log(.warning, msg: "Ambiguous \(description(type: type)) contains in: \(infos)")
    }

    return nil
  }
  
  /// Super function
  private func makeObject(by component: Component, use usingObject: Any?) -> Any? {
    log(.verbose, msg: "Found component: \(component.info)")

    let uniqueKey = component.info
    
    func makeObject(from cacheName: StaticString, use referenceCounting: DILifeTime.ReferenceCounting, scope: Cache.Scope) -> Any? {
      var optCacheObject: Any? = scope.data[uniqueKey]
      if let weakRef = optCacheObject as? Weak<Any> {
        optCacheObject = weakRef.value
      }
      
      if let cacheObject = optCacheObject, isObjectReallyExisted(optCacheObject) {
        /// suspending ignore injection for new object
        guard let usingObject = usingObject else {
          log(.verbose, msg: "Resolve object: \(cacheObject) from cache \(cacheName)")
          return cacheObject
        }
        
        /// suspending double injection
        if cacheObject as AnyObject === usingObject as AnyObject {
          log(.verbose, msg: "Resolve object: \(cacheObject) from cache \(cacheName)")
          return cacheObject
        }
      }
      
      if let makedObject = makeObject() {
        scope.data[uniqueKey] = (.weak == referenceCounting) ? Weak(value: makedObject) : makedObject
        log(.verbose, msg: "Add object: \(makedObject) in cache \(cacheName)")
        return makedObject
      }
      
      return nil
    }

    func getArgumentObject(by type: DIAType) -> Any? {
      guard let extensions = container.extensionsContainer.optionalGet(by: component.info) else {
        log(.error, msg: "Until get argument. Not found extensions for \(component.info)")
        return nil
      }
      return extensions.getNextArg()
    }
    
    func makeObject() -> Any? {
      guard let initializedObject = initialObject() else {
        return nil
      }

      for injection in component.injections {
        if injection.cycle {
          cache.cycleInjectionQueue.append((initializedObject, injection.signature))
        } else {
          _ = use(signature: injection.signature, usingObject: initializedObject)
        }
      }
      
      if let signature = component.postInit {
        if component.injections.contains(where: { $0.cycle }) {
          cache.cycleInjectionQueue.append((initializedObject, signature))
        } else {
          _ = use(signature: signature, usingObject: initializedObject)
        }
      }
      
      return initializedObject
    }
    
    func initialObject() -> Any? {
      if let obj = usingObject {
        log(.verbose, msg: "Use object: \(obj)")
        return obj
      }
      
      if let signature = component.initial {
        let obj = use(signature: signature, usingObject: nil)
        log(.verbose, msg: "Create object: \(String(describing: obj))")
        return obj
      }
      
      log(.warning, msg: "Can't found initial method in \(component.info)")
      return nil
    }
    
    func endResolving() {
      while !cache.cycleInjectionQueue.isEmpty {
        let data = cache.cycleInjectionQueue.removeFirst()
        _ = use(signature: data.signature, usingObject: data.obj)
      }
      
      cache.graph = Cache.Scope()
    }
    
    func use(signature: MethodSignature, usingObject: Any?) -> Any? {
      var objParameters: [Any?] = []
      for parameter in signature.parameters {
        let makedObject: Any?
        if parameter.type is UseObject.Type {
          makedObject = usingObject
        } else if let argParameter = parameter.type as? IsArg.Type {
          makedObject = getArgumentObject(by: argParameter.type)
        } else {
          makedObject = make(by: parameter.type, with: parameter.name, from: component.bundle, use: nil)
        }
        
        if nil != makedObject || parameter.optional {
          objParameters.append(makedObject)
          continue
        }
        
        return nil
      }
      
      return signature.call(objParameters)
    }


    stack.append(component.info)
    defer {
      if 1 == stack.count {
        endResolving()
      }
      stack.removeLast()
    }

    switch component.lifeTime {
    case .single:
      return makeObject(from: "single", use: .strong, scope: Cache.perRun)

    case .perRun(let referenceCounting):
      return makeObject(from: "per run", use: referenceCounting, scope: Cache.perRun)

    case .perContainer(let referenceCounting):
      return makeObject(from: "per container", use: referenceCounting, scope: cache.perContainer)

    case .objectGraph:
      return makeObject(from: "object graph", use: .strong, scope: cache.graph)

    case .prototype:
      return makeObject()
    }
  }
 
  private unowned let container: DIContainer
  
  private let mutex = PThreadMutex(recursive: ())
  
  private let cache = Cache()
  private var stack: ContiguousArray<Component.UniqueKey> = []
  
  private class Cache {
    // need class for reference type
    fileprivate class Scope {
      var data: [Component.UniqueKey: Any] = [:]
    }
    
    // any can by weak, and object
    fileprivate static var perRun = Scope()
    fileprivate var perContainer = Scope()

    fileprivate var graph = Scope()
    fileprivate var cycleInjectionQueue: ContiguousArray<(obj: Any?, signature: MethodSignature)> = []
  }
}

