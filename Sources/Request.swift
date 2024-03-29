//
//  Request.swift
//  DVTNetwork
//
//  Created by darvin on 2021/9/19.
//

/*

 MIT License

 Copyright (c) 2022 darvin http://blog.tcoding.cn

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.

 */

import Foundation
import typealias CommonCrypto.CC_LONG
import func CommonCrypto.CC_SHA256
import var CommonCrypto.CC_SHA256_DIGEST_LENGTH

open class Request {
    // MARK: Lifecycle
    public required init?(_ session: Session?, method: AFHTTPMethod = .post, parameterEncoding: AFParameterEncoding = AFURLEncoding.default,
                          resultEncoding: String.Encoding = .utf8, path: String = "", baseURL: String = "", requestURL: String = "",
                          headers: AFHTTPHeaders = [:], parameters: AFParameters = [:], useCache: Bool = false, cacheTime: TimeInterval = 7 * 24 * 3600) {
        guard let tempSession = session ?? Session.default else {
            return nil
        }

        var newPath = path
        while newPath.hasPrefix("/") {
            newPath.removeFirst()
        }
        self.path = newPath

        var newBaseURL = baseURL
        while newBaseURL.hasSuffix("/") {
            newBaseURL.removeLast()
        }
        self._baseURL = URL(string: newBaseURL)

        self._requestURL = URL(string: requestURL)

        self.session = tempSession
        self.method = method
        self.parameterEncoding = parameterEncoding
        self.resultEncoding = resultEncoding
        self.headers = headers
        self.parameters = parameters
        self.useCache = useCache
        self.cacheTime = cacheTime
    }

    public convenience init?() {
        self.init(nil)
    }

    deinit {
        NetLoger.debug("deinit \(Self.self)")
    }

    // MARK: Open
    open private(set) var method: AFHTTPMethod = .post
    open private(set) var parameterEncoding: AFParameterEncoding = AFURLEncoding.default
    open private(set) var resultEncoding: String.Encoding = .utf8
    open private(set) var isPrintResult = true

    // MARK: - 请求路径

    open private(set) var path: String

    // MARK: - 请求参数

    open private(set) var headers: AFHTTPHeaders = [:]
    open private(set) var parameters: AFParameters = [:]

    // MARK: - 缓存

    /// 仅httpMethod = .get有效
    open private(set) var useCache = false
    /// 接口缓存时间，默认为7天，单位（秒）; 如果超过session的缓存时间无效
    open private(set) var cacheTime: TimeInterval

    /// 需要忽略的参数名
    open private(set) var cacheIgnoreParameters: [String] = []

    open var baseURL: URL? {
        self._baseURL ?? self.session.baseURL
    }

    open var requestURL: URL {
        if self._requestURL == nil {
            var newPath = self.path
            while newPath.hasPrefix("/") {
                newPath.removeFirst()
            }
            self._requestURL = self.baseURL?.appendingPathComponent(newPath)
        }
        if let url = self._requestURL {
            return url
        }
        fatalError("url不能为空")
    }

    /// 请求缓存的相对路径
    open var cacheFliePath: String {
        "\(self.cacheFolder())/\(self.cacheFileName)"
    }

    // MARK: - 加解密

    open func encrypt() -> AFParameters {
        let parameters = self.parameters
        if !parameters.isEmpty {
            NetLoger.debug("参数加密：", parameters)
        }
        weak var tempSelf = self
        return self.session.encryptBlock(tempSelf, parameters)
    }

    open func decrypt(_ value: String) -> String {
        weak var tempSelf = self
        return self.session.decryptBlock(tempSelf, value)
    }

    open func preOperation(_ result: Any?, error: Error?, isCache: Bool) -> (result: Any?, error: Error?)? {
        return self.session.preOperationCallBack(self, result, error, isCache)
    }

    /// 参数签名，在构建请求的时候调用，返回参数签名的key和value
    open func signature(_ headers: AFHTTPHeaders, parameters: AFParameters) -> (key: String, value: String)? {
        return self.session.signatureBlock(headers, parameters)
    }

    /// 构造网络请求
    open func buildCustomURLRequest(_ afSeeion: AFSession) {
        self.count += 1

        let parameters = self.encrypt()
        var headers = self.session.httpHeaderBlock(self, self.headers)

        if let sign = self.signature(headers, parameters: parameters) {
            headers.add(name: sign.key, value: sign.value)
        }
        self.afRequest = afSeeion.request(self.requestURL, method: self.method, parameters: parameters, encoding: self.parameterEncoding, headers: headers)
        self.requestHeaders = headers
        self.requestParameters = parameters
    }

    /// 即将发起请求
    open func willStart() {
        var string = ""
        string = "开始网络请求<" + self.requestURL.absoluteString + ">"

        if !self.requestHeaders.isEmpty {
            string += "\n请求头：\n\(self.requestHeaders)"
        }
        if !self.requestParameters.isEmpty {
            string += "\n请求体：\n\(self.requestParameters)\n"
        }
        NetLoger.debug(string)
    }

