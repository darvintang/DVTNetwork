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

// 依赖DVTLoger，DVTObjectMapper。如果直接把源码拖到项目中去canImport才有其作用

import DVTLoger
public let netLoger = Loger("cn.tcoding.network", logerName: "DVTNetwork")

import DVTObjectMapper
public typealias ResultMappable = Mappable

/// 网络请求成功的回调
public typealias SuccessBlock = (_ result: Any?, _ isCache: Bool) -> Void
/// 网络请求失败的回调
public typealias FailureBlock = (_ error: Error?) -> Void
/// 网络请求完成的回调，如果是请求被取消，result和error都是nil
public typealias CompletionBlock = (_ result: Any?, _ error: Error?, _ isCache: Bool) -> Void
/// 文件上传下载进度的回调
public typealias ProgressBlock = (_ progress: Progress) -> Void
/// 网络请求被取消的回调
public typealias CancelBlock = () -> Void
/// 是否忽略本次结果，如果忽略就不会走请求结果的闭包 ignore
public typealias OperationCallBack = (_ request: Request?, _ value: Any?, _ error: Error?, _ isCache: Bool) -> (ignore: Bool, value: Any?, error: Error?)

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
