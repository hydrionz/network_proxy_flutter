import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:network_proxy/network/bin/configuration.dart';
import 'package:network_proxy/network/http/http.dart';
import 'package:network_proxy/network/util/request_rewrite.dart';
import 'package:network_proxy/ui/component/json/json_viewer.dart';
import 'package:network_proxy/ui/component/json/theme.dart';
import 'package:network_proxy/ui/component/utils.dart';
import 'package:network_proxy/ui/desktop/toolbar/setting/request_rewrite.dart';
import 'package:network_proxy/ui/mobile/setting/request_rewrite.dart';
import 'package:network_proxy/utils/num.dart';
import 'package:network_proxy/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

import '../component/json/json_text.dart';

class HttpBodyWidget extends StatefulWidget {
  final HttpMessage? httpMessage;
  final bool inNewWindow; //是否在新窗口打开
  final WindowController? windowController;
  final ScrollController? scrollController;

  const HttpBodyWidget(
      {super.key, required this.httpMessage, this.inNewWindow = false, this.windowController, this.scrollController});

  @override
  State<StatefulWidget> createState() {
    return HttpBodyState();
  }
}

class HttpBodyState extends State<HttpBodyWidget> {
  var bodyKey = GlobalKey<_BodyState>();
  int tabIndex = 0;

  @override
  void initState() {
    super.initState();
    RawKeyboard.instance.addListener(onKeyEvent);
  }

  /// 按键事件
  void onKeyEvent(RawKeyEvent event) {
    if ((event.isKeyPressed(LogicalKeyboardKey.metaLeft) || event.isControlPressed) &&
        event.isKeyPressed(LogicalKeyboardKey.keyW)) {
      RawKeyboard.instance.removeListener(onKeyEvent);
      widget.windowController?.close();
      return;
    }
  }

  @override
  void dispose() {
    RawKeyboard.instance.removeListener(onKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.httpMessage?.body == null || widget.httpMessage?.body?.isEmpty == true) {
      return const SizedBox();
    }

    var tabs = Tabs.of(widget.httpMessage?.contentType);

    if (tabIndex >= tabs.list.length) tabIndex = tabs.list.length - 1;
    bodyKey.currentState?.changeState(widget.httpMessage, tabs.list[tabIndex]);

    List<Widget> list = [
      widget.inNewWindow ? const SizedBox() : titleWidget(),
      TabBar(
          labelPadding: const EdgeInsets.symmetric(horizontal: 2.0),
          tabs: tabs.tabList(),
          onTap: (index) {
            tabIndex = index;
            bodyKey.currentState?.changeState(widget.httpMessage, tabs.list[tabIndex]);
          }),
      Padding(
          padding: const EdgeInsets.all(10),
          child: _Body(
              key: bodyKey,
              message: widget.httpMessage,
              viewType: tabs.list[tabIndex],
              scrollController: widget.scrollController)) //body
    ];

    var tabController = DefaultTabController(
        initialIndex: tabIndex,
        length: tabs.list.length,
        child: widget.inNewWindow
            ? ListView(children: list)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: list));

    if (widget.inNewWindow) {
      return Scaffold(
          appBar: AppBar(title: titleWidget(inNewWindow: true), toolbarHeight: Platform.isWindows ? 36 : null),
          body: tabController);
    }
    return tabController;
  }

  /// 标题
  Widget titleWidget({inNewWindow = false}) {
    var type = widget.httpMessage is HttpRequest ? "Request" : "Response";

    var list = [
      Text('$type Body', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      const SizedBox(width: 15),
      IconButton(
          icon: const Icon(Icons.copy),
          tooltip: '复制',
          onPressed: () {
            var body = bodyKey.currentState?.body;
            if (body == null) {
              return;
            }
            Clipboard.setData(ClipboardData(text: body)).then((value) => FlutterToastr.show("已复制到剪切板", context));
          }),
    ];

    if (!inNewWindow || Platforms.isMobile()) {
      list.add(const SizedBox(width: 5));
      list.add(IconButton(
          icon: const Icon(Icons.edit_document),
          tooltip: '请求重写',
          onPressed: () {
            HttpRequest? request;
            if (widget.httpMessage is HttpRequest) {
              request = widget.httpMessage as HttpRequest;
            } else {
              request = (widget.httpMessage as HttpResponse).request;
            }

            var body = bodyKey.currentState?.body;
            var rule = RequestRewriteRule(true, request?.path() ?? '', request?.remoteDomain(),
                requestBody: widget.httpMessage is HttpRequest ? body : null,
                responseBody: widget.httpMessage is HttpResponse ? body : null);

            if (Platforms.isMobile()) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => RewriteRule(rule: rule))).then((value) {
                if (value is RequestRewriteRule) {
                  Configuration.instance.then((it) => it.flushRequestRewriteConfig());
                }
              });
            } else {
              showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) => RuleAddDialog(rule: rule)).then((value) {
                if (value != null) {
                  Configuration.instance.then((it) => it.flushRequestRewriteConfig());
                  FlutterToastr.show("添加请求重写规则成功", context);
                }
              });
            }
          }));
    }

    if (!inNewWindow) {
      list.add(const SizedBox(width: 5));
      list.add(IconButton(icon: const Icon(Icons.open_in_new), tooltip: '新窗口打开', onPressed: () => openNew()));
    }

    return Row(
      mainAxisAlignment: widget.inNewWindow ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: list,
    );
  }

  void openNew() async {
    if (Platforms.isDesktop()) {
      var size = MediaQuery.of(context).size;
      var ratio = 1.0;
      if (Platform.isWindows) {
        ratio = WindowManager.instance.getDevicePixelRatio();
      }
      final window = await DesktopMultiWindow.createWindow(jsonEncode(
        {'name': 'HttpBodyWidget', 'httpMessage': widget.httpMessage, 'inNewWindow': true},
      ));
      window
        ..setTitle(widget.httpMessage is HttpRequest ? '请求体' : '响应体')
        ..setFrame(const Offset(100, 100) & Size(800 * ratio, size.height * ratio))
        ..center()
        ..show();
      return;
    }

    Navigator.push(
        context, MaterialPageRoute(builder: (_) => HttpBodyWidget(httpMessage: widget.httpMessage, inNewWindow: true)));
  }
}