    /// 发起请求
    open func start(_ completion: AnyCompletionBlock? = nil) {
        if let tc = completion {
            self.setRequestBlock(tc)
        }
        self.session.append(requestOf: self)
    }

    /// 重新发起网络请求，必须该请求完成之后
    open func retry() {
        if self.isCompletion {
            self.session.append(requestOf: self)
        }
    }

    /// 网络请求错误后是否重试
    /// - Parameter error: 错误
    /// - Returns: 是否重试
    open func retry(_ error: Error) -> Bool {
        return false
    }

    /// 取消请求
    open func cancel() {
        self.session.cancel(at: self)
        self.didCompletion(true)
    }

    /// 已经结束请求，是否是取消
    open func didCompletion(_ isCancel: Bool) {
        if isCancel, !self.isCompletion {
            DispatchQueue.main.async {
                self.completion?(.cancel)
            }
        }
        self.isCompletion = true
        NetLoger.debug("网络请求结束")
    }

    /// 针对多用户的接口缓存作用，可以用用户名等字段来分辨
    /// - Returns: 文件夹名
    open func cacheFolder() -> String {
        return "\(self.self)"
    }

    // MARK: Public
    public let session: Session
    public private(set) var identifier: String?

    // MARK: - 请求处理

    /// 请求完成的回调
    public var completion: AnyCompletionBlock?

    public var requestHeaders: AFHTTPHeaders = [:]
    public var requestParameters: AFParameters = [:]
    public var count = 0

    public weak var afRequest: AFRequest? {
        didSet {
            self.identifier = self.afRequest?.id.uuidString
        }
    }

    public func setRequestBlock(_ completion: @escaping AnyCompletionBlock) {
        self.completion = completion
    }

    public func saveCache(_ value: String) {
        if self.method != .get || !self.useCache {
            return
        }
        self.cacheCreateTime = Date()
        self.cacheResult = value
        // 将缓存写入文件
        CacheManager.addCache(self.cacheFliePath, value: value, expiration: self.cacheTime)
    }

    public func cache() -> String? {
        if self.method != .get || !self.useCache {
            return nil
        }
        let nowTime = Date()

        if self.cacheResult != nil {
            if nowTime.timeIntervalSince1970 - self.cacheTime > (self.cacheCreateTime?.timeIntervalSince1970 ?? 0) {
                return self.cacheResult
            }
        } else {
            // 从文件读取缓存
            let value = CacheManager.cacheString(self.cacheFliePath)
            return value
        }
        return nil
    }

    // MARK: Internal
    internal var isCompletion = false

    // MARK: Fileprivate
    /// cacheResult
    fileprivate var cacheResult: String?
    fileprivate var cacheCreateTime: Date?

    // MARK: Private
    private let id = UUID().uuidString
    private var _baseURL: URL?
    private var _requestURL: URL?
}

extension Request: Equatable {
    public static func == (lhs: Request, rhs: Request) -> Bool {
        lhs.id == rhs.id
    }
}

/// cache路径相关
private extension Request {
    var cacheFileName: String {
        let parameters = self.parameters.filter { !self.cacheIgnoreParameters.contains($0.key) }.sorted {
            $0.key.uppercased() > $1.key.uppercased()
        }
        return self.sha256(String(format: "%@%@", self.requestURL.absoluteString, parameters)) + ".request"
    }

    func sha256(_ string: String) -> String {
        let length = Int(CC_SHA256_DIGEST_LENGTH)
        let messageData = string.data(using: .utf8)!
        var digestData = Data(count: length)

        _ = digestData.withUnsafeMutableBytes { digestBytes -> UInt8 in
            messageData.withUnsafeBytes { messageBytes -> UInt8 in
                if let messageBytesBaseAddress = messageBytes.baseAddress, let digestBytesBlindMemory = digestBytes.bindMemory(to: UInt8.self).baseAddress {
                    let messageLength = CC_LONG(messageData.count)
                    CC_SHA256(messageBytesBaseAddress, messageLength, digestBytesBlindMemory)
                }
                return 0
            }
        }
        return digestData.map { String(format: "%02hhx", $0) }.joined().uppercased()
    }
}

private class RequestCacheInfo: Codable {
    // MARK: Lifecycle
    init(_ filePath: String, expiration: TimeInterval) {
        self.expiration = Date().timeIntervalSince1970 + expiration
        self.infoFilePath = "info/\(filePath)"
        self.filePath = "\(filePath)"
    }

    // MARK: Internal
    let filePath: String
    let infoFilePath: String
    let expiration: TimeInterval

    static func getInfoPath(pathOf filePath: String) -> String {
        return "info/\(filePath)"
    }

