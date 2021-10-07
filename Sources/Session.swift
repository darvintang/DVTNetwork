//
//  Seesion.swift
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
#if canImport(DVTLoger)
    import DVTLoger
#endif

import Foundation

private class SeesionSource {
    var scheme = Scheme.http
    var host = ""
    var baseUrl = ""
}

public protocol SessionInit {
    init?(_ scheme: Scheme?, host: String?, baseUrl: String?)
}

open class Session: SessionInit {
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

    /// 可带端口号的host校验表达式
    public static var hostRegular = "[a-zA-Z0-9][-a-zA-Z0-9]{0,62}(\\.[a-zA-Z0-9][-a-zA-Z0-9]{0,62})+\\.?(:[0-9]{0,6}){0,1}"
    /// url校验表达式
    public static var urlRegular = "^(https|http)://([\\w-]+\\.)+[\\w-]+(:[0-9]{0,6}){0,1}(/[\\w-./?%&=#]*)?$"

    private let source = SeesionSource()

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
                loger.debugLogLevel = self.logLevel
            }
        }
    #endif

    public var cacheTime: TimeInterval

    /// 加密操作
    public var encryptBlock: (_ request: Request?, _ parameters: AFParameters) -> AFParameters

    /// 解密操作，网络请求完成后的原始的字符串，需要自己解析
    public var decryptBlock: (_ request: Request?, _ value: String) -> String

    /// 构造网络请求头的闭包
    public var httpHeaderBlock: (_ request: Request?, _ header: AFHTTPHeaders) -> AFHTTPHeaders

    /// 网络请求结束后，请求状态判断前的操作处理闭包，在这个闭包可以对数据进行提前一步编辑。如果请求成功，在解密操作后执行；如果请求失败不执行解密操作
    public var preOperationCallBack: (_ request: Request?, _ value: Any?, _ error: Error?, _ isCache: Bool) -> (value: Any?, error: Error?)

    // MARK: - 初始化

    public convenience init?(_ baseUrl: String) {
        self.init(nil, host: nil, baseUrl: baseUrl)
    }

    public convenience init?(_ scheme: Scheme, host: String) {
        self.init(scheme, host: host, baseUrl: nil)
    }

    public required init?(_ scheme: Scheme?, host: String?, baseUrl: String?) {
        var isFinishInit = false
        if let tempBaseUrl = baseUrl {
            if Self.getStringType(tempBaseUrl) == .url {
                isFinishInit = true
            }
            assert(isFinishInit, "baseUrl格式不正确")
        } else if let tempScheme = scheme, let tempHost = host {
            if Self.getStringType(tempHost) == .host, tempScheme != .un {
                isFinishInit = true
            }
            assert(isFinishInit, "host或scheme不正确")
        }
        if !isFinishInit {
            return nil
        }

        self.httpHeaderBlock = { $1 }
        self.decryptBlock = { $1 }
        self.encryptBlock = { $1 }
        self.preOperationCallBack = { _, value, error, _ in (value, error) }
        self.afSession = AFSession()
        self.maximumConnectionsPerHost = 10
        self.timeoutInterval = 30.0
        self.queue = DispatchQueue(label: "cn.tcoding.DVTNetwork.manager.\(UUID().uuidString)")
        self.requestsRecord = [:]
        self.afRequestsRecord = [:]

        self.logLevel = .info
        self.cacheTime = 7 * 30 * 360

        if let tempBaseUrl = baseUrl {
            self.baseUrl = tempBaseUrl

        } else if let tempScheme = scheme, let tempHost = host {
            self.scheme = tempScheme
            self.host = tempHost
        }
    }
}

/// 请求管理
public extension Session {
    /// 构造网络请求
    fileprivate func buildCustomUrlRequest(_ request: Request) -> AFDataRequest? {
        var afRequest: AFDataRequest?
        weak var weakRequest = request
        let httpHeader = self.httpHeaderBlock(weakRequest, weakRequest?.headers ?? [:])
        if let tempRequest = request as? UploadRequest {
            afRequest = self.afSession.upload(multipartFormData: { fdata in
                (weakRequest as? UploadRequest)?.multipartFormData(fdata)
            }, to: tempRequest.requestUrl, usingThreshold: UInt64(), method: tempRequest.method, headers: httpHeader).uploadProgress(queue: DispatchQueue.main, closure: { progress in
                (weakRequest as? UploadRequest)?.progressBlock?(progress)
            })
        } else {
            afRequest = self.afSession.request(request.requestUrl, method: request.method, parameters: request.encrypt(), encoding: request.parameterEncoding, headers: httpHeader)
        }

        return afRequest
    }

