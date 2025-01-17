import 'dart:convert';
import 'dart:io';

import 'package:network_proxy/network/host_port.dart';
import 'package:network_proxy/network/http/http.dart';
import 'package:network_proxy/network/http/http_headers.dart';

class Har {
  static int maxBodyLength = 1024 * 1024 * 4;

  static List<Map> _entries(List<HttpRequest> list) {
    return list.map((e) => toHar(e)).toList();
  }

  static Map toHar(HttpRequest request) {
    bool isImage = request.response?.contentType == ContentType.image;
    Map har = {
      "startedDateTime": request.requestTime.toUtc().toIso8601String(), // 请求发出的时间(ISO 8601)
      "time": request.response?.responseTime.difference(request.requestTime).inMilliseconds,
      "pageref": "ProxyPin", // 页面标识
      "request": {
        "method": request.method.name, // 请求方法
        "url": request.requestUrl, // 请求地址
        "httpVersion": request.protocolVersion, // HTTP协议版本
        "cookies": [], // 请求携带的cookie
        "headers": _headers(request), // 请求头
        "queryString": [], // 请求参数
        "postData": _getPostData(request), // 请求体
        "headersSize": -1, // 请求头大小
        "bodySize": request.body?.length ?? -1, // 请求体大小
      },
      "cache": {},
      'timings': {
        'send': 0,
        'wait': request.response?.responseTime.difference(request.requestTime).inMilliseconds,
        'receive': 0,
      },
      'serverIPAddress': request.response?.remoteAddress
    };

    //body已经解码 删除编码
    if (request.response?.headers.contentEncoding == 'br') {
      request.response?.headers.remove(HttpHeaders.CONTENT_ENCODING);
    }
    har['response'] = {
      "status": request.response?.status.code ?? 0, // 响应状态码
      "statusText": request.response?.status.reasonPhrase ?? '', // 响应状态码描述
      "httpVersion": request.response?.protocolVersion ?? 'HTTP/1.1', // HTTP协议版本
      "cookies": [], // 响应携带的cookie
      "headers": _headers(request.response), // 响应头
      "content": {
        "size": isImage ? 0 : request.response?.body?.length ?? -1, // 响应体大小
        "mimeType": _getContentType(request.response?.headers.contentType), // 响应体类型
        "text": isImage ? '' : request.response?.bodyAsString, // 响应体内容
      },
      "redirectURL": '', // 重定向地址
      "headersSize": -1, // 响应头大小
      "bodySize": isImage ? -1 : request.response?.body?.length ?? -1, // 响应体大小
    };
    return har;
  }

  static Future<String> writeJson(List<HttpRequest> list, {String title = ''}) async {
    var entries = _entries(list);
    Map har = {};
    title = title.contains("ProxyPin") ? title : "[ProxyPin]$title";
    har["log"] = {
      "version": "1.2",
      "creator": {"name": "ProxyPin", "version": "1.0.8"},
      "pages": [
        {
          "title": title,
          "id": "ProxyPin",
          "startedDateTime": list.firstOrNull?.requestTime.toUtc().toIso8601String(),
          "pageTimings": {"onContentLoad": -1, "onLoad": -1}
        }
      ],
      "entries": entries,
    };
    return jsonEncode(har);
  }

  static Future<File> writeFile(List<HttpRequest> list, File file, {String title = ''}) async {
    var json = await writeJson(list, title: title);
    return file.writeAsString(json);
  }

  //读取文件
  static Future<List<HttpRequest>> readFile(File file) async {
    var lines = await file.readAsLines();
    List<HttpRequest> list = [];

    for (var value in lines) {
      var har = jsonDecode(value.substring(0, value.length - 1));
      var request = toRequest(har);
      list.add(request);
    }
    return list;
  }

  static List<Map> _headers(HttpMessage? message) {
    var headers = <Map<String, String>>[];
    message?.headers.forEach((name, values) {
      for (var element in values) {
        headers.add({'name': name, 'value': element});
      }
    });
    return headers;
  }

  /// har to request
  static HttpRequest toRequest(Map har) {
    var request = har['request'];
    var method = request['method'];
    List headers = request['headers'];

    var httpRequest = HttpRequest(HttpMethod.valueOf(method), request['url'], protocolVersion: request['httpVersion']);
    httpRequest.body = request['postData']?['text']?.toString().codeUnits;
    for (var element in headers) {
      httpRequest.headers.add(element['name'], element['value']);
    }
    var response = har['response'];
    HttpResponse? httpResponse;
    if (response != null && response['status'] != null) {
      httpResponse = HttpResponse(HttpStatus.newStatus(response['status'], response['statusText']),
          protocolVersion: response['httpVersion']);
      httpResponse.body = response['content']['text']?.toString().codeUnits;
      List responseHeaders = response['headers'];
      for (var element in responseHeaders) {
        httpResponse.headers.add(element['name'], element['value']);
      }
    }

    httpRequest.response = httpResponse;
    httpResponse?.request = httpRequest;
    httpRequest.hostAndPort = HostAndPort.of(httpRequest.requestUrl);
    //请求时间
    if (har['startedDateTime'] != null) {
      httpRequest.requestTime = DateTime.parse(har['startedDateTime']).toLocal();
    }
    if (har['time'] != null) {
      httpRequest.response?.responseTime =
          httpRequest.requestTime.add(Duration(milliseconds: double.parse(har['time'].toString()).toInt()));
    }
    return httpRequest;
  }

  static Map<String, dynamic> _getPostData(HttpRequest request) {
    if (request.contentType == ContentType.formData || request.contentType == ContentType.formUrl) {
      return {
        "mimeType": request.headers.contentType, // 请求体类型
        "text": request.bodyAsString, // 请求体内容
        "params": [], // 请求体内容
      };
    }
    return {
      "mimeType": request.headers.contentType, // 请求体类型
      "text": request.bodyAsString, // 请求体内容
    };
  }

  //获取contentType
  static String? _getContentType(String? type) {
    if (type == null) {
      return '';
    }
    var indexOf = type.indexOf("charset=");
    if (indexOf == -1) {
      return type;
    }
    var contentType = type.substring(0, indexOf).trimRight();
    if (contentType.endsWith(";")) {
      return contentType.substring(0, contentType.length - 1);
    }
    return contentType;
  }
}
