import Foundation
import RustXcframework

public extension RustString {
    func toString() -> String {
        let str = as_str()
        let string = str.toString()

        return string
    }
}

extension RustStr {
    func toBufferPointer() -> UnsafeBufferPointer<UInt8> {
        let bytes = UnsafeBufferPointer(start: start, count: Int(len))
        return bytes
    }

    public func toString() -> String {
        let bytes = toBufferPointer()
        return String(bytes: bytes, encoding: .utf8)!
    }
}

// MARK: - RustStr + Identifiable

extension RustStr: Identifiable {
    public var id: String {
        toString()
    }
}

// MARK: - RustStr + Equatable

extension RustStr: Equatable {
    public static func == (lhs: RustStr, rhs: RustStr) -> Bool {
        // TODO: Rather than compare Strings, we can avoid allocating by calling a function
        // on the Rust side that compares the underlying byte slices.
        lhs.toString() == rhs.toString()
    }
}

// MARK: - IntoRustString

public protocol IntoRustString {
    func intoRustString() -> RustString
}

// MARK: - ToRustStr

public protocol ToRustStr {
    func toRustStr<T>(_ withUnsafeRustStr: (RustStr) -> T) -> T
}

// MARK: - String + IntoRustString

extension String: IntoRustString {
    public func intoRustString() -> RustString {
        // TODO: When passing an owned Swift std String to Rust we've being wasteful here in that
        //  we're creating a RustString (which involves Boxing a Rust std::string::String)
        //  only to unbox it back into a String once it gets to the Rust side.
        //
        //  A better approach would be to pass a RustStr to the Rust side and then have Rust
        //  call `.to_string()` on the RustStr.
        RustString(self)
    }
}

// MARK: - RustString + IntoRustString

extension RustString: IntoRustString {
    public func intoRustString() -> RustString {
        self
    }
}

/// If the String is Some:
///   Safely get a scoped pointer to the String and then call the callback with a RustStr
///   that uses that pointer.
///
/// If the String is None:
///   Call the callback with a RustStr that has a null pointer.
///   The Rust side will know to treat this as `None`.
func optionalStringIntoRustString(_ string: some IntoRustString?) -> RustString? {
    if let val = string {
        return val.intoRustString()
    } else {
        return nil
    }
}

// MARK: - String + ToRustStr

extension String: ToRustStr {
    /// Safely get a scoped pointer to the String and then call the callback with a RustStr
    /// that uses that pointer.
    public func toRustStr<T>(_ withUnsafeRustStr: (RustStr) -> T) -> T {
        utf8CString.withUnsafeBufferPointer { bufferPtr in
            let rustStr = RustStr(
                start: UnsafeMutableRawPointer(mutating: bufferPtr.baseAddress!).assumingMemoryBound(to: UInt8.self),
                // Subtract 1 because of the null termination character at the end
                len: UInt(bufferPtr.count - 1)
            )
            return withUnsafeRustStr(rustStr)
        }
    }
}

// MARK: - RustStr + ToRustStr

extension RustStr: ToRustStr {
    public func toRustStr<T>(_ withUnsafeRustStr: (RustStr) -> T) -> T {
        withUnsafeRustStr(self)
    }
}

func optionalRustStrToRustStr<T>(_ str: some ToRustStr?, _ withUnsafeRustStr: (RustStr) -> T) -> T {
    if let val = str {
        return val.toRustStr(withUnsafeRustStr)
    } else {
        return withUnsafeRustStr(RustStr(start: nil, len: 0))
    }
}

// MARK: - RustVec

// TODO:
//  Implement iterator https://developer.apple.com/documentation/swift/iteratorprotocol

public class RustVec<T: Vectorizable> {
    // MARK: Lifecycle

    init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }

    init() {
        ptr = T.vecOfSelfNew()
        isOwned = true
    }

    deinit {
        if isOwned {
            T.vecOfSelfFree(vecPtr: ptr)
        }
    }

    // MARK: Internal

    var ptr: UnsafeMutableRawPointer
    var isOwned = true

    func push(value: T) {
        T.vecOfSelfPush(vecPtr: ptr, value: value)
    }

    func pop() -> T? {
        T.vecOfSelfPop(vecPtr: ptr)
    }

    func get(index: UInt) -> T.SelfRef? {
        T.vecOfSelfGet(vecPtr: ptr, index: index)
    }

    /// Rust returns a UInt, but we cast to an Int because many Swift APIs such as
    /// `ForEach(0..rustVec.len())` expect Int.
    func len() -> Int {
        Int(T.vecOfSelfLen(vecPtr: ptr))
    }
}

// MARK: Sequence

extension RustVec: Sequence {
    public func makeIterator() -> RustVecIterator<T> {
        RustVecIterator(self)
    }
}