    fileprivate func success(_ request: Request, value: String, isCache: Bool) {
        let tempValue = request.decrypt(value)
        let (handleValue, handleError) = request.preOperation(tempValue, error: nil, isCache: isCache)
        var resultValue = handleValue

        if let resultType = request.resultType {
            if let value = handleValue as? String {
                resultValue = resultType.init(JSONString: value)
            } else if let value = handleValue as? [String: Any] {
                resultValue = resultType.init(JSON: value)
            }
        }

        if let successBlock = request.successBlock, handleError == nil {
            successBlock(resultValue, isCache)
        }

        if let failureBlock = request.failureBlock, handleError != nil {
            failureBlock(handleError)
        }

        if let completeBlock = request.completedBlock {
            completeBlock(resultValue, handleError, isCache)
        }
    }

    /// 处理请求结果
    fileprivate func handleRequestResult(_ request: Request, result: AFStringDataResponse) {
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

        switch result.result {
        case let .success(resultValue):
            // 在这里可以把结果缓存
            handleRequest.saveCache(resultValue)
            self.success(handleRequest, value: resultValue, isCache: false)

        case let .failure(error):
            let handleError = handleRequest.preOperation(nil, error: error, isCache: false).1
            if let failureBlock = request.failureBlock {
                failureBlock(handleError)
            }
            if let completeBlock = request.completedBlock {
                completeBlock(nil, handleError, false)
            }
        }
        handleRequest.didCompletion(false)
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
        request.willBuild()
        guard let sendRequest = self.buildCustomUrlRequest(request) else {
            return
        }
        request.afRequest = sendRequest
        self.queue.sync { [weak self] in
            if let key = request.identifier, !key.isEmpty {
                self?.requestsRecord[key] = request
                self?.afRequestsRecord[key] = sendRequest
            }
        }
        request.willStart()
        // 在这里读取缓存
        if request.cacheTime > 0, let resultValue = request.cache() {
            self.success(request, value: resultValue, isCache: true)
        }
        sendRequest.validate(statusCode: 200 ..< 300).responseString(encoding: request.resultEncoding) { [weak self] result in
            self?.handleRequestResult(request, result: result)
        }
    }
}

/// 通过单例发起请求
public extension Session {
    @discardableResult static func send(_ method: AFHTTPMethod = .post, url: String, parameters: AFParameters = [:], success successBlock: SuccessBlock? = nil, failure failureBlock: FailureBlock? = nil, completed completedBlock: CompleteBlock? = nil) -> Request? {
        guard let session = Session.default else { return nil }
        if let request = Request(self.default) {
            request.requestUrl = url
            request.method = method
            request.parameters = parameters
            request.setRequestBlock(successBlock, failure: failureBlock, completed: completedBlock)
            DispatchQueue.main.async {
                session.append(requestOf: request)
            }
            return request
        }
        return nil
    }

    @discardableResult static func send(_ method: AFHTTPMethod = .post, path: String, parameters: AFParameters = [:], success successBlock: SuccessBlock? = nil, failure failureBlock: FailureBlock? = nil, completed completedBlock: CompleteBlock? = nil) -> Request? {
        guard let session = Session.default else { return nil }
        if let request = Request(self.default) {
            request.path = path
            request.method = method
            request.parameters = parameters
            request.setRequestBlock(successBlock, failure: failureBlock, completed: completedBlock)
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

    var scheme: Scheme {
        get {
            return self.source.scheme
        }
        set {
            let baseUrl = self.source.baseUrl
            if baseUrl.isEmpty {
                self.source.scheme = newValue
            }
        }
    }

    var host: String {
        get {
            self.source.host
        }
        set {
            var tempValue = newValue

            if tempValue.hasPrefix("https://"), let range = tempValue.range(of: "https://") { tempValue.removeSubrange(range) }
            if tempValue.hasPrefix("http://"), let range = tempValue.range(of: "http://") { tempValue.removeSubrange(range) }

            while tempValue.hasSuffix("/") {
                tempValue.removeLast()
            }

            self.source.host = tempValue
        }
    }
}

public extension Session {
    private(set) var baseUrl: String {
        get {
            let tempBaseUrl = self.source.baseUrl
            return tempBaseUrl.isEmpty ? "\(self.scheme.rawValue)://\(self.host)" : tempBaseUrl
        }
        set {
            var tempValue = newValue
            while tempValue.hasSuffix("/") {
                tempValue.removeLast()
            }
            self.source.baseUrl = tempValue
        }
    }
}

/// 字符串格式校验
public extension Session {
    enum StringType {
        case un
        case host
        case url
    }

    /// 获取字符串的格式类型，url or host
    /// - Parameter string: 要获取格式的字符串
    /// - Returns: 返回字符串格式
    static func getStringType(_ string: String) -> StringType {
        if self.regularEvaluate(string, regular: self.hostRegular) { return .host }
        if self.regularEvaluate(string, regular: self.urlRegular) { return .url }
        return .un
    }

    /// 正则校验字符串
    /// - Parameters:
    ///   - string: 需要校验的字符串
    ///   - regular: 正则表达式
    /// - Returns: 结果
    static func regularEvaluate(_ string: String, regular: String) -> Bool {
        NSPredicate(format: "SELF MATCHES %@", regular).evaluate(with: string)
    }
}