class _Body extends StatefulWidget {
  final HttpMessage? message;
  final ViewType viewType;
  final ScrollController? scrollController;

  const _Body({super.key, this.message, required this.viewType, this.scrollController});

  @override
  State<StatefulWidget> createState() {
    return _BodyState();
  }
}

class _BodyState extends State<_Body> {
  late ViewType viewType;
  HttpMessage? message;

  @override
  void initState() {
    super.initState();
    viewType = widget.viewType;
    message = widget.message;
  }

  changeState(HttpMessage? message, ViewType viewType) {
    setState(() {
      this.message = message;
      this.viewType = viewType;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _getBody(viewType);
  }

  String? get body {
    if (message == null || message?.body == null) {
      return null;
    }

    if (viewType == ViewType.hex) {
      return message!.body!.map(intToHex).join(" ");
    }
    try {
      if (viewType == ViewType.formUrl) {
        return Uri.decodeFull(message!.bodyAsString);
      }
      if (viewType == ViewType.jsonText || viewType == ViewType.json) {
        //json格式化
        var jsonObject = json.decode(message!.bodyAsString);
        return const JsonEncoder.withIndent("  ").convert(jsonObject);
      }
    } catch (_) {}
    return message!.bodyAsString;
  }

  Widget _getBody(ViewType type) {
    if (message == null || message?.body == null) {
      return const SizedBox();
    }

    try {
      if (type == ViewType.jsonText) {
        var jsonObject = json.decode(message!.bodyAsString);
        return JsonText(
            json: jsonObject,
            colorTheme: ColorTheme.of(Theme.of(context).brightness),
            scrollController: widget.scrollController);
      }

      if (type == ViewType.json) {
        return JsonViewer(json.decode(message!.bodyAsString), colorTheme: ColorTheme.of(Theme.of(context).brightness));
      }

      if (type == ViewType.formUrl) {
        return SelectableText(Uri.decodeFull(message!.bodyAsString), contextMenuBuilder: contextMenu);
      }
      if (type == ViewType.image) {
        return Image.memory(Uint8List.fromList(message?.body ?? []), fit: BoxFit.none);
      }
      if (type == ViewType.hex) {
        return SelectableText(message!.body!.map(intToHex).join(" "), contextMenuBuilder: contextMenu);
      }
    } catch (e) {
      // ignore: avoid_print
      print(e);
    }

    return SelectableText.rich(TextSpan(text: message?.bodyAsString), contextMenuBuilder: contextMenu);
  }
}

class Tabs {
  final List<ViewType> list = [];

  static Tabs of(ContentType? contentType) {
    var tabs = Tabs();
    if (contentType == null) {
      return tabs;
    }

    if (contentType == ContentType.json) {
      tabs.list.add(ViewType.jsonText);
    }

    tabs.list.add(ViewType.of(contentType) ?? ViewType.text);

    if (contentType == ContentType.text) {
      tabs.list.add(ViewType.jsonText);
    }
    if (contentType == ContentType.formUrl || contentType == ContentType.json) {
      tabs.list.add(ViewType.text);
    }

    tabs.list.add(ViewType.hex);
    return tabs;
  }

  List<Tab> tabList() {
    return list.map((e) => Tab(child: Text(e.title))).toList();
  }
}

enum ViewType {
  text("Text"),
  formUrl("URL 解码"),
  json("JSON"),
  jsonText("JSON Text"),
  html("HTML"),
  image("Image"),
  css("CSS"),
  js("JavaScript"),
  hex("Hex"),
  ;

  final String title;

  const ViewType(this.title);

  static ViewType? of(ContentType contentType) {
    for (var value in values) {
      if (value.name == contentType.name) {
        return value;
      }
    }
    return null;
  }
}
