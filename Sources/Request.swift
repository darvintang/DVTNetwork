//
//  Request.swift
//
//
//  Created by darvintang on 2021/9/19.
//

/*

 MIT License

 Copyright (c) 2021 darvintang http://blog.tcoding.cn

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
import func CommonCrypto.CC_MD5
import var CommonCrypto.CC_MD5_DIGEST_LENGTH

public protocol RequestInit {
    init?(_ session: Session?)
}

open class Request: RequestInit {
    public let session: Session

    public private(set) var identifier: String?
    public weak var afRequest: AFRequest? {
        didSet {
            self.identifier = self.afRequest?.id.uuidString
        }
    }

    /// 在导入了DVTObjectMapper或ObjectMapper后使用
    open var resultType: ResultMappable.Type?
    open var method: AFHTTPMethod = .post
    open var parameterEncoding: AFParameterEncoding = AFURLEncoding.default
    open var resultEncoding: String.Encoding = .utf8

    // MARK: - 请求路径

    open var path = ""
    open var baseUrl = ""
    open var requestUrl = ""

    // MARK: - 请求参数

    open var headers: AFHTTPHeaders = [:]
    open var parameters: AFParameters = [:]

    // MARK: - 请求处理

    /// 请求成功的回调
    public var successBlock: SuccessBlock?
    /// 请求失败的回调
    public var failureBlock: FailureBlock?
    /// 请求完成的回调
    public var completedBlock: CompleteBlock?

    public func setRequestBlock(_ successBlock: SuccessBlock? = nil, failure failureBlock: FailureBlock? = nil, completed completedBlock: CompleteBlock? = nil) {
        self.successBlock = successBlock
        self.failureBlock = failureBlock
        self.completedBlock = completedBlock
    }

    // MARK: - 加解密

    open func encrypt() -> AFParameters {
        let parameters = self.parameters
        if !parameters.isEmpty {
            loger.debug("参数加密：", parameters)
        }
        weak var tempSelf = self
        return self.session.encryptBlock(tempSelf, parameters)
    }

    open func decrypt(_ value: String) -> String {
        if !value.isEmpty {
            loger.debug("接口", self.requestUrl, "的返回数据：", value)
        }
        weak var tempSelf = self
        return self.session.decryptBlock(tempSelf, value)
    }

    // MARK: - 初始化

    public required init?(_ session: Session?) {
        guard let tempSession = session ?? Session.default else {
            return nil
        }
        self.session = tempSession
        self.cacheTime = 7 * 24 * 3600
    }

    public convenience init?() {
        self.init(nil)
    }

    deinit {
        loger.info("deinit \(Self.self)")
    }

    open func preOperation(_ value: Any?, error: Error?, isCache: Bool) -> (Any?, Error?) {
        return self.session.preOperationCallBack(self, value, error, isCache)
    }

    /// 即将发起请求
    open func willStart() {
        loger.debug("开始网络请求<", self.requestUrl, ">")
        if !self.headers.isEmpty {
            print("请求头：\n", self.headers)
        }
        if !self.parameters.isEmpty {
            print("请求体：\n", self.parameters)
        }
    }

    /// 发起请求
    open func start(_ successBlock: SuccessBlock? = nil, failure failureBlock: FailureBlock? = nil, completed completedBlock: CompleteBlock? = nil) {
        self.setRequestBlock(successBlock, failure: failureBlock, completed: completedBlock)
        self.session.append(requestOf: self)
    }

    /// 取消请求
    open func cancel() {
        self.session.cancel(at: self)
        self.didCompletion(true)
    }

    /// 已经结束请求，是否是取消
    open func didCompletion(_ isCancel: Bool) {
        loger.debug("网络请求结束")
    }

    // MARK: - 缓存

    /// 仅httpMethod = .get有效
    public var useCache = true
    /// 接口缓存时间，默认为7天，单位（秒）；
    open var cacheTime: TimeInterval {
        willSet {
            if newValue > self.session.cacheTime {
                self.cacheTime = self.session.cacheTime
            }
        }
    }

    /// 需要忽略的参数名
    open var cacheIgnoreParameters: [String] = []
    open var getCacheIgnoreParameters: [String] {
        self.cacheIgnoreParameters
    }

    /// cacheResult
    fileprivate var cacheResult: String?
    fileprivate var cacheCreateTime: Date?

    /// 针对多用户的接口缓存作用，可以用用户名等字段来分辨
    /// - Returns: 文件夹名
    open func cacheFolder() -> String {
        return "\(self.self)"
    }

    /// 请求缓存的相对路径
    open var cacheFliePath: String {
        "\(self.cacheFolder())/\(self.cacheFileName)"
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

    // MARK: - 实现类似OC重写属性get方法设置请求

    open var getResultType: ResultMappable.Type? { self.resultType }
    open var getMethod: AFHTTPMethod { self.method }
    open var getParameterEncoding: AFParameterEncoding { self.parameterEncoding }
    open var getResultEncoding: String.Encoding { self.resultEncoding }

    open var getPath: String { self.path }
    open var getBaseUrl: String { self.baseUrl.isEmpty ? self.session.baseUrl : self.baseUrl }
    open var getRequestUrl: String { self.requestUrl }
    open var getHeaders: AFHTTPHeaders { self.headers }
    open var getParameters: AFParameters { self.parameters }

    open dynamic func willBuild() {
        self.method = self.getMethod
        self.parameterEncoding = self.getParameterEncoding
        self.resultEncoding = self.getResultEncoding

        self.path = self.getPath
        self.baseUrl = self.getBaseUrl

        self.requestUrl = self.getRequestUrl
        if self.requestUrl.isEmpty {
            self.requestUrl = "\(self.baseUrl)/\(self.path)"
        }

        self.headers = self.getHeaders
        self.parameters = self.getParameters
        self.resultType = self.getResultType
    }
}

/// cache路径相关
private extension Request {
    func md5(_ string: String) -> String {
        let length = Int(CC_MD5_DIGEST_LENGTH)
        let messageData = string.data(using: .utf8)!
        var digestData = Data(count: length)

        _ = digestData.withUnsafeMutableBytes { digestBytes -> UInt8 in
            messageData.withUnsafeBytes { messageBytes -> UInt8 in
                if let messageBytesBaseAddress = messageBytes.baseAddress, let digestBytesBlindMemory = digestBytes.bindMemory(to: UInt8.self).baseAddress {
                    let messageLength = CC_LONG(messageData.count)
                    CC_MD5(messageBytesBaseAddress, messageLength, digestBytesBlindMemory)
                }
                return 0
            }
        }
        return digestData.map { String(format: "%02hhx", $0) }.joined().uppercased()
    }

    var cacheFileName: String {
        let parameters = self.parameters.filter({ !self.cacheIgnoreParameters.contains($0.key) }).sorted {
            $0.key.uppercased() > $1.key.uppercased()
        }
        return self.md5(String(format: "%@%@", self.requestUrl, parameters)) + ".request"
    }
}

/// 上传文件
open class UploadRequest: Request {
    public var progressBlock: ProgressBlock?
    open func multipartFormData(_ formData: AFMultipartFormData) {
    }

    /// 发起请求
    open func start(_ successBlock: SuccessBlock? = nil, failure failureBlock: FailureBlock? = nil, progress progressBlock: ProgressBlock? = nil, completed completedBlock: CompleteBlock? = nil) {
        self.progressBlock = progressBlock
        self.start(successBlock, failure: failureBlock, completed: completedBlock)
    }
}

private class RequestCacheInfo: Codable {
    let filePath: String
    let infoFilePath: String
    let expiration: TimeInterval

    init(_ filePath: String, expiration: TimeInterval) {
        self.expiration = Date().timeIntervalSince1970 + expiration
        self.infoFilePath = "info/\(filePath)"
        self.filePath = "\(filePath)"
    }

    static func getInfoPath(pathOf filePath: String) -> String {
        return "info/\(filePath)"
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

    static func decoder(of path: String) -> Self? {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return try? JSONDecoder().decode(self, from: data)
        }
        return nil
    }
}

/// 该类获取缓存方法都会堵塞当前线程
public class CacheManager {
    fileprivate static let queue: DispatchQueue = DispatchQueue(label: "cn.tcoding.DVTNetwork.cacheManager")

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
}

private extension CacheManager {
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

    static func addCache(_ filePath: String, value: String, expiration: TimeInterval, completedBlock: ((_ success: Bool) -> Void)? = nil) {
        self.addCache(filePath, data: value.data(using: .utf8) ?? Data(), expiration: expiration)
    }

    static func addCache(_ filePath: String, data: Data, expiration: TimeInterval, completedBlock: ((_ success: Bool) -> Void)? = nil) {
        guard !self.cacheBasePath.isEmpty && !filePath.isEmpty else {
            if completedBlock != nil {
                completedBlock?(false)
            }
            return
        }
        let cacheInfo = self.getCacheInfo(filePath, expiration: expiration)
        self.queue.async {
            var flag = true
            do {
                try data.write(to: URL(fileURLWithPath: "\(self.cacheBasePath)/\(cacheInfo.filePath)"))
            } catch let error {
                loger.info(error)
                flag = false
            }
            if flag {
                flag = cacheInfo.encoder(of: "\(self.cacheBasePath)/\(cacheInfo.infoFilePath)")
                if completedBlock != nil {
                    completedBlock?(flag)
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

    static var cacheBasePath: String {
        let path = (NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first ?? "").appending("/cn.tcoding.Cache.Request")
        if self.createBaseDirectory(at: path) {
            _ = self.createBaseDirectory(at: path + "/info")
            return path
        }
        return ""
    }
}
