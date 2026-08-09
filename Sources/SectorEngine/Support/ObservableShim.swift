//
//  ObservableShim.swift
//  SectorEngine
//
//  Combine is Apple-only. The forecast service conforms to ObservableObject and
//  marks two caches @Published purely so the iOS app's UI can observe them — the
//  server never uses that reactivity. On Linux (no Combine) these inert stand-ins
//  let the same declaration compile. On Apple platforms this file is compiled out
//  and the real Combine types are used.
//

#if !canImport(Combine)
import Foundation

public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public init(initialValue: Value) { self.wrappedValue = initialValue }
}
#endif