// MARK: - RustVecIterator

public struct RustVecIterator<T: Vectorizable>: IteratorProtocol {
    // MARK: Lifecycle

    init(_ rustVec: RustVec<T>) {
        self.rustVec = rustVec
    }

    // MARK: Public

    public mutating func next() -> T.SelfRef? {
        let val = rustVec.get(index: index)
        index += 1
        return val
    }

    // MARK: Internal

    var rustVec: RustVec<T>
    var index: UInt = 0
}

// MARK: - RustVec + Collection

extension RustVec: Collection {
    public typealias Index = Int

    public func index(after i: Int) -> Int {
        i + 1
    }

    public subscript(position: Int) -> T.SelfRef {
        get(index: UInt(position))!
    }

    public var startIndex: Int {
        0
    }

    public var endIndex: Int {
        len()
    }
}

// MARK: - RustVec + RandomAccessCollection

extension RustVec: RandomAccessCollection {}

extension UnsafeBufferPointer {
    func toFfiSlice() -> __private__FfiSlice {
        __private__FfiSlice(start: UnsafeMutablePointer(mutating: baseAddress), len: UInt(count))
    }
}

extension Array {
    /// Get an UnsafeBufferPointer to the array's content's first byte with the array's length.
    ///
    /// ```
    /// // BAD! Swift will immediately free the arrays memory and so your pointer is invalid.
    /// let pointer = useMyPointer([1, 2, 3].toUnsafeBufferPointer())
    ///
    /// // GOOD! The array will outlive the buffer pointer.
    /// let array = [1, 2, 3]
    /// useMyPointer(array.toUnsafeBufferPointer())
    /// ```
    func toUnsafeBufferPointer() -> UnsafeBufferPointer<Element> {
        UnsafeBufferPointer(start: UnsafePointer(self), count: count)
    }
}

// MARK: - Vectorizable

public protocol Vectorizable {
    associatedtype SelfRef
    associatedtype SelfRefMut

    static func vecOfSelfNew() -> UnsafeMutableRawPointer

    static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer)

    static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Self)

    static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Self?

    static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> SelfRef?

    static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> SelfRefMut?

    static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt
}

// MARK: - UInt8 + Vectorizable

