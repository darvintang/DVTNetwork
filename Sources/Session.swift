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

    #if canImport(DVTLoger)
        public var logLevel: LogerLevel {
            didSet {
                netLoger.debugLogLevel = self.logLevel
            }
        }
    #endif

    public var useCache = true

    /// 加密操作
    public var encryptBlock: (_ request: Request?, _ parameters: AFParameters) -> AFParameters

    /// 解密操作，网络请求完成后的原始的字符串，需要自己解析
    public var decryptBlock: (_ request: Request?, _ value: String) -> String

    /// 构造网络请求头的闭包
    public var httpHeaderBlock: (_ request: Request?, _ header: AFHTTPHeaders) -> AFHTTPHeaders
    public var allowRequestBlock: (_ request: Request) -> Error?
    /// 网络请求结束后，请求状态判断前的操作处理闭包，在这个闭包可以对数据进行提前一步编辑。如果请求成功，在解密操作后执行；如果请求失败不执行解密操作
    /// 是否忽略本次结果，如果忽略就不会走请求结果的闭包 ignore
    public var preOperationCallBack: OperationCallBack

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
        self.decryptBlock = { $1 }
        self.encryptBlock = { $1 }
        self.preOperationCallBack = { _, value, error, _ in (false, value, error) }
        self.afSession = AFSession()
        self.maximumConnectionsPerHost = 10
        self.timeoutInterval = 30.0
        self.queue = DispatchQueue(label: "cn.tcoding.DVTNetwork.manager.\(UUID().uuidString)")
        self.requestsRecord = [:]
        self.afRequestsRecord = [:]
        self.logLevel = .info
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
        let (ignore, handleValue, handleError) = request.preOperation(tempValue, error: nil, isCache: isCache)
        if ignore {
            return
        }
        var resultValue = handleValue

        if let resultType = request.resultType {
            if let value = handleValue as? String {
                resultValue = resultType.init(JSONString: value)
            } else if let value = handleValue as? [String: Any] {
                resultValue = resultType.init(JSON: value)
            }
        }

        if handleError == nil {
            request.success?(resultValue, isCache)
        }

        if handleError != nil {
            request.failure?(handleError)
        }

        request.completion?(resultValue, handleError, isCache)
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

        defer {
            handleRequest.didCompletion(false)
        }

        switch result.result {
            case let .success(resultValue):
                // 在这里可以把结果缓存
                handleRequest.saveCache(resultValue)
                self.success(handleRequest, value: resultValue, isCache: false)
            case let .failure(error):
                if handleRequest.retry(error) {
                    self.append(requestOf: handleRequest)
                    return
                } else {
                    let tuples = handleRequest.preOperation(nil, error: error, isCache: false)
                    if tuples.ignore {
                        return
                    }

                    request.failure?(tuples.error)
                    request.completion?(nil, tuples.error, false)
                }
        }
    }

    /// 取消该会话的所有请求
    func cancelAll() {
        self.queue.async { [weak self] in
            self?.requestsRecord.forEach({ _, request in
                request.afRequest?.cancel()
                request.didCompletion(true)
            })
            self?.requestsRecord.removeAll()
            self?.afRequestsRecord.removeAll()
        }
    }

    /// 取消指定的请求
    func cancel(at request: Request) {
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
        if let error = self.allowRequest(request) {
            let handleError = request.preOperation(nil, error: error, isCache: false).error
            request.failure?(handleError)
            request.completion?(nil, handleError, false)
            return
        }

        request.buildCustomUrlRequest(self.afSession)
        guard let sendRequest = request.afRequest as? AFDataRequest else {
            let error = AFError.createURLRequestFailed(error: NSError(domain: "初始化失败", code: -999, userInfo: nil))
            request.failure?(error)
            request.completion?(nil, error, false)
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
            self.success(request, value: resultValue, isCache: true)
        }
        sendRequest.validate(statusCode: 200 ..< 300).responseString(encoding: request.resultEncoding) { [weak self] result in
            self?.handleRequestResult(request, result: result)
        }
    }
}

/// 通过单例发起请求
public extension Session {
    @discardableResult
    static func send(_ method: AFHTTPMethod = .post, url: String, parameters: AFParameters = [:], completion: CompletionBlock?) -> Request? {
        self.send(method, url: url, parameters: parameters, success: nil, failure: nil, cancel: nil, completion: completion)
    }

    @discardableResult
    static func send(_ method: AFHTTPMethod = .post, url: String, parameters: AFParameters = [:], success: SuccessBlock?, failure: FailureBlock?, cancel: CancelBlock?) -> Request? {
        self.send(method, url: url, parameters: parameters, success: success, failure: failure, cancel: cancel, completion: nil)
    }

    @discardableResult fileprivate
    static func send(_ method: AFHTTPMethod = .post, url: String, parameters: AFParameters = [:], success: SuccessBlock?, failure: FailureBlock?, cancel: CancelBlock?, completion: CompletionBlock?) -> Request? {
        guard let session = Session.default else { return nil }
        if let request = Request(self.default, method: method, requestUrl: url, parameters: parameters) {
            request.setRequestBlock(success, failure: failure, cancel: cancel, completion: completion)
            DispatchQueue.main.async {
                session.append(requestOf: request)
            }
            return request
        }
        return nil
    }

    @discardableResult
    static func send(_ method: AFHTTPMethod = .post, path: String, parameters: AFParameters = [:], completion: CompletionBlock?) -> Request? {
        self.send(method, path: path, parameters: parameters, success: nil, failure: nil, cancel: nil, completion: completion)
    }

    @discardableResult
    static func send(_ method: AFHTTPMethod = .post, path: String, parameters: AFParameters = [:], success: SuccessBlock?, failure: FailureBlock?, cancel: CancelBlock?) -> Request? {
        self.send(method, path: path, parameters: parameters, success: success, failure: failure, cancel: cancel, completion: nil)
    }

    @discardableResult fileprivate
    static func send(_ method: AFHTTPMethod = .post, path: String, parameters: AFParameters = [:], success: SuccessBlock?, failure: FailureBlock?, cancel: CancelBlock?, completion: CompletionBlock?) -> Request? {
        guard let session = Session.default else { return nil }
        if let request = Request(self.default, method: method, path: path, parameters: parameters) {
            request.setRequestBlock(success, failure: failure, cancel: cancel, completion: completion)
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
