//
//  DIScanModule.swift
//  DITranquillity
//
//  Created by Alexander Ivlev on 13/10/16.
//  Copyright © 2016 Alexander Ivlev. All rights reserved.
//

open class DIScannedModule: DIScanned, DIModule {
  open func load(builder: DIContainerBuilder) {
    preconditionFailure("Please override me: \(#function)")
  }
}

public class DIScanModule: DIScanWithInitializer<DIScannedModule>, DIModule {
  public func load(builder: DIContainerBuilder) {
    for module in getObjects() {
      builder.register(module: module)
    }
  }
}