    static func decoder(of path: String) -> Self? {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return try? JSONDecoder().decode(self, from: data)
        }
        return nil
    }

    func encoder(of path: String) -> Bool {
        if let data = try? JSONEncoder().encode(self) {
            do {
                try data.write(to: URL(fileURLWithPath: path))
                return true
            } catch {
                return false
            }
        }
        return false
    }
}

/// 该类获取缓存方法都会堵塞当前线程
public class CacheManager {
    // MARK: Public
    public static func removeAll() {
        try? FileManager.default.removeItem(atPath: self.cacheBasePath)
    }

    public static func remove(_ group: String = "default") {
        try? FileManager.default.removeItem(atPath: self.cacheBasePath + "/\(group)")
        try? FileManager.default.removeItem(atPath: self.cacheBasePath + "/info/\(group)")
    }

    public static func removeExpiration() {
        var isDir: ObjCBool = true
        let dirPath = self.cacheBasePath + "/info"
        guard FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else {
            return
        }
        do {
            let array = try FileManager.default.contentsOfDirectory(atPath: dirPath)
            for fileName in array {
                let fullPath = "\(dirPath)/\(fileName)"
                if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir) {
                    if isDir.boolValue {
                        let list = try FileManager.default.contentsOfDirectory(atPath: fullPath)
                        for infoName in list {
                            let infoPath = fullPath + "/" + infoName
                            if let cacheInfo = RequestCacheInfo.decoder(of: infoPath) {
                                if cacheInfo.expiration < Date().timeIntervalSince1970 {
                                    try? FileManager.default.removeItem(atPath: self.cacheBasePath + "/info/" + cacheInfo.infoFilePath)
                                    try? FileManager.default.removeItem(atPath: self.cacheBasePath + "/" + cacheInfo.filePath)
                                }
                            }
                        }
                    }
                }
            }
        } catch let error as NSError {
            print("get file path error: \(error)")
        }
    }

    // MARK: Fileprivate
    fileprivate static let queue = DispatchQueue(label: "cn.tcoding.DVTNetwork.cacheManager")
}

private extension CacheManager {
    static var cacheBasePath: String {
        let path = (NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? "").appending("/cn.tcoding.Cache.Request")
        if self.createBaseDirectory(at: path) {
            _ = self.createBaseDirectory(at: path + "/info")
            return path
        }
        return ""
    }

    static func cache(_ filePath: String) -> Data? {
        let infoFilePath = RequestCacheInfo.getInfoPath(pathOf: filePath)
        if let tempCacheInfo = RequestCacheInfo.decoder(of: "\(self.cacheBasePath)/\(infoFilePath)") {
            if tempCacheInfo.expiration < Date().timeIntervalSince1970 {
                return nil
            }
            var data: Data?
            self.queue.sync {
                try? data = Data(contentsOf: URL(fileURLWithPath: "\(self.cacheBasePath)/\(tempCacheInfo.filePath)"))
            }
            return data
        }
        return nil
    }

    static func cacheString(_ filePath: String) -> String? {
        if let tempData = self.cache(filePath) {
            return String(data: tempData, encoding: .utf8)
        }
        return nil
    }

    static func addCache(_ filePath: String, value: String, expiration: TimeInterval, completionBlock: ((_ success: Bool) -> Void)? = nil) {
        self.addCache(filePath, data: value.data(using: .utf8) ?? Data(), expiration: expiration)
    }

    static func addCache(_ filePath: String, data: Data, expiration: TimeInterval, completionBlock: ((_ success: Bool) -> Void)? = nil) {
        guard !self.cacheBasePath.isEmpty, !filePath.isEmpty else {
            if completionBlock != nil {
                completionBlock?(false)
            }
            return
        }
        let cacheInfo = self.getCacheInfo(filePath, expiration: expiration)
        self.queue.async {
            var flag = true
            do {
                try data.write(to: URL(fileURLWithPath: "\(self.cacheBasePath)/\(cacheInfo.filePath)"))
            } catch {
                NetLoger.error(error)
                flag = false
            }
            if flag {
                flag = cacheInfo.encoder(of: "\(self.cacheBasePath)/\(cacheInfo.infoFilePath)")
                if completionBlock != nil {
                    completionBlock?(flag)
                }
            }
        }
    }

    static func getCacheInfo(_ filePath: String, expiration: TimeInterval) -> RequestCacheInfo {
        var list = filePath.components(separatedBy: "/")
        if !list.isEmpty {
            list.removeLast()
            _ = self.createBaseDirectory(at: "\(self.cacheBasePath)/\(list.joined(separator: "/"))")
            if list.count >= 1 {
                list.insert("info", at: list.count - 1)
            }
            _ = self.createBaseDirectory(at: "\(self.cacheBasePath)/\(list.joined(separator: "/"))")
        }

        return RequestCacheInfo(filePath, expiration: expiration)
    }

    static func createBaseDirectory(at path: String) -> Bool {
        var isDirectory = ObjCBool(false)

        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            return true
        }

        do {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true, attributes: nil)
        } catch {
            return false
        }
        return true
    }
}
