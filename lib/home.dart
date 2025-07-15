import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  TextEditingController textEditingController = TextEditingController();
  Map data = {};
  bool checkId = false;
  bool isLoading = false;

  void covertLinkTT() async {
    final url = textEditingController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      isLoading = true;
    });

    final Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      showError();
      return;
    }

    if (uri.host.contains('vt.tiktok.com')) {
      await resolveTikTokShortUrlWithWebView(
        context,
        url,
        (videoId) async {
          await getData(videoId);
        },
        () {
          showError();
        },
      );
    } else if (uri.path.contains('/video/')) {
      final match = RegExp(r'/video/(\d+)').firstMatch(url);
      if (match != null) {
        final videoId = match.group(1)!;
        await getData(videoId);
      } else {
        showError();
      }
    } else {
      showError();
    }
  }

  void showError() {
    setState(() {
      checkId = false;
      isLoading = false;
    });
  }

  Future<void> getData(String videoId) async {
    setState(() {
      isLoading = true;
    });
    try {
      final response = await Dio().get(
        "https://www.tiktok.com/oembed",
        queryParameters: {
          'url': 'https://www.tiktok.com/@tiktok/video/$videoId',
          'format': 'json',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          data = response.data;
          checkId = true;
          isLoading = false;
        });
      } else {
        setState(() {
          checkId = false;
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        checkId = false;
        isLoading = false;
      });
    }
  }

  Future<void> resolveTikTokShortUrlWithWebView(
    BuildContext context,
    String shortUrl,
    void Function(String videoId) onResolved,
    void Function()? onError,
  ) async {
    final controller = WebViewController();
    bool resolved = false;

    final webView = WebViewWidget(
      controller: controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              if (!resolved && url.contains('/video/')) {
                final match = RegExp(r'/video/(\d+)').firstMatch(url);
                if (match != null) {
                  resolved = true;
                  final videoId = match.group(1)!;
                  Navigator.of(context).pop();
                  onResolved(videoId);
                }
              }
            },
            onWebResourceError: (_) {
              if (!resolved) {
                resolved = true;
                Navigator.of(context).pop();
                onError?.call();
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(shortUrl)),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        child: SizedBox(
          width: 0,
          height: 0,
          child: webView,
        ),
      ),
    );
  }

  Future<Map?> downloadImage(String imageUrl, String fileName) async {
    try {
      if (await Permission.storage.request().isDenied) {
        print("Không có quyền truy cập bộ nhớ");
        return null;
      }
      // Android 11 top hight (API 30+):
      if (Platform.isAndroid &&
          (await Permission.manageExternalStorage.status.isDenied)) {
        final status = await Permission.manageExternalStorage.request();
        if (status.isDenied || status.isPermanentlyDenied) {
          print("Không có quyền quản lý bộ nhớ ngoài");
          return null;
        }
      }
      final dio = Dio();
      final response = await dio.get<List<int>>(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      final Uint8List imageBytes = Uint8List.fromList(response.data!);

      final result = await ImageGallerySaverPlus.saveImage(
        imageBytes,
        name: fileName,
      );

      return result;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(top: 30, left: 20, right: 20),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: TextField(
                  controller: textEditingController,
                  decoration:
                      const InputDecoration(hintText: "Nhập link TikTok"),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  covertLinkTT();
                },
                child: const Text("Lấy dữ liệu"),
              ),
              const SizedBox(height: 30),
              if (isLoading) const CircularProgressIndicator(),
              if (!isLoading && checkId)
                Column(
                  children: [
                    Text(data['title'].toString()),
                    const SizedBox(height: 10),
                    Image.network(
                      data['thumbnail_url'],
                      height: 200,
                      width: 200,
                      fit: BoxFit.cover,
                    ),
                    data['thumbnail_url'] != null
                        ? ElevatedButton(
                            onPressed: () async {
                              try {
                                final result = await downloadImage(
                                    data['thumbnail_url'], data['title']);
                                if (!context.mounted) return;

                                final isSuccess = result?['isSuccess'] == true;
                                final filePath = result?['filePath'] ?? "";

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isSuccess
                                          ? "Tải thành công! $filePath"
                                          : "Có lỗi, vui lòng thử lại!",
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Lỗi khi tải ảnh."),
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text("Tải ảnh về"),
                          )
                        : const SizedBox(),
                  ],
                ),
              if (!isLoading && !checkId)
                const Text("Không tìm thấy video hợp lệ."),
            ],
          ),
        ),
      ),
    );
  }
}