extension UInt8: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_u8$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_u8$_free(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Self) {
        __swift_bridge__$Vec_u8$push(vecPtr, value)
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Self? {
        let val = __swift_bridge__$Vec_u8$pop(vecPtr)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_u8$get(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_u8$get_mut(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_u8$len(vecPtr)
    }
}

// MARK: - UInt16 + Vectorizable

extension UInt16: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_u16$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_u16$_free(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Self) {
        __swift_bridge__$Vec_u16$push(vecPtr, value)
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Self? {
        let val = __swift_bridge__$Vec_u16$pop(vecPtr)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_u16$get(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_u16$get_mut(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_u16$len(vecPtr)
    }
}

// MARK: - UInt32 + Vectorizable

extension UInt32: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_u32$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_u32$_free(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Self) {
        __swift_bridge__$Vec_u32$push(vecPtr, value)
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Self? {
        let val = __swift_bridge__$Vec_u32$pop(vecPtr)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_u32$get(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_u32$get_mut(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_u32$len(vecPtr)
    }
}

// MARK: - UInt64 + Vectorizable

extension UInt64: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_u64$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_u64$_free(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Self) {
        __swift_bridge__$Vec_u64$push(vecPtr, value)
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Self? {
        let val = __swift_bridge__$Vec_u64$pop(vecPtr)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_u64$get(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_u64$get_mut(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_u64$len(vecPtr)
    }
}

// MARK: - UInt + Vectorizable

extension UInt: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_usize$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_usize$_free(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Self) {
        __swift_bridge__$Vec_usize$push(vecPtr, value)
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Self? {
        let val = __swift_bridge__$Vec_usize$pop(vecPtr)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_usize$get(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_usize$get_mut(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_usize$len(vecPtr)
    }
}

// MARK: - Int8 + Vectorizable

extension Int8: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_i8$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_i8$_free(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Self) {
        __swift_bridge__$Vec_i8$push(vecPtr, value)
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Self? {
        let val = __swift_bridge__$Vec_i8$pop(vecPtr)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_i8$get(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_i8$get_mut(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_i8$len(vecPtr)
    }
}

// MARK: - Int16 + Vectorizable

extension Int16: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_i16$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_i16$_free(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Self) {
        __swift_bridge__$Vec_i16$push(vecPtr, value)
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Self? {
        let val = __swift_bridge__$Vec_i16$pop(vecPtr)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_i16$get(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_i16$get_mut(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_i16$len(vecPtr)
    }
}

// MARK: - Int32 + Vectorizable

extension Int32: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_i32$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_i32$_free(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Self) {
        __swift_bridge__$Vec_i32$push(vecPtr, value)
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Self? {
        let val = __swift_bridge__$Vec_i32$pop(vecPtr)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_i32$get(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_i32$get_mut(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_i32$len(vecPtr)
    }
}

// MARK: - Int64 + Vectorizable

extension Int64: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_i64$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_i64$_free(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Self) {
        __swift_bridge__$Vec_i64$push(vecPtr, value)
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Self? {
        let val = __swift_bridge__$Vec_i64$pop(vecPtr)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_i64$get(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_i64$get_mut(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_i64$len(vecPtr)
    }
}

// MARK: - Int + Vectorizable

extension Int: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_isize$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_isize$_free(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Self) {
        __swift_bridge__$Vec_isize$push(vecPtr, value)
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Self? {
        let val = __swift_bridge__$Vec_isize$pop(vecPtr)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_isize$get(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_isize$get_mut(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_isize$len(vecPtr)
    }
}

// MARK: - Bool + Vectorizable

extension Bool: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_bool$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_bool$_free(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Self) {
        __swift_bridge__$Vec_bool$push(vecPtr, value)
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Self? {
        let val = __swift_bridge__$Vec_bool$pop(vecPtr)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_bool$get(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Self? {
        let val = __swift_bridge__$Vec_bool$get_mut(vecPtr, index)
        if val.is_some {
            return val.val
        } else {
            return nil
        }
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_bool$len(vecPtr)
    }
}

// MARK: - SwiftBridgeGenericFreer

protocol SwiftBridgeGenericFreer {
    func rust_free()
}

// MARK: - SwiftBridgeGenericCopyTypeFfiRepr

protocol SwiftBridgeGenericCopyTypeFfiRepr {}

// MARK: - RustString

public class RustString: RustStringRefMut {
    // MARK: Lifecycle

    override public init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$RustString$_free(ptr)
        }
    }

    // MARK: Internal

    var isOwned = true
}

public extension RustString {
    convenience init() {
        self.init(ptr: __swift_bridge__$RustString$new())
    }

    convenience init(_ str: some ToRustStr) {
        self.init(ptr: str.toRustStr { strAsRustStr in
            __swift_bridge__$RustString$new_with_str(strAsRustStr)
        })
    }
}

// MARK: - RustStringRefMut

public class RustStringRefMut: RustStringRef {
    override public init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}

// MARK: - RustStringRef

public class RustStringRef {
    // MARK: Lifecycle

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }

    // MARK: Internal

    var ptr: UnsafeMutableRawPointer
}

public extension RustStringRef {
    func len() -> UInt {
        __swift_bridge__$RustString$len(ptr)
    }

    func as_str() -> RustStr {
        __swift_bridge__$RustString$as_str(ptr)
    }

    func trim() -> RustStr {
        __swift_bridge__$RustString$trim(ptr)
    }
}

// MARK: - RustString + Vectorizable

extension RustString: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_RustString$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_RustString$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: RustString) {
        __swift_bridge__$Vec_RustString$push(vecPtr, { value.isOwned = false; return value.ptr }())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Self? {
        let pointer = __swift_bridge__$Vec_RustString$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (RustString(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> RustStringRef? {
        let pointer = __swift_bridge__$Vec_RustString$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return RustStringRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> RustStringRefMut? {
        let pointer = __swift_bridge__$Vec_RustString$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return RustStringRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_RustString$len(vecPtr)
    }
}

// MARK: - __private__RustFnOnceCallbackNoArgsNoRet

public class __private__RustFnOnceCallbackNoArgsNoRet {
    // MARK: Lifecycle

    init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }

    deinit {
        if !called {
            __swift_bridge__$free_boxed_fn_once_no_args_no_return(ptr)
        }
    }

    // MARK: Internal

    var ptr: UnsafeMutableRawPointer
    var called = false

    func call() {
        if called {
            fatalError("Cannot call a Rust FnOnce function twice")
        }
        called = true
        return __swift_bridge__$call_boxed_fn_once_no_args_no_return(ptr)
    }
}

// MARK: - RustResult

public enum RustResult<T, E> {
    case Ok(T)
    case Err(E)
}

extension RustResult {
    func ok() -> T? {
        switch self {
        case let .Ok(ok):
            return ok
        case .Err:
            return nil
        }
    }

    func err() -> E? {
        switch self {
        case .Ok:
            return nil
        case let .Err(err):
            return err
        }
    }

    func toResult() -> Result<T, E>
        where E: Error
    {
        switch self {
        case let .Ok(ok):
            return .success(ok)
        case let .Err(err):
            return .failure(err)
        }
    }
}
