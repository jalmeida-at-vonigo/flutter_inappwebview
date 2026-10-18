//
//  CustomSchemeHandler.swift
//  flutter_inappwebview
//
//  Created by Lorenzo Pichilli on 25/10/2019.
//

import Flutter
import Foundation
import WebKit

@available(iOS 11.0, *)
public class CustomSchemeHandler: NSObject, WKURLSchemeHandler {
    var schemeHandlers: [Int: WKURLSchemeTask] = [:]
    
    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        // answer CORS preflight requests natively, without involving the Dart side
        if urlSchemeTask.request.httpMethod?.uppercased() == "OPTIONS" {
            var headerFields = CustomSchemeHandler.corsHeaderFields(for: urlSchemeTask.request)
            headerFields["Access-Control-Allow-Methods"] = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
            headerFields["Access-Control-Allow-Headers"] = urlSchemeTask.request.value(forHTTPHeaderField: "Access-Control-Request-Headers") ?? "*"
            headerFields["Access-Control-Max-Age"] = "600"
            headerFields["Content-Length"] = "0"
            if let url = urlSchemeTask.request.url,
               let urlResponse = HTTPURLResponse(url: url, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: headerFields) {
                urlSchemeTask.didReceive(urlResponse)
                urlSchemeTask.didFinish()
                return
            }
        }
        
        schemeHandlers[urlSchemeTask.hash] = urlSchemeTask
        let inAppWebView = webView as! InAppWebView
        let request = WebResourceRequest.init(fromURLRequest: urlSchemeTask.request)
        let callback = WebViewChannelDelegate.LoadResourceWithCustomSchemeCallback()
        callback.nonNullSuccess = { (response: CustomSchemeResponse) in
            if (self.schemeHandlers[urlSchemeTask.hash] != nil) {
                var headerFields = CustomSchemeHandler.corsHeaderFields(for: urlSchemeTask.request)
                headerFields["Content-Type"] = response.contentType
                headerFields["Content-Length"] = String(response.data.count)
                let urlResponse = HTTPURLResponse(
                    url: request.url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: headerFields
                ) ?? URLResponse(
                    url: request.url,
                    mimeType: response.contentType,
                    expectedContentLength: response.data.count,
                    textEncodingName: response.contentEncoding
                )
                urlSchemeTask.didReceive(urlResponse)
                urlSchemeTask.didReceive(response.data)
                urlSchemeTask.didFinish()
                self.schemeHandlers.removeValue(forKey: urlSchemeTask.hash)
            }
            return false
        }
        callback.error = { (code: String, message: String?, details: Any?) in
            print(code + ", " + (message ?? ""))
        }
        
        if let channelDelegate = inAppWebView.channelDelegate {
            channelDelegate.onLoadResourceWithCustomScheme(request: request, callback: callback)
        } else {
            callback.defaultBehaviour(nil)
        }
    }
    
    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        schemeHandlers.removeValue(forKey: urlSchemeTask.hash)
    }
    
    /// Allows cross-origin access (fetch/XHR) to custom scheme resources.
    /// The request Origin is echoed back instead of "*", because "*" is rejected for credentialed requests.
    static func corsHeaderFields(for request: URLRequest) -> [String: String] {
        guard let origin = request.value(forHTTPHeaderField: "Origin") else {
            return ["Access-Control-Allow-Origin": "*"]
        }
        return [
            "Access-Control-Allow-Origin": origin,
            "Access-Control-Allow-Credentials": "true",
            "Access-Control-Expose-Headers": "*",
            "Vary": "Origin"
        ]
    }
}
