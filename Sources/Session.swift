//
//  Seesion.swift
//
//
//  Created by darvin on 2021/9/19.
//

/*

 MIT License

 Copyright (c) 2021 darvin http://blog.tcoding.cn

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

import DVTLoger
import Foundation

open class Session {
    fileprivate static var _default: Session?

    public static var `default`: Session? {
        assert(Self.self == Session.self, "该属性只能用于Session类型，不能用于其子类")
        assert(_default != nil, "使用前请先调用setDefault设置默认的Session")
        return _default
    }

    public static func setDefault(_ session: Session) {
        if let value = _default {
            // 取消原有的未完成的网络请求
            value.cancelAll()
        }
        self._default = session
    }

    // MARK: - 属性

    public private(set) var baseUrl: URL?
    fileprivate let queue: DispatchQueue

    fileprivate var requestsRecord: [String: Request]
    fileprivate var afRequestsRecord: [String: AFRequest]

    fileprivate var afSession: AFSession

    fileprivate let cacheQueue: DispatchQueue
    fileprivate var cacheRecord: [Request]

    /// 请求超时时间，修改该参数的时候会取消所有的之前的请求
    public var timeoutInterval: TimeInterval {
        didSet {
            self.resetSession()
        }
    }

    /// 最大并发数，修改该参数的时候会取消所有的之前的请求
    public var maximumConnectionsPerHost: Int {
        didSet {
            self.resetSession()
        }
    }

    public var useCache = true

    /// 加密操作
    public var encryptBlock: (_ request: Request?, _ parameters: AFParameters) -> AFParameters

    /// 解密操作，网络请求完成后的原始的字符串，需要自己解析
    public var decryptBlock: (_ request: Request?, _ value: String) -> String

    /// 构造网络请求头的闭包
    public var httpHeaderBlock: HttpHeaderBlock
    public var allowRequestBlock: (_ request: Request) -> Error?

    /// 网络请求拦截过滤，例如鉴权token失效了，在该闭包实现里将请求保存到cache里，等token刷新成功之后再启动
    ///
    /// 如果需要拦截请返回`nil`
    public var filterBlock: (_ request: Request) -> Request?

    /// 网络请求结束后，请求状态判断前的操作处理闭包，在这个闭包可以对数据进行提前一步编辑。如果请求成功，在解密操作后执行；如果请求失败不执行解密操作
    /// 是否忽略本次结果，如果忽略就不会走请求结果的闭包 ignore

    public var preOperationCallBack: OperationCallBackBlock
    /// 参数签名，在构建请求的时候调用，返回参数签名的key和value
    public var signatureBlock: SignatureBlock

    // MARK: - 初始化

    public init(_ baseUrl: String? = nil) {
        var newBaseUrl = baseUrl ?? ""
        while newBaseUrl.hasSuffix("/") {
            newBaseUrl.removeLast()
        }
        if !newBaseUrl.isEmpty, let tempBaseUrl = URL(string: newBaseUrl) {
            self.baseUrl = tempBaseUrl
        }

        self.httpHeaderBlock = { $1 }
        self.allowRequestBlock = { _ in nil }
        self.filterBlock = { $0 }
        self.decryptBlock = { $1 }
        self.encryptBlock = { $1 }
        self.preOperationCallBack = { _, result, error, _ in (result, error) }
        self.signatureBlock = { _, _ in nil }
        self.afSession = AFSession()
        self.maximumConnectionsPerHost = 10
        self.timeoutInterval = 30.0
        self.queue = DispatchQueue(label: "cn.tcoding.DVTNetwork.manager.\(UUID().uuidString)")
        self.requestsRecord = [:]
        self.afRequestsRecord = [:]

        self.cacheQueue = DispatchQueue(label: "cn.tcoding.DVTNetwork.manager.cache.\(UUID().uuidString)")
        self.cacheRecord = []
    }

    @discardableResult
    public func resetBaseUrl(_ url: String) -> Bool {
        if let tempUrl = URL(string: url) {
            self.cancelAll()
            self.baseUrl = tempUrl
            return true
        }
        return false
    }

    /// 是否允许请求
    /// - Parameter request: 网络请求对象
    /// - Returns: 错误信息，如果不允许就返回错误信息
    open func allowRequest(_ request: Request) -> Error? {
        return self.allowRequestBlock(request)
    }
}

/// 请求管理
public extension Session {
    fileprivate
    func success(_ request: Request, value: String, isCache: Bool) {
        let tempValue = request.decrypt(value)
        guard let (handleValue, handleError) = request.preOperation(tempValue, error: nil, isCache: isCache) else {
            return
        }

        if let resultValue = handleValue {
            request.completion?(.success(result: resultValue, isCache: isCache))
        }

        if let tError = handleError {
            request.completion?(.failure(error: tError))
        }
    }

    /// 处理请求结果
    fileprivate
    func handleRequestResult(_ request: Request, result: AFStringDataResponse) {
        var tempRequest: Request?
        self.queue.sync { [weak self] in
            if let key = request.identifier, !key.isEmpty {
                tempRequest = self?.requestsRecord.removeValue(forKey: key)
                self?.afRequestsRecord.removeValue(forKey: key)
            }
        }
        guard let handleRequest = tempRequest else {
            return
        }

        var retry = false
        defer {
            // 先结束，再重新发起
            handleRequest.didCompletion(false)
            if retry {
                self.append(requestOf: handleRequest)
            }
        }

        switch result.result {
            case let .success(resultValue):
                // 在这里可以把结果缓存
                handleRequest.saveCache(resultValue)
                self.success(handleRequest, value: resultValue, isCache: false)
            case let .failure(error):
                if handleRequest.retry(error) {
                    retry = true
                    return
                } else {
                    guard let tuples = handleRequest.preOperation(nil, error: error, isCache: false) else {
                        return
                    }
                    request.completion?(.failure(error: tuples.error ?? error))
                }
        }
    }

    /// 取消该会话的所有请求
    func cancelAll() {
        self.queue.async { [weak self] in
            self?.requestsRecord.forEach({ _, request in
                // 这里不直接调用request.cancel()，原因是request.cancel()会调用cancel(at:)，然后造成死锁
                request.afRequest?.cancel()
                request.didCompletion(true)
            })
            self?.requestsRecord.removeAll()
            self?.afRequestsRecord.removeAll()
        }
    }

    /// 取消指定的请求
    func cancel(at request: Request) {
        self.cancelCache()
        var tempRequest: Request?
        self.queue.sync { [weak self] in
            if let key = request.identifier, !key.isEmpty {
                tempRequest = self?.requestsRecord.removeValue(forKey: key)
                self?.afRequestsRecord.removeValue(forKey: key)
            }
        }
        tempRequest?.afRequest?.cancel()
        tempRequest?.didCompletion(true)
    }

    /// 添加一个请求，添加后立马执行
    func append(requestOf request: Request) {
        guard let request = self.filterBlock(request) else {
            return
        }

        request.isCompletion = false
        if let error = self.allowRequest(request) {
            if let handleError = request.preOperation(nil, error: error, isCache: false)?.error {
                DispatchQueue.main.async {
                    request.completion?(.failure(error: handleError))
                }
            }
            return
        }

        request.buildCustomUrlRequest(self.afSession)
        guard let sendRequest = request.afRequest as? AFDataRequest else {
            let error = AFError.createURLRequestFailed(error: NSError(domain: "初始化失败", code: -999, userInfo: nil))
            DispatchQueue.main.async {
                request.completion?(.failure(error: error))
            }
            return
        }

        // 将请求添加到任务记录容器
        self.queue.sync { [weak self] in
            if let key = request.identifier, !key.isEmpty {
                self?.requestsRecord[key] = request
                self?.afRequestsRecord[key] = sendRequest
            }
        }
        request.willStart()
        // 在这里读取缓存
        if self.useCache, request.useCache, request.cacheTime > 0, let resultValue = request.cache() {
            DispatchQueue.main.async {
                self.success(request, value: resultValue, isCache: true)
            }
        }
        sendRequest.validate(statusCode: 200 ..< 300).responseString(encoding: request.resultEncoding) { [weak self] result in
            self?.handleRequestResult(request, result: result)
        }
    }

    func appendCache(requestOf request: Request) {
        self.cacheQueue.sync {
            self.cacheRecord.append(request)
        }
    }

    func startCache() {
        self.cacheQueue.sync {
            while !self.cacheRecord.isEmpty {
                let request = self.cacheRecord.removeFirst()
                // 如果不切换到其它线程然后在filterBlock(request)、allowRequest(request)里直接把请求插入到缓存会造成线程死锁
                DispatchQueue.main.async {
                    request.start()
                }
            }
        }
        DispatchQueue.main.async {
            if !self.cacheRecord.isEmpty {
                self.startCache()
            }
        }
    }

    func cancelCache() {
        self.cacheQueue.sync {
            self.cacheRecord.forEach { request in
                request.didCompletion(true)
            }
            self.cacheRecord.removeAll()
        }
    }
}

/// 通过单例发起请求
public extension Session {
    @discardableResult
    static func send(_ method: AFHTTPMethod = .post, url: String, parameters: AFParameters = [:], completion: @escaping AnyCompletionBlock) -> Request? {
        guard let session = Session.default else { return nil }
        if let request = Request(self.default, method: method, requestUrl: url, parameters: parameters) {
            request.setRequestBlock(completion)
            DispatchQueue.main.async {
                session.append(requestOf: request)
            }
            return request
        }
        return nil
    }

    @discardableResult
    static func send(_ method: AFHTTPMethod = .post, path: String, parameters: AFParameters = [:], completion: @escaping AnyCompletionBlock) -> Request? {
        guard let session = Session.default else { return nil }
        if let request = Request(self.default, method: method, path: path, parameters: parameters) {
            request.setRequestBlock(completion)
            DispatchQueue.main.async {
                session.append(requestOf: request)
            }
            return request
        }
        return nil
    }
}

private extension Session {
    func resetSession() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = self.timeoutInterval
        configuration.httpMaximumConnectionsPerHost = self.maximumConnectionsPerHost
        self.requestsRecord.removeAll()
        self.afRequestsRecord.removeAll()
        self.afSession.cancelAllRequests()
        self.afSession = AFSession(configuration: configuration)
    }
}
