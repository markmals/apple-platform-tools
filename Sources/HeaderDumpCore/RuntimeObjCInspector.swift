#if canImport(ObjectiveC)
  import Foundation
  import ObjectiveC

  // SPEC: story.headerdump.dump-framework
  // Runtime fallback: introspect a loaded ObjC class straight from the runtime when
  // static Mach-O parsing can't. Ported from the former ObjC RuntimeFallbackClassInfo
  // — the runtime functions (class_copy*, protocol_copy*, object_getClass, …) are all
  // callable from Swift, so no ObjC is needed. The original wrapped each call in
  // @try/@catch, but none of these functions throw NSException (a malformed class
  // faults with a signal @try can't catch anyway), so the guards were dropped; the
  // legitimate nil-return paths — a missing metaclass — are preserved via `failedStage`.

  struct RuntimeObjCProperty {
    let name: String
    let attributesString: String
    let classProperty: Bool
  }

  struct RuntimeObjCMethod {
    let name: String
    let typeEncoding: String
    let classMethod: Bool
  }

  struct RuntimeObjCIvar {
    let name: String
    let typeEncoding: String
    let offset: Int
  }

  struct RuntimeObjCProtocol {
    let name: String
    let protocols: [RuntimeObjCProtocol]
    let classProperties: [RuntimeObjCProperty]
    let properties: [RuntimeObjCProperty]
    let classMethods: [RuntimeObjCMethod]
    let methods: [RuntimeObjCMethod]
    let optionalClassProperties: [RuntimeObjCProperty]
    let optionalProperties: [RuntimeObjCProperty]
    let optionalClassMethods: [RuntimeObjCMethod]
    let optionalMethods: [RuntimeObjCMethod]
  }

  struct RuntimeObjCClass {
    let name: String
    let version: Int32
    let imageName: String?
    let instanceSize: Int
    let superClassName: String?
    let protocols: [RuntimeObjCProtocol]
    let ivars: [RuntimeObjCIvar]
    let classProperties: [RuntimeObjCProperty]
    let properties: [RuntimeObjCProperty]
    let classMethods: [RuntimeObjCMethod]
    let methods: [RuntimeObjCMethod]
  }

  enum RuntimeObjCInspector {
    /// The only stages that can genuinely fail in pure Swift: the class-side
    /// property/method reads, when a class has no metaclass. Every other read
    /// returns a non-optional value or an empty list.
    private enum Stage: String {
      case classProperties, properties, classMethods, methods
    }

    /// Snapshot one loaded class. Returns nil with `failedStage` set only when a
    /// required read genuinely fails (a missing metaclass); for a valid class it
    /// always returns a snapshot and leaves `failedStage` nil.
    static func snapshot(for cls: AnyClass, failedStage: inout String?) -> RuntimeObjCClass? {
      failedStage = nil

      let name = NSStringFromClass(cls)
      let imageName = class_getImageName(cls).map { String(cString: $0) }
      let version = class_getVersion(cls)
      let instanceSize = class_getInstanceSize(cls)
      let superClassName = class_getSuperclass(cls).map { NSStringFromClass($0) }

      let protocols = protocolSnapshots(of: cls)
      let ivars = ivarSnapshots(of: cls)
      guard
        let classProperties = propertySnapshots(
          of: cls, isInstance: false, stage: .classProperties, failedStage: &failedStage),
        let properties = propertySnapshots(
          of: cls, isInstance: true, stage: .properties, failedStage: &failedStage),
        let classMethods = methodSnapshots(
          of: cls, isInstance: false, stage: .classMethods, failedStage: &failedStage),
        let methods = methodSnapshots(
          of: cls, isInstance: true, stage: .methods, failedStage: &failedStage)
      else { return nil }

      return RuntimeObjCClass(
        name: name, version: version, imageName: imageName, instanceSize: instanceSize,
        superClassName: superClassName, protocols: protocols, ivars: ivars,
        classProperties: classProperties, properties: properties, classMethods: classMethods,
        methods: methods)
    }

    /// Instance reads use the class itself; class-side reads use its metaclass, which
    /// is the one read that can be absent (then the stage failed).
    private static func target(
      of cls: AnyClass, isInstance: Bool, stage: Stage, failedStage: inout String?
    ) -> AnyClass? {
      if isInstance { return cls }
      guard let metaclass = object_getClass(cls) else {
        failedStage = stage.rawValue
        return nil
      }
      return metaclass
    }

    private static func propertySnapshots(
      of cls: AnyClass, isInstance: Bool, stage: Stage, failedStage: inout String?
    ) -> [RuntimeObjCProperty]? {
      guard
        let target = target(
          of: cls, isInstance: isInstance, stage: stage, failedStage: &failedStage)
      else { return nil }
      var count: UInt32 = 0
      guard let list = class_copyPropertyList(target, &count) else { return [] }
      defer { free(list) }
      return (0..<Int(count)).compactMap { property(list[$0], classProperty: !isInstance) }
    }

    private static func methodSnapshots(
      of cls: AnyClass, isInstance: Bool, stage: Stage, failedStage: inout String?
    ) -> [RuntimeObjCMethod]? {
      guard
        let target = target(
          of: cls, isInstance: isInstance, stage: stage, failedStage: &failedStage)
      else { return nil }
      var count: UInt32 = 0
      guard let list = class_copyMethodList(target, &count) else { return [] }
      defer { free(list) }
      return (0..<Int(count)).compactMap { index -> RuntimeObjCMethod? in
        let method = list[index]
        guard let types = method_getTypeEncoding(method) else { return nil }
        return RuntimeObjCMethod(
          name: NSStringFromSelector(method_getName(method)),
          typeEncoding: String(cString: types), classMethod: !isInstance)
      }
    }

    private static func ivarSnapshots(of cls: AnyClass) -> [RuntimeObjCIvar] {
      var count: UInt32 = 0
      guard let list = class_copyIvarList(cls, &count) else { return [] }
      defer { free(list) }
      return (0..<Int(count)).compactMap { index -> RuntimeObjCIvar? in
        let ivar = list[index]
        guard let name = ivar_getName(ivar), let type = ivar_getTypeEncoding(ivar) else {
          return nil
        }
        return RuntimeObjCIvar(
          name: String(cString: name), typeEncoding: String(cString: type),
          offset: ivar_getOffset(ivar))
      }
    }

    private static func protocolSnapshots(of cls: AnyClass) -> [RuntimeObjCProtocol] {
      var count: UInt32 = 0
      guard let list = class_copyProtocolList(cls, &count) else { return [] }
      defer { free(UnsafeMutableRawPointer(list)) }
      return (0..<Int(count)).map { protocolSnapshot(list[$0]) }
    }

    private static func protocolSnapshot(_ proto: Protocol) -> RuntimeObjCProtocol {
      RuntimeObjCProtocol(
        name: String(cString: protocol_getName(proto)),
        protocols: subprotocolSnapshots(of: proto),
        classProperties: protocolProperties(proto, required: true, instance: false),
        properties: protocolProperties(proto, required: true, instance: true),
        classMethods: protocolMethods(proto, required: true, instance: false),
        methods: protocolMethods(proto, required: true, instance: true),
        optionalClassProperties: protocolProperties(proto, required: false, instance: false),
        optionalProperties: protocolProperties(proto, required: false, instance: true),
        optionalClassMethods: protocolMethods(proto, required: false, instance: false),
        optionalMethods: protocolMethods(proto, required: false, instance: true))
    }

    private static func subprotocolSnapshots(of proto: Protocol) -> [RuntimeObjCProtocol] {
      var count: UInt32 = 0
      guard let list = protocol_copyProtocolList(proto, &count) else { return [] }
      defer { free(UnsafeMutableRawPointer(list)) }
      return (0..<Int(count)).map { protocolSnapshot(list[$0]) }
    }

    private static func protocolProperties(
      _ proto: Protocol, required: Bool, instance: Bool
    ) -> [RuntimeObjCProperty] {
      var count: UInt32 = 0
      guard let list = protocol_copyPropertyList2(proto, &count, required, instance) else {
        return []
      }
      defer { free(list) }
      return (0..<Int(count)).compactMap { property(list[$0], classProperty: !instance) }
    }

    private static func protocolMethods(
      _ proto: Protocol, required: Bool, instance: Bool
    ) -> [RuntimeObjCMethod] {
      var count: UInt32 = 0
      guard let list = protocol_copyMethodDescriptionList(proto, required, instance, &count) else {
        return []
      }
      defer { free(list) }
      return (0..<Int(count)).compactMap { index -> RuntimeObjCMethod? in
        let description = list[index]
        guard let selector = description.name, let types = description.types else { return nil }
        return RuntimeObjCMethod(
          name: NSStringFromSelector(selector), typeEncoding: String(cString: types),
          classMethod: !instance)
      }
    }

    private static func property(
      _ property: objc_property_t, classProperty: Bool
    ) -> RuntimeObjCProperty? {
      guard let attributes = property_getAttributes(property) else { return nil }
      return RuntimeObjCProperty(
        name: String(cString: property_getName(property)),
        attributesString: String(cString: attributes), classProperty: classProperty)
    }
  }
#endif
