//
//  Network.swift
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

import Alamofire
import Foundation

import DVTLoger

public var NetLoger: Loger = {
    Loger("cn.tcoding.network", logerName: "DVTNetwork")
}()

public enum ResultStatus<R, E: Error> {
    case success(result: R, isCache: Bool), failure(error: E), cancel
}

public extension ResultStatus {
    var isCancel: Bool {
        if case .cancel = self {
            return true
        }
        return false
    }

    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var isCache: Bool {
        if case let .success(_, isCancel) = self {
            return isCancel
        }
        return false
    }

    var isFailure: Bool {
        if case .failure = self {
            return true
        }
        return false
    }

    var success: R? {
        guard case let .success(value, _) = self else { return nil }
        return value
    }

    var failure: E? {
        guard case let .failure(error) = self else { return nil }
        return error
    }

    /// 类型转换，请确保数据类型正确
    func to<T>(_ type: T.Type) -> ResultStatus<T, Error> {
        switch self {
            case let .success(result, isCache):
                if let res = result as? T {
                    return .success(result: res, isCache: isCache)
                } else {
                    return .failure(error: NSError(domain: "数据类型转换失败", code: 9999, userInfo: nil))
                }
            case let .failure(error):
                return .failure(error: error)
            case .cancel:
                return .cancel
        }
    }
}

public typealias HttpHeaderBlock = (_ request: Request?, _ header: AFHTTPHeaders) -> AFHTTPHeaders

public typealias CompletionBlock<T> = (_ result: ResultStatus<T, Error>) -> Void

public typealias AnyCompletionBlock = CompletionBlock<Any>

/// 文件上传下载进度的回调
public typealias ProgressBlock = (_ progress: Progress) -> Void
/// 是否忽略本次结果，如果忽略就不会走请求结果的闭包， 返回空
public typealias OperationCallBackBlock = (_ request: Request, _ result: Any?, _ error: Error?, _ isCache: Bool) -> (result: Any?, error: Error?)?

public enum Scheme: String {
    case un
    case http
    case https
}

// MARK: - Alamofire的一些类、结构体、协议取别名

public typealias AFSession = Alamofire.Session

public typealias AFRequest = Alamofire.Request
public typealias AFDataRequest = Alamofire.DataRequest
public typealias AFDataResponse = Alamofire.DataResponse
public typealias AFStringDataResponse = Alamofire.AFDataResponse<String>

public typealias AFError = Alamofire.AFError

public typealias AFHTTPMethod = Alamofire.HTTPMethod
public typealias AFHTTPHeaders = Alamofire.HTTPHeaders
public typealias AFParameters = Alamofire.Parameters
public typealias AFMultipartFormData = Alamofire.MultipartFormData

public typealias AFParameterEncoding = Alamofire.ParameterEncoding
public typealias AFJSONEncoding = Alamofire.JSONEncoding
public typealias AFURLEncoding = Alamofire.URLEncoding

public typealias AFNetworkReachabilityManager = Alamofire.NetworkReachabilityManager
public typealias AFNetworkReachabilityStatus = AFNetworkReachabilityManager.NetworkReachabilityStatus
