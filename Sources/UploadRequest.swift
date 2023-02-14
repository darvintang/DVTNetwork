//
//  UploadRequest.swift
//  DVTNetwork
//
//  Created by darvin on 2022/1/2.
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

/// 上传文件
open class UploadRequest: Request {
    // MARK: Lifecycle
    public convenience init?(_ url: String, session: Session? = Session.default,
                             parameterEncoding: AFParameterEncoding = AFJSONEncoding.default, header: AFHTTPHeaders,
                             multipart: @escaping (_ formData: AFMultipartFormData) -> Void,
                             progress: @escaping ProgressBlock) {
        self.init(session, method: .post, parameterEncoding: parameterEncoding, requestURL: url, headers: header)
        self.progress = progress
        self.multipart = multipart
    }

    // MARK: Open
    open private(set) var progress: ProgressBlock?

    open private(set) var multipart: ((_ formData: AFMultipartFormData) -> Void)?

    override open func buildCustomURLRequest(_ afSeeion: AFSession) {
        self.count += 1

        let parameters = self.encrypt()
        var headers = self.session.httpHeaderBlock(self, self.headers)

        if let sign = self.signature(headers, parameters: parameters) {
            headers.add(name: sign.key, value: sign.value)
        }

        self.afRequest = afSeeion.upload(multipartFormData: { [weak self] fdata in
            self?.multipartFormData(fdata)
        }, to: self.requestURL, usingThreshold: UInt64(), method: self.method,
        headers: headers).uploadProgress(queue: DispatchQueue.main,
                                         closure: { [weak self] progress in
                                             self?.progress?(progress)
                                         })
        self.requestHeaders = headers
        self.requestParameters = parameters
    }

    open func multipartFormData(_ formData: AFMultipartFormData) {
        self.multipart?(formData)
    }

    /// 发起请求
    open func start(_ progress: @escaping ProgressBlock, completion: @escaping AnyCompletionBlock) {
        self.progress = progress
        self.start(completion)
    }
}
