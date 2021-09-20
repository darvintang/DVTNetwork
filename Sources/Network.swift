import Alamofire
import Foundation

// 依赖DVTLoger，DVTObjectMapper。如果直接把源码拖到项目中去canImport才有其作用

#if canImport(DVTLoger)
    import DVTLoger
    let loger = Loger("network")
#else
    struct Loger {
        func debug(_ value: Any...) {
        }

        func info(_ value: Any...) {
        }
    }

    let loger = Loger()
#endif

#if canImport(DVTObjectMapper) || canImport(ObjectMapper)
    #if canImport(DVTObjectMapper)
        import DVTObjectMapper
    #else
        import ObjectMapper
    #endif
    public typealias ResultMappable = Mappable
#else
    public protocol DVTMappable {
        init?(JSONString: String)
        init?(JSON: [String: Any])
    }

    public typealias ResultMappable = DVTMappable
    public typealias Map = Any
#endif

/// 网络请求成功的回调
public typealias SuccessBlock = (Any?, Bool) -> Void
/// 网络请求失败的回调
public typealias FailureBlock = (Error?) -> Void
/// 网络请求完成的回调
public typealias CompleteBlock = (Any?, Error?, Bool) -> Void
/// 文件上传下载进度的回调
public typealias ProgressBlock = (Progress) -> Void

public enum Scheme: String {
    case un
    case http
    case https
}

// MARK: - Alamofire的一些类、结构体、协议取别名

public typealias AFSession = Alamofire.Session

public typealias AFRequest = Alamofire.Request
public typealias AFDataRequest = Alamofire.DataRequest
public typealias AFStringDataResponse = Alamofire.AFDataResponse<String>

public typealias AFHTTPMethod = Alamofire.HTTPMethod
public typealias AFHTTPHeaders = Alamofire.HTTPHeaders
public typealias AFParameters = Alamofire.Parameters
public typealias AFMultipartFormData = Alamofire.MultipartFormData

public typealias AFParameterEncoding = Alamofire.ParameterEncoding
public typealias AFJSONEncoding = Alamofire.JSONEncoding
public typealias AFURLEncoding = Alamofire.URLEncoding
